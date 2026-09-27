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


function internal_call_CodeDeclToJsonAbi_Generate_CodeDeclToJsonAbi_Generate(Source: string; Language: string): string;
function internal_call_CodeDeclToJsonAbi_ListFiles_CodeDeclToJsonAbi_ListFiles(): string;
function internal_call_CodeDeclToJsonAbi_GetFile_CodeDeclToJsonAbi_GetFile(FileName: string): string;

implementation

uses
  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  code_decl_to_abi_json_frm;


// Forward declarations for all API callbacks
function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;
procedure Callback_CodeDeclToJsonAbi_Generate_CodeDeclToJsonAbi_Generate(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_ListFiles_CodeDeclToJsonAbi_ListFiles(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;
procedure Callback_CodeDeclToJsonAbi_GetFile_CodeDeclToJsonAbi_GetFile(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;

// =============================================================================
// Shared helper: escape a string for embedding inside a JSON string literal
// (used only on the failure path of Generate, to avoid pulling in an extra
// JSON object allocation for a one-off error message).
// =============================================================================
function _EscapeJsonString(const S: string): string;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #10:  Result := Result + '\n';
      #13:  Result := Result + '\r';
      #9:   Result := Result + '\t';
      else
        if Ord(S[i]) < 32 then
          Result := Result + '\u' + IntToHex(Ord(S[i]), 4)
        else
          Result := Result + S[i];
    end;
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_Generate
//
// Runs on a LingoFuse worker thread. All UI interaction MUST happen on the
// main thread, so the body is wrapped in TCompute.Sync.
//
// UI sequence:
//   1. Select source language in LanguageSelectorComboBox + fire change.
//   2. Push the source text into SourceCodeEditor.
//   3. ParseSourceToJsonClick    -> fills SourceJsonEditor
//   4. NormalizeJsonToModelClick -> fills ModelJsonEditor
//   5. GenerateAllSourcesClick   -> clears and refills final_source_file_ListView,
//                                   writes every artifact to disk under
//                                   <exe-dir>/<UnitName>/, and leaves
//                                   final_Source_edit showing the first entry.
//
// Returns a JSON string:
//   success: {"status":"ok","unit_name":"<unit>","count":26,"files":[...]}
//   failure: {"error":"<message>"}
// =============================================================================
function internal_call_CodeDeclToJsonAbi_Generate_CodeDeclToJsonAbi_Generate(Source: string; Language: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    lang: string;
    i, count: integer;
    resp, modelJo: TZ_JsonObject;
    fileArr: TZ_JsonArray;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := '{"error":"Form not available"}';
      Exit;
    end;

    // ---- Step 1: select source language ----
    lang := LowerCase(Trim(Language));
    if lang = 'pascal' then
    begin
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 1;
      code_decl_to_abi_json_form.LanguageSelectorChange(
        code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else if lang = 'c' then
    begin
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 2;
      code_decl_to_abi_json_form.LanguageSelectorChange(
        code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else
    begin
      Result := '{"error":"Unsupported language. Use ' +
        _EscapeJsonString('''pascal'' or ''c''') + '."}';
      Exit;
    end;

    // ---- Step 2: push source text into the editor ----
    code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;

    // ---- Steps 3..5: parse -> normalize -> generate ----
    try
      code_decl_to_abi_json_form.ParseSourceToJsonClick(
        code_decl_to_abi_json_form.ParseSourceToJsonButton);
      code_decl_to_abi_json_form.NormalizeJsonToModelClick(
        code_decl_to_abi_json_form.NormalizeJsonToModelButton);
      code_decl_to_abi_json_form.GenerateAllSourcesClick(
        code_decl_to_abi_json_form.GenerateAllSourcesButton);
    except
      on E: Exception do
      begin
        Result := '{"error":"' +
          _EscapeJsonString('Generation failed: ' + E.Message) + '"}';
        Exit;
      end;
    end;

    // ---- Read the produced file list from the ListView ----
    count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;

    resp := TZ_JsonObject.Create;
    try
      resp.S['status'] := 'ok';
      resp.I['count'] := count;

      // Try to read unit_name out of the model JSON the form just produced.
      modelJo := TZ_JsonObject.Create;
      try
        if modelJo.ParseText(code_decl_to_abi_json_form.ModelJsonEditor.Text) then
          resp.S['unit_name'] := modelJo.S['UnitName']
        else
          resp.S['unit_name'] := '';
      finally
        modelJo.Free;
      end;

      fileArr := resp.A['files'];
      for i := 0 to count - 1 do
        fileArr.Add(code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption);

      Result := resp.ToJSONString(False);
    finally
      resp.Free;
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
    lang: string;
    i, count: integer;
    resp, modelJo: TZ_JsonObject;
    fileArr: TZ_JsonArray;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := '{"error":"Form not available"}';
      Exit;
    end;

    lang := LowerCase(Trim(Language));
    if lang = 'pascal' then
    begin
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 1;
      code_decl_to_abi_json_form.LanguageSelectorChange(
        code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else if lang = 'c' then
    begin
      code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 2;
      code_decl_to_abi_json_form.LanguageSelectorChange(
        code_decl_to_abi_json_form.LanguageSelectorComboBox);
    end
    else
    begin
      temp_ := '{"error":"Unsupported language. Use ''pascal'' or ''c''."}';
      Exit;
    end;

    code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;

    try
      code_decl_to_abi_json_form.ParseSourceToJsonClick(
        code_decl_to_abi_json_form.ParseSourceToJsonButton);
      code_decl_to_abi_json_form.NormalizeJsonToModelClick(
        code_decl_to_abi_json_form.NormalizeJsonToModelButton);
      code_decl_to_abi_json_form.GenerateAllSourcesClick(
        code_decl_to_abi_json_form.GenerateAllSourcesButton);
    except
      on E: Exception do
      begin
        temp_ := '{"error":"' +
          _EscapeJsonString('Generation failed: ' + E.Message) + '"}';
        Exit;
      end;
    end;

    count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;

    resp := TZ_JsonObject.Create;
    try
      resp.S['status'] := 'ok';
      resp.I['count'] := count;

      modelJo := TZ_JsonObject.Create;
      try
        if modelJo.ParseText(code_decl_to_abi_json_form.ModelJsonEditor.Text) then
          resp.S['unit_name'] := modelJo.S['UnitName']
        else
          resp.S['unit_name'] := '';
      finally
        modelJo.Free;
      end;

      fileArr := resp.A['files'];
      for i := 0 to count - 1 do
        fileArr.Add(code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption);

      temp_ := resp.ToJSONString(False);
    finally
      resp.Free;
    end;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_ListFiles
//
// Runs on a LingoFuse worker thread. Reads the ListView contents on the
// main thread via TCompute.Sync.
//
// Returns a JSON string:
//   success: {"status":"ok","count":26,"files":["<name1>","<name2>",...]}
//   empty  : {"status":"error","count":0,"files":[]}
//
// Pure reader: does not re-run any generator, does not mutate the session.
// =============================================================================
function internal_call_CodeDeclToJsonAbi_ListFiles_CodeDeclToJsonAbi_ListFiles(): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    i, count: integer;
    resp: TZ_JsonObject;
    fileArr: TZ_JsonArray;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      Result := '{"status":"error","count":0,"files":[]}';
      Exit;
    end;

    count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;

    resp := TZ_JsonObject.Create;
    try
      resp.S['status'] := 'ok';
      resp.I['count'] := count;
      fileArr := resp.A['files'];
      for i := 0 to count - 1 do
        fileArr.Add(code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption);
      Result := resp.ToJSONString(False);
    finally
      resp.Free;
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
    i, count: integer;
    resp: TZ_JsonObject;
    fileArr: TZ_JsonArray;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := '{"status":"error","count":0,"files":[]}';
      Exit;
    end;

    count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;

    resp := TZ_JsonObject.Create;
    try
      resp.S['status'] := 'ok';
      resp.I['count'] := count;
      fileArr := resp.A['files'];
      for i := 0 to count - 1 do
        fileArr.Add(code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption);
      temp_ := resp.ToJSONString(False);
    finally
      resp.Free;
    end;
  end);
  Result := temp_;
{$ENDIF FPC}
end;

// =============================================================================
// internal_call_CodeDeclToJsonAbi_GetFile
//
// Runs on a LingoFuse worker thread. Reads one cached artifact on the
// main thread via TCompute.Sync.
//
// Lookup strategy: walk final_source_file_ListView, find the entry whose
// Caption matches FileName exactly, then load the file whose full path is
// stored in that entry's SubItems[0]. This mirrors what the UI itself does
// in final_source_file_ListViewSelectItem, but without relying on the
// selection callback firing (which it does not when the same item is
// already selected).
//
// Returns a JSON string:
//   success: {"status":"ok","name":"<name>","text":"<full text>"}
//   failure: {"status":"error","name":"<name>","error":"<message>"}
//
// The "text" field contains the entire artifact, never truncated. Multi-line
// content is embedded as a standard JSON string.
// =============================================================================
function internal_call_CodeDeclToJsonAbi_GetFile_CodeDeclToJsonAbi_GetFile(FileName: string): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    i: integer;
    found: boolean;
    filePath, textContent: string;
    resp: TZ_JsonObject;
    fs: TFileStream;
    bytes: TBytes;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      resp := TZ_JsonObject.Create;
      try
        resp.S['status'] := 'error';
        resp.S['name'] := FileName;
        resp.S['error'] := 'Form not available';
        Result := resp.ToJSONString(False);
      finally
        resp.Free;
      end;
      Exit;
    end;

    // ---- Locate the entry in the ListView ----
    found := False;
    filePath := '';
    for i := 0 to code_decl_to_abi_json_form.final_source_file_ListView.Items.Count - 1 do
      if code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption = FileName then
      begin
        if code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems.Count > 0 then
          filePath := code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems[0];
        found := True;
        Break;
      end;

    resp := TZ_JsonObject.Create;
    try
      resp.S['name'] := FileName;

      if not found then
      begin
        resp.S['status'] := 'error';
        resp.S['error'] := 'File not found. Call ListFiles first to get valid names.';
        Result := resp.ToJSONString(False);
        Exit;
      end;

      // ---- Read the file content as UTF-8 ----
      textContent := '';
      if FileExists(filePath) then
      begin
        fs := TFileStream.Create(filePath, fmOpenRead or fmShareDenyNone);
        try
          if fs.Size > 0 then
          begin
            SetLength(bytes, fs.Size);
            fs.ReadBuffer(bytes[0], fs.Size);
            textContent := TEncoding.UTF8.GetString(bytes);
          end;
        finally
          fs.Free;
        end;
      end;

      resp.S['status'] := 'ok';
      resp.S['text'] := textContent;
      Result := resp.ToJSONString(False);
    finally
      resp.Free;
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
    i: integer;
    found: boolean;
    filePath, textContent: string;
    resp: TZ_JsonObject;
    fs: TFileStream;
    bytes: TBytes;
  begin
    if code_decl_to_abi_json_form = nil then
    begin
      temp_ := '{"status":"error","name":"' +
        _EscapeJsonString(FileName) + '","error":"Form not available"}';
      Exit;
    end;

    found := False;
    filePath := '';
    for i := 0 to code_decl_to_abi_json_form.final_source_file_ListView.Items.Count - 1 do
      if code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption = FileName then
      begin
        if code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems.Count > 0 then
          filePath := code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems[0];
        found := True;
        Break;
      end;

    resp := TZ_JsonObject.Create;
    try
      resp.S['name'] := FileName;

      if not found then
      begin
        resp.S['status'] := 'error';
        resp.S['error'] := 'File not found. Call ListFiles first to get valid names.';
        temp_ := resp.ToJSONString(False);
        Exit;
      end;

      textContent := '';
      if FileExists(filePath) then
      begin
        fs := TFileStream.Create(filePath, fmOpenRead or fmShareDenyNone);
        try
          if fs.Size > 0 then
          begin
            SetLength(bytes, fs.Size);
            fs.ReadBuffer(bytes[0], fs.Size);
            textContent := TEncoding.UTF8.GetString(bytes);
          end;
        finally
          fs.Free;
        end;
      end;

      resp.S['status'] := 'ok';
      resp.S['text'] := textContent;
      temp_ := resp.ToJSONString(False);
    finally
      resp.Free;
    end;
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
// ---- CodeDeclToJsonAbi_Generate (API: CodeDeclToJsonAbi_Generate) ----
procedure Callback_CodeDeclToJsonAbi_Generate_CodeDeclToJsonAbi_Generate(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_Generate] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_Generate] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_Generate] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_Generate] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_Generate] Error: ' + errMsg);
      end;
      Exit;
    end;
    Source := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToJsonAbi_Generate_CodeDeclToJsonAbi_Generate(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_Generate] called with %s -> result: %s', [Source, Language, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToJsonAbi_Generate] called with %s', [Source, Language]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_Generate] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_Generate] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_ListFiles (API: CodeDeclToJsonAbi_ListFiles) ----
procedure Callback_CodeDeclToJsonAbi_ListFiles_CodeDeclToJsonAbi_ListFiles(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_ListFiles] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_ListFiles] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_ListFiles] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_ListFiles] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_ListFiles] Error: ' + errMsg);
      end;
      Exit;
    end;
    // No parameters
    ret := internal_call_CodeDeclToJsonAbi_ListFiles_CodeDeclToJsonAbi_ListFiles();
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_ListFiles] called (no params) -> result: %s', [ret2str(ret)]);
      SendLogAsync('[CodeDeclToJsonAbi_ListFiles] called (no params) -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_ListFiles] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_ListFiles] Exception: ' + E.Message);
      end;
    end;
  end;
  jo.Free;
end;

// ---- CodeDeclToJsonAbi_GetFile (API: CodeDeclToJsonAbi_GetFile) ----
procedure Callback_CodeDeclToJsonAbi_GetFile_CodeDeclToJsonAbi_GetFile(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
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
      DoStatus('[CodeDeclToJsonAbi_GetFile] Input JSON: %s', [TEncoding.UTF8.GetString(jsonBytes)]);

    if Length(jsonBytes) = 0 then
    begin
      errMsg := 'Empty input';
      jo.Clear;
      jo.S['error'] := errMsg;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetFile] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetFile] Error: ' + errMsg);
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
        DoStatus('[CodeDeclToJsonAbi_GetFile] Error: %s', [errMsg]);
        SendLogAsync('[CodeDeclToJsonAbi_GetFile] Error: ' + errMsg);
      end;
      Exit;
    end;
    FileName := jo.S['FileName'];

    ret := internal_call_CodeDeclToJsonAbi_GetFile_CodeDeclToJsonAbi_GetFile(FileName);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    if DEBUG_LOG then
    begin
      DoStatus('[CodeDeclToJsonAbi_GetFile] called with %s -> result: %s', [FileName, ret2str(ret)]);
      SendLogAsync(PFormat('[CodeDeclToJsonAbi_GetFile] called with %s', [FileName]) + ' -> result: ' + ret2str(ret));
    end;
  except
    on E: Exception do
    begin
      jo.Clear;
      jo.S['error'] := E.Message;
      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
      if DEBUG_LOG then
      begin
        DoStatus('[CodeDeclToJsonAbi_GetFile] Exception: %s', [E.Message]);
        SendLogAsync('[CodeDeclToJsonAbi_GetFile] Exception: ' + E.Message);
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
    // Tool: CodeDeclToJsonAbi_Generate -> CodeDeclToJsonAbi_Generate
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_Generate';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 1 of 2 - Generate every artifact. ROLE The only input tool. Parses the source text, builds the intermediate model, runs all eleven generators, and caches every produced artifact in the session. PREREQUISITE None. This is the first call. OUTPUT A JSON string. On success: { "status":    "ok", "unit_name": "<parsed unit name>", "count":     26, "files": [ "<Unit>_http_json_service_unit.pas", "<Unit>_http_json_service_pascal.md", "<Unit>_http_json_call_unit.pas", "<Unit>_http_json_call_pascal.md", "<Unit>_http_json_call.js", "<Unit>_http_json_call_js.md", "<Unit>_http_json_call_test.html", "<Unit>_http_json_service.py", "<Unit>_http_json_service_python.md", "<Unit>_http_json_call.py", "<Unit>_http_json_call_python.md", "<Unit>_http_json_service.cs", "<Unit>_http_json_service_csharp.md", "<Unit>_http_json_call.cs", "<Unit>_http_json_call_csharp.md", "<Unit>_http_json_service_main_test___.cs", "<Unit>_http_json_call_main_test___.cs", "<Unit>_http_json_test_csharp.md", "<Unit>_http_json_service.hpp", "<Unit>_http_json_service.cpp", "<Unit>_http_json_service_cpp.md", "<Unit>_http_json_call.hpp", "<Unit>_http_json_call.cpp", "<Unit>_http_json_call_cpp.md", "CMakeLists.txt", "test_main___.cpp" ] } On failure: {"error":"<message>"} The "count" field equals Length(files). It is always 26 on success. PARAMETERS Source Complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. Language The SOURCE language of Source. Accepted values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively. Do NOT pass a target language such as '#39'python'#39', '#39'cpp'#39', '#39'csharp'#39' or '#39'javascript'#39'. NOTES Calling Generate again replaces the session: the previous source text and every previously cached artifact are discarded. This is the only way to switch to a different source text. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_Generate';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['Source'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '          Complete source text.'#10'          For Language='#39'pascal'#39' pass a full Pascal unit that starts'#10'          with a unit declaration and contains an interface section.'#10'          For Language='#39'c'#39' pass a full C header that starts with the'#10'          include guard and contains the function prototypes.';
      PropObj := PropsObj.O['Language'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := '          The SOURCE language of Source. Accepted values are '#39'pascal'#39#10'          and '#39'c'#39' only, compared case-insensitively.'#10'          Do NOT pass a target language such as '#39'python'#39', '#39'cpp'#39','#10'          '#39'csharp'#39' or '#39'javascript'#39'.';
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('Source');
      RequiredArr.Add('Language');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_Generate')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_Generate');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_ListFiles -> CodeDeclToJsonAbi_ListFiles
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_ListFiles';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 2 of 2 - List every cached artifact. ROLE Return the file names of every artifact produced by the most recent successful CodeDeclToJsonAbi_Generate call. PREREQUISITE CodeDeclToJsonAbi_Generate must have succeeded first. OUTPUT A JSON string. On success: { "status": "ok", "count":  26, "files":  [ "<name 1>", "<name 2>", ... ] } On failure (Generate has not succeeded yet): { "status": "error", "count": 0, "files": [] } File names are relative. They are identical to what Generate reported in its own "files" array. Never invent a file name; use one of the names returned here. PARAMETERS None. NOTES ListFiles is a pure reader. It never re-runs any generator and never mutates the session. It is safe to call as many times as you like between Generate calls. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_ListFiles';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_ListFiles')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_ListFiles');
    finally
      ToolDef.Free;
    end;

    // Tool: CodeDeclToJsonAbi_GetFile -> CodeDeclToJsonAbi_GetFile
    ToolDef := TZ_JsonObject.Create;
    try
      ToolDef.S['name'] := 'CodeDeclToJsonAbi_GetFile';
      ToolDef.S['description'] := '(* [code_decl_to_json_abi] Step 2 of 2 - Read one cached artifact. ROLE Return the full text of one artifact produced by the most recent successful CodeDeclToJsonAbi_Generate call. PREREQUISITE CodeDeclToJsonAbi_Generate must have succeeded first, and FileName must be one of the names returned by CodeDeclToJsonAbi_ListFiles. OUTPUT A JSON string. On success: { "status": "ok", "name":   "<FileName>", "text":   "<full text of the artifact>" } The "text" field contains the complete artifact, never truncated. Multi-line content is embedded as a JSON string with standard JSON escaping; the caller should json.loads / decode the outer response and read "text" as a native string. On failure (Generate has not succeeded yet, or FileName was not among the produced artifacts): { "status": "error", "name":   "<FileName>", "error":  "<message>" } PARAMETERS FileName One of the file names returned by ListFiles. Case-sensitive and must match exactly. Example values: '#39'<Unit>_http_json_service_unit.pas'#39' '#39'<Unit>_http_json_service_python.md'#39' '#39'<Unit>_http_json_call.cs'#39' '#39'<Unit>_http_json_service.hpp'#39' '#39'CMakeLists.txt'#39' '#39'test_main___.cpp'#39' NOTES GetFile is a pure reader. It never re-runs any generator and never mutates the session. It is safe to call as many times as you like between Generate calls, including for different file names in the same session. Calling GetFile before Generate always fails with a "no generated artifacts" error; the caller should call Generate first. )';
      ToolDef.S['target_app'] := MY_APP_NAME;
      ToolDef.S['target_api'] := 'CodeDeclToJsonAbi_GetFile';

      ParamsObj := ToolDef.O['parameters'];
      ParamsObj.S['type'] := 'object';
      PropsObj := ParamsObj.O['properties'];
      PropObj := PropsObj.O['FileName'];
      PropObj.S['type'] := 'string';
      PropObj.S['description'] := 'must be one of the names returned by'#10'          One of the file names returned by ListFiles. Case-sensitive'#10'          and must match exactly. Example values:'#10'              '#39'<Unit>_http_json_service_unit.pas'#39#10'              '#39'<Unit>_http_json_service_python.md'#39#10'              '#39'<Unit>_http_json_call.cs'#39#10'              '#39'<Unit>_http_json_service.hpp'#39#10'              '#39'CMakeLists.txt'#39#10'              '#39'test_main___.cpp'#39;
      RequiredArr := ParamsObj.a['required'];
      RequiredArr.Add('FileName');
      Success := RegisterTool(ToolDef);
      if Success then Inc(regCount);
      if DEBUG_LOG then
        if Success then
          DoStatus('[RegisterTools] OK: CodeDeclToJsonAbi_GetFile')
        else
          DoStatus('[RegisterTools] FAIL: CodeDeclToJsonAbi_GetFile');
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

  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_Generate', '(* [code_decl_to_json_abi] Step 1 of 2 - Generate every artifact. ROLE The only input tool. Parses the source text, builds the intermediate model, runs all eleven generators, and caches every produced artifact in the session. PREREQUISITE None. This is the first call. OUTPUT A JSON string. On success: { "status":    "ok", "unit_name": "<parsed unit name>", "count":     26, "files": [ "<Unit>_http_json_service_unit.pas", "<Unit>_http_json_service_pascal.md", "<Unit>_http_json_call_unit.pas", "<Unit>_http_json_call_pascal.md", "<Unit>_http_json_call.js", "<Unit>_http_json_call_js.md", "<Unit>_http_json_call_test.html", "<Unit>_http_json_service.py", "<Unit>_http_json_service_python.md", "<Unit>_http_json_call.py", "<Unit>_http_json_call_python.md", "<Unit>_http_json_service.cs", "<Unit>_http_json_service_csharp.md", "<Unit>_http_json_call.cs", "<Unit>_http_json_call_csharp.md", "<Unit>_http_json_service_main_test___.cs", "<Unit>_http_json_call_main_test___.cs", "<Unit>_http_json_test_csharp.md", "<Unit>_http_json_service.hpp", "<Unit>_http_json_service.cpp", "<Unit>_http_json_service_cpp.md", "<Unit>_http_json_call.hpp", "<Unit>_http_json_call.cpp", "<Unit>_http_json_call_cpp.md", "CMakeLists.txt", "test_main___.cpp" ] } On failure: {"error":"<message>"} The "count" field equals Length(files). It is always 26 on success. PARAMETERS Source Complete source text. For Language='#39'pascal'#39' pass a full Pascal unit that starts with a unit declaration and contains an interface section. For Language='#39'c'#39' pass a full C header that starts with the include guard and contains the function prototypes. Language The SOURCE language of Source. Accepted values are '#39'pascal'#39' and '#39'c'#39' only, compared case-insensitively. Do NOT pass a target language such as '#39'python'#39', '#39'cpp'#39', '#39'csharp'#39' or '#39'javascript'#39'. NOTES Calling Generate again replaces the session: the previous source text and every previously cached artifact are discarded. This is the only way to switch to a different source text. )', nil, @Callback_CodeDeclToJsonAbi_Generate_CodeDeclToJsonAbi_Generate);  // Register API: CodeDeclToJsonAbi_Generate -> CodeDeclToJsonAbi_Generate
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_ListFiles', '(* [code_decl_to_json_abi] Step 2 of 2 - List every cached artifact. ROLE Return the file names of every artifact produced by the most recent successful CodeDeclToJsonAbi_Generate call. PREREQUISITE CodeDeclToJsonAbi_Generate must have succeeded first. OUTPUT A JSON string. On success: { "status": "ok", "count":  26, "files":  [ "<name 1>", "<name 2>", ... ] } On failure (Generate has not succeeded yet): { "status": "error", "count": 0, "files": [] } File names are relative. They are identical to what Generate reported in its own "files" array. Never invent a file name; use one of the names returned here. PARAMETERS None. NOTES ListFiles is a pure reader. It never re-runs any generator and never mutates the session. It is safe to call as many times as you like between Generate calls. )', nil, @Callback_CodeDeclToJsonAbi_ListFiles_CodeDeclToJsonAbi_ListFiles);  // Register API: CodeDeclToJsonAbi_ListFiles -> CodeDeclToJsonAbi_ListFiles
  LF_RegisterCallEx(App, 'CodeDeclToJsonAbi_GetFile', '(* [code_decl_to_json_abi] Step 2 of 2 - Read one cached artifact. ROLE Return the full text of one artifact produced by the most recent successful CodeDeclToJsonAbi_Generate call. PREREQUISITE CodeDeclToJsonAbi_Generate must have succeeded first, and FileName must be one of the names returned by CodeDeclToJsonAbi_ListFiles. OUTPUT A JSON string. On success: { "status": "ok", "name":   "<FileName>", "text":   "<full text of the artifact>" } The "text" field contains the complete artifact, never truncated. Multi-line content is embedded as a JSON string with standard JSON escaping; the caller should json.loads / decode the outer response and read "text" as a native string. On failure (Generate has not succeeded yet, or FileName was not among the produced artifacts): { "status": "error", "name":   "<FileName>", "error":  "<message>" } PARAMETERS FileName One of the file names returned by ListFiles. Case-sensitive and must match exactly. Example values: '#39'<Unit>_http_json_service_unit.pas'#39' '#39'<Unit>_http_json_service_python.md'#39' '#39'<Unit>_http_json_call.cs'#39' '#39'<Unit>_http_json_service.hpp'#39' '#39'CMakeLists.txt'#39' '#39'test_main___.cpp'#39' NOTES GetFile is a pure reader. It never re-runs any generator and never mutates the session. It is safe to call as many times as you like between Generate calls, including for different file names in the same session. Calling GetFile before Generate always fails with a "no generated artifacts" error; the caller should call Generate first. )', nil, @Callback_CodeDeclToJsonAbi_GetFile_CodeDeclToJsonAbi_GetFile);  // Register API: CodeDeclToJsonAbi_GetFile -> CodeDeclToJsonAbi_GetFile
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
