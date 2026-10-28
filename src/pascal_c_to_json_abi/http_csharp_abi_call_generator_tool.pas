unit http_csharp_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallCsharpCode - generate the C# HTTP/JSON call module.
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPCallCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

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
  Lines.Add('// Both synchronous and asynchronous variants are generated for');
  Lines.Add('// every supported routine:');
  Lines.Add('//');
  Lines.Add('//   ApiName(args...)                       synchronous');
  Lines.Add('//   ApiNameAsync(args..., onComplete)      callback-style async');
  Lines.Add('//');
  Lines.Add('// The async variant delivers its outcome as a typed');
  Lines.Add('// ApiNameAsyncResult value through the supplied callback. Dispatch');
  Lines.Add('// failure (LF_Async_Call returns 0, or the request cannot be');
  Lines.Add('// serialized) is delivered through the SAME callback, synchronously');
  Lines.Add('// on the caller''s thread, with Ok == false. There is exactly one');
  Lines.Add('// error path.');
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
  Lines.Add('    // HTTPCallError - raised by the synchronous path on any failure.');
  Lines.Add('    //');
  Lines.Add('    // The asynchronous path never throws. It reports failures');
  Lines.Add('    // through the ApiNameAsyncResult value delivered to the');
  Lines.Add('    // callback. The fields of that struct mirror the fields of this');
  Lines.Add('    // exception, so both paths describe failures in the same way.');
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
  Lines.Add('    //');
  Lines.Add('    // The same configuration is used by both the synchronous and the');
  Lines.Add('    // asynchronous entry points.');
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
  Lines.Add('        //');
  Lines.Add('        // Sync path only: the async path uses the C ABI''s own');
  Lines.Add('        // round-trip management, which has no timeout parameter.');
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

// EmitCSharpTransport - internal HttpJsonTransport class with both
// sync and async entry points, sharing the same envelope validator.
procedure EmitCSharpTransport(Lines: TPascalStringList);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // HttpJsonTransport - internal transport layer.');
  Lines.Add('    //');
  Lines.Add('    // This is the single point where every generated function enters');
  Lines.Add('    // the LingoFuse mesh. It has two public entry points:');
  Lines.Add('    //');
  Lines.Add('    //   Call       - synchronous; returns the result.');
  Lines.Add('    //   CallAsync  - callback-style; delivers result through delegates.');
  Lines.Add('    //');
  Lines.Add('    // Both entry points share the same envelope validator');
  Lines.Add('    // (ValidateAndExtract), so the sync and async paths cannot');
  Lines.Add('    // disagree about the wire protocol.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    internal static class HttpJsonTransport');
  Lines.Add('    {');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // Synchronous entry point.');
  Lines.Add('        // ----------------------------------------------------------------');
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
  Lines.Add('            // Step 4: hand off to the shared validator.');
  Lines.Add('            return ValidateAndExtract(envelope, out _);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // Asynchronous entry point.');
  Lines.Add('        //');
  Lines.Add('        // Exactly one of the two supplied delegates is invoked.');
  Lines.Add('        //');
  Lines.Add('        //   * onSuccess receives the parsed body.result value (or');
  Lines.Add('        //     default(JsonElement) when the response carries no');
  Lines.Add('        //     result field).');
  Lines.Add('        //');
  Lines.Add('        //   * onError receives a human-readable message, the error');
  Lines.Add('        //     code, and the HTTP status.');
  Lines.Add('        //');
  Lines.Add('        // Dispatch failure (LF_Async_Call returns 0, or the request');
  Lines.Add('        // cannot be serialized) is delivered through onError,');
  Lines.Add('        // synchronously on the caller''s thread, with code == -1.');
  Lines.Add('        // There is exactly one error path.');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        public static void CallAsync(');
  Lines.Add('            string apiName,');
  Lines.Add('            object[] args,');
  Lines.Add('            Action<JsonElement> onSuccess,');
  Lines.Add('            Action<string, int, int> onError)');
  Lines.Add('        {');
  Lines.Add('            if (apiName is null) throw new ArgumentNullException(nameof(apiName));');
  Lines.Add('            if (onSuccess is null) throw new ArgumentNullException(nameof(onSuccess));');
  Lines.Add('            if (onError is null) throw new ArgumentNullException(nameof(onError));');
  Lines.Add('');
  Lines.Add('            string baseUrl = HttpJsonCallConfig.BaseUrl ?? string.Empty;');
  Lines.Add('            string url = baseUrl.TrimEnd(''/'') + "/" + apiName;');
  Lines.Add('');
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
  Lines.Add('                    "[HttpJsonCallAsync] POST " + url);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Lingofuse.Async.Call serializes the payload, submits the');
  Lines.Add('            // request, and invokes the supplied callback exactly once.');
  Lines.Add('            // The callback may fire synchronously (dispatch failure) or');
  Lines.Add('            // asynchronously on a worker thread (normal completion).');
  Lines.Add('            Async.Call(');
  Lines.Add('                HttpJsonCallConfig.BridgeAppName,');
  Lines.Add('                HttpJsonCallConfig.BridgeApiName,');
  Lines.Add('                bridgeRequest,');
  Lines.Add('                r =>');
  Lines.Add('                {');
  Lines.Add('                    if (!r.Ok)');
  Lines.Add('                    {');
  Lines.Add('                        onError(r.Error ?? "dispatch failed", -1, 0);');
  Lines.Add('                        return;');
  Lines.Add('                    }');
  Lines.Add('');
  Lines.Add('                    try');
  Lines.Add('                    {');
  Lines.Add('                        JsonElement envelope = r.ReadJson<JsonElement>();');
  Lines.Add('                        JsonElement result = ValidateAndExtract(');
  Lines.Add('                            envelope, out _);');
  Lines.Add('                        onSuccess(result);');
  Lines.Add('                    }');
  Lines.Add('                    catch (HTTPCallError ex)');
  Lines.Add('                    {');
  Lines.Add('                        onError(ex.Message, ex.Code, ex.HttpStatus);');
  Lines.Add('                    }');
  Lines.Add('                    catch (Exception ex)');
  Lines.Add('                    {');
  Lines.Add('                        onError(ex.Message, -1, 0);');
  Lines.Add('                    }');
  Lines.Add('                });');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // Envelope validator, shared by Call and CallAsync.');
  Lines.Add('        //');
  Lines.Add('        // Returns the value of body.result (or default when the');
  Lines.Add('        // response has no result field). Throws HTTPCallError on');
  Lines.Add('        // any shape or protocol violation.');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        private static JsonElement ValidateAndExtract(');
  Lines.Add('            JsonElement envelope,');
  Lines.Add('            out int httpStatus)');
  Lines.Add('        {');
  Lines.Add('            // Step 1: bridge-level error (no "status_code" field).');
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
  Lines.Add('            // Step 2: extract HTTP status (default 200).');
  Lines.Add('            httpStatus = 200;');
  Lines.Add('            if (envelope.ValueKind == JsonValueKind.Object');
  Lines.Add('                && envelope.TryGetProperty("status_code", out var statusElem)');
  Lines.Add('                && statusElem.ValueKind == JsonValueKind.Number)');
  Lines.Add('            {');
  Lines.Add('                httpStatus = statusElem.GetInt32();');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 3: extract the target service''s response body.');
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
  Lines.Add('            // Step 4: validate the service''s response envelope.');
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
  Lines.Add('            // Step 5: check the HTTP status after the service code, so');
  Lines.Add('            // that a 200 with code != 0 is reported with the service''s');
  Lines.Add('            // own error message.');
  Lines.Add('            if (httpStatus < 200 || httpStatus >= 300)');
  Lines.Add('            {');
  Lines.Add('                throw new HTTPCallError(');
  Lines.Add('                    "HTTP " + httpStatus, -1, httpStatus);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            // Step 6: return the result.');
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
  Lines.Add('    //');
  Lines.Add('    // Both the synchronous and the asynchronous paths use these');
  Lines.Add('    // helpers, so a type mismatch is reported the same way by both.');
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

// EmitCSharpAsyncResultTypes - one <ApiName>AsyncResult readonly struct
// per supported routine. Functions carry a typed Value field; procedures
// omit it.
procedure EmitCSharpAsyncResultTypes(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ResultType, RetType, InitParam, InitParamUse, SuccessFactory: TP_String;
  Description: TP_String;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // Async result types.');
  Lines.Add('    //');
  Lines.Add('    // Each API has one companion readonly struct that carries the');
  Lines.Add('    // outcome of its asynchronous variant. The struct mirrors the');
  Lines.Add('    // fields of HTTPCallError, so callers see the same error model');
  Lines.Add('    // on both paths.');
  Lines.Add('    //');
  Lines.Add('    // Contract:');
  Lines.Add('    //   Ok == true   -> Value holds the remote result (functions only).');
  Lines.Add('    //   Ok == false  -> Error / Code / HttpStatus describe the failure.');
  Lines.Add('    // ======================================================================');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ResultType := ApiName + 'AsyncResult';
    RetType := ABI_Type_To_CSharp_Decl(F.ReturnType);

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    Lines.Add('    /// <summary>');
    Lines.Add('    /// Outcome of the asynchronous <c>' + ApiName.Text + 'Async</c> call.');
    Lines.Add('    /// </summary>');
    Lines.Add('    /// <remarks>');
    Lines.Add('    /// <para>' + Description.Text + '</para>');
    Lines.Add('    /// <para>');
    Lines.Add('    /// Ok == true means the remote side returned a success response.');
    Lines.Add('    /// ');
    if F.IsFunction then
      Lines.Add('    /// Value then holds the deserialized result.')
    else
      Lines.Add('    /// Procedures have no return value.');
    Lines.Add('    /// </para>');
    Lines.Add('    /// <para>');
    Lines.Add('    /// Ok == false means the call failed. Error, Code, and HttpStatus');
    Lines.Add('    /// describe the failure with the same semantics as HTTPCallError.');
    Lines.Add('    /// </para>');
    Lines.Add('    /// </remarks>');
    Lines.Add('    public readonly struct ' + ResultType.Text);
    Lines.Add('    {');
    Lines.Add('        /// <summary>True when the call produced a success response.</summary>');
    Lines.Add('        public bool Ok { get; }');
    Lines.Add('');
    Lines.Add('        /// <summary>');
    Lines.Add('        /// Bridge / service error code. 0 on success; -1 / -2 / -4 or a');
    Lines.Add('        /// service-defined value on failure. Same semantics as');
    Lines.Add('        /// HTTPCallError.Code.');
    Lines.Add('        /// </summary>');
    Lines.Add('        public int Code { get; }');
    Lines.Add('');
    Lines.Add('        /// <summary>');
    Lines.Add('        /// HTTP status code of the response, or 0 if no response was');
    Lines.Add('        /// produced. Same semantics as HTTPCallError.HttpStatus.');
    Lines.Add('        /// </summary>');
    Lines.Add('        public int HttpStatus { get; }');
    Lines.Add('');
    Lines.Add('        /// <summary>');
    Lines.Add('        /// Human-readable failure message. Null on success.');
    Lines.Add('        /// </summary>');
    Lines.Add('        public string? Error { get; }');

    if F.IsFunction then
    begin
      Lines.Add('');
      Lines.Add('        /// <summary>');
      Lines.Add('        /// Deserialized remote result. Only meaningful when Ok is true.');
      Lines.Add('        /// </summary>');
      Lines.Add('        public ' + RetType.Text + ' Value { get; }');
    end;

    Lines.Add('');
    Lines.Add('        private ' + ResultType.Text + '(');
    Lines.Add('            bool ok, int code, int httpStatus, string? error' +
      if_(F.IsFunction, ', ' + RetType.Text + ' value', '') + ')');
    Lines.Add('        {');
    Lines.Add('            Ok = ok;');
    Lines.Add('            Code = code;');
    Lines.Add('            HttpStatus = httpStatus;');
    Lines.Add('            Error = error;');
    if F.IsFunction then
      Lines.Add('            Value = value;');
    Lines.Add('        }');
    Lines.Add('');

    // Success factory.
    Lines.Add('        internal static ' + ResultType.Text + ' Success(');
    if F.IsFunction then
      Lines.Add('            ' + RetType.Text + ' value)')
    else
      Lines.Add('            )');
    Lines.Add('        {');
    if F.IsFunction then
      Lines.Add('            return new ' + ResultType.Text +
        '(true, 0, 200, null, value);')
    else
      Lines.Add('            return new ' + ResultType.Text +
        '(true, 0, 200, null);');
    Lines.Add('        }');
    Lines.Add('');

    // Failure factory.
    Lines.Add('        internal static ' + ResultType.Text + ' Failure(');
    Lines.Add('            string error, int code, int httpStatus)');
    Lines.Add('        {');
    if F.IsFunction then
    begin
      Lines.Add('            return new ' + ResultType.Text + '(');
      Lines.Add('                false, code, httpStatus, error, ' +
        'default(' + RetType.Text + ')!);');
    end
    else
      Lines.Add('            return new ' + ResultType.Text +
        '(false, code, httpStatus, error);');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
  end;
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
  AsyncMethodName, AsyncResultType, AsyncExtraParam: TP_String;
  AsyncSuccessCall, AsyncErrorCall: TP_String;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // API - typed remote call functions.');
  Lines.Add('    //');
  Lines.Add('    // Every routine is exposed as two methods:');
  Lines.Add('    //');
  Lines.Add('    //   <ApiName>(...)');
  Lines.Add('    //       Blocking call. Returns the result or throws HTTPCallError.');
  Lines.Add('    //');
  Lines.Add('    //   <ApiName>Async(..., onComplete)');
  Lines.Add('    //       Callback-style. Returns immediately. The outcome is');
  Lines.Add('    //       delivered through onComplete as an <ApiName>AsyncResult.');
  Lines.Add('    //');
  Lines.Add('    // The async variant follows the C# Task Asynchronous Pattern''s');
  Lines.Add('    // naming rule ("XxxAsync") and its callback carries all the');
  Lines.Add('    // information the sync path reports through HTTPCallError.');
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

    AsyncMethodName := ApiName + 'Async';
    AsyncResultType := ApiName + 'AsyncResult';

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
    // Signature:
    //   public static void ApiNameAsync(<params>, Action<AsyncResultType> onComplete)
    if HasParams then
      AsyncExtraParam := ParamDecl + ', '
    else
      AsyncExtraParam := '';

    Lines.Add('        /// <summary>');
    if Description.Len > 0 then
      Lines.Add('        /// ' + Description.Text + ' (asynchronous)')
    else
      Lines.Add('        /// HTTP/JSON API: ' + ApiName + ' (asynchronous)');
    Lines.Add('        /// </summary>');
    Lines.Add('        /// <remarks>');
    Lines.Add('        /// <para>');
    Lines.Add('        /// Sends the request through <see cref="LingoFuse.Async"/> and');
    Lines.Add('        /// delivers the outcome to <paramref name="onComplete"/> as a');
    Lines.Add('        /// <see cref="' + AsyncResultType + '"/> value.');
    Lines.Add('        /// </para>');
    Lines.Add('        /// <para>');
    Lines.Add('        /// The callback is invoked on a worker thread under normal');
    Lines.Add('        /// conditions. If the request cannot be dispatched, the');
    Lines.Add('        /// callback is invoked synchronously on the calling thread with');
    Lines.Add('        /// <c>Ok == false</c>. There is exactly one error path: check');
    Lines.Add('        /// <c>result.Ok</c> in the callback body.');
    Lines.Add('        /// </para>');
    Lines.Add('        /// <para>');
    Lines.Add('        /// No timeout or cancellation is provided: the C ABI async family');
    Lines.Add('        /// has neither. Compose a timeout at a higher layer if needed.');
    Lines.Add('        /// </para>');
    Lines.Add('        /// </remarks>');
    Lines.Add('        public static void ' + AsyncMethodName + '(');
    Lines.Add('            ' + AsyncExtraParam + 'Action<' + AsyncResultType + '> onComplete)');
    Lines.Add('        {');
    Lines.Add('            if (onComplete is null)');
    Lines.Add('                throw new ArgumentNullException(nameof(onComplete));');
    Lines.Add('');
    Lines.Add('            HttpJsonTransport.CallAsync(');
    Lines.Add('                ' + CSharpStrLit(ApiName) + ',');
    Lines.Add('                ' + ArgsArrayExpr + ',');

    if f.IsFunction then
    begin
      Lines.Add('                result =>');
      Lines.Add('                {');
      Lines.Add('                    try');
      Lines.Add('                    {');
      Lines.Add('                        ' + RetType + ' value =');
      Lines.Add('                            JsonResult.' + Extractor + '(result);');
      Lines.Add('                        onComplete(' + AsyncResultType + '.Success(value));');
      Lines.Add('                    }');
      Lines.Add('                    catch (Exception ex)');
      Lines.Add('                    {');
      Lines.Add('                        onComplete(' + AsyncResultType + '.Failure(');
      Lines.Add('                            ex.Message, -1, 200));');
      Lines.Add('                    }');
      Lines.Add('                },');
    end
    else
    begin
      Lines.Add('                _ => onComplete(' + AsyncResultType + '.Success()),');
    end;

    Lines.Add('                (error, code, httpStatus) =>');
    Lines.Add('                    onComplete(' + AsyncResultType + '.Failure(');
    Lines.Add('                        error, code, httpStatus)));');
    Lines.Add('        }');
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
    EmitCSharpAsyncResultTypes(Lines, SupportedFuncs, ApiNames);
    EmitCSharpApi(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.', [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'csharp', 'C# HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call.cs', False,
    @GenerateHTTPCallCsharpCode);
end.
