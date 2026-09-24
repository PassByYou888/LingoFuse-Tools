unit code_decl_to_abi_mcp_api_tool_provider_unit;

{$ifdef FPC}
  {$mode delphi}
  {$MODESWITCH NestedProcVars}
  {$modeswitch advancedrecords}
  {$MODESWITCH NESTEDCOMMENTS}
  {$CODEPAGE UTF8}
{$endif}
{$H+}
{$R-}
{$I-}
{$Q-}
{$B-}

interface

uses
  SysUtils, Classes,
  lingofuse_import;

// ---- Exported global var ----
var
  MY_APP_NAME : string = 'code_decl_to_abi_mcp_api';
  MY_APP_DESC : string = 'Tool provider for unit code_decl_to_abi_mcp_api';
  IPC_ENDPOINT : string = 'ipc:agent';
  BEACON_APP : string = 'agent_main_app';
  REGISTER_API : string = 'register_agent';
  AGENT_LOG_API : string = 'agent_log';
  DEBUG_LOG : boolean = True;

// ---- Exported functions ----
{*
 * RegisterAPIs - Creates the LingoFuse application and registers all
 * generated Call APIs. Returns the application handle, or nil on failure.
 * The caller is responsible for freeing the handle with LF_FreeApp.
 *}
function RegisterAPIs: TAppHnd___;

{*
 * RegisterTools - Connects to the beacon, registers all APIs as tools
 * with JSON schemas, and returns True if all registrations succeeded.
 *}
function RegisterTools: Boolean;

{**
 * Execute_And_Reg_all - One-click startup and tool registration.
 *
 * Sequence:
 *   1. RegisterAPIs       : create App + register all Call APIs
 *   2. LF_PrepareClient   : connect to IPC_ENDPOINT with the App
 *   3. LF_PrepareDone     : wait until the client is ready
 *   4. RegisterTools      : advertise every tool to the beacon
 *
 * @return True when all four steps succeeded.
 *}
function Execute_And_Reg_all: Boolean;


function internal_call_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode(Source: string; Language: string): string;
function internal_call_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService(): string;
function internal_call_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall(): string;
function internal_call_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService(): string;
function internal_call_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall(): string;
function internal_call_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService(): string;
function internal_call_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall(): string;
function internal_call_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode(): string;
function internal_call_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme(): string;
function internal_call_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode(): string;
function internal_call_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme(): string;
function internal_call_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode(): string;
function internal_call_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme(): string;
function internal_call_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode(): string;
function internal_call_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme(): string;
function internal_call_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader(): string;
function internal_call_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl(): string;
function internal_call_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme(): string;
function internal_call_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader(): string;
function internal_call_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl(): string;
function internal_call_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme(): string;

implementation

uses
  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  Forms,
  code_decl_to_abi_frm;


// =============================================================================
// Internal state
// =============================================================================

// Source text at the time of the last successful Generate click. Used to
// skip re-parsing / re-generating when the agent calls several conversions
// in a row for the same source.
var
  G_Last_Generated_Source: string = '';


// =============================================================================
// JSON helpers
// =============================================================================

function Json_Status_OK: string;
begin
  Result := '{"status":"ok"}';
end;

function Json_Error(const Msg: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['error'] := Msg;
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
end;

function Json_Result_1(const R: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['result'] := R;
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
end;

function Json_Result_2(const R, Readme: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['result'] := R;
    jo.S['readme'] := Readme;
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
end;

function Json_Result_3(const R, Impl, Readme: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['result'] := R;
    jo.S['impl'] := Impl;
    jo.S['readme'] := Readme;
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
end;


// =============================================================================
// Main-thread worker routines
// =============================================================================
//
// Every routine below MUST be called on the main thread. They drive the
// existing GUI the same way a human operator would:
//
//   1. set the language combo and fire its OnChange handler
//   2. set the source text
//   3. click "Source -> JSON"  (fills Edit_SourceJson)
//   4. click "JSON -> Model"   (fills Edit_ModelJson)
//   5. click "Generate"        (fills all 6 target branches + writes files)
//   6. switch Page_FinalSource to the requested tab and read the editors
//
// The last step is the only part that differs between the six conversion
// branches; everything before it is identical.
// =============================================================================

// Applies the requested language to the combo box and fires the existing
// OnChange handler so that the form's internal `current_language` field is
// updated consistently. Returns False if the language is unsupported.
function Work_Apply_Language(const Language: string): Boolean;
var
  lang: string;
begin
  Result := False;
  if code_decl_to_abi_form = nil then
    Exit;
  lang := LowerCase(Trim(Language));
  if lang = 'pascal' then
  begin
    code_decl_to_abi_form.Cmb_LanguageSelector.ItemIndex := 1;
    code_decl_to_abi_form.Sel_Lang_ComboBoxChange(code_decl_to_abi_form.Cmb_LanguageSelector);
    Result := True;
  end
  else if lang = 'c' then
  begin
    code_decl_to_abi_form.Cmb_LanguageSelector.ItemIndex := 2;
    code_decl_to_abi_form.Sel_Lang_ComboBoxChange(code_decl_to_abi_form.Cmb_LanguageSelector);
    Result := True;
  end;
end;

// The shared "parse -> build model -> generate all" pipeline. Returns ''
// on success, or a human-readable error string on failure.
function Work_Parse_And_Generate: string;
var
  SrcText: string;
begin
  Result := '';
  if code_decl_to_abi_form = nil then
  begin
    Result := 'GUI form is not available.';
    Exit;
  end;

  SrcText := code_decl_to_abi_form.Edit_Source.Text;
  if Trim(SrcText) = '' then
  begin
    Result := 'No source code has been set. Call CodeDeclToAbi_SetSourceCode first.';
    Exit;
  end;

  // Cheap cache: if the source has not changed since the last successful
  // generation AND we already have a model JSON, skip the pipeline.
  if (SrcText = G_Last_Generated_Source) and
     (code_decl_to_abi_form.Edit_ModelJson.Lines.Count > 0) then
  begin
    Exit;
  end;

  try
    // Step 3: Source -> SourceJson
    code_decl_to_abi_form.source_2_json_nex_ButtonClick(nil);
    if code_decl_to_abi_form.Edit_SourceJson.Lines.Count = 0 then
    begin
      Result := 'Parsing failed: Source -> JSON produced no output.';
      Exit;
    end;

    // Step 4: SourceJson -> ModelJson
    code_decl_to_abi_form.JsonToModelButtonClick(nil);
    if code_decl_to_abi_form.Edit_ModelJson.Lines.Count = 0 then
    begin
      Result := 'Model build failed: JSON -> Model produced no output.';
      Exit;
    end;

    // Step 5: ModelJson -> all six branches
    code_decl_to_abi_form.GenerateSourceButtonClick(nil);

    G_Last_Generated_Source := SrcText;
  except
    on E: Exception do
    begin
      Result := 'Generation failed: ' + E.Message;
    end;
  end;
end;

// -- Step 1: set the source text and language ---------------------------------

function Work_Set_Source_Code(const Source, Language: string): string;
begin
  if code_decl_to_abi_form = nil then
  begin
    Result := Json_Error('GUI form is not available.');
    Exit;
  end;

  if not Work_Apply_Language(Language) then
  begin
    Result := Json_Error('Unsupported source language: "' + Language +
      '". Expected "pascal" or "c".');
    Exit;
  end;

  code_decl_to_abi_form.Edit_Source.Text := Source;

  // Any change of source invalidates the generation cache, because the
  // next Convert call must re-run the pipeline against the new text.
  G_Last_Generated_Source := '';

  Result := Json_Status_OK;
end;

// -- Step 2: the six conversion branches --------------------------------------

function Work_Convert_To_PascalService: string;
var
  err: string;
begin
  err := Work_Parse_And_Generate;
  if err <> '' then
  begin
    Result := Json_Error(err);
    Exit;
  end;
  code_decl_to_abi_form.Page_FinalSource.ActivePage := code_decl_to_abi_form.Tab_PasService;
  Result := Json_Result_2(
    code_decl_to_abi_form.Edit_PasServiceSource.Hint,
    code_decl_to_abi_form.Edit_PasServiceReadme.Hint);
end;

function Work_Convert_To_PascalCall: string;
var
  err: string;
begin
  err := Work_Parse_And_Generate;
  if err <> '' then
  begin
    Result := Json_Error(err);
    Exit;
  end;
  code_decl_to_abi_form.Page_FinalSource.ActivePage := code_decl_to_abi_form.Tab_PasCall;
  Result := Json_Result_2(
    code_decl_to_abi_form.Edit_PasCallSource.Hint,
    code_decl_to_abi_form.Edit_PasCallReadme.Hint);
end;

function Work_Convert_To_PythonService: string;
var
  err: string;
begin
  err := Work_Parse_And_Generate;
  if err <> '' then
  begin
    Result := Json_Error(err);
    Exit;
  end;
  code_decl_to_abi_form.Page_FinalSource.ActivePage := code_decl_to_abi_form.Tab_PyService;
  Result := Json_Result_2(
    code_decl_to_abi_form.Edit_PyServiceSource.Hint,
    code_decl_to_abi_form.Edit_PyServiceReadme.Hint);
end;

function Work_Convert_To_PythonCall: string;
var
  err: string;
begin
  err := Work_Parse_And_Generate;
  if err <> '' then
  begin
    Result := Json_Error(err);
    Exit;
  end;
  code_decl_to_abi_form.Page_FinalSource.ActivePage := code_decl_to_abi_form.Tab_PyCall;
  Result := Json_Result_2(
    code_decl_to_abi_form.Edit_PyCallSource.Hint,
    code_decl_to_abi_form.Edit_PyCallReadme.Hint);
end;

function Work_Convert_To_CppService: string;
var
  err: string;
begin
  err := Work_Parse_And_Generate;
  if err <> '' then
  begin
    Result := Json_Error(err);
    Exit;
  end;
  code_decl_to_abi_form.Page_FinalSource.ActivePage := code_decl_to_abi_form.Tab_CppService;
  Result := Json_Result_3(
    code_decl_to_abi_form.Edit_CppServiceHpp.Hint,
    code_decl_to_abi_form.Edit_CppServiceCpp.Hint,
    code_decl_to_abi_form.Edit_CppServiceReadme.Hint);
end;

function Work_Convert_To_CppCall: string;
var
  err: string;
begin
  err := Work_Parse_And_Generate;
  if err <> '' then
  begin
    Result := Json_Error(err);
    Exit;
  end;
  code_decl_to_abi_form.Page_FinalSource.ActivePage := code_decl_to_abi_form.Tab_CppCall;
  Result := Json_Result_3(
    code_decl_to_abi_form.Edit_CppCallHpp.Hint,
    code_decl_to_abi_form.Edit_CppCallCpp.Hint,
    code_decl_to_abi_form.Edit_CppCallReadme.Hint);
end;

// -- Step 3: the fourteen pure readers ----------------------------------------
//
// These only read the editor text. They never touch the pipeline.

function Work_Get_PascalServiceCode: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PasServiceSource.Text;
end;

function Work_Get_PascalServiceReadme: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PasServiceReadme.Text;
end;

function Work_Get_PascalCallCode: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PasCallSource.Text;
end;

function Work_Get_PascalCallReadme: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PasCallReadme.Text;
end;

function Work_Get_PythonServiceCode: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PyServiceSource.Text;
end;

function Work_Get_PythonServiceReadme: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PyServiceReadme.Text;
end;

function Work_Get_PythonCallCode: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PyCallSource.Text;
end;

function Work_Get_PythonCallReadme: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_PyCallReadme.Text;
end;

function Work_Get_CppServiceHeader: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_CppServiceHpp.Text;
end;

function Work_Get_CppServiceImpl: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_CppServiceCpp.Text;
end;

function Work_Get_CppServiceReadme: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_CppServiceReadme.Text;
end;

function Work_Get_CppCallHeader: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_CppCallHpp.Text;
end;

function Work_Get_CppCallImpl: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_CppCallCpp.Text;
end;

function Work_Get_CppCallReadme: string;
begin
  if code_decl_to_abi_form = nil then
    Result := ''
  else
    Result := code_decl_to_abi_form.Edit_CppCallReadme.Text;
end;


// =============================================================================
// Sync wrappers: every public entry point funnels through TCompute.Sync
// =============================================================================

function internal_call_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode(Source: string; Language: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Set_Source_Code(Source, Language);
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Set_Source_Code(Source, Language);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Convert_To_PascalService;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Convert_To_PascalService;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Convert_To_PascalCall;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Convert_To_PascalCall;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Convert_To_PythonService;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Convert_To_PythonService;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Convert_To_PythonCall;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Convert_To_PythonCall;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Convert_To_CppService;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Convert_To_CppService;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Convert_To_CppCall;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Convert_To_CppCall;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PascalServiceCode;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PascalServiceCode;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PascalServiceReadme;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PascalServiceReadme;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PascalCallCode;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PascalCallCode;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PascalCallReadme;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PascalCallReadme;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PythonServiceCode;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PythonServiceCode;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PythonServiceReadme;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PythonServiceReadme;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PythonCallCode;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PythonCallCode;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_PythonCallReadme;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_PythonCallReadme;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_CppServiceHeader;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_CppServiceHeader;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_CppServiceImpl;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_CppServiceImpl;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_CppServiceReadme;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_CppServiceReadme;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_CppCallHeader;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_CppCallHeader;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_CppCallImpl;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_CppCallImpl;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_CppCallReadme;
  end;
{$ELSE FPC}
var temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := Work_Get_CppCallReadme;
  end);
  Result := temp_;
{$ENDIF FPC}
end;


// =============================================================================
// All the remaining scaffolding below is unchanged from the original file.
// =============================================================================

{$Region 'internal_'}
function ret2str(v: Int64): string; overload;
begin
  Result := IntToStr(v);
end;

function ret2str(v: Double): string; overload;
begin
  Result := FloatToStr(v);
end;

function ret2str(const v: string): string; overload;
begin
  Result := v;
end;

// ---- Asynchronous logging to the beacon ----
procedure Do_Th_Send(th: TCompute);
var
  p: Pointer;
  msg: TZ_JsonString;
  Data, ResultHnd: TDataHnd___;
  jo: TZ_JsonObject;
begin
  p := th.UserData;
  msg.ReadUTF8AnsiChar(p);
  TZ_JsonString.FreeUTF8AnsiChar(p);
  Data := LF_CreateDataEx(AGENT_LOG_API);
  try
    jo := TZ_JsonObject.Create;
    try
      jo.S['message'] := msg.Text;
      LF_WriteStringBytes(Data, jo.ToBytes);
    finally
      jo.Free;
    end;
    ResultHnd := LF_CallEx(BEACON_APP, Data, 3000);
    if ResultHnd <> nil then
      LF_FreeData(ResultHnd);
  finally
    LF_FreeData(Data);
  end;
end;

procedure SendLogAsync(const msg: TZ_JsonString);
begin
  TCompute.RunC(msg.BuildUTF8AnsiChar, nil, Do_Th_Send);
end;

{$EndRegion 'internal_'}

{$Region 'callback_'}
// ---- CodeDeclToAbi_SetSourceCode (API: CodeDeclToAbi_SetSourceCode) ----
procedure Callback_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  Source: string;
  Language: string;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_SetSourceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_SetSourceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_SetSourceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_SetSourceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_SetSourceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    Source := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_SetSourceCode] called with %s -> result: %s', [Source, Language, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToAbi_SetSourceCode] called with %s', [Source, Language]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_SetSourceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_SetSourceCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_ConvertToPascalService (API: CodeDeclToAbi_ConvertToPascalService) ----
procedure Callback_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_ConvertToPascalService] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPascalService] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPascalService] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPascalService] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPascalService] Error: ' + errMsg);
      end;
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPascalService] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPascalService] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPascalService] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPascalService] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_ConvertToPascalCall (API: CodeDeclToAbi_ConvertToPascalCall) ----
procedure Callback_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_ConvertToPascalCall] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPascalCall] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPascalCall] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPascalCall] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPascalCall] Error: ' + errMsg);
      end;
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPascalCall] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPascalCall] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPascalCall] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPascalCall] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_ConvertToPythonService (API: CodeDeclToAbi_ConvertToPythonService) ----
procedure Callback_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_ConvertToPythonService] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPythonService] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPythonService] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPythonService] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPythonService] Error: ' + errMsg);
      end;
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPythonService] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPythonService] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPythonService] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPythonService] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_ConvertToPythonCall (API: CodeDeclToAbi_ConvertToPythonCall) ----
procedure Callback_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_ConvertToPythonCall] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPythonCall] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPythonCall] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPythonCall] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPythonCall] Error: ' + errMsg);
      end;
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPythonCall] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPythonCall] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToPythonCall] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_ConvertToPythonCall] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_ConvertToCppService (API: CodeDeclToAbi_ConvertToCppService) ----
procedure Callback_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_ConvertToCppService] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToCppService] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToCppService] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToCppService] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToCppService] Error: ' + errMsg);
      end;
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToCppService] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToCppService] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToCppService] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_ConvertToCppService] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_ConvertToCppCall (API: CodeDeclToAbi_ConvertToCppCall) ----
procedure Callback_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_ConvertToCppCall] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToCppCall] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToCppCall] Error: ' + errMsg);
      end;
      Exit;
    end;
    if not jo.Parae(jsonBytes) then
    begin
      errMsg := 'Invalid JSON';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToCppCall] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_ConvertToCppCall] Error: ' + errMsg);
      end;
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToCppCall] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToCppCall] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_ConvertToCppCall] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_ConvertToCppCall] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPascalServiceCode (API: CodeDeclToAbi_GetLastPascalServiceCode) ----
procedure Callback_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPascalServiceReadme (API: CodeDeclToAbi_GetLastPascalServiceReadme) ----
procedure Callback_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPascalCallCode (API: CodeDeclToAbi_GetLastPascalCallCode) ----
procedure Callback_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPascalCallReadme (API: CodeDeclToAbi_GetLastPascalCallReadme) ----
procedure Callback_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPythonServiceCode (API: CodeDeclToAbi_GetLastPythonServiceCode) ----
procedure Callback_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPythonServiceReadme (API: CodeDeclToAbi_GetLastPythonServiceReadme) ----
procedure Callback_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPythonCallCode (API: CodeDeclToAbi_GetLastPythonCallCode) ----
procedure Callback_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastPythonCallReadme (API: CodeDeclToAbi_GetLastPythonCallReadme) ----
procedure Callback_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastCppServiceHeader (API: CodeDeclToAbi_GetLastCppServiceHeader) ----
procedure Callback_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastCppServiceImpl (API: CodeDeclToAbi_GetLastCppServiceImpl) ----
procedure Callback_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastCppServiceReadme (API: CodeDeclToAbi_GetLastCppServiceReadme) ----
procedure Callback_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastCppCallHeader (API: CodeDeclToAbi_GetLastCppCallHeader) ----
procedure Callback_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastCppCallImpl (API: CodeDeclToAbi_GetLastCppCallImpl) ----
procedure Callback_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetLastCppCallReadme (API: CodeDeclToAbi_GetLastCppCallReadme) ----
procedure Callback_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ret: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if not jo.Parae(jsonBytes) then
    begin
      jo.Clear;
      jo.S['error'] := 'Invalid JSON';
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      Exit;
    end;
    ret := internal_call_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    end;
  end;
  jo.Free;
end;

{$EndRegion 'callback_'}

// -----------------------------------------------------------------------------
// Register a single tool with the beacon via the register_agent API.
// Returns True on success, False on failure.
// -----------------------------------------------------------------------------
function RegisterTool(const ToolDef: TZ_JsonObject): boolean;
var
  Data, ResultHnd: TDataHnd___;
  jsonBytes: TBytes;
  RespJson: TZ_JsonObject;
  toolName, toolDesc, targetApp, targetApi: string;
begin
  Result := False;
  toolName := ToolDef.S['name'];
  toolDesc := ToolDef.S['description'];
  targetApp := ToolDef.S['target_app'];
  targetApi := ToolDef.S['target_api'];
  if DEBUG_LOG then
    DoStatus('[RegisterTool] Registering tool: %s -> %s.%s', [toolName, targetApp, targetApi]);

  Data := LF_CreateDataEx(REGISTER_API);
  try
    LF_WriteStringBytes(Data, ToolDef.ToBytes);
    ResultHnd := LF_CallEx(BEACON_APP, Data, 5000);
    try
      jsonBytes := LF_ReadStringBytes(ResultHnd);
      if Length(jsonBytes) > 0 then
      begin
        RespJson := TZ_JsonObject.Create;
        try
          RespJson.Parae(jsonBytes);
          if RespJson.Exists('status') and (RespJson.S['status'] = 'ok') then
          begin
            Result := True;
            if DEBUG_LOG then
              DoStatus('[RegisterTool] Tool "%s" registered successfully.', [toolName]);
          end
          else
          begin
            if DEBUG_LOG then
              DoStatus('[RegisterTool] Server returned error: %s', [RespJson.S['message']]);
          end;
        finally
          RespJson.Free;
        end;
      end
      else
        if DEBUG_LOG then
          DoStatus('[RegisterTool] Empty response from beacon (timeout or network error)');
    finally
      LF_FreeData(ResultHnd);
    end;
  finally
    LF_FreeData(Data);
  end;
end;

// ---- RegisterTools implementation ----
function RegisterTools: Boolean;
var
  ToolDef: TZ_JsonObject;
  ParamsObj, PropsObj, PropObj: TZ_JsonObject;
  RequiredArr: TZ_JsonArray;
  Success: boolean;
  regCount: integer;
begin
  Result := False;
  regCount := 0;
  if DEBUG_LOG then
    DoStatus('[RegisterTools] Checking beacon availability: app=%s api=%s', [BEACON_APP, REGISTER_API]);
  if not LF_CheckApiEx(BEACON_APP, REGISTER_API) then
  begin
    DoStatus('[RegisterTools] Beacon not available. Please ensure pascal_agent_service is running.');
    exit;
  end;
  if DEBUG_LOG then
    DoStatus('[RegisterTools] Beacon is available. Starting tool registration...');
  try
    // Tool: CodeDeclToAbi_SetSourceCode -> CodeDeclToAbi_SetSourceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_SetSourceCode';
      ToolDef.S['description'] := 'Step 1/3 - Store source text. Does NOT convert.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_SetSourceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'complete source text.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'the SOURCE language. Accepted: pascal, c.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPascalService
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPascalService';
      ToolDef.S['description'] := 'Step 2/3 - Pascal service branch.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPascalService';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPascalCall
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPascalCall';
      ToolDef.S['description'] := 'Step 2/3 - Pascal call-side branch.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPascalCall';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPythonService
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPythonService';
      ToolDef.S['description'] := 'Step 2/3 - Python service branch.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPythonService';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPythonCall
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPythonCall';
      ToolDef.S['description'] := 'Step 2/3 - Python call-side branch.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPythonCall';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToCppService
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToCppService';
      ToolDef.S['description'] := 'Step 2/3 - C++ service branch.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToCppService';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToCppCall
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToCppCall';
      ToolDef.S['description'] := 'Step 2/3 - C++ call-side branch.';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToCppCall';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalServiceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalServiceCode';
      ToolDef.S['description'] := 'Step 3/3 - Pascal service reader (code).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalServiceCode';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalServiceReadme';
      ToolDef.S['description'] := 'Step 3/3 - Pascal service reader (README).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalServiceReadme';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalCallCode';
      ToolDef.S['description'] := 'Step 3/3 - Pascal call-side reader (code).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalCallCode';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalCallReadme';
      ToolDef.S['description'] := 'Step 3/3 - Pascal call-side reader (README).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalCallReadme';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonServiceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonServiceCode';
      ToolDef.S['description'] := 'Step 3/3 - Python service reader (code).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonServiceCode';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonServiceReadme';
      ToolDef.S['description'] := 'Step 3/3 - Python service reader (README).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonServiceReadme';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonCallCode';
      ToolDef.S['description'] := 'Step 3/3 - Python call-side reader (code).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonCallCode';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonCallReadme';
      ToolDef.S['description'] := 'Step 3/3 - Python call-side reader (README).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonCallReadme';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppServiceHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppServiceHeader';
      ToolDef.S['description'] := 'Step 3/3 - C++ service reader (header).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppServiceHeader';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppServiceImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppServiceImpl';
      ToolDef.S['description'] := 'Step 3/3 - C++ service reader (implementation).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppServiceImpl';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppServiceReadme';
      ToolDef.S['description'] := 'Step 3/3 - C++ service reader (README).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppServiceReadme';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppCallHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppCallHeader';
      ToolDef.S['description'] := 'Step 3/3 - C++ call-side reader (header).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppCallHeader';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppCallImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppCallImpl';
      ToolDef.S['description'] := 'Step 3/3 - C++ call-side reader (implementation).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppCallImpl';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppCallReadme';
      ToolDef.S['description'] := 'Step 3/3 - C++ call-side reader (README).';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppCallReadme';
      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
    finally
      ToolDef.Free;
    end;

    Result := (regCount = 21);
    if DEBUG_LOG then
      DoStatus('[RegisterTools] Registered %d out of %d tools.', [regCount, 21]);
  finally
  end;
end;

// ---- RegisterAPIs implementation ----
function RegisterAPIs: TAppHnd___;
var
  App: TAppHnd___;
begin
  Result := nil;
  App := LF_CreateAppEx(MY_APP_NAME, MY_APP_DESC);
  if DEBUG_LOG then
    DoStatus('[RegisterAPIs] Application "%s" created.', [MY_APP_NAME]);

  LF_RegisterCallEx(App, 'CodeDeclToAbi_SetSourceCode', 'Step 1/3', nil, @Callback_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPascalService', 'Step 2/3', nil, @Callback_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPascalCall', 'Step 2/3', nil, @Callback_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPythonService', 'Step 2/3', nil, @Callback_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPythonCall', 'Step 2/3', nil, @Callback_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToCppService', 'Step 2/3', nil, @Callback_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToCppCall', 'Step 2/3', nil, @Callback_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalServiceCode', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalServiceReadme', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalCallCode', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalCallReadme', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonServiceCode', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonServiceReadme', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonCallCode', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonCallReadme', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppServiceHeader', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppServiceImpl', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppServiceReadme', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppCallHeader', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppCallImpl', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl);
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppCallReadme', 'Step 3/3', nil, @Callback_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme);
  if DEBUG_LOG then
    DoStatus('[RegisterAPIs] Registered APIs: 21 functions');
  Result := App;
end;


// ---- Execute_And_Reg_all implementation ----
function Execute_And_Reg_all: Boolean;
var
  App: TAppHnd___;
begin
  Result := False;
  App := RegisterAPIs();
  if App = nil then
  begin
    if DEBUG_LOG then DoStatus('[Execute_And_Reg_all] RegisterAPIs failed');
    Exit;
  end;
  if LF_CheckMainThreadEx then
  begin
    LF_PrepareClientEx(IPC_ENDPOINT, App);
    Result := RegisterTools();
  end
  else
  begin
    LF_PrepareClientEx(IPC_ENDPOINT, App);
    if LF_PrepareDone() > 0 then
      Result := RegisterTools()
    else
    begin
      if DEBUG_LOG then DoStatus('[Execute_And_Reg_all] LF_PrepareDone failed');
    end;
  end;
end;

end.
