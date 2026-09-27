unit cmake_for_cpp_mcp_generator_tool;

// cmake_for_cpp_mcp_generator_tool - CMake + test-program generator for the
// C++ MCP tool provider backend of code_decl_to_mcp.
//
// Given a TPascal_Func_Model, this unit produces two artefacts that turn
// the raw C++ MCP provider sources (emitted by cpp_mcp_generator_tool.pas)
// into a buildable, runnable project:
//
//   GenerateCMakeLists  ->  CMakeLists.txt
//   GenerateCPPTestMain ->  <unit>_tool_provider_test.cpp
//
// Inputs read from LINGOFUSE_CPP_DIR (a single external directory):
//
//   LingoFuse.h  - C ABI declarations
//   LingoFuse.c  - C ABI dynamic-loading wrapper (compiled by CMake)
//   json.hpp     - nlohmann/json single-header distribution
//
// Runtime-loading contract (enforced by LingoFuse.h and LingoFuse.c):
//
//   LingoFuse.c is a dynamic-loading wrapper. Every LF_* symbol is
//   resolved lazily at runtime. The host program MUST call
//   LF_LoadLibrary() BEFORE any other LF_* call, and LF_FreeLibrary()
//   AFTER LF_Shutdown().
//
//   Signatures:
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
//   Expected runtime file names:
//
//       Windows : LingoFuse64.dll (or LingoFuse32.dll)
//       Linux   : liblingofuse.so
//       macOS   : liblingofuse.dylib
//
//   There is no environment-variable override at the C ABI level.
//
// All comments and status messages emitted by this unit and by the
// generated files are in English.
//
// Author: LingoFuse-pasAgent project

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

{$IFDEF FPC}
  {$CODEPAGE UTF8}
{$ENDIF FPC}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

{* Generate the CMakeLists.txt build script. Caller owns the returned list. *}
function GenerateCMakeLists(Model: TPascal_Func_Model): TPascalStringList;

{* Generate the C++ test main program. Caller owns the returned list. *}
function GenerateCPPTestMain(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging helpers
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cmake_for_cpp_mcp_generator_tool] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cmake_for_cpp_mcp_generator_tool] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// Returns the base file name that code_decl_to_mcp_frm.pas uses when it
// saves the generated files. The GUI saves:
//
//   <UnitName>_tool_provider.hpp
//   <UnitName>_tool_provider.cpp
//   <UnitName>_tool_provider_cpp.md
//
// without transforming UnitName, so this helper appends the fixed suffix
// "_tool_provider" and returns the result verbatim.
function MakeSourceBaseName(const UnitName: TP_String): TP_String;
begin
  Result := UnitName + '_tool_provider';
end;

// Returns a name that is safe to use as a CMake target identifier.
// Every character outside [A-Za-z0-9_] is replaced with '_'.
function MakeTargetBaseName(const UnitName: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to UnitName.Len do
  begin
    c := UnitName[i];
    if ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
       ((c >= '0') and (c <= '9')) or (c = '_') then
      Result := Result + c
    else
      Result := Result + '_';
  end;
  if Result.Len = 0 then
    Result := 'tool';
end;

// -----------------------------------------------------------------------------
// EmitRuntimeLoadPrelude
//
// Emits the mandatory runtime-loading prelude. This block MUST appear
// before any other LF_* call in the generated test program.
//
// Contract enforced by LingoFuse.h:
//
//     int LF_LoadLibrary(void);
//
//   - No arguments. The wrapper searches the executable directory first,
//     then the OS default search path.
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

// =============================================================================
// SECTION 1 - CMakeLists.txt generator
// =============================================================================

function GenerateCMakeLists(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, SourceBase, TargetBase: TP_String;
  Lines: TPascalStringList;
begin
  Result := TPascalStringList.Create;
  Lines := Result;

  if Model = nil then
  begin
    Lines.Add('# CMake script generation skipped');
    Lines.Add('#');
    Lines.Add('# Reason: supplied TPascal_Func_Model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Lines.Add('# CMake script generation skipped');
    Lines.Add('#');
    Lines.Add('# Reason: Model.UnitName is empty.');
    Exit;
  end;

  SourceBase := MakeSourceBaseName(UnitName);
  TargetBase := MakeTargetBaseName(UnitName);

  Log(PFormat('GenerateCMakeLists: unit="%s" target="%s"',
    [UnitName.Text, TargetBase.Text]));

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('# Auto-generated by cmake_for_cpp_mcp_generator_tool.');
  Lines.Add('# Source model unit: ' + UnitName.Text + '.');
  Lines.Add('# Do not edit by hand unless you know what you are doing.');
  Lines.Add('#');
  Lines.Add('# This CMake script builds the C++ MCP tool provider emitted by');
  Lines.Add('# cpp_mcp_generator_tool, together with a runnable test program.');
  Lines.Add('#');
  Lines.Add('# Layout assumed by this script (all files in the same directory):');
  Lines.Add('#');
  Lines.Add('#   ' + SourceBase.Text + '.hpp');
  Lines.Add('#   ' + SourceBase.Text + '.cpp');
  Lines.Add('#   ' + SourceBase.Text + '_test.cpp');
  Lines.Add('#');
  Lines.Add('# The LingoFuse C/C++ interface directory (LINGOFUSE_CPP_DIR) must');
  Lines.Add('# contain:');
  Lines.Add('#');
  Lines.Add('#   LingoFuse.h    - C ABI declarations');
  Lines.Add('#   LingoFuse.c    - C ABI dynamic-loading wrapper (compiled by this script)');
  Lines.Add('#   json.hpp       - nlohmann/json single-header distribution');
  Lines.Add('#');
  Lines.Add('# Basic usage:');
  Lines.Add('#');
  Lines.Add('#   cmake -S . -B build -DLINGOFUSE_CPP_DIR=<interface-dir>');
  Lines.Add('#   cmake --build build --config Release');
  Lines.Add('#');
  Lines.Add('# Runtime library:');
  Lines.Add('#');
  Lines.Add('#   The generated test program calls LF_LoadLibrary() as its very');
  Lines.Add('#   first LF_* operation. LF_LoadLibrary() takes no arguments; the');
  Lines.Add('#   wrapper searches the executable directory first, then the OS');
  Lines.Add('#   default search path. Place the runtime (LingoFuse64.dll /');
  Lines.Add('#   liblingofuse.so / liblingofuse.dylib) either next to the test');
  Lines.Add('#   executable or somewhere already on the loader search path.');
  Lines.Add('#   This script does not copy or link the runtime.');
  Lines.Add('#');
  Lines.Add('# Targets produced:');
  Lines.Add('#');
  Lines.Add('#   lingofuse_c_wrapper              static library from LingoFuse.c');
  Lines.Add('#   ' + TargetBase.Text + '_tool_provider         static library from the provider .cpp');
  Lines.Add('#   ' + TargetBase.Text + '_tool_provider_test    executable from the test main.cpp');
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('');

  Lines.Add('cmake_minimum_required(VERSION 3.15)');
  Lines.Add('');
  Lines.Add('project(' + TargetBase.Text + '_tool_provider LANGUAGES C CXX)');
  Lines.Add('');

  // ---------------------------------------------------------------------------
  // Standard configuration
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Locate LINGOFUSE_CPP_DIR
  // ---------------------------------------------------------------------------
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('# Locate the LingoFuse C/C++ interface directory');
  Lines.Add('#');
  Lines.Add('# LINGOFUSE_CPP_DIR is the only external input the script needs.');
  Lines.Add('# It must contain LingoFuse.h, LingoFuse.c, and json.hpp.');
  Lines.Add('#');
  Lines.Add('# The script does not look for or link against the LingoFuse runtime');
  Lines.Add('# shared library (LingoFuse64.dll / liblingofuse.so /');
  Lines.Add('# liblingofuse.dylib). Loading the runtime is handled at program');
  Lines.Add('# startup by LF_LoadLibrary().');
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('if(NOT DEFINED LINGOFUSE_CPP_DIR AND DEFINED ENV{LINGOFUSE_CPP_DIR})');
  Lines.Add('    set(LINGOFUSE_CPP_DIR "$ENV{LINGOFUSE_CPP_DIR}" CACHE PATH');
  Lines.Add('        "Directory containing LingoFuse.h, LingoFuse.c, json.hpp")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('if(NOT DEFINED LINGOFUSE_CPP_DIR)');
  Lines.Add('    set(LINGOFUSE_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE PATH');
  Lines.Add('        "Directory containing LingoFuse.h, LingoFuse.c, json.hpp")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('foreach(_lf_required_file LingoFuse.h LingoFuse.c json.hpp)');
  Lines.Add('    if(NOT EXISTS "${LINGOFUSE_CPP_DIR}/${_lf_required_file}")');
  Lines.Add('        message(FATAL_ERROR');
  Lines.Add('            "Required file not found: ${LINGOFUSE_CPP_DIR}/${_lf_required_file}\n"');
  Lines.Add('            "Set LINGOFUSE_CPP_DIR to a directory that contains:\n"');
  Lines.Add('            "  - LingoFuse.h   (C ABI declarations)\n"');
  Lines.Add('            "  - LingoFuse.c   (dynamic-loading wrapper)\n"');
  Lines.Add('            "  - json.hpp      (nlohmann/json single-header)")');
  Lines.Add('    endif()');
  Lines.Add('endforeach()');
  Lines.Add('');

  // ---------------------------------------------------------------------------
  // LingoFuse C ABI wrapper
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Common compile options + helper function
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Provider static library
  // ---------------------------------------------------------------------------
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('# Provider library (from the generated provider .cpp)');
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + SourceBase.Text + '.cpp")');
  Lines.Add('    message(FATAL_ERROR');
  Lines.Add('        "Provider source not found: ' + SourceBase.Text + '.cpp\n"');
  Lines.Add('        "Place the generated provider files next to this CMakeLists.txt.")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('add_library(' + TargetBase.Text + '_tool_provider STATIC');
  Lines.Add('    ' + SourceBase.Text + '.cpp)');
  Lines.Add('lingofuse_apply_target_defaults(' + TargetBase.Text + '_tool_provider)');
  Lines.Add('');

  // ---------------------------------------------------------------------------
  // Test executable
  // ---------------------------------------------------------------------------
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('# Test executable (from the generated test main.cpp)');
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + SourceBase.Text + '_test.cpp")');
  Lines.Add('    message(FATAL_ERROR');
  Lines.Add('        "Test source not found: ' + SourceBase.Text + '_test.cpp\n"');
  Lines.Add('        "Place the generated test file next to this CMakeLists.txt.")');
  Lines.Add('endif()');
  Lines.Add('');
  Lines.Add('add_executable(' + TargetBase.Text + '_tool_provider_test');
  Lines.Add('    ' + SourceBase.Text + '_test.cpp)');
  Lines.Add('lingofuse_apply_target_defaults(' + TargetBase.Text + '_tool_provider_test)');
  Lines.Add('target_link_libraries(' + TargetBase.Text + '_tool_provider_test PRIVATE');
  Lines.Add('    ' + TargetBase.Text + '_tool_provider)');
  Lines.Add('');

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('# Summary');
  Lines.Add('#');
  Lines.Add('# Configuration is complete. Run `cmake --build build` to compile.');
  Lines.Add('#');
  Lines.Add('# The runtime shared library is not copied and no RPATH is set.');
  Lines.Add('# The generated test program calls LF_LoadLibrary() as its very');
  Lines.Add('# first LF_* operation. That function takes no arguments: the');
  Lines.Add('# wrapper searches the executable directory first, then the OS');
  Lines.Add('# default search path (PATH on Windows, LD_LIBRARY_PATH on Linux,');
  Lines.Add('# DYLD_LIBRARY_PATH on macOS). Place the runtime library');
  Lines.Add('# accordingly before running the test.');
  Lines.Add('#');
  Lines.Add('# Suggested run sequence:');
  Lines.Add('#   1. Start the beacon (pascal_agent_service.exe).');
  Lines.Add('#   2. Run ' + TargetBase.Text + '_tool_provider_test.');
  Lines.Add('#   3. From an MCP client, invoke one of the registered tools.');
  Lines.Add('# ---------------------------------------------------------------------------');
  Lines.Add('');

  Log(PFormat('GenerateCMakeLists: done, %d lines', [Lines.Count]));
end;

// =============================================================================
// SECTION 2 - C++ test main generator
// =============================================================================

function GenerateCPPTestMain(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, SourceBase, TargetBase: TP_String;
  Lines: TPascalStringList;
begin
  Result := TPascalStringList.Create;
  Lines := Result;

  if Model = nil then
  begin
    Lines.Add('// Test program generation skipped');
    Lines.Add('//');
    Lines.Add('// Reason: supplied TPascal_Func_Model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Lines.Add('// Test program generation skipped');
    Lines.Add('//');
    Lines.Add('// Reason: Model.UnitName is empty.');
    Exit;
  end;

  SourceBase := MakeSourceBaseName(UnitName);
  TargetBase := MakeTargetBaseName(UnitName);

  Log(PFormat('GenerateCPPTestMain: unit="%s" hpp="%s"',
    [UnitName.Text, SourceBase.Text + '.hpp']));

  // ---------------------------------------------------------------------------
  // File header
  // ---------------------------------------------------------------------------
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('// Auto-generated by cmake_for_cpp_mcp_generator_tool.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// Runnable test program for the generated C++ MCP tool provider.');
  Lines.Add('//');
  Lines.Add('// Build: see the accompanying CMakeLists.txt.');
  Lines.Add('//');
  Lines.Add('// What this program does:');
  Lines.Add('//   1. Load the LingoFuse runtime dynamic library via LF_LoadLibrary().');
  Lines.Add('//   2. Print the provider configuration (App name, endpoint, beacon,');
  Lines.Add('//      registration API, log API, debug flag).');
  Lines.Add('//   3. Call Execute_And_Reg_all() to:');
  Lines.Add('//         - create the LingoFuse App,');
  Lines.Add('//         - register every supported API as a Call API,');
  Lines.Add('//         - connect to the configured IPC endpoint,');
  Lines.Add('//         - advertise every API to the beacon as an MCP tool.');
  Lines.Add('//   4. Wait for the user to press Enter.');
  Lines.Add('//   5. Shut down cleanly: LF_ExitMainThread -> LF_Shutdown ->');
  Lines.Add('//      LF_FreeLibrary.');
  Lines.Add('//');
  Lines.Add('// It does NOT drive any API directly. After the "[OK] Provider is');
  Lines.Add('// ready" banner appears, exercise the tools from an external MCP');
  Lines.Add('// client (LM Studio / Claude Desktop / mcp_api_tool).');
  Lines.Add('//');
  Lines.Add('// Prerequisite: the beacon (pascal_agent_service.exe) must be running');
  Lines.Add('// on the configured IPC endpoint before this program is started.');
  Lines.Add('//');
  Lines.Add('// Runtime library location:');
  Lines.Add('//   LF_LoadLibrary() takes no arguments. Place LingoFuse64.dll /');
  Lines.Add('//   liblingofuse.so / liblingofuse.dylib either next to this');
  Lines.Add('//   executable or somewhere already on the loader search path');
  Lines.Add('//   (PATH / LD_LIBRARY_PATH / DYLD_LIBRARY_PATH).');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('#include "' + SourceBase.Text + '.hpp"');
  Lines.Add('');
  Lines.Add('#include <cstdio>');
  Lines.Add('#include <cstdlib>');
  Lines.Add('');
  Lines.Add('int main(int argc, char* argv[])');
  Lines.Add('{');
  Lines.Add('    (void)argc;');
  Lines.Add('    (void)argv;');
  Lines.Add('');
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    // Banner: print the effective provider configuration.');
  Lines.Add('    //');
  Lines.Add('    // The extern symbols below are defined by the generated provider');
  Lines.Add('    // implementation (' + SourceBase.Text + '.cpp) and declared in');
  Lines.Add('    // ' + SourceBase.Text + '.hpp.');
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    std::printf("=== %s - C++ MCP Tool Provider Test ===\n", MY_APP_NAME);');
  Lines.Add('    std::printf("Description  : %s\n", MY_APP_DESC);');
  Lines.Add('    std::printf("IPC endpoint : %s\n", IPC_ENDPOINT);');
  Lines.Add('    std::printf("Beacon app   : %s\n", BEACON_APP);');
  Lines.Add('    std::printf("Register API : %s\n", REGISTER_API);');
  Lines.Add('    std::printf("Log API      : %s\n", AGENT_LOG_API);');
  Lines.Add('    std::printf("Debug log    : %s\n", DEBUG_LOG ? "enabled" : "disabled");');
  Lines.Add('    std::printf("\n");');
  Lines.Add('    std::fflush(stdout);');
  Lines.Add('');

  // ---------------------------------------------------------------------------
  // Runtime loading prelude
  // ---------------------------------------------------------------------------
  EmitRuntimeLoadPrelude(Lines);

  // ---------------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------------
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    // Step 2: start the provider.');
  Lines.Add('    //');
  Lines.Add('    // Execute_And_Reg_all() is defined by the generated provider and');
  Lines.Add('    // performs the full startup sequence:');
  Lines.Add('    //   1. RegisterAPIs        create the App + register all Call APIs');
  Lines.Add('    //   2. LF_PrepareClient    connect to IPC_ENDPOINT');
  Lines.Add('    //   3. LF_PrepareDone      wait for readiness');
  Lines.Add('    //   4. RegisterTools       advertise every API to the beacon');
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    if (!Execute_And_Reg_all())');
  Lines.Add('    {');
  Lines.Add('        std::fprintf(stderr,');
  Lines.Add('            "\n[FATAL] Provider startup failed.\n"');
  Lines.Add('            "\nChecklist:\n"');
  Lines.Add('            "  1. Is the beacon (pascal_agent_service.exe) running?\n"');
  Lines.Add('            "  2. Is the endpoint ''%s'' reachable?\n"');
  Lines.Add('            "  3. Is the LingoFuse runtime library on the loader path?\n"');
  Lines.Add('            "  4. Was LF_LoadLibrary() called before any other LF_* call?\n",');
  Lines.Add('            IPC_ENDPOINT);');
  Lines.Add('        std::fflush(stderr);');
  Lines.Add('        LF_FreeLibrary();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    // Step 3: wait for the user.');
  Lines.Add('    //');
  Lines.Add('    // The three common ways to stop the program are all handled');
  Lines.Add('    // gracefully:');
  Lines.Add('    //   - pressing Enter');
  Lines.Add('    //   - sending EOF (Ctrl+D on Linux / macOS, Ctrl+Z then Enter on');
  Lines.Add('    //     Windows)');
  Lines.Add('    //   - sending a signal (Ctrl+C on any platform)');
  Lines.Add('    //');
  Lines.Add('    // std::getchar() returns EOF on input stream close, which is a');
  Lines.Add('    // normal shutdown trigger in this test program.');
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    std::printf("\n[OK] Provider is ready. All tools registered.\n");');
  Lines.Add('    std::printf("The MCP gateway can now discover and invoke these tools.\n");');
  Lines.Add('    std::printf("Press Enter to shut down.\n");');
  Lines.Add('    std::fflush(stdout);');
  Lines.Add('    {');
  Lines.Add('        const int c = std::getchar();');
  Lines.Add('        (void)c;');
  Lines.Add('    }');
  Lines.Add('');

  // ---------------------------------------------------------------------------
  // Shutdown
  // ---------------------------------------------------------------------------
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    // Step 4: shut down.');
  Lines.Add('    //');
  Lines.Add('    // Order matters:');
  Lines.Add('    //   1. LF_ExitMainThread() stops the simulated main thread so that');
  Lines.Add('    //      no further LingoFuse callback can fire.');
  Lines.Add('    //   2. LF_Shutdown() releases the global App pool and every');
  Lines.Add('    //      remaining DataHandle.');
  Lines.Add('    //   3. LF_FreeLibrary() unloads the runtime dynamic library and');
  Lines.Add('    //      clears every cached function pointer.');
  Lines.Add('    // ---------------------------------------------------------------------');
  Lines.Add('    std::printf("\nShutting down ...\n");');
  Lines.Add('    std::fflush(stdout);');
  Lines.Add('');
  Lines.Add('    LF_ExitMainThread();');
  Lines.Add('    LF_Shutdown();');
  Lines.Add('    LF_FreeLibrary();');
  Lines.Add('');
  Lines.Add('    std::printf("[OK] Shutdown complete.\n");');
  Lines.Add('    return 0;');
  Lines.Add('}');
  Lines.Add('');

  Log(PFormat('GenerateCPPTestMain: done, %d lines', [Lines.Count]));
end;

end.
