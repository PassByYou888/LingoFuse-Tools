unit http_cpp_abi_service_generator_tool;

// http_cpp_abi_service_generator_tool - LingoFuse HTTP/JSON ABI Service
// Provider Generator for C++.
//
// Consumes a TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI) and
// produces three artifacts:
//
//   1. A C++ header (*.hpp) that declares the service namespace, its
//      configuration globals, the API stubs, and the entry point.
//
//   2. A C++ implementation (*.cpp) that defines the stubs (with TODO
//      markers), the cdecl callbacks, the registration function, and a
//      ready-to-run main().
//
//   3. A Markdown README for the caller.
//
// Revision notes (v3):
//
//   - run_service() now constructs a lingofuse::LibraryLoader as its
//     first statement. This is the fix for the runtime crash where
//     lingofuse::App threw lingofuse::Error from LF_CreateApp: without
//     a LibraryLoader the dynamic library was never loaded, every LF_*
//     entry point silently no-op'd, and LF_CreateApp returned NULL.
//
//   - The CMake scripts now declare "C CXX" as the project languages.
//     LingoFuse.c is a C source file and cannot be compiled when only
//     the CXX language is enabled; the previous CXX-only project
//     failed to link.
//
//   - The README's "Prepare LingoFuse" sample now uses the RAII
//     LibraryLoader wrapper instead of the raw C ABI, so that the
//     sample matches what the generated run_service() actually does.
//
//   - v2 changes retained: no self-defined LF_CDECL; App scoped so its
//     destructor runs before shutdown(); strict integer-vs-float check;
//     signal handler touches only atomics; registerCall return value
//     is checked; DEBUG_LOG is honored.
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

function GenerateHTTPServiceCppHeader(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPServiceCppReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
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
// HEADER GENERATOR
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
    Lines.Add('//');
    Lines.Add('// This header does NOT define LF_CDECL. That macro is provided by');
    Lines.Add('// LingoFuse.h (pulled in by LingoFuse.hpp). Redefining it here');
    Lines.Add('// would produce a macro redefinition warning on MinGW and');
    Lines.Add('// clang-cl, where LingoFuse.h uses __attribute__((cdecl)) instead');
    Lines.Add('// of __cdecl.');
    Lines.Add('');
    Lines.Add('#ifndef ' + GuardMacro);
    Lines.Add('#define ' + GuardMacro);
    Lines.Add('');
    Lines.Add('#include <cstddef>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Configuration');
    Lines.Add('//');
    Lines.Add('// Set HTTP_SERVICE_APP_NAME and HTTP_SERVICE_ENDPOINT before');
    Lines.Add('// calling run_service(). DEBUG_LOG enables per-call tracing on');
    Lines.Add('// stderr and should be left false in production.');
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
    Lines.Add('//');
    Lines.Add('// The caller owns the App object. The generated run_service()');
    Lines.Add('// constructs it in an inner scope so that its destructor runs');
    Lines.Add('// BEFORE lingofuse::shutdown(). This preserves the documented');
    Lines.Add('// cleanup order: exitMainThread -> FreeApp -> Shutdown.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('void register_all_http_json_apis(lingofuse::App& app);');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Entry point');
    Lines.Add('//');
    Lines.Add('// Loads the LingoFuse dynamic library, prepares the service,');
    Lines.Add('// installs signal handlers, and blocks until a termination signal');
    Lines.Add('// is received. Returns 0 on success, 1 on any fatal startup error.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
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
// IMPLEMENTATION GENERATOR
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
    // File header and includes
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
    Lines.Add('#include <cstddef>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstdlib>');
    Lines.Add('#include <iostream>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('#include <thread>');
    Lines.Add('#include <type_traits>');
    Lines.Add('');
    Lines.Add('namespace ' + Ns + ' {');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Configuration');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('const char* HTTP_SERVICE_APP_NAME = ' + CppStrLit(AppName).Text + ';');
    Lines.Add('const char* HTTP_SERVICE_APP_DESC = ' +
      CppStrLit('HTTP/JSON service for ' + UnitName).Text + ';');
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
    Lines.Add('//');
    Lines.Add('// The bridge emits NUL-terminated UTF-8 JSON. io::read_json strips');
    Lines.Add('// the NUL before parsing. Do NOT replace this with LF_ReadBuffer:');
    Lines.Add('// that would leave a trailing NUL inside the JSON text and break');
    Lines.Add('// parsing.');
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
    Lines.Add('// Contract:');
    Lines.Add('//   * Absent field or JSON null          -> returns T{}.');
    Lines.Add('//   * Integer parameter, JSON float sent -> throws.');
    Lines.Add('//   * Any other type mismatch            -> throws from get<T>().');
    Lines.Add('//');
    Lines.Add('// The integer-vs-float check exists because nlohmann::json will');
    Lines.Add('// happily truncate a float to an integer via get<std::int64_t>().');
    Lines.Add('// That silent truncation is precisely what this wrapper must not');
    Lines.Add('// allow across a public API boundary.');
    Lines.Add('template <typename T>');
    Lines.Add('static T _json_get_arg(const nlohmann::json& req,');
    Lines.Add('                       const char* name,');
    Lines.Add('                       std::size_t index) {');
    Lines.Add('    const nlohmann::json* slot = nullptr;');
    Lines.Add('    if (req.contains("args") && req["args"].is_array()) {');
    Lines.Add('        const auto& arr = req["args"];');
    Lines.Add('        if (index < arr.size() && !arr[index].is_null()) {');
    Lines.Add('            slot = &arr[index];');
    Lines.Add('        }');
    Lines.Add('    } else if (req.contains(name) && !req[name].is_null()) {');
    Lines.Add('        slot = &req[name];');
    Lines.Add('    }');
    Lines.Add('    if (slot == nullptr) {');
    Lines.Add('        return T{};');
    Lines.Add('    }');
    Lines.Add('    if (std::is_integral<T>::value && slot->is_number_float()) {');
    Lines.Add('        throw std::runtime_error(');
    Lines.Add('            std::string("Argument ''") + name +');
    Lines.Add('            "'' expects an integer, but received a floating-point number");');
    Lines.Add('    }');
    Lines.Add('    return slot->get<T>();');
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

    // Stub definitions.
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

    // cdecl callbacks.
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
      Lines.Add('        if (DEBUG_LOG) {');
      Lines.Add('            std::cerr << "Call ' + ApiName.Text + ': request = "');
      Lines.Add('                      << req.dump() << std::endl;');
      Lines.Add('        }');
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
        Lines.Add('        _json_success(out, nlohmann::json());');
      end;

      Lines.Add('    } catch (const std::exception& e) {');
      Lines.Add('        _json_error(out, e.what());');
      Lines.Add('    } catch (...) {');
      Lines.Add('        _json_error(out, "Unknown exception in callback");');
      Lines.Add('    }');
      Lines.Add('}');
      Lines.Add('');
    end;

    // Registration.
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

      Lines.Add('    if (!app.registerCall(' + CppStrLit(ApiName).Text + ', ' +
        CppStrLit(Description).Text + ', nullptr, ' + CallbackName.Text + ')) {');
      Lines.Add('        std::cerr << "Failed to register API \""');
      Lines.Add('                  << ' + CppStrLit(ApiName).Text + ' << "\"" << std::endl;');
      Lines.Add('    }');
    end;

    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Entry point');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('// Signal-safe state. Only these two atomics may be touched from');
    Lines.Add('// the signal handler. All user-visible output happens on the');
    Lines.Add('// main thread after the wait loop exits.');
    Lines.Add('std::atomic<bool> g_stop_requested{false};');
    Lines.Add('std::atomic<int>  g_last_signal{0};');
    Lines.Add('');
    Lines.Add('void _on_signal(int signum) {');
    Lines.Add('    g_last_signal.store(signum);');
    Lines.Add('    g_stop_requested.store(true);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('}  // anonymous namespace');
    Lines.Add('');
    Lines.Add('int run_service() {');
    Lines.Add('    // Load the LingoFuse dynamic library before anything else.');
    Lines.Add('    //');
    Lines.Add('    // LibraryLoader is RAII: it calls LF_LoadLibrary in its');
    Lines.Add('    // constructor and LF_FreeLibrary in its destructor, with a');
    Lines.Add('    // process-wide reference count so that multiple LibraryLoader');
    Lines.Add('    // instances share one load. It MUST be the first LingoFuse');
    Lines.Add('    // object constructed and the last destroyed, because every');
    Lines.Add('    // LF_* entry point is a silent no-op until the library has');
    Lines.Add('    // been successfully loaded. In particular, calling LF_CreateApp');
    Lines.Add('    // before LF_LoadLibrary returns NULL, which makes');
    Lines.Add('    // lingofuse::App throw lingofuse::Error.');
    Lines.Add('    lingofuse::LibraryLoader loader;');
    Lines.Add('');
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
    Lines.Add('                                 HTTP_SERVICE_ENDPOINT) < 0) {');
    Lines.Add('        std::cerr << "LF_PrepareService failed for endpoint "');
    Lines.Add('                  << HTTP_SERVICE_ENDPOINT << std::endl;');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // The App is scoped so that its destructor (which calls');
    Lines.Add('    // LF_FreeApp) runs BEFORE lingofuse::shutdown(). This');
    Lines.Add('    // preserves the documented cleanup order:');
    Lines.Add('    //     exitMainThread -> FreeApp -> Shutdown');
    Lines.Add('    {');
    Lines.Add('        lingofuse::App app(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
    Lines.Add('        if (!app) {');
    Lines.Add('            std::cerr << "Failed to create the LingoFuse App." << std::endl;');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        register_all_http_json_apis(app);');
    Lines.Add('');
    Lines.Add('        if (lingofuse::prepareClient(HTTP_SERVICE_ENDPOINT, app.get()) < 0) {');
    Lines.Add('            std::cerr << "LF_PrepareClient failed for endpoint "');
    Lines.Add('                      << HTTP_SERVICE_ENDPOINT << std::endl;');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        if (lingofuse::prepareDone() != 1) {');
    Lines.Add('            std::cerr << "LF_PrepareDone failed." << std::endl;');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        std::cout << "[OK] Service ready. Press Ctrl+C to stop."');
    Lines.Add('                  << std::endl;');
    Lines.Add('');
    Lines.Add('        std::signal(SIGINT, _on_signal);');
    Lines.Add('#ifdef SIGTERM');
    Lines.Add('        std::signal(SIGTERM, _on_signal);');
    Lines.Add('#endif');
    Lines.Add('');
    Lines.Add('        while (!g_stop_requested.load()) {');
    Lines.Add('            std::this_thread::sleep_for(std::chrono::milliseconds(500));');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        // Step 1: stop the simulated main loop first.');
    Lines.Add('        lingofuse::exitMainThread();');
    Lines.Add('    }');
    Lines.Add('    // Step 2: the App has now been freed.');
    Lines.Add('');
    Lines.Add('    // Step 3: release the rest of the framework.');
    Lines.Add('    lingofuse::shutdown();');
    Lines.Add('');
    Lines.Add('    {');
    Lines.Add('        const int sig = g_last_signal.load();');
    Lines.Add('        if (sig != 0) {');
    Lines.Add('            std::cerr << "Signal " << sig');
    Lines.Add('                      << " received, shutting down..." << std::endl;');
    Lines.Add('        }');
    Lines.Add('    }');
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
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **HTTP/JSON service** that was');
    Lines.Add('generated from the Pascal unit `' + UnitName.Text + '`. The');
    Lines.Add('service is a C++ program that registers one or more functions as');
    Lines.Add('LingoFuse Call APIs, and is reached from HTTP clients through the');
    Lines.Add('LingoFuse HTTP bridge (`bridge.py`).');
    Lines.Add('');
    Lines.Add('### 1.1 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + HeaderFileName.Text + '` | The service header (declarations, config). |');
    Lines.Add('| `' + CodeFileName.Text + '` | The service implementation (stubs, callbacks, `main`). |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_service_cpp.md` | This README. |');
    Lines.Add('');
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Prepare LingoFuse');
    Lines.Add('');
    Lines.Add('The generated `run_service()` already does this. If you write');
    Lines.Add('your own `main()` around the generated code, mirror this');
    Lines.Add('structure:');
    Lines.Add('');
    Lines.Add('```cpp');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    // The dynamic library MUST be loaded before any other');
    Lines.Add('    // LingoFuse call. LibraryLoader is RAII: it calls');
    Lines.Add('    // LF_LoadLibrary in its constructor and LF_FreeLibrary in');
    Lines.Add('    // its destructor, and it manages a process-wide reference');
    Lines.Add('    // count so multiple instances share one load.');
    Lines.Add('    lingofuse::LibraryLoader loader;');
    Lines.Add('');
    Lines.Add('    lingofuse::resetPrepare();');
    Lines.Add('    lingofuse::prepareClient("ipc:' + NormalizedUnit.Text + '_http_json", nullptr);');
    Lines.Add('    if (lingofuse::prepareDone() != 1) {');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('    // ... your work ...');
    Lines.Add('    lingofuse::exitMainThread();');
    Lines.Add('    lingofuse::shutdown();');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Without the `LibraryLoader`, every `LF_*` entry point is a');
    Lines.Add('silent no-op and `LF_CreateApp` returns `NULL`, which makes');
    Lines.Add('`lingofuse::App` throw `lingofuse::Error`.');
    Lines.Add('');
    Lines.Add('### 2.2 Fill in the stubs');
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
    Lines.Add('### 2.3 Add the LingoFuse support files');
    Lines.Add('');
    Lines.Add('You need exactly five third-party files:');
    Lines.Add('');
    Lines.Add('| Piece | File(s) | Purpose |');
    Lines.Add('|-------|---------|---------|');
    Lines.Add('| LingoFuse C ABI | `LingoFuse.h` + `LingoFuse.c` | Loads the dynamic library, forwarders |');
    Lines.Add('| LingoFuse C++ RAII | `LingoFuse.hpp` | `DataHandle`, `App`, `LibraryLoader` |');
    Lines.Add('| LingoFuse payload I/O | `lf_io.hpp` | UTF-8 JSON framing over a data handle |');
    Lines.Add('| JSON engine | `json.hpp` | nlohmann/json single-header |');
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
    Lines.Add('## 4. Wire Protocol');
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
    Lines.Add('fall back to the type default (`0` / `0.0` / `""`).');
    Lines.Add('');
    Lines.Add('**A field present with a mismatched type raises an error** rather');
    Lines.Add('than silently substituting the default. In particular, sending a');
    Lines.Add('JSON float for an integer parameter is rejected outright, because');
    Lines.Add('silent truncation (e.g. `3.7 -> 3`) across a public API boundary');
    Lines.Add('is almost never what the caller intended.');
    Lines.Add('');
    Lines.Add('### 4.2 Response');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": 0,  "result": <value> }     on success');
    Lines.Add('{ "code": -1, "error":  "<message>" } on failure');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 5. Type Mapping');
    Lines.Add('');
    Lines.Add('| ABI type | Pascal type | C++ type | JSON wire type |');
    Lines.Add('|----------|-------------|----------|----------------|');
    Lines.Add('| `integer` | `Integer` | `std::int64_t` | `number` |');
    Lines.Add('| `int64` | `Int64` | `std::int64_t` | `number` |');
    Lines.Add('| `cardinal` | `Cardinal` | `std::int64_t` | `number` |');
    Lines.Add('| `word` | `Word` | `std::int64_t` | `number` |');
    Lines.Add('| `byte` | `Byte` | `std::int64_t` | `number` |');
    Lines.Add('| `uint64` | `UInt64` | `std::int64_t` | `number` |');
    Lines.Add('| `double` | `Double` | `double` | `number` |');
    Lines.Add('| `single` | `Single` | `double` | `number` |');
    Lines.Add('| `string` | `string` | `std::string` | `string` |');
    Lines.Add('| `pchar` | `string` | `std::string` | `string` |');
    Lines.Add('');
    Lines.Add('Anything not in this table causes the **entire routine** to be');
    Lines.Add('silently dropped during generation.');
    Lines.Add('');
    Lines.Add('## 6. Building - Manual');
    Lines.Add('');
    Lines.Add('The generated service has exactly **one** third-party source file');
    Lines.Add('to compile: `LingoFuse.c`.');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('g++ -std=c++17 -O2 \\');
    Lines.Add('    -I. \\');
    Lines.Add('    ' + CodeFileName.Text + ' LingoFuse.c \\');
    Lines.Add('    -o ' + NormalizedUnit.Text + '_http_json_service \\');
    Lines.Add('    -pthread -ldl');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 7. Building - CMake');
    Lines.Add('');
    Lines.Add('Note the `C CXX` in the `project()` line: `LingoFuse.c` is a C');
    Lines.Add('source file and cannot be compiled when only the CXX language is');
    Lines.Add('enabled.');
    Lines.Add('');
    Lines.Add('```cmake');
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('project(' + NormalizedUnit.Text + '_http_json_service C CXX)');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('');
    Lines.Add('# Adjust these two paths if your support files live elsewhere.');
    Lines.Add('set(LINGOFUSE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('set(NLOHMANN_DIR  "${CMAKE_CURRENT_SOURCE_DIR}")');
    Lines.Add('');
    Lines.Add('add_executable(${PROJECT_NAME}');
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
    Lines.Add('## 8. Starting the bridge');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 bridge.py --endpoint ' + Endpoint.Text + ' \\');
    Lines.Add('    --port 8081 --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 9. Cleanup Order');
    Lines.Add('');
    Lines.Add('The generated `run_service()` performs cleanup in the documented');
    Lines.Add('order:');
    Lines.Add('');
    Lines.Add('1. `lingofuse::exitMainThread()` — stop the simulated main loop.');
    Lines.Add('2. `~App()` — the App object leaves scope, calling `LF_FreeApp`.');
    Lines.Add('3. `lingofuse::shutdown()` — release the rest of the framework.');
    Lines.Add('4. `~LibraryLoader()` — `LF_FreeLibrary` is called last, when');
    Lines.Add('   `run_service()` returns.');
    Lines.Add('');
    Lines.Add('## 10. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| `lingofuse::Error: App: LF_CreateApp failed` | `LF_LoadLibrary` was never called | Add `lingofuse::LibraryLoader loader;` as the first statement of `run_service()` (or your `main()`) |');
    Lines.Add('| Linker error: undefined reference to `dlopen` | Missing `-ldl` on Linux | Add `-ldl` to the link line |');
    Lines.Add('| Linker error: undefined reference to `LF_*` | `LingoFuse.c` not compiled in | Add it to the same target |');
    Lines.Add('| CMake: "Cannot determine link language" for LingoFuse.c | `project()` declares only `CXX` | Change to `project(name C CXX)` |');
    Lines.Add('| Macro redefinition warning about `LF_CDECL` | You redefined it in your own header | Do not define it; rely on `LingoFuse.h` |');
    Lines.Add('| HTTP 404 or connection refused | Bridge not running | Start `bridge.py` |');
    Lines.Add('| `{"code": -3}` | Bridge pre-check failed | Add `--no-precheck` |');
    Lines.Add('| `{"code": -1, "error": "Argument ''x'' expects an integer ..."}` | A float was sent for an integer parameter | Fix the caller''s JSON |');
    Lines.Add('| Callback never fires | The stub was not filled in | Search for `TODO` in the .cpp file |');
    Lines.Add('');
    Lines.Add('## 11. API Reference');
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
        Lines.Add('### 11.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('The generator appends `_N` to every overload after the first.');
        Lines.Add('');
      end;

      Lines.Add('### 11.1 Summary');
      Lines.Add('');
      Lines.Add('| # | Stub | HTTP route | Params | Returns | Description |');
      Lines.Add('|---|------|------------|--------|---------|-------------|');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];

        Description := GetFullDescription(F.Comment);
        if Description.Len = 0 then
          Description := '';

        if F.IsFunction then
          ParamWire := ABI_Type_To_Cpp_Decl(F.ReturnType)
        else
          ParamWire := '-';

        Lines.Add('| ' + MdInt(i + 1).Text +
          ' | `' + MdCellEscape(MakeInternalCallName(ApiName)).Text + '`' +
          ' | `POST /' + AppName.Text + '/' + MdCellEscape(ApiName).Text + '`' +
          ' | ' + MdInt(Length(F.Params)).Text +
          ' | `' + MdCellEscape(ParamWire).Text + '`' +
          ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        HasParams := Length(F.Params) > 0;

        PascalDecl := BuildPascalDecl(F);
        CppSig := BuildCppSignature(F, MakeInternalCallName(ApiName));
        CallArgs := BuildCppCallArgList(F.Params);

        Lines.Add('### 11.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');
        Lines.Add('- **Stub signature**: `' + CppSig.Text + '`');
        Lines.Add('- **Pascal source**: `' + PascalDecl.Text + '`');
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
          Lines.Add('| # | Name | C++ type | JSON wire type |');
          Lines.Add('|---|------|----------|----------------|');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafeCppIdent(F.Params[j].Name, j);
            ParamType := ABI_Type_To_Cpp_Decl(F.Params[j].PascalType);
            ParamWire := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);
            Lines.Add('| ' + MdInt(j + 1).Text +
              ' | `' + MdCellEscape(ParamName).Text + '`' +
              ' | `' + MdCellEscape(ParamType).Text + '`' +
              ' | `' + MdCellEscape(ParamWire).Text + '` |');
          end;
          Lines.Add('');
        end;

        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    Lines.Add('## 12. Reference Resources');
    Lines.Add('');
    Lines.Add('| Resource | Purpose |');
    Lines.Add('|----------|---------|');
    Lines.Add('| `LingoFuse.hpp` | C++ RAII wrapper for the LingoFuse dynamic library |');
    Lines.Add('| `LingoFuse.h` | C ABI declarations |');
    Lines.Add('| `lf_io.hpp` | Unified JSON/string I/O for LingoFuse handles |');
    Lines.Add('| `json.hpp` | nlohmann/json (single-header) |');
    Lines.Add('| `bridge.py` | HTTP <-> LingoFuse bridge |');
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
