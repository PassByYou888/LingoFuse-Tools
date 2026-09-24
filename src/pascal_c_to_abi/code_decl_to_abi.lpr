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
  Interfaces, // this includes the LCL widgetset
  Forms,
  lingofuse_import,
  code_decl_to_abi_frm,
  pas_abi_service_generator_tool,
  pas_abi_call_generator_tool,
  py_abi_service_generator_tool,
  py_abi_call_generator_tool,
  cpp_abi_service_generator_tool,
  cpp_abi_call_generator_tool,
  code_decl_to_abi_cmdline, code_decl_to_abi_mcp_api_tool_provider_unit;

  {$R *.res}

begin
  try
    if not Process_CommandLine then
    begin
      exitCode := CommandLine_ExitCode;
      exit;
    end;
    RequireDerivedFormResource := True;
  Application.Scaled:=True;
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
