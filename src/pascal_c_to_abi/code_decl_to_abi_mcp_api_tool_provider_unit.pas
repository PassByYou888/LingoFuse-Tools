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


function internal_call_CodeDeclToAbi_GenerateAll_CodeDeclToAbi_GenerateAll(Source: string; Language: string): string;
function internal_call_CodeDeclToAbi_GetTargetList_CodeDeclToAbi_GetTargetList(): string;
function internal_call_CodeDeclToAbi_GetTargetCode_CodeDeclToAbi_GetTargetCode(FileName: string): string;

implementation

uses
  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  code_decl_to_abi_frm, ComCtrls;


// Forward declarations for all API callbacks
function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;
procedure Callback_CodeDeclToAbi_GenerateAll_CodeDeclToAbi_GenerateAll(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetTargetList_CodeDeclToAbi_GetTargetList(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToAbi_GetTargetCode_CodeDeclToAbi_GetTargetCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;


// =============================================================================
// JSON reply helpers
// =============================================================================

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


// =============================================================================
// Main-thread work helpers
//
// Every helper below MUST run on the main thread. The internal_call_*
// functions that follow marshal onto the main thread via TCompute.Sync
// and call these helpers.
//
// All helpers operate on the GUI form `code_decl_to_abi_form`:
//
//   * Cmb_LanguageSelector                     source-language combo box
//   * Edit_Source                              source text editor
//   * Edit_SourceJson / Edit_ModelJson         intermediate JSON editors
//   * source_2_json_nex_ButtonClick            parse step
//   * JsonToModelButtonClick                   normalize step
//   * GenerateSourceButtonClick                generate-everything step
//   * final_source_file_ListView               the artifact list
//   * final_Source_edit                        the selected artifact text
//
// The GUI button handlers are already the single source of truth for
// the whole pipeline; calling them here keeps the MCP path provably
// identical to what a human would do by clicking through the tabs.
// =============================================================================

function Work_Generate_All(const Source, Language: string): string;
var
  lang: string;
  idx: Integer;
  unitName: string;
  count: Integer;
  jo: TZ_JsonObject;
  joModel: TZ_JsonObject;
begin
  // ---- Preconditions ---------------------------------------------------
  if code_decl_to_abi_form = nil then
  begin
    Result := Json_Error('GUI form is not available. The code_decl_to_abi executable is not running.');
    Exit;
  end;

  if Trim(Source) = '' then
  begin
    Result := Json_Error('Source is empty.');
    Exit;
  end;

  lang := LowerCase(Trim(Language));
  if lang = 'pascal' then
    idx := 1
  else if lang = 'c' then
    idx := 2
  else
  begin
    Result := Json_Error(
      'Unsupported source language: "' + Language + '". ' +
      'Expected ''pascal'' or ''c''. ' +
      'Note: python / cpp / csharp are TARGET languages, not SOURCE languages.');
    Exit;
  end;

  // ---- Reset stale intermediate results --------------------------------
  // GenerateSourceButtonClick also clears final_source_file_ListView at
  // its start; we clear the JSON editors here so the parse step starts
  // from a clean slate.
  try
    code_decl_to_abi_form.Cmb_LanguageSelector.ItemIndex := idx;
    // LCL does not always fire OnChange when ItemIndex is assigned
    // programmatically, so call the handler explicitly to keep the
    // form's `current_language` field in sync.
    code_decl_to_abi_form.Sel_Lang_ComboBoxChange(code_decl_to_abi_form.Cmb_LanguageSelector);

    code_decl_to_abi_form.Edit_Source.Text := Source;
    code_decl_to_abi_form.Edit_SourceJson.Text := '';
    code_decl_to_abi_form.Edit_ModelJson.Text := '';
    code_decl_to_abi_form.final_source_file_ListView.Items.Clear;
    code_decl_to_abi_form.final_Source_edit.Text := '';

    // ---- Step A : Source -> JSON ---------------------------------------
    code_decl_to_abi_form.source_2_json_nex_ButtonClick(nil);
    if code_decl_to_abi_form.Edit_SourceJson.Lines.Count = 0 then
    begin
      Result := Json_Error('Parsing failed: Source -> JSON produced no output. ' +
        'Check that the source text is a complete Pascal unit or C header.');
      Exit;
    end;

    // ---- Step B : JSON -> Model ----------------------------------------
    code_decl_to_abi_form.JsonToModelButtonClick(nil);
    if code_decl_to_abi_form.Edit_ModelJson.Lines.Count = 0 then
    begin
      Result := Json_Error('Model build failed: JSON -> Model produced no output. ' +
        'All routines may have been filtered out by the type whitelist.');
      Exit;
    end;

    // ---- Extract UnitName from the model JSON --------------------------
    unitName := '';
    joModel := TZ_JsonObject.Create;
    try
      if joModel.ParseText(code_decl_to_abi_form.Edit_ModelJson.Text) then
        unitName := joModel.S['UnitName'];
    finally
      joModel.Free;
    end;

    if unitName = '' then
    begin
      Result := Json_Error('Model UnitName is empty.');
      Exit;
    end;

    // ---- Step C : generate every artifact ------------------------------
    // This writes every code file and README to disk, and populates
    // final_source_file_ListView with one row per artifact.
    code_decl_to_abi_form.GenerateSourceButtonClick(nil);

    count := code_decl_to_abi_form.final_source_file_ListView.Items.Count;

    // ---- Build the success reply ---------------------------------------
    jo := TZ_JsonObject.Create;
    try
      jo.S['status'] := 'ok';
      jo.S['unit']   := unitName;
      jo.I['count']  := count;
      Result := jo.ToJSONString(False);
    finally
      jo.Free;
    end;
  except
    on E: Exception do
      Result := Json_Error('Generation failed: ' + E.Message);
  end;
end;

function Work_Get_Target_List: string;
var
  i: Integer;
  item: TListItem;
  jo: TZ_JsonObject;
  arr: TZ_JsonArray;
begin
  if code_decl_to_abi_form = nil then
  begin
    Result := Json_Error('GUI form is not available. The code_decl_to_abi executable is not running.');
    Exit;
  end;

  jo := TZ_JsonObject.Create;
  try
    arr := jo.A['files'];
    for i := 0 to code_decl_to_abi_form.final_source_file_ListView.Items.Count - 1 do
    begin
      item := code_decl_to_abi_form.final_source_file_ListView.Items[i];
      // The Caption holds the file NAME (no directory). SubItems[0]
      // holds the full path; it is not exposed here because the
      // contract of Step 2 is "file names only".
      arr.Add(item.Caption);
    end;
    jo.I['count'] := code_decl_to_abi_form.final_source_file_ListView.Items.Count;
    Result := jo.ToJSONString(False);
  finally
    jo.Free;
  end;
end;

function Work_Get_Target_Code(const FileName: string): string;
var
  i: Integer;
  item: TListItem;
  fullPath: string;
  sl: TPascalStringList;
  content: string;
  jo: TZ_JsonObject;
begin
  if code_decl_to_abi_form = nil then
  begin
    Result := Json_Error('GUI form is not available. The code_decl_to_abi executable is not running.');
    Exit;
  end;

  if FileName = '' then
  begin
    Result := Json_Error('FileName is empty.');
    Exit;
  end;

  // Locate the artifact by its Caption (which is the file name).
  // Comparison is exact and case-sensitive: this keeps the tool's
  // behaviour identical across case-insensitive filesystems.
  for i := 0 to code_decl_to_abi_form.final_source_file_ListView.Items.Count - 1 do
  begin
    item := code_decl_to_abi_form.final_source_file_ListView.Items[i];
    if item.Caption <> FileName then
      Continue;

    if item.SubItems.Count = 0 then
    begin
      Result := Json_Error('File "' + FileName + '" has no recorded path.');
      Exit;
    end;

    fullPath := item.SubItems[0];
    if not umlFileExists(fullPath) then
    begin
      Result := Json_Error('File "' + FileName + '" is no longer on disk.');
      Exit;
    end;

    content := '';
    sl := TPascalStringList.Create;
    try
      sl.LoadFromFile(fullPath);
      content := sl.AsText;
    finally
      sl.Free;
    end;

    jo := TZ_JsonObject.Create;
    try
      jo.S['name']    := FileName;
      jo.S['content'] := content;
      Result := jo.ToJSONString(False);
    finally
      jo.Free;
    end;
    Exit;
  end;

  Result := Json_Error('File "' + FileName + '" is not in the current target list. ' +
    'Call CodeDeclToAbi_GetTargetList first and pass one of the file names it returns.');
end;


// =============================================================================
// internal_call_* implementations
//
// Each function:
//   1. Marshals onto the main thread via TCompute.Sync.
//   2. Calls the matching Work_* helper on the main thread.
//   3. Returns the helper's JSON reply.
//
// FPC captures Result directly through a nested procedure; Delphi
// requires an explicit local temporary.
// =============================================================================

// ---- internal_call_CodeDeclToAbi_GenerateAll ----
function internal_call_CodeDeclToAbi_GenerateAll_CodeDeclToAbi_GenerateAll(Source: string; Language: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Generate_All(Source, Language);
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
    temp_ := Work_Generate_All(Source, Language);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- internal_call_CodeDeclToAbi_GetTargetList ----
function internal_call_CodeDeclToAbi_GetTargetList_CodeDeclToAbi_GetTargetList(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_Target_List;
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
    temp_ := Work_Get_Target_List;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- internal_call_CodeDeclToAbi_GetTargetCode ----
function internal_call_CodeDeclToAbi_GetTargetCode_CodeDeclToAbi_GetTargetCode(FileName: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := Work_Get_Target_Code(FileName);
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
    temp_ := Work_Get_Target_Code(FileName);
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
// ---- CodeDeclToAbi_GenerateAll (API: CodeDeclToAbi_GenerateAll) ----
procedure Callback_CodeDeclToAbi_GenerateAll_CodeDeclToAbi_GenerateAll(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToAbi_GenerateAll] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GenerateAll] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GenerateAll] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GenerateAll] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GenerateAll] Error: ' + errMsg);
      end;
      Exit;
    end;
    Source := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToAbi_GenerateAll_CodeDeclToAbi_GenerateAll(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GenerateAll] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GenerateAll] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GenerateAll] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GenerateAll] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetTargetList (API: CodeDeclToAbi_GetTargetList) ----
procedure Callback_CodeDeclToAbi_GetTargetList_CodeDeclToAbi_GetTargetList(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToAbi_GetTargetList] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetTargetList] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetTargetList] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetTargetList] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetTargetList] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToAbi_GetTargetList_CodeDeclToAbi_GetTargetList();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetTargetList] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetTargetList] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetTargetList] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetTargetList] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToAbi_GetTargetCode (API: CodeDeclToAbi_GetTargetCode) ----
procedure Callback_CodeDeclToAbi_GetTargetCode_CodeDeclToAbi_GetTargetCode(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  FileName: string;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    if DEBUG_LOG then
      DoStatus('[CodeDeclToAbi_GetTargetCode] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetTargetCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetTargetCode] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToAbi_GetTargetCode] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToAbi_GetTargetCode] Error: ' + errMsg);
      end;
      Exit;
    end;
    FileName := jo.S['FileName'];

    ret := internal_call_CodeDeclToAbi_GetTargetCode_CodeDeclToAbi_GetTargetCode(FileName);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToAbi_GetTargetCode] result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToAbi_GetTargetCode] result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToAbi_GetTargetCode] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToAbi_GetTargetCode] Exception: ' + E.Message);
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
    // Tool: CodeDeclToAbi_GenerateAll -> CodeDeclToAbi_GenerateAll
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GenerateAll';
      ToolDef.S['description'] := '(* [Step 1 of 3] Generate every target artifact from one declaration source. This is the primary entry point. It takes a complete Pascal unit or a complete C header, parses it once, and produces EVERY target artifact the code_decl_to_abi toolchain supports: Pascal service + call, Python service + call, C++ service + call, C# service + call + two console tests, plus one Markdown README per artifact. It writes all of them to disk and records them in the session so that Step 2 and Step 3 can retrieve them. The generator does not let you pick a target language. A single call produces artifacts for every supported target. You inspect them through the Step 2 list and retrieve them through the Step 3 reader. Parameters ---------- Source The complete declaration source text. For Language = '#39'pascal'#39', pass a full Pascal unit that begins with a unit declaration and contains an interface section. Top-level function and procedure declarations in that interface section are what gets extracted; everything else is ignored. For Language = '#39'c'#39', pass a full C header that begins with the include guard and contains the function prototypes. Top-level prototypes ending with a semicolon are what gets extracted; struct / enum / union / typedef declarations, global variables, and function definitions with bodies are ignored. Language The SOURCE language of the text in Source. Compared case- insensitively. Accepted values: '#39'pascal'#39'   the input text is a Pascal unit '#39'c'#39'        the input text is a C header Do NOT pass a TARGET language name such as '#39'python'#39', '#39'cpp'#39' or '#39'csharp'#39'. The tool always produces every target; you do not select one. Passing a target-language name here produces {"error":"Unsupported source language: ..."}. Return value ------------ A UTF-8 JSON string. Exactly one of: {"status":"ok","unit":"<U>","count":N} Generation succeeded. <U> is the unit name the parser extracted from the source. N is the number of artifacts that were written to disk and are now retrievable through Steps 2 and 3. {"error":"<message>"} Generation failed. <message> is a human-readable English description of what went wrong. Failure cases ------------- - Language is empty or is not one of '#39'pascal'#39' or '#39'c'#39'. - Language is a target-language name ('#39'python'#39' / '#39'cpp'#39' / '#39'csharp'#39'). - Source is empty or contains no top-level declarations that survive the ABI type whitelist. The whitelist accepts only the integer, float, and string families plus a handful of aliases; anything else causes the whole declaration to be dropped. - The parser rejected the input source text. - The host process is not running (the tool provider is not registered with the beacon). - Any underlying generator raised an internal exception. Side effects ------------ - The previous session state is replaced. Artifacts produced by an earlier GenerateAll call are no longer retrievable through Steps 2 and 3. - All artifacts are written to disk under the tool'#39's output directory. The exact location is decided by the host and is not part of this contract. - Step 2 and Step 3 report the new artifact set from the moment this call returns "ok". Notes ----- - The call is deterministic. The same Source and Language produce the same artifacts. There is no random component. - The call is synchronous. It does not return until every artifact has been written. - The "count" field is not a compile-time constant. It reflects how many routines survived parsing and the type whitelist, so it can change from one input unit to the next. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GenerateAll';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The complete declaration source text.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The SOURCE language of the text in Source. Accepted: ''pascal'' or ''c''.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GenerateAll')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GenerateAll');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetTargetList -> CodeDeclToAbi_GetTargetList
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetTargetList';
      ToolDef.S['description'] := '(* [Step 2 of 3] List the artifact FILE NAMES produced by Step 1. This is a pure reader. It never triggers a new generation and never changes any state. It reports the file names recorded by the most recent successful CodeDeclToAbi_GenerateAll call. The list contains file names, not paths. The order matches the order in which the generator produced the artifacts. Do not rely on the order; use the names. Prerequisites ------------- None. If CodeDeclToAbi_GenerateAll has not been called yet in this session, or if the last call failed, this function returns an empty list rather than an error. An empty list is a legal, expected result. Parameters ---------- None. Return value ------------ A UTF-8 JSON string. Exactly one of: {"count":N,"files":["<name1>","<name2>",...]} The N file names recorded by the most recent successful Step 1 call. {"count":0,"files":[]} No artifacts are currently available. The file names are the values you pass to Step 3 to retrieve the artifact content. They are file names only: no directory component, no drive letter, no URL prefix. Related tools ------------- CodeDeclToAbi_GenerateAll     produce the artifacts CodeDeclToAbi_GetTargetCode   read one artifact by name )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetTargetList';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetTargetList')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetTargetList');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToAbi_GetTargetCode -> CodeDeclToAbi_GetTargetCode
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToAbi_GetTargetCode';
      ToolDef.S['description'] := '(* [Step 3 of 3] Read one artifact by its FILE NAME. This is a pure reader. It never triggers a new generation and never changes any state. It returns the full text of one artifact produced by the most recent successful CodeDeclToAbi_GenerateAll call. Parameters ---------- FileName The exact file name reported by CodeDeclToAbi_GetTargetList. The value is a FILE NAME, not a path. Pass the string exactly as Step 2 returned it, including the extension. Do not prepend a directory, do not strip an extension, do not apply any case normalisation. The comparison is case-sensitive on every platform. Return value ------------ A UTF-8 JSON string. Exactly one of: {"name":"<file>","content":"<text>"} Success. <file> is the FileName you passed. <text> is the full UTF-8 text of the artifact. {"error":"..."} Failure. Three sub-cases are reported: - FileName is empty. - FileName does not appear in the current Step 2 list. - The artifact is known but its content is no longer available. Related tools ------------- CodeDeclToAbi_GenerateAll     produce the artifacts CodeDeclToAbi_GetTargetList   list the file names Notes ----- - The content is raw text. Binary content is never produced by the generator, so every artifact is a UTF-8 text file. - If you request the same file twice you get the same answer. The call is deterministic and idempotent. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToAbi_GetTargetCode';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['FileName'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The exact file name reported by CodeDeclToAbi_GetTargetList.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('FileName');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToAbi_GetTargetCode')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToAbi_GetTargetCode');
    finally
      ToolDef.Free;
    end;

    Result := (regCount = 3);
    if DEBUG_LOG then
      DoStatus('[RegisterTools] Registered %d out of %d tools.', [regCount, 3]);
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

  LF_RegisterCallEx(App, 'CodeDeclToAbi_GenerateAll', '(* [Step 1 of 3] Generate every target artifact from one declaration source. This is the primary entry point. It takes a complete Pascal unit or a complete C header, parses it once, and produces EVERY target artifact the code_decl_to_abi toolchain supports: Pascal service + call, Python service + call, C++ service + call, C# service + call + two console tests, plus one Markdown README per artifact. It writes all of them to disk and records them in the session so that Step 2 and Step 3 can retrieve them. The generator does not let you pick a target language. A single call produces artifacts for every supported target. You inspect them through the Step 2 list and retrieve them through the Step 3 reader. Parameters ---------- Source The complete declaration source text. For Language = '#39'pascal'#39', pass a full Pascal unit that begins with a unit declaration and contains an interface section. Top-level function and procedure declarations in that interface section are what gets extracted; everything else is ignored. For Language = '#39'c'#39', pass a full C header that begins with the include guard and contains the function prototypes. Top-level prototypes ending with a semicolon are what gets extracted; struct / enum / union / typedef declarations, global variables, and function definitions with bodies are ignored. Language The SOURCE language of the text in Source. Compared case- insensitively. Accepted values: '#39'pascal'#39'   the input text is a Pascal unit '#39'c'#39'        the input text is a C header Do NOT pass a TARGET language name such as '#39'python'#39', '#39'cpp'#39' or '#39'csharp'#39'. The tool always produces every target; you do not select one. Passing a target-language name here produces {"error":"Unsupported source language: ..."}. Return value ------------ A UTF-8 JSON string. Exactly one of: {"status":"ok","unit":"<U>","count":N} Generation succeeded. <U> is the unit name the parser extracted from the source. N is the number of artifacts that were written to disk and are now retrievable through Steps 2 and 3. {"error":"<message>"} Generation failed. <message> is a human-readable English description of what went wrong. Failure cases ------------- - Language is empty or is not one of '#39'pascal'#39' or '#39'c'#39'. - Language is a target-language name ('#39'python'#39' / '#39'cpp'#39' / '#39'csharp'#39'). - Source is empty or contains no top-level declarations that survive the ABI type whitelist. The whitelist accepts only the integer, float, and string families plus a handful of aliases; anything else causes the whole declaration to be dropped. - The parser rejected the input source text. - The host process is not running (the tool provider is not registered with the beacon). - Any underlying generator raised an internal exception. Side effects ------------ - The previous session state is replaced. Artifacts produced by an earlier GenerateAll call are no longer retrievable through Steps 2 and 3. - All artifacts are written to disk under the tool'#39's output directory. The exact location is decided by the host and is not part of this contract. - Step 2 and Step 3 report the new artifact set from the moment this call returns "ok". Notes ----- - The call is deterministic. The same Source and Language produce the same artifacts. There is no random component. - The call is synchronous. It does not return until every artifact has been written. - The "count" field is not a compile-time constant. It reflects how many routines survived parsing and the type whitelist, so it can change from one input unit to the next. )', nil, @Callback_CodeDeclToAbi_GenerateAll_CodeDeclToAbi_GenerateAll);  // Register API: CodeDeclToAbi_GenerateAll -> CodeDeclToAbi_GenerateAll
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetTargetList', '(* [Step 2 of 3] List the artifact FILE NAMES produced by Step 1. This is a pure reader. It never triggers a new generation and never changes any state. It reports the file names recorded by the most recent successful CodeDeclToAbi_GenerateAll call. The list contains file names, not paths. The order matches the order in which the generator produced the artifacts. Do not rely on the order; use the names. Prerequisites ------------- None. If CodeDeclToAbi_GenerateAll has not been called yet in this session, or if the last call failed, this function returns an empty list rather than an error. An empty list is a legal, expected result. Parameters ---------- None. Return value ------------ A UTF-8 JSON string. Exactly one of: {"count":N,"files":["<name1>","<name2>",...]} The N file names recorded by the most recent successful Step 1 call. {"count":0,"files":[]} No artifacts are currently available. The file names are the values you pass to Step 3 to retrieve the artifact content. They are file names only: no directory component, no drive letter, no URL prefix. Related tools ------------- CodeDeclToAbi_GenerateAll     produce the artifacts CodeDeclToAbi_GetTargetCode   read one artifact by name )', nil, @Callback_CodeDeclToAbi_GetTargetList_CodeDeclToAbi_GetTargetList);  // Register API: CodeDeclToAbi_GetTargetList -> CodeDeclToAbi_GetTargetList
  LF_RegisterCallEx(App, 'CodeDeclToAbi_GetTargetCode', '(* [Step 3 of 3] Read one artifact by its FILE NAME. This is a pure reader. It never triggers a new generation and never changes any state. It returns the full text of one artifact produced by the most recent successful CodeDeclToAbi_GenerateAll call. Parameters ---------- FileName The exact file name reported by CodeDeclToAbi_GetTargetList. The value is a FILE NAME, not a path. Pass the string exactly as Step 2 returned it, including the extension. Do not prepend a directory, do not strip an extension, do not apply any case normalisation. The comparison is case-sensitive on every platform. Return value ------------ A UTF-8 JSON string. Exactly one of: {"name":"<file>","content":"<text>"} Success. <file> is the FileName you passed. <text> is the full UTF-8 text of the artifact. {"error":"..."} Failure. Three sub-cases are reported: - FileName is empty. - FileName does not appear in the current Step 2 list. - The artifact is known but its content is no longer available. Related tools ------------- CodeDeclToAbi_GenerateAll     produce the artifacts CodeDeclToAbi_GetTargetList   list the file names Notes ----- - The content is raw text. Binary content is never produced by the generator, so every artifact is a UTF-8 text file. - If you request the same file twice you get the same answer. The call is deterministic and idempotent. )', nil, @Callback_CodeDeclToAbi_GetTargetCode_CodeDeclToAbi_GetTargetCode);  // Register API: CodeDeclToAbi_GetTargetCode -> CodeDeclToAbi_GetTargetCode
  if DEBUG_LOG then
    DoStatus('[RegisterAPIs] Registered APIs: 3 functions');
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
