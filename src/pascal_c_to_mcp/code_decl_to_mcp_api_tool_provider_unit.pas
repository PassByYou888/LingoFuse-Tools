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


function internal_call_CodeDeclToMcp_GenerateAll_CodeDeclToMcp_GenerateAll(Source: string; Language: string): string;
function internal_call_CodeDeclToMcp_ListTargets_CodeDeclToMcp_ListTargets(): string;
function internal_call_CodeDeclToMcp_GetTarget_CodeDeclToMcp_GetTarget(FileName: string): string;

implementation

uses
  Forms, StdCtrls, ComCtrls, SynEdit,
  code_decl_to_mcp_frm,
  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine;


{$Region 'gui_bridge_'}
// ============================================================================
// GUI bridge helpers
// ----------------------------------------------------------------------------
// The three internal_* functions below are invoked on a LingoFuse worker
// thread. Every operation they perform touches LCL controls (a TSynEdit,
// a TComboBox and a TListView). LCL controls are not thread-safe, so all
// GUI access is wrapped in TCompute.Sync and executed on the LCL main
// thread.
//
// The bridge drives the GUI directly:
//
//   * The form instance is the global variable CodeDeclToMcpForm declared
//     in unit code_decl_to_mcp_frm. This unit already references this unit
//     through that unit's interface uses clause, so the reverse reference
//     is placed in the implementation uses clause to form the standard
//     FPC/Delphi circular-unit pattern.
//
//   * The three public workflow methods of TCodeDeclToMcpForm are called
//     directly:
//
//         ParseSourceToLv0Json       (same as clicking "Next: Pascal/C -> JSON")
//         BuildLv1ModelFromLv0Json   (same as clicking "Next: JSON <-> Model")
//         GenerateAllArtifacts       (same as clicking "Next: generate source")
//
//     These are the exact methods the GUI buttons invoke, so no button
//     Click is simulated and no control needs to be located by name.
//
//   * FCurrentLanguage, which decides how the source is parsed, is set by
//     the combo box OnChange handler. Setting ItemIndex fires OnChange
//     automatically, and the handler is invoked explicitly as a belt and
//     braces measure in case the current index already equals the target
//     index (in which case LCL would skip the event).
//
//   * The produced file list is read directly from
//     CodeDeclToMcpForm.final_source_file_ListView: each item's Caption is
//     the file NAME, and SubItems[0] is the absolute path on disk.
// ============================================================================

function JsonEscape(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;


// ----------------------------------------------------------------------------
// GUI work: generate every target from one source.
// ----------------------------------------------------------------------------

function GuiGenerateAll_OnMainThread(const Source, Language: string): string;
var
  LangLower: string;
  ComboIndex, Count: integer;
begin
  if Source = '' then
  begin
    Result := '{"error":"Source is empty"}';
    Exit;
  end;

  LangLower := LowerCase(Trim(Language));
  ComboIndex := 0;
  if LangLower = 'pascal' then
    ComboIndex := 1
  else if LangLower = 'c' then
    ComboIndex := 2;

  if ComboIndex = 0 then
  begin
    Result := '{"error":"Unrecognized Language; accepted values: pascal, c"}';
    Exit;
  end;

  if CodeDeclToMcpForm = nil then
  begin
    Result := '{"error":"GUI form not available"}';
    Exit;
  end;

  try
    // Step 1: place the source text into the editor.
    CodeDeclToMcpForm.SourceEdit.Text := Source;

    // Step 2: select the source language. Setting ItemIndex normally
    // fires OnChange, which updates FCurrentLanguage. We call the
    // handler explicitly as well, because LCL skips OnChange when the
    // new index equals the current one.
    CodeDeclToMcpForm.LanguageSelectorComboBox.ItemIndex := ComboIndex;
    CodeDeclToMcpForm.LanguageSelectorComboBoxChange(
      CodeDeclToMcpForm.LanguageSelectorComboBox);

    // Step 3: run the three workflow stages in the same order that a
    // human user would click through the wizard.
    CodeDeclToMcpForm.ParseSourceToLv0Json;
    CodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
    CodeDeclToMcpForm.GenerateAllArtifacts;
  except
    on E: Exception do
    begin
      Result := '{"error":"GUI operation failed: ' +
        JsonEscape(E.Message) + '"}';
      Exit;
    end;
  end;

  Count := CodeDeclToMcpForm.final_source_file_ListView.Items.Count;
  if Count = 0 then
    Result := '{"error":"No target files were produced; ' +
      'the source may contain no supported routines"}'
  else
    Result := '{"status":"ok","count":' + IntToStr(Count) + '}';
end;


// ----------------------------------------------------------------------------
// GUI work: list the target file names.
// ----------------------------------------------------------------------------

function GuiListTargets_OnMainThread: string;
var
  ListView: TListView;
  i: integer;
  First: boolean;
  Temp: string;
begin
  if CodeDeclToMcpForm = nil then
  begin
    Result := '{"error":"GUI form not available"}';
    Exit;
  end;

  ListView := CodeDeclToMcpForm.final_source_file_ListView;

  try
    Temp := '{"files":[';
    First := True;
    for i := 0 to ListView.Items.Count - 1 do
    begin
      if not First then
        Temp := Temp + ',';
      First := False;
      Temp := Temp + '"' + JsonEscape(ListView.Items[i].Caption) + '"';
    end;
    Temp := Temp + '],"count":' + IntToStr(ListView.Items.Count) + '}';
    Result := Temp;
  except
    on E: Exception do
      Result := '{"error":"GUI operation failed: ' +
        JsonEscape(E.Message) + '"}';
  end;
end;


// ----------------------------------------------------------------------------
// GUI work: read one target file by name.
//
// Uses the absolute path stored in the listview SubItems[0] rather than
// relying on a selection-driven editor reload. This makes the result
// independent of the current selection state and of the OnSelectItem
// event's timing.
// ----------------------------------------------------------------------------

function GuiGetTarget_OnMainThread(const FileName: string): string;
var
  ListView: TListView;
  i: integer;
  Item: TListItem;
  FullPath: string;
  fs: TFileStream;
  Bytes: TBytes;
begin
  if FileName = '' then
  begin
    Result := '{"error":"FileName is empty"}';
    Exit;
  end;

  if CodeDeclToMcpForm = nil then
  begin
    Result := '{"error":"GUI form not available"}';
    Exit;
  end;

  ListView := CodeDeclToMcpForm.final_source_file_ListView;

  try
    FullPath := '';
    for i := 0 to ListView.Items.Count - 1 do
    begin
      Item := ListView.Items[i];
      if Item.Caption = FileName then
      begin
        if Item.SubItems.Count > 0 then
          FullPath := Item.SubItems[0];
        Break;
      end;
    end;

    if FullPath = '' then
    begin
      Result := '{"error":"FileName not in the current target set: ' +
        JsonEscape(FileName) + '"}';
      Exit;
    end;

    if not FileExists(FullPath) then
    begin
      Result := '{"error":"Target file not found on disk: ' +
        JsonEscape(FullPath) + '"}';
      Exit;
    end;

    fs := TFileStream.Create(FullPath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, fs.Size);
      if fs.Size > 0 then
        fs.ReadBuffer(Bytes[0], fs.Size);
    finally
      fs.Free;
    end;

    Result := TEncoding.UTF8.GetString(Bytes);
  except
    on E: Exception do
      Result := '{"error":"GUI operation failed: ' +
        JsonEscape(E.Message) + '"}';
  end;
end;

{$EndRegion 'gui_bridge_'}


// Forward declarations for all API callbacks
function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;
procedure Callback_CodeDeclToMcp_GenerateAll_CodeDeclToMcp_GenerateAll(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_ListTargets_CodeDeclToMcp_ListTargets(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToMcp_GetTarget_CodeDeclToMcp_GetTarget(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;


// ---- Internal wrapper for CodeDeclToMcp_GenerateAll ----
// Runs on a LingoFuse worker thread. GUI access is marshalled to the LCL
// main thread via TCompute.Sync. The worker thread blocks until the main
// thread has finished the full generate-all pipeline.
function internal_call_CodeDeclToMcp_GenerateAll_CodeDeclToMcp_GenerateAll(Source: string; Language: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := GuiGenerateAll_OnMainThread(Source, Language);
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
  Result := '';
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := GuiGenerateAll_OnMainThread(Source, Language);
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Internal wrapper for CodeDeclToMcp_ListTargets ----
// Pure reader. No parameters. Runs on a LingoFuse worker thread; the
// listview read is marshalled to the LCL main thread.
function internal_call_CodeDeclToMcp_ListTargets_CodeDeclToMcp_ListTargets(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := GuiListTargets_OnMainThread;
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
  Result := '';
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := GuiListTargets_OnMainThread;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// ---- Internal wrapper for CodeDeclToMcp_GetTarget ----
// Pure reader. Runs on a LingoFuse worker thread; the listview lookup and
// the file read are marshalled to the LCL main thread.
function internal_call_CodeDeclToMcp_GetTarget_CodeDeclToMcp_GetTarget(FileName: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    Result := GuiGetTarget_OnMainThread(FileName);
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
  Result := '';
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    temp_ := GuiGetTarget_OnMainThread(FileName);
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
// ---- CodeDeclToMcp_GenerateAll (API: CodeDeclToMcp_GenerateAll) ----
procedure Callback_CodeDeclToMcp_GenerateAll_CodeDeclToMcp_GenerateAll(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GenerateAll] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GenerateAll] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GenerateAll] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GenerateAll] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GenerateAll] Error: ' + errMsg);
      end;
      Exit;
    end;
    Source := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToMcp_GenerateAll_CodeDeclToMcp_GenerateAll(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GenerateAll] called with %s -> result: %s', [Source, Language, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToMcp_GenerateAll] called with %s', [Source, Language]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GenerateAll] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GenerateAll] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_ListTargets (API: CodeDeclToMcp_ListTargets) ----
procedure Callback_CodeDeclToMcp_ListTargets_CodeDeclToMcp_ListTargets(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_ListTargets] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ListTargets] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ListTargets] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_ListTargets] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_ListTargets] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToMcp_ListTargets_CodeDeclToMcp_ListTargets();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_ListTargets] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToMcp_ListTargets] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_ListTargets] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_ListTargets] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToMcp_GetTarget (API: CodeDeclToMcp_GetTarget) ----
procedure Callback_CodeDeclToMcp_GetTarget_CodeDeclToMcp_GetTarget(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToMcp_GetTarget] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetTarget] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetTarget] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToMcp_GetTarget] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToMcp_GetTarget] Error: ' + errMsg);
      end;
      Exit;
    end;
    FileName := jo.S['FileName'];

    ret := internal_call_CodeDeclToMcp_GetTarget_CodeDeclToMcp_GetTarget(FileName);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToMcp_GetTarget] called with %s -> result: %s', [FileName, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToMcp_GetTarget] called with %s', [FileName]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToMcp_GetTarget] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToMcp_GetTarget] Exception: ' + E.Message);
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
    // Tool: CodeDeclToMcp_GenerateAll -> CodeDeclToMcp_GenerateAll
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GenerateAll';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 1/3 - Generate every target from one source. This is the ONLY write call in the workflow. It performs the entire pipeline in a single round trip: 1. Parse the source text according to Language. 2. Build the internal function model. 3. Run every code generator and every README generator. 4. Write every produced file to disk. 5. Return the total number of target files written. A successful call REPLACES the entire target set produced by any previous CodeDeclToMcp_GenerateAll call. It is safe to call this function repeatedly with different sources. Source: The complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. All parameters of every supported routine must use one of the normalized types: int64, double, or string. Any routine whose signature uses any other type (Boolean, Variant, arrays, records, classes, interfaces, enums, sets, pointers, TDateTime, ...) is silently dropped from the generated output. If you need to pass a complex value, serialize it into a string on the source side. Language: The SOURCE language of the text passed in Source. Accepted values, compared case-insensitively, are: pascal   the source text is a Pascal unit c        the source text is a C header Do NOT pass a target language such as '#39'python'#39', '#39'cpp'#39' or '#39'csharp'#39'. All target languages are produced automatically; there is no per-target selection parameter. Return value: a JSON string. On success: {"status":"ok","count":<N>} where <N> is the total number of target files written. Use CodeDeclToMcp_ListTargets to obtain their names, and CodeDeclToMcp_GetTarget to read any one of them. On failure: {"error":"<message>"} Typical failure reasons: empty Source, unrecognized Language, parser rejected the source, or every routine in the source was filtered out by the type whitelist. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GenerateAll';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The complete source text. For Language='#39'pascal'#39' pass a full'#10'      Pascal unit that starts with a unit declaration and contains an'#10'      interface section. For Language='#39'c'#39' pass a full C header that'#10'      starts with the include guard and contains the function'#10'      prototypes.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The SOURCE language of the text passed in Source. Accepted'#10'      values, compared case-insensitively, are:'#10', parser rejected the source, or every routine in';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GenerateAll')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GenerateAll');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_ListTargets -> CodeDeclToMcp_ListTargets
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_ListTargets';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 2/3 - List the target file names. Returns the names of every target file produced by the most recent successful CodeDeclToMcp_GenerateAll call. Only the file NAME is returned; the directory is not included, and neither is any file content. This is a pure reader. It never triggers a new generation and it never requires the caller to re-supply the source. Prerequisite: At least one successful CodeDeclToMcp_GenerateAll call must have happened earlier in the session. If it has not, the response is an empty file list, not an error. Return value: a JSON string. On success: {"files":["<name1>","<name2>",...],"count":<N>} The "files" array is the authoritative list of file names. The order is the order in which the files were written. The "count" value matches the length of the "files" array and, on a successful Step 1, matches the "count" returned by CodeDeclToMcp_GenerateAll. On failure: {"error":"<message>"} Typical usage: 1. Call CodeDeclToMcp_GenerateAll(Source, Language). 2. Call CodeDeclToMcp_ListTargets and iterate over the "files" array. 3. For each name you actually need, call CodeDeclToMcp_GetTarget(name). )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_ListTargets';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_ListTargets')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_ListTargets');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToMcp_GetTarget -> CodeDeclToMcp_GetTarget
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToMcp_GetTarget';
      ToolDef.S['description'] := '(* [code_decl_to_mcp] Step 3/3 - Read one target file by name. Given a file name returned by CodeDeclToMcp_ListTargets, returns the full text of that file. This is a pure reader. It never triggers a new generation, it never requires the caller to re-supply the source, and it does not modify any file on disk. Prerequisite: CodeDeclToMcp_GenerateAll must have succeeded earlier in the session, and FileName must be one of the names returned by the matching CodeDeclToMcp_ListTargets call. FileName: The exact file name, character for character, as returned by CodeDeclToMcp_ListTargets. Do NOT pass an absolute path, a relative path, or a wildcard. Do NOT add or remove the directory portion. Just the bare name. Return value: a string. On success: The full text of the requested file. This is the raw file content, not a JSON envelope, so it can be very large (a README is typically tens of kilobytes, and generated source files can be larger). On failure: A JSON error object of the form {"error":"<message>"}. Typical failure reasons: no successful Step 1 call yet, or FileName does not match any name in the current target set. Distinguishing success from failure: A successful response is the raw file text. A failed response is a single-line JSON object whose first non-whitespace character is '#39'{'#39' and which contains an "error" key. Since none of the generated target files start with that exact pattern, the caller can reliably tell the two apart. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToMcp_GetTarget';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['FileName'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '      The exact file name, character for character, as returned by'#10'      CodeDeclToMcp_ListTargets. Do NOT pass an absolute path, a'#10'      relative path, or a wildcard. Do NOT add or remove the'#10'      directory portion. Just the bare name.'#10'does not match any name in the current target set.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('FileName');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToMcp_GetTarget')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToMcp_GetTarget');
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

  LF_RegisterCallEx(App, 'CodeDeclToMcp_GenerateAll', '(* [code_decl_to_mcp] Step 1/3 - Generate every target from one source. This is the ONLY write call in the workflow. It performs the entire pipeline in a single round trip: 1. Parse the source text according to Language. 2. Build the internal function model. 3. Run every code generator and every README generator. 4. Write every produced file to disk. 5. Return the total number of target files written. A successful call REPLACES the entire target set produced by any previous CodeDeclToMcp_GenerateAll call. It is safe to call this function repeatedly with different sources. Source: The complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. All parameters of every supported routine must use one of the normalized types: int64, double, or string. Any routine whose signature uses any other type (Boolean, Variant, arrays, records, classes, interfaces, enums, sets, pointers, TDateTime, ...) is silently dropped from the generated output. If you need to pass a complex value, serialize it into a string on the source side. Language: The SOURCE language of the text passed in Source. Accepted values, compared case-insensitively, are: pascal   the source text is a Pascal unit c        the source text is a C header Do NOT pass a target language such as '#39'python'#39', '#39'cpp'#39' or '#39'csharp'#39'. All target languages are produced automatically; there is no per-target selection parameter. Return value: a JSON string. On success: {"status":"ok","count":<N>} where <N> is the total number of target files written. Use CodeDeclToMcp_ListTargets to obtain their names, and CodeDeclToMcp_GetTarget to read any one of them. On failure: {"error":"<message>"} Typical failure reasons: empty Source, unrecognized Language, parser rejected the source, or every routine in the source was filtered out by the type whitelist. )', nil, @Callback_CodeDeclToMcp_GenerateAll_CodeDeclToMcp_GenerateAll);  // Register API: CodeDeclToMcp_GenerateAll -> CodeDeclToMcp_GenerateAll
  LF_RegisterCallEx(App, 'CodeDeclToMcp_ListTargets', '(* [code_decl_to_mcp] Step 2/3 - List the target file names. Returns the names of every target file produced by the most recent successful CodeDeclToMcp_GenerateAll call. Only the file NAME is returned; the directory is not included, and neither is any file content. This is a pure reader. It never triggers a new generation and it never requires the caller to re-supply the source. Prerequisite: At least one successful CodeDeclToMcp_GenerateAll call must have happened earlier in the session. If it has not, the response is an empty file list, not an error. Return value: a JSON string. On success: {"files":["<name1>","<name2>",...],"count":<N>} The "files" array is the authoritative list of file names. The order is the order in which the files were written. The "count" value matches the length of the "files" array and, on a successful Step 1, matches the "count" returned by CodeDeclToMcp_GenerateAll. On failure: {"error":"<message>"} Typical usage: 1. Call CodeDeclToMcp_GenerateAll(Source, Language). 2. Call CodeDeclToMcp_ListTargets and iterate over the "files" array. 3. For each name you actually need, call CodeDeclToMcp_GetTarget(name). )', nil, @Callback_CodeDeclToMcp_ListTargets_CodeDeclToMcp_ListTargets);  // Register API: CodeDeclToMcp_ListTargets -> CodeDeclToMcp_ListTargets
  LF_RegisterCallEx(App, 'CodeDeclToMcp_GetTarget', '(* [code_decl_to_mcp] Step 3/3 - Read one target file by name. Given a file name returned by CodeDeclToMcp_ListTargets, returns the full text of that file. This is a pure reader. It never triggers a new generation, it never requires the caller to re-supply the source, and it does not modify any file on disk. Prerequisite: CodeDeclToMcp_GenerateAll must have succeeded earlier in the session, and FileName must be one of the names returned by the matching CodeDeclToMcp_ListTargets call. FileName: The exact file name, character for character, as returned by CodeDeclToMcp_ListTargets. Do NOT pass an absolute path, a relative path, or a wildcard. Do NOT add or remove the directory portion. Just the bare name. Return value: a string. On success: The full text of the requested file. This is the raw file content, not a JSON envelope, so it can be very large (a README is typically tens of kilobytes, and generated source files can be larger). On failure: A JSON error object of the form {"error":"<message>"}. Typical failure reasons: no successful Step 1 call yet, or FileName does not match any name in the current target set. Distinguishing success from failure: A successful response is the raw file text. A failed response is a single-line JSON object whose first non-whitespace character is '#39'{'#39' and which contains an "error" key. Since none of the generated target files start with that exact pattern, the caller can reliably tell the two apart. )', nil, @Callback_CodeDeclToMcp_GetTarget_CodeDeclToMcp_GetTarget);  // Register API: CodeDeclToMcp_GetTarget -> CodeDeclToMcp_GetTarget
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
