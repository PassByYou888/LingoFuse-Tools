unit http_cmake_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status,
  Z.UnicodeMixedLib,
  Z.ListEngine, code_decl_to_json_abi_registry,
  Z.Pascal_Func_Model;

const
  // Enable verbose logging during generation. Declared in the
  // interface so the Log helpers below can use it.
  GenerateCode_LogEnabled: boolean = False;

// GenerateCMakeScript - main entry point for the CMakeLists.txt.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. Only
// Model.UnitName is consulted.
//
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateCMakeScript(Model: TPascal_Func_Model): TPascalStringList;

// GenerateTestMainCpp - main entry point for the test driver.
//
// Emits, for every supported routine, TWO test blocks:
//   * a [sync] block that calls the blocking wrapper function;
//   * an [async] block that calls the asynchronous wrapper, feeds its
//     result into a std::promise, and waits up to 30 s on the paired
//     std::future.
//
// A single failures counter covers both paths. main() returns 0 when
// every block succeeded, and 1 otherwise.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI.
//
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateTestMainCpp(Model: TPascal_Func_Model): TPascalStringList;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_cmake_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_cmake_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------
//
// These are deliberately identical to the ones in
// http_cpp_abi_call_generator_tool.pas. The test driver emitted by
// GenerateTestMainCpp must reference the same C++ identifiers that the
// call wrapper actually defines.

// NormalizeUnitName - mirror the normalization performed by every
// other generator in this toolchain.
function NormalizeUnitName(const UnitName: U_String): U_String;
begin
  Result := UnitName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

function MakeApiName(const FuncName: U_String): U_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafeCppIdent(const Name: U_String; Index: integer): U_String;
var
  i: integer;
  c: U_Char;
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

function UniqueName(const Base: U_String; Used: TPascalStringList): U_String;
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

// -----------------------------------------------------------------------------
// ABI type classification (mirrors the call generator)
// -----------------------------------------------------------------------------

function ABI_Type_Is_String(const T: U_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: U_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: U_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal') or
    T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: U_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function ABI_Type_To_Cpp_Decl(const T: U_String): U_String;
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

function ABI_Type_To_Cpp_Default_Arg(const T: U_String): U_String;
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

// -----------------------------------------------------------------------------
// Supported-function filtering (mirrors the call generator)
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

// -----------------------------------------------------------------------------
// CMake script
// -----------------------------------------------------------------------------

procedure EmitPrologue(Lines: TPascalStringList;
  const ProjectName, UnitName: U_String);
begin
  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('# ' + ProjectName.Text);
  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('#');
  Lines.Add('# Auto-generated by http_cmake_generator_tool.pas.');
  Lines.Add('# Do not edit by hand unless you know what you are doing.');
  Lines.Add('#');
  Lines.Add('# Purpose: build and test the C++ service and call artifacts that');
  Lines.Add('# were generated for the Pascal unit "' + UnitName.Text + '".');
  Lines.Add('#');
  Lines.Add('# Targets:');
  Lines.Add('#');
  Lines.Add('#   ' + UnitName.Text + '_http_json_service       (executable)');
  Lines.Add('#       The service produced by');
  Lines.Add('#       http_cpp_abi_service_generator_tool.pas. It contains its');
  Lines.Add('#       own main() entry point.');
  Lines.Add('#');
  Lines.Add('#   ' + UnitName.Text + '_http_json_call_test     (executable)');
  Lines.Add('#       The test driver linked against the call wrapper produced by');
  Lines.Add('#       http_cpp_abi_call_generator_tool.pas. It exercises both');
  Lines.Add('#       the synchronous and the asynchronous call path for every');
  Lines.Add('#       supported routine.');
  Lines.Add('#');
  Lines.Add('# Expected files, all in this directory:');
  Lines.Add('#');
  Lines.Add('#   CMakeLists.txt');
  Lines.Add('#   ' + UnitName.Text + '_http_json_service.hpp');
  Lines.Add('#   ' + UnitName.Text + '_http_json_service.cpp');
  Lines.Add('#   ' + UnitName.Text + '_http_json_call.hpp');
  Lines.Add('#   ' + UnitName.Text + '_http_json_call.cpp');
  Lines.Add('#   test_main___.cpp');
  Lines.Add('#');
  Lines.Add('# HOW TO CONFIGURE');
  Lines.Add('# ----------------');
  Lines.Add('#');
  Lines.Add('# Point LINGOFUSE_CPP_LIB_DIR at the LingoFuse C++ library');
  Lines.Add('# directory, which must contain:');
  Lines.Add('#');
  Lines.Add('#   LingoFuse.h, LingoFuse.c, LingoFuse.hpp, lf_io.hpp,');
  Lines.Add('#   lf_http_bridge_client.hpp, json.hpp');
  Lines.Add('#');
  Lines.Add('# In cmake-gui, fill in the field');
  Lines.Add('#     "LingoFuse C++ library directory".');
  Lines.Add('# From a shell, pass it explicitly:');
  Lines.Add('#     cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf');
  Lines.Add('#');
  Lines.Add('# HOW TO RUN');
  Lines.Add('# ----------');
  Lines.Add('#');
  Lines.Add('# After the build completes, start bridge.py (see the service');
  Lines.Add('# README), then launch the service executable, then launch the');
  Lines.Add('# test executable. The test driver prints one line per [sync] and');
  Lines.Add('# per [async] call and exits with 0 when every call succeeded, 1');
  Lines.Add('# otherwise.');
  Lines.Add('#');
  Lines.Add('# NOTE ON LANGUAGES');
  Lines.Add('# -----------------');
  Lines.Add('# "C CXX" is required as the project language list. LingoFuse.c');
  Lines.Add('# is a C source file; CMake cannot pick a link language for a');
  Lines.Add('# target that mixes .c and .cpp files when only CXX is enabled.');
  Lines.Add('#');
  Lines.Add('cmake_minimum_required(VERSION 3.15)');
  Lines.Add('');
  Lines.Add('project(' + ProjectName.Text + ' C CXX)');
  Lines.Add('');
  Lines.Add('set(CMAKE_CXX_STANDARD 17)');
  Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
  Lines.Add('set(CMAKE_CXX_EXTENSIONS OFF)');
  Lines.Add('');
  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('# LingoFuse C++ library directory');
  Lines.Add('#');
  Lines.Add('# LINGOFUSE_CPP_LIB_DIR is a CACHE PATH entry. It appears in');
  Lines.Add('# cmake-gui as a browsable directory field and can also be set');
  Lines.Add('# from the command line with -DLINGOFUSE_CPP_LIB_DIR=... .');
  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('set(LINGOFUSE_CPP_LIB_DIR "" CACHE PATH "LingoFuse C++ library directory")');
  Lines.Add('');
  Lines.Add('if(NOT EXISTS "${LINGOFUSE_CPP_LIB_DIR}/LingoFuse.h")');
  Lines.Add('    message(FATAL_ERROR');
  Lines.Add('        "LINGOFUSE_CPP_LIB_DIR does not point at a LingoFuse C++ "');
  Lines.Add('        "library directory (LingoFuse.h was not found). "');
  Lines.Add('        "Current value: ''${LINGOFUSE_CPP_LIB_DIR}''. "');
  Lines.Add('        "Set it in cmake-gui or pass "');
  Lines.Add('        "-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf on the cmake command line.")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('set(LINGOFUSE_C_SOURCE    "${LINGOFUSE_CPP_LIB_DIR}/LingoFuse.c")');
  Lines.Add('set(LINGOFUSE_INCLUDE_DIR "${LINGOFUSE_CPP_LIB_DIR}")');
  Lines.Add('');
  Lines.Add('set(PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}")');
  Lines.Add('');
end;

procedure EmitWarningFlags(Lines: TPascalStringList;
  const TargetName: U_String);
begin
  Lines.Add('if(MSVC)');
  Lines.Add('    target_compile_options(' + TargetName.Text +
    ' PRIVATE /W4 /permissive-)');
  Lines.Add('else()');
  Lines.Add('    target_compile_options(' + TargetName.Text +
    ' PRIVATE -Wall -Wextra)');
  Lines.Add('endif()');
  Lines.Add('');
end;

procedure EmitLinkLibraries(Lines: TPascalStringList;
  const TargetName: U_String);
begin
  Lines.Add('if(WIN32)');
  Lines.Add('    target_link_libraries(' + TargetName.Text + ' PRIVATE ws2_32)');
  Lines.Add('elseif(APPLE)');
  Lines.Add('    find_package(Threads REQUIRED)');
  Lines.Add('    target_link_libraries(' + TargetName.Text + ' PRIVATE Threads::Threads)');
  Lines.Add('else()');
  Lines.Add('    find_package(Threads REQUIRED)');
  Lines.Add('    target_link_libraries(' + TargetName.Text + ' PRIVATE');
  Lines.Add('        Threads::Threads ${CMAKE_DL_LIBS})');
  Lines.Add('endif()');
  Lines.Add('');
end;

procedure EmitServiceTarget(Lines: TPascalStringList;
  const UnitName: U_String);
var
  TargetName, ServiceHpp, ServiceCpp: U_String;
begin
  TargetName := UnitName + '_http_json_service';
  ServiceHpp := UnitName + '_http_json_service.hpp';
  ServiceCpp := UnitName + '_http_json_service.cpp';

  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('# Service executable');
  Lines.Add('#');
  Lines.Add('# Built from ' + ServiceCpp.Text + ', which is produced by');
  Lines.Add('# http_cpp_abi_service_generator_tool.pas. That source file');
  Lines.Add('# contains its own main() entry point, so the target is an');
  Lines.Add('# executable rather than a library.');
  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('set(SERVICE_HPP "${PROJECT_DIR}/' + ServiceHpp.Text + '")');
  Lines.Add('set(SERVICE_CPP "${PROJECT_DIR}/' + ServiceCpp.Text + '")');
  Lines.Add('');
  Lines.Add('if(NOT EXISTS "${SERVICE_CPP}")');
  Lines.Add('    message(FATAL_ERROR');
  Lines.Add('        "Missing generated service source file: ''${SERVICE_CPP}''. "');
  Lines.Add('        "Run http_cpp_abi_service_generator_tool.pas and place its "');
  Lines.Add('        "output next to this CMakeLists.txt.")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('add_executable(' + TargetName.Text);
  Lines.Add('    "${SERVICE_CPP}"');
  Lines.Add('    "${LINGOFUSE_C_SOURCE}"');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('target_include_directories(' + TargetName.Text + ' PRIVATE');
  Lines.Add('    "${PROJECT_DIR}"');
  Lines.Add('    "${LINGOFUSE_INCLUDE_DIR}"');
  Lines.Add(')');
  Lines.Add('');
  EmitWarningFlags(Lines, TargetName);
  EmitLinkLibraries(Lines, TargetName);
end;

procedure EmitCallTestTarget(Lines: TPascalStringList;
  const UnitName: U_String);
var
  TargetName, CallHpp, CallCpp, TestMain: U_String;
begin
  TargetName := UnitName + '_http_json_call_test';
  CallHpp := UnitName + '_http_json_call.hpp';
  CallCpp := UnitName + '_http_json_call.cpp';
  TestMain := 'test_main___.cpp';

  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('# Call test executable');
  Lines.Add('#');
  Lines.Add('# Built from ' + TestMain.Text + ' (produced by');
  Lines.Add('# http_cmake_generator_tool.pas) and ' + CallCpp.Text + ' (produced');
  Lines.Add('# by http_cpp_abi_call_generator_tool.pas). The test driver');
  Lines.Add('# prepares LingoFuse, sets HTTP_CALL_BASE_URL, then exercises BOTH');
  Lines.Add('# the synchronous and the asynchronous call path for every');
  Lines.Add('# supported routine.');
  Lines.Add('# ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('set(CALL_HPP  "${PROJECT_DIR}/' + CallHpp.Text + '")');
  Lines.Add('set(CALL_CPP  "${PROJECT_DIR}/' + CallCpp.Text + '")');
  Lines.Add('set(TEST_MAIN "${PROJECT_DIR}/' + TestMain.Text + '")');
  Lines.Add('');
  Lines.Add('if(NOT EXISTS "${CALL_CPP}")');
  Lines.Add('    message(FATAL_ERROR');
  Lines.Add('        "Missing generated call source file: ''${CALL_CPP}''. "');
  Lines.Add('        "Run http_cpp_abi_call_generator_tool.pas and place its "');
  Lines.Add('        "output next to this CMakeLists.txt.")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('if(NOT EXISTS "${TEST_MAIN}")');
  Lines.Add('    message(FATAL_ERROR');
  Lines.Add('        "Missing test driver: ''${TEST_MAIN}''. "');
  Lines.Add('        "Run http_cmake_generator_tool.pas to generate it.")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('add_executable(' + TargetName.Text);
  Lines.Add('    "${TEST_MAIN}"');
  Lines.Add('    "${CALL_CPP}"');
  Lines.Add('    "${LINGOFUSE_C_SOURCE}"');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('target_include_directories(' + TargetName.Text + ' PRIVATE');
  Lines.Add('    "${PROJECT_DIR}"');
  Lines.Add('    "${LINGOFUSE_INCLUDE_DIR}"');
  Lines.Add(')');
  Lines.Add('');
  EmitWarningFlags(Lines, TargetName);
  EmitLinkLibraries(Lines, TargetName);
end;

function GenerateCMakeScript(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, Normalized, ProjectName: U_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateCMakeScript: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateCMakeScript: UnitName is empty');
    Exit;
  end;

  Normalized := NormalizeUnitName(UnitName);
  ProjectName := Normalized + '_http_json_test';

  Lines := TPascalStringList.Create;
  try
    EmitPrologue(Lines, ProjectName, Normalized);
    EmitServiceTarget(Lines, Normalized);
    EmitCallTestTarget(Lines, Normalized);

    Result := Lines;
    Log(PFormat('Generated CMake script: %d lines, project "%s".',
      [Lines.Count, ProjectName.Text]));
  except
    DisposeObject(Lines);
    raise;
  end;
end;

// -----------------------------------------------------------------------------
// Test driver (test_main___.cpp)
// -----------------------------------------------------------------------------

// BuildDefaultArgList - comma-separated default test arguments for a
// parameter list.
function BuildDefaultArgList(const F: TFunctionStructure): U_String;
var
  i: integer;
  arg: U_String;
begin
  Result := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    arg := ABI_Type_To_Cpp_Default_Arg(F.Params[i].PascalType);
    Result := Result + arg;
  end;
end;

// EmitTestCall - emit the [sync] and [async] test blocks for one
// supported routine.
//
// Both blocks are wrapped in their own `{}` scope, so the local names
// `r`, `p`, `fut`, `submit_ok` never collide across routines.
//
// The async block uses std::promise / std::future:
//
//   * The callback delivers an ApiNameAsyncResult into the promise.
//   * The driver waits up to 30 s on the paired future.
//
// Dispatch failure (LF_Async_Call returns 0, or the request cannot be
// serialized) is reported through the SAME callback, synchronously on
// the caller's thread; the future is therefore already ready and the
// driver reports FAILED immediately.
procedure EmitTestCall(Lines: TPascalStringList;
  const Ns, CppFuncName, ApiName: U_String;
  const F: TFunctionStructure);
var
  ArgList: U_String;
  HasParams: boolean;
begin
  ArgList := BuildDefaultArgList(F);
  HasParams := Length(F.Params) > 0;

  // ---- Sync block ----
  Lines.Add('    // ---- ' + ApiName.Text + ' [sync] ----');
  Lines.Add('    {');
  Lines.Add('        std::printf("  ' + ApiName.Text + ' [sync] : ");');
  Lines.Add('        try {');
  if F.IsFunction then
  begin
    Lines.Add('            auto r = ' + Ns.Text + '::' + CppFuncName.Text +
      '(' + ArgList.Text + ');');
    Lines.Add('            std::printf("OK\n");');
    Lines.Add('            (void)r;');
  end
  else
  begin
    Lines.Add('            ' + Ns.Text + '::' + CppFuncName.Text +
      '(' + ArgList.Text + ');');
    Lines.Add('            std::printf("OK\n");');
  end;
  Lines.Add('        } catch (const ' + Ns.Text + '::HTTPCallError& e) {');
  Lines.Add('            std::printf("FAILED: %s (code=%d, http=%d)\n",');
  Lines.Add('                e.what(), e.code, e.http_status);');
  Lines.Add('            ++failures;');
  Lines.Add('        } catch (const std::exception& e) {');
  Lines.Add('            std::printf("FAILED: unexpected: %s\n", e.what());');
  Lines.Add('            ++failures;');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');

  // ---- Async block ----
  Lines.Add('    // ---- ' + ApiName.Text + ' [async] ----');
  Lines.Add('    {');
  Lines.Add('        std::printf("  ' + ApiName.Text + ' [async]: ");');
  Lines.Add('        auto p = std::make_shared<std::promise<');
  Lines.Add('            ' + Ns.Text + '::' + CppFuncName.Text + 'AsyncResult>>();');
  Lines.Add('        auto fut = p->get_future();');
  Lines.Add('        bool submit_ok = true;');
  Lines.Add('        try {');
  if HasParams then
    Lines.Add('            ' + Ns.Text + '::' + CppFuncName.Text +
      '_Async(' + ArgList.Text + ',')
  else
    Lines.Add('            ' + Ns.Text + '::' + CppFuncName.Text + '_Async(');
  Lines.Add('                [p](auto r) {');
  Lines.Add('                    // The framework guarantees the callback fires at');
  Lines.Add('                    // most once, but guard against a double set_value');
  Lines.Add('                    // so that this test driver cannot crash on a');
  Lines.Add('                    // pathological framework bug.');
  Lines.Add('                    try { p->set_value(std::move(r)); } catch (...) {}');
  Lines.Add('                });');
  Lines.Add('        } catch (const std::exception& e) {');
  Lines.Add('            std::printf("FAILED: submit threw: %s\n", e.what());');
  Lines.Add('            ++failures;');
  Lines.Add('            submit_ok = false;');
  Lines.Add('        }');
  Lines.Add('        if (submit_ok) {');
  Lines.Add('            if (fut.wait_for(std::chrono::seconds(30))');
  Lines.Add('                    == std::future_status::ready) {');
  Lines.Add('                auto r = fut.get();');
  Lines.Add('                if (r.ok) {');
  Lines.Add('                    std::printf("OK\n");');
  Lines.Add('                } else {');
  Lines.Add('                    std::printf("FAILED: %s (code=%d)\n",');
  Lines.Add('                        r.error.c_str(), r.code);');
  Lines.Add('                    ++failures;');
  Lines.Add('                }');
  Lines.Add('            } else {');
  Lines.Add('                std::printf("FAILED: timeout after 30s\n");');
  Lines.Add('                ++failures;');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

function GenerateTestMainCpp(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, Normalized, Ns, Endpoint, BaseUrl: U_String;
  SupportedFuncs: TArryFunctionStructure;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedCppFuncNames, CppFuncNames: TPascalStringList;
  ApiName, CppFuncName: U_String;
  i: integer;
  f: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateTestMainCpp: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateTestMainCpp: UnitName is empty');
    Exit;
  end;

  Normalized := NormalizeUnitName(UnitName);
  Ns := Normalized.LowerText;
  Endpoint := 'ipc:' + Normalized + '_http_json';
  BaseUrl := 'http://127.0.0.1:8081/' + Normalized;

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
    Lines.Add('// Auto-generated by http_cmake_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Test driver for the ' + Normalized.Text + '_http_json_call wrapper.');
    Lines.Add('//');
    Lines.Add('// What this program does:');
    Lines.Add('//');
    Lines.Add('//   1. Loads the LingoFuse dynamic library through');
    Lines.Add('//      lingofuse::LibraryLoader.');
    Lines.Add('//   2. Prepares a client connection to the LingoFuse endpoint');
    Lines.Add('//      "' + Endpoint.Text + '".');
    Lines.Add('//   3. Points the call wrapper at the bridge by setting');
    Lines.Add('//      HTTP_CALL_BASE_URL.');
    Lines.Add('//   4. For every supported wrapper function, exercises BOTH:');
    Lines.Add('//        - the [sync]  variant, which blocks until the response');
    Lines.Add('//          arrives and reports OK or FAILED;');
    Lines.Add('//        - the [async] variant, which submits the request and');
    Lines.Add('//          delivers the outcome through a std::promise; the');
    Lines.Add('//          driver waits up to 30 s on the paired future.');
    Lines.Add('//   5. Returns 0 when every call succeeded, 1 otherwise.');
    Lines.Add('//');
    Lines.Add('// Prerequisite: bridge.py must be running on the same LingoFuse');
    Lines.Add('// endpoint, and the service executable must be running too.');
    Lines.Add('');
    Lines.Add('#include "' + Normalized.Text + '_http_json_call.hpp"');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('#include <chrono>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstdio>');
    Lines.Add('#include <exception>');
    Lines.Add('#include <future>');
    Lines.Add('#include <memory>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    lingofuse::LibraryLoader loader;');
    Lines.Add('');
    Lines.Add('    lingofuse::resetPrepare();');
    Lines.Add('    lingofuse::prepareClient("' + Endpoint.Text + '", nullptr);');
    Lines.Add('    if (lingofuse::prepareDone() != 1) {');
    Lines.Add('        std::printf("LingoFuse init failed\n");');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    ' + Ns.Text + '::HTTP_CALL_BASE_URL = "'
      + BaseUrl.Text + '";');
    Lines.Add('');
    Lines.Add('    int failures = 0;');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    std::printf("no routines to test\n");');
    end
    else
    begin
      Lines.Add('    std::printf("=== ' + Normalized.Text + ' HTTP/JSON call test ===\n");');
      Lines.Add('    std::printf("Base URL: " "' + BaseUrl.Text + '" "\n");');
      Lines.Add('    std::printf("\n");');
      Lines.Add('');
      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := ApiNames[i];
        CppFuncName := CppFuncNames[i];
        EmitTestCall(Lines, Ns, CppFuncName, ApiName, f);
      end;
    end;

    Lines.Add('    lingofuse::exitMainThread();');
    Lines.Add('    lingofuse::shutdown();');
    Lines.Add('');
    Lines.Add('    if (failures == 0) {');
    Lines.Add('        std::printf("all calls succeeded\n");');
    Lines.Add('        return 0;');
    Lines.Add('    }');
    Lines.Add('    std::printf("%d call(s) failed\n", failures);');
    Lines.Add('    return 1;');
    Lines.Add('}');

    Result := Lines;
    Log(PFormat('Generated test driver: %d lines, %d routines (sync + async).',
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
    'cpp', 'CMake build script',
    asBoth, akBuildScript,
    'CMakeLists.txt', True,
    @GenerateCMakeScript);
  RegisterCodeGenEntry(
    'cpp', 'CMake test driver',
    asBoth, akBuildMain,
    'test_main___.cpp', True,
    @GenerateTestMainCpp);
end.
