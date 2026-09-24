program code_decl_to_json_abi;

{$mode objfpc}{$H+}
{$apptype console}

uses
  mimalloc4p,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  lingofuse_import,
  code_decl_to_abi_json_frm,
  http_pas_abi_service_generator_tool,
  http_pas_abi_call_generator_tool,
  http_js_abi_call_generator_tool,
  http_py_abi_service_generator_tool,
  http_py_abi_call_generator_tool,
  http_cpp_abi_service_generator_tool,
  http_cpp_abi_call_generator_tool,
  code_decl_to_json_abi_mcp_api_tool_provider_unit,
  code_decl_to_json_abi_cmdline;

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
    Application.CreateForm(Tcode_decl_to_abi_json_form, code_decl_to_abi_json_form);
    Application.Run;
  finally
    LF_Shutdown;
  end;
end.
