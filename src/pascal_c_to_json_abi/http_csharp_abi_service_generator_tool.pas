unit http_csharp_abi_service_generator_tool;

// ============================================================================
// http_csharp_abi_service_generator_tool
// ----------------------------------------------------------------------------
// LingoFuse HTTP/JSON ABI Service Provider Generator for C#.
//
// Consumes a TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI) and
// produces two artifacts:
//
//   1. A single self-contained C# source file that registers every
//      supported routine as a LingoFuse Call/Notify API and speaks the
//      cross-language HTTP/JSON wire protocol.
//
//   2. A Markdown README describing the wire protocol, the type
//      mapping, deployment, testing, and the per-API reference.
//
// DESIGN: The generated code uses the official LingoFuse .NET binding
// (namespace LingoFuse) rather than direct P/Invoke. This is the same
// binding documented in "LingoFuse C# Interface - Complete Guide".
//
//   - AppHandle  : RAII application container.
//   - DataHandle : RAII data buffer.
//   - LfIo       : The single sanctioned JSON/string I/O path.
//   - Framework  : Process-wide lifecycle facade.
//   - NetworkEvents : Process-global connect/disconnect events.
//
// WIRE PROTOCOL (matches every other HTTP/JSON generator in this
// toolchain: Pascal, Python, JavaScript, C++):
//
//   request  = {"args": [v1, v2, ...]}      positional arguments
//              {"a": v1, "b": v2, ...}      named arguments
//   response = {"code": 0, "result": ...}   on success
//              {"code": -1, "error":  ...}  on failure
//
// TYPE MAPPING (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> C# int    / JSON number
//   int64                         -> C# long   / JSON number
//   cardinal / dword / longword   -> C# uint   / JSON number
//   word                          -> C# ushort / JSON number
//   smallint                      -> C# short  / JSON number
//   byte                          -> C# byte   / JSON number
//   uint64                        -> C# ulong  / JSON number
//   double / extended / real      -> C# double / JSON number
//   single                        -> C# float  / JSON number
//   string / PChar family         -> C# string / JSON string
//
// The generated module is a PURE CLASS LIBRARY: it declares no Main
// entry point, so it can be referenced by any console, GUI, service,
// or test project without triggering CS0017.
//
// All comments and status output are in English.
//
// Author: LingoFuse-pasAgent project
// ============================================================================

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

// GenerateHTTPServiceCsharpCode - generate the C# HTTP/JSON service
// module. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPServiceCsharpReadme - generate the user-facing README.
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPServiceCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation

// ============================================================================
// Logging helpers
// ============================================================================

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_csharp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_csharp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

// ============================================================================
// ABI type family classification (mirrors every HTTP/JSON generator in
// this toolchain).
// ============================================================================

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or
    T.Same('unicodestring') or T.Same('tpascalstring') or
    T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or
    T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('longint') or
    T.Same('int64') or T.Same('cardinal') or T.Same('dword') or
    T.Same('longword') or T.Same('word') or T.Same('smallint') or
    T.Same('byte') or T.Same('uint64');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

// ABI_Type_To_CSharp_Decl - C# type name for a parameter or a return value.
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
  else if ABI_Type_Is_String(T) then
    Result := 'string'
  else
    Result := '';
end;

// ABI_Type_To_Json_Extractor - the JsonArgs helper method name used to
// pull this parameter out of the request JSON envelope.
function ABI_Type_To_Json_Extractor(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'GetInt32'
  else if T.Same('int64') then
    Result := 'GetInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'GetUInt32'
  else if T.Same('word') then
    Result := 'GetUInt16'
  else if T.Same('smallint') then
    Result := 'GetInt16'
  else if T.Same('byte') then
    Result := 'GetByte'
  else if T.Same('uint64') then
    Result := 'GetUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'GetDouble'
  else if T.Same('single') then
    Result := 'GetSingle'
  else if ABI_Type_Is_String(T) then
    Result := 'GetString'
  else
    Result := '';
end;

// ABI_Type_To_CSharp_Default - literal used in a stub body before the
// user fills it in.
function ABI_Type_To_CSharp_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if T.Same('single') then
    Result := '0.0f'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
end;

// ABI_Type_To_Json_Wire_Type - coarse wire type, used by the README only.
function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

// ============================================================================
// Identifier helpers
// ============================================================================

// MakeApiName - canonicalize a routine name into an identifier that is
// simultaneously safe as a URL path segment, a JSON object key, and an
// identifier in C#, Pascal, Python, and JavaScript.
//
// The replacement set MUST match every other generator in this
// toolchain.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
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

// CSharpStrLit - emit a complete C# string literal with surrounding
// double quotes and standard backslash escapes.
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

// ============================================================================
// Markdown helpers
// ============================================================================

function MdCellEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '|' then
      Result.Append('\|')
    else if c = #10 then
      Result.Append(' ')
    else if c = #13 then
      // Skip CR.
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// ============================================================================
// Comment description extraction
// ============================================================================

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

// ============================================================================
// Parameter helpers
// ============================================================================

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

// BuildPascalDecl - full Pascal declaration, used by the README only.
function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
  PascalType: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeCSharpParamName(F.Params[i].Name, i);
    PascalType := F.Params[i].PascalType;
    decl := PascalType;
    if i > 0 then
      ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' + F.ReturnType + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

// ============================================================================
// Supported-function filtering (mirrors every HTTP/JSON generator)
// ============================================================================

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
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not ABI_Type_Is_Supported(f.ReturnType)) then
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

// ============================================================================
// C# SERVICE MODULE GENERATOR
// ============================================================================

procedure EmitCSharpHeader(Lines: TPascalStringList;
  const UnitName, NsName, AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('// Auto-generated by http_csharp_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI service module for C#.');
  Lines.Add('//');
  Lines.Add('// This module uses the LingoFuse .NET binding (namespace LingoFuse)');
  Lines.Add('// rather than direct P/Invoke. The binding provides:');
  Lines.Add('//   * AppHandle  - RAII application container');
  Lines.Add('//   * DataHandle - RAII data buffer');
  Lines.Add('//   * LfIo       - the single sanctioned JSON/string I/O path');
  Lines.Add('//   * Framework  - process-wide lifecycle facade');
  Lines.Add('//   * NetworkEvents - process-global connect/disconnect events');
  Lines.Add('//');
  Lines.Add('// Wire protocol (both directions):');
  Lines.Add('//   request  = {"args": [v1, v2, ...]}      positional arguments');
  Lines.Add('//              {"a": v1, "b": v2, ...}      named arguments');
  Lines.Add('//   response = {"code": 0, "result": ...}   on success');
  Lines.Add('//              {"code": -1, "error":  ...}  on failure');
  Lines.Add('//');
  Lines.Add('// These shapes match the Pascal, Python, JavaScript, and C++');
  Lines.Add('// HTTP/JSON service generators, so any of them can call each');
  Lines.Add('// other through bridge.py without changes.');
  Lines.Add('//');
  Lines.Add('// This file contains NO Main entry point. It is meant to be');
  Lines.Add('// compiled as a class library. Provide your own Main that calls');
  Lines.Add('// ' + NsName.Text + '.Service.RunService(), or use the companion test');
  Lines.Add('// program generator.');
  Lines.Add('//');
  Lines.Add('// Target framework: .NET 8.0 or later.');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('using System;');
  Lines.Add('using System.Text.Json;');
  Lines.Add('using System.Threading;');
  Lines.Add('using LingoFuse;');
  Lines.Add('');
  Lines.Add('namespace ' + NsName.Text);
  Lines.Add('{');
  Lines.Add('');
end;

procedure EmitCSharpAppInfo(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // Application metadata.');
  Lines.Add('    //');
  Lines.Add('    // The AppName is the mesh-wide identifier used for routing. The');
  Lines.Add('    // Endpoint is the LingoFuse endpoint the service binds to. bridge.py');
  Lines.Add('    // must be started with the same --endpoint value.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class AppInfo');
  Lines.Add('    {');
  Lines.Add('        public const string Name = ' + CSharpStrLit(AppName) + ';');
  Lines.Add('        public const string Desc = ' + CSharpStrLit(AppDesc) + ';');
  Lines.Add('        public const string Endpoint = ' + CSharpStrLit(Endpoint) + ';');
  Lines.Add('        public const bool DebugLog = false;');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCSharpJsonArgs(Lines: TPascalStringList);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // JsonArgs - request envelope navigation helpers.');
  Lines.Add('    //');
  Lines.Add('    // The wire protocol accepts two request shapes:');
  Lines.Add('    //   {"args": [v1, v2, ...]}      positional arguments');
  Lines.Add('    //   {"a": v1, "b": v2, ...}      named arguments');
  Lines.Add('    //');
  Lines.Add('    // If the "args" field is present, positional extraction is used and');
  Lines.Add('    // named lookup is skipped. Otherwise, every parameter is looked up');
  Lines.Add('    // by its original Pascal name.');
  Lines.Add('    //');
  Lines.Add('    // Type policy (matches every other HTTP/JSON generator):');
  Lines.Add('    //   * Integer parameters accept a JSON integer or a numeric string.');
  Lines.Add('    //   * Floating-point parameters accept a JSON number only.');
  Lines.Add('    //   * String parameters accept a JSON string only.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    internal static class JsonArgs');
  Lines.Add('    {');
  Lines.Add('        // Try to get the raw JsonElement for the given parameter.');
  Lines.Add('        public static bool TryGet(JsonElement req, string name, int index,');
  Lines.Add('            out JsonElement value)');
  Lines.Add('        {');
  Lines.Add('            value = default;');
  Lines.Add('            if (req.ValueKind != JsonValueKind.Object) return false;');
  Lines.Add('');
  Lines.Add('            if (req.TryGetProperty("args", out var args))');
  Lines.Add('            {');
  Lines.Add('                if (args.ValueKind != JsonValueKind.Array) return false;');
  Lines.Add('                int i = 0;');
  Lines.Add('                foreach (var e in args.EnumerateArray())');
  Lines.Add('                {');
  Lines.Add('                    if (i == index) { value = e; return true; }');
  Lines.Add('                    i++;');
  Lines.Add('                }');
  Lines.Add('                return false;');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            if (req.TryGetProperty(name, out var named))');
  Lines.Add('            {');
  Lines.Add('                value = named;');
  Lines.Add('                return true;');
  Lines.Add('            }');
  Lines.Add('            return false;');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // Extract a 64-bit signed integer.');
  Lines.Add('        public static long GetInt64(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            switch (e.ValueKind)');
  Lines.Add('            {');
  Lines.Add('                case JsonValueKind.Number:');
  Lines.Add('                    if (e.TryGetInt64(out var l)) return l;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an integer: " + name);');
  Lines.Add('                case JsonValueKind.String:');
  Lines.Add('                    if (long.TryParse(e.GetString(), out var s)) return s;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an integer: " + name);');
  Lines.Add('                default:');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an integer: " + name);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static int GetInt32(JsonElement req, string name, int index)');
  Lines.Add('            => checked((int)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static short GetInt16(JsonElement req, string name, int index)');
  Lines.Add('            => checked((short)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static byte GetByte(JsonElement req, string name, int index)');
  Lines.Add('            => checked((byte)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static uint GetUInt32(JsonElement req, string name, int index)');
  Lines.Add('            => checked((uint)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static ushort GetUInt16(JsonElement req, string name, int index)');
  Lines.Add('            => checked((ushort)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        // Extract a 64-bit unsigned integer.');
  Lines.Add('        public static ulong GetUInt64(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            switch (e.ValueKind)');
  Lines.Add('            {');
  Lines.Add('                case JsonValueKind.Number:');
  Lines.Add('                    if (e.TryGetUInt64(out var u)) return u;');
  Lines.Add('                    if (e.TryGetInt64(out var l) && l >= 0) return (ulong)l;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an unsigned integer: " + name);');
  Lines.Add('                case JsonValueKind.String:');
  Lines.Add('                    if (ulong.TryParse(e.GetString(), out var s)) return s;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an unsigned integer: " + name);');
  Lines.Add('                default:');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an unsigned integer: " + name);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // Extract a 64-bit IEEE 754 floating-point number.');
  Lines.Add('        public static double GetDouble(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            if (e.ValueKind != JsonValueKind.Number)');
  Lines.Add('                throw new ArgumentException(');
  Lines.Add('                    "Argument is not a number: " + name);');
  Lines.Add('            return e.GetDouble();');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static float GetSingle(JsonElement req, string name, int index)');
  Lines.Add('            => (float)GetDouble(req, name, index);');
  Lines.Add('');
  Lines.Add('        // Extract a UTF-8 string.');
  Lines.Add('        public static string GetString(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            if (e.ValueKind != JsonValueKind.String)');
  Lines.Add('                throw new ArgumentException(');
  Lines.Add('                    "Argument is not a string: " + name);');
  Lines.Add('            return e.GetString() ?? "";');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCSharpStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  f: TFunctionStructure;
  ApiName, ParamDecl, ArgList, RetType: TP_String;
  Description: TP_String;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // InternalCalls - one stub per API.');
  Lines.Add('    //');
  Lines.Add('    // This is the ONLY class you are expected to edit. Replace each');
  Lines.Add('    // TODO body with a call to the real implementation, for example:');
  Lines.Add('    //     return MyNamespace.MyClass.Add(a, b);');
  Lines.Add('    //');
  Lines.Add('    // The parameter names and types are already correct. The stub');
  Lines.Add('    // body runs on a native worker thread, so it must be thread-safe');
  Lines.Add('    // and must never call a blocking LingoFuse function');
  Lines.Add('    // (Framework.Call, Framework.Notify, Framework.SequencedNotify,');
  Lines.Add('    // AppHandle.LocalCall, AppHandle.LocalNotify, Framework.PrepareDone,');
  Lines.Add('    // Framework.Shutdown).');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class InternalCalls');
  Lines.Add('    {');

  for i := 0 to High(SupportedFuncs) do
  begin
    f := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildCSharpParamList(f.Params);
    ArgList := BuildCSharpArgList(f.Params);
    RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);

    Description := GetFullDescription(f.Comment);
    if Description.Len > 0 then
      Lines.Add('        // ' + Description.Text);

    Lines.Add('');
    if f.IsFunction then
      Lines.Add('        public static ' + RetType + ' ' + ApiName + '(' + ParamDecl + ')')
    else
      Lines.Add('        public static void ' + ApiName + '(' + ParamDecl + ')');
    Lines.Add('        {');
    Lines.Add('            // TODO: replace the body with a call to the real implementation.');
    if Length(f.Params) > 0 then
      Lines.Add('            // Suggested call: ' + f.Name.Text + '(' + ArgList + ');')
    else
      Lines.Add('            // Suggested call: ' + f.Name.Text + '();');
    if f.IsFunction then
      Lines.Add('            return ' + ABI_Type_To_CSharp_Default(f.ReturnType) + ';');
    Lines.Add('        }');
  end;

  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCSharpRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  f: TFunctionStructure;
  ApiName, RetType, PName, Extractor, ParamNameLit, IdxLit: TP_String;
  Description: TP_String;
  HasParams: boolean;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // Service - registration and entry point.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class Service');
  Lines.Add('    {');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // Register every supported API on the given application.');
  Lines.Add('        //');
  Lines.Add('        // Each API is registered with a callback that reads the JSON');
  Lines.Add('        // request envelope, extracts the arguments, invokes the');
  Lines.Add('        // corresponding InternalCalls stub, and writes the JSON');
  Lines.Add('        // response envelope.');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        public static void RegisterAPIs(AppHandle app)');
  Lines.Add('        {');

  for i := 0 to High(SupportedFuncs) do
  begin
    f := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(f.Params) > 0;
    RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);
    Description := GetFullDescription(f.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    Lines.Add('');
    Lines.Add('            // ---- ' + ApiName.Text + ' ----');

    if f.IsFunction then
    begin
      Lines.Add('            app.RegisterCall(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ',');
      Lines.Add('                ' + CSharpStrLit(Description) + ',');
      Lines.Add('                (input, output) =>');
      Lines.Add('                {');
      Lines.Add('                    try');
      Lines.Add('                    {');
      Lines.Add('                        var req = LfIo.ReadJson<JsonElement>(input);');

      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        Extractor := ABI_Type_To_Json_Extractor(f.Params[j].PascalType);
        ParamNameLit := CSharpStrLit(f.Params[j].Name);
        IdxLit := umlIntToStr(j);
        Lines.Add('                        var ' + PName + ' = JsonArgs.' +
          Extractor + '(req, ' + ParamNameLit + ', ' + IdxLit + ');');
      end;

      Lines.Add('');
      if HasParams then
        Lines.Add('                        var result = InternalCalls.' + ApiName +
          '(' + BuildCSharpArgList(f.Params) + ');')
      else
        Lines.Add('                        var result = InternalCalls.' + ApiName + '();');
      Lines.Add('                        LfIo.WriteJson(output, new { code = 0, result });');
      Lines.Add('                    }');
      Lines.Add('                    catch (Exception ex)');
      Lines.Add('                    {');
      Lines.Add('                        try');
      Lines.Add('                        {');
      Lines.Add('                            LfIo.WriteJson(output, new { code = -1, error = ex.Message });');
      Lines.Add('                        }');
      Lines.Add('                        catch');
      Lines.Add('                        {');
      Lines.Add('                            // The output handle is unusable.');
      Lines.Add('                        }');
      Lines.Add('                    }');
      Lines.Add('                });');
    end
    else
    begin
      Lines.Add('            app.RegisterCall(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ',');
      Lines.Add('                ' + CSharpStrLit(Description) + ',');
      Lines.Add('                (input, output) =>');
      Lines.Add('                {');
      Lines.Add('                    try');
      Lines.Add('                    {');
      Lines.Add('                        var req = LfIo.ReadJson<JsonElement>(input);');

      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        Extractor := ABI_Type_To_Json_Extractor(f.Params[j].PascalType);
        ParamNameLit := CSharpStrLit(f.Params[j].Name);
        IdxLit := umlIntToStr(j);
        Lines.Add('                        var ' + PName + ' = JsonArgs.' +
          Extractor + '(req, ' + ParamNameLit + ', ' + IdxLit + ');');
      end;

      Lines.Add('');
      if HasParams then
        Lines.Add('                        InternalCalls.' + ApiName +
          '(' + BuildCSharpArgList(f.Params) + ');')
      else
        Lines.Add('                        InternalCalls.' + ApiName + '();');
      Lines.Add('                        LfIo.WriteJson(output, new { code = 0 });');
      Lines.Add('                    }');
      Lines.Add('                    catch (Exception ex)');
      Lines.Add('                    {');
      Lines.Add('                        try');
      Lines.Add('                        {');
      Lines.Add('                            LfIo.WriteJson(output, new { code = -1, error = ex.Message });');
      Lines.Add('                        }');
      Lines.Add('                        catch');
      Lines.Add('                        {');
      Lines.Add('                            // The output handle is unusable.');
      Lines.Add('                        }');
      Lines.Add('                    }');
      Lines.Add('                });');
    end;
  end;

  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // RunService - full startup, run loop, and clean shutdown.');
  Lines.Add('        //');
  Lines.Add('        // Returns 0 on success, 1 on a fatal startup error.');
  Lines.Add('        //');
  Lines.Add('        // Call this method from your own Main:');
  Lines.Add('        //     static int Main(string[] args)');
  Lines.Add('        //         => <namespace>.Service.RunService();');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        public static int RunService()');
  Lines.Add('        {');
  Lines.Add('            Console.WriteLine("=== " + AppInfo.Name + " HTTP/JSON service ===");');
  Lines.Add('            Console.WriteLine("Endpoint: " + AppInfo.Endpoint);');
  Lines.Add('');
  Lines.Add('            // Deployment mode: do not block waiting for peers that are not');
  Lines.Add('            // yet ready. This lets bridge.py and this service start in any');
  Lines.Add('            // order.');
  Lines.Add('            Framework.SetOption("Wait_Connection_ReadyOk", "False");');
  Lines.Add('            // Allow multiple clients on the same address so that a bridge');
  Lines.Add('            // restart does not require a service restart.');
  Lines.Add('            Framework.SetOption("Overlap_Connection", "True");');
  Lines.Add('');
  Lines.Add('            Framework.ResetPrepare();');
  Lines.Add('');
  Lines.Add('            if (Framework.PrepareService(AppInfo.Endpoint, AppInfo.Endpoint) < 0)');
  Lines.Add('            {');
  Lines.Add('                Console.Error.WriteLine("[FATAL] PrepareService failed: " + AppInfo.Endpoint);');
  Lines.Add('                return 1;');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            AppHandle? app = null;');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                app = new AppHandle(AppInfo.Name, AppInfo.Desc);');
  Lines.Add('                RegisterAPIs(app);');
  Lines.Add('');
  Lines.Add('                if (Framework.PrepareClient(AppInfo.Endpoint, app) < 0)');
  Lines.Add('                {');
  Lines.Add('                    Console.Error.WriteLine("[FATAL] PrepareClient failed: " + AppInfo.Endpoint);');
  Lines.Add('                    return 1;');
  Lines.Add('                }');
  Lines.Add('');
  Lines.Add('                if (Framework.PrepareDone() != 1)');
  Lines.Add('                {');
  Lines.Add('                    Console.Error.WriteLine("[FATAL] PrepareDone failed.");');
  Lines.Add('                    return 1;');
  Lines.Add('                }');
  Lines.Add('');
  Lines.Add('                Console.WriteLine("[OK] Service ready. Press Ctrl+C to stop.");');
  Lines.Add('');
  Lines.Add('                var stop = new ManualResetEventSlim(false);');
  Lines.Add('                Console.CancelKeyPress += (s, e) =>');
  Lines.Add('                {');
  Lines.Add('                    e.Cancel = true;');
  Lines.Add('                    stop.Set();');
  Lines.Add('                };');
  Lines.Add('');
  Lines.Add('                while (!stop.IsSet)');
  Lines.Add('                    Thread.Sleep(500);');
  Lines.Add('');
  Lines.Add('                Console.WriteLine("Shutting down...");');
  Lines.Add('                return 0;');
  Lines.Add('            }');
  Lines.Add('            finally');
  Lines.Add('            {');
  Lines.Add('                // Required cleanup order:');
  Lines.Add('                //   NetworkEvents.Clear() -> ExitMainThread');
  Lines.Add('                //   -> app.Dispose() -> Shutdown');
  Lines.Add('                try { NetworkEvents.Clear(); } catch { }');
  Lines.Add('                try { Framework.ExitMainThread(); } catch { }');
  Lines.Add('                try { app?.Dispose(); } catch { }');
  Lines.Add('                try { Framework.Shutdown(); } catch { }');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc, Endpoint: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_service';
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating C# HTTP/JSON service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    EmitCSharpHeader(Lines, UnitName, NsName, AppName, AppDesc, Endpoint);
    EmitCSharpAppInfo(Lines, AppName, AppDesc, Endpoint);
    EmitCSharpJsonArgs(Lines);
    EmitCSharpStubs(Lines, SupportedFuncs, ApiNames);
    EmitCSharpRegistration(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// ============================================================================
// C# SERVICE README GENERATOR
// ============================================================================

function GenerateHTTPServiceCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc, Endpoint: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamWire: TP_String;
  ServiceFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  PascalDecl, CSharpSig: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCsharpReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCsharpReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_service';
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  ServiceFileName := NormalizedUnit + '_http_json_service.cs';

  Log(PFormat('Generating HTTP/JSON C# service README for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  FuncCount := Length(SupportedFuncs);

  TotalParams := 0;
  for i := 0 to FuncCount - 1 do
    TotalParams := TotalParams + Length(SupportedFuncs[i].Params);

  DuplicateNameCount := 0;
  LastOriginalName := '';
  for i := 0 to FuncCount - 1 do
  begin
    if SupportedFuncs[i].Name.Same(LastOriginalName) then
      Inc(DuplicateNameCount)
    else
      LastOriginalName := SupportedFuncs[i].Name;
  end;

  Lines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // Header
    Lines.Add('# ' + UnitName.Text + ' - C# HTTP/JSON Service Provider');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_csharp_abi_service_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Service file**      : `' + ServiceFileName.Text + '`');
    Lines.Add('> **Namespace**         : `' + NsName.Text + '`');
    Lines.Add('> **Default App name**  : `' + AppName.Text + '`');
    Lines.Add('> **Default endpoint**  : `' + Endpoint.Text + '`');
    Lines.Add('> **Exposed APIs**      : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('> **Target framework**  : .NET 8.0 or later');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // 1. Overview
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **HTTP/JSON service** that was generated');
    Lines.Add('from the Pascal unit `' + UnitName.Text + '`. The service is a C#');
    Lines.Add('module that registers one or more functions as LingoFuse Call APIs,');
    Lines.Add('and is reached from HTTP clients through the LingoFuse HTTP bridge');
    Lines.Add('(`bridge.py`).');
    Lines.Add('');
    Lines.Add('### 1.1 What the generated module contains');
    Lines.Add('');
    Lines.Add('| Type | Purpose | Edit? |');
    Lines.Add('|------|---------|:-----:|');
    Lines.Add('| `AppInfo` | Constants: App name, description, endpoint. | ⚠️ optional |');
    Lines.Add('| `JsonArgs` | Request envelope navigation helpers. | ❌ |');
    Lines.Add('| **`InternalCalls`** | **One stub per API.** | ✅ |');
    Lines.Add('| `Service` | `RegisterAPIs` + `RunService` entry point. | ❌ |');
    Lines.Add('');
    Lines.Add('### 1.2 Design');
    Lines.Add('');
    Lines.Add('The module uses the official LingoFuse .NET binding');
    Lines.Add('(namespace `LingoFuse`) rather than direct P/Invoke:');
    Lines.Add('');
    Lines.Add('- `AppHandle`  - RAII application container.');
    Lines.Add('- `DataHandle` - RAII data buffer.');
    Lines.Add('- `LfIo`       - the single sanctioned JSON/string I/O path.');
    Lines.Add('- `Framework`  - process-wide lifecycle facade.');
    Lines.Add('- `NetworkEvents` - process-global connect/disconnect events.');
    Lines.Add('');
    Lines.Add('### 1.3 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + ServiceFileName.Text + '` | The service module (fill in the stubs, then compile). |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_service_csharp.md` | This README. |');
    Lines.Add('');

    // 2. Quick Start
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Add the file to a project');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('dotnet new console -o ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('cd ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('cp ../' + ServiceFileName.Text + ' .');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Add a minimal `Program.cs` with the entry point:');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('using ' + NsName.Text + ';');
    Lines.Add('');
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    static int Main(string[] args) => Service.RunService();');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 2.2 Fill in the stubs');
    Lines.Add('');
    Lines.Add('Open `' + ServiceFileName.Text + '` and locate a stub in the');
    Lines.Add('`InternalCalls` class:');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('public static int Add(int a, int b)');
    Lines.Add('{');
    Lines.Add('    // TODO: replace the body with a call to the real implementation.');
    Lines.Add('    // Suggested call: Add(a, b);');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Replace the `// TODO` line and the `return <default>;` line with');
    Lines.Add('the actual call.');
    Lines.Add('');
    Lines.Add('### 2.3 Start the bridge');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 bridge.py --endpoint ' + Endpoint.Text + ' \\');
    Lines.Add('    --port 8081 --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `--no-precheck` flag skips the bridge''s `check_api` step,');
    Lines.Add('which depends on a network broadcast that can lag by up to 3');
    Lines.Add('seconds after the service starts.');
    Lines.Add('');

    // 3. Wire protocol
    Lines.Add('## 3. Wire Protocol');
    Lines.Add('');
    Lines.Add('The C# service uses **plain-text JSON** on both directions.');
    Lines.Add('There is **no binary framing**.');
    Lines.Add('');
    Lines.Add('### 3.1 Request');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "args": [v1, v2, ..., vN] }        // positional');
    Lines.Add('{ "a": v1, "b": v2, ... }            // named');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('If the `args` field is present, positional extraction is used.');
    Lines.Add('Otherwise, every parameter is looked up by its original Pascal');
    Lines.Add('name.');
    Lines.Add('');
    Lines.Add('### 3.2 Response');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": 0,  "result": <value> }');
    Lines.Add('{ "code": -1, "error":  "<message>" }');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 3.3 Type policy');
    Lines.Add('');
    Lines.Add('| Declared type | Accepted JSON value |');
    Lines.Add('|---------------|---------------------|');
    Lines.Add('| integer | a JSON integer or a numeric string |');
    Lines.Add('| floating-point | a JSON number only |');
    Lines.Add('| string | a JSON string only |');
    Lines.Add('');
    Lines.Add('### 3.4 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant H as HTTP Client');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant S as C# Service');
    Lines.Add('    H->>B: POST /<app>/<api>');
    Lines.Add('    Note over H,B: Body: {"args": [a, b]}');
    Lines.Add('    B->>S: LF_Call with JSON payload');
    Lines.Add('    S->>S: JsonArgs.GetXxx -> InternalCalls.Xxx');
    Lines.Add('    S->>S: LfIo.WriteJson');
    Lines.Add('    S-->>B: {"code": 0, "result": ...}');
    Lines.Add('    B-->>H: HTTP 200 with JSON body');
    Lines.Add('```');
    Lines.Add('');

    // 4. Runtime architecture
    Lines.Add('## 4. Runtime Architecture');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    A["Main"] --> B["Service.RunService()"]');
    Lines.Add('    B --> C["Framework.SetOption"]');
    Lines.Add('    C --> D["Framework.ResetPrepare"]');
    Lines.Add('    D --> E["Framework.PrepareService"]');
    Lines.Add('    E --> F["new AppHandle"]');
    Lines.Add('    F --> G["Service.RegisterAPIs"]');
    Lines.Add('    G --> H["Framework.PrepareClient"]');
    Lines.Add('    H --> I["Framework.PrepareDone"]');
    Lines.Add('    I --> J["while not Ctrl+C"]');
    Lines.Add('    J --> K["NetworkEvents.Clear"]');
    Lines.Add('    K --> L["Framework.ExitMainThread"]');
    Lines.Add('    L --> M["app.Dispose"]');
    Lines.Add('    M --> N["Framework.Shutdown"]');
    Lines.Add('```');
    Lines.Add('');

    // 5. Type mapping
    Lines.Add('## 5. Type Mapping');
    Lines.Add('');
    Lines.Add('| ABI type | Pascal type | C# type | JSON wire type |');
    Lines.Add('|----------|-------------|---------|----------------|');
    Lines.Add('| `integer` | `Integer` | `int` | `number` |');
    Lines.Add('| `longint` | `LongInt` | `int` | `number` |');
    Lines.Add('| `int64` | `Int64` | `long` | `number` |');
    Lines.Add('| `cardinal` | `Cardinal` | `uint` | `number` |');
    Lines.Add('| `dword` | `DWord` | `uint` | `number` |');
    Lines.Add('| `longword` | `LongWord` | `uint` | `number` |');
    Lines.Add('| `word` | `Word` | `ushort` | `number` |');
    Lines.Add('| `smallint` | `SmallInt` | `short` | `number` |');
    Lines.Add('| `byte` | `Byte` | `byte` | `number` |');
    Lines.Add('| `uint64` | `UInt64` | `ulong` | `number` |');
    Lines.Add('| `double` | `Double` | `double` | `number` |');
    Lines.Add('| `single` | `Single` | `float` | `number` |');
    Lines.Add('| `extended` | `Extended` | `double` | `number` |');
    Lines.Add('| `real` | `Real` | `double` | `number` |');
    Lines.Add('| `string` | `string` | `string` | `string` |');
    Lines.Add('| `pchar` | `PChar` | `string` | `string` |');
    Lines.Add('');
    Lines.Add('Any type not in this table causes the entire routine to be');
    Lines.Add('silently dropped during generation.');
    Lines.Add('');

    // 6. Cleanup order
    Lines.Add('## 6. Cleanup Order');
    Lines.Add('');
    Lines.Add('The generated `Service.RunService()` performs cleanup in the');
    Lines.Add('required order:');
    Lines.Add('');
    Lines.Add('1. `NetworkEvents.Clear()`     - release managed delegate references.');
    Lines.Add('2. `Framework.ExitMainThread()` - stop the simulated main thread.');
    Lines.Add('3. `app.Dispose()`             - detach the App from the mesh.');
    Lines.Add('4. `Framework.Shutdown()`      - release the entire framework.');
    Lines.Add('');
    Lines.Add('Do not skip any step.');
    Lines.Add('');

    // 7. Testing
    Lines.Add('## 7. Testing');
    Lines.Add('');
    Lines.Add('### 7.1 Build and run');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('cd ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('dotnet run');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Expected output:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('=== ' + AppName.Text + ' HTTP/JSON service ===');
    Lines.Add('Endpoint: ' + Endpoint.Text);
    Lines.Add('[OK] Service ready. Press Ctrl+C to stop.');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.2 Issue a request');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('curl -X POST http://127.0.0.1:8081/' + AppName.Text + '/<api-name> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": [1, 2]}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.3 Verify an error path');
    Lines.Add('');
    Lines.Add('Add `throw new Exception("boom");` to a stub body, restart the');
    Lines.Add('service, and issue the request. The response should be:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": -1, "error": "boom" }');
    Lines.Add('```');
    Lines.Add('');

    // 8. API reference
    Lines.Add('## 8. API Reference');
    Lines.Add('');
    Lines.Add('Total APIs: **' + MdInt(FuncCount).Text + '**.');
    Lines.Add('');

    if FuncCount = 0 then
    begin
      Lines.Add('_No supported routines were found in the source unit._');
      Lines.Add('');
    end
    else
    begin
      if DuplicateNameCount > 0 then
      begin
        Lines.Add('### 8.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('The source unit exposes overloaded routines. The HTTP/JSON');
        Lines.Add('protocol routes by API name, so two overloads cannot both keep');
        Lines.Add('the original name. The generator appends a numeric suffix');
        Lines.Add('(`_1`, `_2`, ...) to every overload after the first.');
        Lines.Add('');
      end;

      Lines.Add('### 8.1 Summary');
      Lines.Add('');
      Lines.Add('| # | API name | Kind | Params | Returns |');
      Lines.Add('|---|----------|------|--------|---------|');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];

        if F.IsFunction then
          ParamWire := ABI_Type_To_CSharp_Decl(F.ReturnType)
        else
          ParamWire := '-';

        Lines.Add('| ' + MdInt(i + 1).Text + ' | `' + MdCellEscape(ApiName).Text + '`' +
          ' | ' + if_(F.IsFunction, 'function', 'procedure') +
          ' | ' + MdInt(Length(F.Params)).Text +
          ' | `' + MdCellEscape(ParamWire).Text + '` |');
      end;
      Lines.Add('');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        HasParams := Length(F.Params) > 0;

        PascalDecl := BuildPascalDecl(F);
        if F.IsFunction then
          CSharpSig := 'public static ' + ABI_Type_To_CSharp_Decl(F.ReturnType) +
            ' ' + ApiName + '(' + BuildCSharpParamList(F.Params) + ')'
        else
          CSharpSig := 'public static void ' + ApiName +
            '(' + BuildCSharpParamList(F.Params) + ')';
        CallArgs := BuildCSharpArgList(F.Params);

        Lines.Add('### 8.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');
        Lines.Add('- **Pascal source**: `' + PascalDecl.Text + '`');
        Lines.Add('- **C# stub**: `' + CSharpSig.Text + '`');
        Lines.Add('- **HTTP route**: `POST /' + AppName.Text + '/' + ApiName.Text + '`');
        Lines.Add('');

        Description := GetFullDescription(F.Comment);
        if Description.Len > 0 then
        begin
          Lines.Add('**Description**: ' + Description.Text);
          Lines.Add('');
        end;

        if HasParams then
        begin
          Lines.Add('| # | Name | C# type | JSON wire type |');
          Lines.Add('|---|------|---------|----------------|');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafeCSharpParamName(F.Params[j].Name, j);
            ParamType := ABI_Type_To_CSharp_Decl(F.Params[j].PascalType);
            ParamWire := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);
            Lines.Add('| ' + MdInt(j + 1).Text + ' | `' + MdCellEscape(ParamName).Text + '`' +
              ' | `' + MdCellEscape(ParamType).Text + '`' +
              ' | `' + MdCellEscape(ParamWire).Text + '` |');
          end;
          Lines.Add('');
        end;

        Lines.Add('#### Example call');
        Lines.Add('');
        Lines.Add('```bash');
        Lines.Add('curl -X POST http://127.0.0.1:8081/' + AppName.Text + '/' + ApiName.Text + ' \\');
        Lines.Add('     -H "Content-Type: application/json" \\');
        if HasParams then
          Lines.Add('     -d ''{"args": [<values for ' + CallArgs.Text + '>]}''')
        else
          Lines.Add('     -d ''{}''');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    // 9. Troubleshooting
    Lines.Add('## 9. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| `DllNotFoundException: LingoFuse64.dll` | Native library not on the search path | Copy the LingoFuse native library next to the executable |');
    Lines.Add('| `BadImageFormatException` | Architecture mismatch | Use the matching native library for your runtime |');
    Lines.Add('| `PrepareService` returned -1 | Endpoint already in use | Use a different endpoint, or stop the conflicting process |');
    Lines.Add('| `PrepareDone` returned 0 | The native main thread is already running | Not a failure; continue if `LingoFuseStatus.CheckMainThread()` returns true |');
    Lines.Add('| HTTP 404 or connection refused | Bridge not running | Start `bridge.py` |');
    Lines.Add('| `{"code": -3}` | Bridge pre-check failed | Add `--no-precheck` to the bridge |');
    Lines.Add('| `{"code": -3}` despite the service running | Bridge endpoint mismatch | Check `--endpoint` matches `' + Endpoint.Text + '` |');
    Lines.Add('| `{"code": -1, "error": "<traceback>"}` | A stub threw an exception | Check the service console |');
    Lines.Add('| Stub never fires | Not filled in | Search for `TODO` in the generated file |');
    Lines.Add('');

    // 10. For AI agents
    Lines.Add('## 10. For AI Agents');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('service:');
    Lines.Add('  app_name: ' + AppName.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  service_file: ' + ServiceFileName.Text);
    Lines.Add('  namespace: ' + NsName.Text);
    Lines.Add('  lf_endpoint: ' + Endpoint.Text);
    Lines.Add('  bridge_default_http_port: 8081');
    Lines.Add('');
    Lines.Add('binding:');
    Lines.Add('  namespace: LingoFuse');
    Lines.Add('  types_used: [AppHandle, DataHandle, LfIo, Framework, NetworkEvents]');
    Lines.Add('  direct_pinvoke: false');
    Lines.Add('');
    Lines.Add('http:');
    Lines.Add('  method: POST');
    Lines.Add('  route_format: "/<app>/<api>"');
    Lines.Add('  content_type: "application/json; charset=utf-8"');
    Lines.Add('');
    Lines.Add('request:');
    Lines.Add('  positional: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('  named: ''{"param1": v1, "param2": v2}''');
    Lines.Add('  precedence: args wins when both are present');
    Lines.Add('');
    Lines.Add('response:');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('type_map:');
    Lines.Add('  int_family: int / long / uint / ulong / short / ushort / byte');
    Lines.Add('  float_family: double / float');
    Lines.Add('  string_family: string');
    Lines.Add('  unsupported: [bool, DateTime, decimal, arrays, records, classes, enums, pointers]');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 10.1 Anti-patterns');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Blocking call inside a stub | The stub runs on a worker thread; blocking deadlocks | Offload to another thread |');
    Lines.Add('| Touching UI from a stub | The stub is not on the UI thread | Marshal to the UI thread |');
    Lines.Add('| Calling `Framework.Shutdown` before `app.Dispose` | Use-after-free | Follow the cleanup order in §6 |');
    Lines.Add('| Using `JsonSerializer` directly | Bypasses the wire contract | Use `LfIo.WriteJson` / `LfIo.ReadJson` |');
    Lines.Add('| Writing to a borrowed `DataHandle` after the callback returns | The native buffer is freed | Only use the handle inside the callback body |');
    Lines.Add('');

    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_csharp_abi_service_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated C# service README: %d lines, %d routines.',
      [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
