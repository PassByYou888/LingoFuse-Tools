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
  Forms,                     // <-- added: required for TThread / GUI form access
  code_decl_to_abi_frm;      // <-- added: the GUI form that this provider drives

// Forward declarations for all API callbacks
function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;
procedure Callback_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;


// =============================================================================
// JSON reply helpers
// =============================================================================
//
// Every conversion tool returns a small JSON object. These helpers build
// the three shapes that the agent contract expects:
//
//     {"status":"ok"}                                       (Step 1 success)
//     {"result":"<path>"}                                   (single-file target)
//     {"result":"<path>","readme":"<path>"}                 (code + README)
//     {"result":"<path>","impl":"<path>","readme":"<path>"}(C++ pair + README)
//     {"error":"<message>"}                                 (any failure)
//
// The JSON is emitted compact (Formated_ = False) so it fits on one line
// in an MCP tool result.

function Json_Status_OK: string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['status'] := 'ok';
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
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
// Every routine below MUST run on the main thread. They drive the existing
// code_decl_to_abi_frm form exactly the way a human operator would:
//
//   1. set the language combo box and fire its OnChange handler
//   2. set the source text into Edit_Source
//   3. click "Source -> JSON"     (fills Edit_SourceJson)
//   4. click "JSON -> Model"      (fills Edit_ModelJson)
//   5. click "Generate"           (fills all branches and writes files)
//   6. switch Page_FinalSource to the requested tab and read the editors
//
// Only step 6 differs between the six conversion branches; everything
// before it is identical.
//
// The form itself owns all of the parsing / generation state, so this
// unit does not need to reimplement any of it. The form also writes the
// generated artifacts to disk (see GenerateSourceButtonClick), and the
// writers cache the file paths in each TSynEdit.Hint field. Those Hint
// values are what the conversion tools return as "<path>" in the JSON
// reply, matching the CLI's behaviour.

// Cache of the last source text that successfully went through the
// parse -> model -> generate pipeline. Used to skip the pipeline when an
// agent issues several conversions in a row for the same source.
var
  G_Last_Generated_Source: string = '';

// Apply the requested language to the combo box and fire the OnChange
// handler so the form's internal current_language field stays in sync.
// Returns False when the language is not one of the two accepted values.
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
    code_decl_to_abi_form.Sel_Lang_ComboBoxChange(
      code_decl_to_abi_form.Cmb_LanguageSelector);
    Result := True;
  end
  else if lang = 'c' then
  begin
    code_decl_to_abi_form.Cmb_LanguageSelector.ItemIndex := 2;
    code_decl_to_abi_form.Sel_Lang_ComboBoxChange(
      code_decl_to_abi_form.Cmb_LanguageSelector);
    Result := True;
  end;
end;

// Shared "parse -> build model -> generate all branches" pipeline.
//
// Returns '' on success, or a human-readable error string on failure.
//
// The form's Generate button already writes each artifact to disk and
// stashes the file path in the corresponding TSynEdit.Hint, so the six
// conversion tools do not need to touch the filesystem themselves.
function Work_Parse_And_Generate: string;
var
  SrcText: string;
begin
  Result := '';
  if code_decl_to_abi_form = nil then
  begin
    Result := 'GUI form is not available. The code_decl_to_abi executable is not running.';
    Exit;
  end;

  SrcText := code_decl_to_abi_form.Edit_Source.Text;
  if Trim(SrcText) = '' then
  begin
    Result := 'No source code has been set. Call CodeDeclToAbi_SetSourceCode first.';
    Exit;
  end;

  // Cheap cache: if the same source has already been through the
  // pipeline and the model JSON is populated, skip the pipeline. This
  // is what makes "one SetSourceCode, many conversions" cheap.
  if (SrcText = G_Last_Generated_Source) and
     (code_decl_to_abi_form.Edit_ModelJson.Lines.Count > 0) then
    Exit;

  try
    // Step 3 of the GUI: Source -> SourceJson
    code_decl_to_abi_form.source_2_json_nex_ButtonClick(nil);
    if code_decl_to_abi_form.Edit_SourceJson.Lines.Count = 0 then
    begin
      Result := 'Parsing failed: Source -> JSON produced no output. '
              + 'Check that the source text is a complete Pascal unit or C header.';
      Exit;
    end;

    // Step 4 of the GUI: SourceJson -> ModelJson
    code_decl_to_abi_form.JsonToModelButtonClick(nil);
    if code_decl_to_abi_form.Edit_ModelJson.Lines.Count = 0 then
    begin
      Result := 'Model build failed: JSON -> Model produced no output. '
              + 'All routines may have been filtered out by the type whitelist.';
      Exit;
    end;

    // Step 5 of the GUI: ModelJson -> all six branches, files written
    code_decl_to_abi_form.GenerateSourceButtonClick(nil);

    G_Last_Generated_Source := SrcText;
  except
    on E: Exception do
      Result := 'Generation failed: ' + E.Message;
  end;
end;

// Step 1: store the source text and language. This is the only work the
// SetSourceCode tool does beyond validating arguments.
function Work_Set_Source_Code(const Source, Language: string): string;
begin
  if code_decl_to_abi_form = nil then
  begin
    Result := Json_Error('GUI form is not available. The code_decl_to_abi executable is not running.');
    Exit;
  end;

  if not Work_Apply_Language(Language) then
  begin
    Result := Json_Error('Unsupported source language: "' + Language +
      '". Expected "pascal" or "c". Note: python/cpp are TARGET languages, ' +
      'not SOURCE languages.');
    Exit;
  end;

  code_decl_to_abi_form.Edit_Source.Text := Source;

  // Any change of source invalidates the pipeline cache, because the
  // next Convert call must re-run the pipeline against the new text.
  G_Last_Generated_Source := '';

  Result := Json_Status_OK;
end;

// -- Step 2: the six conversion branches --------------------------------------
//
// Each branch runs the shared pipeline, then switches the Final Source
// page to the tab the agent asked for. The reader tools (Step 3) read
// back the editors regardless of which tab is currently selected, so
// this tab switch is purely cosmetic -- it keeps the GUI consistent with
// what the agent just requested, in case a human is watching.

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
  code_decl_to_abi_form.Page_FinalSource.ActivePage :=
    code_decl_to_abi_form.Tab_PasService;
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
  code_decl_to_abi_form.Page_FinalSource.ActivePage :=
    code_decl_to_abi_form.Tab_PasCall;
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
  code_decl_to_abi_form.Page_FinalSource.ActivePage :=
    code_decl_to_abi_form.Tab_PyService;
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
  code_decl_to_abi_form.Page_FinalSource.ActivePage :=
    code_decl_to_abi_form.Tab_PyCall;
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
  code_decl_to_abi_form.Page_FinalSource.ActivePage :=
    code_decl_to_abi_form.Tab_CppService;
  // C++ produces three artifacts: header, implementation, README.
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
  code_decl_to_abi_form.Page_FinalSource.ActivePage :=
    code_decl_to_abi_form.Tab_CppCall;
  Result := Json_Result_3(
    code_decl_to_abi_form.Edit_CppCallHpp.Hint,
    code_decl_to_abi_form.Edit_CppCallCpp.Hint,
    code_decl_to_abi_form.Edit_CppCallReadme.Hint);
end;

// -- Step 3: the fourteen pure readers ----------------------------------------
//
// These read the editor contents. They never touch the pipeline and never
// re-run a conversion. If the matching Step 2 conversion has not run yet
// the editor is empty and the reader returns an empty string, which is
// exactly the documented contract.

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
//
// The Call API callbacks run on a LingoFuse worker thread. Every GUI
// operation must run on the main thread. TCompute.Sync is a user-space
// synchronisation primitive: it queues the closure to the main thread and
// blocks the caller until it has executed. See the Z.Core knowledge base
// for the contract. The wrapper never returns before the work has
// completed, so the caller can safely read the result.
//
// The FPC and Delphi branches differ only in how the compiler captures
// local variables: FPC captures Result directly through a nested
// procedure; Delphi requires an explicit local to hold the value.

// ---- Step 1 ----
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

// ---- Step 2: Pascal service ----
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

// ---- Step 2: Pascal call ----
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

// ---- Step 2: Python service ----
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

// ---- Step 2: Python call ----
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

// ---- Step 2: C++ service ----
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

// ---- Step 2: C++ call ----
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

// ---- Step 3: Pascal service readers ----
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

// ---- Step 3: Python service readers ----
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

// ---- Step 3: C++ service readers ----
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

// ---- Step 3: C++ call readers ----
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
    // No parameters
    ret := internal_call_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPascalService] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPascalService] called (no params) -> result: ' + ret2str(ret));
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
    // No parameters
    ret := internal_call_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPascalCall] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPascalCall] called (no params) -> result: ' + ret2str(ret));
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
    // No parameters
    ret := internal_call_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPythonService] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPythonService] called (no params) -> result: ' + ret2str(ret));
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
    // No parameters
    ret := internal_call_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToPythonCall] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToPythonCall] called (no params) -> result: ' + ret2str(ret));
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
    // No parameters
    ret := internal_call_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToCppService] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToCppService] called (no params) -> result: ' + ret2str(ret));
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
    // No parameters
    ret := internal_call_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_ConvertToCppCall] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_ConvertToCppCall] called (no params) -> result: ' + ret2str(ret));
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPascalServiceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPascalServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPascalServiceCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalServiceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceCode] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPascalServiceReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPascalServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPascalServiceReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalServiceReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalServiceReadme] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPascalCallCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalCallCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPascalCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalCallCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPascalCallCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPascalCallCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalCallCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalCallCode] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPascalCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPascalCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPascalCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPascalCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPascalCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPascalCallReadme] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPythonServiceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPythonServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPythonServiceCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonServiceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceCode] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPythonServiceReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPythonServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPythonServiceReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonServiceReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonServiceReadme] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPythonCallCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonCallCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPythonCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonCallCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPythonCallCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPythonCallCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonCallCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonCallCode] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastPythonCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastPythonCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastPythonCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastPythonCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastPythonCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastPythonCallReadme] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastCppServiceHeader] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppServiceHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceHeader] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastCppServiceHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceHeader] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastCppServiceHeader] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastCppServiceHeader] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppServiceHeader] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceHeader] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastCppServiceImpl] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppServiceImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceImpl] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastCppServiceImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceImpl] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastCppServiceImpl] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastCppServiceImpl] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppServiceImpl] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceImpl] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastCppServiceReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastCppServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastCppServiceReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastCppServiceReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppServiceReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppServiceReadme] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastCppCallHeader] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppCallHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallHeader] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastCppCallHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallHeader] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastCppCallHeader] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastCppCallHeader] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppCallHeader] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallHeader] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastCppCallImpl] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppCallImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallImpl] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastCppCallImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallImpl] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastCppCallImpl] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastCppCallImpl] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppCallImpl] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallImpl] Exception: ' + E.Message);
      end;
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
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetLastCppCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetLastCppCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetLastCppCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetLastCppCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetLastCppCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetLastCppCallReadme] Exception: ' + E.Message);
      end;
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
      ToolDef.S['description'] := '(* [Step 1/3] Store source text and SOURCE language. Does NOT convert. This is a setup call. It does NOT produce any output and does NOT decide which target language or which side (service / call) will be generated. After this call succeeds you MUST invoke exactly one of the six Step 2 conversion functions to actually produce a result: CodeDeclToAbi_ConvertToPascalService CodeDeclToAbi_ConvertToPascalCall CodeDeclToAbi_ConvertToPythonService CodeDeclToAbi_ConvertToPythonCall CodeDeclToAbi_ConvertToCppService CodeDeclToAbi_ConvertToCppCall The stored source stays in effect for the rest of the session. To switch target languages or to switch between the service and call side you do NOT call this function again; you just call another Step 2 function. Parameters ---------- Source The complete source text. For Language = '#39'pascal'#39', pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language = '#39'c'#39', pass a full C header that starts with the include guard and contains the function prototypes. Language The SOURCE language of the text in Source. Compared case- insensitively. Accepted values: '#39'pascal'#39'   the input text is a Pascal unit '#39'c'#39'        the input text is a C header Do NOT pass a TARGET language such as '#39'python'#39' or '#39'cpp'#39'. The target language is selected by calling the corresponding CodeDeclToAbi_ConvertToXxxYyy function in Step 2. Passing a target-language name here produces {"error":"Unsupported source language: ..."}. Return value ------------ A JSON string. Exactly one of: {"status":"ok"}          on success {"error":"<message>"}    on failure The success response is stable and contains no other fields. Do not expect a "result" field: this function produces no artefact. Failure cases ------------- - Language is empty or unknown. - Language is '#39'python'#39' / '#39'cpp'#39' / any other target-language name. Remember: this field names the SOURCE, not the target. - The host program is not running (the tool provider is not registered with the beacon). - The underlying code generator raised an internal exception. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_SetSourceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The complete source text.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The SOURCE language of the text in Source. Compared case-'#10'      insensitively. Accepted values:';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_SetSourceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_SetSourceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPascalService -> CodeDeclToAbi_ConvertToPascalService
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPascalService';
      ToolDef.S['description'] := '(* [Step 2/3] Pascal service branch: generate service unit + README. Produce a Pascal ABI service unit and its README from the source stored by CodeDeclToAbi_SetSourceCode. The service unit is a complete Pascal source file that you compile into your own program. It exposes: const DEFAULT_APP_NAME, DEFAULT_APP_DESC; procedure RegisterAllABIAPIs(App: TAppHnd___); function  CreateAndRegisterABIApp: TAppHnd___; one internal_call_<Api> stub per routine, which you fill in with the real implementation. See the matching README for the full build and deployment guide, including the FPC compile command lines and a runnable .lpr test program. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. If it has not, the call returns an error. Calling this function does NOT require calling SetSourceCode again: the stored source is reused as-is. Output ------ On success: {"result":"<service_unit.pas>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPascalServiceCode    the service unit CodeDeclToAbi_GetLastPascalServiceReadme  the user guide Independence ------------ This branch is independent from the Python and C++ branches. Calling it does not affect the caches of the other branches. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPascalService';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_ConvertToPascalService')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_ConvertToPascalService');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPascalCall -> CodeDeclToAbi_ConvertToPascalCall
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPascalCall';
      ToolDef.S['description'] := '(* [Step 2/3] Pascal call-side branch: generate call unit + README. Produce a Pascal ABI call-side unit and its README from the source stored by CodeDeclToAbi_SetSourceCode. The call-side unit is a complete Pascal source file that you compile into your own program. It exposes one free function per routine of the matching service, with the same signature. Each function: - serialises its arguments into a DataHandle, - issues an LF_CallEx to the matching service, - reads the response, - raises EABI_RemoteError if the service reported a failure. See the matching README for the full build and deployment guide, including the FPC compile command lines and a runnable .lpr test program. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<call_unit.pas>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPascalCallCode    the call unit CodeDeclToAbi_GetLastPascalCallReadme  the user guide Pairing ------- The generated call unit and the matching service unit MUST come from the SAME stored source text. Do not mix halves from different sources: the wire format is positional and there is no negotiation. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPascalCall';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_ConvertToPascalCall')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_ConvertToPascalCall');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPythonService -> CodeDeclToAbi_ConvertToPythonService
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPythonService';
      ToolDef.S['description'] := '(* [Step 2/3] Python service branch: generate service module + README. Produce a Python ABI service module and its README from the source stored by CodeDeclToAbi_SetSourceCode. The service module is a self-contained Python 3 file. It exposes: DEFAULT_APP_NAME, DEFAULT_APP_DESC RegisterAllABIAPIs(app) CreateAndRegisterABIApp() one internal_call_<api> stub per routine, which you fill in with the real implementation. It also contains an `if __name__ == "__main__":` block, so the module itself is the test program: run it with `python <module>.py` to start the service. See the matching README for the full build and deployment guide. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<service.py>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPythonServiceCode    the service module CodeDeclToAbi_GetLastPythonServiceReadme  the user guide Runtime ------- The generated module imports from `lingofuse._lf_native` and `lingofuse.lf_io`. See the README for how to install the package or point PYTHONPATH at the shipped copy. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPythonService';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_ConvertToPythonService')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_ConvertToPythonService');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToPythonCall -> CodeDeclToAbi_ConvertToPythonCall
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToPythonCall';
      ToolDef.S['description'] := '(* [Step 2/3] Python call-side branch: generate call module + README. Produce a Python ABI call-side module and its README from the source stored by CodeDeclToAbi_SetSourceCode. The call-side module is a self-contained Python 3 file. It exposes one free function per routine of the matching service, with the same signature. Each function: - serialises its arguments with little-endian `struct.pack`, - issues an LF_Call to the matching service, - reads the response with `struct.unpack`, - raises EABIRemoteError if the service reported a failure. See the matching README for the full build and deployment guide. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<call.py>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPythonCallCode    the call module CodeDeclToAbi_GetLastPythonCallReadme  the user guide Pairing ------- The generated call module and the matching service module MUST come from the SAME stored source text. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToPythonCall';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_ConvertToPythonCall')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_ConvertToPythonCall');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToCppService -> CodeDeclToAbi_ConvertToCppService
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToCppService';
      ToolDef.S['description'] := '(* [Step 2/3] C++ service branch: generate header + impl + README. Produce a C++ ABI service pair (header + implementation) and its README from the source stored by CodeDeclToAbi_SetSourceCode. The pair consists of two files with the same base name: <UnitName>_abi_service.hpp    declaration header <UnitName>_abi_service.cpp    implementation The header exposes: extern const char* DEFAULT_APP_NAME; extern const char* DEFAULT_APP_DESC; constexpr std::uint8_t STATUS_OK / STATUS_ERROR; inline Safe_Write_Error / Safe_Write_Scalar / Safe_Write_String / Safe_Write_Void helpers; one internal_call_<Api> stub declaration per routine; one LF_CDECL Callback_<Api> declaration per routine; RegisterAllABIAPIs / CreateAndRegisterABIApp. The implementation provides the default stub bodies (which you replace), the cdecl callbacks, and the registration functions. See the matching README for the full build and deployment guide, including a CMake script and raw compile commands for g++ / clang++ / MSVC / MinGW. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<service.hpp>","impl":"<service.cpp>", "readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastCppServiceHeader  the header CodeDeclToAbi_GetLastCppServiceImpl    the implementation CodeDeclToAbi_GetLastCppServiceReadme  the user guide Note ---- Both files are written together. Naming either one in a CLI invocation produces both. The header is the entry point; the implementation includes it. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToCppService';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_ConvertToCppService')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_ConvertToCppService');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_ConvertToCppCall -> CodeDeclToAbi_ConvertToCppCall
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_ConvertToCppCall';
      ToolDef.S['description'] := '(* [Step 2/3] C++ call-side branch: generate header + impl + README. Produce a C++ ABI call-side pair (header + implementation) and its README from the source stored by CodeDeclToAbi_SetSourceCode. The pair consists of two files with the same base name: <UnitName>_abi_call.hpp    declaration header <UnitName>_abi_call.cpp    implementation The header exposes: extern std::string   ABI_TargetApp; extern std::uint64_t ABI_Timeout; constexpr std::uint8_t STATUS_OK / STATUS_ERROR; class EABI_RemoteError; one typed free-function declaration per routine. The implementation provides ABI_TargetApp / ABI_Timeout definitions and one typed free function per routine. Each free function: - writes its arguments into a lingofuse::DataHandle, - calls lingofuse::tryCall(ABI_TargetApp, ...), - reads the status byte, - throws EABI_RemoteError if the status is not STATUS_OK. See the matching README for the full build and deployment guide, including a CMake script. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<call.hpp>","impl":"<call.cpp>", "readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastCppCallHeader  the header CodeDeclToAbi_GetLastCppCallImpl    the implementation CodeDeclToAbi_GetLastCppCallReadme  the user guide Pairing ------- The generated pair MUST come from the SAME stored source text as the matching service pair. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_ConvertToCppCall';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_ConvertToCppCall')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_ConvertToCppCall');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalServiceCode -> CodeDeclToAbi_GetLastPascalServiceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalServiceCode';
      ToolDef.S['description'] := '(* [Step 3/3] Pascal service reader: return the cached service unit text. Returns the full text of the Pascal service unit produced by the most recent successful CodeDeclToAbi_ConvertToPascalService call. Prerequisite: CodeDeclToAbi_ConvertToPascalService must have succeeded earlier in this session. If it has not, this returns an empty string. It never triggers a conversion. Return value: the full service unit text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalServiceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPascalServiceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPascalServiceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalServiceReadme -> CodeDeclToAbi_GetLastPascalServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalServiceReadme';
      ToolDef.S['description'] := '(* [Step 3/3] Pascal service reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPascalService call. Prerequisite: CodeDeclToAbi_ConvertToPascalService must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. Tip: this README is the build and deployment guide for the generated service unit. Read it before you write any build script. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalServiceReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPascalServiceReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPascalServiceReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalCallCode -> CodeDeclToAbi_GetLastPascalCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalCallCode';
      ToolDef.S['description'] := '(* [Step 3/3] Pascal call reader: return the cached call unit text. Returns the full text of the Pascal call-side unit produced by the most recent successful CodeDeclToAbi_ConvertToPascalCall call. Prerequisite: CodeDeclToAbi_ConvertToPascalCall must have succeeded earlier in this session. Return value: the full call-side unit text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalCallCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPascalCallCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPascalCallCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPascalCallReadme -> CodeDeclToAbi_GetLastPascalCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPascalCallReadme';
      ToolDef.S['description'] := '(* [Step 3/3] Pascal call reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPascalCall call. Prerequisite: CodeDeclToAbi_ConvertToPascalCall must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPascalCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPascalCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPascalCallReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonServiceCode -> CodeDeclToAbi_GetLastPythonServiceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonServiceCode';
      ToolDef.S['description'] := '(* [Step 3/3] Python service reader: return the cached module text. Returns the full text of the Python service module produced by the most recent successful CodeDeclToAbi_ConvertToPythonService call. Prerequisite: CodeDeclToAbi_ConvertToPythonService must have succeeded earlier in this session. Return value: the full Python module text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonServiceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPythonServiceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPythonServiceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonServiceReadme -> CodeDeclToAbi_GetLastPythonServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonServiceReadme';
      ToolDef.S['description'] := '(* [Step 3/3] Python service reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPythonService call. Prerequisite: CodeDeclToAbi_ConvertToPythonService must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. Tip: this README is the build and deployment guide for the generated Python service module. Read it before running anything. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonServiceReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPythonServiceReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPythonServiceReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonCallCode -> CodeDeclToAbi_GetLastPythonCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonCallCode';
      ToolDef.S['description'] := '(* [Step 3/3] Python call reader: return the cached module text. Returns the full text of the Python call-side module produced by the most recent successful CodeDeclToAbi_ConvertToPythonCall call. Prerequisite: CodeDeclToAbi_ConvertToPythonCall must have succeeded earlier in this session. Return value: the full Python module text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonCallCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPythonCallCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPythonCallCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastPythonCallReadme -> CodeDeclToAbi_GetLastPythonCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastPythonCallReadme';
      ToolDef.S['description'] := '(* [Step 3/3] Python call reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPythonCall call. Prerequisite: CodeDeclToAbi_ConvertToPythonCall must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastPythonCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastPythonCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastPythonCallReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppServiceHeader -> CodeDeclToAbi_GetLastCppServiceHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppServiceHeader';
      ToolDef.S['description'] := '(* [Step 3/3] C++ service reader: return the cached header text. Returns the full text of the C++ service header produced by the most recent successful CodeDeclToAbi_ConvertToCppService call. Prerequisite: CodeDeclToAbi_ConvertToCppService must have succeeded earlier in this session. Return value: the full header text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppServiceHeader';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastCppServiceHeader')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastCppServiceHeader');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppServiceImpl -> CodeDeclToAbi_GetLastCppServiceImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppServiceImpl';
      ToolDef.S['description'] := '(* [Step 3/3] C++ service reader: return the cached impl text. Returns the full text of the C++ service implementation produced by the most recent successful CodeDeclToAbi_ConvertToCppService call. Prerequisite: CodeDeclToAbi_ConvertToCppService must have succeeded earlier in this session. Return value: the full implementation text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppServiceImpl';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastCppServiceImpl')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastCppServiceImpl');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppServiceReadme -> CodeDeclToAbi_GetLastCppServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppServiceReadme';
      ToolDef.S['description'] := '(* [Step 3/3] C++ service reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToCppService call. Prerequisite: CodeDeclToAbi_ConvertToCppService must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. Tip: this README is the build and deployment guide for the generated C++ service pair. It contains a CMake script, compile commands for g++ / clang++ / MSVC / MinGW, and a runnable test program. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppServiceReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastCppServiceReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastCppServiceReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppCallHeader -> CodeDeclToAbi_GetLastCppCallHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppCallHeader';
      ToolDef.S['description'] := '(* [Step 3/3] C++ call reader: return the cached header text. Returns the full text of the C++ call-side header produced by the most recent successful CodeDeclToAbi_ConvertToCppCall call. Prerequisite: CodeDeclToAbi_ConvertToCppCall must have succeeded earlier in this session. Return value: the full header text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppCallHeader';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastCppCallHeader')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastCppCallHeader');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppCallImpl -> CodeDeclToAbi_GetLastCppCallImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppCallImpl';
      ToolDef.S['description'] := '(* [Step 3/3] C++ call reader: return the cached impl text. Returns the full text of the C++ call-side implementation produced by the most recent successful CodeDeclToAbi_ConvertToCppCall call. Prerequisite: CodeDeclToAbi_ConvertToCppCall must have succeeded earlier in this session. Return value: the full implementation text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppCallImpl';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastCppCallImpl')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastCppCallImpl');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetLastCppCallReadme -> CodeDeclToAbi_GetLastCppCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetLastCppCallReadme';
      ToolDef.S['description'] := '(* [Step 3/3] C++ call reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToCppCall call. Prerequisite: CodeDeclToAbi_ConvertToCppCall must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetLastCppCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetLastCppCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetLastCppCallReadme');
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

  LF_RegisterCallEx(App, 'CodeDeclToAbi_SetSourceCode', '(* [Step 1/3] Store source text and SOURCE language. Does NOT convert. This is a setup call. It does NOT produce any output and does NOT decide which target language or which side (service / call) will be generated. After this call succeeds you MUST invoke exactly one of the six Step 2 conversion functions to actually produce a result: CodeDeclToAbi_ConvertToPascalService CodeDeclToAbi_ConvertToPascalCall CodeDeclToAbi_ConvertToPythonService CodeDeclToAbi_ConvertToPythonCall CodeDeclToAbi_ConvertToCppService CodeDeclToAbi_ConvertToCppCall The stored source stays in effect for the rest of the session. To switch target languages or to switch between the service and call side you do NOT call this function again; you just call another Step 2 function. Parameters ---------- Source The complete source text. For Language = '#39'pascal'#39', pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language = '#39'c'#39', pass a full C header that starts with the include guard and contains the function prototypes. Language The SOURCE language of the text in Source. Compared case- insensitively. Accepted values: '#39'pascal'#39'   the input text is a Pascal unit '#39'c'#39'        the input text is a C header Do NOT pass a TARGET language such as '#39'python'#39' or '#39'cpp'#39'. The target language is selected by calling the corresponding CodeDeclToAbi_ConvertToXxxYyy function in Step 2. Passing a target-language name here produces {"error":"Unsupported source language: ..."}. Return value ------------ A JSON string. Exactly one of: {"status":"ok"}          on success {"error":"<message>"}    on failure The success response is stable and contains no other fields. Do not expect a "result" field: this function produces no artefact. Failure cases ------------- - Language is empty or unknown. - Language is '#39'python'#39' / '#39'cpp'#39' / any other target-language name. Remember: this field names the SOURCE, not the target. - The host program is not running (the tool provider is not registered with the beacon). - The underlying code generator raised an internal exception. )', nil, @Callback_CodeDeclToAbi_SetSourceCode_CodeDeclToAbi_SetSourceCode);  // Register API: CodeDeclToAbi_SetSourceCode -> CodeDeclToAbi_SetSourceCode
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPascalService', '(* [Step 2/3] Pascal service branch: generate service unit + README. Produce a Pascal ABI service unit and its README from the source stored by CodeDeclToAbi_SetSourceCode. The service unit is a complete Pascal source file that you compile into your own program. It exposes: const DEFAULT_APP_NAME, DEFAULT_APP_DESC; procedure RegisterAllABIAPIs(App: TAppHnd___); function  CreateAndRegisterABIApp: TAppHnd___; one internal_call_<Api> stub per routine, which you fill in with the real implementation. See the matching README for the full build and deployment guide, including the FPC compile command lines and a runnable .lpr test program. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. If it has not, the call returns an error. Calling this function does NOT require calling SetSourceCode again: the stored source is reused as-is. Output ------ On success: {"result":"<service_unit.pas>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPascalServiceCode    the service unit CodeDeclToAbi_GetLastPascalServiceReadme  the user guide Independence ------------ This branch is independent from the Python and C++ branches. Calling it does not affect the caches of the other branches. )', nil, @Callback_CodeDeclToAbi_ConvertToPascalService_CodeDeclToAbi_ConvertToPascalService);  // Register API: CodeDeclToAbi_ConvertToPascalService -> CodeDeclToAbi_ConvertToPascalService
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPascalCall', '(* [Step 2/3] Pascal call-side branch: generate call unit + README. Produce a Pascal ABI call-side unit and its README from the source stored by CodeDeclToAbi_SetSourceCode. The call-side unit is a complete Pascal source file that you compile into your own program. It exposes one free function per routine of the matching service, with the same signature. Each function: - serialises its arguments into a DataHandle, - issues an LF_CallEx to the matching service, - reads the response, - raises EABI_RemoteError if the service reported a failure. See the matching README for the full build and deployment guide, including the FPC compile command lines and a runnable .lpr test program. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<call_unit.pas>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPascalCallCode    the call unit CodeDeclToAbi_GetLastPascalCallReadme  the user guide Pairing ------- The generated call unit and the matching service unit MUST come from the SAME stored source text. Do not mix halves from different sources: the wire format is positional and there is no negotiation. )', nil, @Callback_CodeDeclToAbi_ConvertToPascalCall_CodeDeclToAbi_ConvertToPascalCall);  // Register API: CodeDeclToAbi_ConvertToPascalCall -> CodeDeclToAbi_ConvertToPascalCall
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPythonService', '(* [Step 2/3] Python service branch: generate service module + README. Produce a Python ABI service module and its README from the source stored by CodeDeclToAbi_SetSourceCode. The service module is a self-contained Python 3 file. It exposes: DEFAULT_APP_NAME, DEFAULT_APP_DESC RegisterAllABIAPIs(app) CreateAndRegisterABIApp() one internal_call_<api> stub per routine, which you fill in with the real implementation. It also contains an `if __name__ == "__main__":` block, so the module itself is the test program: run it with `python <module>.py` to start the service. See the matching README for the full build and deployment guide. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<service.py>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPythonServiceCode    the service module CodeDeclToAbi_GetLastPythonServiceReadme  the user guide Runtime ------- The generated module imports from `lingofuse._lf_native` and `lingofuse.lf_io`. See the README for how to install the package or point PYTHONPATH at the shipped copy. )', nil, @Callback_CodeDeclToAbi_ConvertToPythonService_CodeDeclToAbi_ConvertToPythonService);  // Register API: CodeDeclToAbi_ConvertToPythonService -> CodeDeclToAbi_ConvertToPythonService
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToPythonCall', '(* [Step 2/3] Python call-side branch: generate call module + README. Produce a Python ABI call-side module and its README from the source stored by CodeDeclToAbi_SetSourceCode. The call-side module is a self-contained Python 3 file. It exposes one free function per routine of the matching service, with the same signature. Each function: - serialises its arguments with little-endian `struct.pack`, - issues an LF_Call to the matching service, - reads the response with `struct.unpack`, - raises EABIRemoteError if the service reported a failure. See the matching README for the full build and deployment guide. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<call.py>","readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastPythonCallCode    the call module CodeDeclToAbi_GetLastPythonCallReadme  the user guide Pairing ------- The generated call module and the matching service module MUST come from the SAME stored source text. )', nil, @Callback_CodeDeclToAbi_ConvertToPythonCall_CodeDeclToAbi_ConvertToPythonCall);  // Register API: CodeDeclToAbi_ConvertToPythonCall -> CodeDeclToAbi_ConvertToPythonCall
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToCppService', '(* [Step 2/3] C++ service branch: generate header + impl + README. Produce a C++ ABI service pair (header + implementation) and its README from the source stored by CodeDeclToAbi_SetSourceCode. The pair consists of two files with the same base name: <UnitName>_abi_service.hpp    declaration header <UnitName>_abi_service.cpp    implementation The header exposes: extern const char* DEFAULT_APP_NAME; extern const char* DEFAULT_APP_DESC; constexpr std::uint8_t STATUS_OK / STATUS_ERROR; inline Safe_Write_Error / Safe_Write_Scalar / Safe_Write_String / Safe_Write_Void helpers; one internal_call_<Api> stub declaration per routine; one LF_CDECL Callback_<Api> declaration per routine; RegisterAllABIAPIs / CreateAndRegisterABIApp. The implementation provides the default stub bodies (which you replace), the cdecl callbacks, and the registration functions. See the matching README for the full build and deployment guide, including a CMake script and raw compile commands for g++ / clang++ / MSVC / MinGW. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<service.hpp>","impl":"<service.cpp>", "readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastCppServiceHeader  the header CodeDeclToAbi_GetLastCppServiceImpl    the implementation CodeDeclToAbi_GetLastCppServiceReadme  the user guide Note ---- Both files are written together. Naming either one in a CLI invocation produces both. The header is the entry point; the implementation includes it. )', nil, @Callback_CodeDeclToAbi_ConvertToCppService_CodeDeclToAbi_ConvertToCppService);  // Register API: CodeDeclToAbi_ConvertToCppService -> CodeDeclToAbi_ConvertToCppService
  LF_RegisterCallEx(App, 'CodeDeclToAbi_ConvertToCppCall', '(* [Step 2/3] C++ call-side branch: generate header + impl + README. Produce a C++ ABI call-side pair (header + implementation) and its README from the source stored by CodeDeclToAbi_SetSourceCode. The pair consists of two files with the same base name: <UnitName>_abi_call.hpp    declaration header <UnitName>_abi_call.cpp    implementation The header exposes: extern std::string   ABI_TargetApp; extern std::uint64_t ABI_Timeout; constexpr std::uint8_t STATUS_OK / STATUS_ERROR; class EABI_RemoteError; one typed free-function declaration per routine. The implementation provides ABI_TargetApp / ABI_Timeout definitions and one typed free function per routine. Each free function: - writes its arguments into a lingofuse::DataHandle, - calls lingofuse::tryCall(ABI_TargetApp, ...), - reads the status byte, - throws EABI_RemoteError if the status is not STATUS_OK. See the matching README for the full build and deployment guide, including a CMake script. Prerequisites ------------- CodeDeclToAbi_SetSourceCode must have succeeded earlier in this session. Output ------ On success: {"result":"<call.hpp>","impl":"<call.cpp>", "readme":"<readme.md>"} On failure: {"error":"<message>"} Related readers --------------- CodeDeclToAbi_GetLastCppCallHeader  the header CodeDeclToAbi_GetLastCppCallImpl    the implementation CodeDeclToAbi_GetLastCppCallReadme  the user guide Pairing ------- The generated pair MUST come from the SAME stored source text as the matching service pair. )', nil, @Callback_CodeDeclToAbi_ConvertToCppCall_CodeDeclToAbi_ConvertToCppCall);  // Register API: CodeDeclToAbi_ConvertToCppCall -> CodeDeclToAbi_ConvertToCppCall
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalServiceCode', '(* [Step 3/3] Pascal service reader: return the cached service unit text. Returns the full text of the Pascal service unit produced by the most recent successful CodeDeclToAbi_ConvertToPascalService call. Prerequisite: CodeDeclToAbi_ConvertToPascalService must have succeeded earlier in this session. If it has not, this returns an empty string. It never triggers a conversion. Return value: the full service unit text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastPascalServiceCode_CodeDeclToAbi_GetLastPascalServiceCode);  // Register API: CodeDeclToAbi_GetLastPascalServiceCode -> CodeDeclToAbi_GetLastPascalServiceCode
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalServiceReadme', '(* [Step 3/3] Pascal service reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPascalService call. Prerequisite: CodeDeclToAbi_ConvertToPascalService must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. Tip: this README is the build and deployment guide for the generated service unit. Read it before you write any build script. )', nil, @Callback_CodeDeclToAbi_GetLastPascalServiceReadme_CodeDeclToAbi_GetLastPascalServiceReadme);  // Register API: CodeDeclToAbi_GetLastPascalServiceReadme -> CodeDeclToAbi_GetLastPascalServiceReadme
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalCallCode', '(* [Step 3/3] Pascal call reader: return the cached call unit text. Returns the full text of the Pascal call-side unit produced by the most recent successful CodeDeclToAbi_ConvertToPascalCall call. Prerequisite: CodeDeclToAbi_ConvertToPascalCall must have succeeded earlier in this session. Return value: the full call-side unit text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastPascalCallCode_CodeDeclToAbi_GetLastPascalCallCode);  // Register API: CodeDeclToAbi_GetLastPascalCallCode -> CodeDeclToAbi_GetLastPascalCallCode
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPascalCallReadme', '(* [Step 3/3] Pascal call reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPascalCall call. Prerequisite: CodeDeclToAbi_ConvertToPascalCall must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastPascalCallReadme_CodeDeclToAbi_GetLastPascalCallReadme);  // Register API: CodeDeclToAbi_GetLastPascalCallReadme -> CodeDeclToAbi_GetLastPascalCallReadme
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonServiceCode', '(* [Step 3/3] Python service reader: return the cached module text. Returns the full text of the Python service module produced by the most recent successful CodeDeclToAbi_ConvertToPythonService call. Prerequisite: CodeDeclToAbi_ConvertToPythonService must have succeeded earlier in this session. Return value: the full Python module text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastPythonServiceCode_CodeDeclToAbi_GetLastPythonServiceCode);  // Register API: CodeDeclToAbi_GetLastPythonServiceCode -> CodeDeclToAbi_GetLastPythonServiceCode
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonServiceReadme', '(* [Step 3/3] Python service reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPythonService call. Prerequisite: CodeDeclToAbi_ConvertToPythonService must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. Tip: this README is the build and deployment guide for the generated Python service module. Read it before running anything. )', nil, @Callback_CodeDeclToAbi_GetLastPythonServiceReadme_CodeDeclToAbi_GetLastPythonServiceReadme);  // Register API: CodeDeclToAbi_GetLastPythonServiceReadme -> CodeDeclToAbi_GetLastPythonServiceReadme
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonCallCode', '(* [Step 3/3] Python call reader: return the cached module text. Returns the full text of the Python call-side module produced by the most recent successful CodeDeclToAbi_ConvertToPythonCall call. Prerequisite: CodeDeclToAbi_ConvertToPythonCall must have succeeded earlier in this session. Return value: the full Python module text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastPythonCallCode_CodeDeclToAbi_GetLastPythonCallCode);  // Register API: CodeDeclToAbi_GetLastPythonCallCode -> CodeDeclToAbi_GetLastPythonCallCode
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastPythonCallReadme', '(* [Step 3/3] Python call reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToPythonCall call. Prerequisite: CodeDeclToAbi_ConvertToPythonCall must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastPythonCallReadme_CodeDeclToAbi_GetLastPythonCallReadme);  // Register API: CodeDeclToAbi_GetLastPythonCallReadme -> CodeDeclToAbi_GetLastPythonCallReadme
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppServiceHeader', '(* [Step 3/3] C++ service reader: return the cached header text. Returns the full text of the C++ service header produced by the most recent successful CodeDeclToAbi_ConvertToCppService call. Prerequisite: CodeDeclToAbi_ConvertToCppService must have succeeded earlier in this session. Return value: the full header text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastCppServiceHeader_CodeDeclToAbi_GetLastCppServiceHeader);  // Register API: CodeDeclToAbi_GetLastCppServiceHeader -> CodeDeclToAbi_GetLastCppServiceHeader
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppServiceImpl', '(* [Step 3/3] C++ service reader: return the cached impl text. Returns the full text of the C++ service implementation produced by the most recent successful CodeDeclToAbi_ConvertToCppService call. Prerequisite: CodeDeclToAbi_ConvertToCppService must have succeeded earlier in this session. Return value: the full implementation text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastCppServiceImpl_CodeDeclToAbi_GetLastCppServiceImpl);  // Register API: CodeDeclToAbi_GetLastCppServiceImpl -> CodeDeclToAbi_GetLastCppServiceImpl
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppServiceReadme', '(* [Step 3/3] C++ service reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToCppService call. Prerequisite: CodeDeclToAbi_ConvertToCppService must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. Tip: this README is the build and deployment guide for the generated C++ service pair. It contains a CMake script, compile commands for g++ / clang++ / MSVC / MinGW, and a runnable test program. )', nil, @Callback_CodeDeclToAbi_GetLastCppServiceReadme_CodeDeclToAbi_GetLastCppServiceReadme);  // Register API: CodeDeclToAbi_GetLastCppServiceReadme -> CodeDeclToAbi_GetLastCppServiceReadme
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppCallHeader', '(* [Step 3/3] C++ call reader: return the cached header text. Returns the full text of the C++ call-side header produced by the most recent successful CodeDeclToAbi_ConvertToCppCall call. Prerequisite: CodeDeclToAbi_ConvertToCppCall must have succeeded earlier in this session. Return value: the full header text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastCppCallHeader_CodeDeclToAbi_GetLastCppCallHeader);  // Register API: CodeDeclToAbi_GetLastCppCallHeader -> CodeDeclToAbi_GetLastCppCallHeader
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppCallImpl', '(* [Step 3/3] C++ call reader: return the cached impl text. Returns the full text of the C++ call-side implementation produced by the most recent successful CodeDeclToAbi_ConvertToCppCall call. Prerequisite: CodeDeclToAbi_ConvertToCppCall must have succeeded earlier in this session. Return value: the full implementation text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastCppCallImpl_CodeDeclToAbi_GetLastCppCallImpl);  // Register API: CodeDeclToAbi_GetLastCppCallImpl -> CodeDeclToAbi_GetLastCppCallImpl
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetLastCppCallReadme', '(* [Step 3/3] C++ call reader: return the cached README text. Returns the full text of the Markdown README produced by the most recent successful CodeDeclToAbi_ConvertToCppCall call. Prerequisite: CodeDeclToAbi_ConvertToCppCall must have succeeded earlier in this session. Return value: the Markdown README text, or an empty string. )', nil, @Callback_CodeDeclToAbi_GetLastCppCallReadme_CodeDeclToAbi_GetLastCppCallReadme);  // Register API: CodeDeclToAbi_GetLastCppCallReadme -> CodeDeclToAbi_GetLastCppCallReadme
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
