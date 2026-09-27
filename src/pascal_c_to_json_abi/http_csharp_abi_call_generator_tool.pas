unit http_csharp_abi_call_generator_tool;

// ============================================================================
// http_csharp_abi_call_generator_tool
// ----------------------------------------------------------------------------
// LingoFuse HTTP/JSON ABI Call-Side Generator for C#.
//
// Consumes a TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI) and
// produces two artifacts:
//
//   1. A single self-contained C# source file that provides one typed
//      free function per supported routine. Each function sends a JSON
//      request to a remote HTTP/JSON service through the LingoFuse
//      HTTP bridge (bridge.py) and returns the deserialized result.
//
//   2. A Markdown README describing the outbound wire protocol, the
//      type mapping, deployment, testing, and the per-API reference.
//
// DESIGN: The generated code uses the official LingoFuse .NET binding
// (namespace LingoFuse) rather than direct HTTP or raw P/Invoke. The
// transport layer routes through the LingoFuse mesh to the bridge's
// outbound proxy. This mirrors the Pascal and C++ call generators,
// which also reach the bridge through the LingoFuse mesh, and it
// keeps the client independent of any HTTP client library.
//
//   - AppHandle  : RAII application container.
//   - DataHandle : RAII data buffer.
//   - LfIo       : The single sanctioned JSON/string I/O path.
//   - Framework  : Process-wide lifecycle facade.
//
// WIRE PROTOCOL (matches every HTTP/JSON generator in this toolchain:
// Pascal, Python, JavaScript, C++):
//
//   What the caller sends to the bridge's outbound proxy:
//
//     {
//       "url":     "http://127.0.0.1:8081/<app>",
//       "method":  "POST",
//       "body":    { "args": [v1, v2, ...] },
//       "timeout": 25
//     }
//
//   What the bridge returns to the caller:
//
//     {
//       "status_code": 200,
//       "headers":     { ... },
//       "body":        { "code": 0, "result": ... }
//     }
//
//   The body carries the service's own response envelope:
//
//     { "code": 0,  "result": <value> }   on success
//     { "code": -1, "error":  "<message>" } on failure
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
// entry point. It is meant to be referenced by a caller-supplied
// program that first initializes LingoFuse.
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

// GenerateHTTPCallCsharpCode - generate the C# HTTP/JSON call module.
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPCallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallCsharpReadme - generate the user-facing README.
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPCallCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_csharp_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_csharp_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

// ABI_Type_To_Result_Extractor - the JsonResult helper method name used
// to convert the "result" JsonElement into the declared C# type.
function ABI_Type_To_Result_Extractor(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'AsInt32'
  else if T.Same('int64') then
    Result := 'AsInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'AsUInt32'
  else if T.Same('word') then
    Result := 'AsUInt16'
  else if T.Same('smallint') then
    Result := 'AsInt16'
  else if T.Same('byte') then
    Result := 'AsByte'
  else if T.Same('uint64') then
    Result := 'AsUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'AsDouble'
  else if T.Same('single') then
    Result := 'AsSingle'
  else if ABI_Type_Is_String(T) then
    Result := 'AsString'
  else
    Result := '';
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

// BuildCSharpArgsArray - "new object[] { a, b }" or "Array.Empty<object>()".
function BuildCSharpArgsArray(const Params: TParamArray): TP_String;
begin
  if Length(Params) = 0 then
    Result := 'Array.Empty<object>()'
  else
    Result := 'new object[] { ' + BuildCSharpArgList(Params) + ' }';
end;

// BuildPascalDecl - full Pascal declaration, used by the README only.
function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeCSharpParamName(F.Params[i].Name, i);
    decl := F.Params[i].PascalType;
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
// C# CALL MODULE GENERATOR
// ============================================================================

// EmitCSharpHeader - module docstring and usings.
procedure EmitCSharpHeader(Lines: TPascalStringList;
  const UnitName, NsName, DefaultBaseUrl: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('// Auto-generated by http_csharp_abi_call_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI call-side module for C#.');
  Lines.Add('//');
  Lines.Add('// This module uses the official LingoFuse .NET binding (namespace');
  Lines.Add('// LingoFuse) rather than direct HTTP or raw P/Invoke. The transport');
  Lines.Add('// layer routes through the LingoFuse mesh to the bridge''s outbound');
  Lines.Add('// proxy, mirroring the Pascal and C++ call generators.');
  Lines.Add('//');
  Lines.Add('// Required caller-side initialization (once per process):');
  Lines.Add('//');
  Lines.Add('//     Framework.SetOption("Wait_Connection_ReadyOk", "True");');
  Lines.Add('//     Framework.SetOption("Overlap_Connection", "True");');
  Lines.Add('//     Framework.ResetPrepare();');
  Lines.Add('//     Framework.PrepareClient("<endpoint>", null);   // pure consumer');
  Lines.Add('//     if (Framework.PrepareDone() != 1) { /* fatal */ }');
  Lines.Add('//');
  Lines.Add('// Then any generated function can be called.');
  Lines.Add('//');
  Lines.Add('// Wire protocol (matches every HTTP/JSON generator in this toolchain:');
  Lines.Add('// Pascal, Python, JavaScript, C++):');
  Lines.Add('//');
  Lines.Add('//   Caller -> bridge:');
  Lines.Add('//     { "url": <base> + "/" + <api>, "method": "POST",');
  Lines.Add('//       "body": {"args": [v1, v2, ...]}, "timeout": <sec> }');
  Lines.Add('//');
  Lines.Add('//   Bridge -> caller:');
  Lines.Add('//     { "status_code": 200, "headers": {...},');
  Lines.Add('//       "body": { "code": 0, "result": <value> } }');
  Lines.Add('//');
  Lines.Add('// The body carries the target service''s own response envelope.');
  Lines.Add('//');
  Lines.Add('// This file contains NO Main entry point. It is meant to be');
  Lines.Add('// compiled as a class library alongside a caller-supplied program.');
  Lines.Add('//');
  Lines.Add('// Target framework: .NET 8.0 or later.');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('using System;');
  Lines.Add('using System.Text.Json;');
  Lines.Add('using System.Threading.Tasks;');
  Lines.Add('using LingoFuse;');
  Lines.Add('');
  Lines.Add('namespace ' + NsName.Text);
  Lines.Add('{');
  Lines.Add('');
end;

// EmitCSharpException - HTTPCallError.
procedure EmitCSharpException(Lines: TPascalStringList);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // HTTPCallError - raised on any failure.');
  Lines.Add('    //');
  Lines.Add('    // Code:');
  Lines.Add('    //   -1  transport-level failure (network, bridge unreachable, timeout,');
  Lines.Add('    //       or a service-side exception forwarded by the bridge).');
  Lines.Add('    //   -2  request shape error (empty URL, un-serializable body).');
  Lines.Add('    //   -4  bridge protocol error (malformed envelope, missing field).');
  Lines.Add('    //   any other value: a service-defined error code forwarded from the');
  Lines.Add('    //       service''s { "code": N, "error": "..." } response.');
  Lines.Add('    //');
  Lines.Add('    // HttpStatus:');
  Lines.Add('    //   the HTTP status code of the response, or 0 if no HTTP response was');
  Lines.Add('    //   produced.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public sealed class HTTPCallError : Exception');
  Lines.Add('    {');
  Lines.Add('        public int Code { get; }');
  Lines.Add('        public int HttpStatus { get; }');
  Lines.Add('');
  Lines.Add('        public HTTPCallError(string message)');
  Lines.Add('            : this(message, -1, 0) { }');
  Lines.Add('');
  Lines.Add('        public HTTPCallError(string message, int code)');
  Lines.Add('            : this(message, code, 0) { }');
  Lines.Add('');
  Lines.Add('        public HTTPCallError(string message, int code, int httpStatus)');
  Lines.Add('            : base(message)');
  Lines.Add('        {');
  Lines.Add('            Code = code;');
  Lines.Add('            HttpStatus = httpStatus;');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

// EmitCSharpConfig - HttpJsonCallConfig.
procedure EmitCSharpConfig(Lines: TPascalStringList; const DefaultBaseUrl: TP_String);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // HttpJsonCallConfig - global configuration.');
  Lines.Add('    //');
  Lines.Add('    // Set BaseUrl once at startup, before any call. The other settings');
  Lines.Add('    // are optional overrides with sensible defaults.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class HttpJsonCallConfig');
  Lines.Add('    {');
  Lines.Add('        // Base URL of the target service. The full URL for API "X" is');
  Lines.Add('        // BaseUrl.TrimEnd(''/'') + "/" + "X".');
  Lines.Add('        public static string BaseUrl = ' + CSharpStrLit(DefaultBaseUrl) + ';');
  Lines.Add('');
  Lines.Add('        // LingoFuse App name of the bridge.');
  Lines.Add('        public static string BridgeAppName = "__lf_http_bridge__";');
  Lines.Add('');
  Lines.Add('        // LingoFuse API name of the bridge''s outbound POST proxy.');
  Lines.Add('        public static string BridgeApiName = "__lf_outbound_post__";');
  Lines.Add('');
  Lines.Add('        // Timeout, in milliseconds, for the LingoFuse round trip that');
  Lines.Add('        // carries the request to the bridge and the response back.');
  Lines.Add('        public static ulong CallTimeoutMs = 60000;');
  Lines.Add('');
  Lines.Add('        // Outbound HTTP timeout, in seconds, sent inside the bridge');
  Lines.Add('        // request. Must be smaller than CallTimeoutMs / 1000 by a');
  Lines.Add('        // comfortable margin.');
  Lines.Add('        public static double HttpTimeoutSec = 25.0;');
  Lines.Add('');
  Lines.Add('        // When true, logs every request URL to standard error.');
  Lines.Add('        public static bool DebugLog = false;');
  Lines.Add('    }');
  Lines.Add('');
end;

// EmitCSharpTransport - internal HttpJsonTransport class.
procedure EmitCSharpTransport(Lines: TPascalStringList);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // HttpJsonTransport - internal transport layer.');
  Lines.Add('    //');
  Lines.Add('    // This is the single point where every generated function enters');
  Lines.Add('    // the LingoFuse mesh. It builds the bridge request, sends it via');
  Lines.Add('    // Framework.Call, unwraps the bridge envelope, validates the service');
  Lines.Add('    // response, and returns the "result" field as a JsonElement.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    internal static class HttpJsonTransport');
  Lines.Add('    {');
  Lines.Add('        public static JsonElement Call(string apiName, object[] args)');
  Lines.Add('        {');
  Lines.Add('            string baseUrl = HttpJsonCallConfig.BaseUrl ?? string.Empty;');
  Lines.Add('            string url = baseUrl.TrimEnd(''/'') + "/" + apiName;');
  Lines.Add('');
  Lines.Add('            // Step 1: build the bridge request body.');
  Lines.Add('            var bridgeRequest = new');
  Lines.Add('            {');
  Lines.Add('                url = url,');
  Lines.Add('                method = "POST",');
  Lines.Add('                body = new { args = args },');
  Lines.Add('                timeout = (int)Math.Ceiling(');
  Lines.Add('                    HttpJsonCallConfig.HttpTimeoutSec)');
  Lines.Add('            };');
  Lines.Add('');
  Lines.Add('            if (HttpJsonCallConfig.DebugLog)');
  Lines.Add('            {');
  Lines.Add('                Console.Error.WriteLine(');
  Lines.Add('                    "[HttpJsonCall] POST " + url);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 2: wrap it in a DataHandle and send through the bridge.');
  Lines.Add('            JsonElement envelope;');
  Lines.Add('            using (var param = new DataHandle(');
  Lines.Add('                HttpJsonCallConfig.BridgeApiName))');
  Lines.Add('            {');
  Lines.Add('                LfIo.WriteJson(param, bridgeRequest);');
  Lines.Add('');
  Lines.Add('                using var response = Framework.Call(');
  Lines.Add('                    HttpJsonCallConfig.BridgeAppName,');
  Lines.Add('                    param,');
  Lines.Add('                    HttpJsonCallConfig.CallTimeoutMs);');
  Lines.Add('');
  Lines.Add('                if (response.Size == 0)');
  Lines.Add('                {');
  Lines.Add('                    throw new HTTPCallError(');
  Lines.Add('                        "Call returned an empty handle (timeout or " +');
  Lines.Add('                        "bridge unreachable)", -1, 0);');
  Lines.Add('                }');
  Lines.Add('');
  Lines.Add('                // Step 3: parse the bridge envelope.');
  Lines.Add('                try');
  Lines.Add('                {');
  Lines.Add('                    envelope = LfIo.ReadJson<JsonElement>(response);');
  Lines.Add('                }');
  Lines.Add('                catch (LingoFuseException ex)');
  Lines.Add('                {');
  Lines.Add('                    throw new HTTPCallError(');
  Lines.Add('                        "Invalid bridge response: " + ex.Message,');
  Lines.Add('                        -1, 0);');
  Lines.Add('                }');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 4: bridge-level error (no "status_code" field).');
  Lines.Add('            if (envelope.ValueKind == JsonValueKind.Object');
  Lines.Add('                && !envelope.TryGetProperty("status_code", out _)');
  Lines.Add('                && envelope.TryGetProperty("error", out var bridgeErr)');
  Lines.Add('                && bridgeErr.ValueKind == JsonValueKind.String)');
  Lines.Add('            {');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    bridgeErr.GetString() ?? "bridge reported an error",');
  Lines.Add('                    -1, 0);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 5: extract HTTP status (default 200).');
  Lines.Add('            int httpStatus = 200;');
  Lines.Add('            if (envelope.ValueKind == JsonValueKind.Object');
  Lines.Add('                && envelope.TryGetProperty("status_code", out var statusElem)');
  Lines.Add('                && statusElem.ValueKind == JsonValueKind.Number)');
  Lines.Add('            {');
  Lines.Add('                httpStatus = statusElem.GetInt32();');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 6: extract the target service''s response body.');
  Lines.Add('            if (envelope.ValueKind != JsonValueKind.Object');
  Lines.Add('                || !envelope.TryGetProperty("body", out var body))');
  Lines.Add('            {');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "Bridge envelope has no ''body'' field",');
  Lines.Add('                    -4, httpStatus);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            if (body.ValueKind != JsonValueKind.Object)');
  Lines.Add('            {');
  Lines.Add('                // The target returned a non-JSON body (an HTTP error');
  Lines.Add('                // page, an image, plain text). Report it as an HTTP');
  Lines.Add('                // error rather than a protocol error.');
  Lines.Add('                string bodyPreview = body.ValueKind == JsonValueKind.String');
  Lines.Add('                    ? (body.GetString() ?? string.Empty)');
  Lines.Add('                    : body.GetRawText();');
  Lines.Add('                if (bodyPreview.Length > 200)');
  Lines.Add('                    bodyPreview = bodyPreview.Substring(0, 200);');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "Service returned a non-JSON body (HTTP " +');
  Lines.Add('                    httpStatus + "): " + bodyPreview,');
  Lines.Add('                    -1, httpStatus);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 7: validate the service''s response envelope.');
  Lines.Add('            if (!body.TryGetProperty("code", out var codeElem)');
  Lines.Add('                || codeElem.ValueKind != JsonValueKind.Number)');
  Lines.Add('            {');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "Service response has no integer ''code'' field",');
  Lines.Add('                    -4, httpStatus);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            int serviceCode = codeElem.GetInt32();');
  Lines.Add('            if (serviceCode != 0)');
  Lines.Add('            {');
  Lines.Add('                string msg = "service reported an error";');
  Lines.Add('                if (body.TryGetProperty("error", out var errElem)');
  Lines.Add('                    && errElem.ValueKind == JsonValueKind.String)');
  Lines.Add('                {');
  Lines.Add('                    msg = errElem.GetString() ?? msg;');
  Lines.Add('                }');
  Lines.Add('                throw new HTTPCallError(msg, serviceCode, httpStatus);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 8: check the HTTP status after the service code, so');
  Lines.Add('            // that a 200 with code != 0 is reported with the service''s');
  Lines.Add('            // own error message.');
  Lines.Add('            if (httpStatus < 200 || httpStatus >= 300)');
  Lines.Add('            {');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "HTTP " + httpStatus, -1, httpStatus);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 9: return the result.');
  Lines.Add('            if (!body.TryGetProperty("result", out var result))');
  Lines.Add('            {');
  Lines.Add('                // A procedure has no result. Return a JSON null so');
  Lines.Add('                // that the caller''s type conversion can be a no-op.');
  Lines.Add('                return default;');
  Lines.Add('            }');
  Lines.Add('            return result;');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

// EmitCSharpResultHelpers - JsonResult typed extractors.
procedure EmitCSharpResultHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // JsonResult - typed converters from JsonElement to C# values.');
  Lines.Add('    //');
  Lines.Add('    // Each converter accepts only the JSON shapes that the service');
  Lines.Add('    // side would actually produce for the declared Pascal type. An');
  Lines.Add('    // integer result must be a JSON number (or a numeric string; the');
  Lines.Add('    // bridge may re-serialize through a generic JSON parser that');
  Lines.Add('    // stringifies large values). A string result must be a JSON string.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    internal static class JsonResult');
  Lines.Add('    {');
  Lines.Add('        public static long AsInt64(JsonElement e)');
  Lines.Add('        {');
  Lines.Add('            if (e.ValueKind == JsonValueKind.Number)');
  Lines.Add('            {');
  Lines.Add('                if (e.TryGetInt64(out var l)) return l;');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "Result does not fit in a 64-bit signed integer",');
  Lines.Add('                    -1, 200);');
  Lines.Add('            }');
  Lines.Add('            if (e.ValueKind == JsonValueKind.String');
  Lines.Add('                && long.TryParse(e.GetString(), out var s))');
  Lines.Add('            {');
  Lines.Add('                return s;');
  Lines.Add('            }');
  Lines.Add('            throw new HTTPCallError(');
  Lines.Add('                "Result is not an integer", -1, 200);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static int AsInt32(JsonElement e)');
  Lines.Add('            => checked((int)AsInt64(e));');
  Lines.Add('');
  Lines.Add('        public static short AsInt16(JsonElement e)');
  Lines.Add('            => checked((short)AsInt64(e));');
  Lines.Add('');
  Lines.Add('        public static byte AsByte(JsonElement e)');
  Lines.Add('            => checked((byte)AsInt64(e));');
  Lines.Add('');
  Lines.Add('        public static ulong AsUInt64(JsonElement e)');
  Lines.Add('        {');
  Lines.Add('            if (e.ValueKind == JsonValueKind.Number)');
  Lines.Add('            {');
  Lines.Add('                if (e.TryGetUInt64(out var u)) return u;');
  Lines.Add('                if (e.TryGetInt64(out var l) && l >= 0) return (ulong)l;');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "Result does not fit in a 64-bit unsigned integer",');
  Lines.Add('                    -1, 200);');
  Lines.Add('            }');
  Lines.Add('            if (e.ValueKind == JsonValueKind.String');
  Lines.Add('                && ulong.TryParse(e.GetString(), out var s))');
  Lines.Add('            {');
  Lines.Add('                return s;');
  Lines.Add('            }');
  Lines.Add('            throw new HTTPCallError(');
  Lines.Add('                "Result is not an unsigned integer", -1, 200);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static uint AsUInt32(JsonElement e)');
  Lines.Add('            => checked((uint)AsUInt64(e));');
  Lines.Add('');
  Lines.Add('        public static ushort AsUInt16(JsonElement e)');
  Lines.Add('            => checked((ushort)AsUInt64(e));');
  Lines.Add('');
  Lines.Add('        public static double AsDouble(JsonElement e)');
  Lines.Add('        {');
  Lines.Add('            if (e.ValueKind == JsonValueKind.Number)');
  Lines.Add('                return e.GetDouble();');
  Lines.Add('            if (e.ValueKind == JsonValueKind.String');
  Lines.Add('                && double.TryParse(e.GetString(), out var s))');
  Lines.Add('            {');
  Lines.Add('                return s;');
  Lines.Add('            }');
  Lines.Add('            throw new HTTPCallError(');
  Lines.Add('                "Result is not a number", -1, 200);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static float AsSingle(JsonElement e)');
  Lines.Add('            => (float)AsDouble(e);');
  Lines.Add('');
  Lines.Add('        public static string AsString(JsonElement e)');
  Lines.Add('        {');
  Lines.Add('            if (e.ValueKind == JsonValueKind.String)');
  Lines.Add('                return e.GetString() ?? string.Empty;');
  Lines.Add('            if (e.ValueKind == JsonValueKind.Null)');
  Lines.Add('                return string.Empty;');
  Lines.Add('            throw new HTTPCallError(');
  Lines.Add('                "Result is not a string", -1, 200);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

// EmitCSharpApi - the API class with one sync + one async method per
// supported routine.
procedure EmitCSharpApi(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  f: TFunctionStructure;
  ApiName, ParamDecl, ArgList, ArgsArrayExpr: TP_String;
  RetType, Extractor: TP_String;
  Description: TP_String;
  HasParams: boolean;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // API - typed remote call functions.');
  Lines.Add('    //');
  Lines.Add('    // Every routine is exposed as two methods:');
  Lines.Add('    //   * <ApiName>Async(...)  returns Task<T>; runs on the thread pool.');
  Lines.Add('    //   * <ApiName>(...)       blocks and returns T directly.');
  Lines.Add('    //');
  Lines.Add('    // Both variants raise HTTPCallError on any failure.');
  Lines.Add('    //');
  Lines.Add('    // The class is stateless and thread-safe. Any number of threads');
  Lines.Add('    // may call the functions concurrently.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class API');
  Lines.Add('    {');

  for i := 0 to High(SupportedFuncs) do
  begin
    f := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(f.Params) > 0;
    ParamDecl := BuildCSharpParamList(f.Params);
    ArgList := BuildCSharpArgList(f.Params);
    ArgsArrayExpr := BuildCSharpArgsArray(f.Params);
    RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);
    Extractor := ABI_Type_To_Result_Extractor(f.ReturnType);

    Description := GetFullDescription(f.Comment);

    Lines.Add('');

    // ---- Doc comment ------------------------------------------------------
    Lines.Add('        /// <summary>');
    if Description.Len > 0 then
      Lines.Add('        /// ' + Description.Text)
    else
      Lines.Add('        /// HTTP/JSON API: ' + ApiName);
    Lines.Add('        /// </summary>');
    Lines.Add('        /// <remarks>');
    Lines.Add('        /// HTTP route: <c>POST /' + ApiName + '</c> (relative to the');
    Lines.Add('        /// configured <see cref="HttpJsonCallConfig.BaseUrl"/>).');
    Lines.Add('        /// </remarks>');

    // ---- Sync method ------------------------------------------------------
    if f.IsFunction then
    begin
      if HasParams then
        Lines.Add('        public static ' + RetType + ' ' + ApiName +
          '(' + ParamDecl + ')')
      else
        Lines.Add('        public static ' + RetType + ' ' + ApiName + '()');
      Lines.Add('        {');
      Lines.Add('            var result = HttpJsonTransport.Call(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ', ' + ArgsArrayExpr + ');');
      Lines.Add('            return JsonResult.' + Extractor + '(result);');
      Lines.Add('        }');
    end
    else
    begin
      if HasParams then
        Lines.Add('        public static void ' + ApiName + '(' + ParamDecl + ')')
      else
        Lines.Add('        public static void ' + ApiName + '()');
      Lines.Add('        {');
      Lines.Add('            HttpJsonTransport.Call(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ', ' + ArgsArrayExpr + ');');
      Lines.Add('        }');
    end;

    Lines.Add('');

    // ---- Async method -----------------------------------------------------
    if f.IsFunction then
    begin
      if HasParams then
        Lines.Add('        public static Task<' + RetType + '> ' + ApiName +
          'Async(' + ParamDecl + ')')
      else
        Lines.Add('        public static Task<' + RetType + '> ' + ApiName + 'Async()');
      Lines.Add('        {');
      if HasParams then
        Lines.Add('            return Task.Run(() => ' + ApiName + '(' + ArgList + '));')
      else
        Lines.Add('            return Task.Run(() => ' + ApiName + '());');
      Lines.Add('        }');
    end
    else
    begin
      if HasParams then
        Lines.Add('        public static Task ' + ApiName + 'Async(' + ParamDecl + ')')
      else
        Lines.Add('        public static Task ' + ApiName + 'Async()');
      Lines.Add('        {');
      if HasParams then
        Lines.Add('            return Task.Run(() => ' + ApiName + '(' + ArgList + '));')
      else
        Lines.Add('            return Task.Run(() => ' + ApiName + '());');
      Lines.Add('        }');
    end;
  end;

  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPCallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, DefaultBaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_call';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating C# HTTP/JSON call module for unit "%s"', [UnitName.Text]));

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

    EmitCSharpHeader(Lines, UnitName, NsName, DefaultBaseUrl);
    EmitCSharpException(Lines);
    EmitCSharpConfig(Lines, DefaultBaseUrl);
    EmitCSharpTransport(Lines);
    EmitCSharpResultHelpers(Lines);
    EmitCSharpApi(Lines, SupportedFuncs, ApiNames);

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
// C# CALL README GENERATOR
// ============================================================================

function GenerateHTTPCallCsharpReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, DefaultBaseUrl: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamWire: TP_String;
  CsFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  PascalDecl, CSharpSig: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallCsharpReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallCsharpReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_call';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  CsFileName := NormalizedUnit + '_http_json_call.cs';

  Log(PFormat('Generating HTTP/JSON C# call README for unit "%s"', [UnitName.Text]));

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
    Lines.Add('# ' + UnitName.Text + ' - C# HTTP/JSON Call-Side Wrapper');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_csharp_abi_call_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Call module file**  : `' + CsFileName.Text + '`');
    Lines.Add('> **Namespace**         : `' + NsName.Text + '`');
    Lines.Add('> **Default base URL**  : `' + DefaultBaseUrl.Text + '`');
    Lines.Add('> **Exposed functions** : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('> **Target framework**  : .NET 8.0 or later');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // 1. Overview
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **call-side wrapper** that was generated');
    Lines.Add('from the Pascal unit `' + UnitName.Text + '`. The module exposes one');
    Lines.Add('typed C# function per supported routine in the source. Each');
    Lines.Add('generated function sends a JSON request to a remote HTTP/JSON');
    Lines.Add('service through the LingoFuse HTTP bridge (`bridge.py`), parses the');
    Lines.Add('response, and returns the result as a native C# value.');
    Lines.Add('');
    Lines.Add('### 1.1 Design');
    Lines.Add('');
    Lines.Add('The module uses the official LingoFuse .NET binding');
    Lines.Add('(namespace `LingoFuse`) rather than direct HTTP or raw P/Invoke:');
    Lines.Add('');
    Lines.Add('- The transport layer routes through the LingoFuse mesh to the');
    Lines.Add('  bridge''s outbound proxy.');
    Lines.Add('- This mirrors the Pascal and C++ call generators, which also');
    Lines.Add('  reach the bridge through the LingoFuse mesh.');
    Lines.Add('- The client is independent of any HTTP client library.');
    Lines.Add('');
    Lines.Add('### 1.2 What the generated module contains');
    Lines.Add('');
    Lines.Add('| Type | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `HTTPCallError` | The only exception raised on failure. |');
    Lines.Add('| `HttpJsonCallConfig` | Global configuration knobs. |');
    Lines.Add('| `HttpJsonTransport` | Internal: the single point of transport. |');
    Lines.Add('| `JsonResult` | Internal: typed JsonElement converters. |');
    Lines.Add('| **`API`** | **One sync + one async method per remote API.** |');
    Lines.Add('');
    Lines.Add('### 1.3 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + CsFileName.Text + '` | The call module (import and use). |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_call_csharp.md` | This README. |');
    Lines.Add('');

    // 2. Quick Start
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Prepare LingoFuse (once per process)');
    Lines.Add('');
    Lines.Add('The generated module talks to the bridge through the LingoFuse');
    Lines.Add('mesh, so the caller must initialize LingoFuse first. The caller');
    Lines.Add('is a pure consumer: no application needs to be exposed.');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('using LingoFuse;');
    Lines.Add('');
    Lines.Add('Framework.SetOption("Wait_Connection_ReadyOk", "True");');
    Lines.Add('Framework.SetOption("Overlap_Connection", "True");');
    Lines.Add('Framework.ResetPrepare();');
    Lines.Add('Framework.PrepareClient("<endpoint>", null);  // null = no app');
    Lines.Add('');
    Lines.Add('if (Framework.PrepareDone() != 1)');
    Lines.Add('{');
    Lines.Add('    Console.Error.WriteLine("LingoFuse init failed");');
    Lines.Add('    return;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `<endpoint>` must match the bridge''s `--endpoint` argument.');
    Lines.Add('');
    Lines.Add('### 2.2 Configure the client');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('using ' + NsName.Text + ';');
    Lines.Add('');
    Lines.Add('HttpJsonCallConfig.BaseUrl = ' + CSharpStrLit(DefaultBaseUrl) + ';');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The default already points at the local bridge, with the source');
    Lines.Add('unit''s name as the target application.');
    Lines.Add('');
    Lines.Add('### 2.3 Make a call');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('try');
    Lines.Add('{');
    Lines.Add('    var result = API.<ApiName>(/* args */);');
    Lines.Add('    Console.WriteLine(result);');
    Lines.Add('}');
    Lines.Add('catch (HTTPCallError e)');
    Lines.Add('{');
    Lines.Add('    Console.Error.WriteLine(');
    Lines.Add('        "Call failed: " + e.Message +');
    Lines.Add('        " (code=" + e.Code + ", http=" + e.HttpStatus + ")");');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 2.4 Make an async call');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('var result = await API.<ApiName>Async(/* args */);');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The async variants run the blocking transport on the thread pool,');
    Lines.Add('so they are safe to call from an async context.');
    Lines.Add('');

    // 3. Compatibility
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('| Requirement | Value |');
    Lines.Add('|-------------|-------|');
    Lines.Add('| .NET | 8.0 or later |');
    Lines.Add('| LingoFuse binding | LingoFuse.dll (namespace `LingoFuse`) |');
    Lines.Add('| bridge.py | Running and reachable via the LingoFuse mesh |');
    Lines.Add('| Native LingoFuse library | Installed next to the executable, or on the loader search path |');
    Lines.Add('');
    Lines.Add('### 3.1 Threading model');
    Lines.Add('');
    Lines.Add('The synchronous API blocks the calling thread until the response');
    Lines.Add('arrives or the timeout expires. The asynchronous variants offload');
    Lines.Add('the blocking call to the thread pool.');
    Lines.Add('');
    Lines.Add('Different threads may call different functions concurrently. The');
    Lines.Add('generated module holds no mutable state, so no synchronization is');
    Lines.Add('required.');
    Lines.Add('');
    Lines.Add('`HttpJsonCallConfig` fields are plain static fields. Set them once');
    Lines.Add('at startup, before any call. Changing them at runtime is not');
    Lines.Add('thread-safe.');
    Lines.Add('');

    // 4. Wire protocol
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The call module speaks **plain-text JSON** on both directions,');
    Lines.Add('transported through the LingoFuse mesh to the bridge.');
    Lines.Add('');
    Lines.Add('### 4.1 URL composition');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('HttpJsonCallConfig.BaseUrl.TrimEnd(''/'') + "/" + <api-name>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.2 Outbound request (caller -> bridge)');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "url":     "<base> + ''/'' + <api-name>",');
    Lines.Add('  "method":  "POST",');
    Lines.Add('  "body":    { "args": [v1, v2, ..., vN] },');
    Lines.Add('  "timeout": <HttpTimeoutSec>');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.3 Inbound response (bridge -> caller)');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "status_code": 200,');
    Lines.Add('  "headers":     { ... },');
    Lines.Add('  "body":        { "code": 0, "result": <value> }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `body` field carries the target service''s own response');
    Lines.Add('envelope.');
    Lines.Add('');
    Lines.Add('### 4.4 Error model');
    Lines.Add('');
    Lines.Add('Every failure mode is translated into `HTTPCallError`:');
    Lines.Add('');
    Lines.Add('| Condition | `Code` | `HttpStatus` |');
    Lines.Add('|-----------|:------:|:------------:|');
    Lines.Add('| LingoFuse call timed out | `-1` | `0` |');
    Lines.Add('| Bridge App unreachable | `-1` | `0` |');
    Lines.Add('| Bridge-level error (`{"error": "..."}`) | `-1` | `0` |');
    Lines.Add('| Bridge envelope has no `body` | `-4` | the bridge''s status |');
    Lines.Add('| Service returned a non-JSON body | `-1` | the bridge''s status |');
    Lines.Add('| Service response lacks an integer `code` | `-4` | the bridge''s status |');
    Lines.Add('| Service returned `code != 0` | service code | the bridge''s status |');
    Lines.Add('| HTTP status not 2xx (with `code == 0`) | `-1` | the bridge''s status |');
    Lines.Add('| Result type mismatch | `-1` | `200` |');
    Lines.Add('');
    Lines.Add('### 4.5 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant P as C# Client');
    Lines.Add('    participant M as LingoFuse Mesh');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant S as Remote Service');
    Lines.Add('    P->>M: Framework.Call("__lf_http_bridge__", req)');
    Lines.Add('    M->>B: LF_Call');
    Lines.Add('    B->>S: HTTP POST /<app>/<api>');
    Lines.Add('    Note over B,S: Body: {"args": [a, b]}');
    Lines.Add('    S-->>B: {"code": 0, "result": ...}');
    Lines.Add('    B-->>M: {"status_code": 200, "headers": {...}, "body": {...}}');
    Lines.Add('    M-->>P: LF_Call response');
    Lines.Add('    P->>P: unwrap body -> code -> result');
    Lines.Add('```');
    Lines.Add('');

    // 5. Global configuration
    Lines.Add('## 5. Global Configuration');
    Lines.Add('');
    Lines.Add('The module exposes one static configuration class.');
    Lines.Add('');
    Lines.Add('| Field | Type | Default | Purpose |');
    Lines.Add('|-------|------|---------|---------|');
    Lines.Add('| `BaseUrl` | `string` | `' + DefaultBaseUrl.Text + '` | Base URL of the target service. |');
    Lines.Add('| `BridgeAppName` | `string` | `__lf_http_bridge__` | LingoFuse App name of the bridge. |');
    Lines.Add('| `BridgeApiName` | `string` | `__lf_outbound_post__` | Bridge''s outbound proxy API name. |');
    Lines.Add('| `CallTimeoutMs` | `ulong` | `60000` | LingoFuse round-trip timeout. |');
    Lines.Add('| `HttpTimeoutSec` | `double` | `25.0` | HTTP timeout inside the bridge request. |');
    Lines.Add('| `DebugLog` | `bool` | `false` | Log every request URL to stderr. |');
    Lines.Add('');
    Lines.Add('Set `BaseUrl` first. The other fields rarely need changing.');
    Lines.Add('');

    // 6. Error handling
    Lines.Add('## 6. Error Handling');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('public sealed class HTTPCallError : Exception');
    Lines.Add('{');
    Lines.Add('    public int Code { get; }');
    Lines.Add('    public int HttpStatus { get; }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 6.1 Recommended catch pattern');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('try');
    Lines.Add('{');
    Lines.Add('    var result = API.SomeApi(/* args */);');
    Lines.Add('    // use result');
    Lines.Add('}');
    Lines.Add('catch (HTTPCallError e)');
    Lines.Add('{');
    Lines.Add('    if (e.Code == -1 && e.HttpStatus == 0)');
    Lines.Add('        Console.Error.WriteLine("Network error: " + e.Message);');
    Lines.Add('    else if (e.Code == -4)');
    Lines.Add('        Console.Error.WriteLine("Protocol error: " + e.Message);');
    Lines.Add('    else');
    Lines.Add('        Console.Error.WriteLine(');
    Lines.Add('            "Remote error (code " + e.Code + "): " + e.Message);');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');

    // 7. Deployment
    Lines.Add('## 7. Deployment');
    Lines.Add('');
    Lines.Add('### 7.1 Directory layout');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('my_csharp_client/');
    Lines.Add('  ' + CsFileName.Text + '      <- generated (described here)');
    Lines.Add('  Program.cs                                <- your Main');
    Lines.Add('  my_csharp_client.csproj');
    Lines.Add('  LingoFuse.dll                             <- binding');
    Lines.Add('  LingoFuse64.dll / liblingofuse.so         <- native library');
    Lines.Add('  z_ipc_64.dll / libz_ipc_64.so');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.2 Build');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('dotnet new console -o my_csharp_client');
    Lines.Add('cp ' + CsFileName.Text + ' my_csharp_client/');
    Lines.Add('cd my_csharp_client');
    Lines.Add('dotnet add reference ../LingoFuse/LingoFuse.csproj');
    Lines.Add('# write your own Program.cs');
    Lines.Add('dotnet run');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.3 Starting the bridge');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 bridge.py --endpoint <endpoint> --port 8081 --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `--endpoint` must match the value you passed to');
    Lines.Add('`Framework.PrepareClient`.');
    Lines.Add('');

    // 8. Testing
    Lines.Add('## 8. Testing');
    Lines.Add('');
    Lines.Add('### 8.1 Complete client program');
    Lines.Add('');
    Lines.Add('```csharp');
    Lines.Add('using System;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName.Text + ';');
    Lines.Add('');
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    static int Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Framework.SetOption("Wait_Connection_ReadyOk", "True");');
    Lines.Add('        Framework.SetOption("Overlap_Connection", "True");');
    Lines.Add('        Framework.ResetPrepare();');
    Lines.Add('        Framework.PrepareClient("<endpoint>", null);');
    Lines.Add('');
    Lines.Add('        if (Framework.PrepareDone() != 1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("LingoFuse init failed");');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        HttpJsonCallConfig.BaseUrl = ' + CSharpStrLit(DefaultBaseUrl) + ';');
    Lines.Add('');
    Lines.Add('        try');
    Lines.Add('        {');
    Lines.Add('            // Replace with actual calls to the generated functions.');
    Lines.Add('        }');
    Lines.Add('        catch (HTTPCallError e)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[ERROR] " + e.Message);');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('        finally');
    Lines.Add('        {');
    Lines.Add('            NetworkEvents.Clear();');
    Lines.Add('            Framework.ExitMainThread();');
    Lines.Add('            Framework.Shutdown();');
    Lines.Add('        }');
    Lines.Add('        return 0;');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.2 Verifying failure paths');
    Lines.Add('');
    Lines.Add('Three failure modes worth testing explicitly:');
    Lines.Add('');
    Lines.Add('1. **Bridge unreachable**: stop the bridge and call any API.');
    Lines.Add('   Expect `HTTPCallError` with `Code = -1` and `HttpStatus = 0`.');
    Lines.Add('2. **Service-side exception**: call an API whose stub throws.');
    Lines.Add('   Expect `HTTPCallError` with the exception message and');
    Lines.Add('   `Code = -1` or the service''s own code.');
    Lines.Add('3. **Unknown API**: call a name that does not exist. The bridge');
    Lines.Add('   returns `-3` from its pre-check; expect `HTTPCallError` with');
    Lines.Add('   `Code = -3`.');
    Lines.Add('');

    // 9. API reference
    Lines.Add('## 9. API Reference');
    Lines.Add('');
    Lines.Add('Total functions: **' + MdInt(FuncCount).Text + '**.');
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
        Lines.Add('### 9.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('Overloads receive an `_N` suffix (`_1`, `_2`, ...) after the');
        Lines.Add('first. The first overload keeps the bare name.');
        Lines.Add('');
      end;

      Lines.Add('### 9.1 Summary');
      Lines.Add('');
      Lines.Add('| # | Function | Kind | Params | Returns |');
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

        Lines.Add('### 9.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');
        Lines.Add('- **Pascal source**: `' + PascalDecl.Text + '`');
        Lines.Add('- **C# signature**: `' + CSharpSig.Text + '`');
        Lines.Add('- **HTTP route**: `POST /<app>/' + ApiName.Text + '`');
        Lines.Add('- **Raises**: `HTTPCallError` on any failure');
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

        Lines.Add('#### Example');
        Lines.Add('');
        Lines.Add('```csharp');
        Lines.Add('try');
        Lines.Add('{');
        if F.IsFunction then
        begin
          if HasParams then
            Lines.Add('    var result = API.' + ApiName + '(' + CallArgs + ');')
          else
            Lines.Add('    var result = API.' + ApiName + '();');
        end
        else
        begin
          if HasParams then
            Lines.Add('    API.' + ApiName + '(' + CallArgs + ');')
          else
            Lines.Add('    API.' + ApiName + '();');
        end;
        Lines.Add('}');
        Lines.Add('catch (HTTPCallError e)');
        Lines.Add('{');
        Lines.Add('    Console.Error.WriteLine("Call failed: " + e.Message);');
        Lines.Add('}');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    // 10. Troubleshooting
    Lines.Add('## 10. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| `DllNotFoundException: LingoFuse64.dll` | Native library not found | Copy it next to the executable |');
    Lines.Add('| `Framework.PrepareDone() != 1` | LingoFuse already running, or init failed | Check `LingoFuseStatus.CheckMainThread()`; use `Framework.Shutdown` between cycles |');
    Lines.Add('| `HTTPCallError: Call returned an empty handle` | Bridge unreachable or LingoFuse call timed out | Start `bridge.py`; verify `Framework.PrepareClient` endpoint |');
    Lines.Add('| `HTTPCallError: ... code=-3` | Bridge pre-check failed | Add `--no-precheck` to the bridge |');
    Lines.Add('| `HTTPCallError: Bridge envelope has no ''body''` | Bridge-level error | Check the bridge log |');
    Lines.Add('| `HTTPCallError: Service returned a non-JSON body` | Target URL does not point at a HTTP/JSON service | Verify `BaseUrl` |');
    Lines.Add('| Result value is truncated | JSON number exceeds the declared C# type | Widen the return type on the service side |');
    Lines.Add('');

    // 11. For AI agents
    Lines.Add('## 11. For AI Agents');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('artifact:');
    Lines.Add('  type: csharp_http_json_client');
    Lines.Add('  module_file: ' + CsFileName.Text);
    Lines.Add('  namespace: ' + NsName.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  default_base_url: ' + DefaultBaseUrl.Text);
    Lines.Add('  target_framework: ".NET 8.0+"');
    Lines.Add('  binding: LingoFuse (namespace LingoFuse)');
    Lines.Add('');
    Lines.Add('caller_prerequisites:');
    Lines.Add('  - ''Framework.SetOption("Wait_Connection_ReadyOk", "True")''');
    Lines.Add('  - ''Framework.SetOption("Overlap_Connection", "True")''');
    Lines.Add('  - ''Framework.ResetPrepare()''');
    Lines.Add('  - ''Framework.PrepareClient("<endpoint>", null)''');
    Lines.Add('  - ''Framework.PrepareDone() == 1''');
    Lines.Add('');
    Lines.Add('global_configuration:');
    Lines.Add('  HttpJsonCallConfig.BaseUrl: "str"');
    Lines.Add('  HttpJsonCallConfig.BridgeAppName: "str, default ''__lf_http_bridge__''"');
    Lines.Add('  HttpJsonCallConfig.BridgeApiName: "str, default ''__lf_outbound_post__''"');
    Lines.Add('  HttpJsonCallConfig.CallTimeoutMs: "ulong, default 60000"');
    Lines.Add('  HttpJsonCallConfig.HttpTimeoutSec: "double, default 25.0"');
    Lines.Add('  HttpJsonCallConfig.DebugLog: "bool, default false"');
    Lines.Add('');
    Lines.Add('outbound_request:');
    Lines.Add('  transport: Framework.Call(BridgeAppName, param, CallTimeoutMs)');
    Lines.Add('  param_api_name: BridgeApiName');
    Lines.Add('  param_body: ''{"url":...,"method":"POST","body":{"args":[...]},"timeout":...}''');
    Lines.Add('');
    Lines.Add('inbound_response:');
    Lines.Add('  bridge_envelope: ''{"status_code":...,"headers":...,"body":...}''');
    Lines.Add('  service_success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  service_failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('exception:');
    Lines.Add('  type: HTTPCallError');
    Lines.Add('  fields:');
    Lines.Add('    Code: "int, -1/-4 or a service code"');
    Lines.Add('    HttpStatus: "int, 0 for transport errors"');
    Lines.Add('');
    Lines.Add('type_map:');
    Lines.Add('  int_family: int / long / uint / ulong / short / ushort / byte');
    Lines.Add('  float_family: double / float');
    Lines.Add('  string_family: string');
    Lines.Add('  unsupported: [bool, DateTime, decimal, arrays, records, classes, enums, pointers]');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 11.1 Anti-patterns');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Calling `API.Xxx` before `Framework.PrepareDone` returns 1 | The mesh is not ready | Prepare LingoFuse first |');
    Lines.Add('| Setting `HttpJsonCallConfig.BaseUrl` after the first call | Race with in-flight calls | Set once at startup |');
    Lines.Add('| Catching `Exception` instead of `HTTPCallError` | Hides unrelated bugs | Catch `HTTPCallError` explicitly |');
    Lines.Add('| Blocking a UI thread with a sync call | UI freezes | Use the async variant, or `Task.Run` |');
    Lines.Add('| Forgetting `NetworkEvents.Clear()` before `Framework.Shutdown()` | Managed delegates stay alive | Follow the cleanup order |');
    Lines.Add('| Assuming `-4` means a network error | `-4` is a protocol error | Check `Code` and `HttpStatus` together |');
    Lines.Add('');

    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_csharp_abi_call_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated C# call README: %d lines, %d routines.',
      [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
