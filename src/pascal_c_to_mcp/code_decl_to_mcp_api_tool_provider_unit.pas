unit code_decl_to_mcp_api_tool_provider_unit;

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
  MY_APP_NAME : string = 'code_decl_to_mcp_api';
  MY_APP_DESC : string = 'Tool provider for unit code_decl_to_mcp_api';
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


function internal_call_CodeDeclToMcp_SetSourceCode_CodeDeclToMcp_SetSourceCode(Source: string; Language: string): string;
function internal_call_CodeDeclToMcp_ConvertToPascal_CodeDeclToMcp_ConvertToPascal(): string;
function internal_call_CodeDeclToMcp_ConvertToPython_CodeDeclToMcp_ConvertToPython(): string;
function internal_call_CodeDeclToMcp_ConvertToCpp_CodeDeclToMcp_ConvertToCpp(): string;
function internal_call_CodeDeclToMcp_GetLastPascalCode_CodeDeclToMcp_GetLastPascalCode(): string;
function internal_call_CodeDeclToMcp_GetLastPascalReadme_CodeDeclToMcp_GetLastPascalReadme(): string;
function internal_call_CodeDeclToMcp_GetLastPythonCode_CodeDeclToMcp_GetLastPythonCode(): string;
function internal_call_CodeDeclToMcp_GetLastPythonReadme_CodeDeclToMcp_GetLastPythonReadme(): string;
function internal_call_CodeDeclToMcp_GetLastCppHeader_CodeDeclToMcp_GetLastCppHeader(): string;
function internal_call_CodeDeclToMcp_GetLastCppImpl_CodeDeclToMcp_GetLastCppImpl(): string;
function internal_call_CodeDeclToMcp_GetLastCppReadme_CodeDeclToMcp_GetLastCppReadme(): string;

implementation

uses
  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  code_decl_to_mcp_frm;


// Forward declarations for all API callbacks
function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;
procedure Callback_CodeDeclToMcp_SetSourceCode_CodeDeclToMcp_SetSourceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_ConvertToPascal_CodeDeclToMcp_ConvertToPascal(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_ConvertToPython_CodeDeclToMcp_ConvertToPython(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_ConvertToCpp_CodeDeclToMcp_ConvertToCpp(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastPascalCode_CodeDeclToMcp_GetLastPascalCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastPascalReadme_CodeDeclToMcp_GetLastPascalReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastPythonCode_CodeDeclToMcp_GetLastPythonCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastPythonReadme_CodeDeclToMcp_GetLastPythonReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastCppHeader_CodeDeclToMcp_GetLastCppHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastCppImpl_CodeDeclToMcp_GetLastCppImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetLastCppReadme_CodeDeclToMcp_GetLastCppReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;



// -----------------------------------------------------------------------------
// JSON response helpers
//
// The generated callbacks wrap whatever these functions return inside a
// {"result": "..."} envelope before writing it to _Out. So each of these
// helpers returns a JSON string that is meant to be nested inside that
// envelope; the client unwraps the outer "result" field and then parses
// the inner JSON.
// -----------------------------------------------------------------------------

function JsonStatusOk: string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['status'] := 'ok';
    Result := TEncoding.UTF8.GetString(jo.ToBytes);
  finally
    jo.Free;
  end;
end;

function JsonError(const Msg: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['error'] := Msg;
    Result := TEncoding.UTF8.GetString(jo.ToBytes);
  finally
    jo.Free;
  end;
end;

function JsonResult(const Path: string): string;
var
  jo: TZ_JsonObject;
begin
  jo := TZ_JsonObject.Create;
  try
    jo.S['result'] := Path;
    Result := TEncoding.UTF8.GetString(jo.ToBytes);
  finally
    jo.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Pipeline helper
//
// Ensures the UI has a valid language selection before any conversion runs.
// Returns True if it is safe to proceed.
// -----------------------------------------------------------------------------
function EnsureLanguageSelected: Boolean;
begin
  Result := (CodeDeclToMcpForm <> nil)
        and (CodeDeclToMcpForm.LanguageSelectorComboBox.ItemIndex <> 0);
end;


// =============================================================================
// Step 1 - SetSourceCode
//
// Mimics the human workflow: select the language in the combo box, paste the
// source text into SourceEdit. Clears all downstream state so that the next
// ConvertToXxx re-runs the full parse -> model -> generate pipeline.
// =============================================================================
function internal_call_CodeDeclToMcp_SetSourceCode_CodeDeclToMcp_SetSourceCode(Source: string; Language: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;

    if SameText(Language, 'pascal') then
    begin
      CodeDeclToMcpForm.LanguageSelectorComboBox.ItemIndex := 1;
      CodeDeclToMcpForm.LanguageSelectorComboBoxChange(CodeDeclToMcpForm.LanguageSelectorComboBox);
    end
    else if SameText(Language, 'c') then
    begin
      CodeDeclToMcpForm.LanguageSelectorComboBox.ItemIndex := 2;
      CodeDeclToMcpForm.LanguageSelectorComboBoxChange(CodeDeclToMcpForm.LanguageSelectorComboBox);
    end
    else
    begin
      Result := JsonError('Unsupported language. Use pascal or c.');
      Exit;
    end;

    CodeDeclToMcpForm.SourceEdit.Text := Source;

    // Clear downstream state: the next ConvertToXxx must rebuild the pipeline.
    CodeDeclToMcpForm.SourceJsonEdit.Text := '';
    CodeDeclToMcpForm.ModelJsonEdit.Text := '';
    CodeDeclToMcpForm.FinalPascalSourceEdit.Text := '';
    CodeDeclToMcpForm.FinalPascalReadmeEdit.Text := '';
    CodeDeclToMcpForm.FinalPythonSourceEdit.Text := '';
    CodeDeclToMcpForm.FinalPythonReadmeEdit.Text := '';
    CodeDeclToMcpForm.FinalCppHeaderEdit.Text := '';
    CodeDeclToMcpForm.FinalCppImplEdit.Text := '';
    CodeDeclToMcpForm.FinalCppReadmeEdit.Text := '';

    Result := JsonStatusOk;
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
    if CodeDeclToMcpForm = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;

    if SameText(Language, 'pascal') then
    begin
      CodeDeclToMcpForm.LanguageSelectorComboBox.ItemIndex := 1;
      CodeDeclToMcpForm.LanguageSelectorComboBoxChange(CodeDeclToMcpForm.LanguageSelectorComboBox);
    end
    else if SameText(Language, 'c') then
    begin
      CodeDeclToMcpForm.LanguageSelectorComboBox.ItemIndex := 2;
      CodeDeclToMcpForm.LanguageSelectorComboBoxChange(CodeDeclToMcpForm.LanguageSelectorComboBox);
    end
    else
    begin
      temp_ := JsonError('Unsupported language. Use pascal or c.');
      Exit;
    end;

    CodeDeclToMcpForm.SourceEdit.Text := Source;

    CodeDeclToMcpForm.SourceJsonEdit.Text := '';
    CodeDeclToMcpForm.ModelJsonEdit.Text := '';
    CodeDeclToMcpForm.FinalPascalSourceEdit.Text := '';
    CodeDeclToMcpForm.FinalPascalReadmeEdit.Text := '';
    CodeDeclToMcpForm.FinalPythonSourceEdit.Text := '';
    CodeDeclToMcpForm.FinalPythonReadmeEdit.Text := '';
    CodeDeclToMcpForm.FinalCppHeaderEdit.Text := '';
    CodeDeclToMcpForm.FinalCppImplEdit.Text := '';
    CodeDeclToMcpForm.FinalCppReadmeEdit.Text := '';

    temp_ := JsonStatusOk;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// Step 2 - ConvertToPascal
//
// Mimics the human workflow: click "下一步: 生成源码", then switch the final
// page control to the Pascal tab. Returns the absolute path of the generated
// provider unit, read back from FinalPascalSourceEdit.Hint.
// =============================================================================
function internal_call_CodeDeclToMcp_ConvertToPascal_CodeDeclToMcp_ConvertToPascal(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;

    if CodeDeclToMcpForm.SourceEdit.Text = '' then
    begin
      Result := JsonError('No source set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    if not EnsureLanguageSelected then
    begin
      Result := JsonError('Source language not set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    try
      CodeDeclToMcpForm.ParseSourceToLv0Json;
      CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
      CodeDeclToMcpForm.GenerateAllArtifacts;
    except
      on E: Exception do
      begin
        Result := JsonError('ConvertToPascal failed: ' + E.Message);
        Exit;
      end;
    end;

    // Switch the final page control to the Pascal tab so the user sees it too.
    CodeDeclToMcpForm.FinalSourcePageControl.ActivePage := CodeDeclToMcpForm.FinalPascalTab;

    Result := JsonResult(CodeDeclToMcpForm.FinalPascalSourceEdit.Hint);
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
    if CodeDeclToMcpForm = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;

    if CodeDeclToMcpForm.SourceEdit.Text = '' then
    begin
      temp_ := JsonError('No source set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    if not EnsureLanguageSelected then
    begin
      temp_ := JsonError('Source language not set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    try
      CodeDeclToMcpForm.ParseSourceToLv0Json;
      CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
      CodeDeclToMcpForm.GenerateAllArtifacts;
    except
      on E: Exception do
      begin
        temp_ := JsonError('ConvertToPascal failed: ' + E.Message);
        Exit;
      end;
    end;

    CodeDeclToMcpForm.FinalSourcePageControl.ActivePage := CodeDeclToMcpForm.FinalPascalTab;

    temp_ := JsonResult(CodeDeclToMcpForm.FinalPascalSourceEdit.Hint);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// Step 2 - ConvertToPython
// =============================================================================
function internal_call_CodeDeclToMcp_ConvertToPython_CodeDeclToMcp_ConvertToPython(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;

    if CodeDeclToMcpForm.SourceEdit.Text = '' then
    begin
      Result := JsonError('No source set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    if not EnsureLanguageSelected then
    begin
      Result := JsonError('Source language not set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    try
      CodeDeclToMcpForm.ParseSourceToLv0Json;
      CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
      CodeDeclToMcpForm.GenerateAllArtifacts;
    except
      on E: Exception do
      begin
        Result := JsonError('ConvertToPython failed: ' + E.Message);
        Exit;
      end;
    end;

    CodeDeclToMcpForm.FinalSourcePageControl.ActivePage := CodeDeclToMcpForm.FinalPythonTab;

    Result := JsonResult(CodeDeclToMcpForm.FinalPythonSourceEdit.Hint);
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
    if CodeDeclToMcpForm = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;

    if CodeDeclToMcpForm.SourceEdit.Text = '' then
    begin
      temp_ := JsonError('No source set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    if not EnsureLanguageSelected then
    begin
      temp_ := JsonError('Source language not set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    try
      CodeDeclToMcpForm.ParseSourceToLv0Json;
      CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
      CodeDeclToMcpForm.GenerateAllArtifacts;
    except
      on E: Exception do
      begin
        temp_ := JsonError('ConvertToPython failed: ' + E.Message);
        Exit;
      end;
    end;

    CodeDeclToMcpForm.FinalSourcePageControl.ActivePage := CodeDeclToMcpForm.FinalPythonTab;

    temp_ := JsonResult(CodeDeclToMcpForm.FinalPythonSourceEdit.Hint);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// Step 2 - ConvertToCpp
// =============================================================================
function internal_call_CodeDeclToMcp_ConvertToCpp_CodeDeclToMcp_ConvertToCpp(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
    begin
      Result := JsonError('Form not available');
      Exit;
    end;

    if CodeDeclToMcpForm.SourceEdit.Text = '' then
    begin
      Result := JsonError('No source set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    if not EnsureLanguageSelected then
    begin
      Result := JsonError('Source language not set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    try
      CodeDeclToMcpForm.ParseSourceToLv0Json;
      CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
      CodeDeclToMcpForm.GenerateAllArtifacts;
    except
      on E: Exception do
      begin
        Result := JsonError('ConvertToCpp failed: ' + E.Message);
        Exit;
      end;
    end;

    CodeDeclToMcpForm.FinalSourcePageControl.ActivePage := CodeDeclToMcpForm.FinalCppTab;

    Result := JsonResult(CodeDeclToMcpForm.FinalCppHeaderEdit.Hint);
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
    if CodeDeclToMcpForm = nil then
    begin
      temp_ := JsonError('Form not available');
      Exit;
    end;

    if CodeDeclToMcpForm.SourceEdit.Text = '' then
    begin
      temp_ := JsonError('No source set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    if not EnsureLanguageSelected then
    begin
      temp_ := JsonError('Source language not set. Call CodeDeclToMcp_SetSourceCode first.');
      Exit;
    end;

    try
      CodeDeclToMcpForm.ParseSourceToLv0Json;
      CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
      CodeDeclToMcpForm.GenerateAllArtifacts;
    except
      on E: Exception do
      begin
        temp_ := JsonError('ConvertToCpp failed: ' + E.Message);
        Exit;
      end;
    end;

    CodeDeclToMcpForm.FinalSourcePageControl.ActivePage := CodeDeclToMcpForm.FinalCppTab;

    temp_ := JsonResult(CodeDeclToMcpForm.FinalCppHeaderEdit.Hint);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// Step 3 - Pascal readers
// =============================================================================
function internal_call_CodeDeclToMcp_GetLastPascalCode_CodeDeclToMcp_GetLastPascalCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalPascalSourceEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalPascalSourceEdit.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToMcp_GetLastPascalReadme_CodeDeclToMcp_GetLastPascalReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalPascalReadmeEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalPascalReadmeEdit.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// Step 3 - Python readers
// =============================================================================
function internal_call_CodeDeclToMcp_GetLastPythonCode_CodeDeclToMcp_GetLastPythonCode(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalPythonSourceEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalPythonSourceEdit.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToMcp_GetLastPythonReadme_CodeDeclToMcp_GetLastPythonReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalPythonReadmeEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalPythonReadmeEdit.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// Step 3 - C++ readers
// =============================================================================
function internal_call_CodeDeclToMcp_GetLastCppHeader_CodeDeclToMcp_GetLastCppHeader(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalCppHeaderEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalCppHeaderEdit.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToMcp_GetLastCppImpl_CodeDeclToMcp_GetLastCppImpl(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalCppImplEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalCppImplEdit.Text;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

function internal_call_CodeDeclToMcp_GetLastCppReadme_CodeDeclToMcp_GetLastCppReadme(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    if CodeDeclToMcpForm = nil then
      Result := ''
    else
      Result := CodeDeclToMcpForm.FinalCppReadmeEdit.Text;
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
    if CodeDeclToMcpForm = nil then
      temp_ := ''
    else
      temp_ := CodeDeclToMcpForm.FinalCppReadmeEdit.Text;
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
// ---- CodeDeclToMcp_SetSourceCode (API: CodeDeclToMcp_SetSourceCode) ----
procedure Callback_CodeDeclToMcp_SetSourceCode_CodeDeclToMcp_SetSourceCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_SetSourceCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_SetSourceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_SetSourceCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_SetSourceCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_SetSourceCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    Source := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToMcp_SetSourceCode_CodeDeclToMcp_SetSourceCode(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_SetSourceCode] called with %s -> result: %s', [Source, Language, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToMcp_SetSourceCode] called with %s', [Source, Language]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_SetSourceCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_SetSourceCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_ConvertToPascal (API: CodeDeclToMcp_ConvertToPascal) ----
procedure Callback_CodeDeclToMcp_ConvertToPascal_CodeDeclToMcp_ConvertToPascal(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_ConvertToPascal] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ConvertToPascal] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ConvertToPascal] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_ConvertToPascal] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ConvertToPascal] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_ConvertToPascal_CodeDeclToMcp_ConvertToPascal();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_ConvertToPascal] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_ConvertToPascal] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ConvertToPascal] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_ConvertToPascal] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_ConvertToPython (API: CodeDeclToMcp_ConvertToPython) ----
procedure Callback_CodeDeclToMcp_ConvertToPython_CodeDeclToMcp_ConvertToPython(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_ConvertToPython] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ConvertToPython] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ConvertToPython] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_ConvertToPython] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ConvertToPython] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_ConvertToPython_CodeDeclToMcp_ConvertToPython();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_ConvertToPython] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_ConvertToPython] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ConvertToPython] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_ConvertToPython] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_ConvertToCpp (API: CodeDeclToMcp_ConvertToCpp) ----
procedure Callback_CodeDeclToMcp_ConvertToCpp_CodeDeclToMcp_ConvertToCpp(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_ConvertToCpp] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ConvertToCpp] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ConvertToCpp] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_ConvertToCpp] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ConvertToCpp] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_ConvertToCpp_CodeDeclToMcp_ConvertToCpp();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_ConvertToCpp] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_ConvertToCpp] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ConvertToCpp] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_ConvertToCpp] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastPascalCode (API: CodeDeclToMcp_GetLastPascalCode) ----
procedure Callback_CodeDeclToMcp_GetLastPascalCode_CodeDeclToMcp_GetLastPascalCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastPascalCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPascalCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPascalCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastPascalCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPascalCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastPascalCode_CodeDeclToMcp_GetLastPascalCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastPascalCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastPascalCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPascalCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastPascalCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastPascalReadme (API: CodeDeclToMcp_GetLastPascalReadme) ----
procedure Callback_CodeDeclToMcp_GetLastPascalReadme_CodeDeclToMcp_GetLastPascalReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastPascalReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPascalReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPascalReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastPascalReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPascalReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastPascalReadme_CodeDeclToMcp_GetLastPascalReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastPascalReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastPascalReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPascalReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastPascalReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastPythonCode (API: CodeDeclToMcp_GetLastPythonCode) ----
procedure Callback_CodeDeclToMcp_GetLastPythonCode_CodeDeclToMcp_GetLastPythonCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastPythonCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPythonCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPythonCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastPythonCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPythonCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastPythonCode_CodeDeclToMcp_GetLastPythonCode();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastPythonCode] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastPythonCode] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPythonCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastPythonCode] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastPythonReadme (API: CodeDeclToMcp_GetLastPythonReadme) ----
procedure Callback_CodeDeclToMcp_GetLastPythonReadme_CodeDeclToMcp_GetLastPythonReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastPythonReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPythonReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPythonReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastPythonReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastPythonReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastPythonReadme_CodeDeclToMcp_GetLastPythonReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastPythonReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastPythonReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastPythonReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastPythonReadme] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastCppHeader (API: CodeDeclToMcp_GetLastCppHeader) ----
procedure Callback_CodeDeclToMcp_GetLastCppHeader_CodeDeclToMcp_GetLastCppHeader(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastCppHeader] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastCppHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppHeader] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastCppHeader] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppHeader] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastCppHeader_CodeDeclToMcp_GetLastCppHeader();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastCppHeader] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastCppHeader] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastCppHeader] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppHeader] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastCppImpl (API: CodeDeclToMcp_GetLastCppImpl) ----
procedure Callback_CodeDeclToMcp_GetLastCppImpl_CodeDeclToMcp_GetLastCppImpl(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastCppImpl] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastCppImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppImpl] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastCppImpl] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppImpl] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastCppImpl_CodeDeclToMcp_GetLastCppImpl();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastCppImpl] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastCppImpl] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastCppImpl] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppImpl] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetLastCppReadme (API: CodeDeclToMcp_GetLastCppReadme) ----
procedure Callback_CodeDeclToMcp_GetLastCppReadme_CodeDeclToMcp_GetLastCppReadme(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetLastCppReadme] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastCppReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppReadme] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetLastCppReadme] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppReadme] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_GetLastCppReadme_CodeDeclToMcp_GetLastCppReadme();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetLastCppReadme] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_GetLastCppReadme] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetLastCppReadme] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetLastCppReadme] Exception: ' + E.Message);
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
    // Tool: CodeDeclToMcp_SetSourceCode -> CodeDeclToMcp_SetSourceCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_SetSourceCode';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 1/3 - Store source text. Does NOT convert. Stores the source text and its SOURCE language into the generator. This is a setup call: it does NOT produce any output file and does NOT decide which target language will be generated. After this call succeeds you MUST invoke exactly one of the Step 2 tools to actually produce a result: CodeDeclToMcp_ConvertToPascal CodeDeclToMcp_ConvertToPython CodeDeclToMcp_ConvertToCpp The stored source stays in effect for the rest of the session. To switch target languages you do NOT call this tool again; you just call another Step 2 tool. Source: complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. Language: the SOURCE language of the text passed in Source. Accepted values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively. Do NOT pass a target language such as '#39'python'#39' or '#39'cpp'#39'; the target language is selected by calling the corresponding CodeDeclToMcp_ConvertToXxx tool in Step 2. Return value: JSON string. On success: {"status":"ok"}. On failure: {"error":"<message>"}. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_SetSourceCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'complete source text. For Language='#39'pascal'#39' pass a full Pascal'#10'          unit that starts with a unit declaration and contains an'#10'          interface section. For Language='#39'c'#39' pass a full C header that'#10'          starts with the include guard and contains the function'#10'          prototypes.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'the SOURCE language of the text passed in Source. Accepted'#10'          values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively.'#10'          Do NOT pass a target language such as '#39'python'#39' or '#39'cpp'#39'; the'#10'          target language is selected by calling the corresponding'#10'          CodeDeclToMcp_ConvertToXxx tool in Step 2.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_SetSourceCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_SetSourceCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_ConvertToPascal -> CodeDeclToMcp_ConvertToPascal
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_ConvertToPascal';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 2/3 - Pascal branch. Produce a Pascal MCP tool provider from the source stored by CodeDeclToMcp_SetSourceCode. Prerequisite: CodeDeclToMcp_SetSourceCode must have succeeded earlier in this session. If it has not, this call returns an error. Calling this tool does NOT require calling SetSourceCode again. After success, read the produced files with: CodeDeclToMcp_GetLastPascalCode    (the provider unit) CodeDeclToMcp_GetLastPascalReadme  (the user guide) The Pascal branch is independent from the Python and C++ branches. You may call all three Step 2 tools in any order after one SetSourceCode. No parameters. Return value: JSON string. On success: {"result":"<absolute file path>"}. On failure: {"error":"<message>"}. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_ConvertToPascal';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_ConvertToPascal')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_ConvertToPascal');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_ConvertToPython -> CodeDeclToMcp_ConvertToPython
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_ConvertToPython';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 2/3 - Python branch. Produce a Python MCP tool provider from the source stored by CodeDeclToMcp_SetSourceCode. Prerequisite: CodeDeclToMcp_SetSourceCode must have succeeded earlier in this session. If it has not, this call returns an error. Calling this tool does NOT require calling SetSourceCode again. After success, read the produced files with: CodeDeclToMcp_GetLastPythonCode    (the module) CodeDeclToMcp_GetLastPythonReadme  (the user guide) The Python branch is independent from the Pascal and C++ branches. You may call all three Step 2 tools in any order after one SetSourceCode. No parameters. Return value: JSON string. On success: {"result":"<absolute file path>"}. On failure: {"error":"<message>"}. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_ConvertToPython';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_ConvertToPython')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_ConvertToPython');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_ConvertToCpp -> CodeDeclToMcp_ConvertToCpp
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_ConvertToCpp';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 2/3 - C++ branch. Produce a C++ MCP tool provider from the source stored by CodeDeclToMcp_SetSourceCode. Prerequisite: CodeDeclToMcp_SetSourceCode must have succeeded earlier in this session. If it has not, this call returns an error. Calling this tool does NOT require calling SetSourceCode again. Two files are produced: a header (.hpp) and an implementation (.cpp) that sits next to it with the same base name. After success, read the produced files with: CodeDeclToMcp_GetLastCppHeader  (the header) CodeDeclToMcp_GetLastCppImpl    (the implementation) CodeDeclToMcp_GetLastCppReadme  (the user guide) The C++ branch is independent from the Pascal and Python branches. You may call all three Step 2 tools in any order after one SetSourceCode. No parameters. Return value: JSON string. On success: {"result":"<absolute file path of the .hpp>"}. On failure: {"error":"<message>"}. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_ConvertToCpp';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_ConvertToCpp')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_ConvertToCpp');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastPascalCode -> CodeDeclToMcp_GetLastPascalCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastPascalCode';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - Pascal reader. Returns the full text of the Pascal provider unit produced by the most recent successful CodeDeclToMcp_ConvertToPascal call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPascal must have succeeded first. No parameters. Return value: string with the full Pascal unit text, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastPascalCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastPascalCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastPascalCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastPascalReadme -> CodeDeclToMcp_GetLastPascalReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastPascalReadme';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - Pascal reader. Returns the full text of the Pascal README produced by the most recent successful CodeDeclToMcp_ConvertToPascal call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPascal must have succeeded first. No parameters. Return value: string with the Markdown README, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastPascalReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastPascalReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastPascalReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastPythonCode -> CodeDeclToMcp_GetLastPythonCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastPythonCode';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - Python reader. Returns the full text of the Python module produced by the most recent successful CodeDeclToMcp_ConvertToPython call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPython must have succeeded first. No parameters. Return value: string with the full Python module text, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastPythonCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastPythonCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastPythonCode');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastPythonReadme -> CodeDeclToMcp_GetLastPythonReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastPythonReadme';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - Python reader. Returns the full text of the Python README produced by the most recent successful CodeDeclToMcp_ConvertToPython call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPython must have succeeded first. No parameters. Return value: string with the Markdown README, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastPythonReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastPythonReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastPythonReadme');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastCppHeader -> CodeDeclToMcp_GetLastCppHeader
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastCppHeader';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - C++ reader. Returns the full text of the C++ header produced by the most recent successful CodeDeclToMcp_ConvertToCpp call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToCpp must have succeeded first. No parameters. Return value: string with the full C++ header text, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastCppHeader';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastCppHeader')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastCppHeader');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastCppImpl -> CodeDeclToMcp_GetLastCppImpl
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastCppImpl';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - C++ reader. Returns the full text of the C++ implementation produced by the most recent successful CodeDeclToMcp_ConvertToCpp call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToCpp must have succeeded first. No parameters. Return value: string with the full C++ implementation text, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastCppImpl';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastCppImpl')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastCppImpl');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetLastCppReadme -> CodeDeclToMcp_GetLastCppReadme
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetLastCppReadme';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - C++ reader. Returns the full text of the C++ README produced by the most recent successful CodeDeclToMcp_ConvertToCpp call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToCpp must have succeeded first. No parameters. Return value: string with the Markdown README, or an empty string if nothing has been generated yet. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetLastCppReadme';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetLastCppReadme')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetLastCppReadme');
    finally
      ToolDef.Free;
    end;

    Result := (regCount = 11);
    if DEBUG_LOG then
      DoStatus('[RegisterTools] Registered %d out of %d tools.', [regCount, 11]);
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

  LF_RegisterCallEx(App, 'CodeDeclToMcp_SetSourceCode', '(* [code_decl_to_mcp] Step 1/3 - Store source text. Does NOT convert. Stores the source text and its SOURCE language into the generator. This is a setup call: it does NOT produce any output file and does NOT decide which target language will be generated. After this call succeeds you MUST invoke exactly one of the Step 2 tools to actually produce a result: CodeDeclToMcp_ConvertToPascal CodeDeclToMcp_ConvertToPython CodeDeclToMcp_ConvertToCpp The stored source stays in effect for the rest of the session. To switch target languages you do NOT call this tool again; you just call another Step 2 tool. Source: complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. Language: the SOURCE language of the text passed in Source. Accepted values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively. Do NOT pass a target language such as '#39'python'#39' or '#39'cpp'#39'; the target language is selected by calling the corresponding CodeDeclToMcp_ConvertToXxx tool in Step 2. Return value: JSON string. On success: {"status":"ok"}. On failure: {"error":"<message>"}. )', nil, @Callback_CodeDeclToMcp_SetSourceCode_CodeDeclToMcp_SetSourceCode);  // Register API: CodeDeclToMcp_SetSourceCode -> CodeDeclToMcp_SetSourceCode
  LF_RegisterCallEx(App, 'CodeDeclToMcp_ConvertToPascal', '(* [code_decl_to_mcp] Step 2/3 - Pascal branch. Produce a Pascal MCP tool provider from the source stored by CodeDeclToMcp_SetSourceCode. Prerequisite: CodeDeclToMcp_SetSourceCode must have succeeded earlier in this session. If it has not, this call returns an error. Calling this tool does NOT require calling SetSourceCode again. After success, read the produced files with: CodeDeclToMcp_GetLastPascalCode    (the provider unit) CodeDeclToMcp_GetLastPascalReadme  (the user guide) The Pascal branch is independent from the Python and C++ branches. You may call all three Step 2 tools in any order after one SetSourceCode. No parameters. Return value: JSON string. On success: {"result":"<absolute file path>"}. On failure: {"error":"<message>"}. )', nil, @Callback_CodeDeclToMcp_ConvertToPascal_CodeDeclToMcp_ConvertToPascal);  // Register API: CodeDeclToMcp_ConvertToPascal -> CodeDeclToMcp_ConvertToPascal
  LF_RegisterCallEx(App, 'CodeDeclToMcp_ConvertToPython', '(* [code_decl_to_mcp] Step 2/3 - Python branch. Produce a Python MCP tool provider from the source stored by CodeDeclToMcp_SetSourceCode. Prerequisite: CodeDeclToMcp_SetSourceCode must have succeeded earlier in this session. If it has not, this call returns an error. Calling this tool does NOT require calling SetSourceCode again. After success, read the produced files with: CodeDeclToMcp_GetLastPythonCode    (the module) CodeDeclToMcp_GetLastPythonReadme  (the user guide) The Python branch is independent from the Pascal and C++ branches. You may call all three Step 2 tools in any order after one SetSourceCode. No parameters. Return value: JSON string. On success: {"result":"<absolute file path>"}. On failure: {"error":"<message>"}. )', nil, @Callback_CodeDeclToMcp_ConvertToPython_CodeDeclToMcp_ConvertToPython);  // Register API: CodeDeclToMcp_ConvertToPython -> CodeDeclToMcp_ConvertToPython
  LF_RegisterCallEx(App, 'CodeDeclToMcp_ConvertToCpp', '(* [code_decl_to_mcp] Step 2/3 - C++ branch. Produce a C++ MCP tool provider from the source stored by CodeDeclToMcp_SetSourceCode. Prerequisite: CodeDeclToMcp_SetSourceCode must have succeeded earlier in this session. If it has not, this call returns an error. Calling this tool does NOT require calling SetSourceCode again. Two files are produced: a header (.hpp) and an implementation (.cpp) that sits next to it with the same base name. After success, read the produced files with: CodeDeclToMcp_GetLastCppHeader  (the header) CodeDeclToMcp_GetLastCppImpl    (the implementation) CodeDeclToMcp_GetLastCppReadme  (the user guide) The C++ branch is independent from the Pascal and Python branches. You may call all three Step 2 tools in any order after one SetSourceCode. No parameters. Return value: JSON string. On success: {"result":"<absolute file path of the .hpp>"}. On failure: {"error":"<message>"}. )', nil, @Callback_CodeDeclToMcp_ConvertToCpp_CodeDeclToMcp_ConvertToCpp);  // Register API: CodeDeclToMcp_ConvertToCpp -> CodeDeclToMcp_ConvertToCpp
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastPascalCode', '(* [code_decl_to_mcp] Step 3/3 - Pascal reader. Returns the full text of the Pascal provider unit produced by the most recent successful CodeDeclToMcp_ConvertToPascal call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPascal must have succeeded first. No parameters. Return value: string with the full Pascal unit text, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastPascalCode_CodeDeclToMcp_GetLastPascalCode);  // Register API: CodeDeclToMcp_GetLastPascalCode -> CodeDeclToMcp_GetLastPascalCode
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastPascalReadme', '(* [code_decl_to_mcp] Step 3/3 - Pascal reader. Returns the full text of the Pascal README produced by the most recent successful CodeDeclToMcp_ConvertToPascal call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPascal must have succeeded first. No parameters. Return value: string with the Markdown README, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastPascalReadme_CodeDeclToMcp_GetLastPascalReadme);  // Register API: CodeDeclToMcp_GetLastPascalReadme -> CodeDeclToMcp_GetLastPascalReadme
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastPythonCode', '(* [code_decl_to_mcp] Step 3/3 - Python reader. Returns the full text of the Python module produced by the most recent successful CodeDeclToMcp_ConvertToPython call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPython must have succeeded first. No parameters. Return value: string with the full Python module text, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastPythonCode_CodeDeclToMcp_GetLastPythonCode);  // Register API: CodeDeclToMcp_GetLastPythonCode -> CodeDeclToMcp_GetLastPythonCode
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastPythonReadme', '(* [code_decl_to_mcp] Step 3/3 - Python reader. Returns the full text of the Python README produced by the most recent successful CodeDeclToMcp_ConvertToPython call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToPython must have succeeded first. No parameters. Return value: string with the Markdown README, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastPythonReadme_CodeDeclToMcp_GetLastPythonReadme);  // Register API: CodeDeclToMcp_GetLastPythonReadme -> CodeDeclToMcp_GetLastPythonReadme
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastCppHeader', '(* [code_decl_to_mcp] Step 3/3 - C++ reader. Returns the full text of the C++ header produced by the most recent successful CodeDeclToMcp_ConvertToCpp call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToCpp must have succeeded first. No parameters. Return value: string with the full C++ header text, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastCppHeader_CodeDeclToMcp_GetLastCppHeader);  // Register API: CodeDeclToMcp_GetLastCppHeader -> CodeDeclToMcp_GetLastCppHeader
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastCppImpl', '(* [code_decl_to_mcp] Step 3/3 - C++ reader. Returns the full text of the C++ implementation produced by the most recent successful CodeDeclToMcp_ConvertToCpp call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToCpp must have succeeded first. No parameters. Return value: string with the full C++ implementation text, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastCppImpl_CodeDeclToMcp_GetLastCppImpl);  // Register API: CodeDeclToMcp_GetLastCppImpl -> CodeDeclToMcp_GetLastCppImpl
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetLastCppReadme', '(* [code_decl_to_mcp] Step 3/3 - C++ reader. Returns the full text of the C++ README produced by the most recent successful CodeDeclToMcp_ConvertToCpp call. Pure reader: never triggers a new conversion, never requires calling CodeDeclToMcp_SetSourceCode again. Prerequisite: CodeDeclToMcp_ConvertToCpp must have succeeded first. No parameters. Return value: string with the Markdown README, or an empty string if nothing has been generated yet. )', nil, @Callback_CodeDeclToMcp_GetLastCppReadme_CodeDeclToMcp_GetLastCppReadme);  // Register API: CodeDeclToMcp_GetLastCppReadme -> CodeDeclToMcp_GetLastCppReadme
  if DEBUG_LOG then
    DoStatus('[RegisterAPIs] Registered APIs: 11 functions');
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
