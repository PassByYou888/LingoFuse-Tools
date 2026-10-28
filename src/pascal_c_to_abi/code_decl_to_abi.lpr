program code_decl_to_abi;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

{$apptype console}

uses
  mimalloc4p,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, Forms, lingofuse_import, code_decl_to_abi_registry, code_decl_to_abi_frm, code_decl_to_abi_cmdline, code_decl_to_abi_mcp_api_tool_provider_unit,
  pas_abi_service_generator_tool, pas_abi_call_generator_tool, pas_abi_test_generator_tool, py_abi_service_generator_tool, py_abi_call_generator_tool,
  cpp_abi_service_generator_tool, cpp_abi_call_generator_tool, cpp_abi_cmake_generator_tool, csharp_abi_service_generator_tool, csharp_abi_call_generator_tool,
  csharp_abi_test_generator_tool, py_abi_test_generator_tool, rust_abi_service_generator_tool, rust_abi_call_generator_tool, rust_abi_test_generator_tool,
  rust_abi_test_setup_generator_tool, go_abi_call_generator_tool, go_abi_service_generator_tool, go_abi_test_generator_tool, go_abi_test_setup_generator_tool,
  java_abi_service_generator_tool, java_abi_call_generator_tool, java_abi_test_generator_tool, java_abi_test_setup_generator_tool, nodejs_abi_service_generator_tool,
  nodejs_abi_call_generator_tool, nodejs_abi_test_generator_tool, nodejs_abi_test_setup_generator_tool, ts_abi_service_generator_tool, ts_abi_test_setup_generator_tool,
  ts_abi_call_generator_tool, ts_abi_test_generator_tool, erlang_abi_service_generator_tool, erlang_abi_call_generator_tool, erlang_abi_test_generator_tool, 
erlang_abi_test_setup_generator_tool, julia_abi_service_generator_tool, julia_abi_call_generator_tool, julia_abi_test_generator_tool, julia_abi_test_setup_generator_tool, 
zig_abi_service_generator_tool, zig_abi_call_generator_tool, zig_abi_test_generator_tool, zig_abi_test_setup_generator_tool, swift_abi_service_generator_tool, 
swift_abi_call_generator_tool, swift_abi_test_generator_tool, swift_abi_test_setup_generator_tool, ruby_abi_service_generator_tool, ruby_abi_test_setup_generator_tool, 
ruby_abi_call_generator_tool, ruby_abi_test_generator_tool, fortran_abi_service_generator_tool, fortran_abi_call_generator_tool, fortran_abi_test_generator_tool, 
fortran_abi_test_setup_generator_tool, dart_abi_service_generator_tool, dart_abi_call_generator_tool, dart_abi_test_generator_tool, dart_abi_test_setup_generator_tool, 
R_abi_service_generator_tool, R_abi_call_generator_tool, R_abi_test_generator_tool, R_abi_test_setup_generator_tool;

  {$R *.res}

begin
  try
    if not Process_CommandLine then
    begin
      exitCode := CommandLine_ExitCode;
      exit;
    end;
    RequireDerivedFormResource := True;
    Application.Scaled := True;
    {$PUSH}
    {$WARN 5044 OFF}
    Application.MainFormOnTaskbar := True;
    {$POP}
    Application.Initialize;
    Application.CreateForm(Tcode_decl_to_abi_form, code_decl_to_abi_form);
    Application.Run;
  finally
    LF_Shutdown();
  end;
end.
