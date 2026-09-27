unit csharp_abi_call_generator_tool;


// csharp_abi_call_generator_tool - LingoFuse ABI Call-Side Generator
// for C# (rebuild edition).
//
// This unit consumes a TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI)
// and produces a single C# source file that speaks the LingoFuse ABI
// wire protocol.
//
// Unlike the legacy generator, this rebuild edition does NOT re-declare
// the P/Invoke layer, the serialization helpers, or the exception
// hierarchy. It builds directly on top of the rebuilt LingoFuse C#
// interface (namespace `LingoFuse`), whose public types are:
//
//   Framework           - process-wide ABI facade.
//   DataHandle          - RAII wrapper over the native data buffer.
//   LfIo                - unified JSON / string I/O.
//   LingoFuseCallException - remote call failure exception.
//   LingoFuseException  - base exception type.
//
// The generated file exposes:
//
//   WireStatus      - ABI status byte constants (0x00 = OK, 0xFF = error).
//   ABI             - one typed static method per routine, plus the
//                     TargetApp / Timeout configuration fields.
//
// The generated file is a pure CLASS LIBRARY. It does NOT declare a
// `Program` class or a `Main` entry point. The entry point is provided
// either by the user's own application or by the paired test program
// emitted by csharp_abi_test_generator_tool.
//
// Wire protocol (matches every other backend):
//   request  = [field1][field2]...[fieldN]
//   response = [status:byte][payload]
//     status = 0x00 -> success; payload is the serialized result
//                      (functions) or empty (procedures).
//     status = 0xFF -> error; payload is a UTF-8 string message
//                      terminated by a NUL byte.
//
// Type mapping (mirrors every other backend):
//   integer / longint             -> int    / ReadInt32    / WriteInt32
//   int64                         -> long   / ReadInt64    / WriteInt64
//   cardinal / dword / longword   -> uint   / ReadUInt32   / WriteUInt32
//   word                          -> ushort / ReadUInt16   / WriteUInt16
//   smallint                      -> short  / ReadInt16    / WriteInt16
//   byte                          -> byte   / ReadUInt8    / WriteUInt8
//   uint64                        -> ulong  / ReadUInt64   / WriteUInt64
//   double / extended / real      -> double / ReadDouble   / WriteDouble
//   single                        -> float  / ReadSingle   / WriteSingle
//   string / PChar family         -> string / ReadString   / WriteString
//
// All comments and status output are in English.
//
// Author: LingoFuse-pasAgent project

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;


  // GenerateABICallCsharpCode - generate the C# call-side module.
  //
  // The returned list contains the lines of a .cs file that declares
  // the ABI class and its typed methods. The file has NO Main entry
  // point; it is meant to be compiled as a library alongside a host
  // program or a test program. The caller owns the list and must
  // release it with DisposeObject.

function GenerateABICallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICallCsharpReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// call-side type mapping, and every exported method. The document is
// written so that both human readers and AI assistants can learn the
// call-side module's usage model from the README alone.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABICallCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation


// -----------------------------------------------------------------------------
// Logging helpers
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;


// -----------------------------------------------------------------------------
// ABI type mapping
// -----------------------------------------------------------------------------

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or
    T.Same('unicodestring') or T.Same('tpascalstring') or
    T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

// C# type used in signatures.
function ABI_Type_To_CSharp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'uint'
  else if T.Same('word') then
    Result := 'ushort'
  else if T.Same('smallint') then
    Result := 'short'
  else if T.Same('byte') then
    Result := 'byte'
  else if T.Same('uint64') then
    Result := 'ulong'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'string'
  else
    Result := '';
end;

// DataHandle writer method name for the given ABI type (without the
// "param." receiver and without the argument list).
function ABI_Type_To_CSharp_Writer_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'WriteInt32'
  else if T.Same('int64') then Result := 'WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'WriteUInt32'
  else if T.Same('word') then Result := 'WriteUInt16'
  else if T.Same('smallint') then Result := 'WriteInt16'
  else if T.Same('byte') then Result := 'WriteUInt8'
  else if T.Same('uint64') then Result := 'WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'WriteDouble'
  else if T.Same('single') then Result := 'WriteSingle'
  else if IsStringABIType(T) then Result := 'WriteString'
  else
    Result := '';
end;

// DataHandle reader method name for the given ABI type (without the
// "response." receiver).
function ABI_Type_To_CSharp_Reader_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'ReadInt32'
  else if T.Same('int64') then Result := 'ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'ReadUInt32'
  else if T.Same('word') then Result := 'ReadUInt16'
  else if T.Same('smallint') then Result := 'ReadInt16'
  else if T.Same('byte') then Result := 'ReadUInt8'
  else if T.Same('uint64') then Result := 'ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'ReadDouble'
  else if T.Same('single') then Result := 'ReadSingle'
  else if IsStringABIType(T) then Result := 'ReadString'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_CSharp_Decl(T) <> '';
end;


// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsCSharpKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('base') or
    S.Same('bool') or S.Same('break') or S.Same('byte') or
    S.Same('case') or S.Same('catch') or S.Same('char') or
    S.Same('checked') or S.Same('class') or S.Same('const') or
    S.Same('continue') or S.Same('decimal') or S.Same('default') or
    S.Same('delegate') or S.Same('do') or S.Same('double') or
    S.Same('else') or S.Same('enum') or S.Same('event') or
    S.Same('explicit') or S.Same('extern') or S.Same('false') or
    S.Same('finally') or S.Same('fixed') or S.Same('float') or
    S.Same('for') or S.Same('foreach') or S.Same('goto') or
    S.Same('if') or S.Same('implicit') or S.Same('in') or
    S.Same('int') or S.Same('interface') or S.Same('internal') or
    S.Same('is') or S.Same('lock') or S.Same('long') or
    S.Same('namespace') or S.Same('new') or S.Same('null') or
    S.Same('object') or S.Same('operator') or S.Same('out') or
    S.Same('override') or S.Same('params') or S.Same('private') or
    S.Same('protected') or S.Same('public') or S.Same('readonly') or
    S.Same('ref') or S.Same('return') or S.Same('sbyte') or
    S.Same('sealed') or S.Same('short') or S.Same('sizeof') or
    S.Same('stackalloc') or S.Same('static') or S.Same('string') or
    S.Same('struct') or S.Same('switch') or S.Same('this') or
    S.Same('throw') or S.Same('true') or S.Same('try') or
    S.Same('typeof') or S.Same('uint') or S.Same('ulong') or
    S.Same('unchecked') or S.Same('unsafe') or S.Same('ushort') or
    S.Same('using') or S.Same('virtual') or S.Same('void') or
    S.Same('volatile') or S.Same('while');
end;

function MakeSafeCSharpParamName(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'p' + umlIntToStr(Index);
    Exit;
  end;

  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if IsCSharpKeyword(Result) then
    Result := Result + '_';
end;


// -----------------------------------------------------------------------------
// C# string literal helper
// -----------------------------------------------------------------------------

function CSharpStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
    begin
      Result.Append('\');
      Result.Append('"');
    end
    else if c = '\' then
    begin
      Result.Append('\');
      Result.Append('\');
    end
    else if c = #10 then
    begin
      Result.Append('\');
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append('\');
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append('\');
      Result.Append('t');
    end
    else if c = #0 then
    begin
      Result.Append('\');
      Result.Append('0');
    end
    else
      Result.Append(c);
  end;
  Result.Append('"');
end;


// -----------------------------------------------------------------------------
// Comment description extraction
// -----------------------------------------------------------------------------

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);

  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);

  if T.Len > 0 then
  begin
    if T[1] = '{' then
      T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;

  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then
      T := T.GetString(1, T.Len).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then
      T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
  end;

  Result := T;
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var
  i, j: integer;
  Line: TP_String;
begin
  Result := '';
  if Comment.Len = 0 then
    Exit;

  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do
      Inc(j);

    if j > i then
    begin
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);

      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
          // Skip Doxygen tag lines.
        end
        else
        begin
          if Line[1] = '*' then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);

          if Line.Len > 0 then
          begin
            Result := Line;
            if Result.Len > 200 then
              Result := Result.GetString(1, 201);
            Exit;
          end;
        end;
      end;
    end;

    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
end;


// -----------------------------------------------------------------------------
// Parameter helpers
// -----------------------------------------------------------------------------

function BuildCSharpParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCSharpParamName(Params[i].Name, i);
    PTyp := ABI_Type_To_CSharp_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PTyp + ' ' + PName;
  end;
end;


// -----------------------------------------------------------------------------
// Supported-function filtering
// -----------------------------------------------------------------------------

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(f.Params) do
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: routine with empty Name');
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;


// =============================================================================
// GenerateABICallCsharpCode
// =============================================================================

function GenerateABICallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, TargetAppName, CsFileName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, ParamDecl, RetType: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  PName, PTyp, WriterMethod, ReaderMethod: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  // The call-side namespace deliberately differs from the service-side
  // namespace (`<unit>_abi`) so that both files can live side by side
  // in the same C# project without symbol collisions.
  NsName := NormalizedUnit + '_abi_call';
  TargetAppName := NormalizedUnit + '_abi';
  CsFileName := NormalizedUnit + '_abi_call.cs';

  Log(PFormat('Generating C# ABI call module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    // =========================================================================
    // 1. File header
    // =========================================================================
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by csharp_abi_call_generator_tool (rebuild edition).');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (both directions):');
    Lines.Add('//   request  = [field1][field2]...[fieldN]');
    Lines.Add('//   response = [status:byte][payload]');
    Lines.Add('//     status = 0x00 -> success; payload is the serialized result');
    Lines.Add('//                      (functions) or empty (procedures).');
    Lines.Add('//     status = 0xFF -> error; payload is a UTF-8 string message');
    Lines.Add('//                      terminated by a NUL byte.');
    Lines.Add('//');
    Lines.Add('// Every integer and float is little-endian. Every string is');
    Lines.Add('// UTF-8 bytes terminated by a single NUL byte.');
    Lines.Add('//');
    Lines.Add('// This file is a pure CONSUMER. It never registers APIs of its');
    Lines.Add('// own and never calls Framework.PrepareService. The host program');
    Lines.Add('// is responsible for wiring up LingoFuse before calling any');
    Lines.Add('// method in the ABI class:');
    Lines.Add('//');
    Lines.Add('//     Framework.ResetPrepare();');
    Lines.Add('//     Framework.PrepareClient("ipc:my_unit_abi", null);');
    Lines.Add('//     if (Framework.PrepareDone() != 1) { /* fail */ }');
    Lines.Add('//     try {');
    Lines.Add('//         int r = ABI.Add(3, 4);');
    Lines.Add('//         Console.WriteLine(r);');
    Lines.Add('//     } finally {');
    Lines.Add('//         Framework.ExitMainThread();');
    Lines.Add('//         Framework.Shutdown();');
    Lines.Add('//     }');
    Lines.Add('//');
    Lines.Add('// This file is a pure CLASS LIBRARY. It does NOT declare a Main');
    Lines.Add('// entry point. The entry point is provided either by the user''s');
    Lines.Add('// own application, or by the paired test program emitted by');
    Lines.Add('// csharp_abi_test_generator_tool.');
    Lines.Add('//');
    Lines.Add('// The module is built on top of the rebuilt LingoFuse C# interface');
    Lines.Add('// (namespace `LingoFuse`). The host project must therefore either');
    Lines.Add('// reference the compiled LingoFuse assembly, or include its source');
    Lines.Add('// files in the same project. See the companion README, §7.');
    Lines.Add('//');
    Lines.Add('// The runtime library is loaded lazily on the first LF_* call via');
    Lines.Add('// the DllImportResolver installed by the LingoFuse assembly. Place');
    Lines.Add('// LingoFuse64.dll (Windows) / liblingofuse.so (Linux) /');
    Lines.Add('// liblingofuse.dylib (macOS) next to the executable, or on the');
    Lines.Add('// OS loader search path.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');

    // =========================================================================
    // 2. Usings
    // =========================================================================
    Lines.Add('using System;');
    Lines.Add('using LingoFuse;');
    Lines.Add('');

    // =========================================================================
    // 3. Namespace
    // =========================================================================
    Lines.Add('namespace ' + NsName);
    Lines.Add('{');

    // =========================================================================
    // 4. WireStatus
    // =========================================================================
    Lines.Add('    // =====================================================================');
    Lines.Add('    // WireStatus - ABI status byte values.');
    Lines.Add('    //');
    Lines.Add('    // Every response on the wire starts with one of these two bytes.');
    Lines.Add('    // =====================================================================');
    Lines.Add('    internal static class WireStatus');
    Lines.Add('    {');
    Lines.Add('        /// <summary>Success: the payload is the serialized result.</summary>');
    Lines.Add('        public const byte Ok = 0x00;');
    Lines.Add('');
    Lines.Add('        /// <summary>Error: the payload is a UTF-8 message terminated by NUL.</summary>');
    Lines.Add('        public const byte Error = 0xFF;');
    Lines.Add('    }');
    Lines.Add('');

    // =========================================================================
    // 5. ABI class
    // =========================================================================
    Lines.Add('    // =====================================================================');
    Lines.Add('    // ABI - typed remote call methods.');
    Lines.Add('    //');
    Lines.Add('    // Configure <see cref="TargetApp"/> and <see cref="Timeout"/>');
    Lines.Add('    // before the first call. Every method in this class:');
    Lines.Add('    //   1. creates a request DataHandle and writes its arguments;');
    Lines.Add('    //   2. invokes Framework.Call against TargetApp with Timeout;');
    Lines.Add('    //   3. decodes the status byte and the payload;');
    Lines.Add('    //   4. throws LingoFuseCallException or LingoFuseException on');
    Lines.Add('    //      any failure.');
    Lines.Add('    //');
    Lines.Add('    // The class is stateless and thread-safe. Any number of threads');
    Lines.Add('    // may call the methods concurrently.');
    Lines.Add('    // =====================================================================');
    Lines.Add('    public static class ABI');
    Lines.Add('    {');
    Lines.Add('        /// <summary>');
    Lines.Add('        /// LingoFuse application name of the ABI service. Must match');
    Lines.Add('        /// AppInfo.Name on the service side.');
    Lines.Add('        /// </summary>');
    Lines.Add('        public static string TargetApp = ' + CSharpStrLit(TargetAppName) + ';');
    Lines.Add('');
    Lines.Add('        /// <summary>Per-call timeout in milliseconds.</summary>');
    Lines.Add('        public static ulong Timeout = 5000;');
    Lines.Add('');

    // ---- Per-API typed methods ------------------------------------------
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];

      ApiName := MakeApiName(f.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      ParamDecl := BuildCSharpParamList(f.Params);
      RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);

      Lines.Add('        // ---- ' + ApiName.Text + ' ----');
      if f.IsFunction then
        Lines.Add('        public static ' + RetType + ' ' + ApiName + '(' + ParamDecl + ')')
      else
        Lines.Add('        public static void ' + ApiName + '(' + ParamDecl + ')');
      Lines.Add('        {');

      // ---- 1. Build the request ---------------------------------------
      Lines.Add('            using (var param = new DataHandle(' + CSharpStrLit(ApiName) + '))');
      Lines.Add('            {');

      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        WriterMethod := ABI_Type_To_CSharp_Writer_Method(f.Params[j].PascalType);
        Lines.Add('                param.' + WriterMethod + '(' + PName + ');');
      end;

      // ---- 2. Invoke the remote call ----------------------------------
      Lines.Add('');
      Lines.Add('                using (var response = Framework.Call(TargetApp, param, Timeout))');
      Lines.Add('                {');

      // ---- 3. Decode the response -------------------------------------
      Lines.Add('                    if (!response.IsValid || response.Size == 0)');
      Lines.Add('                    {');
      Lines.Add('                        throw new LingoFuseCallException(');
      Lines.Add('                            "ABI call \"' + ApiName + '\" returned an empty response " +');
      Lines.Add('                            "(timeout or target application not found).",');
      Lines.Add('                            targetApp: TargetApp,');
      Lines.Add('                            targetApi: ' + CSharpStrLit(ApiName) + ');');
      Lines.Add('                    }');
      Lines.Add('');
      Lines.Add('                    response.Position = 0;');
      Lines.Add('                    byte status = response.ReadUInt8();');
      Lines.Add('                    if (status != WireStatus.Ok)');
      Lines.Add('                    {');
      Lines.Add('                        string err = "";');
      Lines.Add('                        try { err = response.ReadString(); }');
      Lines.Add('                        catch { /* payload was truncated; keep the empty message */ }');
      Lines.Add('                        throw new LingoFuseException(');
      Lines.Add('                            "ABI call \"' + ApiName + '\" failed: " + err);');
      Lines.Add('                    }');

      if f.IsFunction then
      begin
        ReaderMethod := ABI_Type_To_CSharp_Reader_Method(f.ReturnType);
        Lines.Add('');
        Lines.Add('                    return response.' + ReaderMethod + '();');
      end;

      Lines.Add('                }');
      Lines.Add('            }');
      Lines.Add('        }');
      Lines.Add('');
    end;

    Lines.Add('    }');

    // =========================================================================
    // Close namespace
    // =========================================================================
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the C# call module.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;


// =============================================================================
// README generator
// =============================================================================

function CSharpCallReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '1 byte'
  else if ABI_Type.Same('word') or ABI_Type.Same('smallint') then
    Result := '2 bytes'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or
    ABI_Type.Same('longword') or ABI_Type.Same('integer') or
    ABI_Type.Same('longint') or ABI_Type.Same('single') then
    Result := '4 bytes'
  else if ABI_Type.Same('int64') or ABI_Type.Same('uint64') or
    ABI_Type.Same('double') or ABI_Type.Same('extended') or
    ABI_Type.Same('real') then
    Result := '8 bytes'
  else if IsStringABIType(ABI_Type) then
    Result := 'variable + NUL'
  else
    Result := 'unknown';
end;

function CSharpCallReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

function CSharpCallReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

function GenerateABICallCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, TargetAppName, CsFileName: TP_String;

  // ---------------------------------------------------------------------------
  // §1. Header
  // ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - C# ABI Call Client');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `csharp_abi_call_generator_tool.pas`');
    L.Add('> (rebuild edition); this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Call-side file**    : `' + CsFileName + '`');
    L.Add('> **Namespace**         : `' + NsName + '`');
    L.Add('> **Target App name**   : `' + TargetAppName + '`');
    L.Add('> **Exported methods**  : ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> compile, deploy, or call this module without reading the source.');
    L.Add('');
    L.Add('---');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §2. Overview
  // ---------------------------------------------------------------------------
  procedure EmitOverview;
  begin
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('This document describes the **C# call-side client module** that');
    L.Add('was generated from the Pascal unit `' + UnitName + '`. The module');
    L.Add('is a strongly-typed wrapper around the LingoFuse C# interface that');
    L.Add('talks to a matching ABI service over a compact binary wire');
    L.Add('protocol.');
    L.Add('');
    L.Add('### 1.1 What is a call-side client?');
    L.Add('');
    L.Add('A C# call-side client is a single self-contained `.cs` file that:');
    L.Add('');
    L.Add('- exports one **static method** per API of the matching service;');
    L.Add('- each method mirrors the signature of the original routine;');
    L.Add('- serialises its arguments with `DataHandle.WriteXxx`, sends them');
    L.Add('  through `Framework.Call`, and decodes the response with');
    L.Add('  `DataHandle.ReadXxx`;');
    L.Add('- throws `LingoFuseCallException` on timeout or unreachable target,');
    L.Add('  and `LingoFuseException` when the service returns a `0xFF`');
    L.Add('  error status.');
    L.Add('');
    L.Add('The module is a **pure consumer**: it never registers APIs of its');
    L.Add('own, never calls `Framework.PrepareService`, and never touches the');
    L.Add('LingoFuse main-thread setup beyond what the host program');
    L.Add('provides.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Target resolution | Direct by App name (no discovery) |');
    L.Add('| Service dependency | Must be generated from the same model |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Implementation | C#, .NET 5+ (or .NET Core 3.0+) |');
    L.Add('| Base assembly | Rebuilt LingoFuse C# interface (`LingoFuse` namespace) |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Copy** the generated `.cs` file into your C# project. See §7.');
    L.Add('2. **Prepare** the LingoFuse framework in your `Main` (see §5.1).');
    L.Add('3. **Call** the exported static methods. See §8 and §9.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + CsFileName + '` | The call-side module (one self-contained file). |');
    L.Add('| `' + UnitName + '_abi_call_csharp.md` | This README. |');
    L.Add('');
    L.Add('### 1.5 File layout inside the generated module');
    L.Add('');
    L.Add('The generated file contains the following top-level types, all');
    L.Add('inside the `' + NsName + '` namespace:');
    L.Add('');
    L.Add('| Type | Purpose | Edit? |');
    L.Add('|------|---------|:-----:|');
    L.Add('| `WireStatus` | ABI status byte constants. | ❌ |');
    L.Add('| **`ABI`** | **One typed method per API, plus `TargetApp` and `Timeout`.** | ✅ |');
    L.Add('');
    L.Add('Only the `ABI` class needs your attention: set `TargetApp` and,');
    L.Add('if necessary, `Timeout`.');
    L.Add('');
    L.Add('### 1.6 No Main entry point');
    L.Add('');
    L.Add('The generated file is a **pure class library**. It does NOT');
    L.Add('declare a `Program` class and does NOT declare a `Main` entry');
    L.Add('point. This is deliberate:');
    L.Add('');
    L.Add('- A C# project may have exactly one `Main`. If the call library');
    L.Add('  brought its own `Main`, any host program (or the test program');
    L.Add('  emitted by `csharp_abi_test_generator_tool`) would collide and');
    L.Add('  the compiler would emit');
    L.Add('  `CS0017: Program has more than one entry point defined`.');
    L.Add('- Keeping the library entry-point-free lets it be referenced by');
    L.Add('  any number of console, GUI, service, or test projects.');
    L.Add('');
    L.Add('The entry point is provided by:');
    L.Add('');
    L.Add('- the paired test program from');
    L.Add('  `csharp_abi_test_generator_tool.pas`, or');
    L.Add('- your own `Main` method, following the startup sequence in §5.1.');
    L.Add('');
    L.Add('### 1.7 Dependency on the LingoFuse C# interface');
    L.Add('');
    L.Add('Unlike the legacy generator, this rebuild edition does NOT');
    L.Add('re-declare the P/Invoke layer, the serialization helpers, or the');
    L.Add('exception hierarchy. It builds directly on top of the rebuilt');
    L.Add('LingoFuse C# interface, whose public types are:');
    L.Add('');
    L.Add('| Type | Role |');
    L.Add('|------|------|');
    L.Add('| `Framework` | Process-wide ABI facade. |');
    L.Add('| `DataHandle` | RAII wrapper over the native data buffer. |');
    L.Add('| `LfIo` | Unified JSON / string I/O. |');
    L.Add('| `LingoFuseCallException` | Remote call failure exception. |');
    L.Add('| `LingoFuseException` | Base exception type. |');
    L.Add('');
    L.Add('The host project must therefore either:');
    L.Add('');
    L.Add('- **reference the compiled LingoFuse assembly**, or');
    L.Add('- **include the LingoFuse source files** in the same project.');
    L.Add('');
    L.Add('See §7.4 for the exact list of files.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use this call-side module');
    L.Add('');
    L.Add('Use this module when:');
    L.Add('');
    L.Add('- You need to call a **specific, known ABI service**.');
    L.Add('- The service signature is **stable** and known at build time.');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- A C# front-end calling a Python or C++ ABI service.');
    L.Add('- A .NET compute job calling a native Pascal engine.');
    L.Add('- A CLI tool that talks to a long-running ABI service.');
    L.Add('- A test harness exercising a remote ABI service.');
    L.Add('');
    L.Add('### 2.2 When NOT to use this call-side module');
    L.Add('');
    L.Add('- You need to discover the API surface at runtime.');
    L.Add('- The target service signature changes without a rebuild.');
    L.Add('- Parameters include complex types (List, Dictionary, custom');
    L.Add('  classes).');
    L.Add('- You need a client that can target **arbitrary** third-party');
    L.Add('  services without prior generation.');
    L.Add('- You need to talk to a JSON-based service.');
    L.Add('');
    L.Add('### 2.3 Comparison with other RPC clients');
    L.Add('');
    L.Add('| Approach | Typed | Binary | Self-describing | Paired codegen |');
    L.Add('|----------|:-----:|:------:|:---------------:|:--------------:|');
    L.Add('| This ABI client | yes | yes | no | yes (required) |');
    L.Add('| gRPC client | yes | yes | yes (proto) | yes (generated) |');
    L.Add('| REST + JSON client | no | no | yes | no |');
    L.Add('| Raw TCP client | no | yes | no | yes |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §4. Compatibility
  // ---------------------------------------------------------------------------
  procedure EmitCompatibility;
  begin
    L.Add('## 3. Compatibility');
    L.Add('');
    L.Add('### 3.1 .NET version support');
    L.Add('');
    L.Add('| Runtime | Status |');
    L.Add('|---------|--------|');
    L.Add('| .NET 5 / 6 / 7 / 8 / 9 | Recommended |');
    L.Add('| .NET Core 3.1 | Supported |');
    L.Add('| .NET Framework 4.7.2+ | Supported (with minor adjustments) |');
    L.Add('');
    L.Add('The LingoFuse C# interface uses `NativeLibrary.SetDllImportResolver`,');
    L.Add('which is available on .NET Core 3.0+ and .NET 5+. On .NET');
    L.Add('Framework 4.7.2+ the resolver is not available; use a standard');
    L.Add('DllImport with an explicit library file name instead.');
    L.Add('');
    L.Add('### 3.2 Platform support');
    L.Add('');
    L.Add('| Platform | Architecture | Status |');
    L.Add('|----------|-------------|--------|');
    L.Add('| Windows | x86_64 | Primary target |');
    L.Add('| Linux | x86_64 | Supported |');
    L.Add('| Linux | aarch64 | Supported |');
    L.Add('| macOS | x86_64 | Supported |');
    L.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    L.Add('');
    L.Add('**Byte order note**: the ABI wire format is little-endian.');
    L.Add('Every platform listed above is little-endian, and the helpers');
    L.Add('in `DataHandle` never perform byte swapping.');
    L.Add('');
    L.Add('### 3.3 Runtime dependencies');
    L.Add('');
    L.Add('| Dependency | Where to get it |');
    L.Add('|------------|----------------|');
    L.Add('| LingoFuse C# interface | The rebuilt C# binding (namespace `LingoFuse`) |');
    L.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    L.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | ZNetV2 binary distribution |');
    L.Add('| .NET 5+ (or .NET Core 3.0+) runtime | Microsoft |');
    L.Add('');
    L.Add('### 3.4 Character encoding');
    L.Add('');
    L.Add('- **Source file**: UTF-8, no BOM required.');
    L.Add('- **String payloads**: UTF-8 followed by a single `0x00` terminator.');
    L.Add('- **All strings** are .NET `System.String` (UTF-16 in memory);');
    L.Add('  the `DataHandle.WriteString` / `DataHandle.ReadString` helpers');
    L.Add('  perform the UTF-8 conversion.');
    L.Add('');
    L.Add('### 3.5 Threading model');
    L.Add('');
    L.Add('Every method in the `ABI` class is **thread-safe**. Different');
    L.Add('threads may call different methods in parallel. `Framework.Call`');
    L.Add('performs its own internal synchronisation and blocks the calling');
    L.Add('thread until the response arrives or the timeout expires.');
    L.Add('');
    L.Add('**Do not call an `ABI` method from inside a LingoFuse callback.**');
    L.Add('Doing so deadlocks the calling worker thread. If you need to');
    L.Add('reach a remote service from inside a callback, offload the call');
    L.Add('to a separate `Task.Run` or a dedicated thread.');
    L.Add('');
    L.Add('### 3.6 First-call initialization');
    L.Add('');
    L.Add('The runtime library is resolved lazily on the first `LF_*` call');
    L.Add('by the LingoFuse C# interface. There is no explicit load step.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The call-side module speaks the same wire format as the matching');
    L.Add('service.');
    L.Add('');
    L.Add('### 4.1 Request');
    L.Add('');
    L.Add('```');
    L.Add('request = [field1][field2]...[fieldN]');
    L.Add('```');
    L.Add('');
    L.Add('Fields are serialised in the **exact order** in which they appear');
    L.Add('in the original Pascal declaration. Each exported method performs');
    L.Add('this serialisation automatically.');
    L.Add('');
    L.Add('### 4.2 Response');
    L.Add('');
    L.Add('```');
    L.Add('response = [status:byte][payload]');
    L.Add('```');
    L.Add('');
    L.Add('The first byte is a status code:');
    L.Add('');
    L.Add('| Status | Value | Meaning | Payload |');
    L.Add('|--------|-------|---------|---------|');
    L.Add('| `WireStatus.Ok` | `0x00` | Success | Serialised result (functions) or empty (procedures). |');
    L.Add('| `WireStatus.Error` | `0xFF` | Error | UTF-8 message, terminated by `0x00`. |');
    L.Add('');
    L.Add('The exported methods decode this automatically:');
    L.Add('');
    L.Add('- `WireStatus.Ok` -> returns the deserialised result (or returns');
    L.Add('  normally for procedures).');
    L.Add('- `WireStatus.Error` -> throws `LingoFuseException` with the');
    L.Add('  decoded message.');
    L.Add('');
    L.Add('### 4.3 Encoding rules');
    L.Add('');
    L.Add('| Rule | Value |');
    L.Add('|------|-------|');
    L.Add('| Byte order | Little-endian |');
    L.Add('| Integer | Fixed-width, little-endian |');
    L.Add('| Float | IEEE 754, little-endian |');
    L.Add('| String | UTF-8 bytes terminated by a single `0x00` |');
    L.Add('| Boolean | Not supported |');
    L.Add('| Generics / collections | Not supported |');
    L.Add('');
    L.Add('### 4.4 Call sequence');
    L.Add('');
    L.Add('```mermaid');
    L.Add('sequenceDiagram');
    L.Add('    participant C as Call-side module');
    L.Add('    participant S as Service');
    L.Add('    C->>C: param.WriteXxx(a), param.WriteXxx(b)');
    L.Add('    C->>S: Framework.Call(TargetApp, param, Timeout)');
    L.Add('    S-->>C: [status][payload]');
    L.Add('    C->>C: response.ReadUInt8() -> status');
    L.Add('    alt status == WireStatus.Ok');
    L.Add('        C->>C: response.ReadXxx() -> result');
    L.Add('    else status == WireStatus.Error');
    L.Add('        C->>C: response.ReadString() -> error');
    L.Add('        C->>C: throw LingoFuseException');
    L.Add('    end');
    L.Add('```');
    L.Add('');
    L.Add('### 4.5 Error response example');
    L.Add('');
    L.Add('Bytes on the wire:');
    L.Add('');
    L.Add('```');
    L.Add('FF                                  <- WireStatus.Error');
    L.Add('72 65 61 64 20 66 61 69 6C 65 64    <- "read failed" (UTF-8)');
    L.Add('00                                  <- NUL terminator');
    L.Add('```');
    L.Add('');
    L.Add('The call-side module throws `LingoFuseException` with the decoded');
    L.Add('message. Callers should wrap their calls in a `try/catch` block.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §6. Runtime architecture
  // ---------------------------------------------------------------------------
  procedure EmitRuntimeArchitecture;
  begin
    L.Add('## 5. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph Client["Client process (this module)"]');
    L.Add('        C_PREP["Framework.ResetPrepare()"]');
    L.Add('        C_CLI["Framework.PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, null)"]');
    L.Add('        C_RUN["Framework.PrepareDone()"]');
    L.Add('        C_CALL["ABI.&lt;ApiName&gt;(args)"]');
    L.Add('        C_CATCH["try / catch LingoFuseCallException / LingoFuseException"]');
    L.Add('        C_OFF["Framework.ExitMainThread() + Framework.Shutdown()"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Service["Service process (external)"]');
    L.Add('        S_RUN["ABI service running<br/>App = &lt;unit&gt;_abi"]');
    L.Add('    end');
    L.Add('');
    L.Add('    C_PREP --> C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "Framework.Call over IPC" .-> S_RUN');
    L.Add('    S_RUN -. "response" .-> C_CATCH');
    L.Add('    C_CATCH --> C_OFF');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (client)');
    L.Add('');
    L.Add('```csharp');
    L.Add('using ' + NsName + ';');
    L.Add('using LingoFuse;');
    L.Add('');
    L.Add('Framework.ResetPrepare();');
    L.Add('Framework.PrepareClient("ipc:' + TargetAppName + '", null);');
    L.Add('');
    L.Add('if (Framework.PrepareDone() != 1)');
    L.Add('{');
    L.Add('    Console.Error.WriteLine("[FATAL] PrepareDone failed");');
    L.Add('    return 1;');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('Pass `null` as the second argument to `Framework.PrepareClient`');
    L.Add('because the client does not expose any APIs of its own.');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The caller invokes a static method, e.g. `ABI.Add(3, 4)`.');
    L.Add('2. The method creates a request `DataHandle`.');
    L.Add('3. It writes every argument with the matching `WriteXxx`.');
    L.Add('4. It calls `Framework.Call(TargetApp, param, Timeout)`.');
    L.Add('5. LingoFuse routes the payload to the service and waits for the');
    L.Add('   response (blocking).');
    L.Add('6. On a null or empty response, the method throws');
    L.Add('   `LingoFuseCallException` (timeout or unreachable target).');
    L.Add('7. It reads the status byte.');
    L.Add('8. On `WireStatus.Error`, it reads the UTF-8 message and throws');
    L.Add('   `LingoFuseException`.');
    L.Add('9. On `WireStatus.Ok`, it reads the result with `ReadXxx` and');
    L.Add('   returns it.');
    L.Add('');
    L.Add('### 5.3 Timeout');
    L.Add('');
    L.Add('The timeout is controlled by the static field `ABI.Timeout`');
    L.Add('(default `5000` ms). Change it before making calls:');
    L.Add('');
    L.Add('```csharp');
    L.Add('ABI.Timeout = 30000;  // 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('A value of `0` disables the timeout, which means the call blocks');
    L.Add('indefinitely if the service never responds.');
    L.Add('');
    L.Add('### 5.4 Target application name');
    L.Add('');
    L.Add('The target service is identified by the static field');
    L.Add('`ABI.TargetApp` (default `' + TargetAppName + '`). Change it to');
    L.Add('point at a differently-named service:');
    L.Add('');
    L.Add('```csharp');
    L.Add('ABI.TargetApp = "my_other_service_abi";');
    L.Add('```');
    L.Add('');
    L.Add('### 5.5 Shutdown');
    L.Add('');
    L.Add('```csharp');
    L.Add('Framework.ExitMainThread();');
    L.Add('Framework.Shutdown();');
    L.Add('```');
    L.Add('');
    L.Add('The client does not own an App handle, so there is nothing to');
    L.Add('release with `AppHandle.Dispose`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §7. Type mapping
  // ---------------------------------------------------------------------------
  procedure EmitTypeMapping;
  begin
    L.Add('## 6. Type Mapping');
    L.Add('');
    L.Add('### 6.1 Supported types');
    L.Add('');
    L.Add('The call-side module accepts the same type set as the matching');
    L.Add('service. Every exported method''s parameters and return type are');
    L.Add('drawn from this table.');
    L.Add('');
    L.Add('| ABI type | C# type | Reader | Writer | Wire size |');
    L.Add('|----------|---------|--------|--------|-----------|');
    L.Add('| `integer` | `int` | `response.ReadInt32()` | `param.WriteInt32()` | 4 bytes |');
    L.Add('| `longint` | `int` | `response.ReadInt32()` | `param.WriteInt32()` | 4 bytes |');
    L.Add('| `int64` | `long` | `response.ReadInt64()` | `param.WriteInt64()` | 8 bytes |');
    L.Add('| `cardinal` | `uint` | `response.ReadUInt32()` | `param.WriteUInt32()` | 4 bytes |');
    L.Add('| `dword` | `uint` | `response.ReadUInt32()` | `param.WriteUInt32()` | 4 bytes |');
    L.Add('| `longword` | `uint` | `response.ReadUInt32()` | `param.WriteUInt32()` | 4 bytes |');
    L.Add('| `word` | `ushort` | `response.ReadUInt16()` | `param.WriteUInt16()` | 2 bytes |');
    L.Add('| `smallint` | `short` | `response.ReadInt16()` | `param.WriteInt16()` | 2 bytes |');
    L.Add('| `byte` | `byte` | `response.ReadUInt8()` | `param.WriteUInt8()` | 1 byte |');
    L.Add('| `uint64` | `ulong` | `response.ReadUInt64()` | `param.WriteUInt64()` | 8 bytes |');
    L.Add('| `double` | `double` | `response.ReadDouble()` | `param.WriteDouble()` | 8 bytes |');
    L.Add('| `single` | `float` | `response.ReadSingle()` | `param.WriteSingle()` | 4 bytes |');
    L.Add('| `extended` | `double` | `response.ReadDouble()` | `param.WriteDouble()` | 8 bytes |');
    L.Add('| `real` | `double` | `response.ReadDouble()` | `param.WriteDouble()` | 8 bytes |');
    L.Add('| `string` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `ansistring` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `unicodestring` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `tpascalstring` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `tupascalstring` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `tp_string` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `pchar` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `pansichar` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('| `pwidechar` | `string` | `response.ReadString()` | `param.WriteString()` | variable + NUL |');
    L.Add('');
    L.Add('### 6.2 Unsupported types');
    L.Add('');
    L.Add('Anything not in §6.1 cannot appear in an exported method''s');
    L.Add('signature. If the original routine used a complex type, the');
    L.Add('matching method is **not generated at all**.');
    L.Add('');
    L.Add('Common examples of unsupported types:');
    L.Add('');
    L.Add('- `bool`');
    L.Add('- `List<T>`, `Dictionary<K,V>`, `HashSet<T>`, arrays');
    L.Add('- Custom classes and structs');
    L.Add('- `Nullable<T>`, tuples, `ValueTuple`');
    L.Add('- `DateTime`, `TimeSpan`, `decimal`');
    L.Add('- Pointers, delegates, function pointers');
    L.Add('');
    L.Add('**Workaround**: serialise the complex value into a `string` first');
    L.Add('(JSON or a custom format) on the caller side, then call a');
    L.Add('string-typed overload of the service. On the service side,');
    L.Add('deserialise the string back into the rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The wire format is little-endian for all integers and floats.');
    L.Add('Every supported platform is little-endian, so the generated code');
    L.Add('never performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('The exported methods use `DataHandle.WriteString` and');
    L.Add('`DataHandle.ReadString` for string parameters and return values.');
    L.Add('`WriteString` always appends a single `0x00` byte after the');
    L.Add('UTF-8 payload. `ReadString` scans forward until it finds that');
    L.Add('byte, or consumes the entire remaining buffer when no NUL is');
    L.Add('present (matching the Pascal / Python / C++ readers).');
    L.Add('');
    L.Add('**Recommendation**: do not hand-roll string encoding. Always');
    L.Add('rely on the generated methods.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §8. Deployment
  // ---------------------------------------------------------------------------
  procedure EmitDeployment;
  begin
    L.Add('## 7. Deployment');
    L.Add('');
    L.Add('### 7.1 Directory layout');
    L.Add('');
    L.Add('```');
    L.Add('my_csharp_client/');
    L.Add('  ' + CsFileName + '             <- generated (described here)');
    L.Add('  Program.cs                                     <- your own Main');
    L.Add('  my_csharp_client.csproj');
    L.Add('  LingoFuse64.dll                                <- Windows');
    L.Add('  liblingofuse.so                                <- Linux');
    L.Add('  liblingofuse.dylib                             <- macOS');
    L.Add('  z_ipc_64.dll / libz_ipc_64.so                  <- ZNetV2');
    L.Add('  // and the LingoFuse C# interface files (see §7.4)');
    L.Add('```');
    L.Add('');
    L.Add('The matching service process must be running independently and');
    L.Add('must expose the App name `' + TargetAppName + '`.');
    L.Add('');
    L.Add('### 7.2 Integration steps');
    L.Add('');
    L.Add('1. **Copy** `' + CsFileName + '` into your project directory.');
    L.Add('2. **Add** it to the project:');
    L.Add('   - `dotnet` CLI: it is picked up automatically as part of the');
    L.Add('     project SDK glob.');
    L.Add('   - Visual Studio: right-click the project, "Add → Existing');
    L.Add('     Item", select the file.');
    L.Add('3. **Reference** the namespace in your `Program.cs`:');
    L.Add('   ```csharp');
    L.Add('   using ' + NsName + ';');
    L.Add('   ```');
    L.Add('4. **Adjust** `ABI.TargetApp` if the service name differs from');
    L.Add('   the default `' + TargetAppName + '`.');
    L.Add('5. **Optionally adjust** `ABI.Timeout`.');
    L.Add('6. **Call** the methods as described in §8.');
    L.Add('');
    L.Add('### 7.3 Build commands');
    L.Add('');
    L.Add('**dotnet CLI:**');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet new console -o my_csharp_client');
    L.Add('cp ' + CsFileName + ' my_csharp_client/');
    L.Add('cp LingoFuse64.dll my_csharp_client/       # or .so / .dylib');
    L.Add('cd my_csharp_client');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('**MSBuild / Visual Studio:**');
    L.Add('');
    L.Add('1. Create a new Console App project targeting .NET 5+.');
    L.Add('2. Add the generated `.cs` file to the project.');
    L.Add('3. Add the LingoFuse C# interface (see §7.4).');
    L.Add('4. Copy `LingoFuse64.dll` (or the `.so` / `.dylib`) into the');
    L.Add('   project output directory, or mark it "Copy if newer" in');
    L.Add('   the project file.');
    L.Add('5. Build and run.');
    L.Add('');
    L.Add('### 7.4 Adding the LingoFuse C# interface to your project');
    L.Add('');
    L.Add('Because the generated module uses the rebuilt LingoFuse C#');
    L.Add('interface, the host project must reference it. Two options are');
    L.Add('available:');
    L.Add('');
    L.Add('**Option A — reference the compiled assembly.**');
    L.Add('');
    L.Add('Add a project reference to the assembly that contains the');
    L.Add('`LingoFuse` namespace:');
    L.Add('');
    L.Add('```xml');
    L.Add('<ItemGroup>');
    L.Add('  <ProjectReference Include="..\\src\\LingoFuse\\LingoFuse.csproj" />');
    L.Add('</ItemGroup>');
    L.Add('```');
    L.Add('');
    L.Add('**Option B — include the source files directly.**');
    L.Add('');
    L.Add('Copy the following files into your project directory. The');
    L.Add('project SDK glob will pick them up automatically:');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `Framework.cs` | Process-wide ABI facade. |');
    L.Add('| `AppHandle.cs` | Application container with typed registration. |');
    L.Add('| `DataHandle.cs` | RAII wrapper over the native data buffer. |');
    L.Add('| `LfIo.cs` | Unified JSON / string I/O. |');
    L.Add('| `LingoFuseException.cs` | Exception hierarchy. |');
    L.Add('| `NetworkEvents.cs` | Process-global connect / disconnect events. |');
    L.Add('| `LingoFuseStatus.cs` | Status queue and health checks. |');
    L.Add('| `NativeMethods.cs` | P/Invoke declarations. |');
    L.Add('| `NativeTypes.cs` | Opaque handle types and callback delegates. |');
    L.Add('| `Utf8Marshal.cs` | UTF-8 marshalling helpers. |');
    L.Add('');
    L.Add('Both options produce the same `LingoFuse` namespace. Choose');
    L.Add('whichever fits your build topology better.');
    L.Add('');
    L.Add('### 7.5 Runtime library location');
    L.Add('');
    L.Add('The runtime library is resolved by the `DllImportResolver`');
    L.Add('installed by the LingoFuse C# interface, which maps the logical');
    L.Add('name `"LingoFuse"` to:');
    L.Add('');
    L.Add('| Platform | File |');
    L.Add('|----------|------|');
    L.Add('| Windows x64 | `LingoFuse64.dll` |');
    L.Add('| Windows x86 | `LingoFuse32.dll` |');
    L.Add('| Linux / BSD | `liblingofuse.so` |');
    L.Add('| macOS | `liblingofuse.dylib` |');
    L.Add('');
    L.Add('Place the file in the application directory, or on the OS');
    L.Add('loader search path (`PATH` / `LD_LIBRARY_PATH` /');
    L.Add('`DYLD_LIBRARY_PATH`).');
    L.Add('');
    L.Add('### 7.6 Coexistence with the service file');
    L.Add('');
    L.Add('If you also generated the service file with');
    L.Add('`csharp_abi_service_generator_tool`, both `.cs` files can live');
    L.Add('side by side in the same project without symbol collisions,');
    L.Add('because:');
    L.Add('');
    L.Add('- the service module uses the namespace `' + UnitName + '_abi`;');
    L.Add('- the call module uses the namespace `' + NsName + '`;');
    L.Add('- each module owns its own `WireStatus` constants, scoped to its');
    L.Add('  own namespace.');
    L.Add('');
    L.Add('### 7.7 Shutdown');
    L.Add('');
    L.Add('The recommended shutdown sequence on the client side is:');
    L.Add('');
    L.Add('1. `Framework.ExitMainThread();`');
    L.Add('2. `Framework.Shutdown();`');
    L.Add('');
    L.Add('The client does not own an App handle, so there is nothing to');
    L.Add('release with `AppHandle.Dispose`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Testing
  // ---------------------------------------------------------------------------
  procedure EmitTesting;
  begin
    L.Add('## 8. Testing');
    L.Add('');
    L.Add('The program below is a complete, copy-paste-ready test client.');
    L.Add('Save it as `Program.cs` next to the generated call module.');
    L.Add('');
    L.Add('### 8.1 Client program (`Program.cs`)');
    L.Add('');
    L.Add('```csharp');
    L.Add('// Program.cs - test entry point for the generated C# ABI client.');
    L.Add('//');
    L.Add('// Build:');
    L.Add('//   dotnet new console');
    L.Add('//   cp ' + CsFileName + ' .');
    L.Add('//   cp LingoFuse64.dll .');
    L.Add('//   dotnet run');
    L.Add('');
    L.Add('using System;');
    L.Add('using ' + NsName + ';');
    L.Add('using LingoFuse;');
    L.Add('');
    L.Add('internal static class Program');
    L.Add('{');
    L.Add('    static int Main(string[] args)');
    L.Add('    {');
    L.Add('        Console.WriteLine("=== ' + UnitName + ' ABI client ===");');
    L.Add('');
    L.Add('        // ---- Prepare the framework --------------------------------');
    L.Add('        Framework.ResetPrepare();');
    L.Add('        Framework.PrepareClient("ipc:' + TargetAppName + '", null);');
    L.Add('');
    L.Add('        if (Framework.PrepareDone() != 1)');
    L.Add('        {');
    L.Add('            Console.Error.WriteLine("[FATAL] PrepareDone failed");');
    L.Add('            return 1;');
    L.Add('        }');
    L.Add('');
    L.Add('        try');
    L.Add('        {');
    L.Add('            // Replace with actual calls to the generated methods.');
    L.Add('            // Example:');
    L.Add('            //     int r = ABI.Add(3, 4);');
    L.Add('            //     Console.WriteLine("Add(3,4) = " + r);');
    L.Add('        }');
    L.Add('        catch (LingoFuseCallException ex)');
    L.Add('        {');
    L.Add('            Console.Error.WriteLine("[CALL-ERROR] " + ex.Message);');
    L.Add('        }');
    L.Add('        catch (LingoFuseException ex)');
    L.Add('        {');
    L.Add('            Console.Error.WriteLine("[ERROR] " + ex.Message);');
    L.Add('        }');
    L.Add('        finally');
    L.Add('        {');
    L.Add('            Framework.ExitMainThread();');
    L.Add('            Framework.Shutdown();');
    L.Add('        }');
    L.Add('');
    L.Add('        return 0;');
    L.Add('    }');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Running the test');
    L.Add('');
    L.Add('Open two terminals.');
    L.Add('');
    L.Add('**Terminal 1 (service)** — start the matching service (generated');
    L.Add('by `csharp_abi_service_generator_tool`,');
    L.Add('`py_abi_service_generator_tool`, or');
    L.Add('`cpp_abi_service_generator_tool`).');
    L.Add('');
    L.Add('Wait for the service to print `[OK] Service ready` or');
    L.Add('equivalent.');
    L.Add('');
    L.Add('**Terminal 2 (client)**');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path:');
    L.Add('');
    L.Add('1. Stop the service process.');
    L.Add('2. Run the client again.');
    L.Add('3. The exported method throws `LingoFuseCallException` with a');
    L.Add('   timeout or "target not found" message.');
    L.Add('');
    L.Add('### 8.4 Unit-level testing of the DataHandle helpers');
    L.Add('');
    L.Add('The `DataHandle` type is publicly accessible, so a unit test can');
    L.Add('exercise the serialization path without a running service:');
    L.Add('');
    L.Add('```csharp');
    L.Add('using var hnd = new DataHandle("test");');
    L.Add('hnd.WriteInt32(42);');
    L.Add('hnd.WriteString("hello");');
    L.Add('hnd.Position = 0;');
    L.Add('int i = hnd.ReadInt32();         // i == 42');
    L.Add('string s = hnd.ReadString();     // s == "hello"');
    L.Add('```');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §10. API reference
  // ---------------------------------------------------------------------------
  procedure EmitApiReference;
  var
    ii, jj: integer;
    Func: TFunctionStructure;
    FuncDesc: TP_String;
    ShortDesc: TP_String;
    ApiNm: TP_String;
    RowStr: TP_String;
    ParamDecl: TP_String;
    RetDecl: TP_String;
    CallExpr: TP_String;
    PName, PTyp: TP_String;
    UsedNames: TPascalStringList;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this call-side module exports no methods.**');
      L.Add('>');
      L.Add('> Possible reasons:');
      L.Add('>');
      L.Add('> 1. The source unit has no top-level routines.');
      L.Add('> 2. Every routine failed the ABI type check.');
      L.Add('>');
      L.Add('> Supported types are listed in §6.1.');
      L.Add('');
      Exit;
    end;

    L.Add('Total exported methods: **' + umlIntToStr(Length(SupportedFuncs)).Text + '**.');
    L.Add('');
    L.Add('Every method is a **static method** on the `ABI` class. Call');
    L.Add('them directly from your code:');
    L.Add('');
    L.Add('```csharp');
    L.Add('using ' + NsName + ';');
    L.Add('');
    L.Add('var r = ABI.<ApiName>(...);');
    L.Add('```');
    L.Add('');

    // ---- Summary --------------------------------------------------------
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | Method | Kind | Params | Return | Description |');
    L.Add('|---|--------|------|--------|--------|-------------|');

    UsedNames := TPascalStringList.Create;
    try
      for ii := 0 to High(SupportedFuncs) do
      begin
        Func := SupportedFuncs[ii];
        ApiNm := MakeApiName(Func.Name);
        if UsedNames.IndexOf(ApiNm) >= 0 then
        begin
          jj := 1;
          while UsedNames.IndexOf(ApiNm + '_' + umlIntToStr(jj).Text) >= 0 do
            Inc(jj);
          ApiNm := ApiNm + '_' + umlIntToStr(jj).Text;
        end;
        UsedNames.Add(ApiNm);

        ShortDesc := CSharpCallReadmeTableCell(GetFullDescription(Func.Comment));
        if ShortDesc.Len > 60 then
          ShortDesc := ShortDesc.GetString(1, 61) + '...';

        if Func.IsFunction then
          RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | function | '
            + umlIntToStr(Length(Func.Params)).Text + ' | `'
            + ABI_Type_To_CSharp_Decl(Func.ReturnType) + '` | ' + ShortDesc + ' |'
        else
          RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | procedure | '
            + umlIntToStr(Length(Func.Params)).Text + ' | - | ' + ShortDesc + ' |';
        L.Add(RowStr);
      end;
    finally
      UsedNames.Free;
    end;

    L.Add('');

    // ---- Per-API details ------------------------------------------------
    UsedNames := TPascalStringList.Create;
    try
      for ii := 0 to High(SupportedFuncs) do
      begin
        Func := SupportedFuncs[ii];
        ApiNm := MakeApiName(Func.Name);
        if UsedNames.IndexOf(ApiNm) >= 0 then
        begin
          jj := 1;
          while UsedNames.IndexOf(ApiNm + '_' + umlIntToStr(jj).Text) >= 0 do
            Inc(jj);
          ApiNm := ApiNm + '_' + umlIntToStr(jj).Text;
        end;
        UsedNames.Add(ApiNm);

        FuncDesc := CSharpCallReadmeParagraph(GetFullDescription(Func.Comment));

        // Reconstructed signature.
        ParamDecl := '';
        for jj := 0 to High(Func.Params) do
        begin
          PName := MakeSafeCSharpParamName(Func.Params[jj].Name, jj);
          PTyp := ABI_Type_To_CSharp_Decl(Func.Params[jj].PascalType);
          if jj > 0 then ParamDecl := ParamDecl + ', ';
          ParamDecl := ParamDecl + PTyp + ' ' + PName;
        end;

        // Example call expression.
        CallExpr := ApiNm + '(';
        for jj := 0 to High(Func.Params) do
        begin
          if jj > 0 then CallExpr := CallExpr + ', ';
          if IsStringABIType(Func.Params[jj].PascalType) then
            CallExpr := CallExpr + '"hello"'
          else if Func.Params[jj].PascalType.Same('single') then
            CallExpr := CallExpr + '0.0f'
          else if Func.Params[jj].PascalType.Same('double') or
                  Func.Params[jj].PascalType.Same('extended') or
                  Func.Params[jj].PascalType.Same('real') then
            CallExpr := CallExpr + '0.0'
          else
            CallExpr := CallExpr + '0';
        end;
        CallExpr := CallExpr + ')';

        L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
        L.Add('');

        if Func.IsFunction then
        begin
          RetDecl := ABI_Type_To_CSharp_Decl(Func.ReturnType);
          L.Add('- **Declaration**: `public static ' + RetDecl + ' ' + ApiNm
            + '(' + ParamDecl + ')`');
          L.Add('- **Kind**: function; returns `' + RetDecl + '`');
        end
        else
        begin
          L.Add('- **Declaration**: `public static void ' + ApiNm
            + '(' + ParamDecl + ')`');
          L.Add('- **Kind**: procedure');
        end;
        L.Add('- **Throws**: `LingoFuseCallException` on timeout / unreachable target,');
        L.Add('  `LingoFuseException` on `WireStatus.Error`.');
        L.Add('');

        if FuncDesc.Len > 0 then
        begin
          L.Add('#### Description');
          L.Add('');
          L.Add(FuncDesc);
          L.Add('');
        end;

        if Length(Func.Params) > 0 then
        begin
          L.Add('#### Parameters');
          L.Add('');
          L.Add('| # | Name | C# type | ABI type | Wire size |');
          L.Add('|---|------|---------|----------|-----------|');
          for jj := 0 to High(Func.Params) do
          begin
            PName := MakeSafeCSharpParamName(Func.Params[jj].Name, jj);
            PTyp := ABI_Type_To_CSharp_Decl(Func.Params[jj].PascalType);
            RowStr := '| ' + umlIntToStr(jj + 1).Text + ' | `' + PName + '`'
              + ' | `' + PTyp + '`'
              + ' | `' + Func.Params[jj].PascalType + '`'
              + ' | ' + CSharpCallReadmeWireSizeText(Func.Params[jj].PascalType)
              + ' |';
            L.Add(RowStr);
          end;
          L.Add('');
        end;

        L.Add('#### Call example');
        L.Add('');
        L.Add('```csharp');
        L.Add('using ' + NsName + ';');
        L.Add('using LingoFuse;');
        L.Add('');
        L.Add('try');
        L.Add('{');
        if Func.IsFunction then
          L.Add('    var result = ABI.' + CallExpr + ';')
        else
          L.Add('    ABI.' + CallExpr + ';');
        L.Add('}');
        L.Add('catch (LingoFuseCallException ex)');
        L.Add('{');
        L.Add('    // Timeout or unreachable target.');
        L.Add('    Console.Error.WriteLine("Call failed: " + ex.Message);');
        L.Add('}');
        L.Add('catch (LingoFuseException ex)');
        L.Add('{');
        L.Add('    // The service returned WireStatus.Error.');
        L.Add('    Console.Error.WriteLine("Service error: " + ex.Message);');
        L.Add('}');
        L.Add('```');
        L.Add('');

        L.Add('---');
        L.Add('');
      end;
    finally
      UsedNames.Free;
    end;
  end;

  // ---------------------------------------------------------------------------
  // §11. Troubleshooting
  // ---------------------------------------------------------------------------
  procedure EmitTroubleshooting;
  begin
    L.Add('## 10. Troubleshooting');
    L.Add('');
    L.Add('### 10.1 Symptom, cause, fix');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `CS0017: Program has more than one entry point` | The call library brings its own `Main`, or an old copy of the file is present | The current generator emits a library with no `Main`. If the error persists, delete the old file and regenerate. |');
    L.Add('| `CS0246: type or namespace ''Framework'' not found` | The LingoFuse C# interface is not referenced | Add the interface assembly reference, or include its source files in the project (see §7.4). |');
    L.Add('| `DllNotFoundException: LingoFuse64.dll` | Runtime library not on the search path | Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` next to the executable. |');
    L.Add('| `BadImageFormatException` | Architecture mismatch (32-bit vs 64-bit) | Use the matching runtime for your platform. |');
    L.Add('| `PrepareDone` returns 0 | Framework already running in this process | Reuse the existing runtime, or call `Framework.Shutdown` first. |');
    L.Add('| `PrepareDone` returns 0 | Service not running | Start the service before the client, or poll `LingoFuseStatus.CheckApp`. |');
    L.Add('| `LingoFuseCallException: returned an empty response` | App name mismatch | Check `ABI.TargetApp` and the service `AppInfo.Name`. |');
    L.Add('| `LingoFuseCallException: returned an empty response` | Timeout too short | Increase `ABI.Timeout`. |');
    L.Add('| `LingoFuseException: failed: input truncated` | Service rejected the request | Verify the client and service were generated from the same model. |');
    L.Add('| `LingoFuseException: failed: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| `LingoFuseException: failed: ...` on every call | Service App not registered | Verify the service is running and registered. |');
    L.Add('| Deadlock inside a callback | Calling an ABI method inside a LingoFuse callback | Offload the call to a separate `Task.Run` or thread. |');
    L.Add('| Client hangs forever | Timeout set to 0 | Set `ABI.Timeout` to a positive value. |');
    L.Add('| Symbol collision with the service file | Both files in the same namespace | The call module uses `' + NsName + '`; the service module uses `' + UnitName + '_abi`. Do not put both types in one namespace. |');
    L.Add('');
    L.Add('### 10.2 Verifying the service is reachable');
    L.Add('');
    L.Add('Before making a call:');
    L.Add('');
    L.Add('```csharp');
    L.Add('using LingoFuse;');
    L.Add('');
    L.Add('if (!LingoFuseStatus.CheckMainThread())');
    L.Add('    Console.Error.WriteLine("Main thread is not running");');
    L.Add('');
    L.Add('if (!LingoFuseStatus.CheckApp(ABI.TargetApp))');
    L.Add('    Console.Error.WriteLine("Target service is not registered");');
    L.Add('```');
    L.Add('');
    L.Add('### 10.3 Inspecting the raw payload');
    L.Add('');
    L.Add('To dump the raw bytes of a `DataHandle` for debugging:');
    L.Add('');
    L.Add('```csharp');
    L.Add('long sz = handle.Size;');
    L.Add('byte[] bytes = new byte[sz];');
    L.Add('handle.Position = 0;');
    L.Add('handle.ReadBytesExact((int)sz).CopyTo(bytes, 0);');
    L.Add('Console.WriteLine(BitConverter.ToString(bytes).Replace("-", " "));');
    L.Add('```');
    L.Add('');
    L.Add('### 10.4 Adjusting the timeout');
    L.Add('');
    L.Add('Increase `ABI.Timeout` when calling a slow service:');
    L.Add('');
    L.Add('```csharp');
    L.Add('ABI.Timeout = 30000;  // 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('A value of `0` disables the timeout, which means the call blocks');
    L.Add('indefinitely if the service never responds.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §12. Self-assessment checklist
  // ---------------------------------------------------------------------------
  procedure EmitSelfAssessment;
  begin
    L.Add('## 11. Self-Assessment Checklist');
    L.Add('');
    L.Add('After reading this document you should be able to answer the');
    L.Add('following questions without consulting the source code. If any');
    L.Add('answer is unclear, re-read the corresponding section.');
    L.Add('');
    L.Add('| # | Question | Section |');
    L.Add('|---|----------|---------|');
    L.Add('| 1 | What does this call-side module export? | §1 |');
    L.Add('| 2 | When should I use this client instead of a JSON client? | §2 |');
    L.Add('| 3 | Which .NET runtime and platforms are supported? | §3 |');
    L.Add('| 4 | What is the wire format of a request and a response? | §4 |');
    L.Add('| 5 | What is the client startup sequence? | §5.1 |');
    L.Add('| 6 | How is the target App name configured? | §5.4 |');
    L.Add('| 7 | How is the timeout configured? | §5.3 |');
    L.Add('| 8 | Which C# types are accepted? | §6.1 |');
    L.Add('| 9 | What LingoFuse C# types does the generated code use? | §1.7 |');
    L.Add('| 10 | How do I integrate the file into my project? | §7.2 |');
    L.Add('| 11 | How do I add the LingoFuse C# interface to my project? | §7.4 |');
    L.Add('| 12 | Can I use both service and call files in one project? | §7.6 |');
    L.Add('| 13 | What is the shutdown order on the client side? | §7.7 |');
    L.Add('| 14 | What exceptions does a call throw? | §4.2, §9 |');
    L.Add('| 15 | What should I do if the client hangs forever? | §10.4 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('C# call-side module.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §13. Resources
  // ---------------------------------------------------------------------------
  procedure EmitResources;
  begin
    L.Add('## 12. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| LingoFuse C# interface | Rebuilt C# binding (namespace `LingoFuse`) |');
    L.Add('| LingoFuse runtime distribution | Native `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` |');
    L.Add('| ZNetV2 repository | Provides `z_ipc_*` binaries |');
    L.Add('| `csharp_abi_service_generator_tool.pas` | Paired C# service-side generator |');
    L.Add('| `csharp_abi_test_generator_tool.pas` | Paired C# test-program generator |');
    L.Add('| `pas_abi_service_generator_tool.pas` | Paired Pascal service-side generator |');
    L.Add('| `pas_abi_call_generator_tool.pas` | Paired Pascal call-side generator |');
    L.Add('| `py_abi_service_generator_tool.pas` | Paired Python service-side generator |');
    L.Add('| `py_abi_call_generator_tool.pas` | Paired Python call-side generator |');
    L.Add('| `cpp_abi_service_generator_tool.pas` | Paired C++ service-side generator |');
    L.Add('| `cpp_abi_call_generator_tool.pas` | Paired C++ call-side generator |');
    L.Add('| `cpp_abi_cmake_generator_tool.pas` | CMake and test-program generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `csharp_abi_call_generator_tool.pas`');
    L.Add('(rebuild edition).');
    L.Add('');
  end;

// =============================================================================
// Main body
// =============================================================================
begin
  Result := TPascalStringList.Create;

  if Model = nil then
  begin
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: supplied TPascal_Func_Model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: Model.UnitName is empty.');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi_call';
  TargetAppName := NormalizedUnit + '_abi';
  CsFileName := NormalizedUnit + '_abi_call.cs';

  Log(PFormat('GenerateABICallCsharpReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABICallCsharpReadme: %d valid APIs',
    [Length(SupportedFuncs)]));

  L := Result;
  try
    EmitHeader;
    EmitOverview;
    EmitApplicationScope;
    EmitCompatibility;
    EmitWireProtocol;
    EmitRuntimeArchitecture;
    EmitTypeMapping;
    EmitDeployment;
    EmitTesting;
    EmitApiReference;
    EmitTroubleshooting;
    EmitSelfAssessment;
    EmitResources;
  finally
    // Result already owns L; nothing to free here.
  end;

  Log(PFormat('GenerateABICallCsharpReadme: %d lines generated', [L.Count]));
end;

end.
