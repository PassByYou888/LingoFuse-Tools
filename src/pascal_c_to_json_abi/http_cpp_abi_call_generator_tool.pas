unit http_cpp_abi_call_generator_tool;

// http_cpp_abi_call_generator_tool - LingoFuse HTTP/JSON ABI Call-Side
// Generator for C++.
//
// Consumes a TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI) and
// produces three artifacts:
//
//   1. A C++ header (*.hpp) that declares the call-side namespace, its
//      configuration globals, the HTTPCallError class, and one typed
//      free function per supported routine.
//
//   2. A C++ implementation (*.cpp) that defines the configuration
//      globals, the error class, and every generated call function.
//      The transport is delegated to the C++ bridge client shipped
//      with the LingoFuse distribution (lf_http_bridge_client.hpp),
//      i.e. lingofuse::bridge::httpCall.
//
//   3. A Markdown README describing the contract, deployment, a full
//      CMake script, a minimal test program, and a machine-readable
//      summary for AI agents.
//
// Revision notes (v3):
//
//   - The README CMake script now declares "C CXX" as the project
//     languages. LingoFuse.c is a C source file and cannot be compiled
//     when only the CXX language is enabled; the previous CXX-only
//     project failed at configure time with "Cannot determine link
//     language".
//
//   - The dead catch clause for nlohmann::json::exception in _invoke
//     has been removed. Every JSON failure that can reach the caller
//     is already wrapped into lingofuse::Error by the bridge client.
//
//   - The redundant `static` on the anonymous-namespace helpers has
//     been removed; symbols inside an anonymous namespace already
//     have internal linkage.
//
//   - The error code -2 is now meaningful. When the bridge client
//     reports ErrorCode::InvalidArgument (empty URL, un-serializable
//     request body), the wrapper maps it to -2 rather than collapsing
//     it into the generic -1 transport code. The header comment
//     documents this exactly.
//
//   - The README troubleshooting table now lists the symptom of a
//     missing LibraryLoader (lingofuse::Error "App: LF_CreateApp
//     failed"), which was previously only documented on the service
//     side.
//
// Revision notes (v2):
//
//   - The generated client no longer touches the C ABI directly. It
//     calls lingofuse::bridge::httpCall, the cross-language-canonical
//     bridge transport, so the generated code stays consistent with
//     the C++ bridge client, the Pascal bridge client, and the Python
//     bridge client.
//
//   - Every exception raised by the transport layer is translated
//     into HTTPCallError. Callers only ever need to catch one type.
//
//   - The generated code rejects a JSON float sent for an integer
//     result instead of silently truncating it.
//
//   - The bridge request "timeout" field is emitted as an integer,
//     matching every other language binding in this toolchain.
//
// Wire protocol (from the client's point of view):
//   the client sends   = lingofuse::bridge::httpCall(...)
//   the bridge returns = { "status_code": ..., "headers": {...},
//                          "body": { "code": 0, "result": ... } }
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
// toolchain:
//   * http_pas_abi_service_generator_tool
//   * http_pas_abi_call_generator_tool
//   * http_js_abi_call_generator_tool
//   * http_py_abi_service_generator_tool
//   * http_py_abi_call_generator_tool
//   * http_cpp_abi_service_generator_tool
//
// Replaced characters: space, tab, '.', '/', '\', '@', ':', '#', '?',
// '&', '=', '+', '-'.
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

      // The C++ function name may differ from the API name when the
      // sanitized API name is a C++ reserved word (for example a
      // Pascal routine literally named 'class'). In that case the C++
      // function gets a '_' suffix while the URL path keeps the raw
      // sanitized name, because that is what the service side
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
    Lines.Add('// was generated from the same source unit. Requests go through the');
    Lines.Add('// LingoFuse HTTP bridge (bridge.py) via lingofuse::bridge, which is');
    Lines.Add('// provided by the LingoFuse C++ distribution.');
    Lines.Add('//');
    Lines.Add('// Required LingoFuse C++ files (in addition to this pair):');
    Lines.Add('//   * LingoFuse.h, LingoFuse.c           (C ABI)');
    Lines.Add('//   * LingoFuse.hpp, lf_io.hpp           (RAII wrappers)');
    Lines.Add('//   * lf_http_bridge_client.hpp          (bridge transport)');
    Lines.Add('//   * json.hpp                           (nlohmann/json)');
    Lines.Add('//');
    Lines.Add('// The transport is fully encapsulated in the paired .cpp file.');
    Lines.Add('// This header only exposes configuration, the exception type, and');
    Lines.Add('// the typed call functions.');
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
    Lines.Add('// Raised by every generated function when a call fails for any');
    Lines.Add('// reason. The transport layer (lingofuse::bridge) raises');
    Lines.Add('// lingofuse::Error; this wrapper translates every such exception');
    Lines.Add('// into HTTPCallError so that the caller only ever needs to catch');
    Lines.Add('// one type.');
    Lines.Add('//');
    Lines.Add('// `code` semantics:');
    Lines.Add('//   * -1: transport / service failure. Any lingofuse::Error from');
    Lines.Add('//         the bridge client except ErrorCode::InvalidArgument, or');
    Lines.Add('//         a service-side exception forwarded by the bridge.');
    Lines.Add('//   * -2: request shape error. Raised when the caller supplied an');
    Lines.Add('//         empty URL, or when the request body could not be');
    Lines.Add('//         serialized. These are caller-side mistakes rather than');
    Lines.Add('//         transport failures, so they are reported distinctly.');
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
    Lines.Add('    // Bridge / service error code. See the comment above for the');
    Lines.Add('    // exact meaning of each value.');
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
    Lines.Add('// The transport is delegated to lingofuse::bridge::httpCall, which');
    Lines.Add('// is provided by lf_http_bridge_client.hpp. This keeps the generated');
    Lines.Add('// code aligned with the canonical C++ bridge client and avoids');
    Lines.Add('// duplicating the wire protocol in every generated client.');
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
    Lines.Add('// Internal helpers');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// Every helper in this anonymous namespace has internal linkage');
    Lines.Add('// by virtue of the unnamed namespace; a `static` qualifier would');
    Lines.Add('// be redundant.');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('// Send a request through the bridge and return the service''s parsed');
    Lines.Add('// response "body" object.');
    Lines.Add('//');
    Lines.Add('// Responsibilities:');
    Lines.Add('//   1. Forward the request to the bridge via lingofuse::bridge,');
    Lines.Add('//      using the caller''s configuration and falling back to the');
    Lines.Add('//      bridge client''s compiled-in defaults where a setting is');
    Lines.Add('//      empty or zero.');
    Lines.Add('//   2. Validate the bridge envelope and the service response.');
    Lines.Add('//   3. Translate every transport-level failure into HTTPCallError.');
    Lines.Add('//   4. Raise HTTPCallError with the service error code when the');
    Lines.Add('//      service responds with a non-zero "code" field.');
    Lines.Add('//');
    Lines.Add('// On success, the returned object is the service''s "body", which');
    Lines.Add('// is guaranteed to have a "code" field equal to 0. The caller only');
    Lines.Add('// needs to extract "result".');
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
    Lines.Add('        // lingofuse::bridge::httpCall throws lingofuse::Error on');
    Lines.Add('        // any transport-level failure: empty URL, network');
    Lines.Add('        // unreachable, bridge App not on the mesh, LF_Call');
    Lines.Add('        // timeout, malformed bridge envelope, etc. Every JSON');
    Lines.Add('        // failure that can reach this point is already wrapped');
    Lines.Add('        // into lingofuse::Error by the bridge client, so a single');
    Lines.Add('        // catch clause covers all transport failures.');
    Lines.Add('        envelope = lingofuse::bridge::httpCall(');
    Lines.Add('            url,');
    Lines.Add('            "POST",');
    Lines.Add('            request_body,');
    Lines.Add('            HTTP_CALL_DEFAULT_TIMEOUT_S,');
    Lines.Add('            app_name,');
    Lines.Add('            api_name,');
    Lines.Add('            HTTP_CALL_TIMEOUT_MS);');
    Lines.Add('    } catch (const lingofuse::Error& e) {');
    Lines.Add('        // Distinguish caller-side shape errors from genuine');
    Lines.Add('        // transport failures. ErrorCode::InvalidArgument is');
    Lines.Add('        // raised for an empty URL or an un-serializable request');
    Lines.Add('        // body; both are the caller''s fault, so they are');
    Lines.Add('        // reported with code -2 rather than collapsed into the');
    Lines.Add('        // generic -1 transport code.');
    Lines.Add('        const int code =');
    Lines.Add('            (e.code() == lingofuse::ErrorCode::InvalidArgument)');
    Lines.Add('                ? -2');
    Lines.Add('                : -1;');
    Lines.Add('        throw HTTPCallError(e.what(), code, 0);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // The bridge response is an envelope of the form');
    Lines.Add('    //     { "status_code": ..., "headers": {...}, "body": {...} }');
    Lines.Add('    // The service''s actual response is inside "body".');
    Lines.Add('    if (!envelope.is_object()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "bridge envelope is not a JSON object", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    if (!envelope.contains("body")) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "bridge envelope has no ''body'' field", -4, 0);');
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
    Lines.Add('');
    Lines.Add('    // The code field must be a JSON integer. A non-integer value');
    Lines.Add('    // (string, float, object) is a protocol violation, so it is');
    Lines.Add('    // reported as -4 rather than silently coerced.');
    Lines.Add('    if (!body.at("code").is_number_integer()) {');
    Lines.Add('        throw HTTPCallError(');
    Lines.Add('            "service response ''code'' is not an integer", -4, 0);');
    Lines.Add('    }');
    Lines.Add('    const int service_code = body.at("code").get<int>();');
    Lines.Add('');
    Lines.Add('    if (service_code != 0) {');
    Lines.Add('        std::string err = "service reported an error";');
    Lines.Add('        if (body.contains("error") && body.at("error").is_string()) {');
    Lines.Add('            err = body.at("error").get<std::string>();');
    Lines.Add('        }');
    Lines.Add('        throw HTTPCallError(err, service_code, 200);');
    Lines.Add('    }');
    Lines.Add('');
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
    Lines.Add('T _extract_result(const nlohmann::json& body) {');
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
    Lines.Add('}  // anonymous namespace');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Typed call functions');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    // Function definitions.
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
        Lines.Add('    return _extract_result<' + RetType.Text + '>(body);');
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
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
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
    Lines.Add('The generated wrapper depends on the standard LingoFuse C++');
    Lines.Add('distribution. In particular, it calls `lingofuse::bridge`, the');
    Lines.Add('canonical C++ bridge client. The five files that must be present');
    Lines.Add('on the include path are:');
    Lines.Add('');
    Lines.Add('| Piece | Files | Purpose |');
    Lines.Add('|-------|-------|---------|');
    Lines.Add('| LingoFuse C ABI | `LingoFuse.h` + `LingoFuse.c` | Loads the dynamic library, forwarders |');
    Lines.Add('| LingoFuse C++ RAII | `LingoFuse.hpp` | `DataHandle`, `App`, `LibraryLoader` |');
    Lines.Add('| LingoFuse payload I/O | `lf_io.hpp` | UTF-8 JSON framing over a data handle |');
    Lines.Add('| Bridge transport | `lf_http_bridge_client.hpp` | The `lingofuse::bridge` namespace |');
    Lines.Add('| JSON engine | `json.hpp` | nlohmann/json single-header |');
    Lines.Add('');
    Lines.Add('The generated code does **not** re-implement the bridge wire');
    Lines.Add('protocol. It relies on `lingofuse::bridge::httpCall`, which is');
    Lines.Add('the same entry point used by every other C++ bridge client in');
    Lines.Add('this toolchain.');
    Lines.Add('');
    Lines.Add('### 1.2 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + HeaderFileName.Text + '` | The call wrapper header. |');
    Lines.Add('| `' + CodeFileName.Text + '` | The call wrapper implementation. |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_call_cpp.md` | This README. |');
    Lines.Add('');
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Prepare LingoFuse');
    Lines.Add('');
    Lines.Add('Your program must prepare LingoFuse before the first call. The');
    Lines.Add('`LibraryLoader` is the essential first step: it calls');
    Lines.Add('`LF_LoadLibrary` in its constructor. Without it, every `LF_*`');
    Lines.Add('entry point is a silent no-op and `LF_CreateApp` returns');
    Lines.Add('`NULL`.');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    lingofuse::LibraryLoader loader;');
    Lines.Add('    lingofuse::resetPrepare();');
    Lines.Add('    lingofuse::prepareClient("ipc:' + NormalizedUnit.Text + '_http_json", nullptr);');
    Lines.Add('    if (lingofuse::prepareDone() != 1) {');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('    // ... your calls ...');
    Lines.Add('    lingofuse::exitMainThread();');
    Lines.Add('    lingofuse::shutdown();');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `LibraryLoader` RAII wrapper manages the reference count on');
    Lines.Add('`LF_LoadLibrary` / `LF_FreeLibrary`. The bridge App name defaults');
    Lines.Add('to `__lf_http_bridge__`; you only need to override it if your');
    Lines.Add('deployment used a non-default `--bridge-app` argument.');
    Lines.Add('');
    Lines.Add('### 2.2 Configure the client');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add(Ns.Text + '::HTTP_CALL_BASE_URL = ' + CppStrLit(BaseUrl).Text + ';');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The other four globals are optional overrides. Leave them empty');
    Lines.Add('(or zero) to use the bridge client''s compiled-in defaults:');
    Lines.Add('');
    Lines.Add('| Variable | Default if empty |');
    Lines.Add('|----------|------------------|');
    Lines.Add('| `HTTP_BRIDGE_APP_NAME` | `__lf_http_bridge__` |');
    Lines.Add('| `HTTP_BRIDGE_API_NAME` | `__lf_outbound_post__` |');
    Lines.Add('| `HTTP_CALL_TIMEOUT_MS` | `60000` ms |');
    Lines.Add('| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `25.0` s |');
    Lines.Add('');
    Lines.Add('### 2.3 Make a call');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('try {');
    Lines.Add('    std::int64_t r = ' + Ns.Text + '::Add(3, 4);');
    Lines.Add('    std::cout << "Add(3, 4) = " << r << "\n";');
    Lines.Add('} catch (const ' + Ns.Text + '::HTTPCallError& e) {');
    Lines.Add('    std::cerr << "Call failed: " << e.what()');
    Lines.Add('              << " (code=" << e.code');
    Lines.Add('              << ", http_status=" << e.http_status << ")\n";');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('| Compiler | Minimum version |');
    Lines.Add('|----------|-----------------|');
    Lines.Add('| GCC | 7 |');
    Lines.Add('| Clang | 6 |');
    Lines.Add('| MSVC | 2019 (19.20) |');
    Lines.Add('');
    Lines.Add('The generated code requires C++17.');
    Lines.Add('');
    Lines.Add('### 3.1 Threading');
    Lines.Add('');
    Lines.Add('Generated functions are synchronous and blocking. `LF_Call` is');
    Lines.Add('thread-safe, so multiple threads may call different functions');
    Lines.Add('concurrently. The five configuration globals are not atomic: set');
    Lines.Add('them once at startup, before any call, and do not modify them');
    Lines.Add('while a call is in flight.');
    Lines.Add('');
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The transport is entirely handled by `lingofuse::bridge::httpCall`;');
    Lines.Add('the generated code never speaks HTTP directly. This section');
    Lines.Add('documents what that helper does on the caller''s behalf.');
    Lines.Add('');
    Lines.Add('### 4.1 URL composition');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('HTTP_CALL_BASE_URL + "/" + <api-name>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.2 Bridge request');
    Lines.Add('');
    Lines.Add('`lingofuse::bridge::httpCall` sends a LingoFuse call to the');
    Lines.Add('bridge with this JSON body:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "url":     "<HTTP_CALL_BASE_URL>/<api>",');
    Lines.Add('  "method":  "POST",');
    Lines.Add('  "body":    { "args": [v1, v2, ...] },');
    Lines.Add('  "timeout": 25');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.3 Bridge response');
    Lines.Add('');
    Lines.Add('The bridge returns an envelope:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "status_code": 200,');
    Lines.Add('  "headers":     { ... },');
    Lines.Add('  "body":        { "code": 0, "result": <value> }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated code unwraps the envelope, checks `body.code` and');
    Lines.Add('either returns `body.result` or throws `HTTPCallError`.');
    Lines.Add('');
    Lines.Add('### 4.4 Error model');
    Lines.Add('');
    Lines.Add('Every failure mode is translated into `HTTPCallError`:');
    Lines.Add('');
    Lines.Add('| Condition | `code` | `http_status` |');
    Lines.Add('|-----------|:------:|:-------------:|');
    Lines.Add('| Empty URL or un-serializable request body | `-2` | `0` |');
    Lines.Add('| LingoFuse call timed out | `-1` | `0` |');
    Lines.Add('| Bridge App unreachable | `-1` | `0` |');
    Lines.Add('| Bridge-level error (`{"error": "..."}`) | `-1` | `0` |');
    Lines.Add('| Bridge envelope missing `body` | `-4` | `0` |');
    Lines.Add('| Bridge envelope `body` not an object | `-4` | `0` |');
    Lines.Add('| Response lacks `code` or `code` is not an integer | `-4` | `0` |');
    Lines.Add('| Service returned `code != 0` | service code | `200` |');
    Lines.Add('| Response `result` type mismatch | `-1` | `200` |');
    Lines.Add('');
    Lines.Add('## 5. Global Configuration');
    Lines.Add('');
    Lines.Add('| Variable | Type | Default | Purpose |');
    Lines.Add('|----------|------|---------|---------|');
    Lines.Add('| `HTTP_CALL_BASE_URL` | `std::string` | `' + BaseUrl.Text + '` | Base URL of the target service. Must be set. |');
    Lines.Add('| `HTTP_BRIDGE_APP_NAME` | `std::string` | `""` | Bridge App name. Empty means "use the bridge default". |');
    Lines.Add('| `HTTP_BRIDGE_API_NAME` | `std::string` | `""` | Bridge outbound API name. Empty means "use the bridge default". |');
    Lines.Add('| `HTTP_CALL_TIMEOUT_MS` | `std::uint64_t` | `0` | LingoFuse round-trip timeout. 0 means "use the bridge default". |');
    Lines.Add('| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `double` | `0.0` | HTTP timeout inside the bridge request. 0.0 means "use the bridge default". |');
    Lines.Add('');
    Lines.Add('## 6. Error Handling');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('class HTTPCallError : public std::runtime_error {');
    Lines.Add('public:');
    Lines.Add('    int code;         // -1 (transport) / -2 (shape) / -4 (protocol)');
    Lines.Add('    int http_status;  // 0 for transport errors, 200 for service errors');
    Lines.Add('    HTTPCallError(const std::string& message,');
    Lines.Add('                  int code_ = -1,');
    Lines.Add('                  int http_status_ = 0);');
    Lines.Add('};');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated code translates every `lingofuse::Error` into');
    Lines.Add('`HTTPCallError`. Callers do not need to know about');
    Lines.Add('`lingofuse::Error` or any other LingoFuse exception type.');
    Lines.Add('');
    Lines.Add('| Code | Meaning |');
    Lines.Add('|------|---------|');
    Lines.Add('| `0` | Success. Never thrown. |');
    Lines.Add('| `-1` | Transport failure: LF_Call timeout, bridge unreachable, or a service-side exception forwarded by the bridge. |');
    Lines.Add('| `-2` | Request shape error: empty URL or un-serializable request body. |');
    Lines.Add('| `-4` | Bridge protocol error: malformed envelope or missing field. |');
    Lines.Add('| any other value | A service-defined error code from the service''s `{"code": N, "error": "..."}` response. |');
    Lines.Add('');
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
          Lines.Add('**Description**: ' + Description.Text);
          Lines.Add('');
        end;

        if HasParams then
        begin
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
        Lines.Add('              << " (code=" << e.code << ")\n";');
        Lines.Add('}');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    Lines.Add('## 8. Building - Manual');
    Lines.Add('');
    Lines.Add('The generated wrapper is a library that you compile into your');
    Lines.Add('own program. It requires exactly one third-party source file to');
    Lines.Add('be compiled in: `LingoFuse.c`. Everything else is headers.');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('g++ -std=c++17 -O2 \\');
    Lines.Add('    -I. \\');
    Lines.Add('    your_main.cpp ' + CodeFileName.Text + ' LingoFuse.c \\');
    Lines.Add('    -o your_app \\');
    Lines.Add('    -pthread -ldl');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Note that `LingoFuse.c` is a C file. When you invoke a C++');
    Lines.Add('compiler driver like `g++` it will compile the `.c` file as C++');
    Lines.Add('by default. That is usually fine, but if your build uses a');
    Lines.Add('stricter toolchain, compile `LingoFuse.c` with a C compiler and');
    Lines.Add('link the resulting object file.');
    Lines.Add('');
    Lines.Add('### 8.1 Minimal MSVC build');
    Lines.Add('');
    Lines.Add('```cmd');
    Lines.Add('cl /std:c++17 /O2 /EHsc ^');
    Lines.Add('   /I. ^');
    Lines.Add('   your_main.cpp ' + CodeFileName.Text + ' LingoFuse.c ^');
    Lines.Add('   /Fe:your_app.exe');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 9. Building - CMake');
    Lines.Add('');
    Lines.Add('The `project()` line must enable BOTH the `C` and `CXX`');
    Lines.Add('languages. `LingoFuse.c` is a C source file, and CMake cannot');
    Lines.Add('determine a link language for a target that contains a `.c` file');
    Lines.Add('when only `CXX` is enabled. Enabling `C CXX` lets CMake route');
    Lines.Add('`LingoFuse.c` to the C compiler and everything else to the C++');
    Lines.Add('compiler.');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('project(' + NormalizedUnit.Text + '_http_json_call_test C CXX)');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('');
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
    Lines.Add('# Copy the Windows runtime DLLs next to the executable so that');
    Lines.Add('# the program can find them without a manual PATH change.');
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
    Lines.Add('## 10. Minimal Test Program');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('#include "' + HeaderFileName.Text + '"');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstdio>');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    lingofuse::LibraryLoader loader;');
    Lines.Add('    lingofuse::resetPrepare();');
    Lines.Add('    lingofuse::prepareClient("ipc:' + NormalizedUnit.Text + '_http_json", nullptr);');
    Lines.Add('    if (lingofuse::prepareDone() != 1) {');
    Lines.Add('        std::fprintf(stderr, "LingoFuse init failed\n");');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    ' + Ns.Text + '::HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/' + NormalizedUnit.Text + '";');
    Lines.Add('');
    Lines.Add('    try {');

    if FuncCount > 0 then
    begin
      f := SupportedFuncs[0];
      CppFuncName := CppFuncNames[0];
      CallArgs := BuildCppCallArgList(f.Params);

      if f.IsFunction then
      begin
        Lines.Add('        auto r = ' + Ns.Text + '::' + CppFuncName.Text +
          '(' + CallArgs.Text + ');');
        Lines.Add('        std::printf("call succeeded\n");');
      end
      else
      begin
        Lines.Add('        ' + Ns.Text + '::' + CppFuncName.Text +
          '(' + CallArgs.Text + ');');
        Lines.Add('        std::printf("call succeeded\n");');
      end;
    end
    else
      Lines.Add('        // No supported routines were generated for this unit.');

    Lines.Add('    } catch (const ' + Ns.Text + '::HTTPCallError& e) {');
    Lines.Add('        std::fprintf(stderr, "Call failed: %s (code=%d, http=%d)\n",');
    Lines.Add('                     e.what(), e.code, e.http_status);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    lingofuse::exitMainThread();');
    Lines.Add('    lingofuse::shutdown();');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 11. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| `lingofuse::Error: LibraryLoader: LF_LoadLibrary failed` | The LingoFuse dynamic library is not on the search path | Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` next to the executable, or add its directory to PATH / LD_LIBRARY_PATH |');
    Lines.Add('| `lingofuse::Error: App: LF_CreateApp failed` | `LF_LoadLibrary` was never called | Add `lingofuse::LibraryLoader loader;` as the first statement of `main()` |');
    Lines.Add('| `code == -1`, `http_status == 0` | Transport failure | Start `bridge.py`; verify `HTTP_CALL_BASE_URL` |');
    Lines.Add('| `code == -2` | Request shape error: empty URL or un-serializable body | Verify `HTTP_CALL_BASE_URL` is non-empty and the arguments can be serialized to JSON |');
    Lines.Add('| `code == -4` | Bridge protocol error | Bridge returned an unexpected envelope; check the bridge log |');
    Lines.Add('| `code == -3` | Bridge pre-check failed | Start the bridge with `--no-precheck`, or retry after ~3 s |');
    Lines.Add('| Service returns wrong result type | The service sent a JSON type that does not match the declared Pascal type | Fix the service, or widen the declared type |');
    Lines.Add('| Linker error: undefined reference to `LF_*` | `LingoFuse.c` not compiled in | Add it to the same build target |');
    Lines.Add('| CMake: "Cannot determine link language" | `project()` declares only `CXX` | Change to `project(name C CXX)` |');
    Lines.Add('| Linker error: undefined reference to `dlopen` | Missing `-ldl` on Linux | Add `-ldl` to the link line |');
    Lines.Add('');
    Lines.Add('## 12. For AI Agents');
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
    Lines.Add('  - LingoFuse.h            # C ABI declarations');
    Lines.Add('  - LingoFuse.c            # C ABI implementation (compile it in)');
    Lines.Add('  - LingoFuse.hpp          # C++ RAII wrappers');
    Lines.Add('  - lf_io.hpp              # unified payload I/O');
    Lines.Add('  - lf_http_bridge_client.hpp  # lingofuse::bridge transport');
    Lines.Add('  - json.hpp               # nlohmann/json single header');
    Lines.Add('');
    Lines.Add('transport:');
    Lines.Add('  provider: lingofuse::bridge::httpCall');
    Lines.Add('  protocol: JSON over the LingoFuse mesh to bridge.py');
    Lines.Add('');
    Lines.Add('global_configuration:');
    Lines.Add('  HTTP_CALL_BASE_URL: "' + BaseUrl.Text + '"');
    Lines.Add('  HTTP_BRIDGE_APP_NAME: ""            # empty -> bridge default');
    Lines.Add('  HTTP_BRIDGE_API_NAME: ""            # empty -> bridge default');
    Lines.Add('  HTTP_CALL_TIMEOUT_MS: 0             # 0 -> bridge default');
    Lines.Add('  HTTP_CALL_DEFAULT_TIMEOUT_S: 0.0    # 0.0 -> bridge default');
    Lines.Add('');
    Lines.Add('outbound_request:');
    Lines.Add('  transport_call: lingofuse::bridge::httpCall(url, "POST", body, http_timeout, app, api, lf_timeout)');
    Lines.Add('  url: "HTTP_CALL_BASE_URL + ''/'' + api_name"');
    Lines.Add('  body: ''{"args": [v1, v2, ..., vN]}''');
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
    Lines.Add('    code: "int, -1/-2/-4 or a service code"');
    Lines.Add('    http_status: "int, 0 for transport errors"');
    Lines.Add('  translation:');
    Lines.Add('    source: [lingofuse::Error]');
    Lines.Add('    target: HTTPCallError');
    Lines.Add('    special_cases:');
    Lines.Add('      - "lingofuse::ErrorCode::InvalidArgument -> code = -2"');
    Lines.Add('');
    Lines.Add('types:');
    Lines.Add('  cpp_int: "std::int64_t"');
    Lines.Add('  cpp_float: "double"');
    Lines.Add('  cpp_str: "std::string"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 12.1 Anti-patterns');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Missing `lingofuse::LibraryLoader` | Every `LF_*` call is a silent no-op; `LF_CreateApp` returns NULL | Make `LibraryLoader` the first object in `main()` |');
    Lines.Add('| Calling a function before `prepareDone()` | LingoFuse mesh not ready | Prepare LingoFuse first |');
    Lines.Add('| Setting `HTTP_CALL_BASE_URL` after the first call | Race with in-flight calls | Set once at startup |');
    Lines.Add('| Catching `std::exception` instead of `HTTPCallError` | Hides unrelated bugs | Catch `HTTPCallError` explicitly |');
    Lines.Add('| Catching `lingofuse::Error` on a generated call | It is never thrown by the generated code | Catch `HTTPCallError` |');
    Lines.Add('| Omitting `LingoFuse.c` from the build | Linker error | Add it to the same target |');
    Lines.Add('| `project(name CXX)` in CMake | CMake cannot link a target that contains a `.c` file | Use `project(name C CXX)` |');
    Lines.Add('| Omitting `-ldl` on Linux | Linker error | Add `-ldl` to the link line |');
    Lines.Add('| Using `int`/`float` instead of `std::int64_t`/`double` | Silent truncation at the API boundary | Use the generated types verbatim |');
    Lines.Add('');
    Lines.Add('### 12.2 What this document does NOT cover');
    Lines.Add('');
    Lines.Add('- The internal implementation of `bridge.py`.');
    Lines.Add('- The internal implementation of `lingofuse::bridge`.');
    Lines.Add('- The service side. See the paired');
    Lines.Add('  `' + NormalizedUnit.Text + '_http_json_service_cpp.md`.');
    Lines.Add('- Other language bindings (Pascal, Python, JavaScript).');
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
