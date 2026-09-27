unit csharp_abi_service_generator_tool;


// csharp_abi_service_generator_tool - LingoFuse ABI Service Provider
// Generator for C# (rebuild edition).
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
//   AppHandle           - application container with typed registration.
//   DataHandle          - RAII wrapper over the native data buffer.
//   LfIo                - unified JSON / string I/O.
//   LingoFuseException  - base exception type.
//
// The generated file exposes:
//
//   AppInfo         - Name / Desc constants.
//   WireStatus      - ABI status byte constants (0x00 = OK, 0xFF = error).
//   InternalCalls   - one stub per routine (the user replaces the body).
//   Callbacks       - one action per routine, implementing the ABI
//                     status protocol on the wire.
//   Service         - RegisterAllABIAPIs / CreateAndRegisterABIApp.
//
// The generated file is a pure CLASS LIBRARY. It does NOT declare a
// `Program` class or a `Main` entry point. The entry point is provided
// either by the user's own application or by the paired test program
// emitted by csharp_abi_test_generator_tool.
//
// Wire protocol (both directions):
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


  // GenerateABIServiceCsharpCode - generate the C# service module.
  //
  // The returned list contains the lines of a .cs file that declares
  // the service classes. The file has NO Main entry point; it is meant
  // to be compiled as a library alongside a host program or a test
  // program. The caller owns the list and must release it with
  // DisposeObject.

function GenerateABIServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABIServiceCsharpReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// ABI type mapping, and every exposed API of the generated C# service.
// The document is written so that both human readers and AI assistants
// can learn the service's usage model from the README alone.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABIServiceCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[csharp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;


// -----------------------------------------------------------------------------
// ABI type mapping (unchanged from the legacy generator)
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

// DataHandle reader method name for the given ABI type (without the
// "input." receiver).
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

// DataHandle writer method name for the given ABI type (without the
// "output." receiver and without the argument list).
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

// Default value text for the stub body (used when a function has a
// non-void return type and the user has not yet filled the body in).
function ABI_Type_To_CSharp_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'string.Empty'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else if T.Same('single') then
    Result := '0.0f'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_CSharp_Decl(T) <> '';
end;


// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// Wire API name: matches the naming scheme used by every other service
// generator, so that the API names registered on LingoFuse are
// identical across languages.
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

function BuildCSharpArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCSharpParamName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
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
// GenerateABIServiceCsharpCode
// =============================================================================

function GenerateABIServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  ParamDecl, ArgList, RetType: TP_String;
  Description: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  HasParams: boolean;
  PName, PTyp, ReaderMethod, WriterMethod: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating C# ABI service for unit "%s"', [UnitName.Text]));

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
    Lines.Add('// Auto-generated by csharp_abi_service_generator_tool (rebuild edition).');
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
    Lines.Add('// This file is a pure CLASS LIBRARY. It does NOT declare a Main');
    Lines.Add('// entry point. The entry point is provided either by the user''s');
    Lines.Add('// own application, or by the paired test program emitted by');
    Lines.Add('// csharp_abi_test_generator_tool.');
    Lines.Add('//');
    Lines.Add('// The module is built on top of the rebuilt LingoFuse C# interface');
    Lines.Add('// (namespace `LingoFuse`), which provides:');
    Lines.Add('//');
    Lines.Add('//     Framework           - process-wide ABI facade.');
    Lines.Add('//     AppHandle           - application container with typed registration.');
    Lines.Add('//     DataHandle          - RAII wrapper over the native data buffer.');
    Lines.Add('//     LfIo                - unified JSON / string I/O.');
    Lines.Add('//     LingoFuseException  - base exception type.');
    Lines.Add('//');
    Lines.Add('// The generated code uses these public types directly. It does NOT');
    Lines.Add('// re-declare the P/Invoke layer or the serialization helpers. The');
    Lines.Add('// host project must therefore reference (or include the source of)');
    Lines.Add('// the LingoFuse C# assembly.');
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
    // 4. AppInfo
    // =========================================================================
    Lines.Add('    // =====================================================================');
    Lines.Add('    // AppInfo - application metadata.');
    Lines.Add('    //');
    Lines.Add('    // Name must match the TargetApp configured on the client side.');
    Lines.Add('    //');
    Lines.Add('    //    Service : AppInfo.Name');
    Lines.Add('    //    Client  : ABI.TargetApp');
    Lines.Add('    // =====================================================================');
    Lines.Add('    public static class AppInfo');
    Lines.Add('    {');
    Lines.Add('        /// <summary>LingoFuse application name of this ABI service.</summary>');
    Lines.Add('        public const string Name = ' + CSharpStrLit(AppName) + ';');
    Lines.Add('');
    Lines.Add('        /// <summary>Human-readable description of this ABI service.</summary>');
    Lines.Add('        public const string Desc = ' + CSharpStrLit(AppDesc) + ';');
    Lines.Add('    }');
    Lines.Add('');

    // =========================================================================
    // 5. WireStatus
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
    // 6. InternalCalls stubs
    // =========================================================================
    Lines.Add('    // =====================================================================');
    Lines.Add('    // InternalCalls - one stub per API.');
    Lines.Add('    //');
    Lines.Add('    // This is the ONLY class the user is expected to edit. Replace');
    Lines.Add('    // each TODO comment with a call to the real implementation.');
    Lines.Add('    //');
    Lines.Add('    // The method signature is generated to match the original');
    Lines.Add('    // declaration exactly. Parameter names and return types are');
    Lines.Add('    // fixed; the body is yours.');
    Lines.Add('    // =====================================================================');
    Lines.Add('    public static class InternalCalls');
    Lines.Add('    {');

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

      InternalCallName := 'InternalCall_' + ApiName;
      ParamDecl := BuildCSharpParamList(f.Params);
      ArgList := BuildCSharpArgList(f.Params);
      // RetType is computed here for the stub signature. It is ALSO
      // recomputed inside the Callbacks loop below; the two loops are
      // independent and must not share this variable across iterations.
      RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);

      Lines.Add('');
      Lines.Add('        // ---- ' + ApiName.Text + ' ----');
      if f.IsFunction then
        Lines.Add('        public static ' + RetType + ' ' + InternalCallName + '(' + ParamDecl + ')')
      else
        Lines.Add('        public static void ' + InternalCallName + '(' + ParamDecl + ')');
      Lines.Add('        {');
      Lines.Add('            // TODO: replace the body with a call to the real function.');
      if f.IsFunction then
        Lines.Add('            //     return MyEngine.' + f.Name.Text + '(' + ArgList + ');')
      else
        Lines.Add('            //     MyEngine.' + f.Name.Text + '(' + ArgList + ');');

      if f.IsFunction then
        Lines.Add('            return ' + ABI_Type_To_CSharp_Default(f.ReturnType) + ';');
      Lines.Add('        }');
    end;

    Lines.Add('    }');
    Lines.Add('');

    // =========================================================================
    // 7. Callbacks
    // =========================================================================
    Lines.Add('    // =====================================================================');
    Lines.Add('    // Callbacks - one action per API, implementing the ABI status');
    Lines.Add('    // protocol on the wire.');
    Lines.Add('    //');
    Lines.Add('    // Every action:');
    Lines.Add('    //   1. reads its parameters from the input DataHandle;');
    Lines.Add('    //   2. invokes the matching InternalCalls stub;');
    Lines.Add('    //   3. writes [status][payload] to the output DataHandle.');
    Lines.Add('    //');
    Lines.Add('    // The actions are registered with the AppHandle through');
    Lines.Add('    // AppHandle.RegisterCall, which accepts an');
    Lines.Add('    // Action<DataHandle, DataHandle> delegate. The AppHandle');
    Lines.Add('    // keeps the delegate alive for the whole application lifetime,');
    Lines.Add('    // so no manual GC-keepalive is required here.');
    Lines.Add('    //');
    Lines.Add('    // A managed exception raised inside an action MUST NOT be');
    Lines.Add('    // allowed to escape into the native layer. Each action catches');
    Lines.Add('    // its own exceptions and reports them through the 0xFF status');
    Lines.Add('    // code, so the client receives a well-formed error response.');
    Lines.Add('    // =====================================================================');
    Lines.Add('    internal static class Callbacks');
    Lines.Add('    {');

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

      CallbackName := 'Callback_' + ApiName;
      InternalCallName := 'InternalCall_' + ApiName;
      HasParams := Length(f.Params) > 0;

      // -----------------------------------------------------------------
      // Recompute RetType for THIS routine.
      //
      // This variable is reused across iterations of this loop and must
      // therefore be re-evaluated for every function. Reusing the value
      // left behind by the InternalCalls loop above would produce a
      // wrong local variable type in the generated code:
      //
      //     CS0029: Cannot implicitly convert type 'int' to 'string'
      //     CS1503: Argument 1: cannot convert from 'string' to 'int'
      //
      // Both errors are reported at the `_ret` declaration and at the
      // subsequent `output.WriteXxx(_ret)` call.
      // -----------------------------------------------------------------
      RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);

      Lines.Add('');
      Lines.Add('        // ---- ' + ApiName.Text + ' ----');
      Lines.Add('        public static void ' + ApiName + '(DataHandle input, DataHandle output)');
      Lines.Add('        {');
      Lines.Add('            try');
      Lines.Add('            {');

      // Deserialize parameters.
      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        PTyp := ABI_Type_To_CSharp_Decl(f.Params[j].PascalType);
        ReaderMethod := ABI_Type_To_CSharp_Reader_Method(f.Params[j].PascalType);
        Lines.Add('                ' + PTyp + ' ' + PName + ' = input.' + ReaderMethod + '();');
      end;

      // Invoke the internal stub.
      ArgList := BuildCSharpArgList(f.Params);
      if f.IsFunction then
        Lines.Add('                ' + RetType + ' _ret = InternalCalls.' + InternalCallName + '(' + ArgList + ');')
      else
        Lines.Add('                InternalCalls.' + InternalCallName + '(' + ArgList + ');');

      // Success path.
      Lines.Add('                output.WriteUInt8(WireStatus.Ok);');
      if f.IsFunction then
      begin
        WriterMethod := ABI_Type_To_CSharp_Writer_Method(f.ReturnType);
        Lines.Add('                output.' + WriterMethod + '(_ret);');
      end;

      // Error path.
      Lines.Add('            }');
      Lines.Add('            catch (Exception ex)');
      Lines.Add('            {');
      Lines.Add('                output.WriteUInt8(WireStatus.Error);');
      Lines.Add('                output.WriteString(ex.Message);');
      Lines.Add('            }');
      Lines.Add('        }');
    end;

    Lines.Add('    }');
    Lines.Add('');

    // =========================================================================
    // 8. Service - registration
    // =========================================================================
    Lines.Add('    // =====================================================================');
    Lines.Add('    // Service - registration entry points.');
    Lines.Add('    // =====================================================================');
    Lines.Add('    public static class Service');
    Lines.Add('    {');

    // RegisterAllABIAPIs
    Lines.Add('        /// <summary>');
    Lines.Add('        /// Register every generated API on the given AppHandle.');
    Lines.Add('        /// </summary>');
    Lines.Add('        /// <remarks>');
    Lines.Add('        /// AppHandle.RegisterCall returns false when a name is');
    Lines.Add('        /// already taken. The generated names are unique, so a');
    Lines.Add('        /// failure here indicates a user-supplied AppHandle that');
    Lines.Add('        /// already has conflicting registrations.');
    Lines.Add('        /// </remarks>');
    Lines.Add('        public static void RegisterAllABIAPIs(AppHandle app)');
    Lines.Add('        {');
    Lines.Add('            if (app == null) throw new ArgumentNullException(nameof(app));');

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

      CallbackName := 'Callbacks.' + ApiName;
      Description := GetFullDescription(f.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + f.Name;

      Lines.Add('            app.RegisterCall(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ',');
      Lines.Add('                ' + CSharpStrLit(Description) + ',');
      Lines.Add('                ' + CallbackName + ');');
    end;

    Lines.Add('        }');
    Lines.Add('');

    // CreateAndRegisterABIApp
    Lines.Add('        /// <summary>');
    Lines.Add('        /// Create a new AppHandle and register every generated API.');
    Lines.Add('        /// The caller owns the returned handle and must dispose it.');
    Lines.Add('        /// </summary>');
    Lines.Add('        public static AppHandle CreateAndRegisterABIApp()');
    Lines.Add('        {');
    Lines.Add('            var app = new AppHandle(AppInfo.Name, AppInfo.Desc);');
    Lines.Add('            RegisterAllABIAPIs(app);');
    Lines.Add('            return app;');
    Lines.Add('        }');
    Lines.Add('    }');

    // =========================================================================
    // Close namespace
    // =========================================================================
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the C# service.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;


// =============================================================================
// README generator
// =============================================================================

function CSharpReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
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

function CSharpReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

function CSharpReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

function GenerateABIServiceCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, CsFileName: TP_String;

  // ---------------------------------------------------------------------------
  // §1. Header
  // ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - C# ABI Service Provider');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `csharp_abi_service_generator_tool.pas`');
    L.Add('> (rebuild edition); this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Service file**      : `' + CsFileName + '`');
    L.Add('> **Namespace**         : `' + NsName + '`');
    L.Add('> **Default App name**  : `' + AppName + '`');
    L.Add('> **Exposed APIs**      : ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> compile, deploy, or call this service without reading the source.');
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
    L.Add('This document describes the **C# ABI service module** that was');
    L.Add('generated from the Pascal unit `' + UnitName + '`. The module is a');
    L.Add('strongly-typed, binary-wire RPC endpoint built on top of the');
    L.Add('LingoFuse C# interface.');
    L.Add('');
    L.Add('### 1.1 What is an ABI service?');
    L.Add('');
    L.Add('An ABI service is a LingoFuse endpoint that:');
    L.Add('');
    L.Add('- exposes one or more routines as remotely callable APIs;');
    L.Add('- uses a **compact binary wire protocol** in both directions;');
    L.Add('- binds every API to a **fixed, statically-typed signature**;');
    L.Add('- requires a **matching call-side client** to invoke. The');
    L.Add('  call-side client can be generated by the paired Pascal,');
    L.Add('  Python, C++, or C# generator from the same model.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Discovery | Direct by App name on LingoFuse |');
    L.Add('| Client | Must be paired (generated from the same model) |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Implementation | C#, .NET 5+ (or .NET Core 3.0+) |');
    L.Add('| Base assembly | Rebuilt LingoFuse C# interface (`LingoFuse` namespace) |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Copy** the generated `.cs` file into your C# project. See §7.');
    L.Add('2. **Implement** every `InternalCall_*` method. See §7.2.');
    L.Add('3. **Wire up** the LingoFuse startup sequence in your own');
    L.Add('   `Main`, or use the paired test program from');
    L.Add('   `csharp_abi_test_generator_tool`. See §5.1 and §8.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + CsFileName + '` | The service module (one library file, no Main). |');
    L.Add('| `' + UnitName + '_abi_service_csharp.md` | This README. |');
    L.Add('');
    L.Add('### 1.5 File layout inside the generated module');
    L.Add('');
    L.Add('The generated file contains the following top-level types,');
    L.Add('all inside the `' + NsName + '` namespace:');
    L.Add('');
    L.Add('| Type | Purpose | Edit? |');
    L.Add('|------|---------|:-----:|');
    L.Add('| `AppInfo` | Name / Desc constants. | ⚠️ |');
    L.Add('| `WireStatus` | ABI status byte constants. | ❌ |');
    L.Add('| **`InternalCalls`** | **One stub per API. Replace the bodies.** | ✅ |');
    L.Add('| `Callbacks` | One action per API, implementing the wire protocol. | ❌ |');
    L.Add('| `Service` | `RegisterAllABIAPIs` / `CreateAndRegisterABIApp`. | ❌ |');
    L.Add('');
    L.Add('### 1.6 No Main entry point');
    L.Add('');
    L.Add('The generated file is a **pure class library**. It does NOT');
    L.Add('declare a `Program` class and does NOT declare a `Main` entry');
    L.Add('point. This is deliberate:');
    L.Add('');
    L.Add('- A C# project may have exactly one `Main`. If the service');
    L.Add('  library brought its own `Main`, any host program (or the test');
    L.Add('  program emitted by `csharp_abi_test_generator_tool`) would');
    L.Add('  collide and the compiler would emit');
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
    L.Add('| `AppHandle` | Application container with typed registration. |');
    L.Add('| `DataHandle` | RAII wrapper over the native data buffer. |');
    L.Add('| `LfIo` | Unified JSON / string I/O. |');
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
    L.Add('### 2.1 When to use a C# ABI service');
    L.Add('');
    L.Add('Use this generator when:');
    L.Add('');
    L.Add('- You have a **fixed set of C# methods** with stable signatures.');
    L.Add('- Your callers are **known in advance** (you control both sides).');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- A C# service consumed by a Python orchestrator.');
    L.Add('- A C# worker inside a larger native application.');
    L.Add('- A high-frequency producer that pushes typed events to a client.');
    L.Add('- A .NET bridge between a Pascal host and a C++ library.');
    L.Add('');
    L.Add('### 2.2 When NOT to use a C# ABI service');
    L.Add('');
    L.Add('- The API surface changes frequently: regenerate the whole chain.');
    L.Add('- Callers need to discover the API surface dynamically at runtime.');
    L.Add('- Parameters include complex types (classes, generics, collections).');
    L.Add('- The service must be reachable by arbitrary third-party clients.');
    L.Add('- The service must support multiple versions of a signature at once.');
    L.Add('');
    L.Add('### 2.3 Comparison with other RPC approaches');
    L.Add('');
    L.Add('| Approach | Typed | Binary | Self-describing | Paired client |');
    L.Add('|----------|:-----:|:------:|:---------------:|:-------------:|');
    L.Add('| This ABI service | yes | yes | no | yes (required) |');
    L.Add('| gRPC | yes | yes | yes (proto) | yes (generated) |');
    L.Add('| REST + JSON | no | no | yes | no |');
    L.Add('| Raw TCP sockets | no | yes | no | yes |');
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
    L.Add('Callbacks are invoked on a native worker thread, not the main');
    L.Add('thread. Every generated callback:');
    L.Add('');
    L.Add('- is an `Action<DataHandle, DataHandle>` registered through');
    L.Add('  `AppHandle.RegisterCall`;');
    L.Add('- is wrapped in a `try/catch` so that no managed exception');
    L.Add('  crosses the C ABI boundary;');
    L.Add('- reports failures through the ABI status byte (0xFF) rather');
    L.Add('  than through an exception.');
    L.Add('');
    L.Add('**Do not call any blocking LingoFuse function inside a callback.**');
    L.Add('Doing so deadlocks the calling worker thread. If you need to');
    L.Add('reach out to another service from inside a callback, offload the');
    L.Add('work to a `Task.Run` or a dedicated thread.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The ABI service uses a minimal, fixed binary wire format on both');
    L.Add('directions.');
    L.Add('');
    L.Add('### 4.1 Request');
    L.Add('');
    L.Add('```');
    L.Add('request = [field1][field2]...[fieldN]');
    L.Add('```');
    L.Add('');
    L.Add('Fields are serialised in the **exact order** in which they appear');
    L.Add('in the original Pascal declaration. There is no header, no length');
    L.Add('prefix, and no field tag: the receiver must know the signature to');
    L.Add('parse the payload.');
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
    L.Add('    participant C as Client');
    L.Add('    participant S as C# service');
    L.Add('    C->>C: write fields (little-endian)');
    L.Add('    C->>S: LF_CallEx(payload)');
    L.Add('    S->>S: input.ReadXxx()');
    L.Add('    S->>S: InternalCalls.InternalCall_xxx(a, b)');
    L.Add('    S->>S: output.WriteUInt8(WireStatus.Ok)');
    L.Add('    S->>S: output.WriteXxx(result)');
    L.Add('    S-->>C: response');
    L.Add('    C->>C: read status + result');
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
    L.Add('The call side raises `LingoFuseException` (or the language');
    L.Add('equivalent) with the decoded message.');
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
    L.Add('    subgraph CSharpService["C# service process (host program)"]');
    L.Add('        P_MAIN["Main(args) in YOUR project"]');
    L.Add('        P_LOAD["Framework.ResetPrepare + Framework.PrepareService"]');
    L.Add('        P_APP["Service.CreateAndRegisterABIApp()"]');
    L.Add('        P_CLI["Framework.PrepareClient(endpoint, app)"]');
    L.Add('        P_RUN["Framework.PrepareDone()"]');
    L.Add('        P_CBK["Action&lt;DataHandle, DataHandle&gt; callbacks"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["Client process (external)"]');
    L.Add('        C_CLI["Framework.PrepareClient(endpoint, null)"]');
    L.Add('        C_RUN["Framework.PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;ApiName&gt;(args)"]');
    L.Add('    end');
    L.Add('');
    L.Add('    P_MAIN --> P_LOAD --> P_APP --> P_CLI --> P_RUN');
    L.Add('    P_RUN --> P_CBK');
    L.Add('    C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "LF_CallEx over IPC" .-> P_CBK');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (C# service)');
    L.Add('');
    L.Add('The generated service library does not own a `Main`. The host');
    L.Add('program must perform the following five steps before the service');
    L.Add('is live:');
    L.Add('');
    L.Add('```csharp');
    L.Add('using ' + NsName + ';');
    L.Add('using LingoFuse;');
    L.Add('');
    L.Add('// 1. Reset any previous preparation state.');
    L.Add('Framework.ResetPrepare();');
    L.Add('');
    L.Add('// 2. Prepare the C4 service on the endpoint.');
    L.Add('string endpoint = "ipc:" + AppInfo.Name;');
    L.Add('Framework.PrepareService(endpoint, endpoint);');
    L.Add('');
    L.Add('// 3. Create the App and register every generated API.');
    L.Add('AppHandle app = Service.CreateAndRegisterABIApp();');
    L.Add('// (app is null only if the native layer ran out of memory)');
    L.Add('');
    L.Add('// 4. Connect a local client to the endpoint.');
    L.Add('Framework.PrepareClient(endpoint, app);');
    L.Add('');
    L.Add('// 5. Start the simulated main thread.');
    L.Add('if (Framework.PrepareDone() != 1) { /* handle failure */ }');
    L.Add('```');
    L.Add('');
    L.Add('The paired test program from `csharp_abi_test_generator_tool`');
    L.Add('performs exactly this sequence, so you can copy its `Main` as a');
    L.Add('starting point.');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The client serialises the parameters and calls `LF_CallEx`.');
    L.Add('2. LingoFuse routes the payload to the matching');
    L.Add('   `Action<DataHandle, DataHandle>` callback.');
    L.Add('3. The callback deserialises the parameters with `input.ReadXxx`.');
    L.Add('4. It calls the namespace-level `InternalCall_<Api>` method.');
    L.Add('5. The method runs the real C# body.');
    L.Add('6. The callback writes `WireStatus.Ok` and the serialised result.');
    L.Add('7. On any exception, the callback writes `WireStatus.Error` and');
    L.Add('   the UTF-8 error message.');
    L.Add('');
    L.Add('### 5.3 Threading notes');
    L.Add('');
    L.Add('- Callbacks execute on a LingoFuse worker thread.');
    L.Add('- Never let a managed exception escape into the C ABI boundary.');
    L.Add('- Do not block the callback for long periods: it holds a');
    L.Add('  worker thread from the LingoFuse pool.');
    L.Add('- Do not call `Framework.Call` / `Framework.Notify` from inside');
    L.Add('  a callback.');
    L.Add('- If you need to touch a UI or main-thread state, marshal the');
    L.Add('  work through your framework''s dispatcher.');
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
    L.Add('Every parameter and return type of every exposed API must be in');
    L.Add('this table. Any other type causes the **entire routine** to be');
    L.Add('silently dropped during generation.');
    L.Add('');
    L.Add('| ABI type | C# type | Reader | Writer | Wire size |');
    L.Add('|----------|---------|--------|--------|-----------|');
    L.Add('| `integer` | `int` | `input.ReadInt32()` | `output.WriteInt32()` | 4 bytes |');
    L.Add('| `longint` | `int` | `input.ReadInt32()` | `output.WriteInt32()` | 4 bytes |');
    L.Add('| `int64` | `long` | `input.ReadInt64()` | `output.WriteInt64()` | 8 bytes |');
    L.Add('| `cardinal` | `uint` | `input.ReadUInt32()` | `output.WriteUInt32()` | 4 bytes |');
    L.Add('| `dword` | `uint` | `input.ReadUInt32()` | `output.WriteUInt32()` | 4 bytes |');
    L.Add('| `longword` | `uint` | `input.ReadUInt32()` | `output.WriteUInt32()` | 4 bytes |');
    L.Add('| `word` | `ushort` | `input.ReadUInt16()` | `output.WriteUInt16()` | 2 bytes |');
    L.Add('| `smallint` | `short` | `input.ReadInt16()` | `output.WriteInt16()` | 2 bytes |');
    L.Add('| `byte` | `byte` | `input.ReadUInt8()` | `output.WriteUInt8()` | 1 byte |');
    L.Add('| `uint64` | `ulong` | `input.ReadUInt64()` | `output.WriteUInt64()` | 8 bytes |');
    L.Add('| `double` | `double` | `input.ReadDouble()` | `output.WriteDouble()` | 8 bytes |');
    L.Add('| `single` | `float` | `input.ReadSingle()` | `output.WriteSingle()` | 4 bytes |');
    L.Add('| `extended` | `double` | `input.ReadDouble()` | `output.WriteDouble()` | 8 bytes |');
    L.Add('| `real` | `double` | `input.ReadDouble()` | `output.WriteDouble()` | 8 bytes |');
    L.Add('| `string` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `ansistring` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `unicodestring` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `tpascalstring` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `tupascalstring` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `tp_string` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `pchar` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `pansichar` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('| `pwidechar` | `string` | `input.ReadString()` | `output.WriteString()` | variable + NUL |');
    L.Add('');
    L.Add('### 6.2 Unsupported types');
    L.Add('');
    L.Add('Anything not in §6.1 causes the **entire routine** to be');
    L.Add('silently dropped during generation. Common examples:');
    L.Add('');
    L.Add('- `bool`');
    L.Add('- `List<T>`, `Dictionary<K,V>`, `HashSet<T>`, arrays');
    L.Add('- Custom classes and structs');
    L.Add('- `Nullable<T>`, tuples, `ValueTuple`');
    L.Add('- `DateTime`, `TimeSpan`, `decimal`');
    L.Add('- Pointers, delegates, function pointers');
    L.Add('');
    L.Add('**Workaround**: serialise complex values into a `string` first');
    L.Add('(JSON or a custom format), then pass the string across the ABI');
    L.Add('boundary. On the call side, deserialise the string back into');
    L.Add('the rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The ABI wire format uses little-endian for all integers and');
    L.Add('floats. Every supported platform is little-endian, so the');
    L.Add('generated code never performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('String parameters and return values are written and read by');
    L.Add('`DataHandle.WriteString` and `DataHandle.ReadString`.');
    L.Add('`WriteString` always appends a single `0x00` byte after the');
    L.Add('UTF-8 payload. `ReadString` scans forward until it finds that');
    L.Add('byte, or consumes the entire remaining buffer when no NUL is');
    L.Add('present (matching the Pascal / Python / C++ readers).');
    L.Add('');
    L.Add('**Recommendation**: always use the provided helpers. Do not');
    L.Add('hand-roll the string encoding.');
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
    L.Add('my_csharp_service/');
    L.Add('  ' + CsFileName + '            <- generated (described here)');
    L.Add('  Program.cs                                     <- your own Main');
    L.Add('  my_csharp_service.csproj');
    L.Add('  LingoFuse64.dll                                <- Windows');
    L.Add('  liblingofuse.so                                <- Linux');
    L.Add('  liblingofuse.dylib                             <- macOS');
    L.Add('  z_ipc_64.dll / libz_ipc_64.so                  <- ZNetV2');
    L.Add('  // and the LingoFuse C# interface files (see §7.4)');
    L.Add('```');
    L.Add('');
    L.Add('### 7.2 Implementing the InternalCall_* stubs');
    L.Add('');
    L.Add('The generated `InternalCalls` class contains one stub per API:');
    L.Add('');
    L.Add('```csharp');
    L.Add('public static int InternalCall_Add(int a, int b)');
    L.Add('{');
    L.Add('    // TODO: replace the body with a call to the real function.');
    L.Add('    //     return MyEngine.Add(a, b);');
    L.Add('    return 0;');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('Two options are available:');
    L.Add('');
    L.Add('**Option A (default)** — edit the placeholder body in place.');
    L.Add('Replace the `// TODO` comment and the `return <default>;` line');
    L.Add('with a call to the real method. The signature can stay as it is.');
    L.Add('');
    L.Add('**Option B** — move the bodies into a separate class. Because');
    L.Add('`InternalCalls` is a `public static` class, your new class can');
    L.Add('reference it from anywhere. Alternatively, delete the stub');
    L.Add('bodies from the generated file and provide your own partial');
    L.Add('declarations in a second file (declare `InternalCalls` as');
    L.Add('`static partial` in both places).');
    L.Add('');
    L.Add('### 7.3 Providing your own Main');
    L.Add('');
    L.Add('Because the generated service file does not contain a `Main`,');
    L.Add('your project must supply one. The simplest form is to copy the');
    L.Add('`Program.Main` body from the paired test program emitted by');
    L.Add('`csharp_abi_test_generator_tool`. For a minimal hand-written');
    L.Add('entry point, see §5.1.');
    L.Add('');
    L.Add('If you do NOT want to write your own `Main`, use the test');
    L.Add('program:');
    L.Add('');
    L.Add('```bash');
    L.Add('cp ' + NormalizedUnit + '_abi_service_test___.cs Program.cs');
    L.Add('```');
    L.Add('');
    L.Add('This gives you a working console entry point without any extra');
    L.Add('effort.');
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
    L.Add('### 7.5 Build commands');
    L.Add('');
    L.Add('**dotnet CLI:**');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet new console -o my_csharp_service');
    L.Add('cp ' + CsFileName + ' my_csharp_service/');
    L.Add('cp LingoFuse64.dll my_csharp_service/       # or .so / .dylib');
    L.Add('cd my_csharp_service');
    L.Add('# write your own Program.cs, or copy the paired test program:');
    L.Add('cp ../' + NormalizedUnit + '_abi_service_test___.cs Program.cs');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('**MSBuild / Visual Studio:**');
    L.Add('');
    L.Add('1. Create a new Console App project targeting .NET 5+.');
    L.Add('2. Add the generated `.cs` file to the project.');
    L.Add('3. Add the LingoFuse C# interface (see §7.4).');
    L.Add('4. Add a `Program.cs` with a `Main` (your own, or the paired');
    L.Add('   test program).');
    L.Add('5. Copy `LingoFuse64.dll` (or the `.so` / `.dylib`) to the');
    L.Add('   project output directory, or mark it "Copy if newer" in');
    L.Add('   the project file.');
    L.Add('6. Build and run.');
    L.Add('');
    L.Add('### 7.6 Runtime library location');
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
    L.Add('### 7.7 Shutdown');
    L.Add('');
    L.Add('The recommended shutdown sequence is:');
    L.Add('');
    L.Add('1. `Framework.ExitMainThread();`');
    L.Add('2. `app.Dispose();`');
    L.Add('3. `Framework.Shutdown();`');
    L.Add('');
    L.Add('Do not skip any step.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Testing
  // ---------------------------------------------------------------------------
  procedure EmitTesting;
  begin
    L.Add('## 8. Testing');
    L.Add('');
    L.Add('The recommended way to test the service is to use the paired');
    L.Add('test program emitted by `csharp_abi_test_generator_tool.pas`.');
    L.Add('');
    L.Add('### 8.1 Service test');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet new console -o ' + NormalizedUnit + '_service_test');
    L.Add('cd ' + NormalizedUnit + '_service_test');
    L.Add('cp ../generated/' + CsFileName + ' .');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_service_test___.cs Program.cs');
    L.Add('cp ../runtime/LingoFuse64.dll .            # or .so / .dylib');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName + ' ABI service test ===');
    L.Add('[OK] Service ready on ipc:' + AppName + '.');
    L.Add('[OK] Registered ' + umlIntToStr(Length(SupportedFuncs)).Text + ' API(s).');
    L.Add('[OK] Press Enter to shut down.');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Call test');
    L.Add('');
    L.Add('In a second terminal:');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet new console -o ' + NormalizedUnit + '_call_test');
    L.Add('cd ' + NormalizedUnit + '_call_test');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_call.cs .');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_call_test___.cs Program.cs');
    L.Add('cp ../runtime/LingoFuse64.dll .');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName + ' ABI client test ===');
    L.Add('[OK] Connected. Calling ' + umlIntToStr(Length(SupportedFuncs)).Text + ' API(s).');
    L.Add('...');
    L.Add('=== Summary ===');
    L.Add('Passed: ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('Failed: 0');
    L.Add('[OK] Client test complete.');
    L.Add('```');
    L.Add('');
    L.Add('See `' + UnitName + '_abi_test_csharp.md` for the full test guide.');
    L.Add('');
    L.Add('### 8.3 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path, make a call with a deliberately');
    L.Add('truncated payload (for example, pass an empty string where a');
    L.Add('non-empty value is expected). The callback responds with');
    L.Add('`WireStatus.Error` and the client raises its language-equivalent');
    L.Add('exception.');
    L.Add('');
    L.Add('### 8.4 Unit-level testing of a callback');
    L.Add('');
    L.Add('To exercise a callback without a full LingoFuse deployment, use');
    L.Add('the `DataHandle` and `AppHandle` types directly:');
    L.Add('');
    L.Add('```csharp');
    L.Add('// Create two temporary data handles for the test.');
    L.Add('using var input  = new DataHandle("' + AppName + '");');
    L.Add('using var output = new DataHandle("' + AppName + '");');
    L.Add('');
    L.Add('// Write the request bytes with input.WriteXxx(...).');
    L.Add('input.Position = 0;');
    L.Add('');
    L.Add('// Call the callback directly.');
    L.Add('Callbacks.<ApiName>(input, output);');
    L.Add('');
    L.Add('// Read the response bytes with output.ReadXxx().');
    L.Add('output.Position = 0;');
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
    PName, PTyp: TP_String;
    UsedNames: TPascalStringList;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this service exposes no APIs.**');
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

    L.Add('Total APIs: **' + umlIntToStr(Length(SupportedFuncs)).Text + '**.');
    L.Add('');
    L.Add('Every API is exposed as a LingoFuse Call API with the same');
    L.Add('name. The callbacks are registered automatically by');
    L.Add('`Service.RegisterAllABIAPIs`.');
    L.Add('');

    // ---- Summary --------------------------------------------------------
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');

    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      ShortDesc := CSharpReadmeTableCell(GetFullDescription(Func.Comment));
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

        FuncDesc := CSharpReadmeParagraph(GetFullDescription(Func.Comment));

        ParamDecl := '';
        for jj := 0 to High(Func.Params) do
        begin
          PName := MakeSafeCSharpParamName(Func.Params[jj].Name, jj);
          PTyp := ABI_Type_To_CSharp_Decl(Func.Params[jj].PascalType);
          if jj > 0 then
            ParamDecl := ParamDecl + ', ';
          ParamDecl := ParamDecl + PTyp + ' ' + PName;
        end;

        L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
        L.Add('');

        if Func.IsFunction then
        begin
          RetDecl := ABI_Type_To_CSharp_Decl(Func.ReturnType);
          L.Add('- **Stub**: `public static ' + RetDecl + ' InternalCall_' + ApiNm
            + '(' + ParamDecl + ')`');
          L.Add('- **Kind**: function; returns `' + RetDecl + '`');
        end
        else
        begin
          L.Add('- **Stub**: `public static void InternalCall_' + ApiNm
            + '(' + ParamDecl + ')`');
          L.Add('- **Kind**: procedure');
        end;
        L.Add('- **Callback**: `Callbacks.' + ApiNm + '`');
        L.Add('- **Raises**: nothing; failures are encoded as `WireStatus.Error`.');
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
              + ' | ' + CSharpReadmeWireSizeText(Func.Params[jj].PascalType)
              + ' |';
            L.Add(RowStr);
          end;
          L.Add('');
        end;

        L.Add('#### Request layout');
        L.Add('');
        L.Add('```');
        if Length(Func.Params) = 0 then
          L.Add('(empty payload)')
        else
        begin
          RowStr := '';
          for jj := 0 to High(Func.Params) do
          begin
            PName := MakeSafeCSharpParamName(Func.Params[jj].Name, jj);
            if RowStr <> '' then RowStr := RowStr + ' ';
            RowStr := RowStr + '[' + PName + ': ' + Func.Params[jj].PascalType + ']';
          end;
          L.Add(RowStr);
        end;
        L.Add('```');
        L.Add('');

        L.Add('#### Success response layout');
        L.Add('');
        L.Add('```');
        if Func.IsFunction then
          L.Add('[WireStatus.Ok] [result: ' + ABI_Type_To_CSharp_Decl(Func.ReturnType) + ']')
        else
          L.Add('[WireStatus.Ok]');
        L.Add('```');
        L.Add('');

        L.Add('#### Error response');
        L.Add('');
        L.Add('`WireStatus.Error` (0xFF) followed by a UTF-8 message terminated');
        L.Add('by `0x00`. The call side raises an exception with the decoded');
        L.Add('message.');
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
    L.Add('| `CS0017: Program has more than one entry point` | Both the service library and a host/test file declare a `Main` | The generated service library has no `Main`. If you still see this error, an old copy of the file (from an earlier generator version) is present. Delete it and regenerate. |');
    L.Add('| `CS0246: type or namespace ''AppHandle'' not found` | The LingoFuse C# interface is not referenced | Add the interface assembly reference, or include its source files in the project (see §7.4). |');
    L.Add('| `CS0029: Cannot implicitly convert type ''X'' to ''Y''` at the `_ret` declaration | An old copy of the file was generated by a buggy version of the generator | Regenerate the file. The current version recomputes the return type for every callback. |');
    L.Add('| `CS1503: Argument 1: cannot convert from ''X'' to ''Y''` at `output.WriteXxx(_ret)` | Same as above | Regenerate the file. |');
    L.Add('| `DllNotFoundException: LingoFuse64.dll` | Runtime library not on the search path | Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` next to the executable. |');
    L.Add('| `BadImageFormatException` | Architecture mismatch (32-bit vs 64-bit) | Use the matching runtime for your platform. |');
    L.Add('| `Framework.PrepareDone` returns 0 | Service already running in this process | Reuse the existing runtime, or call `Framework.Shutdown` first. |');
    L.Add('| Client `PrepareDone` returns 0 | C# service not running | Start the C# service before the client. |');
    L.Add('| `LingoFuseCallException: nil (timeout)` | App name mismatch | Check `AppInfo.Name` on the service and `ABI.TargetApp` on the client. |');
    L.Add('| `LingoFuseCallException: "input truncated"` | Fewer fields than expected | Verify the client writes every parameter. |');
    L.Add('| `LingoFuseException: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| String parameters read as empty | Missing NUL terminator | Use `output.WriteString` on the writer side. |');
    L.Add('| Callback never fires | `InternalCall_*` stub not filled | Search for `TODO` in the generated `.cs`. |');
    L.Add('| Callback crashes the process | Managed exception escaped the boundary | The generated wrapper is `try/catch`-protected; check that no exception is raised outside it. |');
    L.Add('| UI update crashes the service | Worker thread touching UI | Marshal UI updates to the main thread. |');
    L.Add('| AppHandle.RegisterCall returned false | API name already registered | The generated names are unique; a false return indicates a user-supplied AppHandle with conflicting registrations. |');
    L.Add('');
    L.Add('### 10.2 Verifying a running service');
    L.Add('');
    L.Add('Before making a call, from the client side:');
    L.Add('');
    L.Add('```csharp');
    L.Add('if (!LingoFuseStatus.CheckMainThread())');
    L.Add('    Console.Error.WriteLine("Main thread is not running");');
    L.Add('');
    L.Add('if (!LingoFuseStatus.CheckApp("' + AppName + '"))');
    L.Add('    Console.Error.WriteLine("Service App not registered");');
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
    L.Add('### 10.4 Enabling verbose logging');
    L.Add('');
    L.Add('In your `Main`, before starting the service:');
    L.Add('');
    L.Add('```csharp');
    L.Add('Framework.SetOption("ConsoleOutput", "True");');
    L.Add('Framework.SetOption("Quiet", "False");');
    L.Add('```');
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
    L.Add('| 1 | What does the C# ABI service expose? | §1 |');
    L.Add('| 2 | When should I choose ABI instead of a JSON-based RPC? | §2 |');
    L.Add('| 3 | Which .NET runtime and platforms are supported? | §3 |');
    L.Add('| 4 | What are the two bytes that frame every response? | §4.2 |');
    L.Add('| 5 | Which method do I call to create the App? | §5.1 |');
    L.Add('| 6 | What happens if a parameter type is not in the whitelist? | §6.2 |');
    L.Add('| 7 | What LingoFuse C# types does the generated code use? | §1.7 |');
    L.Add('| 8 | How do I implement an InternalCall_* stub? | §7.2 |');
    L.Add('| 9 | Does the generated service library contain a Main? | §1.6, §7.3 |');
    L.Add('| 10 | How do I add the LingoFuse C# interface to my project? | §7.4 |');
    L.Add('| 11 | What is the shutdown order? | §7.7 |');
    L.Add('| 12 | How do I test the service? | §8 |');
    L.Add('| 13 | How do I invoke a specific API from the call side? | §9 |');
    L.Add('| 14 | What does the call side raise on failure? | §4.5 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('C# ABI service.');
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
    L.Add('| `csharp_abi_call_generator_tool.pas` | Paired C# call-side generator |');
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
    L.Add('End of document. Generated by `csharp_abi_service_generator_tool.pas`');
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
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';
  CsFileName := NormalizedUnit + '_abi_service.cs';

  Log(PFormat('GenerateABIServiceCsharpReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABIServiceCsharpReadme: %d valid APIs',
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

  Log(PFormat('GenerateABIServiceCsharpReadme: %d lines generated', [L.Count]));
end;

end.
