unit http_cpp_abi_call_generator_tool;

// http_cpp_abi_call_generator_tool - LingoFuse HTTP/JSON ABI Call-Side
// Generator for C++.
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces three artifacts:
//
//   1. A C++ header (*.hpp) declaring the call-side namespace, its
//      configuration globals, the HTTPCallError class, and one typed
//      free function per supported routine.
//
//   2. A C++ implementation (*.cpp) defining the configuration globals,
//      the error class, the internal bridge transport helper, and every
//      generated call function.
//
//   3. A Markdown README describing the contract, deployment, a full
//      CMake script, a minimal test program, and a machine-readable
//      summary for AI agents.
//
// The generated client uses ONLY the C ABI declared in LingoFuse.h.
// It does not depend on any specific version of the C++ wrapper
// (LingoFuse.hpp), so it stays stable across wrapper reorganisation.
//
// Wire protocol (from the client's point of view):
//   the client sends  = POST <HTTP_CALL_BASE_URL>/<api>
//                       body: { "args": [v1, v2, ...] }
//   the client receives = { "code": 0,  "result": ... }
//                         { "code": -1, "error":  ... }
// The bridge is what actually performs the HTTP POST; the client only
// sees a LingoFuse round trip.
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   Every integer family member  -> std::int64_t
//   Every float family member    -> double
//   Every string family member   -> std::string
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

// GenerateHTTPCallCppHeader - main entry point for the C++ header.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallCppHeader(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallCppCode - main entry point for the C++ implementation.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallCppCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallCppReadme - main entry point for the README.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallCppReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_cpp_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_cpp_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification
// -----------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal') or
    T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function ABI_Type_To_Cpp_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'std::string'
  else if ABI_Type_Is_Float(T) then
    Result := 'double'
  else if ABI_Type_Is_Int(T) then
    Result := 'std::int64_t'
  else
    Result := '';
end;

function ABI_Type_To_Cpp_Default_Extract(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'std::string()'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := 'std::int64_t(0)'
  else
    Result := '{}';
end;

function ABI_Type_To_Pascal_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') then Result := 'Integer'
  else if T.Same('int64') then Result := 'Int64'
  else if T.Same('cardinal') then Result := 'Cardinal'
  else if T.Same('longint') then Result := 'LongInt'
  else if T.Same('dword') then Result := 'DWord'
  else if T.Same('word') then Result := 'Word'
  else if T.Same('smallint') then Result := 'SmallInt'
  else if T.Same('byte') then Result := 'Byte'
  else if T.Same('uint64') then Result := 'UInt64'
  else if T.Same('longword') then Result := 'LongWord'
  else if T.Same('double') then Result := 'Double'
  else if T.Same('single') then Result := 'Single'
  else if T.Same('extended') then Result := 'Extended'
  else if T.Same('real') then Result := 'Real'
  else if ABI_Type_Is_String(T) then Result := 'string'
  else Result := '';
end;

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// MakeApiName - canonicalize an arbitrary identifier into one that is
// safe to use simultaneously as:
//   * an API name on the LingoFuse wire,
//   * a URL path segment for the bridge's HTTP route,
//   * a JavaScript object key,
//   * a C++ / Pascal / Python identifier.
//
// The character set replaced here MUST match the character set replaced
// by every other generator in this toolchain:
//   * http_pas_abi_service_generator_tool
//   * http_pas_abi_call_generator_tool
//   * http_js_abi_call_generator_tool
//   * http_py_abi_service_generator_tool
//   * http_py_abi_call_generator_tool
//   * http_cpp_abi_service_generator_tool
//
// Replaced character set:
//   space, tab, '.', '/', '\', '@', ':', '#', '?', '&', '=', '+', '-'
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

// MakeSafeCppIdent - turn an arbitrary string into a valid C++
// identifier. Rules:
//   * empty input        -> 'p' + index
//   * invalid chars      -> '_'
//   * leading digit      -> prefix '_'
//   * C++ reserved word  -> suffix '_'
function MakeSafeCppIdent(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
      ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if Result.Same('alignas') or Result.Same('alignof') or Result.Same('and') or
    Result.Same('and_eq') or Result.Same('asm') or Result.Same('auto') or
    Result.Same('bitand') or Result.Same('bitor') or Result.Same('bool') or
    Result.Same('break') or Result.Same('case') or Result.Same('catch') or
    Result.Same('char') or Result.Same('char16_t') or Result.Same('char32_t') or
    Result.Same('class') or Result.Same('compl') or Result.Same('concept') or
    Result.Same('const') or Result.Same('constexpr') or Result.Same('const_cast') or
    Result.Same('continue') or Result.Same('co_await') or Result.Same('co_return') or
    Result.Same('co_yield') or Result.Same('decltype') or Result.Same('default') or
    Result.Same('delete') or Result.Same('do') or Result.Same('double') or
    Result.Same('dynamic_cast') or Result.Same('else') or Result.Same('enum') or
    Result.Same('explicit') or Result.Same('export') or Result.Same('extern') or
    Result.Same('false') or Result.Same('float') or Result.Same('for') or
    Result.Same('friend') or Result.Same('goto') or Result.Same('if') or
    Result.Same('inline') or Result.Same('int') or Result.Same('long') or
    Result.Same('mutable') or Result.Same('namespace') or Result.Same('new') or
    Result.Same('noexcept') or Result.Same('not') or Result.Same('not_eq') or
    Result.Same('nullptr') or Result.Same('operator') or Result.Same('or') or
    Result.Same('or_eq') or Result.Same('private') or Result.Same('protected') or
    Result.Same('public') or Result.Same('register') or Result.Same('reinterpret_cast') or
    Result.Same('requires') or Result.Same('return') or Result.Same('short') or
    Result.Same('signed') or Result.Same('sizeof') or Result.Same('static') or
    Result.Same('static_assert') or Result.Same('static_cast') or Result.Same('struct') or
    Result.Same('switch') or Result.Same('template') or Result.Same('this') or
    Result.Same('thread_local') or Result.Same('throw') or Result.Same('true') or
    Result.Same('try') or Result.Same('typedef') or Result.Same('typeid') or
    Result.Same('typename') or Result.Same('union') or Result.Same('unsigned') or
    Result.Same('using') or Result.Same('virtual') or Result.Same('void') or
    Result.Same('volatile') or Result.Same('wchar_t') or Result.Same('while') or
    Result.Same('xor') or Result.Same('xor_eq') then
    Result := Result + '_';
end;

// UniqueName - given a base identifier and a list of already-used
// identifiers, return a candidate that is not yet in the list.
function UniqueName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while Used.IndexOf(Base + '_' + umlIntToStr(i).Text) >= 0 do
    Inc(i);
  Result := Base + '_' + umlIntToStr(i).Text;
end;

// CppStrLit - produce a complete C++ string literal with the
// surrounding double quotes included.
function CppStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #34;   // opening double quote
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #34: Result.Append('\"');
      #92: Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9:  Result.Append('\t');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\x');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
        end
        else
          Result.Append(c);
    end;
  end;
  Result.Append(#34);   // closing double quote
end;

// -----------------------------------------------------------------------------
// Markdown helpers
// -----------------------------------------------------------------------------

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
      // skip
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
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

function BuildCppParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, decl: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeCppIdent(Params[i].Name, i);
    decl := ABI_Type_To_Cpp_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + decl + ' ' + n;
  end;
end;

function BuildCppCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeCppIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildCppArgArrayInit(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeCppIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeCppIdent(F.Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    if i > 0 then
      ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

function BuildCppSignature(const F: TFunctionStructure; const CppFuncName: TP_String): TP_String;
begin
  if F.IsFunction then
    Result := ABI_Type_To_Cpp_Decl(F.ReturnType) + ' ' + CppFuncName +
      '(' + BuildCppParamList(F.Params) + ')'
  else
    Result := 'void ' + CppFuncName + '(' + BuildCppParamList(F.Params) + ')';
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

// =============================================================================
// C++ CALL HEADER GENERATOR
// =============================================================================

function GenerateHTTPCallCppHeader(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, BaseUrl, GuardMacro: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedCppFuncNames, CppFuncNames: TPascalStringList;
  ApiName, CppFuncName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  ParamList, RetType: TP_String;
  Description: TP_String;
  HeaderFileName: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallCppHeader: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallCppHeader: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Ns := NormalizedUnit.LowerText;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  GuardMacro := NormalizedUnit.UpperText + '_HTTP_JSON_CALL_HPP';
  HeaderFileName := NormalizedUnit + '_http_json_call.hpp';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  UsedCppFuncNames := TPascalStringList.Create;
  CppFuncNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);

      // The C++ function name may differ from the API name when the
      // sanitized API name is a C++ reserved word (for example a
      // Pascal routine literally named 'class'). In that case the
      // C++ function gets a '_' suffix while the URL path keeps the
      // raw sanitized name, because that is what the service side
      // registered on the LingoFuse wire.
      CppFuncName := UniqueName(MakeSafeCppIdent(ApiName, i), UsedCppFuncNames);
      UsedCppFuncNames.Add(CppFuncName);
      CppFuncNames.Add(CppFuncName);
    end;

    // -------------------------------------------------------------------------
    // Header preamble
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_cpp_abi_call_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side C++ wrapper for the LingoFuse HTTP/JSON service that');
    Lines.Add('// was generated from the same source unit. Requests are routed');
    Lines.Add('// through the LingoFuse HTTP bridge (bridge.py) via the bridge''s');
    Lines.Add('// outbound POST API.');
    Lines.Add('//');
    Lines.Add('// The generated client uses ONLY the C ABI declared in');
    Lines.Add('// "LingoFuse.h". It does not depend on any specific version of');
    Lines.Add('// the C++ wrapper (LingoFuse.hpp), so it stays stable across');
    Lines.Add('// wrapper reorganisations.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (from the client''s point of view):');
    Lines.Add('//   request  = POST <HTTP_CALL_BASE_URL>/<api>');
    Lines.Add('//              body: { "args": [v1, v2, ...] }');
    Lines.Add('//   response = { "code": 0,  "result": ... }   on success');
    Lines.Add('//              { "code": -1, "error":  ... }   on failure');
    Lines.Add('//');
    Lines.Add('// Mapping note: when the sanitized API name collides with a C++');
    Lines.Add('// reserved word (for example a Pascal routine called "class"),');
    Lines.Add('// the C++ function is suffixed with "_" to keep it a legal');
    Lines.Add('// identifier. The URL path used at runtime keeps the original');
    Lines.Add('// sanitized name, so routing to the service is unaffected.');
    Lines.Add('');
    Lines.Add('#ifndef ' + GuardMacro);
    Lines.Add('#define ' + GuardMacro);
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Global configuration');
    Lines.Add('//');
    Lines.Add('// Set these once, before the first call. All five are global');
    Lines.Add('// variables; they are read on every call. Do not change them');
    Lines.Add('// from another thread while a call is in flight.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// LingoFuse application name of the bridge''s outbound POST API.');
    Lines.Add('extern std::string HTTP_BRIDGE_APP_NAME;');
    Lines.Add('');
    Lines.Add('// LingoFuse API name of the bridge''s outbound POST API.');
    Lines.Add('extern std::string HTTP_BRIDGE_API_NAME;');
    Lines.Add('');
    Lines.Add('// Timeout, in milliseconds, for the LingoFuse round trip to the');
    Lines.Add('// bridge. Must be larger than the HTTP timeout carried inside');
    Lines.Add('// the request.');
    Lines.Add('extern std::uint64_t HTTP_CALL_TIMEOUT_MS;');
    Lines.Add('');
    Lines.Add('// Base URL prefix of the target service. The full URL for API');
    Lines.Add('// "X" is HTTP_CALL_BASE_URL + "/" + "X". Do not append a');
    Lines.Add('// trailing slash: the generated code adds it.');
    Lines.Add('extern std::string HTTP_CALL_BASE_URL;');
    Lines.Add('');
    Lines.Add('// Default outbound HTTP timeout, in seconds, used when the');
    Lines.Add('// caller does not specify one.');
    Lines.Add('extern double HTTP_CALL_DEFAULT_TIMEOUT_S;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Error type');
    Lines.Add('//');
    Lines.Add('// Raised by every generated function when a call fails for any');
    Lines.Add('// reason: transport error, missing response field, or a non-zero');
    Lines.Add('// "code" in the response body.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('class HTTPCallError : public std::runtime_error {');
    Lines.Add('public:');
    Lines.Add('    // Bridge / service error code. -1 for transport errors and');
    Lines.Add('    // service exceptions, -2 for request-shape errors, -3 for');
    Lines.Add('    // bridge pre-check failures, or a service-defined code.');
    Lines.Add('    int code;');
    Lines.Add('');
    Lines.Add('    // HTTP status code of the underlying response, or 0 if the');
    Lines.Add('    // request never produced an HTTP response.');
    Lines.Add('    int http_status;');
    Lines.Add('');
    Lines.Add('    HTTPCallError(const std::string& message,');
    Lines.Add('                  int code_ = -1,');
    Lines.Add('                  int http_status_ = 0);');
    Lines.Add('};');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Typed call functions');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := ApiNames[i];
      CppFuncName := CppFuncNames[i];

      Description := GetFullDescription(f.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;

      ParamList := BuildCppParamList(f.Params);

      Lines.Add('// ' + Description.Text);
      Lines.Add('// HTTP route: POST /' + AppName.Text + '/' + ApiName.Text);
      if f.IsFunction then
      begin
        RetType := ABI_Type_To_Cpp_Decl(f.ReturnType);
        Lines.Add(RetType.Text + ' ' + CppFuncName.Text +
          '(' + ParamList.Text + ');');
      end
      else
        Lines.Add('void ' + CppFuncName.Text + '(' + ParamList.Text + ');');
      Lines.Add('');
    end;

    Lines.Add('}  // namespace ' + Ns);
    Lines.Add('');
    Lines.Add('#endif  // ' + GuardMacro);

    Result := Lines;
    Log(PFormat('Generated C++ call header: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    UsedCppFuncNames.Free;
    CppFuncNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// C++ CALL IMPLEMENTATION GENERATOR
// =============================================================================

function GenerateHTTPCallCppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, BaseUrl, HeaderFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedCppFuncNames, CppFuncNames: TPascalStringList;
  ApiName, CppFuncName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  ParamList, RetType: TP_String;
  ArgInit: TP_String;
  ExtractDefault: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallCppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallCppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Ns := NormalizedUnit.LowerText;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  HeaderFileName := NormalizedUnit + '_http_json_call.hpp';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  UsedCppFuncNames := TPascalStringList.Create;
  CppFuncNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);

      CppFuncName := UniqueName(MakeSafeCppIdent(ApiName, i), UsedCppFuncNames);
      UsedCppFuncNames.Add(CppFuncName);
      CppFuncNames.Add(CppFuncName);
    end;

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_cpp_abi_call_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Implementation of the C++ HTTP/JSON call wrapper declared in');
    Lines.Add('// "' + HeaderFileName.Text + '".');
    Lines.Add('//');
    Lines.Add('// This file uses ONLY the C ABI declared in "LingoFuse.h". It');
    Lines.Add('// does not include "LingoFuse.hpp" and does not depend on any');
    Lines.Add('// version-specific C++ wrapper API.');
    Lines.Add('');
    Lines.Add('#include "' + HeaderFileName.Text + '"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.h"');
    Lines.Add('#include "json.hpp"');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Global configuration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('std::string HTTP_BRIDGE_APP_NAME = "__lf_http_bridge__";');
    Lines.Add('std::string HTTP_BRIDGE_API_NAME = "__lf_outbound_post__";');
    Lines.Add('std::uint64_t HTTP_CALL_TIMEOUT_MS = 60000;');
    Lines.Add('std::string HTTP_CALL_BASE_URL = ' + CppStrLit(BaseUrl).Text + ';');
    Lines.Add('double HTTP_CALL_DEFAULT_TIMEOUT_S = 25.0;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Error type');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('HTTPCallError::HTTPCallError(const std::string& message,');
    Lines.Add('                             int code_,');
    Lines.Add('                             int http_status_)');
    Lines.Add('    : std::runtime_error(message),');
    Lines.Add('      code(code_),');
    Lines.Add('      http_status(http_status_) {');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Internal helpers');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('// Strip trailing NUL bytes from a std::string in place.');
    Lines.Add('static void _strip_trailing_nuls(std::string& s) {');
    Lines.Add('    while (!s.empty() && s.back() == ''\\0'') {');
    Lines.Add('        s.pop_back();');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// Send an HTTP POST request through the bridge using the C ABI');
    Lines.Add('// declared in LingoFuse.h. On success returns the parsed body');
    Lines.Add('// object. On failure throws HTTPCallError.');
    Lines.Add('static nlohmann::json _lf_http_post(const std::string& url,');
    Lines.Add('                                    const nlohmann::json& body,');
    Lines.Add('                                    double timeout_seconds) {');
    Lines.Add('    // Build the bridge request JSON.');
    Lines.Add('    nlohmann::json bridge_req;');
    Lines.Add('    bridge_req["url"] = url;');
    Lines.Add('    bridge_req["method"] = "POST";');
    Lines.Add('    bridge_req["body"] = body;');
    Lines.Add('    bridge_req["timeout"] = timeout_seconds;');
    Lines.Add('    std::string req_text = bridge_req.dump();');
    Lines.Add('');
    Lines.Add('    // Create the request handle.');
    Lines.Add('    void* param_h = LF_CreateData(HTTP_BRIDGE_API_NAME.c_str());');
    Lines.Add('    if (param_h == nullptr) {');
    Lines.Add('        throw HTTPCallError("LF_CreateData returned null", -1, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Write UTF-8 JSON + NUL.');
    Lines.Add('    try {');
    Lines.Add('        std::int64_t to_write =');
    Lines.Add('            static_cast<std::int64_t>(req_text.size()) + 1;');
    Lines.Add('        std::int64_t written = LF_WriteBuffer(');
    Lines.Add('            param_h, &req_text[0], to_write);');
    Lines.Add('        if (written != to_write) {');
    Lines.Add('            throw HTTPCallError(');
    Lines.Add('                "LF_WriteBuffer wrote fewer bytes than requested",');
    Lines.Add('                -1, 0);');
    Lines.Add('        }');
    Lines.Add('    } catch (...) {');
    Lines.Add('        LF_FreeData(param_h);');
    Lines.Add('        throw;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Send through LingoFuse. LF_Call returns a NEW handle; the');
    Lines.Add('    // request handle is no longer needed.');
    Lines.Add('    void* resp_h = LF_Call(HTTP_BRIDGE_APP_NAME.c_str(),');
    Lines.Add('                           param_h, HTTP_CALL_TIMEOUT_MS);');
    Lines.Add('    LF_FreeData(param_h);');
    Lines.Add('');
    Lines.Add('    if (resp_h == nullptr) {');
    Lines.Add('        throw HTTPCallError("LF_Call returned a null handle", -1, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Read the response.');
    Lines.Add('    std::string resp_text;');
    Lines.Add('    try {');
    Lines.Add('        std::int64_t size = LF_GetSize(resp_h);');
    Lines.Add('        if (size <= 0) {');
    Lines.Add('            throw HTTPCallError(');
    Lines.Add('                "Bridge returned an empty response (timeout?)", -1, 0);');
    Lines.Add('        }');
    Lines.Add('        resp_text.resize(static_cast<std::size_t>(size));');
    Lines.Add('        std::int64_t read = LF_ReadBuffer(');
    Lines.Add('            resp_h, &resp_text[0], size);');
    Lines.Add('        if (read < 0) read = 0;');
    Lines.Add('        resp_text.resize(static_cast<std::size_t>(read));');
    Lines.Add('    } catch (...) {');
    Lines.Add('        LF_FreeData(resp_h);');
    Lines.Add('        throw;');
    Lines.Add('    }');
    Lines.Add('    LF_FreeData(resp_h);');
    Lines.Add('');
    Lines.Add('    _strip_trailing_nuls(resp_text);');
    Lines.Add('    if (resp_text.empty()) {');
    Lines.Add('        throw HTTPCallError("Bridge returned an empty string", -1, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Parse the bridge envelope.');
    Lines.Add('    nlohmann::json bridge_resp;');
    Lines.Add('    try {');
    Lines.Add('        bridge_resp = nlohmann::json::parse(resp_text);');
    Lines.Add('    } catch (const std::exception& e) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            std::string("Invalid JSON response from bridge: ")');
    Lines.Add('                + e.what(), -1, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (!bridge_resp.is_object()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "Bridge response is not a JSON object", -1, 0);');
    Lines.Add('    }');
    Lines.Add('    if (!bridge_resp.contains("body")) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "Bridge response has no ''body'' field", -1, 0);');
    Lines.Add('    }');
    Lines.Add('    const nlohmann::json& inner = bridge_resp["body"];');
    Lines.Add('    if (!inner.is_object()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "Bridge response ''body'' is not a JSON object", -1, 0);');
    Lines.Add('    }');
    Lines.Add('    if (!inner.contains("code")) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "Bridge response ''body'' has no ''code'' field", -1, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    const int code = inner.value("code", -1);');
    Lines.Add('    if (code != 0) {');
    Lines.Add('        const std::string err = inner.value(');
    Lines.Add('            "error", std::string("unknown error"));');
    Lines.Add('        throw HTTPCallError(err, code, 200);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    return inner;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // anonymous namespace');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Typed call functions');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    // Function definitions
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := ApiNames[i];
      CppFuncName := CppFuncNames[i];

      ParamList := BuildCppParamList(f.Params);
      ArgInit := BuildCppArgArrayInit(f.Params);

      if f.IsFunction then
        RetType := ABI_Type_To_Cpp_Decl(f.ReturnType)
      else
        RetType := 'void';

      Lines.Add(RetType.Text + ' ' + CppFuncName.Text + '(' + ParamList.Text + ') {');
      Lines.Add('    const std::string url = HTTP_CALL_BASE_URL + "/' + ApiName.Text + '";');
      Lines.Add('');
      Lines.Add('    // Build the request body: { "args": [<arg1>, <arg2>, ...] }.');
      Lines.Add('    nlohmann::json req;');
      Lines.Add('    req["args"] = nlohmann::json::array({' + ArgInit.Text + '});');
      Lines.Add('');
      Lines.Add('    const nlohmann::json body = _lf_http_post(');
      Lines.Add('        url, req, HTTP_CALL_DEFAULT_TIMEOUT_S);');

      if f.IsFunction then
      begin
        ExtractDefault := ABI_Type_To_Cpp_Default_Extract(f.ReturnType);
        Lines.Add('');
        Lines.Add('    return body.value("result", ' + ExtractDefault.Text + ');');
      end
      else
      begin
        Lines.Add('    (void)body;  // procedures have no return value');
      end;

      Lines.Add('}');
      Lines.Add('');
    end;

    Lines.Add('}  // namespace ' + Ns);

    Result := Lines;
    Log(PFormat('Generated C++ call implementation: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    UsedCppFuncNames.Free;
    CppFuncNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// C++ CALL README GENERATOR
// =============================================================================

function GenerateHTTPCallCppReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, BaseUrl: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedCppFuncNames, CppFuncNames: TPascalStringList;
  ApiName, CppFuncName: TP_String;
  f: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamWire: TP_String;
  HeaderFileName, CodeFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  PascalDecl, CppSig: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallCppReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallCppReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Ns := NormalizedUnit.LowerText;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  HeaderFileName := NormalizedUnit + '_http_json_call.hpp';
  CodeFileName := NormalizedUnit + '_http_json_call.cpp';

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
  UsedCppFuncNames := TPascalStringList.Create;
  CppFuncNames := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);

      CppFuncName := UniqueName(MakeSafeCppIdent(ApiName, i), UsedCppFuncNames);
      UsedCppFuncNames.Add(CppFuncName);
      CppFuncNames.Add(CppFuncName);
    end;

    // =========================================================================
    // Header block
    // =========================================================================
    Lines.Add('# ' + UnitName.Text + ' - C++ HTTP/JSON Call-Side Wrapper');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_cpp_abi_call_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Header file**       : `' + HeaderFileName.Text + '`');
    Lines.Add('> **Implementation**    : `' + CodeFileName.Text + '`');
    Lines.Add('> **Namespace**         : `' + Ns.Text + '`');
    Lines.Add('> **Target App name**   : `' + AppName.Text + '`');
    Lines.Add('> **Default base URL**  : `' + BaseUrl.Text + '`');
    Lines.Add('> **Exposed functions** : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('>');
    Lines.Add('> **Audience**: C++ developers and AI assistants who need to');
    Lines.Add('> compile the generated wrapper into their own program and call');
    Lines.Add('> a remote service through `bridge.py`.');
    Lines.Add('>');
    Lines.Add('> **AI agents**: jump straight to §12 "For AI Agents" for a');
    Lines.Add('> compact, machine-readable summary.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // =========================================================================
    // 1. Overview
    // =========================================================================
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **call-side C++ wrapper** that was');
    Lines.Add('generated from the Pascal unit `' + UnitName.Text + '`. The');
    Lines.Add('wrapper exposes one typed C++ function per supported routine');
    Lines.Add('in the source. Each generated function routes a request through');
    Lines.Add('the LingoFuse HTTP bridge to a remote HTTP/JSON service, parses');
    Lines.Add('the response, and returns the result as a native C++ value.');
    Lines.Add('');
    Lines.Add('### 1.1 Dependencies');
    Lines.Add('');
    Lines.Add('The generated wrapper has exactly three third-party dependencies:');
    Lines.Add('');
    Lines.Add('| Piece | Files | Purpose |');
    Lines.Add('|-------|-------|---------|');
    Lines.Add('| LingoFuse C ABI | `LingoFuse.h` + `LingoFuse.c` | Transport to the bridge |');
    Lines.Add('| nlohmann/json | `json.hpp` | JSON encode/decode |');
    Lines.Add('| C++ standard library | — | `std::string`, `std::runtime_error`, etc. |');
    Lines.Add('');
    Lines.Add('It does **not** depend on `LingoFuse.hpp` or `lf_io.hpp` — those');
    Lines.Add('are C++ wrapper headers whose API varies across releases. Only');
    Lines.Add('the stable C ABI is used.');
    Lines.Add('');
    Lines.Add('### 1.2 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + HeaderFileName.Text + '` | The call wrapper header. |');
    Lines.Add('| `' + CodeFileName.Text + '` | The call wrapper implementation. |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_call_cpp.md` | This README. |');
    Lines.Add('');

    // =========================================================================
    // 2. Quick Start
    // =========================================================================
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Prepare LingoFuse');
    Lines.Add('');
    Lines.Add('Your program must prepare LingoFuse before the first call:');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('#include "LingoFuse.h"');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    // Connect to the same LingoFuse endpoint the bridge uses.');
    Lines.Add('    LF_ResetPrepare();');
    Lines.Add('    LF_PrepareClient("ipc:' + NormalizedUnit.Text + '_http_json", nullptr);');
    Lines.Add('    if (LF_PrepareDone() != 1) {');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('    // ... your calls ...');
    Lines.Add('    LF_ExitMainThread();');
    Lines.Add('    LF_Shutdown();');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 2.2 Configure the client');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add(Ns.Text + '::HTTP_CALL_BASE_URL = ' + CppStrLit(BaseUrl).Text + ';');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 2.3 Make a call');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('try {');
    Lines.Add('    std::int64_t r = ' + Ns.Text + '::Add(3, 4);');
    Lines.Add('    std::cout << "Add(3, 4) = " << r << "\\n";');
    Lines.Add('} catch (const ' + Ns.Text + '::HTTPCallError& e) {');
    Lines.Add('    std::cerr << "Call failed: " << e.what()');
    Lines.Add('              << " (code=" << e.code');
    Lines.Add('              << ", http_status=" << e.http_status << ")\\n";');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 3. Compatibility
    // =========================================================================
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('### 3.1 Compiler support');
    Lines.Add('');
    Lines.Add('| Compiler | Minimum version |');
    Lines.Add('|----------|-----------------|');
    Lines.Add('| GCC | 7 |');
    Lines.Add('| Clang | 6 |');
    Lines.Add('| MSVC | 2019 (19.20) |');
    Lines.Add('');
    Lines.Add('The generated code requires C++17.');
    Lines.Add('');
    Lines.Add('### 3.2 Platform support');
    Lines.Add('');
    Lines.Add('| Platform | Architecture | Status |');
    Lines.Add('|----------|-------------|--------|');
    Lines.Add('| Windows | x86_64 | Primary target |');
    Lines.Add('| Linux | x86_64 | Supported |');
    Lines.Add('| Linux | aarch64 | Supported |');
    Lines.Add('| macOS | x86_64 | Supported |');
    Lines.Add('| macOS | aarch64 | Supported |');
    Lines.Add('');
    Lines.Add('### 3.3 Threading');
    Lines.Add('');
    Lines.Add('Generated functions are synchronous and blocking. `LF_Call` is');
    Lines.Add('thread-safe, so multiple threads may call different functions');
    Lines.Add('concurrently. The five module-level configuration globals are');
    Lines.Add('not atomic: set them once at startup, before any call, and do');
    Lines.Add('not modify them while a call is in flight.');
    Lines.Add('');

    // =========================================================================
    // 4. Wire Protocol
    // =========================================================================
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('Every generated function performs a LingoFuse round trip to the');
    Lines.Add('bridge, which then performs an HTTP POST to the target service.');
    Lines.Add('The client never speaks HTTP directly.');
    Lines.Add('');
    Lines.Add('### 4.1 URL composition');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('HTTP_CALL_BASE_URL + "/" + <api-name>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.2 Outbound request');
    Lines.Add('');
    Lines.Add('The client sends a bridge request:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "url":     "<HTTP_CALL_BASE_URL>/<api>",');
    Lines.Add('  "method":  "POST",');
    Lines.Add('  "body":    { "args": [v1, v2, ...] },');
    Lines.Add('  "timeout": 25.0');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.3 Inbound response');
    Lines.Add('');
    Lines.Add('The bridge returns a JSON envelope:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "status_code": 200,');
    Lines.Add('  "headers":     { ... },');
    Lines.Add('  "body":        { "code": 0, "result": <value> }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated function inspects `body.code` and either returns');
    Lines.Add('`body.result` or throws `HTTPCallError` with `body.error`.');
    Lines.Add('');
    Lines.Add('### 4.4 Error model');
    Lines.Add('');
    Lines.Add('| Condition | `code` in HTTPCallError |');
    Lines.Add('|-----------|:-----------------------:|');
    Lines.Add('| LingoFuse call timed out | `-1` |');
    Lines.Add('| Bridge envelope missing `body` | `-1` |');
    Lines.Add('| Bridge envelope `body` is not an object | `-1` |');
    Lines.Add('| Response lacks `code` | `-1` |');
    Lines.Add('| Service returned `code <> 0` | the service code |');
    Lines.Add('');

    // =========================================================================
    // 5. Global Configuration
    // =========================================================================
    Lines.Add('## 5. Global Configuration');
    Lines.Add('');
    Lines.Add('| Variable | Type | Default | Purpose |');
    Lines.Add('|----------|------|---------|---------|');
    Lines.Add('| `HTTP_BRIDGE_APP_NAME` | `std::string` | `"__lf_http_bridge__"` | LingoFuse app name of the bridge. |');
    Lines.Add('| `HTTP_BRIDGE_API_NAME` | `std::string` | `"__lf_outbound_post__"` | LingoFuse API name of the bridge''s outbound POST proxy. |');
    Lines.Add('| `HTTP_CALL_TIMEOUT_MS` | `std::uint64_t` | `60000` | Timeout for the LingoFuse round trip. |');
    Lines.Add('| `HTTP_CALL_BASE_URL` | `std::string` | `' + BaseUrl.Text + '` | Base URL of the target service. |');
    Lines.Add('| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `double` | `25.0` | Default HTTP timeout inside the request. |');
    Lines.Add('');

    // =========================================================================
    // 6. Error Handling
    // =========================================================================
    Lines.Add('## 6. Error Handling');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('class HTTPCallError : public std::runtime_error {');
    Lines.Add('public:');
    Lines.Add('    int code;         // -1, -2, -3, or a service code');
    Lines.Add('    int http_status;  // 0 for transport errors, 200 for service errors');
    Lines.Add('    HTTPCallError(const std::string& message,');
    Lines.Add('                  int code_ = -1,');
    Lines.Add('                  int http_status_ = 0);');
    Lines.Add('};');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('| Code | Meaning |');
    Lines.Add('|------|---------|');
    Lines.Add('| `0` | Success. Never thrown. |');
    Lines.Add('| `-1` | Remote call failed (service exception, transport error, timeout). |');
    Lines.Add('| `-2` | Request shape error (URL path could not be parsed by the bridge). |');
    Lines.Add('| `-3` | Bridge pre-check failed. |');
    Lines.Add('');

    // =========================================================================
    // 7. API Reference
    // =========================================================================
    Lines.Add('## 7. API Reference');
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
        Lines.Add('### 7.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('The source unit exposes overloaded routines. Because the');
        Lines.Add('HTTP/JSON protocol routes by API name, the generator appends');
        Lines.Add('`_N` to every overload after the first.');
        Lines.Add('');
      end;

      Lines.Add('### 7.1 Summary');
      Lines.Add('');
      Lines.Add('| # | C++ function | HTTP route | Params | Returns | Description |');
      Lines.Add('|---|--------------|------------|--------|---------|-------------|');

      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := ApiNames[i];
        CppFuncName := CppFuncNames[i];

        Description := GetFullDescription(f.Comment);
        if Description.Len = 0 then
          Description := '';

        if f.IsFunction then
          ParamWire := ABI_Type_To_Cpp_Decl(f.ReturnType)
        else
          ParamWire := '-';

        Lines.Add('| ' + MdInt(i + 1).Text +
          ' | `' + MdCellEscape(CppFuncName).Text + '`' +
          ' | `POST /' + AppName.Text + '/' + MdCellEscape(ApiName).Text + '`' +
          ' | ' + MdInt(Length(f.Params)).Text +
          ' | `' + MdCellEscape(ParamWire).Text + '`' +
          ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := ApiNames[i];
        CppFuncName := CppFuncNames[i];
        HasParams := Length(f.Params) > 0;

        PascalDecl := BuildPascalDecl(f);
        CppSig := BuildCppSignature(f, CppFuncName);
        CallArgs := BuildCppCallArgList(f.Params);

        Lines.Add('### 7.' + MdInt(i + 2).Text + ' `' + CppFuncName.Text + '`');
        Lines.Add('');

        Lines.Add('- **C++ signature**: `' + CppSig.Text + '`');
        Lines.Add('- **Pascal source**: `' + PascalDecl.Text + '`');
        Lines.Add('- **HTTP route**: `POST /' + AppName.Text + '/' + ApiName.Text + '`');
        Lines.Add('- **Throws**: `HTTPCallError` on any failure');
        Lines.Add('');

        Description := GetFullDescription(f.Comment);
        if Description.Len > 0 then
        begin
          Lines.Add('#### Description');
          Lines.Add('');
          Lines.Add(Description.Text);
          Lines.Add('');
        end;

        if HasParams then
        begin
          Lines.Add('#### Arguments');
          Lines.Add('');
          Lines.Add('| # | Name | C++ type | JSON wire type |');
          Lines.Add('|---|------|----------|----------------|');
          for j := 0 to High(f.Params) do
          begin
            ParamName := MakeSafeCppIdent(f.Params[j].Name, j);
            ParamType := ABI_Type_To_Cpp_Decl(f.Params[j].PascalType);
            ParamWire := ABI_Type_To_Json_Wire_Type(f.Params[j].PascalType);
            Lines.Add('| ' + MdInt(j + 1).Text +
              ' | `' + MdCellEscape(ParamName).Text + '`' +
              ' | `' + MdCellEscape(ParamType).Text + '`' +
              ' | `' + MdCellEscape(ParamWire).Text + '` |');
          end;
          Lines.Add('');
        end;

        Lines.Add('#### Example');
        Lines.Add('');
        Lines.Add('```cpp');
        Lines.Add('try {');
        if f.IsFunction then
          Lines.Add('    auto result = ' + Ns.Text + '::' + CppFuncName.Text +
            '(' + CallArgs.Text + ');')
        else
          Lines.Add('    ' + Ns.Text + '::' + CppFuncName.Text +
            '(' + CallArgs.Text + ');');
        Lines.Add('} catch (const ' + Ns.Text + '::HTTPCallError& e) {');
        Lines.Add('    std::cerr << "Call failed: " << e.what()');
        Lines.Add('              << " (code=" << e.code << ")\\n";');
        Lines.Add('}');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    // =========================================================================
    // 8. Building - Manual
    // =========================================================================
    Lines.Add('## 8. Building - Manual');
    Lines.Add('');
    Lines.Add('The generated wrapper is **not** a program by itself: it is a');
    Lines.Add('library that you compile into your own program. The only');
    Lines.Add('third-party source file that needs to be compiled in is');
    Lines.Add('`LingoFuse.c`. Everything else is a header.');
    Lines.Add('');
    Lines.Add('### 8.1 Required files next to your sources');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('your_project/');
    Lines.Add('  ' + HeaderFileName.Text + '      <- generated');
    Lines.Add('  ' + CodeFileName.Text + '        <- generated');
    Lines.Add('  your_main.cpp                             <- your entry point');
    Lines.Add('  LingoFuse.h                               <- from LingoFuse distribution');
    Lines.Add('  LingoFuse.c                               <- from LingoFuse distribution');
    Lines.Add('  json.hpp                                  <- nlohmann/json single header');
    Lines.Add('  LingoFuse64.dll                           <- Windows runtime');
    Lines.Add('  liblingofuse.so                           <- Linux runtime');
    Lines.Add('  liblingofuse.dylib                        <- macOS runtime');
    Lines.Add('  z_ipc_64.dll                              <- Windows runtime');
    Lines.Add('  libz_ipc_64.so                            <- Linux runtime');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.2 Minimal build (GCC / Clang)');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('g++ -std=c++17 -O2 \\');
    Lines.Add('    -I. \\');
    Lines.Add('    your_main.cpp ' + CodeFileName.Text + ' LingoFuse.c \\');
    Lines.Add('    -o your_app \\');
    Lines.Add('    -pthread -ldl');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.3 Minimal build (MSVC)');
    Lines.Add('');
    Lines.Add('```cmd');
    Lines.Add('cl /std:c++17 /O2 /EHsc ^');
    Lines.Add('   /I. ^');
    Lines.Add('   your_main.cpp ' + CodeFileName.Text + ' LingoFuse.c ^');
    Lines.Add('   /Fe:your_app.exe');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 9. Building - CMake
    // =========================================================================
    Lines.Add('## 9. Building - CMake');
    Lines.Add('');
    Lines.Add('If you use CMake, drop this `CMakeLists.txt` next to the two');
    Lines.Add('generated files, the five support files, and a `test_main.cpp`');
    Lines.Add('(see §10 for a minimal one).');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('project(' + NormalizedUnit.Text + '_http_json_call_test CXX)');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Adjust these paths if the support files live elsewhere.');
    Lines.Add('# LINGOFUSE_DIR must contain: LingoFuse.h, LingoFuse.c');
    Lines.Add('# NLOHMANN_DIR  must contain: json.hpp');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('set(LINGOFUSE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('set(NLOHMANN_DIR  "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('');
    Lines.Add('add_executable(${PROJECT_NAME}');
    Lines.Add('    test_main.cpp');
    Lines.Add('    ' + CodeFileName.Text);
    Lines.Add('    "${LINGOFUSE_DIR}/LingoFuse.c"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('target_include_directories(${PROJECT_NAME} PRIVATE');
    Lines.Add('    "${CMAKE_CURRENT_SOURCE_DIR}"');
    Lines.Add('    "${LINGOFUSE_DIR}"');
    Lines.Add('    "${NLOHMANN_DIR}"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('if(WIN32)');
    Lines.Add('    target_link_libraries(${PROJECT_NAME} PRIVATE ws2_32)');
    Lines.Add('elseif(APPLE)');
    Lines.Add('    find_package(Threads REQUIRED)');
    Lines.Add('    target_link_libraries(${PROJECT_NAME} PRIVATE Threads::Threads)');
    Lines.Add('else()');
    Lines.Add('    find_package(Threads REQUIRED)');
    Lines.Add('    target_link_libraries(${PROJECT_NAME} PRIVATE');
    Lines.Add('        Threads::Threads ${CMAKE_DL_LIBS})');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Copy the Windows runtime DLLs next to the executable.');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('if(WIN32)');
    Lines.Add('    foreach(_dll');
    Lines.Add('        "${LINGOFUSE_DIR}/LingoFuse64.dll"');
    Lines.Add('        "${LINGOFUSE_DIR}/z_ipc_64.dll")');
    Lines.Add('        if(EXISTS "${_dll}")');
    Lines.Add('            add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD');
    Lines.Add('                COMMAND ${CMAKE_COMMAND} -E copy_if_different');
    Lines.Add('                    "${_dll}"');
    Lines.Add('                    "$<TARGET_FILE_DIR:${PROJECT_NAME}>")');
    Lines.Add('        endif()');
    Lines.Add('    endforeach()');
    Lines.Add('endif()');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 9.1 Add to an existing CMake project');
    Lines.Add('');
    Lines.Add('If you already have a top-level `CMakeLists.txt`, add the');
    Lines.Add('following to it instead of making a separate project:');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('# Build the generated wrapper as a static library.');
    Lines.Add('add_library(' + NormalizedUnit.Text + '_http_json_call STATIC');
    Lines.Add('    ' + CodeFileName.Text);
    Lines.Add('    "${LINGOFUSE_DIR}/LingoFuse.c"');
    Lines.Add(')');
    Lines.Add('target_include_directories(' + NormalizedUnit.Text + '_http_json_call PUBLIC');
    Lines.Add('    "${CMAKE_CURRENT_SOURCE_DIR}"');
    Lines.Add('    "${LINGOFUSE_DIR}"');
    Lines.Add('    "${NLOHMANN_DIR}"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('# Link your program against it.');
    Lines.Add('target_link_libraries(your_app PRIVATE ' + NormalizedUnit.Text + '_http_json_call)');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 10. Minimal Test Program
    // =========================================================================
    Lines.Add('## 10. Minimal Test Program');
    Lines.Add('');
    Lines.Add('`test_main.cpp` used by §9:');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('// Sample test program for the generated ' + NormalizedUnit.Text + '_http_json_call');
    Lines.Add('// library. Replace the calls below with real ones.');
    Lines.Add('');
    Lines.Add('#include "' + HeaderFileName.Text + '"');
    Lines.Add('');
    Lines.Add('#include <cstdio>');
    Lines.Add('#include <cstdint>');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.h"');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    // 1. Prepare LingoFuse. The endpoint must match the one the');
    Lines.Add('    //    bridge was started with (its --endpoint argument).');
    Lines.Add('    LF_ResetPrepare();');
    Lines.Add('    LF_PrepareClient("ipc:' + NormalizedUnit.Text + '_http_json", nullptr);');
    Lines.Add('    if (LF_PrepareDone() != 1) {');
    Lines.Add('        std::fprintf(stderr, "LingoFuse init failed\\n");');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // 2. Point the generated client at the bridge.');
    Lines.Add('    ' + Ns.Text + '::HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/' + NormalizedUnit.Text + '";');
    Lines.Add('');

    if FuncCount > 0 then
    begin
      f := SupportedFuncs[0];
      CppFuncName := CppFuncNames[0];
      CallArgs := BuildCppCallArgList(f.Params);

      Lines.Add('    // 3. Call a generated function.');
      Lines.Add('    try {');
      if f.IsFunction then
      begin
        Lines.Add('        std::int64_t r = ' + Ns.Text + '::' + CppFuncName.Text +
          '(' + CallArgs.Text + ');');
        Lines.Add('        std::printf("' + CppFuncName.Text + '(...) = %lld\\n", (long long)r);');
      end
      else
      begin
        Lines.Add('        ' + Ns.Text + '::' + CppFuncName.Text + '(' + CallArgs.Text + ');');
        Lines.Add('        std::printf("' + CppFuncName.Text + '(...) succeeded\\n");');
      end;
      Lines.Add('    } catch (const ' + Ns.Text + '::HTTPCallError& e) {');
      Lines.Add('        std::fprintf(stderr, "Call failed: %s (code=%d, http=%d)\\n",');
      Lines.Add('                     e.what(), e.code, e.http_status);');
      Lines.Add('    }');
    end
    else
    begin
      Lines.Add('    // No supported routines were generated for this unit.');
    end;

    Lines.Add('');
    Lines.Add('    // 4. Clean shutdown.');
    Lines.Add('    LF_ExitMainThread();');
    Lines.Add('    LF_Shutdown();');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 11. Troubleshooting
    // =========================================================================
    Lines.Add('## 11. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| Linker error: undefined reference to `LF_*` | `LingoFuse.c` not compiled in | Add it to the same build target |');
    Lines.Add('| Linker error: undefined reference to `dlopen` | Missing `-ldl` on Linux | Add `-ldl` to the link line |');
    Lines.Add('| `LF_CreateData returned null` | LingoFuse library not loaded | Ensure `LingoFuse64.dll` / `liblingofuse.so` is next to the executable or on the search path |');
    Lines.Add('| `LF_Call returned a null handle` | LingoFuse not prepared, or the bridge is not reachable | Call `LF_PrepareClient` + `LF_PrepareDone` before the first call |');
    Lines.Add('| `Bridge returned an empty response` | Timeout, or the bridge is not running | Increase `HTTP_CALL_TIMEOUT_MS`; start `bridge.py` |');
    Lines.Add('| `code: -3` | Bridge pre-check failed | Add `--no-precheck` to the bridge, or retry after ~3 s |');
    Lines.Add('| `HTTP 404` from the bridge | Wrong URL path | Verify `HTTP_CALL_BASE_URL` ends with `/<app>` |');
    Lines.Add('');

    // =========================================================================
    // 12. For AI Agents
    // =========================================================================
    Lines.Add('## 12. For AI Agents');
    Lines.Add('');
    Lines.Add('### 12.1 Contract summary');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('artifact:');
    Lines.Add('  type: cpp_http_json_client');
    Lines.Add('  header_file: ' + HeaderFileName.Text);
    Lines.Add('  code_file: ' + CodeFileName.Text);
    Lines.Add('  namespace: ' + Ns.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  target_app_name: ' + AppName.Text);
    Lines.Add('  default_base_url: ' + BaseUrl.Text);
    Lines.Add('');
    Lines.Add('dependencies:');
    Lines.Add('  - LingoFuse.h   # C ABI declarations');
    Lines.Add('  - LingoFuse.c   # C ABI implementation (compile it in)');
    Lines.Add('  - json.hpp      # nlohmann/json single header');
    Lines.Add('  - c++ standard library');
    Lines.Add('');
    Lines.Add('does_not_depend_on:');
    Lines.Add('  - LingoFuse.hpp');
    Lines.Add('  - lf_io.hpp');
    Lines.Add('');
    Lines.Add('global_configuration:');
    Lines.Add('  HTTP_BRIDGE_APP_NAME: "__lf_http_bridge__"');
    Lines.Add('  HTTP_BRIDGE_API_NAME: "__lf_outbound_post__"');
    Lines.Add('  HTTP_CALL_TIMEOUT_MS: 60000');
    Lines.Add('  HTTP_CALL_BASE_URL: "' + BaseUrl.Text + '"');
    Lines.Add('  HTTP_CALL_DEFAULT_TIMEOUT_S: 25.0');
    Lines.Add('');
    Lines.Add('outbound_request:');
    Lines.Add('  transport: "LF_Call to (__lf_http_bridge__, __lf_outbound_post__)"');
    Lines.Add('  bridge_request:');
    Lines.Add('    url: "HTTP_CALL_BASE_URL + ''/'' + api_name"');
    Lines.Add('    method: POST');
    Lines.Add('    body: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('    timeout: HTTP_CALL_DEFAULT_TIMEOUT_S');
    Lines.Add('');
    Lines.Add('inbound_response:');
    Lines.Add('  envelope: ''{"status_code": ..., "headers": {...}, "body": {...}}''');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('exception:');
    Lines.Add('  type: HTTPCallError');
    Lines.Add('  base: std::runtime_error');
    Lines.Add('  fields:');
    Lines.Add('    code: "int"');
    Lines.Add('    http_status: "int"');
    Lines.Add('');
    Lines.Add('types:');
    Lines.Add('  cpp_int: "std::int64_t"');
    Lines.Add('  cpp_float: "double"');
    Lines.Add('  cpp_str: "std::string"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 12.2 Anti-patterns');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Calling a function before `LF_PrepareDone()` | LingoFuse mesh not ready | Prepare LingoFuse first |');
    Lines.Add('| Setting `HTTP_CALL_BASE_URL` after the first call | Race with in-flight calls | Set once at startup |');
    Lines.Add('| Catching `std::exception` instead of `HTTPCallError` | Hides unrelated bugs | Catch `HTTPCallError` explicitly |');
    Lines.Add('| Omitting `LingoFuse.c` from the build | Linker error | Add it to the same target |');
    Lines.Add('| Omitting `-ldl` on Linux | Linker error | Add `-ldl` to the link line |');
    Lines.Add('| Using `int`/`float` instead of `std::int64_t`/`double` | Silent truncation | Use the generated types verbatim |');
    Lines.Add('');

    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_cpp_abi_call_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated C++ call README: %d lines, %d routines.',
      [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    UsedCppFuncNames.Free;
    CppFuncNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
