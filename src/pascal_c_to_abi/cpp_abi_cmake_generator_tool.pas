unit cpp_abi_cmake_generator_tool;


// cpp_abi_cmake_generator_tool - CMake + test-program generator for the
// C++ ABI backend of code_decl_to_abi.
//
// Given a TPascal_Func_Model (built with Typ_Normalize_Func = tnf_ABI),
// this unit produces three artefacts that turn the raw C++ ABI sources
// into a buildable, runnable project:
//
//   GenerateABICmakeScript         ->  CMakeLists.txt
//   GenerateABIServiceTestProgram  ->  <unit>_abi_service_main.cpp
//   GenerateABICallTestProgram     ->  <unit>_abi_call_main.cpp
//
// Runtime-loading contract (as mandated by LingoFuse.h):
//
//   LingoFuse.c is a dynamic-loading wrapper. Every LF_* symbol is
//   resolved lazily at runtime. The host program MUST call
//   LF_LoadLibrary() BEFORE any other LF_* call, and LF_FreeLibrary()
//   AFTER LF_Shutdown().
//
//   Signature:
//
//       int  LF_LoadLibrary(void);
//       void LF_FreeLibrary(void);
//
//   LF_LoadLibrary takes NO arguments. The wrapper resolves the runtime
//   library using a fixed search order:
//
//       1. the directory that contains the current executable, then
//       2. the OS default search path.
//
//   The expected runtime file names are:
//
//       Windows : LingoFuse64.dll (or LingoFuse32.dll)
//       Linux   : liblingofuse.so
//       macOS   : liblingofuse.dylib
//
//   There is no environment-variable override at the C ABI level.
//   To relocate the runtime, place it next to the executable, or make
//   sure it is reachable through the platform's default loader search
//   path (PATH on Windows, LD_LIBRARY_PATH on Linux, DYLD_LIBRARY_PATH
//   on macOS).
//
// All comments and status messages emitted by this unit and by the
// generated files are in English.
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


function GenerateABICmakeScript(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABIServiceTestProgram(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestProgram(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging helpers
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_cmake_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_cmake_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type mapping
// -----------------------------------------------------------------------------

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Cpp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'int32_t'
  else if T.Same('int64') then Result := 'int64_t'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'uint32_t'
  else if T.Same('word') then Result := 'uint16_t'
  else if T.Same('smallint') then Result := 'int16_t'
  else if T.Same('byte') then Result := 'uint8_t'
  else if T.Same('uint64') then Result := 'uint64_t'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'double'
  else if T.Same('single') then Result := 'float'
  else if IsStringABIType(T) then Result := 'std::string'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Cpp_Decl(T) <> '';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
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

// -----------------------------------------------------------------------------
// EmitRuntimeLoadPrelude
//
// Emits the mandatory runtime-loading prelude. This block MUST be
// emitted before any other LF_* call in both test programs.
//
// Contract enforced by LingoFuse.h:
//
//     int LF_LoadLibrary(void);
//
//   - No arguments. The wrapper searches the executable directory
//     first, then the OS default search path.
//   - Returns 1 on success, 0 on failure.
//   - Must be the very first LF_* call in the process.
// -----------------------------------------------------------------------------

procedure EmitRuntimeLoadPrelude(Lines: TPascalStringList);
begin
  Lines.Add('    // -----------------------------------------------------------------');
  Lines.Add('    // Step 1: load the LingoFuse runtime dynamic library.');
  Lines.Add('    //');
  Lines.Add('    // LF_LoadLibrary() takes no arguments and must be the very first');
  Lines.Add('    // LF_* call in the process. The wrapper resolves every other LF_*');
  Lines.Add('    // symbol lazily after the library has been loaded.');
  Lines.Add('    //');
  Lines.Add('    // Search order used by the wrapper:');
  Lines.Add('    //   1. the directory containing the current executable, then');
  Lines.Add('    //   2. the OS default search path.');
  Lines.Add('    //');
  Lines.Add('    // Expected runtime file names:');
  Lines.Add('    //   Windows : LingoFuse64.dll (or LingoFuse32.dll)');
  Lines.Add('    //   Linux   : liblingofuse.so');
  Lines.Add('    //   macOS   : liblingofuse.dylib');
  Lines.Add('    //');
  Lines.Add('    // There is no environment-variable override at the C ABI level.');
  Lines.Add('    // Either place the runtime next to this executable, or make it');
  Lines.Add('    // reachable through the platform loader search path (PATH on');
  Lines.Add('    // Windows, LD_LIBRARY_PATH on Linux, DYLD_LIBRARY_PATH on macOS).');
  Lines.Add('    // -----------------------------------------------------------------');
  Lines.Add('    if (LF_LoadLibrary() != 1) {');
  Lines.Add('        std::fprintf(stderr,');
  Lines.Add('            "[FATAL] LF_LoadLibrary failed.\n"');
  Lines.Add('            "        Could not load the LingoFuse runtime library.\n"');
  Lines.Add('            "        Place it next to this executable, or on the OS\n"');
  Lines.Add('            "        loader search path:\n"');
  Lines.Add('            "          Windows : LingoFuse64.dll\n"');
  Lines.Add('            "          Linux   : liblingofuse.so\n"');
  Lines.Add('            "          macOS   : liblingofuse.dylib\n");');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('    std::printf("[OK] LingoFuse runtime loaded.\n");');
  Lines.Add('');
end;

// -----------------------------------------------------------------------------
// GenerateABICmakeScript
// -----------------------------------------------------------------------------

function GenerateABICmakeScript(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, NsName: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICmakeScript: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICmakeScript: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';

  Log(PFormat('Generating CMake script for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('CMake script covers %d valid APIs', [Length(SupportedFuncs)]));

  Lines := TPascalStringList.Create;
  try
    // -------------------------------------------------------------------------
    // Header
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Auto-generated by cpp_abi_cmake_generator_tool.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# This CMake script builds the C++ ABI artefacts produced by');
    Lines.Add('# code_decl_to_abi for the unit "' + UnitName.Text + '". It is');
    Lines.Add('# self-contained: it detects which of the four source files are');
    Lines.Add('# present (service .cpp, service test main.cpp, call-side .cpp,');
    Lines.Add('# call-side test main.cpp) and creates only the corresponding');
    Lines.Add('# targets.');
    Lines.Add('#');
    Lines.Add('# Layout assumed by this script (all files in the same directory):');
    Lines.Add('#');
    Lines.Add('#   ' + NormalizedUnit + '_abi_service.hpp');
    Lines.Add('#   ' + NormalizedUnit + '_abi_service.cpp');
    Lines.Add('#   ' + NormalizedUnit + '_abi_service_main.cpp   (optional)');
    Lines.Add('#   ' + NormalizedUnit + '_abi_call.hpp');
    Lines.Add('#   ' + NormalizedUnit + '_abi_call.cpp');
    Lines.Add('#   ' + NormalizedUnit + '_abi_call_main.cpp      (optional)');
    Lines.Add('#');
    Lines.Add('# LingoFuse C/C++ interface directory (LINGOFUSE_CPP_DIR) must');
    Lines.Add('# contain:');
    Lines.Add('#');
    Lines.Add('#   LingoFuse.h    - C ABI declarations');
    Lines.Add('#   LingoFuse.c    - C ABI dynamic-loading wrapper (compiled by this script)');
    Lines.Add('#   LingoFuse.hpp  - C++ RAII wrapper (header-only)');
    Lines.Add('#   lf_io.hpp      - Unified I/O (header-only)');
    Lines.Add('#');
    Lines.Add('# Basic usage:');
    Lines.Add('#');
    Lines.Add('#   cmake -S . -B build -DLINGOFUSE_CPP_DIR=<interface-dir>');
    Lines.Add('#   cmake --build build --config Release');
    Lines.Add('#');
    Lines.Add('# Runtime library:');
    Lines.Add('#');
    Lines.Add('#   The generated test programs call LF_LoadLibrary() as their very');
    Lines.Add('#   first LF_* operation. LF_LoadLibrary() takes no arguments; the');
    Lines.Add('#   wrapper searches the executable directory first, then the OS');
    Lines.Add('#   default search path. Place the runtime (LingoFuse64.dll /');
    Lines.Add('#   liblingofuse.so / liblingofuse.dylib) either next to the test');
    Lines.Add('#   executables or somewhere already on the loader search path.');
    Lines.Add('#   This script does not copy or link the runtime.');
    Lines.Add('#');
    Lines.Add('# Targets produced (when the corresponding sources exist):');
    Lines.Add('#');
    Lines.Add('#   lingofuse_c_wrapper           static library from LingoFuse.c');
    Lines.Add('#   ' + NsName + '_service       static library from the service .cpp');
    Lines.Add('#   ' + NsName + '_service_test  executable from the service main.cpp');
    Lines.Add('#   ' + NsName + '_call          static library from the call-side .cpp');
    Lines.Add('#   ' + NsName + '_call_test     executable from the call-side main.cpp');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('');
    Lines.Add('project(' + NsName + ' LANGUAGES C CXX)');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Standard configuration
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Build configuration');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('set(CMAKE_CXX_EXTENSIONS OFF)');
    Lines.Add('');
    Lines.Add('if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)');
    Lines.Add('    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)');
    Lines.Add('endif()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Locate the LingoFuse C/C++ interface directory
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Locate the LingoFuse C/C++ interface directory');
    Lines.Add('#');
    Lines.Add('# LINGOFUSE_CPP_DIR is the only external input the script needs.');
    Lines.Add('# It must contain LingoFuse.h, LingoFuse.c, LingoFuse.hpp, lf_io.hpp.');
    Lines.Add('#');
    Lines.Add('# The script does not look for or link against the LingoFuse runtime');
    Lines.Add('# shared library (LingoFuse64.dll / liblingofuse.so /');
    Lines.Add('# liblingofuse.dylib). Loading the runtime is handled at program');
    Lines.Add('# startup by LF_LoadLibrary(), which searches the executable');
    Lines.Add('# directory first and then the OS default search path.');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('if(NOT DEFINED LINGOFUSE_CPP_DIR AND DEFINED ENV{LINGOFUSE_CPP_DIR})');
    Lines.Add('    set(LINGOFUSE_CPP_DIR "$ENV{LINGOFUSE_CPP_DIR}" CACHE PATH');
    Lines.Add('        "Directory containing LingoFuse.h, LingoFuse.c, LingoFuse.hpp, lf_io.hpp")');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('if(NOT DEFINED LINGOFUSE_CPP_DIR)');
    Lines.Add('    set(LINGOFUSE_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE PATH');
    Lines.Add('        "Directory containing LingoFuse.h, LingoFuse.c, LingoFuse.hpp, lf_io.hpp")');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('if(NOT EXISTS "${LINGOFUSE_CPP_DIR}/LingoFuse.h")');
    Lines.Add('    message(FATAL_ERROR');
    Lines.Add('        "LingoFuse.h not found under ${LINGOFUSE_CPP_DIR}. "');
    Lines.Add('        "Set LINGOFUSE_CPP_DIR to the directory that contains it.")');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('if(NOT EXISTS "${LINGOFUSE_CPP_DIR}/LingoFuse.c")');
    Lines.Add('    message(FATAL_ERROR');
    Lines.Add('        "LingoFuse.c not found under ${LINGOFUSE_CPP_DIR}. "');
    Lines.Add('        "The C ABI dynamic-loading wrapper source is required.")');
    Lines.Add('endif()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // LingoFuse C ABI wrapper static library
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# LingoFuse C ABI wrapper (static library)');
    Lines.Add('#');
    Lines.Add('# This compiles LingoFuse.c, which resolves every LF_* symbol at');
    Lines.Add('# runtime. On Windows no extra library is required (kernel32 is');
    Lines.Add('# linked by default). On Unix, libdl is required for dlopen/dlsym.');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('add_library(lingofuse_c_wrapper STATIC');
    Lines.Add('    "${LINGOFUSE_CPP_DIR}/LingoFuse.c")');
    Lines.Add('target_include_directories(lingofuse_c_wrapper PUBLIC');
    Lines.Add('    "${LINGOFUSE_CPP_DIR}")');
    Lines.Add('if(NOT WIN32)');
    Lines.Add('    target_link_libraries(lingofuse_c_wrapper PUBLIC ${CMAKE_DL_LIBS})');
    Lines.Add('endif()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Common compile options
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Compile options shared by every target in this project');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('set(_lf_common_compile_opts "")');
    Lines.Add('if(MSVC)');
    Lines.Add('    list(APPEND _lf_common_compile_opts /utf-8 /EHsc /W4)');
    Lines.Add('else()');
    Lines.Add('    list(APPEND _lf_common_compile_opts -Wall -Wextra)');
    Lines.Add('endif()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Helper: attach standard options to a target
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Helper: attach the standard LingoFuse options to a target');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('function(lingofuse_apply_target_defaults tgt)');
    Lines.Add('    target_include_directories(${tgt} PUBLIC');
    Lines.Add('        "${CMAKE_CURRENT_SOURCE_DIR}"');
    Lines.Add('        "${LINGOFUSE_CPP_DIR}")');
    Lines.Add('    target_link_libraries(${tgt} PUBLIC lingofuse_c_wrapper)');
    Lines.Add('    target_compile_options(${tgt} PRIVATE ${_lf_common_compile_opts})');
    Lines.Add('endfunction()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Service library + test
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Service side');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_service.cpp")');
    Lines.Add('');
    Lines.Add('    add_library(' + NsName + '_service STATIC');
    Lines.Add('        ' + NormalizedUnit + '_abi_service.cpp)');
    Lines.Add('    lingofuse_apply_target_defaults(' + NsName + '_service)');
    Lines.Add('');
    Lines.Add('    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_service_main.cpp")');
    Lines.Add('        add_executable(' + NsName + '_service_test');
    Lines.Add('            ' + NormalizedUnit + '_abi_service_main.cpp)');
    Lines.Add('        lingofuse_apply_target_defaults(' + NsName + '_service_test)');
    Lines.Add('        target_link_libraries(' + NsName + '_service_test PRIVATE');
    Lines.Add('            ' + NsName + '_service)');
    Lines.Add('    endif()');
    Lines.Add('');
    Lines.Add('endif()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Call-side library + test
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Call side');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_call.cpp")');
    Lines.Add('');
    Lines.Add('    add_library(' + NsName + '_call STATIC');
    Lines.Add('        ' + NormalizedUnit + '_abi_call.cpp)');
    Lines.Add('    lingofuse_apply_target_defaults(' + NsName + '_call)');
    Lines.Add('');
    Lines.Add('    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_call_main.cpp")');
    Lines.Add('        add_executable(' + NsName + '_call_test');
    Lines.Add('            ' + NormalizedUnit + '_abi_call_main.cpp)');
    Lines.Add('        lingofuse_apply_target_defaults(' + NsName + '_call_test)');
    Lines.Add('        target_link_libraries(' + NsName + '_call_test PRIVATE');
    Lines.Add('            ' + NsName + '_call)');
    Lines.Add('    endif()');
    Lines.Add('');
    Lines.Add('endif()');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('# Summary');
    Lines.Add('#');
    Lines.Add('# The script has finished configuring. Run `cmake --build build` to');
    Lines.Add('# compile the targets that were created. Targets whose sources were');
    Lines.Add('# absent are silently skipped.');
    Lines.Add('#');
    Lines.Add('# The runtime shared library is not copied and no RPATH is set.');
    Lines.Add('# The generated test programs call LF_LoadLibrary() as their very');
    Lines.Add('# first LF_* operation. That function takes no arguments: the');
    Lines.Add('# wrapper searches the executable directory first, then the OS');
    Lines.Add('# default search path (PATH on Windows, LD_LIBRARY_PATH on Linux,');
    Lines.Add('# DYLD_LIBRARY_PATH on macOS). Place the runtime library');
    Lines.Add('# accordingly before running the tests.');
    Lines.Add('# ---------------------------------------------------------------------------');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the CMake script.', [Lines.Count]));
  finally
    // Lines is returned to the caller; not freed here.
  end;
end;

// -----------------------------------------------------------------------------
// GenerateABIServiceTestProgram
// -----------------------------------------------------------------------------

function GenerateABIServiceTestProgram(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, NsName, AppName: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestProgram: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestProgram: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C++ ABI service test program for unit "%s"',
    [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service test program references %d APIs',
    [Length(SupportedFuncs)]));

  Lines := TPascalStringList.Create;
  try
    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by cpp_abi_cmake_generator_tool.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Test entry point for the generated C++ ABI service.');
    Lines.Add('//');
    Lines.Add('// Build: see the accompanying CMakeLists.txt.');
    Lines.Add('//');
    Lines.Add('// What this program does:');
    Lines.Add('//   1. Load the LingoFuse runtime dynamic library via LF_LoadLibrary().');
    Lines.Add('//   2. Prepare and start the service endpoint.');
    Lines.Add('//   3. Register every generated API.');
    Lines.Add('//   4. Connect a local client to that endpoint.');
    Lines.Add('//   5. Wait for the user to press Enter.');
    Lines.Add('//   6. Shut down cleanly in the recommended order, then unload the');
    Lines.Add('//      runtime via LF_FreeLibrary().');
    Lines.Add('//');
    Lines.Add('// Run this program in one terminal, then run the matching client');
    Lines.Add('// test (<unit>_abi_call_main.cpp) in another terminal to exercise');
    Lines.Add('// the APIs end to end.');
    Lines.Add('//');
    Lines.Add('// Runtime library location:');
    Lines.Add('//   LF_LoadLibrary() takes no arguments. Place LingoFuse64.dll /');
    Lines.Add('//   liblingofuse.so / liblingofuse.dylib either next to this');
    Lines.Add('//   executable or somewhere already on the loader search path');
    Lines.Add('//   (PATH / LD_LIBRARY_PATH / DYLD_LIBRARY_PATH).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#include "' + NormalizedUnit + '_abi_service.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdio>');
    Lines.Add('#include <cstdlib>');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    std::printf("=== ' + UnitName.Text + ' ABI service test ===\n");');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Runtime loading prelude
    // -------------------------------------------------------------------------
    EmitRuntimeLoadPrelude(Lines);

    // -------------------------------------------------------------------------
    // Prepare the service
    // -------------------------------------------------------------------------
    Lines.Add('    LF_ResetPrepare();');
    Lines.Add('    LF_PrepareService("ipc:' + AppName + '", "ipc:' + AppName + '");');
    Lines.Add('');
    Lines.Add('    TAppHnd app = ' + NsName + '::CreateAndRegisterABIApp();');
    Lines.Add('    if (app == nullptr) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] CreateAndRegisterABIApp failed\n");');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (LF_PrepareClient("ipc:' + AppName + '", app) == -1) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareClient failed\n");');
    Lines.Add('        LF_FreeApp(app);');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (LF_PrepareDone() != 1) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareDone failed\n");');
    Lines.Add('        LF_ExitMainThread();');
    Lines.Add('        LF_FreeApp(app);');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std::printf("[OK] Service ready on ipc:%s.\n", "'
      + AppName + '");');
    Lines.Add('    std::printf("[OK] Registered %d API(s).\n", '
      + umlIntToStr(Length(SupportedFuncs)).Text + ');');
    Lines.Add('    std::printf("[OK] Press Enter to shut down.\n");');
    Lines.Add('    std::getchar();');
    Lines.Add('');
    Lines.Add('    LF_ExitMainThread();');
    Lines.Add('    LF_FreeApp(app);');
    Lines.Add('    LF_Shutdown();');
    Lines.Add('    LF_FreeLibrary();');
    Lines.Add('    std::printf("[OK] Shutdown complete.\n");');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service test program.',
      [Lines.Count]));
  finally
    // Lines is returned to the caller; not freed here.
  end;
end;

// -----------------------------------------------------------------------------
// BuildCallArgs
// -----------------------------------------------------------------------------

function BuildCallArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';

    if IsStringABIType(Params[i].PascalType) then
      Result := Result + '"test"'
    else if Params[i].PascalType.Same('double') or
            Params[i].PascalType.Same('extended') or
            Params[i].PascalType.Same('real') then
      Result := Result + '0.0'
    else if Params[i].PascalType.Same('single') then
      Result := Result + '0.0f'
    else
      Result := Result + '0';
  end;
end;

// -----------------------------------------------------------------------------
// GenerateABICallTestProgram
// -----------------------------------------------------------------------------

function GenerateABICallTestProgram(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  UnitName, NormalizedUnit, NsName, AppName: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  Lines: TPascalStringList;
  f: TFunctionStructure;
  ApiName, Args: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestProgram: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestProgram: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C++ ABI call test program for unit "%s"',
    [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call test program exercises %d APIs',
    [Length(SupportedFuncs)]));

  Lines := TPascalStringList.Create;
  try
    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by cpp_abi_cmake_generator_tool.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Test entry point for the generated C++ ABI client.');
    Lines.Add('//');
    Lines.Add('// Build: see the accompanying CMakeLists.txt.');
    Lines.Add('//');
    Lines.Add('// Before running this program, start the matching service in');
    Lines.Add('// another terminal:');
    Lines.Add('//');
    Lines.Add('//     ' + NormalizedUnit + '_service_test');
    Lines.Add('//');
    Lines.Add('// Then run this program:');
    Lines.Add('//');
    Lines.Add('//     ' + NormalizedUnit + '_call_test');
    Lines.Add('//');
    Lines.Add('// The program calls every generated API exactly once, using');
    Lines.Add('// type-appropriate placeholder arguments, and prints each result.');
    Lines.Add('// Every call is wrapped in its own try/catch so that a single');
    Lines.Add('// failing API does not abort the rest of the run.');
    Lines.Add('//');
    Lines.Add('// Runtime library location:');
    Lines.Add('//   LF_LoadLibrary() takes no arguments. Place LingoFuse64.dll /');
    Lines.Add('//   liblingofuse.so / liblingofuse.dylib either next to this');
    Lines.Add('//   executable or somewhere already on the loader search path');
    Lines.Add('//   (PATH / LD_LIBRARY_PATH / DYLD_LIBRARY_PATH).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#include "' + NormalizedUnit + '_abi_call.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdio>');
    Lines.Add('#include <cstdlib>');
    Lines.Add('#include <exception>');
    Lines.Add('#include <iostream>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    std::printf("=== ' + UnitName.Text
      + ' ABI client test ===\n");');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Runtime loading prelude
    // -------------------------------------------------------------------------
    EmitRuntimeLoadPrelude(Lines);

    // -------------------------------------------------------------------------
    // Prepare the client
    // -------------------------------------------------------------------------
    Lines.Add('    LF_ResetPrepare();');
    Lines.Add('    LF_PrepareClient("ipc:' + AppName + '", nullptr);');
    Lines.Add('');
    Lines.Add('    if (LF_PrepareDone() != 1) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareDone failed\n");');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Per-API test call
    // -------------------------------------------------------------------------
    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    std::printf("[WARN] No APIs were generated for this unit.\n");');
      Lines.Add('    // Nothing to call.');
    end
    else
    begin
      Lines.Add('    std::printf("[OK] Connected. Calling %d API(s).\n", '
        + umlIntToStr(Length(SupportedFuncs)).Text + ');');
      Lines.Add('');

      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := MakeApiName(f.Name);
        Args := BuildCallArgs(f.Params);

        Lines.Add('    // ---- ' + ApiName + ' ----');
        Lines.Add('    try {');
        if f.IsFunction then
        begin
          Lines.Add('        auto _r = ' + NsName + '::' + ApiName
            + '(' + Args + ');');
          Lines.Add('        std::cout << "' + ApiName
            + ' = " << _r << "\n";');
        end
        else
        begin
          Lines.Add('        ' + NsName + '::' + ApiName
            + '(' + Args + ');');
          Lines.Add('        std::cout << "' + ApiName + ' OK\n";');
        end;
        Lines.Add('    } catch (const std::exception& _e) {');
        Lines.Add('        std::cerr << "' + ApiName
          + ' failed: " << _e.what() << "\n";');
        Lines.Add('    }');
        Lines.Add('');
      end;
    end;

    // -------------------------------------------------------------------------
    // Shutdown
    // -------------------------------------------------------------------------
    Lines.Add('    std::printf("[OK] Client test complete.\n");');
    Lines.Add('');
    Lines.Add('    LF_ExitMainThread();');
    Lines.Add('    LF_Shutdown();');
    Lines.Add('    LF_FreeLibrary();');
    Lines.Add('    return 0;');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test program.',
      [Lines.Count]));
  finally
    // Lines is returned to the caller; not freed here.
  end;
end;

end.
