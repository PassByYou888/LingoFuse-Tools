program code_decl_to_mcp;

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
  code_decl_to_mcp_frm,
  pas_mcp_generator_tool,
  py_mcp_generator_tool,
  cpp_mcp_generator_tool,
  code_decl_to_mcp_api_tool_provider_unit,
  code_decl_to_mcp_cmdline;

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
    Application.CreateForm(TCodeDeclToMcpForm, CodeDeclToMcpForm);
    Application.Run;
  finally
    LF_Shutdown();
  end;
end.
