unit cpp_abi_cmake_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICmakeScript(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABIServiceTestProgram(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestProgram(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

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

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Cpp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'std::int32_t'
  else if T.Same('int64') then
    Result := 'std::int64_t'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'std::uint32_t'
  else if T.Same('word') then
    Result := 'std::uint16_t'
  else if T.Same('smallint') then
    Result := 'std::int16_t'
  else if T.Same('byte') then
    Result := 'std::uint8_t'
  else if T.Same('uint64') then
    Result := 'std::uint64_t'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'std::string'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Cpp_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

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

function CppStrLit(const S: TP_String): TP_String;
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
    else
      Result.Append(c);
  end;
  Result.Append('"');
end;

function BuildArgValues(const Params: TParamArray): TP_String;
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
    Lines.Add('cmake_minimum_required(VERSION 3.15)');
    Lines.Add('');
    Lines.Add('project(' + NsName + ' LANGUAGES C CXX)');
    Lines.Add('');
    Lines.Add('set(CMAKE_CXX_STANDARD 17)');
    Lines.Add('set(CMAKE_CXX_STANDARD_REQUIRED ON)');
    Lines.Add('set(CMAKE_CXX_EXTENSIONS OFF)');
    Lines.Add('');
    Lines.Add('if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)');
    Lines.Add('    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('find_package(Threads REQUIRED)');
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
    Lines.Add('    message(FATAL_ERROR "LingoFuse.h not found under ${LINGOFUSE_CPP_DIR}.")');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('if(NOT EXISTS "${LINGOFUSE_CPP_DIR}/LingoFuse.c")');
    Lines.Add('    message(FATAL_ERROR "LingoFuse.c not found under ${LINGOFUSE_CPP_DIR}.")');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('add_library(lingofuse_c_wrapper STATIC');
    Lines.Add('    "${LINGOFUSE_CPP_DIR}/LingoFuse.c")');
    Lines.Add('target_include_directories(lingofuse_c_wrapper PUBLIC');
    Lines.Add('    "${LINGOFUSE_CPP_DIR}")');
    Lines.Add('if(NOT WIN32)');
    Lines.Add('    target_link_libraries(lingofuse_c_wrapper PUBLIC ${CMAKE_DL_LIBS})');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('set(_lf_common_compile_opts "")');
    Lines.Add('if(MSVC)');
    Lines.Add('    list(APPEND _lf_common_compile_opts /utf-8 /EHsc /W4)');
    Lines.Add('else()');
    Lines.Add('    list(APPEND _lf_common_compile_opts -Wall -Wextra -pthread)');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('function(lingofuse_apply_target_defaults tgt)');
    Lines.Add('    target_include_directories(${tgt} PUBLIC');
    Lines.Add('        "${CMAKE_CURRENT_SOURCE_DIR}"');
    Lines.Add('        "${LINGOFUSE_CPP_DIR}")');
    Lines.Add('    target_link_libraries(${tgt} PUBLIC lingofuse_c_wrapper Threads::Threads)');
    Lines.Add('    target_compile_options(${tgt} PRIVATE ${_lf_common_compile_opts})');
    Lines.Add('endfunction()');
    Lines.Add('');
    Lines.Add('if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_service.cpp")');
    Lines.Add('    add_library(' + NsName + '_service STATIC');
    Lines.Add('        ' + NormalizedUnit + '_abi_service.cpp)');
    Lines.Add('    lingofuse_apply_target_defaults(' + NsName + '_service)');
    Lines.Add('    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_service_main.cpp")');
    Lines.Add('        add_executable(' + NsName + '_service_test');
    Lines.Add('            ' + NormalizedUnit + '_abi_service_main.cpp)');
    Lines.Add('        lingofuse_apply_target_defaults(' + NsName + '_service_test)');
    Lines.Add('        target_link_libraries(' + NsName + '_service_test PRIVATE');
    Lines.Add('            ' + NsName + '_service)');
    Lines.Add('    endif()');
    Lines.Add('endif()');
    Lines.Add('');
    Lines.Add('if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_call.cpp")');
    Lines.Add('    add_library(' + NsName + '_call STATIC');
    Lines.Add('        ' + NormalizedUnit + '_abi_call.cpp)');
    Lines.Add('    lingofuse_apply_target_defaults(' + NsName + '_call)');
    Lines.Add('    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/' + NormalizedUnit + '_abi_call_main.cpp")');
    Lines.Add('        add_executable(' + NsName + '_call_test');
    Lines.Add('            ' + NormalizedUnit + '_abi_call_main.cpp)');
    Lines.Add('        lingofuse_apply_target_defaults(' + NsName + '_call_test)');
    Lines.Add('        target_link_libraries(' + NsName + '_call_test PRIVATE');
    Lines.Add('            ' + NsName + '_call)');
    Lines.Add('    endif()');
    Lines.Add('endif()');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the CMake script.', [Lines.Count]));
  finally
  end;
end;

procedure EmitRuntimeLoadPrelude(Lines: TPascalStringList);
begin
  Lines.Add('    if (LF_LoadLibrary() != 1) {');
  Lines.Add('        std::fprintf(stderr,');
  Lines.Add('            "[FATAL] LF_LoadLibrary failed.\n"');
  Lines.Add('            "        Place LingoFuse64.dll / liblingofuse.so / liblingofuse.dylib\n"');
  Lines.Add('            "        next to the executable, or on the OS loader search path.\n");');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('    std::printf("[OK] LingoFuse runtime loaded.\n");');
  Lines.Add('');
end;

function GenerateABIServiceTestProgram(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, NsName, AppName, P2PName: TP_String;
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
  P2PName := NormalizedUnit + '_service_test_p2p';

  Log(PFormat('Generating C++ ABI service test program for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service test program references %d APIs', [Length(SupportedFuncs)]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('#include "' + NormalizedUnit + '_abi_service.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <array>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstdio>');
    Lines.Add('#include <cstdlib>');
    Lines.Add('#include <cstring>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('constexpr const char* kP2PName = ' + CppStrLit(P2PName) + ';');
    Lines.Add('');
    Lines.Add('void LF_CDECL Cb_WhoAmI(void* _Trigger, void* _In, void* _Out) {');
    Lines.Add('    (void)_Trigger;');
    Lines.Add('    lingofuse::DataHandle out_h(static_cast<TDataHnd>(_Out), false);');
    Lines.Add('    try {');
    Lines.Add('        std::array<std::uint8_t, 32> uid{};');
    Lines.Add('        std::string p2p;');
    Lines.Add('        try {');
    Lines.Add('            lingofuse::DataHandle in_h(static_cast<TDataHnd>(_In), false);');
    Lines.Add('            uid = in_h.getP2PUid();');
    Lines.Add('            p2p = in_h.getP2PName();');
    Lines.Add('        } catch (...) {}');
    Lines.Add('        std::uint8_t status = 0x00;');
    Lines.Add('        out_h.write(status);');
    Lines.Add('        out_h.writeRaw(uid.data(), 32);');
    Lines.Add('        out_h.write(p2p);');
    Lines.Add('        std::printf("[SERVICE] whoami: p2p=%s\\n", p2p.c_str());');
    Lines.Add('    } catch (...) {}');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('void LF_CDECL Cb_AskServiceCallMe(void* _Trigger, void* _In) {');
    Lines.Add('    (void)_Trigger;');
    Lines.Add('    const TP2P_UID* uid_ptr = LF_Get_P2P_UID(static_cast<TDataHnd>(_In));');
    Lines.Add('    if (uid_ptr == nullptr) {');
    Lines.Add('        std::fprintf(stderr, "[SERVICE] ask_call_me: no UID in input\n");');
    Lines.Add('        return;');
    Lines.Add('    }');
    Lines.Add('    TP2P_UID client_uid = *uid_ptr;');
    Lines.Add('');
    Lines.Add('    TDataHnd req = LF_CreateData("LF_TEST_REPORT_SERVICE_IDENTITY");');
    Lines.Add('    if (req == nullptr) return;');
    Lines.Add('    try {');
    Lines.Add('        lingofuse::io::write_string(req, std::string("service initiates call"));');
    Lines.Add('        std::printf("[SERVICE] ask_call_me: calling client via UID\n");');
    Lines.Add('        TDataHnd res = LF_UID_Call(client_uid, req, 5000);');
    Lines.Add('        if (res != nullptr) {');
    Lines.Add('            std::printf("[SERVICE] ask_call_me: client responded ok\n");');
    Lines.Add('            LF_FreeData(res);');
    Lines.Add('        } else {');
    Lines.Add('            std::printf("[SERVICE] ask_call_me: UID call returned nil (timeout)\n");');
    Lines.Add('        }');
    Lines.Add('    } catch (...) {}');
    Lines.Add('    LF_FreeData(req);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('} // namespace');
    Lines.Add('');
    Lines.Add('int main() {');
    Lines.Add('    std::printf("=== ' + UnitName.Text + ' ABI service test ===\n");');
    Lines.Add('');
    EmitRuntimeLoadPrelude(Lines);
    Lines.Add('    LF_ResetPrepare();');
    Lines.Add('    LF_Set_Opt_Quiet(1);');
    Lines.Add('    LF_Set_Opt_ConsoleOutput(1);');
    Lines.Add('    LF_PrepareService("ipc:' + AppName + '", "ipc:' + AppName + '");');
    Lines.Add('');
    Lines.Add('    TAppHnd app = ' + NsName + '::Create_And_Register_ABI_App();');
    Lines.Add('    if (app == nullptr) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] Create_And_Register_ABI_App failed\n");');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    LF_RegisterCall(app, "LF_TEST_WHOAMI",');
    Lines.Add('        "service-side whoami helper", nullptr, &Cb_WhoAmI);');
    Lines.Add('    LF_RegisterNotify(app, "LF_TEST_ASK_SERVICE_CALL_ME",');
    Lines.Add('        "ask service to call back client", nullptr, &Cb_AskServiceCallMe);');
    Lines.Add('');
    Lines.Add('    LF_Set_Opt_P2P_Name(kP2PName);');
    Lines.Add('    ' + NsName + '::Register_All_P2P_ABI_APIs();');
    Lines.Add('    LF_Register_P2P_Call("LF_TEST_WHOAMI",');
    Lines.Add('        "service-side whoami helper", nullptr, &Cb_WhoAmI);');
    Lines.Add('    LF_Register_P2P_Notify("LF_TEST_ASK_SERVICE_CALL_ME",');
    Lines.Add('        "ask service to call back client", nullptr, &Cb_AskServiceCallMe);');
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
    Lines.Add('    std::printf("[OK] Service ready on ipc:%s.\n", "' + AppName + '");');
    Lines.Add('    std::printf("[OK] Registered %d API(s).\n", ' +
      umlIntToStr(Length(SupportedFuncs)).Text + ');');
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
    Log(PFormat('Generated %d lines for the service test program.', [Lines.Count]));
  finally
  end;
end;

procedure EmitCallTestPrelude(Lines: TPascalStringList);
begin
  Lines.Add('#include <array>');
  Lines.Add('#include <chrono>');
  Lines.Add('#include <condition_variable>');
  Lines.Add('#include <cstdint>');
  Lines.Add('#include <cstdio>');
  Lines.Add('#include <cstdlib>');
  Lines.Add('#include <cstring>');
  Lines.Add('#include <functional>');
  Lines.Add('#include <iostream>');
  Lines.Add('#include <memory>');
  Lines.Add('#include <mutex>');
  Lines.Add('#include <string>');
  Lines.Add('#include <thread>');
  Lines.Add('#include <type_traits>');
  Lines.Add('');
  Lines.Add('namespace {');
  Lines.Add('');
  Lines.Add('template <typename T>');
  Lines.Add('bool try_read_abi_scalar(lingofuse::DataHandle& h, T& out, std::string& err) {');
  Lines.Add('    std::uint8_t status = 0;');
  Lines.Add('    if (!h.read(status)) { err = "truncated status"; return false; }');
  Lines.Add('    if (status != 0) { try { h.read(err); } catch (...) {} return false; }');
  Lines.Add('    if (!h.read(out)) { err = "truncated result"; return false; }');
  Lines.Add('    return true;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('inline bool try_read_abi_string(lingofuse::DataHandle& h, std::string& out, std::string& err) {');
  Lines.Add('    std::uint8_t status = 0;');
  Lines.Add('    if (!h.read(status)) { err = "truncated status"; return false; }');
  Lines.Add('    if (status != 0) { try { h.read(err); } catch (...) {} return false; }');
  Lines.Add('    if (!h.read(out)) { err = "truncated result"; return false; }');
  Lines.Add('    return true;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('inline bool try_read_abi_void(lingofuse::DataHandle& h, std::string& err) {');
  Lines.Add('    std::uint8_t status = 0;');
  Lines.Add('    if (!h.read(status)) { err = "truncated status"; return false; }');
  Lines.Add('    if (status != 0) { try { h.read(err); } catch (...) {} return false; }');
  Lines.Add('    return true;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('template <typename T>');
  Lines.Add('class SyncBox {');
  Lines.Add('public:');
  Lines.Add('    void set(T value) {');
  Lines.Add('        std::lock_guard<std::mutex> lk(m_);');
  Lines.Add('        value_ = std::move(value);');
  Lines.Add('        ok_ = true;');
  Lines.Add('        done_ = true;');
  Lines.Add('        cv_.notify_all();');
  Lines.Add('    }');
  Lines.Add('    void set_error(std::string msg) {');
  Lines.Add('        std::lock_guard<std::mutex> lk(m_);');
  Lines.Add('        error_ = std::move(msg);');
  Lines.Add('        ok_ = false;');
  Lines.Add('        done_ = true;');
  Lines.Add('        cv_.notify_all();');
  Lines.Add('    }');
  Lines.Add('    bool wait(int timeout_ms) {');
  Lines.Add('        std::unique_lock<std::mutex> lk(m_);');
  Lines.Add('        return cv_.wait_for(lk, std::chrono::milliseconds(timeout_ms),');
  Lines.Add('                             [this] { return done_; });');
  Lines.Add('    }');
  Lines.Add('    bool ok() const { return ok_; }');
  Lines.Add('    const T& value() const { return value_; }');
  Lines.Add('    const std::string& error() const { return error_; }');
  Lines.Add('    void on_scalar_result(lingofuse::AsyncResult& r) {');
  Lines.Add('        if (!r.ok()) { set_error(r.error()); return; }');
  Lines.Add('        auto& h = r.handle();');
  Lines.Add('        h.seek(0);');
  Lines.Add('        T v{};');
  Lines.Add('        std::string err;');
  Lines.Add('        if (try_read_abi_scalar<T>(h, v, err)) set(v);');
  Lines.Add('        else set_error(err);');
  Lines.Add('    }');
  Lines.Add('    void on_string_result(lingofuse::AsyncResult& r) {');
  Lines.Add('        if (!r.ok()) { set_error(r.error()); return; }');
  Lines.Add('        auto& h = r.handle();');
  Lines.Add('        h.seek(0);');
  Lines.Add('        std::string v;');
  Lines.Add('        std::string err;');
  Lines.Add('        if (try_read_abi_string(h, v, err)) set(std::move(v));');
  Lines.Add('        else set_error(err);');
  Lines.Add('    }');
  Lines.Add('private:');
  Lines.Add('    std::mutex m_;');
  Lines.Add('    std::condition_variable cv_;');
  Lines.Add('    bool done_ = false;');
  Lines.Add('    bool ok_ = false;');
  Lines.Add('    T value_{};');
  Lines.Add('    std::string error_;');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('struct VoidBox {');
  Lines.Add('    void set() {');
  Lines.Add('        std::lock_guard<std::mutex> lk(m_);');
  Lines.Add('        ok_ = true;');
  Lines.Add('        done_ = true;');
  Lines.Add('        cv_.notify_all();');
  Lines.Add('    }');
  Lines.Add('    void set_error(std::string msg) {');
  Lines.Add('        std::lock_guard<std::mutex> lk(m_);');
  Lines.Add('        error_ = std::move(msg);');
  Lines.Add('        ok_ = false;');
  Lines.Add('        done_ = true;');
  Lines.Add('        cv_.notify_all();');
  Lines.Add('    }');
  Lines.Add('    bool wait(int timeout_ms) {');
  Lines.Add('        std::unique_lock<std::mutex> lk(m_);');
  Lines.Add('        return cv_.wait_for(lk, std::chrono::milliseconds(timeout_ms),');
  Lines.Add('                             [this] { return done_; });');
  Lines.Add('    }');
  Lines.Add('    bool ok() const { return ok_; }');
  Lines.Add('    const std::string& error() const { return error_; }');
  Lines.Add('    void on_void_result(lingofuse::AsyncResult& r) {');
  Lines.Add('        if (!r.ok()) { set_error(r.error()); return; }');
  Lines.Add('        auto& h = r.handle();');
  Lines.Add('        h.seek(0);');
  Lines.Add('        std::string err;');
  Lines.Add('        if (try_read_abi_void(h, err)) set();');
  Lines.Add('        else set_error(err);');
  Lines.Add('    }');
  Lines.Add('private:');
  Lines.Add('    std::mutex m_;');
  Lines.Add('    std::condition_variable cv_;');
  Lines.Add('    bool done_ = false;');
  Lines.Add('    bool ok_ = false;');
  Lines.Add('    std::string error_;');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('template <typename RetT, typename Invoker>');
  Lines.Add('void async_test_scalar(const std::string& label, Invoker&& invoker, int& pass, int& fail) {');
  Lines.Add('    auto box = std::make_shared<SyncBox<RetT>>();');
  Lines.Add('    try {');
  Lines.Add('        invoker([box](lingofuse::AsyncResult r) { box->on_scalar_result(r); });');
  Lines.Add('    } catch (const std::exception& e) {');
  Lines.Add('        std::cerr << "[FAIL] " << label << " -- dispatch: " << e.what() << "\n";');
  Lines.Add('        ++fail;');
  Lines.Add('        return;');
  Lines.Add('    }');
  Lines.Add('    if (!box->wait(5000)) { std::cerr << "[FAIL] " << label << " -- timeout\n"; ++fail; return; }');
  Lines.Add('    if (!box->ok()) { std::cerr << "[FAIL] " << label << " -- " << box->error() << "\n"; ++fail; return; }');
  Lines.Add('    std::cout << "[PASS] " << label << "\n";');
  Lines.Add('    ++pass;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('template <typename Invoker>');
  Lines.Add('void async_test_string(const std::string& label, Invoker&& invoker, int& pass, int& fail) {');
  Lines.Add('    auto box = std::make_shared<SyncBox<std::string>>();');
  Lines.Add('    try {');
  Lines.Add('        invoker([box](lingofuse::AsyncResult r) { box->on_string_result(r); });');
  Lines.Add('    } catch (const std::exception& e) {');
  Lines.Add('        std::cerr << "[FAIL] " << label << " -- dispatch: " << e.what() << "\n";');
  Lines.Add('        ++fail;');
  Lines.Add('        return;');
  Lines.Add('    }');
  Lines.Add('    if (!box->wait(5000)) { std::cerr << "[FAIL] " << label << " -- timeout\n"; ++fail; return; }');
  Lines.Add('    if (!box->ok()) { std::cerr << "[FAIL] " << label << " -- " << box->error() << "\n"; ++fail; return; }');
  Lines.Add('    std::cout << "[PASS] " << label << "\n";');
  Lines.Add('    ++pass;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('inline void async_test_void(const std::string& label,');
  Lines.Add('                            std::function<void(std::function<void(lingofuse::AsyncResult)>)> invoker,');
  Lines.Add('                            int& pass, int& fail) {');
  Lines.Add('    auto box = std::make_shared<VoidBox>();');
  Lines.Add('    try {');
  Lines.Add('        invoker([box](lingofuse::AsyncResult r) { box->on_void_result(r); });');
  Lines.Add('    } catch (const std::exception& e) {');
  Lines.Add('        std::cerr << "[FAIL] " << label << " -- dispatch: " << e.what() << "\n";');
  Lines.Add('        ++fail;');
  Lines.Add('        return;');
  Lines.Add('    }');
  Lines.Add('    if (!box->wait(5000)) { std::cerr << "[FAIL] " << label << " -- timeout\n"; ++fail; return; }');
  Lines.Add('    if (!box->ok()) { std::cerr << "[FAIL] " << label << " -- " << box->error() << "\n"; ++fail; return; }');
  Lines.Add('    std::cout << "[PASS] " << label << "\n";');
  Lines.Add('    ++pass;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('std::array<std::uint8_t, 32> g_service_uid{};');
  Lines.Add('bool g_has_service_uid = false;');
  Lines.Add('std::string g_service_p2p;');
  Lines.Add('bool g_service_called_me = false;');
  Lines.Add('');
  Lines.Add('} // namespace');
  Lines.Add('');
end;

procedure EmitCallTestCallbacksAndProbes(Lines: TPascalStringList; const NsName, AppName, P2PName: TP_String);
begin
  Lines.Add('namespace {');
  Lines.Add('');
  Lines.Add('constexpr const char* kTargetApp = ' + CppStrLit(AppName) + ';');
  Lines.Add('constexpr const char* kTargetP2P = ' + CppStrLit(P2PName) + ';');
  Lines.Add('');
  Lines.Add('void LF_CDECL Cb_ReportServiceIdentity(void* _Trigger, void* _In, void* _Out) {');
  Lines.Add('    (void)_Trigger;');
  Lines.Add('    lingofuse::DataHandle in_h(static_cast<TDataHnd>(_In), false);');
  Lines.Add('    lingofuse::DataHandle out_h(static_cast<TDataHnd>(_Out), false);');
  Lines.Add('    try {');
  Lines.Add('        g_service_uid = in_h.getP2PUid();');
  Lines.Add('        g_service_p2p = in_h.getP2PName();');
  Lines.Add('        g_has_service_uid = true;');
  Lines.Add('        g_service_called_me = true;');
  Lines.Add('        std::string msg;');
  Lines.Add('        try { in_h.read(msg); } catch (...) {}');
  Lines.Add('        std::printf("[CLIENT] service called me: msg=%s\\n", msg.c_str());');
  Lines.Add('        lingofuse::io::write_string(out_h.get(), std::string("identity received"));');
  Lines.Add('    } catch (...) {}');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('bool Probe_Client_Identity() {');
  Lines.Add('    lingofuse::DataHandle param("LF_TEST_WHOAMI");');
  Lines.Add('    auto opt = lingofuse::tryCall(kTargetApp, param, 5000);');
  Lines.Add('    if (!opt) return false;');
  Lines.Add('    auto& h = *opt;');
  Lines.Add('    h.seek(0);');
  Lines.Add('    std::uint8_t status = 0;');
  Lines.Add('    if (!h.read(status) || status != 0) return false;');
  Lines.Add('    std::array<std::uint8_t, 32> uid{};');
  Lines.Add('    if (h.readRaw(uid.data(), 32) != 32) return false;');
  Lines.Add('    std::string p2p;');
  Lines.Add('    if (!h.read(p2p)) return false;');
  Lines.Add('    bool non_zero = false;');
  Lines.Add('    for (auto b : uid) if (b != 0) { non_zero = true; break; }');
  Lines.Add('    std::printf("[INFO] client UID = ");');
  Lines.Add('    for (auto b : uid) std::printf("%02X", b);');
  Lines.Add('    std::printf("\n");');
  Lines.Add('    std::printf("[INFO] client P2P = %s\n", p2p.c_str());');
  Lines.Add('    return non_zero;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('bool Test_ServiceInitiatesCall() {');
  Lines.Add('    g_service_called_me = false;');
  Lines.Add('    g_has_service_uid = false;');
  Lines.Add('    g_service_uid.fill(0);');
  Lines.Add('    g_service_p2p.clear();');
  Lines.Add('');
  Lines.Add('    lingofuse::DataHandle param("LF_TEST_ASK_SERVICE_CALL_ME");');
  Lines.Add('    lingofuse::notify(kTargetApp, param);');
  Lines.Add('');
  Lines.Add('    for (int i = 0; i < 1000; ++i) {');
  Lines.Add('        if (g_service_called_me) break;');
  Lines.Add('        std::this_thread::sleep_for(std::chrono::milliseconds(10));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (!g_service_called_me) return false;');
  Lines.Add('    if (!g_has_service_uid) return false;');
  Lines.Add('    std::printf("[INFO] service UID = ");');
  Lines.Add('    for (auto b : g_service_uid) std::printf("%02X", b);');
  Lines.Add('    std::printf("\n");');
  Lines.Add('    std::printf("[INFO] service P2P = %s\n", g_service_p2p.c_str());');
  Lines.Add('    return true;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('} // namespace');
  Lines.Add('');
end;

procedure EmitAsyncTestCall(Lines: TPascalStringList;
  const Indent, Helper, Label_, CallExpr, Args, ExtraArg: TP_String);
var
  ParamStr: TP_String;
begin
  if ExtraArg = '' then
    ParamStr := Args
  else if Args = '' then
    ParamStr := ExtraArg
  else
    ParamStr := ExtraArg + ', ' + Args;

  Lines.Add(Indent + Helper + '("' + Label_ + '",');
  Lines.Add(Indent + '    [](std::function<void(lingofuse::AsyncResult)> cb) {');
  if ParamStr = '' then
    Lines.Add(Indent + '        ' + CallExpr + '(cb);')
  else
    Lines.Add(Indent + '        ' + CallExpr + '(' + ParamStr + ', cb);');
  Lines.Add(Indent + '    }, _pass, _fail);');
end;

procedure EmitFunctionTestBlock(Lines: TPascalStringList; const NsName, ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, Args, CallExpr: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  Args := BuildArgValues(F.Params);
  CallExpr := NsName + '::' + ApiName;

  Lines.Add('void Test_' + ApiName + '(int& _pass, int& _fail) {');

  Lines.Add('    try {');
  if Args = '' then
    Lines.Add('        auto _r = ' + CallExpr + '();')
  else
    Lines.Add('        auto _r = ' + CallExpr + '(' + Args + ');');
  Lines.Add('        std::cout << "[PASS] ' + ApiName + '(app call) = " << _r << "\n";');
  Lines.Add('        ++_pass;');
  Lines.Add('    } catch (const std::exception& e) {');
  Lines.Add('        std::cerr << "[FAIL] ' + ApiName + '(app call) -- " << e.what() << "\n";');
  Lines.Add('        ++_fail;');
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    if (g_has_service_uid) {');
  Lines.Add('        try {');
  if Args = '' then
    Lines.Add('            auto _r = ' + CallExpr + '_UID_Call(g_service_uid);')
  else
    Lines.Add('            auto _r = ' + CallExpr + '_UID_Call(g_service_uid, ' + Args + ');');
  Lines.Add('            std::cout << "[PASS] ' + ApiName + '(uid call) = " << _r << "\n";');
  Lines.Add('            ++_pass;');
  Lines.Add('        } catch (const std::exception& e) {');
  Lines.Add('            std::cerr << "[FAIL] ' + ApiName + '(uid call) -- " << e.what() << "\n";');
  Lines.Add('            ++_fail;');
  Lines.Add('        }');
  Lines.Add('    } else {');
  Lines.Add('        std::cout << "[SKIP] ' + ApiName + '(uid call) -- no service UID\n";');
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    try {');
  if Args = '' then
    Lines.Add('        auto _r = ' + CallExpr + '_P2PName_Call(kTargetP2P);')
  else
    Lines.Add('        auto _r = ' + CallExpr + '_P2PName_Call(kTargetP2P, ' + Args + ');');
  Lines.Add('        std::cout << "[PASS] ' + ApiName + '(p2pname call) = " << _r << "\n";');
  Lines.Add('        ++_pass;');
  Lines.Add('    } catch (const std::exception& e) {');
  Lines.Add('        std::cerr << "[FAIL] ' + ApiName + '(p2pname call) -- " << e.what() << "\n";');
  Lines.Add('        ++_fail;');
  Lines.Add('    }');
  Lines.Add('');

  if IsStringABIType(F.ReturnType) then
  begin
    EmitAsyncTestCall(Lines, '    ', 'async_test_string',
      ApiName + '(app async)', CallExpr + '_Async', Args, '');
    EmitAsyncTestCall(Lines, '    ', 'async_test_string',
      ApiName + '(app asyncSeq)', CallExpr + '_AsyncSequenced', Args, '');

    Lines.Add('    if (g_has_service_uid) {');
    EmitAsyncTestCall(Lines, '        ', 'async_test_string',
      ApiName + '(uid async)', CallExpr + '_UID_Async', Args, 'g_service_uid');
    EmitAsyncTestCall(Lines, '        ', 'async_test_string',
      ApiName + '(uid asyncSeq)', CallExpr + '_UID_AsyncSequenced', Args, 'g_service_uid');
    Lines.Add('    }');

    EmitAsyncTestCall(Lines, '    ', 'async_test_string',
      ApiName + '(p2pname async)', CallExpr + '_P2PName_Async', Args, 'kTargetP2P');
    EmitAsyncTestCall(Lines, '    ', 'async_test_string',
      ApiName + '(p2pname asyncSeq)', CallExpr + '_P2PName_AsyncSequenced', Args, 'kTargetP2P');
  end
  else
  begin
    EmitAsyncTestCall(Lines, '    ', 'async_test_scalar<' + RetType + '>',
      ApiName + '(app async)', CallExpr + '_Async', Args, '');
    EmitAsyncTestCall(Lines, '    ', 'async_test_scalar<' + RetType + '>',
      ApiName + '(app asyncSeq)', CallExpr + '_AsyncSequenced', Args, '');

    Lines.Add('    if (g_has_service_uid) {');
    EmitAsyncTestCall(Lines, '        ', 'async_test_scalar<' + RetType + '>',
      ApiName + '(uid async)', CallExpr + '_UID_Async', Args, 'g_service_uid');
    EmitAsyncTestCall(Lines, '        ', 'async_test_scalar<' + RetType + '>',
      ApiName + '(uid asyncSeq)', CallExpr + '_UID_AsyncSequenced', Args, 'g_service_uid');
    Lines.Add('    }');

    EmitAsyncTestCall(Lines, '    ', 'async_test_scalar<' + RetType + '>',
      ApiName + '(p2pname async)', CallExpr + '_P2PName_Async', Args, 'kTargetP2P');
    EmitAsyncTestCall(Lines, '    ', 'async_test_scalar<' + RetType + '>',
      ApiName + '(p2pname asyncSeq)', CallExpr + '_P2PName_AsyncSequenced', Args, 'kTargetP2P');
  end;

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNotifyTestCall(Lines: TPascalStringList;
  const Indent, Label_, CallExpr, Args, ExtraArg: TP_String);
var
  ParamStr: TP_String;
begin
  if ExtraArg = '' then
    ParamStr := Args
  else if Args = '' then
    ParamStr := ExtraArg
  else
    ParamStr := ExtraArg + ', ' + Args;

  Lines.Add(Indent + 'try {');
  if ParamStr = '' then
    Lines.Add(Indent + '    ' + CallExpr + '();')
  else
    Lines.Add(Indent + '    ' + CallExpr + '(' + ParamStr + ');');
  Lines.Add(Indent + '    std::cout << "[PASS] ' + Label_ + '\n";');
  Lines.Add(Indent + '    ++_pass;');
  Lines.Add(Indent + '} catch (const std::exception& e) {');
  Lines.Add(Indent + '    std::cerr << "[FAIL] ' + Label_ + ' -- " << e.what() << "\n";');
  Lines.Add(Indent + '    ++_fail;');
  Lines.Add(Indent + '}');
end;

procedure EmitProcedureTestBlock(Lines: TPascalStringList; const NsName, ApiName: TP_String; const F: TFunctionStructure);
var
  CallExpr, Args: TP_String;
begin
  CallExpr := NsName + '::' + ApiName;
  Args := BuildArgValues(F.Params);

  Lines.Add('void Test_' + ApiName + '(int& _pass, int& _fail) {');

  EmitNotifyTestCall(Lines, '    ', ApiName + '(app notify)',
    CallExpr, Args, '');
  Lines.Add('');

  EmitNotifyTestCall(Lines, '    ', ApiName + '(app seq notify)',
    CallExpr + '_SequencedNotify', Args, '');
  Lines.Add('');

  Lines.Add('    if (g_has_service_uid) {');
  EmitNotifyTestCall(Lines, '        ', ApiName + '(uid notify)',
    CallExpr + '_UID_Notify', Args, 'g_service_uid');
  EmitNotifyTestCall(Lines, '        ', ApiName + '(uid seq notify)',
    CallExpr + '_UID_SequencedNotify', Args, 'g_service_uid');
  Lines.Add('    }');
  Lines.Add('');

  EmitNotifyTestCall(Lines, '    ', ApiName + '(p2pname notify)',
    CallExpr + '_P2PName_Notify', Args, 'kTargetP2P');
  Lines.Add('');

  EmitNotifyTestCall(Lines, '    ', ApiName + '(p2pname seq notify)',
    CallExpr + '_P2PName_SequencedNotify', Args, 'kTargetP2P');
  Lines.Add('');

  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallTestProgram(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, P2PName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
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
  P2PName := NormalizedUnit + '_service_test_p2p';

  Log(PFormat('Generating C++ ABI call test program for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call test program exercises %d APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#include "' + NormalizedUnit + '_abi_call.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');

    EmitCallTestPrelude(Lines);
    EmitCallTestCallbacksAndProbes(Lines, NsName, AppName, P2PName);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      if F.IsFunction then
        EmitFunctionTestBlock(Lines, NsName, ApiName, F)
      else
        EmitProcedureTestBlock(Lines, NsName, ApiName, F);
    end;

    Lines.Add('int main() {');
    Lines.Add('    std::printf("=== ' + UnitName.Text + ' ABI client test ===\n");');
    Lines.Add('');
    EmitRuntimeLoadPrelude(Lines);
    Lines.Add('    LF_ResetPrepare();');
    Lines.Add('    LF_Set_Opt_Quiet(1);');
    Lines.Add('    LF_Set_Opt_ConsoleOutput(1);');
    Lines.Add('    ' + NsName + '::ABI_TargetApp = ' + CppStrLit(AppName) + ';');
    Lines.Add('    ' + NsName + '::ABI_Timeout = 5000;');
    Lines.Add('');
    Lines.Add('    TAppHnd client_app = LF_CreateApp("LF_TEST_CLIENT_SELF",');
    Lines.Add('        "client test app");');
    Lines.Add('    if (client_app == nullptr) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] LF_CreateApp failed\n");');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    LF_RegisterCall(client_app, "LF_TEST_REPORT_SERVICE_IDENTITY",');
    Lines.Add('        "report service identity", nullptr, &Cb_ReportServiceIdentity);');
    Lines.Add('');
    Lines.Add('    if (LF_PrepareClient("ipc:' + AppName + '", client_app) == -1) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareClient failed\n");');
    Lines.Add('        LF_FreeApp(client_app);');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (LF_PrepareDone() != 1) {');
    Lines.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareDone failed\n");');
    Lines.Add('        LF_ExitMainThread();');
    Lines.Add('        LF_FreeApp(client_app);');
    Lines.Add('        LF_Shutdown();');
    Lines.Add('        LF_FreeLibrary();');
    Lines.Add('        return 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std::printf("[OK] Client online.\n");');
    Lines.Add('');
    Lines.Add('    if (Probe_Client_Identity()) {');
    Lines.Add('        std::printf("[OK] client identity probe\n");');
    Lines.Add('    } else {');
    Lines.Add('        std::printf("[WARN] whoami failed, UID tests will be skipped\n");');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (Test_ServiceInitiatesCall()) {');
    Lines.Add('        std::printf("[OK] service-initiated call\n");');
    Lines.Add('    } else {');
    Lines.Add('        std::printf("[FAIL] service-initiated call -- timeout or no UID\n");');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    int _pass = 0;');
    Lines.Add('    int _fail = 0;');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      Lines.Add('    Test_' + ApiName + '(_pass, _fail);');
    end;

    Lines.Add('');
    Lines.Add('    std::printf("\n=== Summary ===\n");');
    Lines.Add('    std::printf("Pass: %d\n", _pass);');
    Lines.Add('    std::printf("Fail: %d\n", _fail);');
    Lines.Add('');
    Lines.Add('    LF_ExitMainThread();');
    Lines.Add('    LF_FreeApp(client_app);');
    Lines.Add('    LF_Shutdown();');
    Lines.Add('    LF_FreeLibrary();');
    Lines.Add('');
    Lines.Add('    std::printf("[OK] Client test complete.\n");');
    Lines.Add('    return (_fail == 0) ? 0 : 2;');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test program.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'cpp',
    'CMakeLists.txt',
    gkProject,
    'CMake build script',
    @GenerateABICmakeScript);

  RegisterGenerator(
    'cpp',
    'xxx_abi_service_main.cpp',
    gkProject,
    'C++ service test program',
    @GenerateABIServiceTestProgram);

  RegisterGenerator(
    'cpp',
    'xxx_abi_call_main.cpp',
    gkProject,
    'C++ call test program',
    @GenerateABICallTestProgram);

end.
