unit http_cpp_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

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

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
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
// ABI type classification
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

// MakeApiName - canonicalize a routine name into an identifier that is
// simultaneously safe as a URL path segment, a JSON object key, and an
// identifier in C++, Pascal, and Python.
//
// The replacement set MUST match every other generator in this
// toolchain.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

// MakeSafeCppIdent - turn an arbitrary string into a valid C++
// identifier. Empty input yields a generated placeholder. Leading
// digits are prefixed with '_'. C++ reserved words are suffixed with
// '_'.
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
  Result := #34;
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
  Result.Append(#34);
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
      // skip CR
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

// BuildCppArgArrayInit - comma-separated argument names for use inside
// nlohmann::json::array({...}). Empty when the routine has no
// parameters; the caller must then emit nlohmann::json::array().
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
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, BaseUrl, GuardMacro: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedCppFuncNames, CppFuncNames: TPascalStringList;
  ApiName, CppFuncName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  ParamList, RetType: TP_String;
  Description: TP_String;
  ExtraParamSep: TP_String;
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
    // Header preamble
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_cpp_abi_call_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side C++ wrapper for the LingoFuse HTTP/JSON service that');
    Lines.Add('// was generated from the same source unit. Requests go through the');
    Lines.Add('// LingoFuse HTTP bridge (bridge.py) via lingofuse::bridge for the');
    Lines.Add('// synchronous path, and via lingofuse::callAsync for the');
    Lines.Add('// asynchronous path. Both are provided by the LingoFuse C++');
    Lines.Add('// distribution.');
    Lines.Add('//');
    Lines.Add('// Required LingoFuse C++ files (in addition to this pair):');
    Lines.Add('//   * LingoFuse.h, LingoFuse.c           (C ABI)');
    Lines.Add('//   * LingoFuse.hpp, lf_io.hpp           (RAII wrappers + async model)');
    Lines.Add('//   * lf_http_bridge_client.hpp          (bridge transport)');
    Lines.Add('//   * json.hpp                           (nlohmann/json)');
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
    Lines.Add('#include <type_traits>');
    Lines.Add('#include <utility>');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "json.hpp"');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Configuration');
    Lines.Add('//');
    Lines.Add('// Set HTTP_CALL_BASE_URL before the first call. The other four');
    Lines.Add('// variables are optional overrides: leave them empty (or zero) to');
    Lines.Add('// use the bridge client''s own compiled-in defaults.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// Base URL prefix of the target service. The full URL for API "X"');
    Lines.Add('// is HTTP_CALL_BASE_URL + "/" + "X". Must not have a trailing');
    Lines.Add('// slash: the generated code adds it.');
    Lines.Add('extern std::string HTTP_CALL_BASE_URL;');
    Lines.Add('');
    Lines.Add('// LingoFuse App name of the bridge. An empty string means "use the');
    Lines.Add('// bridge client''s default", which is __lf_http_bridge__.');
    Lines.Add('extern std::string HTTP_BRIDGE_APP_NAME;');
    Lines.Add('');
    Lines.Add('// LingoFuse API name of the bridge''s outbound POST proxy. An empty');
    Lines.Add('// string means "use the bridge client''s default", which is');
    Lines.Add('// __lf_outbound_post__.');
    Lines.Add('extern std::string HTTP_BRIDGE_API_NAME;');
    Lines.Add('');
    Lines.Add('// Timeout, in milliseconds, for the LingoFuse round trip that');
    Lines.Add('// carries the request to the bridge and the response back. Zero');
    Lines.Add('// means "use the bridge client''s default" (60000 ms).');
    Lines.Add('//');
    Lines.Add('// Must be larger than the outbound HTTP timeout');
    Lines.Add('// (HTTP_CALL_DEFAULT_TIMEOUT_S * 1000), otherwise the LF_Call');
    Lines.Add('// times out before the HTTP request completes and the caller sees');
    Lines.Add('// an empty response.');
    Lines.Add('extern std::uint64_t HTTP_CALL_TIMEOUT_MS;');
    Lines.Add('');
    Lines.Add('// Outbound HTTP timeout, in seconds, sent inside the bridge');
    Lines.Add('// request. Zero means "use the bridge client''s default" (25.0 s).');
    Lines.Add('extern double HTTP_CALL_DEFAULT_TIMEOUT_S;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Error type');
    Lines.Add('//');
    Lines.Add('// Raised by every synchronous generated function when a call fails');
    Lines.Add('// for any reason. Asynchronous functions do NOT raise; they');
    Lines.Add('// deliver their outcome to the caller-supplied callback as a typed');
    Lines.Add('// ApiNameAsyncResult value.');
    Lines.Add('//');
    Lines.Add('// `code` semantics:');
    Lines.Add('//   * -1: transport / service failure. Any lingofuse::Error from');
    Lines.Add('//         the bridge client except ErrorCode::InvalidArgument, or');
    Lines.Add('//         a service-side exception forwarded by the bridge.');
    Lines.Add('//   * -2: request shape error. Raised when the caller supplied an');
    Lines.Add('//         empty URL, or when the request body could not be');
    Lines.Add('//         serialized.');
    Lines.Add('//   * -4: bridge protocol error (malformed envelope, missing field).');
    Lines.Add('//   * any other value: a service-defined error code forwarded from');
    Lines.Add('//         the service''s { "code": N, "error": "..." } response.');
    Lines.Add('//');
    Lines.Add('// `http_status` is 200 for any well-formed service response and 0');
    Lines.Add('// for transport-level failures.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('class HTTPCallError : public std::runtime_error {');
    Lines.Add('public:');
    Lines.Add('    int code;');
    Lines.Add('    int http_status;');
    Lines.Add('    HTTPCallError(const std::string& message,');
    Lines.Add('                  int code_ = -1,');
    Lines.Add('                  int http_status_ = 0);');
    Lines.Add('};');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Detail helpers');
    Lines.Add('//');
    Lines.Add('// These helpers are shared by the synchronous and the asynchronous');
    Lines.Add('// code paths, so that both paths validate the bridge envelope with');
    Lines.Add('// exactly the same rules.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('namespace detail {');
    Lines.Add('');
    Lines.Add('// Parse a bridge envelope and return its "body" object.');
    Lines.Add('//');
    Lines.Add('// Throws HTTPCallError on any shape violation. On success,');
    Lines.Add('// out_http_status is set to 200.');
    Lines.Add('inline nlohmann::json parse_envelope(const nlohmann::json& envelope,');
    Lines.Add('                                     int& out_http_status) {');
    Lines.Add('    out_http_status = 0;');
    Lines.Add('    if (!envelope.is_object()) {');
    Lines.Add('        throw HTTPCallError("bridge envelope is not a JSON object", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    if (!envelope.contains("body")) {');
    Lines.Add('        throw HTTPCallError("bridge envelope has no ''body'' field", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    const nlohmann::json& body = envelope.at("body");');
    Lines.Add('    if (!body.is_object()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "bridge envelope ''body'' is not a JSON object", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    if (!body.contains("code")) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "service response has no ''code'' field", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    if (!body.at("code").is_number_integer()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "service response ''code'' is not an integer", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    const int service_code = body.at("code").get<int>();');
    Lines.Add('    if (service_code != 0) {');
    Lines.Add('        std::string err = "service reported an error";');
    Lines.Add('        if (body.contains("error") && body.at("error").is_string()) {');
    Lines.Add('            err = body.at("error").get<std::string>();');
    Lines.Add('        }');
    Lines.Add('        throw HTTPCallError(err, service_code, 200);');
    Lines.Add('    }');
    Lines.Add('    out_http_status = 200;');
    Lines.Add('    return body;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// Extract the "result" field of a service response with explicit');
    Lines.Add('// type checking.');
    Lines.Add('//');
    Lines.Add('// Contract:');
    Lines.Add('//   * Missing or null "result"    -> returns T{}.');
    Lines.Add('//   * Integer T, JSON float value -> throws. nlohmann::json''s');
    Lines.Add('//                                    get<std::int64_t>() would');
    Lines.Add('//                                    silently truncate 3.7 to 3,');
    Lines.Add('//                                    which is not acceptable');
    Lines.Add('//                                    across a public API boundary.');
    Lines.Add('//   * Any other type mismatch     -> throws.');
    Lines.Add('template <typename T>');
    Lines.Add('inline T extract_result(const nlohmann::json& body) {');
    Lines.Add('    if (!body.contains("result") || body.at("result").is_null()) {');
    Lines.Add('        return T{};');
    Lines.Add('    }');
    Lines.Add('    const nlohmann::json& slot = body.at("result");');
    Lines.Add('    if (std::is_integral<T>::value && slot.is_number_float()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "service response ''result'' expects an integer, but the "');
    Lines.Add('            "service sent a floating-point number", -1, 200);');
    Lines.Add('    }');
    Lines.Add('    try {');
    Lines.Add('        return slot.get<T>();');
    Lines.Add('    } catch (const nlohmann::json::exception& e) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            std::string("cannot convert service response ''result'': ")');
    Lines.Add('                + e.what(), -1, 200);');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // namespace detail');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Synchronous typed call functions');
    Lines.Add('//');
    Lines.Add('// Each function blocks until the bridge returns a response. On');
    Lines.Add('// failure it throws HTTPCallError; on success it returns the');
    Lines.Add('// extracted result.');
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

    // -------------------------------------------------------------------------
    // Async result struct + async function per API
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Asynchronous typed call functions');
    Lines.Add('//');
    Lines.Add('// Every sync function above has a matching async variant. The');
    Lines.Add('// async variant submits the request through lingofuse::callAsync');
    Lines.Add('// and delivers the outcome through the user-provided callback.');
    Lines.Add('//');
    Lines.Add('// Dispatch failure (LF_Async_Call returns 0, or the request cannot');
    Lines.Add('// be serialized) is reported through the SAME callback,');
    Lines.Add('// synchronously on the caller''s thread, with ok=false. There is');
    Lines.Add('// exactly one error path.');
    Lines.Add('//');
    Lines.Add('// Inside the callback, read or copy everything you need. The');
    Lines.Add('// AsyncResult handle is borrowed by the framework and is released');
    Lines.Add('// the instant the callback returns.');
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
      RetType := ABI_Type_To_Cpp_Decl(f.ReturnType);

      // Async result struct.
      Lines.Add('// Async result of ' + CppFuncName.Text + '.');
      Lines.Add('struct ' + CppFuncName.Text + 'AsyncResult {');
      Lines.Add('    bool ok = false;');
      Lines.Add('    int code = -1;');
      Lines.Add('    int http_status = 0;');
      Lines.Add('    std::string error;');
      if f.IsFunction then
        Lines.Add('    ' + RetType.Text + ' value = {};');
      Lines.Add('};');
      Lines.Add('');

      // Async function (template, inline in header).
      Lines.Add('// ' + Description.Text);
      Lines.Add('// HTTP route: POST /' + AppName.Text + '/' + ApiName.Text);
      Lines.Add('// on_complete receives a ' + CppFuncName.Text + 'AsyncResult.');
      Lines.Add('template <typename F>');
      if Length(f.Params) > 0 then
        ExtraParamSep := ', '
      else
        ExtraParamSep := '';
      Lines.Add('inline void ' + CppFuncName.Text + '_Async(' + ParamList.Text +
        ExtraParamSep.Text + 'F&& on_complete) {');
      Lines.Add('    nlohmann::json req;');
      if Length(f.Params) = 0 then
        Lines.Add('    req["args"] = nlohmann::json::array();')
      else
        Lines.Add('    req["args"] = nlohmann::json::array({' +
          BuildCppArgArrayInit(f.Params).Text + '});');
      Lines.Add('');
      Lines.Add('    nlohmann::json bridge_req;');
      Lines.Add('    bridge_req["url"] = std::string(HTTP_CALL_BASE_URL) + "/' +
        ApiName.Text + '";');
      Lines.Add('    bridge_req["method"] = "POST";');
      Lines.Add('    bridge_req["body"] = req;');
      Lines.Add('    const double effective_http_timeout =');
      Lines.Add('        HTTP_CALL_DEFAULT_TIMEOUT_S > 0.0');
      Lines.Add('            ? HTTP_CALL_DEFAULT_TIMEOUT_S');
      Lines.Add('            : 25.0;');
      Lines.Add('    bridge_req["timeout"] =');
      Lines.Add('        static_cast<int>(effective_http_timeout + 0.5);');
      Lines.Add('');
      Lines.Add('    const std::string effective_app =');
      Lines.Add('        HTTP_BRIDGE_APP_NAME.empty()');
      Lines.Add('            ? std::string("__lf_http_bridge__")');
      Lines.Add('            : HTTP_BRIDGE_APP_NAME;');
      Lines.Add('    const std::string effective_api =');
      Lines.Add('        HTTP_BRIDGE_API_NAME.empty()');
      Lines.Add('            ? std::string("__lf_outbound_post__")');
      Lines.Add('            : HTTP_BRIDGE_API_NAME;');
      Lines.Add('');
      Lines.Add('    lingofuse::callAsync(');
      Lines.Add('        effective_app, effective_api, bridge_req,');
      Lines.Add('        [f = std::forward<F>(on_complete)](');
      Lines.Add('            lingofuse::AsyncResult r) mutable {');
      Lines.Add('            ' + CppFuncName.Text + 'AsyncResult result;');
      Lines.Add('            if (!r.ok()) {');
      Lines.Add('                result.error = r.error();');
      Lines.Add('                f(std::move(result));');
      Lines.Add('                return;');
      Lines.Add('            }');
      Lines.Add('            try {');
      Lines.Add('                nlohmann::json envelope = r.handle().readJson();');
      Lines.Add('                int http_status = 0;');
      Lines.Add('                nlohmann::json body =');
      Lines.Add('                    detail::parse_envelope(envelope, http_status);');
      Lines.Add('                result.http_status = http_status;');
      if f.IsFunction then
        Lines.Add('                result.value = detail::extract_result<' +
          RetType.Text + '>(body);');
      Lines.Add('                result.ok = true;');
      Lines.Add('                result.code = 0;');
      Lines.Add('            } catch (const HTTPCallError& e) {');
      Lines.Add('                result.error = e.what();');
      Lines.Add('                result.code = e.code;');
      Lines.Add('                result.http_status = e.http_status;');
      Lines.Add('            } catch (const std::exception& e) {');
      Lines.Add('                result.error = e.what();');
      Lines.Add('                result.code = -1;');
      Lines.Add('            }');
      Lines.Add('            f(std::move(result));');
      Lines.Add('        });');
      Lines.Add('}');
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
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, BaseUrl, HeaderFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedCppFuncNames, CppFuncNames: TPascalStringList;
  ApiName, CppFuncName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  ParamList, RetType: TP_String;
  ArgInit: TP_String;
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
    // File header and includes
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_cpp_abi_call_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Implementation of the C++ HTTP/JSON call wrapper declared in');
    Lines.Add('// "' + HeaderFileName.Text + '".');
    Lines.Add('//');
    Lines.Add('// The synchronous path delegates to lingofuse::bridge::httpCall,');
    Lines.Add('// which is provided by lf_http_bridge_client.hpp. The asynchronous');
    Lines.Add('// path is entirely template code and lives in the header. Both');
    Lines.Add('// paths share detail::parse_envelope and detail::extract_result<T>');
    Lines.Add('// for envelope validation and result extraction, so the two paths');
    Lines.Add('// observe exactly the same protocol rules.');
    Lines.Add('');
    Lines.Add('#include "' + HeaderFileName.Text + '"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_http_bridge_client.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <string>');
    Lines.Add('#include <type_traits>');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Configuration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('std::string HTTP_CALL_BASE_URL = ' + CppStrLit(BaseUrl).Text + ';');
    Lines.Add('std::string HTTP_BRIDGE_APP_NAME = "";');
    Lines.Add('std::string HTTP_BRIDGE_API_NAME = "";');
    Lines.Add('std::uint64_t HTTP_CALL_TIMEOUT_MS = 0;');
    Lines.Add('double HTTP_CALL_DEFAULT_TIMEOUT_S = 0.0;');
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
    Lines.Add('// Internal sync helper');
    Lines.Add('//');
    Lines.Add('// One helper in an anonymous namespace. It does two things:');
    Lines.Add('//   1. Call the bridge through lingofuse::bridge::httpCall and');
    Lines.Add('//      translate any lingofuse::Error into HTTPCallError.');
    Lines.Add('//   2. Hand the bridge envelope to detail::parse_envelope, which');
    Lines.Add('//      is the same validator used by the async path.');
    Lines.Add('//');
    Lines.Add('// The helper is in an anonymous namespace, which gives it internal');
    Lines.Add('// linkage; a `static` qualifier would be redundant.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('nlohmann::json _invoke(const std::string& url,');
    Lines.Add('                       const nlohmann::json& request_body) {');
    Lines.Add('    const char* app_name = HTTP_BRIDGE_APP_NAME.empty()');
    Lines.Add('        ? nullptr');
    Lines.Add('        : HTTP_BRIDGE_APP_NAME.c_str();');
    Lines.Add('    const char* api_name = HTTP_BRIDGE_API_NAME.empty()');
    Lines.Add('        ? nullptr');
    Lines.Add('        : HTTP_BRIDGE_API_NAME.c_str();');
    Lines.Add('');
    Lines.Add('    nlohmann::json envelope;');
    Lines.Add('    try {');
    Lines.Add('        envelope = lingofuse::bridge::httpCall(');
    Lines.Add('            url,');
    Lines.Add('            "POST",');
    Lines.Add('            request_body,');
    Lines.Add('            HTTP_CALL_DEFAULT_TIMEOUT_S,');
    Lines.Add('            app_name,');
    Lines.Add('            api_name,');
    Lines.Add('            HTTP_CALL_TIMEOUT_MS);');
    Lines.Add('    } catch (const lingofuse::Error& e) {');
    Lines.Add('        const int code =');
    Lines.Add('            (e.code() == lingofuse::ErrorCode::InvalidArgument)');
    Lines.Add('                ? -2');
    Lines.Add('                : -1;');
    Lines.Add('        throw HTTPCallError(e.what(), code, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    int http_status = 0;');
    Lines.Add('    return detail::parse_envelope(envelope, http_status);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // anonymous namespace');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Synchronous typed call functions');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    // Sync function definitions.
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
      if Length(f.Params) = 0 then
        Lines.Add('    req["args"] = nlohmann::json::array();')
      else
        Lines.Add('    req["args"] = nlohmann::json::array({' + ArgInit.Text + '});');
      Lines.Add('');
      Lines.Add('    const nlohmann::json body = _invoke(url, req);');

      if f.IsFunction then
      begin
        Lines.Add('');
        Lines.Add('    return detail::extract_result<' + RetType.Text + '>(body);');
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

initialization
  RegisterCodeGenEntry(
    'cpp', 'C++ HTTP/JSON call header',
    asCall, akCallHeader,
    '_http_json_call.hpp', False,
    @GenerateHTTPCallCppHeader);
  RegisterCodeGenEntry(
    'cpp', 'C++ HTTP/JSON call implementation',
    asCall, akCallCode,
    '_http_json_call.cpp', False,
    @GenerateHTTPCallCppCode);
end.
