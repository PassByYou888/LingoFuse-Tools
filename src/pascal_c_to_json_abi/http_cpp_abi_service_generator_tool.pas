unit http_cpp_abi_service_generator_tool;

// http_cpp_abi_service_generator_tool - LingoFuse HTTP/JSON ABI Service
// Provider Generator for C++.
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces three artifacts:
//
//   1. A C++ header file (*.hpp) declaring the service namespace, its
//      configuration constants, one stub per exposed API, and the
//      registration helpers.
//
//   2. A C++ implementation file (*.cpp) defining the stubs (with TODO
//      markers), the cdecl callbacks, the registration function, and a
//      ready-to-run main().
//
//   3. A Markdown README describing the contract, deployment, testing,
//      and a machine-readable summary for AI agents. The README also
//      contains a complete CMake script and a minimal "add to your
//      project" recipe, so the caller can pick whichever fits.
//
// The generated service is a LingoFuse Call service reachable via
// bridge.py from any HTTP client. It uses the C++ RAII wrappers from
// LingoFuse.hpp (lingofuse::App, lingofuse::DataHandle) and the unified
// JSON I/O from lf_io.hpp (lingofuse::io).
//
// Wire protocol (HTTP/JSON path, both directions):
//   request  = JSON object
//              { "args": [v1, v2, ...] }     positional arguments
//              { "a": v1, "b": v2, ... }     named arguments
//   response = JSON object
//              { "code": 0,  "result": ... }  on success
//              { "code": -1, "error":  ... }  on failure
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   Every integer family member  -> std::int64_t
//   Every float family member    -> double
//   Every string family member   -> std::string
//
// The generated C++ source has no third-party dependency beyond
// LingoFuse.hpp, json.hpp, and the C++ standard library.
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

// GenerateHTTPServiceCppHeader - main entry point for the C++ header.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServiceCppHeader(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPServiceCppCode - main entry point for the C++ implementation.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPServiceCppReadme - main entry point for the README.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServiceCppReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_cpp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_cpp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

// ABI_Type_To_Cpp_Decl - canonical C++ type for an ABI type. Integers
// collapse to std::int64_t, floats to double, strings to std::string.
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

// ABI_Type_To_Cpp_Default - C++ literal for the argument's default
// value, used when the caller did not supply it.
function ABI_Type_To_Cpp_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'std::string()'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := '{}';
end;

// ABI_Type_To_Pascal_Decl - Pascal type keyword used by the README only.
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
  else
    Result := '';
end;

// ABI_Type_To_Json_Wire_Type - coarse wire type used by the README only.
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
//   * http_cpp_abi_call_generator_tool
//
// If the sets diverge, the same source routine would be routed to
// different API names on the service side and on the call side, and
// every cross-language call would fail at runtime.
//
// Replaced character set:
//   space, tab, '.', '/', '\', '@', ':', '#', '?', '&', '=', '+', '-'
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeInternalCallName(const ApiName: TP_String): TP_String;
begin
  Result := 'internal_call_' + ApiName;
end;

function MakeCallbackName(const ApiName: TP_String): TP_String;
begin
  Result := 'Callback_' + ApiName;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  // C++ reserved words. Only the ones that would produce a compile
  // error if used as an identifier are listed here. Shadowing a
  // library name (e.g. 'std') is legal, so those are not renamed.
  if Result.Same('alignas') or Result.Same('alignof') or Result.Same('and') or Result.Same('and_eq') or Result.Same('asm') or
    Result.Same('auto') or Result.Same('bitand') or Result.Same('bitor') or Result.Same('bool') or Result.Same('break') or Result.Same('case') or
    Result.Same('catch') or Result.Same('char') or Result.Same('char16_t') or Result.Same('char32_t') or Result.Same('class') or
    Result.Same('compl') or Result.Same('concept') or Result.Same('const') or Result.Same('constexpr') or Result.Same('const_cast') or
    Result.Same('continue') or Result.Same('co_await') or Result.Same('co_return') or Result.Same('co_yield') or Result.Same('decltype') or
    Result.Same('default') or Result.Same('delete') or Result.Same('do') or Result.Same('double') or Result.Same('dynamic_cast') or
    Result.Same('else') or Result.Same('enum') or Result.Same('explicit') or Result.Same('export') or Result.Same('extern') or
    Result.Same('false') or Result.Same('float') or Result.Same('for') or Result.Same('friend') or Result.Same('goto') or Result.Same('if') or
    Result.Same('inline') or Result.Same('int') or Result.Same('long') or Result.Same('mutable') or Result.Same('namespace') or
    Result.Same('new') or Result.Same('noexcept') or Result.Same('not') or Result.Same('not_eq') or Result.Same('nullptr') or
    Result.Same('operator') or Result.Same('or') or Result.Same('or_eq') or Result.Same('private') or Result.Same('protected') or
    Result.Same('public') or Result.Same('register') or Result.Same('reinterpret_cast') or Result.Same('requires') or Result.Same('return') or
    Result.Same('short') or Result.Same('signed') or Result.Same('sizeof') or Result.Same('static') or Result.Same('static_assert') or
    Result.Same('static_cast') or Result.Same('struct') or Result.Same('switch') or Result.Same('template') or Result.Same('this') or
    Result.Same('thread_local') or Result.Same('throw') or Result.Same('true') or Result.Same('try') or Result.Same('typedef') or
    Result.Same('typeid') or Result.Same('typename') or Result.Same('union') or Result.Same('unsigned') or Result.Same('using') or
    Result.Same('virtual') or Result.Same('void') or Result.Same('volatile') or Result.Same('wchar_t') or Result.Same('while') or
    Result.Same('xor') or Result.Same('xor_eq') then
    Result := Result + '_';
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

// BuildPascalDecl - Pascal declaration used by the README only.
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

// BuildCppSignature - C++ declaration used by the README only.
function BuildCppSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
begin
  if F.IsFunction then
    Result := ABI_Type_To_Cpp_Decl(F.ReturnType) + ' ' + ApiName +
      '(' + BuildCppParamList(F.Params) + ')'
  else
    Result := 'void ' + ApiName + '(' + BuildCppParamList(F.Params) + ')';
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
// C++ HEADER GENERATOR
// =============================================================================

function GenerateHTTPServiceCppHeader(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, Endpoint, GuardMacro: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  ParamList, RetType: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCppHeader: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCppHeader: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Ns := NormalizedUnit.LowerText;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  GuardMacro := NormalizedUnit.UpperText + '_HTTP_JSON_SERVICE_HPP';

  SupportedFuncs := CollectSupportedFunctions(Model);

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

    Lines.Add('// Auto-generated by http_cpp_abi_service_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (HTTP/JSON path, both directions):');
    Lines.Add('//   request  = JSON object');
    Lines.Add('//              { "args": [v1, v2, ...] }     positional arguments');
    Lines.Add('//              { "a": v1, "b": v2, ... }     named arguments');
    Lines.Add('//   response = JSON object');
    Lines.Add('//              { "code": 0,  "result": ... }  on success');
    Lines.Add('//              { "code": -1, "error":  ... }  on failure');
    Lines.Add('');
    Lines.Add('#ifndef ' + GuardMacro);
    Lines.Add('#define ' + GuardMacro);
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// LF_CDECL fallback');
    Lines.Add('//');
    Lines.Add('// The generated callbacks must use the C calling convention. Some');
    Lines.Add('// distributions of LingoFuse.hpp define LF_CDECL; others do not.');
    Lines.Add('// To keep the generated file self-contained, define it here only');
    Lines.Add('// when the LingoFuse header has not already done so.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#ifndef LF_CDECL');
    Lines.Add('#  if defined(_WIN32) || defined(_WIN64) || defined(__CYGWIN__)');
    Lines.Add('#    define LF_CDECL __cdecl');
    Lines.Add('#  else');
    Lines.Add('#    define LF_CDECL');
    Lines.Add('#  endif');
    Lines.Add('#endif');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Configuration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('extern const char* HTTP_SERVICE_APP_NAME;');
    Lines.Add('extern const char* HTTP_SERVICE_APP_DESC;');
    Lines.Add('extern const char* HTTP_SERVICE_ENDPOINT;');
    Lines.Add('extern bool DEBUG_LOG;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// API stubs');
    Lines.Add('//');
    Lines.Add('// Each stub mirrors one original Pascal routine. Fill in the body');
    Lines.Add('// in the paired .cpp file with a call to the real implementation.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ParamList := BuildCppParamList(F.Params);

      if F.IsFunction then
      begin
        RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
        Lines.Add(RetType.Text + ' ' + MakeInternalCallName(ApiName).Text +
          '(' + ParamList.Text + ');');
      end
      else
        Lines.Add('void ' + MakeInternalCallName(ApiName).Text +
          '(' + ParamList.Text + ');');
    end;

    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Registration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// Register every generated Call API on the given LingoFuse App.');
    Lines.Add('//');
    Lines.Add('// NOTE ON LIFETIME: the caller owns the App. The generated');
    Lines.Add('// run_service() constructs the App on the stack, registers every');
    Lines.Add('// API, and lets the App go out of scope on shutdown. Do NOT');
    Lines.Add('// return an App by value from a helper: its move semantics are not');
    Lines.Add('// guaranteed by all distributions of LingoFuse.hpp.');
    Lines.Add('void register_all_http_json_apis(lingofuse::App& app);');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Entry point');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// Start the service, install signal handlers, and block until a');
    Lines.Add('// termination signal is received. Returns 0 on success, 1 on any');
    Lines.Add('// fatal startup error.');
    Lines.Add('int run_service();');
    Lines.Add('');
    Lines.Add('}  // namespace ' + Ns);
    Lines.Add('');
    Lines.Add('#endif  // ' + GuardMacro);

    Result := Lines;
    Log(PFormat('Generated C++ header: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// C++ IMPLEMENTATION GENERATOR
// =============================================================================

function GenerateHTTPServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, Endpoint, HeaderFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, CallbackName, StubName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  ParamList, RetType: TP_String;
  Description: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Ns := NormalizedUnit.LowerText;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  HeaderFileName := NormalizedUnit + '_http_json_service.hpp';

  SupportedFuncs := CollectSupportedFunctions(Model);

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

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_cpp_abi_service_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('');
    Lines.Add('#include "' + HeaderFileName.Text + '"');
    Lines.Add('');
    Lines.Add('#include <atomic>');
    Lines.Add('#include <chrono>');
    Lines.Add('#include <csignal>');
    Lines.Add('#include <cstdlib>');
    Lines.Add('#include <iostream>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('#include <thread>');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Configuration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('const char* HTTP_SERVICE_APP_NAME = ' + CppStrLit(AppName).Text + ';');
    Lines.Add('const char* HTTP_SERVICE_APP_DESC = ' + CppStrLit('HTTP/JSON service for ' + UnitName).Text + ';');
    Lines.Add('const char* HTTP_SERVICE_ENDPOINT = ' + CppStrLit(Endpoint).Text + ';');
    Lines.Add('bool DEBUG_LOG = false;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Internal helpers');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('// Read and parse the JSON request from the input handle.');
    Lines.Add('static nlohmann::json _json_request(lingofuse::DataHandle& in) {');
    Lines.Add('    nlohmann::json req = lingofuse::io::read_json(in.get());');
    Lines.Add('    if (!req.is_object()) {');
    Lines.Add('        throw std::runtime_error("Request must be a JSON object");');
    Lines.Add('    }');
    Lines.Add('    return req;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// Write a success response to the output handle.');
    Lines.Add('static void _json_success(lingofuse::DataHandle& out,');
    Lines.Add('                          const nlohmann::json& result) {');
    Lines.Add('    nlohmann::json resp = {');
    Lines.Add('        {"code", 0},');
    Lines.Add('        {"result", result},');
    Lines.Add('    };');
    Lines.Add('    lingofuse::io::write_json(out.get(), resp);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// Write an error response to the output handle.');
    Lines.Add('static void _json_error(lingofuse::DataHandle& out,');
    Lines.Add('                        const std::string& message) {');
    Lines.Add('    nlohmann::json resp = {');
    Lines.Add('        {"code", -1},');
    Lines.Add('        {"error", message},');
    Lines.Add('    };');
    Lines.Add('    lingofuse::io::write_json(out.get(), resp);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// Extract a single argument by index (positional form) or by');
    Lines.Add('// name (named form).');
    Lines.Add('//');
    Lines.Add('// Behaviour:');
    Lines.Add('//   * Field is absent or JSON null   -> returns the type default.');
    Lines.Add('//   * Field is present with wrong    -> the nlohmann get<T>()');
    Lines.Add('//     value type                        throws; the exception is');
    Lines.Add('//                                        caught by the callback');
    Lines.Add('//                                        wrapper and converted into');
    Lines.Add('//                                        a { "code": -1, ... }');
    Lines.Add('//                                        response.');
    Lines.Add('//');
    Lines.Add('// This deliberately does NOT silently fall back to the default on');
    Lines.Add('// a type mismatch. A caller who sends "3" for a numeric parameter');
    Lines.Add('// receives an explicit error instead of a silently wrong result.');
    Lines.Add('template <typename T>');
    Lines.Add('static T _json_get_arg(const nlohmann::json& req,');
    Lines.Add('                       const char* name,');
    Lines.Add('                       std::size_t index) {');
    Lines.Add('    if (req.contains("args") && req["args"].is_array()) {');
    Lines.Add('        const auto& arr = req["args"];');
    Lines.Add('        if (index < arr.size() && !arr[index].is_null()) {');
    Lines.Add('            return arr[index].get<T>();');
    Lines.Add('        }');
    Lines.Add('    } else if (req.contains(name) && !req[name].is_null()) {');
    Lines.Add('        return req[name].get<T>();');
    Lines.Add('    }');
    Lines.Add('    return T{};');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // anonymous namespace');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// API stubs');
    Lines.Add('//');
    Lines.Add('// Each stub mirrors one original Pascal routine. Replace the body');
    Lines.Add('// with a call to the real implementation, for example:');
    Lines.Add('//     return MyNamespace::Add(a, b);');
    Lines.Add('// The parameter names and types are already correct.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    // Stub definitions
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      StubName := MakeInternalCallName(ApiName);
      ParamList := BuildCppParamList(F.Params);
      CallArgs := BuildCppCallArgList(F.Params);
      Description := GetFullDescription(F.Comment);

      if F.IsFunction then
      begin
        RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
        Lines.Add('// ' + Description.Text);
        Lines.Add(RetType.Text + ' ' + StubName.Text + '(' + ParamList.Text + ') {');
        Lines.Add('    // TODO: implement this stub.');
        if Length(F.Params) > 0 then
          Lines.Add('    // Suggested call: ' + F.Name.Text + '(' + CallArgs.Text + ');')
        else
          Lines.Add('    // Suggested call: ' + F.Name.Text + '();');
        Lines.Add('    return ' + ABI_Type_To_Cpp_Default(F.ReturnType) + ';');
        Lines.Add('}');
      end
      else
      begin
        Lines.Add('// ' + Description.Text);
        Lines.Add('void ' + StubName.Text + '(' + ParamList.Text + ') {');
        Lines.Add('    // TODO: implement this stub.');
        if Length(F.Params) > 0 then
          Lines.Add('    // Suggested call: ' + F.Name.Text + '(' + CallArgs.Text + ');')
        else
          Lines.Add('    // Suggested call: ' + F.Name.Text + '();');
        Lines.Add('    (void)0;  // silence unused-parameter warnings');
        Lines.Add('}');
      end;
      Lines.Add('');
    end;

    // cdecl callbacks
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// cdecl callbacks');
    Lines.Add('//');
    Lines.Add('// Each callback wraps one stub, reads the JSON request, writes the');
    Lines.Add('// JSON response, and isolates every exception. The callbacks are');
    Lines.Add('// registered by register_all_http_json_apis below.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      CallbackName := MakeCallbackName(ApiName);
      StubName := MakeInternalCallName(ApiName);

      Lines.Add('static void LF_CDECL ' + CallbackName.Text +
        '(void* trigger, void* in_raw, void* out_raw) {');
      Lines.Add('    (void)trigger;');
      Lines.Add('    lingofuse::DataHandle in(static_cast<TDataHnd>(in_raw), false);');
      Lines.Add('    lingofuse::DataHandle out(static_cast<TDataHnd>(out_raw), false);');
      Lines.Add('    try {');
      Lines.Add('        nlohmann::json req = _json_request(in);');
      Lines.Add('');

      if Length(F.Params) > 0 then
      begin
        for j := 0 to High(F.Params) do
        begin
          ParamList := MakeSafeCppIdent(F.Params[j].Name, j);
          RetType := ABI_Type_To_Cpp_Decl(F.Params[j].PascalType);
          Lines.Add('        ' + RetType.Text + ' ' + ParamList.Text +
            ' = _json_get_arg<' + RetType.Text + '>(');
          Lines.Add('            req, ' + CppStrLit(F.Params[j].Name).Text + ', ' +
            umlIntToStr(j).Text + ');');
        end;
        Lines.Add('');
      end;

      if F.IsFunction then
      begin
        RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
        Lines.Add('        ' + RetType.Text + ' result = ' + StubName.Text +
          '(' + BuildCppCallArgList(F.Params).Text + ');');
        Lines.Add('        _json_success(out, result);');
      end
      else
      begin
        Lines.Add('        ' + StubName.Text + '(' +
          BuildCppCallArgList(F.Params).Text + ');');
        Lines.Add('        _json_success(out, nullptr);');
      end;

      Lines.Add('    } catch (const std::exception& e) {');
      Lines.Add('        _json_error(out, e.what());');
      Lines.Add('    } catch (...) {');
      Lines.Add('        _json_error(out, "Unknown exception in callback");');
      Lines.Add('    }');
      Lines.Add('}');
      Lines.Add('');
    end;

    // Registration
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Registration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('void register_all_http_json_apis(lingofuse::App& app) {');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      CallbackName := MakeCallbackName(ApiName);
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON api for ' + F.Name;

      Lines.Add('    app.registerCall(' + CppStrLit(ApiName).Text + ', ' +
        CppStrLit(Description).Text + ', nullptr, ' + CallbackName.Text + ');');
    end;

    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Entry point');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('std::atomic<bool> g_stop_requested{false};');
    Lines.Add('');
    Lines.Add('void _on_signal(int signum) {');
    Lines.Add('    std::cerr << "Signal " << signum << " received, shutting down..." << std::endl;');
    Lines.Add('    g_stop_requested.store(true);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // anonymous namespace');
    Lines.Add('');
    Lines.Add('int run_service() {');
    Lines.Add('    std::cout << "=== " << HTTP_SERVICE_APP_NAME');
    Lines.Add('              << " HTTP/JSON service ===" << std::endl;');
    Lines.Add('    std::cout << "Endpoint: " << HTTP_SERVICE_ENDPOINT << std::endl;');
    Lines.Add('');
    Lines.Add('    // Deployment mode: do not block waiting for peers that are');
    Lines.Add('    // not yet ready. This lets bridge.py and this service start');
    Lines.Add('    // in any order.');
    Lines.Add('    lingofuse::setOption("Wait_Connection_ReadyOk", "False");');
    Lines.Add('');
    Lines.Add('    lingofuse::resetPrepare();');
    Lines.Add('');
    Lines.Add('    if (lingofuse::prepareService(HTTP_SERVICE_ENDPOINT,');
    Lines.Add('                                 HTTP_SERVICE_ENDPOINT) == -1) {');
    Lines.Add('        std::cerr << "LF_PrepareService failed for endpoint "');
    Lines.Add('                  << HTTP_SERVICE_ENDPOINT << std::endl;');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Construct the App in place. Do not factor this into a');
    Lines.Add('    // helper that returns App by value: move semantics are not');
    Lines.Add('    // guaranteed across all distributions of LingoFuse.hpp.');
    Lines.Add('    lingofuse::App app(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
    Lines.Add('    if (!app) {');
    Lines.Add('        std::cerr << "Failed to create the LingoFuse App." << std::endl;');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    register_all_http_json_apis(app);');
    Lines.Add('');
    Lines.Add('    if (lingofuse::prepareClient(HTTP_SERVICE_ENDPOINT, app.get()) == -1) {');
    Lines.Add('        std::cerr << "LF_PrepareClient failed for endpoint "');
    Lines.Add('                  << HTTP_SERVICE_ENDPOINT << std::endl;');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (lingofuse::prepareDone() != 1) {');
    Lines.Add('        std::cerr << "LF_PrepareDone failed." << std::endl;');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std::cout << "[OK] Service ready. Press Ctrl+C to stop." << std::endl;');
    Lines.Add('');
    Lines.Add('    std::signal(SIGINT, _on_signal);');
    Lines.Add('#ifdef SIGTERM');
    Lines.Add('    std::signal(SIGTERM, _on_signal);');
    Lines.Add('#endif');
    Lines.Add('');
    Lines.Add('    while (!g_stop_requested.load()) {');
    Lines.Add('        std::this_thread::sleep_for(std::chrono::milliseconds(500));');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Clean shutdown.');
    Lines.Add('    lingofuse::exitMainThread();');
    Lines.Add('    // `app` is destroyed when it goes out of scope.');
    Lines.Add('    lingofuse::shutdown();');
    Lines.Add('');
    Lines.Add('    std::cout << "Service stopped." << std::endl;');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // namespace ' + Ns);
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    return ' + Ns.Text + '::run_service();');
    Lines.Add('}');

    Result := Lines;
    Log(PFormat('Generated C++ implementation: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// README GENERATOR
// =============================================================================

function GenerateHTTPServiceCppReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Ns, AppName, Endpoint, HeaderFileName, CodeFileName: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamWire: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  PascalDecl, CppSig: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCppReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCppReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Ns := NormalizedUnit.LowerText;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  HeaderFileName := NormalizedUnit + '_http_json_service.hpp';
  CodeFileName := NormalizedUnit + '_http_json_service.cpp';

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

    // =========================================================================
    // Header block
    // =========================================================================
    Lines.Add('# ' + UnitName.Text + ' - C++ HTTP/JSON Service Provider');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_cpp_abi_service_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Header file**       : `' + HeaderFileName.Text + '`');
    Lines.Add('> **Implementation**    : `' + CodeFileName.Text + '`');
    Lines.Add('> **Namespace**         : `' + Ns.Text + '`');
    Lines.Add('> **Default App name**  : `' + AppName.Text + '`');
    Lines.Add('> **Default endpoint**  : `' + Endpoint.Text + '`');
    Lines.Add('> **Exposed APIs**      : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('>');
    Lines.Add('> **Audience**: C++ developers and AI assistants who need to fill');
    Lines.Add('> in the generated stubs, compile the service, and expose it to');
    Lines.Add('> HTTP clients through `bridge.py`.');
    Lines.Add('>');
    Lines.Add('> **AI agents**: jump straight to §14 "For AI Agents" for a');
    Lines.Add('> compact, machine-readable summary of the contract, common');
    Lines.Add('> anti-patterns, and a decision tree.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // =========================================================================
    // 1. Overview
    // =========================================================================
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **HTTP/JSON service** that was');
    Lines.Add('generated from the Pascal unit `' + UnitName.Text + '`. The');
    Lines.Add('service is a C++ program that registers one or more functions as');
    Lines.Add('LingoFuse Call APIs, and is reached from HTTP clients through the');
    Lines.Add('LingoFuse HTTP bridge (`bridge.py`).');
    Lines.Add('');
    Lines.Add('### 1.1 What is an HTTP/JSON C++ service?');
    Lines.Add('');
    Lines.Add('An HTTP/JSON C++ service is:');
    Lines.Add('');
    Lines.Add('- a C++ program that links against the LingoFuse C wrapper;');
    Lines.Add('- a set of stub functions registered as LingoFuse Call APIs;');
    Lines.Add('- a JSON RPC endpoint that speaks the same wire protocol as the');
    Lines.Add('  Pascal, Python, and JavaScript services generated from the same');
    Lines.Add('  source unit;');
    Lines.Add('- reachable by any HTTP client (browser, `curl`, `requests`,');
    Lines.Add('  Node.js, PHP, another C++ program) through `bridge.py`.');
    Lines.Add('');
    Lines.Add('### 1.2 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + HeaderFileName.Text + '` | The service header (declarations, config). |');
    Lines.Add('| `' + CodeFileName.Text + '` | The service implementation (stubs, callbacks, `main`). |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_service_cpp.md` | This README. |');
    Lines.Add('');

    // =========================================================================
    // 2. Quick Start
    // =========================================================================
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Fill in the stubs');
    Lines.Add('');
    Lines.Add('Open `' + CodeFileName.Text + '` and locate a stub:');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('std::int64_t internal_call_Add(std::int64_t a, std::int64_t b) {');
    Lines.Add('    // TODO: implement this stub.');
    Lines.Add('    // Suggested call: Add(a, b);');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Replace the `// TODO` line and the `return 0;` line with the');
    Lines.Add('actual call.');
    Lines.Add('');
    Lines.Add('### 2.2 Add the LingoFuse support library');
    Lines.Add('');
    Lines.Add('You need exactly three third-party pieces:');
    Lines.Add('');
    Lines.Add('| Piece | File(s) | Purpose |');
    Lines.Add('|-------|---------|---------|');
    Lines.Add('| LingoFuse C wrapper | `LingoFuse.h` + `LingoFuse.c` | The C ABI used by the runtime |');
    Lines.Add('| LingoFuse C++ wrapper | `LingoFuse.hpp` + `lf_io.hpp` | The RAII helpers this code uses |');
    Lines.Add('| nlohmann/json | `json.hpp` | The JSON engine this code uses |');
    Lines.Add('');
    Lines.Add('You have two ways to bring them in:');
    Lines.Add('');
    Lines.Add('- **Manual**: drop the five files above next to the two generated');
    Lines.Add('  files, and add `LingoFuse.c` to the same build target. No');
    Lines.Add('  further configuration is required.');
    Lines.Add('- **CMake**: use the script in §13.');
    Lines.Add('');

    // =========================================================================
    // 3. Compatibility
    // =========================================================================
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('### 3.1 Compiler support');
    Lines.Add('');
    Lines.Add('| Compiler | Minimum version | Notes |');
    Lines.Add('|----------|-----------------|-------|');
    Lines.Add('| GCC | 7 | Tested on 7 through 13. |');
    Lines.Add('| Clang | 6 | Tested on 6 through 17. |');
    Lines.Add('| MSVC | 2019 (19.20) | Tested on 2019 and 2022. |');
    Lines.Add('');
    Lines.Add('The generated code uses C++17 features. Designated initializers');
    Lines.Add('are NOT used.');
    Lines.Add('');
    Lines.Add('### 3.2 Platform support');
    Lines.Add('');
    Lines.Add('| Platform | Architecture | Status |');
    Lines.Add('|----------|-------------|--------|');
    Lines.Add('| Windows | x86_64 | Primary target |');
    Lines.Add('| Linux | x86_64 | Supported |');
    Lines.Add('| Linux | aarch64 | Supported |');
    Lines.Add('| macOS | x86_64 | Supported |');
    Lines.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    Lines.Add('');
    Lines.Add('### 3.3 Runtime dependencies');
    Lines.Add('');
    Lines.Add('| Dependency | Where to get it |');
    Lines.Add('|------------|----------------|');
    Lines.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    Lines.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | LingoFuse runtime distribution |');
    Lines.Add('| `bridge.py` | LingoFuse Python package |');
    Lines.Add('| Python 3.7+ and Flask | `bridge.py` runtime |');
    Lines.Add('');
    Lines.Add('### 3.4 Threading model');
    Lines.Add('');
    Lines.Add('Callbacks execute on LingoFuse worker threads. The main thread');
    Lines.Add('blocks in a sleep loop and does not execute user code.');
    Lines.Add('');

    // =========================================================================
    // 4. Wire Protocol
    // =========================================================================
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The C++ service uses **plain-text JSON** on both directions.');
    Lines.Add('');
    Lines.Add('### 4.1 Request');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "args": [v1, v2, ..., vN] }');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Named arguments are also accepted:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "a": v1, "b": v2 }');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('If `args` is present, named lookup is skipped. Missing fields');
    Lines.Add('fall back to the type default (`0` / `0.0` / `""`). **A field');
    Lines.Add('present with a mismatched type raises an error** rather than');
    Lines.Add('silently substituting the default.');
    Lines.Add('');
    Lines.Add('### 4.2 Response');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": 0,  "result": <value> }     on success');
    Lines.Add('{ "code": -1, "error":  "<message>" } on failure');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.3 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant H as HTTP Client');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant C as C++ Service');
    Lines.Add('    H->>B: POST /<app>/<api>');
    Lines.Add('    Note over H,B: Body: {"args": [a, b]}');
    Lines.Add('    B->>C: LF_Call with JSON payload');
    Lines.Add('    C->>C: _json_request, _json_get_arg');
    Lines.Add('    C->>C: call internal_call_<api>');
    Lines.Add('    C->>C: _json_success or _json_error');
    Lines.Add('    C-->>B: JSON response');
    Lines.Add('    B-->>H: HTTP 200 with JSON body');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 5. Type Mapping
    // =========================================================================
    Lines.Add('## 5. Type Mapping');
    Lines.Add('');
    Lines.Add('### 5.1 The key fact');
    Lines.Add('');
    Lines.Add('JSON has fewer types than the binary ABI. Every integer family');
    Lines.Add('member collapses to `std::int64_t`; every float family member');
    Lines.Add('collapses to `double`; every string family member collapses to');
    Lines.Add('`std::string`.');
    Lines.Add('');
    Lines.Add('### 5.2 Supported Pascal types and their C++ mapping');
    Lines.Add('');
    Lines.Add('| ABI type | Pascal type | C++ type | JSON wire type |');
    Lines.Add('|----------|-------------|----------|----------------|');
    Lines.Add('| `integer` | `Integer` | `std::int64_t` | `number` |');
    Lines.Add('| `longint` | `LongInt` | `std::int64_t` | `number` |');
    Lines.Add('| `int64` | `Int64` | `std::int64_t` | `number` |');
    Lines.Add('| `cardinal` | `Cardinal` | `std::int64_t` | `number` |');
    Lines.Add('| `dword` | `DWord` | `std::int64_t` | `number` |');
    Lines.Add('| `longword` | `LongWord` | `std::int64_t` | `number` |');
    Lines.Add('| `word` | `Word` | `std::int64_t` | `number` |');
    Lines.Add('| `smallint` | `SmallInt` | `std::int64_t` | `number` |');
    Lines.Add('| `byte` | `Byte` | `std::int64_t` | `number` |');
    Lines.Add('| `uint64` | `UInt64` | `std::int64_t` | `number` |');
    Lines.Add('| `double` | `Double` | `double` | `number` |');
    Lines.Add('| `single` | `Single` | `double` | `number` |');
    Lines.Add('| `extended` | `Extended` | `double` | `number` |');
    Lines.Add('| `real` | `Real` | `double` | `number` |');
    Lines.Add('| `string` | `string` | `std::string` | `string` |');
    Lines.Add('| `ansistring` | `string` | `std::string` | `string` |');
    Lines.Add('| `unicodestring` | `string` | `std::string` | `string` |');
    Lines.Add('| `tpascalstring` | `string` | `std::string` | `string` |');
    Lines.Add('| `tupascalstring` | `string` | `std::string` | `string` |');
    Lines.Add('| `tp_string` | `string` | `std::string` | `string` |');
    Lines.Add('| `pchar` | `string` | `std::string` | `string` |');
    Lines.Add('| `pansichar` | `string` | `std::string` | `string` |');
    Lines.Add('| `pwidechar` | `string` | `std::string` | `string` |');
    Lines.Add('');
    Lines.Add('### 5.3 Unsupported types');
    Lines.Add('');
    Lines.Add('Anything not in §5.2 causes the **entire routine** to be');
    Lines.Add('silently dropped during generation. Common examples:');
    Lines.Add('');
    Lines.Add('- `Boolean`, `WordBool`, `LongBool`');
    Lines.Add('- `Variant`, `OleVariant`');
    Lines.Add('- Arrays, records, classes, interfaces');
    Lines.Add('- Enumerations, sets, generics');
    Lines.Add('- Pointers, function pointers');
    Lines.Add('- `Currency`, `Comp`, `TDateTime`');
    Lines.Add('');

    // =========================================================================
    // 6. Deployment - Directory Layout
    // =========================================================================
    Lines.Add('## 6. Deployment');
    Lines.Add('');
    Lines.Add('### 6.1 Directory layout (manual mode)');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('my_http_json_cpp_service/');
    Lines.Add('  ' + HeaderFileName.Text + '      <- generated');
    Lines.Add('  ' + CodeFileName.Text + '        <- generated');
    Lines.Add('  LingoFuse.h                               <- from the C wrapper distribution');
    Lines.Add('  LingoFuse.c                               <- from the C wrapper distribution');
    Lines.Add('  LingoFuse.hpp                             <- from the C++ wrapper distribution');
    Lines.Add('  lf_io.hpp                                 <- from the C++ wrapper distribution');
    Lines.Add('  json.hpp                                  <- nlohmann/json single header');
    Lines.Add('  bridge.py                                 <- from the LingoFuse Python package');
    Lines.Add('  LingoFuse64.dll                           <- Windows runtime');
    Lines.Add('  liblingofuse.so                           <- Linux runtime');
    Lines.Add('  liblingofuse.dylib                        <- macOS runtime');
    Lines.Add('  z_ipc_64.dll                              <- Windows runtime');
    Lines.Add('  libz_ipc_64.so                            <- Linux runtime');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 7. Building - Manual
    // =========================================================================
    Lines.Add('## 7. Building - Manual (no build system)');
    Lines.Add('');
    Lines.Add('The generated service has exactly **one** third-party source file');
    Lines.Add('to compile: `LingoFuse.c`. Everything else is headers.');
    Lines.Add('');
    Lines.Add('### 7.1 Minimal build (GCC / Clang)');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('g++ -std=c++17 -O2 \\');
    Lines.Add('    -I. \\');
    Lines.Add('    ' + CodeFileName.Text + ' LingoFuse.c \\');
    Lines.Add('    -o ' + NormalizedUnit.Text + '_http_json_service \\');
    Lines.Add('    -pthread -ldl');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `-ldl` flag is required on Linux because `LingoFuse.c` uses');
    Lines.Add('`dlopen` / `dlsym`.');
    Lines.Add('');
    Lines.Add('### 7.2 Minimal build (MSVC)');
    Lines.Add('');
    Lines.Add('```cmd');
    Lines.Add('cl /std:c++17 /O2 /EHsc ^');
    Lines.Add('   /I. ^');
    Lines.Add('   ' + CodeFileName.Text + ' LingoFuse.c ^');
    Lines.Add('   /Fe:' + NormalizedUnit.Text + '_http_json_service.exe');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.3 Running the service');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('./' + NormalizedUnit.Text + '_http_json_service');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Expected output:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('=== ' + UnitName.Text + ' HTTP/JSON service ===');
    Lines.Add('Endpoint: ' + Endpoint.Text);
    Lines.Add('[OK] Service ready. Press Ctrl+C to stop.');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 8. Building - CMake
    // =========================================================================
    Lines.Add('## 8. Building - CMake');
    Lines.Add('');
    Lines.Add('If you already use CMake, drop this `CMakeLists.txt` next to the');
    Lines.Add('two generated files and the five support files:');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('project(' + NormalizedUnit.Text + '_http_json_service CXX)');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Adjust these two paths if your third-party files live elsewhere.');
    Lines.Add('# LINGOFUSE_DIR must contain: LingoFuse.h, LingoFuse.c,');
    Lines.Add('#                            LingoFuse.hpp, lf_io.hpp');
    Lines.Add('# NLOHMANN_DIR  must contain: json.hpp');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('set(LINGOFUSE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('set(NLOHMANN_DIR  "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('');
    Lines.Add('add_executable(${PROJECT_NAME}');
    Lines.Add('    ' + CodeFileName.Text);
    Lines.Add('    ' + HeaderFileName.Text);
    Lines.Add('    "${LINGOFUSE_DIR}/LingoFuse.c"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('target_include_directories(${PROJECT_NAME} PRIVATE');
    Lines.Add('    "${CMAKE_CURRENT_SOURCE_DIR}"');
    Lines.Add('    "${LINGOFUSE_DIR}"');
    Lines.Add('    "${NLOHMANN_DIR}"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('# Platform-specific link libraries.');
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
    Lines.Add('# Copy the Windows runtime DLLs next to the executable so the');
    Lines.Add('# program can find them without a manual PATH change.');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('if(WIN32)');
    Lines.Add('    set(_RUNTIME_DLLS');
    Lines.Add('        "${LINGOFUSE_DIR}/LingoFuse64.dll"');
    Lines.Add('        "${LINGOFUSE_DIR}/z_ipc_64.dll")');
    Lines.Add('    foreach(_dll ${_RUNTIME_DLLS})');
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
    Lines.Add('### 8.1 Build with CMake');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('cmake -S . -B build -DCMAKE_BUILD_TYPE=Release');
    Lines.Add('cmake --build build --config Release');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.2 Add the target to an existing CMake project');
    Lines.Add('');
    Lines.Add('If you already have a top-level `CMakeLists.txt`, you do not need');
    Lines.Add('to make a separate project. Add the following to your existing');
    Lines.Add('file:');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('add_executable(' + NormalizedUnit.Text + '_http_json_service');
    Lines.Add('    ${CMAKE_CURRENT_SOURCE_DIR}/' + CodeFileName.Text);
    Lines.Add('    ${LINGOFUSE_DIR}/LingoFuse.c');
    Lines.Add(')');
    Lines.Add('target_include_directories(' + NormalizedUnit.Text + '_http_json_service PRIVATE');
    Lines.Add('    ${CMAKE_CURRENT_SOURCE_DIR}');
    Lines.Add('    ${LINGOFUSE_DIR}');
    Lines.Add('    ${NLOHMANN_DIR}');
    Lines.Add(')');
    Lines.Add('target_link_libraries(' + NormalizedUnit.Text + '_http_json_service PRIVATE');
    Lines.Add('    Threads::Threads ${CMAKE_DL_LIBS}');
    Lines.Add(')');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 9. Starting the bridge
    // =========================================================================
    Lines.Add('## 9. Starting the bridge');
    Lines.Add('');
    Lines.Add('In a second terminal:');
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
    Lines.Add('### 9.1 Startup order');
    Lines.Add('');
    Lines.Add('Either order works, because the service uses deployment mode.');
    Lines.Add('');
    Lines.Add('### 9.2 Shutdown');
    Lines.Add('');
    Lines.Add('Press **Ctrl+C** in the service terminal. The sequence is:');
    Lines.Add('');
    Lines.Add('1. Signal handler sets the stop flag.');
    Lines.Add('2. The main loop wakes up and calls `lingofuse::exitMainThread()`.');
    Lines.Add('3. The App goes out of scope and its destructor frees it.');
    Lines.Add('4. `lingofuse::shutdown()` releases the LingoFuse library.');
    Lines.Add('5. `main()` returns 0.');
    Lines.Add('');

    // =========================================================================
    // 10. Testing
    // =========================================================================
    Lines.Add('## 10. Testing');
    Lines.Add('');
    Lines.Add('### 10.1 Issuing a request');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('curl -X POST http://127.0.0.1:8081/' + AppName.Text + '/<api> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": [1, 2]}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 10.2 Verifying the failure path');
    Lines.Add('');
    Lines.Add('Add `throw std::runtime_error("boom");` to a stub body, rebuild,');
    Lines.Add('and re-issue the request. The response should be:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": -1, "error": "boom" }');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 10.3 Verifying the type-mismatch path');
    Lines.Add('');
    Lines.Add('Send a numeric parameter as a string:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('curl -X POST http://127.0.0.1:8081/' + AppName.Text + '/<api> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": ["3", "4"]}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Expected: a `{ "code": -1, "error": "type must be number, but is string" }`');
    Lines.Add('response. This is by design: the generated `_json_get_arg` does');
    Lines.Add('not silently substitute a default on a type mismatch.');
    Lines.Add('');

    // =========================================================================
    // 11. Troubleshooting
    // =========================================================================
    Lines.Add('## 11. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| Linker error: undefined reference to `dlopen` | Missing `-ldl` on Linux | Add `-ldl` to the link line. |');
    Lines.Add('| Linker error: undefined reference to `LF_*` | `LingoFuse.c` not compiled in | Add `LingoFuse.c` to the compile command. |');
    Lines.Add('| `LF_LoadLibrary failed` at startup | The LingoFuse dynamic library is not on `PATH` / `LD_LIBRARY_PATH` | Copy the DLL next to the executable, or set the search path. |');
    Lines.Add('| `LF_PrepareService failed` | The endpoint is already in use | Use a different endpoint, or stop the conflicting process. |');
    Lines.Add('| `LF_PrepareDone failed` | The LingoFuse library could not initialise | Check the console output. |');
    Lines.Add('| HTTP 404 or connection refused | Bridge not running | Start `bridge.py`. |');
    Lines.Add('| `{"code": -3, "error": "API not available"}` | Bridge pre-check failed | Add `--no-precheck`, or wait ~3 s. |');
    Lines.Add('| `{"code": -1, "error": "type must be ..."}` | Caller sent the wrong JSON type | Fix the client''s JSON serialization. |');
    Lines.Add('| Callback never fires | The stub was not filled in and returns the default | Search for `TODO` in the generated .cpp file. |');
    Lines.Add('');

    // =========================================================================
    // 12. Reference Resources
    // =========================================================================
    Lines.Add('## 12. Reference Resources');
    Lines.Add('');
    Lines.Add('| Resource | Purpose |');
    Lines.Add('|----------|---------|');
    Lines.Add('| `LingoFuse.hpp` | C++ RAII wrapper for the LingoFuse dynamic library |');
    Lines.Add('| `LingoFuse.h` | C ABI declarations |');
    Lines.Add('| `lf_io.hpp` | Unified JSON/string I/O for LingoFuse handles |');
    Lines.Add('| `json.hpp` | nlohmann/json (single-header) |');
    Lines.Add('| `bridge.py` | HTTP <-> LingoFuse bridge |');
    Lines.Add('| `http_pas_abi_service_generator_tool.pas` | Pascal service generator (same wire protocol) |');
    Lines.Add('| `http_py_abi_service_generator_tool.pas` | Python service generator (same wire protocol) |');
    Lines.Add('');

    // =========================================================================
    // 13. Copy-Paste CMake Script (standalone, at-a-glance)
    // =========================================================================
    Lines.Add('## 13. Copy-Paste CMake Script');
    Lines.Add('');
    Lines.Add('This is the same script as §8, repeated here as the single');
    Lines.Add('authoritative copy for copy-paste use.');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('project(' + NormalizedUnit.Text + '_http_json_service CXX)');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('');
    Lines.Add('# Adjust these paths if your third-party files live elsewhere.');
    Lines.Add('set(LINGOFUSE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('set(NLOHMANN_DIR  "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('');
    Lines.Add('add_executable(${PROJECT_NAME}');
    Lines.Add('    ' + CodeFileName.Text);
    Lines.Add('    ${LINGOFUSE_DIR}/LingoFuse.c');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('target_include_directories(${PROJECT_NAME} PRIVATE');
    Lines.Add('    ${CMAKE_CURRENT_SOURCE_DIR}');
    Lines.Add('    ${LINGOFUSE_DIR}');
    Lines.Add('    ${NLOHMANN_DIR}');
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
    Lines.Add('Build:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('cmake -S . -B build -DCMAKE_BUILD_TYPE=Release');
    Lines.Add('cmake --build build --config Release');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 14. For AI Agents
    // =========================================================================
    Lines.Add('## 14. For AI Agents');
    Lines.Add('');
    Lines.Add('### 14.1 Contract summary');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('service:');
    Lines.Add('  app_name: ' + AppName.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  namespace: ' + Ns.Text);
    Lines.Add('  header_file: ' + HeaderFileName.Text);
    Lines.Add('  code_file: ' + CodeFileName.Text);
    Lines.Add('  lf_endpoint: ' + Endpoint.Text);
    Lines.Add('  bridge_default_http_port: 8081');
    Lines.Add('  cpp_standard: c++17');
    Lines.Add('');
    Lines.Add('third_party_files_required:');
    Lines.Add('  - LingoFuse.h');
    Lines.Add('  - LingoFuse.c        # the ONLY source file to compile in');
    Lines.Add('  - LingoFuse.hpp');
    Lines.Add('  - lf_io.hpp');
    Lines.Add('  - json.hpp           # nlohmann single header');
    Lines.Add('');
    Lines.Add('build_modes:');
    Lines.Add('  manual: "g++ -std=c++17 *.cpp LingoFuse.c -o service -pthread -ldl"');
    Lines.Add('  cmake: "see §13";');
    Lines.Add('');
    Lines.Add('outbound_response:');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('argument_resolution:');
    Lines.Add('  positional_first: args array');
    Lines.Add('  named_fallback: by name');
    Lines.Add('  missing_field: type default');
    Lines.Add('  type_mismatch: throws, becomes code=-1');
    Lines.Add('');
    Lines.Add('app_lifetime:');
    Lines.Add('  construct_in_place: true');
    Lines.Add('  return_by_value: not recommended');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 14.2 Anti-patterns');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Returning `lingofuse::App` by value from a helper | Move semantics are not guaranteed | Construct in place inside `run_service()` |');
    Lines.Add('| Omitting `LingoFuse.c` from the build | Undefined references | Add it to the same target |');
    Lines.Add('| Omitting `-ldl` on Linux | Undefined `dlopen` | Add `-ldl` to the link line |');
    Lines.Add('| Editing `_json_get_arg` to swallow type errors | Wrong results become silent | The generated code throws on mismatch; keep it that way |');
    Lines.Add('| Blocking inside a stub for a long time | Holds a LingoFuse worker thread | Offload to a background thread |');
    Lines.Add('| Using `int`/`float` in stubs | Silent truncation on the wire | Use `std::int64_t` / `double` |');
    Lines.Add('');
    Lines.Add('### 14.3 Decision tree: how to build');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    S["I have the generated .hpp and .cpp"] --> Q1{"Do you use CMake?"}');
    Lines.Add('    Q1 -- "yes" --> A1["Use the CMake script in §13"]');
    Lines.Add('    Q1 -- "no"  --> A2["Compile with g++/cl, see §7"]');
    Lines.Add('    A1 --> B["Fill in the stubs"]');
    Lines.Add('    A2 --> B');
    Lines.Add('    B --> C["Run the binary"]');
    Lines.Add('    C --> D["Start bridge.py with the same endpoint"]');
    Lines.Add('    D --> E["POST JSON to the bridge"]');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 14.4 What this document does NOT cover');
    Lines.Add('');
    Lines.Add('- The internal implementation of `bridge.py`.');
    Lines.Add('- The internal implementation of the LingoFuse C wrapper.');
    Lines.Add('- Other language bindings (Pascal, Python, JavaScript).');
    Lines.Add('- Binary ABI services. See the corresponding generator.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_cpp_abi_service_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated C++ service README: %d lines, %d routines.',
      [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
