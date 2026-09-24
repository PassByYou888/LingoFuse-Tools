unit code_decl_to_json_abi_mcp_api_tool_provider_unit;

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
  MY_APP_NAME : string = 'code_decl_to_json_abi_mcp_api';
  MY_APP_DESC : string = 'Tool provider for unit code_decl_to_json_abi_mcp_api';
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


function internal_call_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(Source: string; Language: string): string;
function internal_call_CodeDeclToJsonAbi_SetModelJson_CodeDeclToJsonAbi_SetModelJson(ModelJson: string): string;
function internal_call_CodeDeclToJsonAbi_GetSourceJson_CodeDeclToJsonAbi_GetSourceJson(): string;
function internal_call_CodeDeclToJsonAbi_GetModelJson_CodeDeclToJsonAbi_GetModelJson(): string;
function internal_call_CodeDeclToJsonAbi_GenerateAll_CodeDeclToJsonAbi_GenerateAll(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPascalServiceCode_CodeDeclToJsonAbi_GetLastPascalServiceCode(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPascalServiceReadme_CodeDeclToJsonAbi_GetLastPascalServiceReadme(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPascalCallCode_CodeDeclToJsonAbi_GetLastPascalCallCode(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPascalCallReadme_CodeDeclToJsonAbi_GetLastPascalCallReadme(): string;
function internal_call_CodeDeclToJsonAbi_GetLastJsCallCode_CodeDeclToJsonAbi_GetLastJsCallCode(): string;
function internal_call_CodeDeclToJsonAbi_GetLastJsCallReadme_CodeDeclToJsonAbi_GetLastJsCallReadme(): string;
function internal_call_CodeDeclToJsonAbi_GetLastJsTestHtml_CodeDeclToJsonAbi_GetLastJsTestHtml(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPythonServiceCode_CodeDeclToJsonAbi_GetLastPythonServiceCode(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPythonServiceReadme_CodeDeclToJsonAbi_GetLastPythonServiceReadme(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPythonCallCode_CodeDeclToJsonAbi_GetLastPythonCallCode(): string;
function internal_call_CodeDeclToJsonAbi_GetLastPythonCallReadme_CodeDeclToJsonAbi_GetLastPythonCallReadme(): string;
function internal_call_CodeDeclToJsonAbi_GetLastCppServiceHeader_CodeDeclToJsonAbi_GetLastCppServiceHeader(): string;
function internal_call_CodeDeclToJsonAbi_GetLastCppServiceImpl_CodeDeclToJsonAbi_GetLastCppServiceImpl(): string;
function internal_call_CodeDeclToJsonAbi_GetLastCppServiceReadme_CodeDeclToJsonAbi_GetLastCppServiceReadme(): string;
function internal_call_CodeDeclToJsonAbi_GetLastCppCallHeader_CodeDeclToJsonAbi_GetLastCppCallHeader(): string;
function internal_call_CodeDeclToJsonAbi_GetLastCppCallImpl_CodeDeclToJsonAbi_GetLastCppCallImpl(): string;
function internal_call_CodeDeclToJsonAbi_GetLastCppCallReadme_CodeDeclToJsonAbi_GetLastCppCallReadme(): string;

implementation

uses
  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  code_decl_to_abi_json_frm;   // 用于访问全局 GUI 表单实例 code_decl_to_abi_json_form


// Forward declarations for all API callbacks
function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;
procedure Callback_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_SetModelJson_CodeDeclToJsonAbi_SetModelJson(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetSourceJson_CodeDeclToJsonAbi_GetSourceJson(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetModelJson_CodeDeclToJsonAbi_GetModelJson(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GenerateAll_CodeDeclToJsonAbi_GenerateAll(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPascalServiceCode_CodeDeclToJsonAbi_GetLastPascalServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPascalServiceReadme_CodeDeclToJsonAbi_GetLastPascalServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPascalCallCode_CodeDeclToJsonAbi_GetLastPascalCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPascalCallReadme_CodeDeclToJsonAbi_GetLastPascalCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastJsCallCode_CodeDeclToJsonAbi_GetLastJsCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastJsCallReadme_CodeDeclToJsonAbi_GetLastJsCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastJsTestHtml_CodeDeclToJsonAbi_GetLastJsTestHtml(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPythonServiceCode_CodeDeclToJsonAbi_GetLastPythonServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPythonServiceReadme_CodeDeclToJsonAbi_GetLastPythonServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPythonCallCode_CodeDeclToJsonAbi_GetLastPythonCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastPythonCallReadme_CodeDeclToJsonAbi_GetLastPythonCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastCppServiceHeader_CodeDeclToJsonAbi_GetLastCppServiceHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastCppServiceImpl_CodeDeclToJsonAbi_GetLastCppServiceImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastCppServiceReadme_CodeDeclToJsonAbi_GetLastCppServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastCppCallHeader_CodeDeclToJsonAbi_GetLastCppCallHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastCppCallImpl_CodeDeclToJsonAbi_GetLastCppCallImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetLastCppCallReadme_CodeDeclToJsonAbi_GetLastCppCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;


// =============================================================================
// JSON 辅助
// =============================================================================

function JsonStatusOk: string;
begin
  Result := '{"status":"ok"}';
end;

function JsonError(const Msg: string): string;
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

function JsonStatusOkWithUnit(const UnitName: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['status'] := 'ok';
    jo.S['unit_name'] := UnitName;
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
end;


// =============================================================================
// internal_call_CodeDeclToJsonAbi_SetSourceCode_...
// =============================================================================
function internal_call_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(Source: string; Language: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    lang: string;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;
    lang := LowerCase(Trim(Language));
    if lang = 'pascal' then
    begin
      // Simulate: switch to Pascal language (combo item 1 -> slPascal).
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 1;
      code_decl_to_abi_json_form.LanguageSelectorChange(code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else if lang = 'c' then
    begin
      // Simulate: switch to C language (combo item 2 -> slC).
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 2;
      code_decl_to_abi_json_form.LanguageSelectorChange(code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else
    begin
      Result := JsonError('Unsupported language. Use pascal or c.');
      Exit;
    end;

    // Simulate: fill the source editor with the supplied Source text.
    code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;

    // Simulate: switch the UI to the source-code tab.
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.SourceCodeTabSheet;

    Result := JsonStatusOk;
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  var
    lang: string;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;
    lang := LowerCase(Trim(Language));
    if lang = 'pascal' then
    begin
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 1;
      code_decl_to_abi_json_form.LanguageSelectorChange(code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else if lang = 'c' then
    begin
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 2;
      code_decl_to_abi_json_form.LanguageSelectorChange(code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else
    begin
      temp_ := JsonError('Unsupported language. Use pascal or c.');
      Exit;
    end;
    code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.SourceCodeTabSheet;
    temp_ := JsonStatusOk;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_SetModelJson_...
// =============================================================================
function internal_call_CodeDeclToJsonAbi_SetModelJson_CodeDeclToJsonAbi_SetModelJson(ModelJson: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    jo: TZ_JsonObject;
    unitName: string;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;
    if Trim(ModelJson) = '' then
    begin
      Result := JsonError('Empty model JSON');
      Exit;
    end;

    // Validate that the incoming JSON is a well-formed object.
    jo := TZ_JsonObject.Create;
    try
      if not jo.ParseText(ModelJson) then
      begin
        Result := JsonError('Invalid model JSON');
        Exit;
      end;
      unitName := jo.S['UnitName'];
    finally
      jo.Free;
    end;

    // Simulate: fill the model-JSON editor.
    code_decl_to_abi_json_form.ModelJsonEditor.Text := ModelJson;

    // Simulate: switch the UI to the model-JSON tab.
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.ModelJsonTabSheet;

    Result := JsonStatusOkWithUnit(unitName);
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  var
    jo: TZ_JsonObject;
    unitName: string;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;
    if Trim(ModelJson) = '' then
    begin
      temp_ := JsonError('Empty model JSON');
      Exit;
    end;
    jo := TZ_JsonObject.Create;
    try
      if not jo.ParseText(ModelJson) then
      begin
        temp_ := JsonError('Invalid model JSON');
        Exit;
      end;
      unitName := jo.S['UnitName'];
    finally
      jo.Free;
    end;
    code_decl_to_abi_json_form.ModelJsonEditor.Text := ModelJson;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.ModelJsonTabSheet;
    temp_ := JsonStatusOkWithUnit(unitName);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_GetSourceJson_...
// =============================================================================
function internal_call_CodeDeclToJsonAbi_GetSourceJson_CodeDeclToJsonAbi_GetSourceJson(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := '';
      Exit;
    end;
    // Simulate: read the source-JSON editor.
    Result := code_decl_to_abi_json_form.SourceJsonEditor.Text;
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := '';
      Exit;
    end;
    temp_ := code_decl_to_abi_json_form.SourceJsonEditor.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_GetModelJson_...
// =============================================================================
function internal_call_CodeDeclToJsonAbi_GetModelJson_CodeDeclToJsonAbi_GetModelJson(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := '';
      Exit;
    end;
    // Simulate: read the model-JSON editor.
    Result := code_decl_to_abi_json_form.ModelJsonEditor.Text;
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := '';
      Exit;
    end;
    temp_ := code_decl_to_abi_json_form.ModelJsonEditor.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_GenerateAll_...
//
// Simulated click sequence:
//   1) ParseSourceToJsonClick   (source   -> source JSON)
//   2) NormalizeJsonToModelClick (source JSON -> model JSON)
//   3) GenerateAllSourcesClick  (model JSON  -> 17 artifacts)
// After each step the UI is switched to the corresponding tab sheet.
// =============================================================================
function internal_call_CodeDeclToJsonAbi_GenerateAll_CodeDeclToJsonAbi_GenerateAll(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    modelJo: TZ_JsonObject;
    unitName: string;
    files: TZ_JsonObject;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;

    // Require at least source text or model JSON to begin.
    if (Trim(code_decl_to_abi_json_form.SourceCodeEditor.Text) = '')
       and (Trim(code_decl_to_abi_json_form.ModelJsonEditor.Text) = '') then
    begin
      Result := JsonError('No source text or model JSON in session. Call SetSourceCode or SetModelJson first.');
      Exit;
    end;

    // Step 1: if the source editor is non-empty, simulate clicking ParseSourceToJson.
    if Trim(code_decl_to_abi_json_form.SourceCodeEditor.Text) <> '' then
    begin
      code_decl_to_abi_json_form.ParseSourceToJsonClick(code_decl_to_abi_json_form.ParseSourceToJsonButton);
      // ParseSourceToJsonClick internally switches MainPageControl to SourceJsonTabSheet.
    end;

    // Step 2: if the source-JSON editor is non-empty, simulate clicking NormalizeJsonToModel.
    if Trim(code_decl_to_abi_json_form.SourceJsonEditor.Text) <> '' then
    begin
      code_decl_to_abi_json_form.NormalizeJsonToModelClick(code_decl_to_abi_json_form.NormalizeJsonToModelButton);
      // NormalizeJsonToModelClick internally switches MainPageControl to ModelJsonTabSheet.
    end;

    // Step 3: simulate clicking GenerateAllSources (emits all 17 artifacts into the final editors).
    if Trim(code_decl_to_abi_json_form.ModelJsonEditor.Text) = '' then
    begin
      Result := JsonError('Model JSON is empty. Cannot generate.');
      Exit;
    end;

    code_decl_to_abi_json_form.GenerateAllSourcesClick(code_decl_to_abi_json_form.GenerateAllSourcesButton);

    // Extract UnitName from the model JSON, used to assemble the file manifest.
    modelJo := TZ_JsonObject.Create;
    try
      unitName := '';
      if modelJo.ParseText(code_decl_to_abi_json_form.ModelJsonEditor.Text) then
        unitName := modelJo.S['UnitName'];
    finally
      modelJo.Free;
    end;

    // Simulate: switch to FinalSourceTabSheet so the final artifacts are visible.
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;

    // Build the file manifest.
    files := TZ_JsonObject.Create;
    try
      files.S['pascal_service_code']   := unitName + '_http_json_service_unit.pas';
      files.S['pascal_service_readme'] := unitName + '_http_json_service_pascal.md';
      files.S['pascal_call_code']      := unitName + '_http_json_call_unit.pas';
      files.S['pascal_call_readme']    := unitName + '_http_json_call_pascal.md';
      files.S['js_call_code']          := unitName + '_http_json_call.js';
      files.S['js_call_readme']        := unitName + '_http_json_call_js.md';
      files.S['js_test_html']          := unitName + '_http_json_call_test.html';
      files.S['python_service_code']   := unitName + '_http_json_service.py';
      files.S['python_service_readme'] := unitName + '_http_json_service_python.md';
      files.S['python_call_code']      := unitName + '_http_json_call.py';
      files.S['python_call_readme']    := unitName + '_http_json_call_python.md';
      files.S['cpp_service_header']    := unitName + '_http_json_service.hpp';
      files.S['cpp_service_impl']      := unitName + '_http_json_service.cpp';
      files.S['cpp_service_readme']    := unitName + '_http_json_service_cpp.md';
      files.S['cpp_call_header']       := unitName + '_http_json_call.hpp';
      files.S['cpp_call_impl']         := unitName + '_http_json_call.cpp';
      files.S['cpp_call_readme']       := unitName + '_http_json_call_cpp.md';

      Result := '{"status":"ok","unit_name":"' + unitName + '","files":' + files.ToJSONString(False) + '}';
    finally
      files.Free;
    end;
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  var
    modelJo: TZ_JsonObject;
    unitName: string;
    files: TZ_JsonObject;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;

    if (Trim(code_decl_to_abi_json_form.SourceCodeEditor.Text) = '')
       and (Trim(code_decl_to_abi_json_form.ModelJsonEditor.Text) = '') then
    begin
      temp_ := JsonError('No source text or model JSON in session. Call SetSourceCode or SetModelJson first.');
      Exit;
    end;

    if Trim(code_decl_to_abi_json_form.SourceCodeEditor.Text) <> '' then
      code_decl_to_abi_json_form.ParseSourceToJsonClick(code_decl_to_abi_json_form.ParseSourceToJsonButton);

    if Trim(code_decl_to_abi_json_form.SourceJsonEditor.Text) <> '' then
      code_decl_to_abi_json_form.NormalizeJsonToModelClick(code_decl_to_abi_json_form.NormalizeJsonToModelButton);

    if Trim(code_decl_to_abi_json_form.ModelJsonEditor.Text) = '' then
    begin
      temp_ := JsonError('Model JSON is empty. Cannot generate.');
      Exit;
    end;

    code_decl_to_abi_json_form.GenerateAllSourcesClick(code_decl_to_abi_json_form.GenerateAllSourcesButton);

    modelJo := TZ_JsonObject.Create;
    try
      unitName := '';
      if modelJo.ParseText(code_decl_to_abi_json_form.ModelJsonEditor.Text) then
        unitName := modelJo.S['UnitName'];
    finally
      modelJo.Free;
    end;

    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;

    files := TZ_JsonObject.Create;
    try
      files.S['pascal_service_code']   := unitName + '_http_json_service_unit.pas';
      files.S['pascal_service_readme'] := unitName + '_http_json_service_pascal.md';
      files.S['pascal_call_code']      := unitName + '_http_json_call_unit.pas';
      files.S['pascal_call_readme']    := unitName + '_http_json_call_pascal.md';
      files.S['js_call_code']          := unitName + '_http_json_call.js';
      files.S['js_call_readme']        := unitName + '_http_json_call_js.md';
      files.S['js_test_html']          := unitName + '_http_json_call_test.html';
      files.S['python_service_code']   := unitName + '_http_json_service.py';
      files.S['python_service_readme'] := unitName + '_http_json_service_python.md';
      files.S['python_call_code']      := unitName + '_http_json_call.py';
      files.S['python_call_readme']    := unitName + '_http_json_call_python.md';
      files.S['cpp_service_header']    := unitName + '_http_json_service.hpp';
      files.S['cpp_service_impl']      := unitName + '_http_json_service.cpp';
      files.S['cpp_service_readme']    := unitName + '_http_json_service_cpp.md';
      files.S['cpp_call_header']       := unitName + '_http_json_call.hpp';
      files.S['cpp_call_impl']         := unitName + '_http_json_call.cpp';
      files.S['cpp_call_readme']       := unitName + '_http_json_call_cpp.md';

      temp_ := '{"status":"ok","unit_name":"' + unitName + '","files":' + files.ToJSONString(False) + '}';
    finally
      files.Free;
    end;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// The 17 readers below simulate "read the corresponding final_*_Edit.Lines.Text".
// Each reader switches to the corresponding tab sheet first, then reads the text,
// so the visible UI state and the returned value stay consistent.
// =============================================================================

// ---- Pascal service code ----
function internal_call_CodeDeclToJsonAbi_GetLastPascalServiceCode_CodeDeclToJsonAbi_GetLastPascalServiceCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalServiceTabSheet;
    Result := code_decl_to_abi_json_form.PascalServiceCodeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.PascalServiceCodeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Pascal service readme ----
function internal_call_CodeDeclToJsonAbi_GetLastPascalServiceReadme_CodeDeclToJsonAbi_GetLastPascalServiceReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalServiceTabSheet;
    Result := code_decl_to_abi_json_form.PascalServiceReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.PascalServiceReadmeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Pascal call code ----
function internal_call_CodeDeclToJsonAbi_GetLastPascalCallCode_CodeDeclToJsonAbi_GetLastPascalCallCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalCallTabSheet;
    Result := code_decl_to_abi_json_form.PascalCallCodeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalCallTabSheet;
    temp_ := code_decl_to_abi_json_form.PascalCallCodeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Pascal call readme ----
function internal_call_CodeDeclToJsonAbi_GetLastPascalCallReadme_CodeDeclToJsonAbi_GetLastPascalCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalCallTabSheet;
    Result := code_decl_to_abi_json_form.PascalCallReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPascalCallTabSheet;
    temp_ := code_decl_to_abi_json_form.PascalCallReadmeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- JS call code ----
function internal_call_CodeDeclToJsonAbi_GetLastJsCallCode_CodeDeclToJsonAbi_GetLastJsCallCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpJavaScriptCallTabSheet;
    Result := code_decl_to_abi_json_form.JavaScriptCallCodeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpJavaScriptCallTabSheet;
    temp_ := code_decl_to_abi_json_form.JavaScriptCallCodeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- JS call readme ----
function internal_call_CodeDeclToJsonAbi_GetLastJsCallReadme_CodeDeclToJsonAbi_GetLastJsCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpJavaScriptCallTabSheet;
    Result := code_decl_to_abi_json_form.JavaScriptCallReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpJavaScriptCallTabSheet;
    temp_ := code_decl_to_abi_json_form.JavaScriptCallReadmeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- JS test html ----
function internal_call_CodeDeclToJsonAbi_GetLastJsTestHtml_CodeDeclToJsonAbi_GetLastJsTestHtml(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpJavaScriptTestTabSheet;
    Result := code_decl_to_abi_json_form.JavaScriptTestHtmlEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpJavaScriptTestTabSheet;
    temp_ := code_decl_to_abi_json_form.JavaScriptTestHtmlEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Python service code ----
function internal_call_CodeDeclToJsonAbi_GetLastPythonServiceCode_CodeDeclToJsonAbi_GetLastPythonServiceCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonServiceTabSheet;
    Result := code_decl_to_abi_json_form.PythonServiceCodeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.PythonServiceCodeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Python service readme ----
function internal_call_CodeDeclToJsonAbi_GetLastPythonServiceReadme_CodeDeclToJsonAbi_GetLastPythonServiceReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonServiceTabSheet;
    Result := code_decl_to_abi_json_form.PythonServiceReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.PythonServiceReadmeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Python call code ----
function internal_call_CodeDeclToJsonAbi_GetLastPythonCallCode_CodeDeclToJsonAbi_GetLastPythonCallCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonCallTabSheet;
    Result := code_decl_to_abi_json_form.PythonCallCodeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonCallTabSheet;
    temp_ := code_decl_to_abi_json_form.PythonCallCodeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Python call readme ----
function internal_call_CodeDeclToJsonAbi_GetLastPythonCallReadme_CodeDeclToJsonAbi_GetLastPythonCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonCallTabSheet;
    Result := code_decl_to_abi_json_form.PythonCallReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpPythonCallTabSheet;
    temp_ := code_decl_to_abi_json_form.PythonCallReadmeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- C++ service header ----
function internal_call_CodeDeclToJsonAbi_GetLastCppServiceHeader_CodeDeclToJsonAbi_GetLastCppServiceHeader(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppServiceTabSheet;
    Result := code_decl_to_abi_json_form.CppServiceHeaderEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.CppServiceHeaderEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- C++ service impl ----
function internal_call_CodeDeclToJsonAbi_GetLastCppServiceImpl_CodeDeclToJsonAbi_GetLastCppServiceImpl(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppServiceTabSheet;
    Result := code_decl_to_abi_json_form.CppServiceImplEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.CppServiceImplEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- C++ service readme ----
function internal_call_CodeDeclToJsonAbi_GetLastCppServiceReadme_CodeDeclToJsonAbi_GetLastCppServiceReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppServiceTabSheet;
    Result := code_decl_to_abi_json_form.CppServiceReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppServiceTabSheet;
    temp_ := code_decl_to_abi_json_form.CppServiceReadmeEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- C++ call header ----
function internal_call_CodeDeclToJsonAbi_GetLastCppCallHeader_CodeDeclToJsonAbi_GetLastCppCallHeader(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppCallTabSheet;
    Result := code_decl_to_abi_json_form.CppCallHeaderEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppCallTabSheet;
    temp_ := code_decl_to_abi_json_form.CppCallHeaderEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- C++ call impl ----
function internal_call_CodeDeclToJsonAbi_GetLastCppCallImpl_CodeDeclToJsonAbi_GetLastCppCallImpl(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppCallTabSheet;
    Result := code_decl_to_abi_json_form.CppCallImplEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppCallTabSheet;
    temp_ := code_decl_to_abi_json_form.CppCallImplEditor.Lines.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- C++ call readme ----
function internal_call_CodeDeclToJsonAbi_GetLastCppCallReadme_CodeDeclToJsonAbi_GetLastCppCallReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if code_decl_to_abi_json_form = nil then begin Result := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppCallTabSheet;
    Result := code_decl_to_abi_json_form.CppCallReadmeEditor.Lines.Text;
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
    if code_decl_to_abi_json_form = nil then begin temp_ := ''; Exit; end;
    code_decl_to_abi_json_form.MainPageControl.ActivePage := code_decl_to_abi_json_form.FinalSourceTabSheet;
    code_decl_to_abi_json_form.FinalSourcePageControl.ActivePage := code_decl_to_abi_json_form.HttpCppCallTabSheet;
    temp_ := code_decl_to_abi_json_form.CppCallReadmeEditor.Lines.Text;
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
// ---- CodeDeclToJsonAbi_SetSourceCode (API: CodeDeclToJsonAbi_SetSourceCode) ----
procedure Callback_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_SetSourceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_SetSourceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_SetSourceCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_SetSourceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_SetSourceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    Source := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_SetSourceCode] called with %s -> result: %s', [Source, Language, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToJsonAbi_SetSourceCode] called with %s', [Source, Language]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_SetSourceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_SetSourceCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_SetModelJson (API: CodeDeclToJsonAbi_SetModelJson) ----
procedure Callback_CodeDeclToJsonAbi_SetModelJson_CodeDeclToJsonAbi_SetModelJson(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  ModelJson: string;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToJsonAbi_SetModelJson] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_SetModelJson] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_SetModelJson] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_SetModelJson] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_SetModelJson] Error: ' + errMsg);
      end;
      Exit;
    end;
    ModelJson := jo.S['ModelJson'];

    ret := internal_call_CodeDeclToJsonAbi_SetModelJson_CodeDeclToJsonAbi_SetModelJson(ModelJson);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_SetModelJson] called with %s -> result: %s', [ModelJson, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToJsonAbi_SetModelJson] called with %s', [ModelJson]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_SetModelJson] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_SetModelJson] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetSourceJson (API: CodeDeclToJsonAbi_GetSourceJson) ----
procedure Callback_CodeDeclToJsonAbi_GetSourceJson_CodeDeclToJsonAbi_GetSourceJson(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetSourceJson] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetSourceJson] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetSourceJson] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetSourceJson] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetSourceJson] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetSourceJson_CodeDeclToJsonAbi_GetSourceJson();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetSourceJson] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetSourceJson] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetSourceJson] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetSourceJson] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetModelJson (API: CodeDeclToJsonAbi_GetModelJson) ----
procedure Callback_CodeDeclToJsonAbi_GetModelJson_CodeDeclToJsonAbi_GetModelJson(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetModelJson] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetModelJson] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetModelJson] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetModelJson] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetModelJson] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetModelJson_CodeDeclToJsonAbi_GetModelJson();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetModelJson] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetModelJson] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetModelJson] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetModelJson] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GenerateAll (API: CodeDeclToJsonAbi_GenerateAll) ----
procedure Callback_CodeDeclToJsonAbi_GenerateAll_CodeDeclToJsonAbi_GenerateAll(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GenerateAll] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GenerateAll] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GenerateAll] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GenerateAll] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GenerateAll] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GenerateAll_CodeDeclToJsonAbi_GenerateAll();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GenerateAll] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GenerateAll] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GenerateAll] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GenerateAll] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPascalServiceCode (API: CodeDeclToJsonAbi_GetLastPascalServiceCode) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPascalServiceCode_CodeDeclToJsonAbi_GetLastPascalServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPascalServiceCode_CodeDeclToJsonAbi_GetLastPascalServiceCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPascalServiceReadme (API: CodeDeclToJsonAbi_GetLastPascalServiceReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPascalServiceReadme_CodeDeclToJsonAbi_GetLastPascalServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPascalServiceReadme_CodeDeclToJsonAbi_GetLastPascalServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalServiceReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPascalCallCode (API: CodeDeclToJsonAbi_GetLastPascalCallCode) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPascalCallCode_CodeDeclToJsonAbi_GetLastPascalCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPascalCallCode_CodeDeclToJsonAbi_GetLastPascalCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPascalCallReadme (API: CodeDeclToJsonAbi_GetLastPascalCallReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPascalCallReadme_CodeDeclToJsonAbi_GetLastPascalCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPascalCallReadme_CodeDeclToJsonAbi_GetLastPascalCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPascalCallReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastJsCallCode (API: CodeDeclToJsonAbi_GetLastJsCallCode) ----
procedure Callback_CodeDeclToJsonAbi_GetLastJsCallCode_CodeDeclToJsonAbi_GetLastJsCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastJsCallCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastJsCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastJsCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastJsCallCode_CodeDeclToJsonAbi_GetLastJsCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastJsCallCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastJsCallCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastJsCallReadme (API: CodeDeclToJsonAbi_GetLastJsCallReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastJsCallReadme_CodeDeclToJsonAbi_GetLastJsCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastJsCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastJsCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastJsCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastJsCallReadme_CodeDeclToJsonAbi_GetLastJsCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastJsCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastJsCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsCallReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastJsTestHtml (API: CodeDeclToJsonAbi_GetLastJsTestHtml) ----
procedure Callback_CodeDeclToJsonAbi_GetLastJsTestHtml_CodeDeclToJsonAbi_GetLastJsTestHtml(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastJsTestHtml] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastJsTestHtml] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsTestHtml] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastJsTestHtml] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsTestHtml] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastJsTestHtml_CodeDeclToJsonAbi_GetLastJsTestHtml();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastJsTestHtml] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastJsTestHtml] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastJsTestHtml] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastJsTestHtml] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPythonServiceCode (API: CodeDeclToJsonAbi_GetLastPythonServiceCode) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPythonServiceCode_CodeDeclToJsonAbi_GetLastPythonServiceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPythonServiceCode_CodeDeclToJsonAbi_GetLastPythonServiceCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPythonServiceReadme (API: CodeDeclToJsonAbi_GetLastPythonServiceReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPythonServiceReadme_CodeDeclToJsonAbi_GetLastPythonServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPythonServiceReadme_CodeDeclToJsonAbi_GetLastPythonServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonServiceReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPythonCallCode (API: CodeDeclToJsonAbi_GetLastPythonCallCode) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPythonCallCode_CodeDeclToJsonAbi_GetLastPythonCallCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPythonCallCode_CodeDeclToJsonAbi_GetLastPythonCallCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastPythonCallReadme (API: CodeDeclToJsonAbi_GetLastPythonCallReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastPythonCallReadme_CodeDeclToJsonAbi_GetLastPythonCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastPythonCallReadme_CodeDeclToJsonAbi_GetLastPythonCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastPythonCallReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastCppServiceHeader (API: CodeDeclToJsonAbi_GetLastCppServiceHeader) ----
procedure Callback_CodeDeclToJsonAbi_GetLastCppServiceHeader_CodeDeclToJsonAbi_GetLastCppServiceHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastCppServiceHeader_CodeDeclToJsonAbi_GetLastCppServiceHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceHeader] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceHeader] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceHeader] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastCppServiceImpl (API: CodeDeclToJsonAbi_GetLastCppServiceImpl) ----
procedure Callback_CodeDeclToJsonAbi_GetLastCppServiceImpl_CodeDeclToJsonAbi_GetLastCppServiceImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastCppServiceImpl_CodeDeclToJsonAbi_GetLastCppServiceImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceImpl] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceImpl] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceImpl] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastCppServiceReadme (API: CodeDeclToJsonAbi_GetLastCppServiceReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastCppServiceReadme_CodeDeclToJsonAbi_GetLastCppServiceReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastCppServiceReadme_CodeDeclToJsonAbi_GetLastCppServiceReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppServiceReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastCppCallHeader (API: CodeDeclToJsonAbi_GetLastCppCallHeader) ----
procedure Callback_CodeDeclToJsonAbi_GetLastCppCallHeader_CodeDeclToJsonAbi_GetLastCppCallHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastCppCallHeader] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallHeader] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallHeader] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastCppCallHeader_CodeDeclToJsonAbi_GetLastCppCallHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastCppCallHeader] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallHeader] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallHeader] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallHeader] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastCppCallImpl (API: CodeDeclToJsonAbi_GetLastCppCallImpl) ----
procedure Callback_CodeDeclToJsonAbi_GetLastCppCallImpl_CodeDeclToJsonAbi_GetLastCppCallImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastCppCallImpl] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallImpl] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallImpl] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastCppCallImpl_CodeDeclToJsonAbi_GetLastCppCallImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastCppCallImpl] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallImpl] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallImpl] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallImpl] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetLastCppCallReadme (API: CodeDeclToJsonAbi_GetLastCppCallReadme) ----
procedure Callback_CodeDeclToJsonAbi_GetLastCppCallReadme_CodeDeclToJsonAbi_GetLastCppCallReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetLastCppCallReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_GetLastCppCallReadme_CodeDeclToJsonAbi_GetLastCppCallReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetLastCppCallReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetLastCppCallReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetLastCppCallReadme] Exception: ' + E.Message);
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
    // Tool: CodeDeclToJsonAbi_SetSourceCode -> CodeDeclToJsonAbi_SetSourceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_SetSourceCode';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 1/3 - Store source text. Stores the source text and its SOURCE language into the generator. This is a setup call: it does NOT generate any artifact and does NOT determine which target language or side will be produced. After this call succeeds, you MUST call CodeDeclToJsonAbi_GenerateAll to actually produce output, then call the Step-3 readers for whichever artifacts you want. The stored source stays in effect for the rest of the session. To switch target languages you do NOT call this tool again; you just call another Step-3 reader after the same GenerateAll. Source: complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. Language: the SOURCE language of the text passed in Source. Accepted values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively. Do NOT pass a target language such as '#39'python'#39' or '#39'cpp'#39'; target languages are selected by which Step-3 reader you call after GenerateAll. Return value: JSON string. On success: {"status":"ok","unit_name":"<parsed unit name>"} On failure: {"error":"<message>"} )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_SetSourceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'complete source text. For Language='#39'pascal'#39' pass a full'#10'          Pascal unit that starts with a unit declaration and contains'#10'          an interface section. For Language='#39'c'#39' pass a full C header'#10'          that starts with the include guard and contains the function'#10'          prototypes.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'the SOURCE language of the text passed in Source. Accepted'#10'          values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively.'#10'          Do NOT pass a target language such as '#39'python'#39' or '#39'cpp'#39';'#10'          target languages are selected by which Step-3 reader you'#10'          call after GenerateAll.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_SetSourceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_SetSourceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_SetModelJson -> CodeDeclToJsonAbi_SetModelJson
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_SetModelJson';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 1/3 - Store an LV1 model JSON directly. Alternative to CodeDeclToJsonAbi_SetSourceCode for callers that already have the LV1 model JSON. Use this only if you produced the Model JSON yourself (for example, via CodeDeclToJsonAbi_GetModelJson in an earlier session, or via any other tool that emits the same shape). This bypasses both the source-text parser and the JSON normalizer. It does NOT generate any artifact; call GenerateAll afterwards. ModelJson: an LV1 model JSON document. Must be the output shape of TPascal_Func_Model.SaveToJson, as produced by CodeDeclToJsonAbi_GetModelJson. Return value: JSON string. On success: {"status":"ok","unit_name":"<unit name from model>"} On failure: {"error":"<message>"} )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_SetModelJson';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['ModelJson'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'an LV1 model JSON document. Must be the output shape of'#10'             TPascal_Func_Model.SaveToJson, as produced by'#10'             CodeDeclToJsonAbi_GetModelJson.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('ModelJson');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_SetModelJson')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_SetModelJson');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetSourceJson -> CodeDeclToJsonAbi_GetSourceJson
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetSourceJson';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Inspect the Source JSON. Returns the Source JSON produced by the parser from the source text stored by the most recent successful CodeDeclToJsonAbi_SetSourceCode call. Pure reader: never triggers a new conversion. Returns '#39#39' if SetSourceCode has not been called successfully yet, or if the most recent Step-1 call was SetModelJson (which bypasses the parser and therefore does not produce a Source JSON). No parameters. Return value: the Source JSON text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetSourceJson';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetSourceJson')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetSourceJson');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetModelJson -> CodeDeclToJsonAbi_GetModelJson
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetModelJson';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Inspect the Model JSON. Returns the LV1 model JSON produced by the normalizer from the Source JSON. Pure reader: never triggers a new conversion. Returns '#39#39' if neither SetSourceCode nor SetModelJson has been called successfully yet. If SetModelJson was the most recent Step-1 call, this reader returns the exact JSON that was passed to SetModelJson. If SetSourceCode was the most recent Step-1 call, this reader returns the Model JSON that the normalizer produced from the parsed source. No parameters. Return value: the Model JSON text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetModelJson';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetModelJson')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetModelJson');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GenerateAll -> CodeDeclToJsonAbi_GenerateAll
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GenerateAll';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 2/3 - Generate all 17 artifacts. Runs the seven generators twice each (once for the code artifact(s), once for the README artifact) against the currently stored Model JSON, and caches all 17 results. After this call the Step-3 readers return the freshly generated text. Prerequisite: either CodeDeclToJsonAbi_SetSourceCode or CodeDeclToJsonAbi_SetModelJson must have succeeded earlier in this session. If neither has, this call returns an error. Calling GenerateAll multiple times is safe; each call re-runs the seven generators against the current Model JSON and replaces the cached outputs. This is also the correct way to refresh the cache after a second SetSourceCode / SetModelJson call. No parameters. Return value: JSON string describing the produced files. On success: {"status":"ok","unit_name":"<unit>", "files":{ "pascal_service_code":    "<...>.pas", "pascal_service_readme":  "<...>.md", "pascal_call_code":       "<...>.pas", "pascal_call_readme":     "<...>.md", "js_call_code":           "<...>.js", "js_call_readme":         "<...>.md", "js_test_html":           "<...>.html", "python_service_code":    "<...>.py", "python_service_readme":  "<...>.md", "python_call_code":       "<...>.py", "python_call_readme":     "<...>.md", "cpp_service_header":     "<...>.hpp", "cpp_service_impl":       "<...>.cpp", "cpp_service_readme":     "<...>.md", "cpp_call_header":        "<...>.hpp", "cpp_call_impl":          "<...>.cpp", "cpp_call_readme":        "<...>.md" }} On failure: {"error":"<message>"} )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GenerateAll';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GenerateAll')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GenerateAll');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPascalServiceCode -> CodeDeclToJsonAbi_GetLastPascalServiceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPascalServiceCode';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Pascal service reader (code). Returns the full text of the Pascal HTTP/JSON service unit produced by the most recent successful GenerateAll. Pure reader: never triggers a new conversion, never requires calling SetSourceCode again. Prerequisite: GenerateAll must have succeeded first. If it has not, this returns an empty string. No parameters. Return value: the Pascal service unit text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPascalServiceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPascalServiceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPascalServiceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPascalServiceReadme -> CodeDeclToJsonAbi_GetLastPascalServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPascalServiceReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Pascal service reader (README). Returns the full text of the Markdown README paired with the Pascal service unit. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPascalServiceReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPascalServiceReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPascalServiceReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPascalCallCode -> CodeDeclToJsonAbi_GetLastPascalCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPascalCallCode';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Pascal call-side reader (code). Returns the full text of the Pascal HTTP/JSON call-side unit produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Pascal call-side unit text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPascalCallCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPascalCallCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPascalCallCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPascalCallReadme -> CodeDeclToJsonAbi_GetLastPascalCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPascalCallReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Pascal call-side reader (README). Returns the full text of the Markdown README paired with the Pascal call-side unit. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPascalCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPascalCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPascalCallReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastJsCallCode -> CodeDeclToJsonAbi_GetLastJsCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastJsCallCode';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - JS call-side reader (code). Returns the full text of the browser-side JavaScript client produced by the most recent successful GenerateAll. The text is a standalone IIFE library that attaches itself to window.<UnitName>Api (or globalThis.<UnitName>Api when window is unavailable). Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the JavaScript source, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastJsCallCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastJsCallCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastJsCallCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastJsCallReadme -> CodeDeclToJsonAbi_GetLastJsCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastJsCallReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - JS call-side reader (README). Returns the full text of the Markdown README paired with the browser JavaScript client. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastJsCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastJsCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastJsCallReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastJsTestHtml -> CodeDeclToJsonAbi_GetLastJsTestHtml
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastJsTestHtml';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - JS call-side reader (HTML test page). Returns the full text of the self-contained HTML test page produced by the most recent successful GenerateAll. The page embeds the JS client library and renders one interactive test card per exposed routine. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the HTML document, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastJsTestHtml';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastJsTestHtml')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastJsTestHtml');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPythonServiceCode -> CodeDeclToJsonAbi_GetLastPythonServiceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPythonServiceCode';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Python service reader (code). Returns the full text of the Python HTTP/JSON service module produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Python module source, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPythonServiceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPythonServiceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPythonServiceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPythonServiceReadme -> CodeDeclToJsonAbi_GetLastPythonServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPythonServiceReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Python service reader (README). Returns the full text of the Markdown README paired with the Python service module. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPythonServiceReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPythonServiceReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPythonServiceReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPythonCallCode -> CodeDeclToJsonAbi_GetLastPythonCallCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPythonCallCode';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Python call-side reader (code). Returns the full text of the Python HTTP/JSON call-side module produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Python module source, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPythonCallCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPythonCallCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPythonCallCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastPythonCallReadme -> CodeDeclToJsonAbi_GetLastPythonCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastPythonCallReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - Python call-side reader (README). Returns the full text of the Markdown README paired with the Python call-side module. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastPythonCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastPythonCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastPythonCallReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastCppServiceHeader -> CodeDeclToJsonAbi_GetLastCppServiceHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastCppServiceHeader';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - C++ service reader (header). Returns the full text of the C++ HTTP/JSON service header (.hpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the header text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastCppServiceHeader';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastCppServiceHeader')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastCppServiceHeader');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastCppServiceImpl -> CodeDeclToJsonAbi_GetLastCppServiceImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastCppServiceImpl';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - C++ service reader (implementation). Returns the full text of the C++ HTTP/JSON service implementation (.cpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the implementation text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastCppServiceImpl';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastCppServiceImpl')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastCppServiceImpl');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastCppServiceReadme -> CodeDeclToJsonAbi_GetLastCppServiceReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastCppServiceReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - C++ service reader (README). Returns the full text of the Markdown README paired with the C++ service header and implementation. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastCppServiceReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastCppServiceReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastCppServiceReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastCppCallHeader -> CodeDeclToJsonAbi_GetLastCppCallHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastCppCallHeader';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - C++ call-side reader (header). Returns the full text of the C++ HTTP/JSON call-side header (.hpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the header text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastCppCallHeader';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastCppCallHeader')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastCppCallHeader');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastCppCallImpl -> CodeDeclToJsonAbi_GetLastCppCallImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastCppCallImpl';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - C++ call-side reader (implementation). Returns the full text of the C++ HTTP/JSON call-side implementation (.cpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the implementation text, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastCppCallImpl';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastCppCallImpl')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastCppCallImpl');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetLastCppCallReadme -> CodeDeclToJsonAbi_GetLastCppCallReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetLastCppCallReadme';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 3/3 - C++ call-side reader (README). Returns the full text of the Markdown README paired with the C++ call-side header and implementation. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetLastCppCallReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetLastCppCallReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetLastCppCallReadme');
    finally
      ToolDef.Free;
    end;

    Result := (regCount = 22);
    if DEBUG_LOG then
      DoStatus('[RegisterTools] Registered %d out of %d tools.', [regCount, 22]);
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

  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_SetSourceCode', '(* [code_decl_to_json_abi] Step 1/3 - Store source text. Stores the source text and its SOURCE language into the generator. This is a setup call: it does NOT generate any artifact and does NOT determine which target language or side will be produced. After this call succeeds, you MUST call CodeDeclToJsonAbi_GenerateAll to actually produce output, then call the Step-3 readers for whichever artifacts you want. The stored source stays in effect for the rest of the session. To switch target languages you do NOT call this tool again; you just call another Step-3 reader after the same GenerateAll. Source: complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. Language: the SOURCE language of the text passed in Source. Accepted values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively. Do NOT pass a target language such as '#39'python'#39' or '#39'cpp'#39'; target languages are selected by which Step-3 reader you call after GenerateAll. Return value: JSON string. On success: {"status":"ok","unit_name":"<parsed unit name>"} On failure: {"error":"<message>"} )', nil, @Callback_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode);  // Register API: CodeDeclToJsonAbi_SetSourceCode -> CodeDeclToJsonAbi_SetSourceCode
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_SetModelJson', '(* [code_decl_to_json_abi] Step 1/3 - Store an LV1 model JSON directly. Alternative to CodeDeclToJsonAbi_SetSourceCode for callers that already have the LV1 model JSON. Use this only if you produced the Model JSON yourself (for example, via CodeDeclToJsonAbi_GetModelJson in an earlier session, or via any other tool that emits the same shape). This bypasses both the source-text parser and the JSON normalizer. It does NOT generate any artifact; call GenerateAll afterwards. ModelJson: an LV1 model JSON document. Must be the output shape of TPascal_Func_Model.SaveToJson, as produced by CodeDeclToJsonAbi_GetModelJson. Return value: JSON string. On success: {"status":"ok","unit_name":"<unit name from model>"} On failure: {"error":"<message>"} )', nil, @Callback_CodeDeclToJsonAbi_SetModelJson_CodeDeclToJsonAbi_SetModelJson);  // Register API: CodeDeclToJsonAbi_SetModelJson -> CodeDeclToJsonAbi_SetModelJson
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetSourceJson', '(* [code_decl_to_json_abi] Step 3/3 - Inspect the Source JSON. Returns the Source JSON produced by the parser from the source text stored by the most recent successful CodeDeclToJsonAbi_SetSourceCode call. Pure reader: never triggers a new conversion. Returns '#39#39' if SetSourceCode has not been called successfully yet, or if the most recent Step-1 call was SetModelJson (which bypasses the parser and therefore does not produce a Source JSON). No parameters. Return value: the Source JSON text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetSourceJson_CodeDeclToJsonAbi_GetSourceJson);  // Register API: CodeDeclToJsonAbi_GetSourceJson -> CodeDeclToJsonAbi_GetSourceJson
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetModelJson', '(* [code_decl_to_json_abi] Step 3/3 - Inspect the Model JSON. Returns the LV1 model JSON produced by the normalizer from the Source JSON. Pure reader: never triggers a new conversion. Returns '#39#39' if neither SetSourceCode nor SetModelJson has been called successfully yet. If SetModelJson was the most recent Step-1 call, this reader returns the exact JSON that was passed to SetModelJson. If SetSourceCode was the most recent Step-1 call, this reader returns the Model JSON that the normalizer produced from the parsed source. No parameters. Return value: the Model JSON text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetModelJson_CodeDeclToJsonAbi_GetModelJson);  // Register API: CodeDeclToJsonAbi_GetModelJson -> CodeDeclToJsonAbi_GetModelJson
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GenerateAll', '(* [code_decl_to_json_abi] Step 2/3 - Generate all 17 artifacts. Runs the seven generators twice each (once for the code artifact(s), once for the README artifact) against the currently stored Model JSON, and caches all 17 results. After this call the Step-3 readers return the freshly generated text. Prerequisite: either CodeDeclToJsonAbi_SetSourceCode or CodeDeclToJsonAbi_SetModelJson must have succeeded earlier in this session. If neither has, this call returns an error. Calling GenerateAll multiple times is safe; each call re-runs the seven generators against the current Model JSON and replaces the cached outputs. This is also the correct way to refresh the cache after a second SetSourceCode / SetModelJson call. No parameters. Return value: JSON string describing the produced files. On success: {"status":"ok","unit_name":"<unit>", "files":{ "pascal_service_code":    "<...>.pas", "pascal_service_readme":  "<...>.md", "pascal_call_code":       "<...>.pas", "pascal_call_readme":     "<...>.md", "js_call_code":           "<...>.js", "js_call_readme":         "<...>.md", "js_test_html":           "<...>.html", "python_service_code":    "<...>.py", "python_service_readme":  "<...>.md", "python_call_code":       "<...>.py", "python_call_readme":     "<...>.md", "cpp_service_header":     "<...>.hpp", "cpp_service_impl":       "<...>.cpp", "cpp_service_readme":     "<...>.md", "cpp_call_header":        "<...>.hpp", "cpp_call_impl":          "<...>.cpp", "cpp_call_readme":        "<...>.md" }} On failure: {"error":"<message>"} )', nil, @Callback_CodeDeclToJsonAbi_GenerateAll_CodeDeclToJsonAbi_GenerateAll);  // Register API: CodeDeclToJsonAbi_GenerateAll -> CodeDeclToJsonAbi_GenerateAll
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPascalServiceCode', '(* [code_decl_to_json_abi] Step 3/3 - Pascal service reader (code). Returns the full text of the Pascal HTTP/JSON service unit produced by the most recent successful GenerateAll. Pure reader: never triggers a new conversion, never requires calling SetSourceCode again. Prerequisite: GenerateAll must have succeeded first. If it has not, this returns an empty string. No parameters. Return value: the Pascal service unit text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPascalServiceCode_CodeDeclToJsonAbi_GetLastPascalServiceCode);  // Register API: CodeDeclToJsonAbi_GetLastPascalServiceCode -> CodeDeclToJsonAbi_GetLastPascalServiceCode
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPascalServiceReadme', '(* [code_decl_to_json_abi] Step 3/3 - Pascal service reader (README). Returns the full text of the Markdown README paired with the Pascal service unit. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPascalServiceReadme_CodeDeclToJsonAbi_GetLastPascalServiceReadme);  // Register API: CodeDeclToJsonAbi_GetLastPascalServiceReadme -> CodeDeclToJsonAbi_GetLastPascalServiceReadme
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPascalCallCode', '(* [code_decl_to_json_abi] Step 3/3 - Pascal call-side reader (code). Returns the full text of the Pascal HTTP/JSON call-side unit produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Pascal call-side unit text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPascalCallCode_CodeDeclToJsonAbi_GetLastPascalCallCode);  // Register API: CodeDeclToJsonAbi_GetLastPascalCallCode -> CodeDeclToJsonAbi_GetLastPascalCallCode
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPascalCallReadme', '(* [code_decl_to_json_abi] Step 3/3 - Pascal call-side reader (README). Returns the full text of the Markdown README paired with the Pascal call-side unit. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPascalCallReadme_CodeDeclToJsonAbi_GetLastPascalCallReadme);  // Register API: CodeDeclToJsonAbi_GetLastPascalCallReadme -> CodeDeclToJsonAbi_GetLastPascalCallReadme
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastJsCallCode', '(* [code_decl_to_json_abi] Step 3/3 - JS call-side reader (code). Returns the full text of the browser-side JavaScript client produced by the most recent successful GenerateAll. The text is a standalone IIFE library that attaches itself to window.<UnitName>Api (or globalThis.<UnitName>Api when window is unavailable). Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the JavaScript source, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastJsCallCode_CodeDeclToJsonAbi_GetLastJsCallCode);  // Register API: CodeDeclToJsonAbi_GetLastJsCallCode -> CodeDeclToJsonAbi_GetLastJsCallCode
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastJsCallReadme', '(* [code_decl_to_json_abi] Step 3/3 - JS call-side reader (README). Returns the full text of the Markdown README paired with the browser JavaScript client. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastJsCallReadme_CodeDeclToJsonAbi_GetLastJsCallReadme);  // Register API: CodeDeclToJsonAbi_GetLastJsCallReadme -> CodeDeclToJsonAbi_GetLastJsCallReadme
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastJsTestHtml', '(* [code_decl_to_json_abi] Step 3/3 - JS call-side reader (HTML test page). Returns the full text of the self-contained HTML test page produced by the most recent successful GenerateAll. The page embeds the JS client library and renders one interactive test card per exposed routine. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the HTML document, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastJsTestHtml_CodeDeclToJsonAbi_GetLastJsTestHtml);  // Register API: CodeDeclToJsonAbi_GetLastJsTestHtml -> CodeDeclToJsonAbi_GetLastJsTestHtml
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPythonServiceCode', '(* [code_decl_to_json_abi] Step 3/3 - Python service reader (code). Returns the full text of the Python HTTP/JSON service module produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Python module source, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPythonServiceCode_CodeDeclToJsonAbi_GetLastPythonServiceCode);  // Register API: CodeDeclToJsonAbi_GetLastPythonServiceCode -> CodeDeclToJsonAbi_GetLastPythonServiceCode
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPythonServiceReadme', '(* [code_decl_to_json_abi] Step 3/3 - Python service reader (README). Returns the full text of the Markdown README paired with the Python service module. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPythonServiceReadme_CodeDeclToJsonAbi_GetLastPythonServiceReadme);  // Register API: CodeDeclToJsonAbi_GetLastPythonServiceReadme -> CodeDeclToJsonAbi_GetLastPythonServiceReadme
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPythonCallCode', '(* [code_decl_to_json_abi] Step 3/3 - Python call-side reader (code). Returns the full text of the Python HTTP/JSON call-side module produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Python module source, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPythonCallCode_CodeDeclToJsonAbi_GetLastPythonCallCode);  // Register API: CodeDeclToJsonAbi_GetLastPythonCallCode -> CodeDeclToJsonAbi_GetLastPythonCallCode
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastPythonCallReadme', '(* [code_decl_to_json_abi] Step 3/3 - Python call-side reader (README). Returns the full text of the Markdown README paired with the Python call-side module. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastPythonCallReadme_CodeDeclToJsonAbi_GetLastPythonCallReadme);  // Register API: CodeDeclToJsonAbi_GetLastPythonCallReadme -> CodeDeclToJsonAbi_GetLastPythonCallReadme
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastCppServiceHeader', '(* [code_decl_to_json_abi] Step 3/3 - C++ service reader (header). Returns the full text of the C++ HTTP/JSON service header (.hpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the header text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastCppServiceHeader_CodeDeclToJsonAbi_GetLastCppServiceHeader);  // Register API: CodeDeclToJsonAbi_GetLastCppServiceHeader -> CodeDeclToJsonAbi_GetLastCppServiceHeader
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastCppServiceImpl', '(* [code_decl_to_json_abi] Step 3/3 - C++ service reader (implementation). Returns the full text of the C++ HTTP/JSON service implementation (.cpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the implementation text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastCppServiceImpl_CodeDeclToJsonAbi_GetLastCppServiceImpl);  // Register API: CodeDeclToJsonAbi_GetLastCppServiceImpl -> CodeDeclToJsonAbi_GetLastCppServiceImpl
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastCppServiceReadme', '(* [code_decl_to_json_abi] Step 3/3 - C++ service reader (README). Returns the full text of the Markdown README paired with the C++ service header and implementation. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastCppServiceReadme_CodeDeclToJsonAbi_GetLastCppServiceReadme);  // Register API: CodeDeclToJsonAbi_GetLastCppServiceReadme -> CodeDeclToJsonAbi_GetLastCppServiceReadme
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastCppCallHeader', '(* [code_decl_to_json_abi] Step 3/3 - C++ call-side reader (header). Returns the full text of the C++ HTTP/JSON call-side header (.hpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the header text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastCppCallHeader_CodeDeclToJsonAbi_GetLastCppCallHeader);  // Register API: CodeDeclToJsonAbi_GetLastCppCallHeader -> CodeDeclToJsonAbi_GetLastCppCallHeader
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastCppCallImpl', '(* [code_decl_to_json_abi] Step 3/3 - C++ call-side reader (implementation). Returns the full text of the C++ HTTP/JSON call-side implementation (.cpp) produced by the most recent successful GenerateAll. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the implementation text, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastCppCallImpl_CodeDeclToJsonAbi_GetLastCppCallImpl);  // Register API: CodeDeclToJsonAbi_GetLastCppCallImpl -> CodeDeclToJsonAbi_GetLastCppCallImpl
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetLastCppCallReadme', '(* [code_decl_to_json_abi] Step 3/3 - C++ call-side reader (README). Returns the full text of the Markdown README paired with the C++ call-side header and implementation. Pure reader. Returns '#39#39' if GenerateAll has not succeeded. No parameters. Return value: the Markdown README, or an empty string. )', nil, @Callback_CodeDeclToJsonAbi_GetLastCppCallReadme_CodeDeclToJsonAbi_GetLastCppCallReadme);  // Register API: CodeDeclToJsonAbi_GetLastCppCallReadme -> CodeDeclToJsonAbi_GetLastCppCallReadme
  if DEBUG_LOG then
    DoStatus('[RegisterAPIs] Registered APIs: 22 functions');
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
