unit pas_mcp_generator_tool;

{*******************************************************************************
 * pas_mcp_generator_tool - LingoFuse Tool Provider Code & Doc Generator
 *
 * Produces two artifacts from one TPascal_Func_Model:
 *
 *   1. GeneratePascalCode()   -> <unit>_tool_provider_unit.pas
 *      A complete Pascal unit that registers every supported top-level
 *      function as a LingoFuse Call API and advertises each API as an MCP
 *      tool through the beacon.
 *
 *   2. GeneratePascalReadme() -> <unit>_tool_provider_pascal.md
 *      An English Markdown user guide that documents:
 *        - runtime architecture
 *        - a COMPLETE, COPY-PASTE-READY test .lpr program
 *        - a step-by-step build & test procedure
 *        - every exposed tool with JSON input/output examples
 *        - Delphi portability notes
 *        - debugging and troubleshooting
 *
 * =============================================================================
 * NOTES
 * =============================================================================
 *   - Fixed beacon application name: 'agent_main_app'
 *   - Fixed IPC endpoint          : 'ipc:agent'
 *   - Nested routines (NestLevel <> 0) are skipped by the model itself.
 *   - The README references LingoFuse-pasAgent-v3, ZCore, and ZNetV2 as the
 *     runtime dependencies; their URLs appear as placeholders. Replace them
 *     with actual clone URLs before distributing.
 *   - All README content is generated in English.
 * ****************************************************************************}

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

{$IFDEF FPC}
  {$CODEPAGE UTF8}
{$ENDIF FPC}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

{* Generate the Pascal tool provider unit. Caller owns the returned list. *}
function GeneratePascalCode(Model: TPascal_Func_Model): TPascalStringList;

{* Generate the English Markdown README. Caller owns the returned list. *}
function GeneratePascalReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_mcp_generator] %s', [Msg.Text]);
end;

// -----------------------------------------------------------------------------
// Type helpers
// -----------------------------------------------------------------------------

function IsSupportedType(const Typ: TP_String): boolean;
begin
  Result := Typ.Same('int64', 'double', 'string');
end;

function PascalTypeToJsonType(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := 'integer'
  else if Typ.Same('double') then Result := 'number'
  else if Typ.Same('string') then Result := 'string'
  else
    Result := 'string';
end;

function PascalTypeToJsonLiteral(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := '0'
  else if Typ.Same('double') then Result := '0.0'
  else if Typ.Same('string') then Result := '""'
  else
    Result := 'null';
end;

// -----------------------------------------------------------------------------
// Name helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function MakeCallbackName(const FuncName: TP_String): TP_String;
begin
  Result := 'Callback_' + MakeApiName(FuncName);
end;

function MakeInternalCallName(const FuncName: TP_String): TP_String;
begin
  Result := 'internal_call_' + MakeApiName(FuncName);
end;

function PascalStrLit(const S: TP_String): TP_String;
begin
  Result := TTextParsing.Translate_Text_To_Pascal_Decl(S);
end;

// -----------------------------------------------------------------------------
// Comment normalisation
// -----------------------------------------------------------------------------

function GetFullDescription(const Comment: TP_String): TP_String;
var
  Lines: TPascalStringList;
  i: integer;
  Line: TP_String;
begin
  Result := '';
  if Comment = '' then Exit;

  Lines := TPascalStringList.Create;
  try
    Lines.AsText := Comment;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := TP_String(Lines[i]);
      Line := Line.TrimChar(#32#9);
      if Line.Len = 0 then Continue;
      if Line[1] = '@' then Continue;
      if Line[1] = '*' then
        Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
      if (Line.Len > 0) and (Line[1] = '*') then
        Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
      if Line.Len > 0 then
      begin
        if Result.Len > 0 then Result := Result + ' ';
        Result := Result + Line;
      end;
    end;
  finally
    Lines.Free;
  end;
  Result := Result.TrimChar(#32#9);
end;

function GetTableCellText(const Comment: TP_String): TP_String;
begin
  Result := GetFullDescription(Comment);
  Result := Result.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// -----------------------------------------------------------------------------
// Shared function filtering
// -----------------------------------------------------------------------------

type
  TValidFuncArray = array of TFunctionStructure;

function CollectValidFunctions(Model: TPascal_Func_Model): TValidFuncArray;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  if Model = nil then Exit;

  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(f.Params) do
      if not IsSupportedType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": param "%s" has unsupported type "%s"', [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and not IsSupportedType(f.ReturnType) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" unsupported', [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

// =============================================================================
// SECTION 1 - Pascal code generator
// =============================================================================

function GeneratePascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TValidFuncArray;
  UnitName, AppName, BeaconApp, RegisterApi, AgentLogApi, IpcEndpoint: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  ExtractCode, CallArgs: TP_String;
  Description: TP_String;
  ParamName: TP_String;
  tmp: TP_String;

  HeaderLines, InterfaceLines, UsesLines, ForwardLines: TPascalStringList;
  Interface_InternalCallLines, InternalCallLines: TPascalStringList;
  Ret2StrLines, LoggingLines, CallbackLines: TPascalStringList;
  RegisterToolLines, RegisterAPIsLines, ExecuteLines, ResultLines: TPascalStringList;

  function BuildParamDecl(const Params: TParamArray): TP_String;
  var
    k: integer;
  begin
    Result := '';
    for k := 0 to High(Params) do
    begin
      if k > 0 then Result := Result + '; ';
      Result := Result + Params[k].Name + ': ' + Params[k].PascalType;
    end;
  end;

  function BuildArgList(const Params: TParamArray): TP_String;
  var
    k: integer;
  begin
    Result := '';
    for k := 0 to High(Params) do
    begin
      if k > 0 then Result := Result + ', ';
      Result := Result + Params[k].Name;
    end;
  end;

begin
  Result := nil;
  if Model = nil then begin
    Log('GeneratePascalCode: model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName = '' then begin
    Log('GeneratePascalCode: UnitName is empty.');
    Exit;
  end;

  AppName := UnitName;
  if umlMultipleMatch('*.pas', AppName) then
    AppName := umlChangeFileExt(AppName.Text, '').Text;
  AppName := AppName.ReplaceChar('.', '_').ReplaceChar('-', '_');

  BeaconApp := 'agent_main_app';
  RegisterApi := 'register_agent';
  AgentLogApi := 'agent_log';
  IpcEndpoint := 'ipc:agent';

  Log(PFormat('Generating code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectValidFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported functions; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceLines := TPascalStringList.Create;
  UsesLines := TPascalStringList.Create;
  ForwardLines := TPascalStringList.Create;
  Interface_InternalCallLines := TPascalStringList.Create;
  InternalCallLines := TPascalStringList.Create;
  Ret2StrLines := TPascalStringList.Create;
  LoggingLines := TPascalStringList.Create;
  CallbackLines := TPascalStringList.Create;
  RegisterToolLines := TPascalStringList.Create;
  RegisterAPIsLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // ---- 1. Unit header ----
    HeaderLines.Add('unit ' + UnitName + '_tool_provider_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('{$ifdef FPC}');
    HeaderLines.Add('  {$mode delphi}');
    HeaderLines.Add('  {$MODESWITCH NestedProcVars}');
    HeaderLines.Add('  {$modeswitch advancedrecords}');
    HeaderLines.Add('  {$MODESWITCH NESTEDCOMMENTS}');
    HeaderLines.Add('  {$CODEPAGE UTF8}');
    HeaderLines.Add('{$endif}');
    HeaderLines.Add('{$H+}');
    HeaderLines.Add('{$R-}');
    HeaderLines.Add('{$I-}');
    HeaderLines.Add('{$Q-}');
    HeaderLines.Add('{$B-}');
    HeaderLines.Add('');
    HeaderLines.Add('interface');
    HeaderLines.Add('');

    // ---- 2. Interface ----
    InterfaceLines.Add('uses');
    InterfaceLines.Add('  SysUtils, Classes,');
    InterfaceLines.Add('  lingofuse_import;');
    InterfaceLines.Add('');
    InterfaceLines.Add('// ---- Exported global var ----');
    InterfaceLines.Add('var');
    InterfaceLines.Add('  MY_APP_NAME : string = ' + PascalStrLit(AppName) + ';');
    InterfaceLines.Add('  MY_APP_DESC : string = ' + PascalStrLit('Tool provider for unit ' + UnitName) + ';');
    InterfaceLines.Add('  IPC_ENDPOINT : string = ' + PascalStrLit(IpcEndpoint) + ';');
    InterfaceLines.Add('  BEACON_APP : string = ' + PascalStrLit(BeaconApp) + ';');
    InterfaceLines.Add('  REGISTER_API : string = ' + PascalStrLit(RegisterApi) + ';');
    InterfaceLines.Add('  AGENT_LOG_API : string = ' + PascalStrLit(AgentLogApi) + ';');
    InterfaceLines.Add('  DEBUG_LOG : boolean = True;');
    InterfaceLines.Add('');
    InterfaceLines.Add('// ---- Exported functions ----');
    InterfaceLines.Add('{*');
    InterfaceLines.Add(' * RegisterAPIs - Creates the LingoFuse application and registers all');
    InterfaceLines.Add(' * generated Call APIs. Returns the application handle, or nil on failure.');
    InterfaceLines.Add(' * The caller is responsible for freeing the handle with LF_FreeApp.');
    InterfaceLines.Add(' *}');
    InterfaceLines.Add('function RegisterAPIs: TAppHnd___;');
    InterfaceLines.Add('');
    InterfaceLines.Add('{*');
    InterfaceLines.Add(' * RegisterTools - Connects to the beacon, registers all APIs as tools');
    InterfaceLines.Add(' * with JSON schemas, and returns True if all registrations succeeded.');
    InterfaceLines.Add(' *}');
    InterfaceLines.Add('function RegisterTools: Boolean;');
    InterfaceLines.Add('');
    InterfaceLines.Add('{**');
    InterfaceLines.Add(' * Execute_And_Reg_all - One-click startup and tool registration.');
    InterfaceLines.Add(' *');
    InterfaceLines.Add(' * Sequence:');
    InterfaceLines.Add(' *   1. RegisterAPIs       : create App + register all Call APIs');
    InterfaceLines.Add(' *   2. LF_PrepareClient   : connect to IPC_ENDPOINT with the App');
    InterfaceLines.Add(' *   3. LF_PrepareDone     : wait until the client is ready');
    InterfaceLines.Add(' *   4. RegisterTools      : advertise every tool to the beacon');
    InterfaceLines.Add(' *');
    InterfaceLines.Add(' * @return True when all four steps succeeded.');
    InterfaceLines.Add(' *}');
    InterfaceLines.Add('function Execute_And_Reg_all: Boolean;');
    InterfaceLines.Add('');

    // ---- 3. Uses (implementation) ----
    UsesLines.Add('uses');
    UsesLines.Add('  Z.Core, Z.Json, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib, Z.ListEngine;');
    UsesLines.Add('');

    ForwardLines.Add('');
    ForwardLines.Add('// Forward declarations for all API callbacks');
    ForwardLines.Add('function RegisterTool(const ToolDef: TZ_JsonObject): boolean; forward;');

    // ---- 4. ret2str overloads ----
    Ret2StrLines.Add('function ret2str(v: Int64): string; overload;');
    Ret2StrLines.Add('begin');
    Ret2StrLines.Add('  Result := IntToStr(v);');
    Ret2StrLines.Add('end;');
    Ret2StrLines.Add('');
    Ret2StrLines.Add('function ret2str(v: Double): string; overload;');
    Ret2StrLines.Add('begin');
    Ret2StrLines.Add('  Result := FloatToStr(v);');
    Ret2StrLines.Add('end;');
    Ret2StrLines.Add('');
    Ret2StrLines.Add('function ret2str(const v: string): string; overload;');
    Ret2StrLines.Add('begin');
    Ret2StrLines.Add('  Result := v;');
    Ret2StrLines.Add('end;');
    Ret2StrLines.Add('');

    // ---- 5. Internal call wrappers ----
    UsedApiNames.Clear;
    InternalCallLines.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        InternalCallName := MakeInternalCallName(Name) + '_' + ApiName;

        CallArgs := '';
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;
          if CallArgs <> '' then CallArgs.Append(', ');
          CallArgs := CallArgs + ParamName;
        end;

        InternalCallLines.Add('// ---- Internal wrapper for ' + Name + ' ----');
        InternalCallLines.Add('// Runs on a LingoFuse worker thread. If main-thread synchronization is');
        InternalCallLines.Add('// required, uncomment the block below and adjust.');

        if IsFunction then
          tmp := 'function ' + InternalCallName + '(' + BuildParamDecl(Params) + '): ' + ReturnType + ';'
        else
          tmp := 'procedure ' + InternalCallName + '(' + BuildParamDecl(Params) + ');';
        InternalCallLines.Add(tmp);
        Interface_InternalCallLines.Add(tmp);

        InternalCallLines.Add('(*');
        InternalCallLines.Add('{$IFDEF FPC}');
        InternalCallLines.Add('  procedure Do_Sync___();');
        InternalCallLines.Add('  begin');
        if IsFunction then
          InternalCallLines.Add(PFormat('    // Result := do_%s(%s);', [InternalCallName.Text, CallArgs.Text]))
        else
          InternalCallLines.Add(PFormat('    // do_%s(%s);', [InternalCallName.Text, CallArgs.Text]));
        InternalCallLines.Add('  end;');
        if IsFunction then
        begin
          InternalCallLines.Add('{$ELSE FPC}');
          InternalCallLines.Add('var temp_: ' + ReturnType + ';');
        end;
        InternalCallLines.Add('{$ENDIF FPC}');
        InternalCallLines.Add('*)');
        InternalCallLines.Add('begin');
        if IsFunction then
        begin
          if ReturnType.Same('string') then
            InternalCallLines.Add('  Result := ' + #39#39 + ';')
          else
            InternalCallLines.Add('  Result := 0;');
          InternalCallLines.Add(PFormat('  // Result := do_%s(%s);', [InternalCallName.Text, CallArgs.Text]));

          InternalCallLines.Add('(*');
          InternalCallLines.Add('{$IFDEF FPC}');
          InternalCallLines.Add('  TCompute.Sync(Do_Sync___);');
          InternalCallLines.Add('{$ELSE FPC}');
          InternalCallLines.Add('  TCompute.Sync(procedure()');
          InternalCallLines.Add('  begin');
          InternalCallLines.Add(PFormat('    // temp_ := do_%s(%s);', [InternalCallName.Text, CallArgs.Text]));
          InternalCallLines.Add('  end);');
          InternalCallLines.Add('  Result := temp_;');
          InternalCallLines.Add('{$ENDIF FPC}');
          InternalCallLines.Add('*)');
        end;
        InternalCallLines.Add('end;');
        InternalCallLines.Add('');
      end;
    end;

    // ---- 6. Asynchronous logging ----
    LoggingLines.Add('// ---- Asynchronous logging to the beacon ----');
    LoggingLines.Add('procedure Do_Th_Send(th: TCompute);');
    LoggingLines.Add('var');
    LoggingLines.Add('  p: Pointer;');
    LoggingLines.Add('  msg: TZ_JsonString;');
    LoggingLines.Add('  Data, ResultHnd: TDataHnd___;');
    LoggingLines.Add('  jo: TZ_JsonObject;');
    LoggingLines.Add('begin');
    LoggingLines.Add('  p := th.UserData;');
    LoggingLines.Add('  msg.ReadUTF8AnsiChar(p);');
    LoggingLines.Add('  TZ_JsonString.FreeUTF8AnsiChar(p);');
    LoggingLines.Add('  Data := LF_CreateDataEx(AGENT_LOG_API);');
    LoggingLines.Add('  try');
    LoggingLines.Add('    jo := TZ_JsonObject.Create;');
    LoggingLines.Add('    try');
    LoggingLines.Add('      jo.S[''message''] := msg.Text;');
    LoggingLines.Add('      LF_WriteStringBytes(Data, jo.ToBytes);');
    LoggingLines.Add('    finally');
    LoggingLines.Add('      jo.Free;');
    LoggingLines.Add('    end;');
    LoggingLines.Add('    ResultHnd := LF_CallEx(BEACON_APP, Data, 3000);');
    LoggingLines.Add('    if ResultHnd <> nil then');
    LoggingLines.Add('      LF_FreeData(ResultHnd);');
    LoggingLines.Add('  finally');
    LoggingLines.Add('    LF_FreeData(Data);');
    LoggingLines.Add('  end;');
    LoggingLines.Add('end;');
    LoggingLines.Add('');
    LoggingLines.Add('procedure SendLogAsync(const msg: TZ_JsonString);');
    LoggingLines.Add('begin');
    LoggingLines.Add('  TCompute.RunC(msg.BuildUTF8AnsiChar, nil, Do_Th_Send);');
    LoggingLines.Add('end;');
    LoggingLines.Add('');

    // ---- 7. Callbacks ----
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        CallbackName := MakeCallbackName(Name) + '_' + ApiName;
        InternalCallName := MakeInternalCallName(Name) + '_' + ApiName;

        Log('  Generating callback: ' + CallbackName + ' (params: ' + umlIntToStr(Length(Params)).Text + ')');

        ExtractCode := '';
        CallArgs := '';
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;
          if j > 0 then CallArgs := CallArgs + ', ';
          if Params[j].PascalType.Same('Int64') then
            ExtractCode := ExtractCode + '    ' + ParamName + ' := jo.I64[' + #39 + ParamName + #39 + '];' + sLineBreak
          else if Params[j].PascalType.Same('Double') then
            ExtractCode := ExtractCode + '    ' + ParamName + ' := jo.F[' + #39 + ParamName + #39 + '];' + sLineBreak
          else if Params[j].PascalType.Same('string') then
            ExtractCode := ExtractCode + '    ' + ParamName + ' := jo.S[' + #39 + ParamName + #39 + '];' + sLineBreak;
          CallArgs := CallArgs + ParamName;
        end;

        ForwardLines.Add('procedure ' + CallbackName + '(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl; forward;');

        CallbackLines.Add('// ---- ' + Name + ' (API: ' + ApiName + ') ----');
        CallbackLines.Add('procedure ' + CallbackName + '(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;');
        CallbackLines.Add('var');
        CallbackLines.Add('  jsonBytes: TBytes;');
        CallbackLines.Add('  jo: TZ_JsonObject;');
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;
          CallbackLines.Add('  ' + ParamName + ': ' + Params[j].PascalType + ';');
        end;
        if IsFunction then
          CallbackLines.Add('  ret: ' + ReturnType + ';');
        CallbackLines.Add('  errMsg: string;');
        CallbackLines.Add('begin');
        CallbackLines.Add('  jo := TZ_JsonObject.Create;');
        CallbackLines.Add('  try');
        CallbackLines.Add('    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));');
        CallbackLines.Add('    if DEBUG_LOG then');
        CallbackLines.Add('      DoStatus(''[' + Name + '] Input JSON: %s'', [TEncoding.UTF8.GetString(jsonBytes)]);');
        CallbackLines.Add('');
        CallbackLines.Add('    if Length(jsonBytes) = 0 then');
        CallbackLines.Add('    begin');
        CallbackLines.Add('      errMsg := ''Empty input'';');
        CallbackLines.Add('      jo.Clear;');
        CallbackLines.Add('      jo.S[''error''] := errMsg;');
        CallbackLines.Add('      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);');
        CallbackLines.Add('      if DEBUG_LOG then');
        CallbackLines.Add('      begin');
        CallbackLines.Add('        DoStatus(''[' + Name + '] Error: %s'', [errMsg]);');
        CallbackLines.Add('        SendLogAsync(''[' + Name + '] Error: '' + errMsg);');
        CallbackLines.Add('      end;');
        CallbackLines.Add('      Exit;');
        CallbackLines.Add('    end;');
        CallbackLines.Add('    if not jo.Parae(jsonBytes) then');
        CallbackLines.Add('    begin');
        CallbackLines.Add('      errMsg := ''Invalid JSON'';');
        CallbackLines.Add('      jo.Clear;');
        CallbackLines.Add('      jo.S[''error''] := errMsg;');
        CallbackLines.Add('      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);');
        CallbackLines.Add('      if DEBUG_LOG then');
        CallbackLines.Add('      begin');
        CallbackLines.Add('        DoStatus(''[' + Name + '] Error: %s'', [errMsg]);');
        CallbackLines.Add('        SendLogAsync(''[' + Name + '] Error: '' + errMsg);');
        CallbackLines.Add('      end;');
        CallbackLines.Add('      Exit;');
        CallbackLines.Add('    end;');
        if ExtractCode <> '' then
          CallbackLines.Add(ExtractCode)
        else
          CallbackLines.Add('    // No parameters');
        if IsFunction then
        begin
          CallbackLines.Add('    ret := ' + InternalCallName + '(' + CallArgs + ');');
          CallbackLines.Add('    jo.Clear;');
          if ReturnType.Same('Int64') then
            CallbackLines.Add('    jo.I64[''result''] := ret;')
          else if ReturnType.Same('Double') then
            CallbackLines.Add('    jo.F[''result''] := ret;')
          else if ReturnType.Same('string') then
            CallbackLines.Add('    jo.S[''result''] := ret;');
          CallbackLines.Add('    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);');
          CallbackLines.Add('    if DEBUG_LOG then');
          CallbackLines.Add('    begin');
          if CallArgs = '' then
          begin
            CallbackLines.Add('      DoStatus(''[' + Name + '] called (no params) -> result: %s'', [ret2str(ret)]);');
            CallbackLines.Add('      SendLogAsync(''[' + Name + '] called (no params) -> result: '' + ret2str(ret));');
          end
          else
          begin
            CallbackLines.Add('      DoStatus(''[' + Name + '] called with %s -> result: %s'', [' + CallArgs + ', ret2str(ret)]);');
            CallbackLines.Add('      SendLogAsync(PFormat(''[' + Name + '] called with %s'', [' + CallArgs + ']) + '' -> result: '' + ret2str(ret));');
          end;
        end
        else
        begin
          CallbackLines.Add('    ' + InternalCallName + '(' + CallArgs + ');');
          CallbackLines.Add('    jo.Clear;');
          CallbackLines.Add('    jo.S[''status''] := ''ok'';');
          CallbackLines.Add('    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);');
          CallbackLines.Add('    if DEBUG_LOG then');
          CallbackLines.Add('    begin');
          if CallArgs = '' then
          begin
            CallbackLines.Add('      DoStatus(''[' + Name + '] called (no params)'');');
            CallbackLines.Add('      SendLogAsync(''[' + Name + '] called (no params)'');');
          end
          else
          begin
            CallbackLines.Add('      DoStatus(''[' + Name + '] called with %s'', [' + CallArgs + ']);');
            CallbackLines.Add('      SendLogAsync(PFormat(''[' + Name + '] called with %s'', [' + CallArgs + ']));');
          end;
        end;
        CallbackLines.Add('    end;');
        CallbackLines.Add('  except');
        CallbackLines.Add('    on E: Exception do');
        CallbackLines.Add('    begin');
        CallbackLines.Add('      jo.Clear;');
        CallbackLines.Add('      jo.S[''error''] := E.Message;');
        CallbackLines.Add('      LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);');
        CallbackLines.Add('      if DEBUG_LOG then');
        CallbackLines.Add('      begin');
        CallbackLines.Add('        DoStatus(''[' + Name + '] Exception: %s'', [E.Message]);');
        CallbackLines.Add('        SendLogAsync(''[' + Name + '] Exception: '' + E.Message);');
        CallbackLines.Add('      end;');
        CallbackLines.Add('    end;');
        CallbackLines.Add('  end;');
        CallbackLines.Add('  jo.Free;');
        CallbackLines.Add('end;');
        CallbackLines.Add('');
      end;
    end;

    // ---- 8. RegisterTool + RegisterTools ----
    RegisterToolLines.Add('// -----------------------------------------------------------------------------');
    RegisterToolLines.Add('// Register a single tool with the beacon via the register_agent API.');
    RegisterToolLines.Add('// Returns True on success, False on failure.');
    RegisterToolLines.Add('// -----------------------------------------------------------------------------');
    RegisterToolLines.Add('function RegisterTool(const ToolDef: TZ_JsonObject): boolean;');
    RegisterToolLines.Add('var');
    RegisterToolLines.Add('  Data, ResultHnd: TDataHnd___;');
    RegisterToolLines.Add('  jsonBytes: TBytes;');
    RegisterToolLines.Add('  RespJson: TZ_JsonObject;');
    RegisterToolLines.Add('  toolName, toolDesc, targetApp, targetApi: string;');
    RegisterToolLines.Add('begin');
    RegisterToolLines.Add('  Result := False;');
    RegisterToolLines.Add('  toolName := ToolDef.S[''name''];');
    RegisterToolLines.Add('  toolDesc := ToolDef.S[''description''];');
    RegisterToolLines.Add('  targetApp := ToolDef.S[''target_app''];');
    RegisterToolLines.Add('  targetApi := ToolDef.S[''target_api''];');
    RegisterToolLines.Add('  if DEBUG_LOG then');
    RegisterToolLines.Add('    DoStatus(''[RegisterTool] Registering tool: %s -> %s.%s'', [toolName, targetApp, targetApi]);');
    RegisterToolLines.Add('');
    RegisterToolLines.Add('  Data := LF_CreateDataEx(REGISTER_API);');
    RegisterToolLines.Add('  try');
    RegisterToolLines.Add('    LF_WriteStringBytes(Data, ToolDef.ToBytes);');
    RegisterToolLines.Add('    ResultHnd := LF_CallEx(BEACON_APP, Data, 5000);');
    RegisterToolLines.Add('    try');
    RegisterToolLines.Add('      jsonBytes := LF_ReadStringBytes(ResultHnd);');
    RegisterToolLines.Add('      if Length(jsonBytes) > 0 then');
    RegisterToolLines.Add('      begin');
    RegisterToolLines.Add('        RespJson := TZ_JsonObject.Create;');
    RegisterToolLines.Add('        try');
    RegisterToolLines.Add('          RespJson.Parae(jsonBytes);');
    RegisterToolLines.Add('          if RespJson.Exists(''status'') and (RespJson.S[''status''] = ''ok'') then');
    RegisterToolLines.Add('          begin');
    RegisterToolLines.Add('            Result := True;');
    RegisterToolLines.Add('            if DEBUG_LOG then');
    RegisterToolLines.Add('              DoStatus(''[RegisterTool] Tool "%s" registered successfully.'', [toolName]);');
    RegisterToolLines.Add('          end');
    RegisterToolLines.Add('          else');
    RegisterToolLines.Add('          begin');
    RegisterToolLines.Add('            if DEBUG_LOG then');
    RegisterToolLines.Add('              DoStatus(''[RegisterTool] Server returned error: %s'', [RespJson.S[''message'']]);');
    RegisterToolLines.Add('          end;');
    RegisterToolLines.Add('        finally');
    RegisterToolLines.Add('          RespJson.Free;');
    RegisterToolLines.Add('        end;');
    RegisterToolLines.Add('      end');
    RegisterToolLines.Add('      else');
    RegisterToolLines.Add('        if DEBUG_LOG then');
    RegisterToolLines.Add('          DoStatus(''[RegisterTool] Empty response from beacon (timeout or network error)'');');
    RegisterToolLines.Add('    finally');
    RegisterToolLines.Add('      LF_FreeData(ResultHnd);');
    RegisterToolLines.Add('    end;');
    RegisterToolLines.Add('  finally');
    RegisterToolLines.Add('    LF_FreeData(Data);');
    RegisterToolLines.Add('  end;');
    RegisterToolLines.Add('end;');
    RegisterToolLines.Add('');

    RegisterToolLines.Add('// ---- RegisterTools implementation ----');
    RegisterToolLines.Add('function RegisterTools: Boolean;');
    RegisterToolLines.Add('var');
    RegisterToolLines.Add('  ToolDef: TZ_JsonObject;');
    RegisterToolLines.Add('  ParamsObj, PropsObj, PropObj: TZ_JsonObject;');
    RegisterToolLines.Add('  RequiredArr: TZ_JsonArray;');
    RegisterToolLines.Add('  Success: boolean;');
    RegisterToolLines.Add('  regCount: integer;');
    RegisterToolLines.Add('begin');
    RegisterToolLines.Add('  Result := False;');
    RegisterToolLines.Add('  regCount := 0;');
    RegisterToolLines.Add('  if DEBUG_LOG then');
    RegisterToolLines.Add('    DoStatus(''[RegisterTools] Checking beacon availability: app=%s api=%s'', [BEACON_APP, REGISTER_API]);');
    RegisterToolLines.Add('  if not LF_CheckApiEx(BEACON_APP, REGISTER_API) then');
    RegisterToolLines.Add('  begin');
    RegisterToolLines.Add('    DoStatus(''[RegisterTools] Beacon not available. Please ensure pascal_agent_service is running.'');');
    RegisterToolLines.Add('    exit;');
    RegisterToolLines.Add('  end;');
    RegisterToolLines.Add('  if DEBUG_LOG then');
    RegisterToolLines.Add('    DoStatus(''[RegisterTools] Beacon is available. Starting tool registration...'');');
    RegisterToolLines.Add('  try');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        Description := GetFullDescription(Comment);
        if Description = '' then Description := 'Auto-generated call for ' + Name;

        RegisterToolLines.Add('    // Tool: ' + Name + ' -> ' + ApiName);
        RegisterToolLines.Add('    ToolDef := TZ_JsonObject.Create;');
        RegisterToolLines.Add('    try');
        RegisterToolLines.Add('      ToolDef.S[''name''] := ' + PascalStrLit(ApiName) + ';');
        RegisterToolLines.Add('      ToolDef.S[''description''] := ' + PascalStrLit(Description) + ';');
        RegisterToolLines.Add('      ToolDef.S[''target_app''] := MY_APP_NAME;');
        RegisterToolLines.Add('      ToolDef.S[''target_api''] := ' + PascalStrLit(ApiName) + ';');
        RegisterToolLines.Add('');
        RegisterToolLines.Add('      ParamsObj := ToolDef.O[''parameters''];');
        RegisterToolLines.Add('      ParamsObj.S[''type''] := ''object'';');
        RegisterToolLines.Add('      PropsObj := ParamsObj.O[''properties''];');
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;
          RegisterToolLines.Add('      PropObj := PropsObj.O[' + PascalStrLit(ParamName) + '];');
          if Params[j].PascalType.Same('Int64') then
            RegisterToolLines.Add('      PropObj.S[''type''] := ''integer'';')
          else if Params[j].PascalType.Same('Double') then
            RegisterToolLines.Add('      PropObj.S[''type''] := ''number'';')
          else if Params[j].PascalType.Same('string') then
            RegisterToolLines.Add('      PropObj.S[''type''] := ''string'';');
          if Params[j].Description <> '' then
            RegisterToolLines.Add('      PropObj.S[''description''] := ' + PascalStrLit(Params[j].Description) + ';')
          else
            RegisterToolLines.Add('      PropObj.S[''description''] := ' + PascalStrLit(ParamName + ' parameter') + ';');
        end;
        if Length(Params) > 0 then
        begin
          RegisterToolLines.Add('      RequiredArr := ParamsObj.a[''required''];');
          for j := 0 to High(Params) do
          begin
            if Params[j].Name = '' then
              ParamName := 'p' + umlIntToStr(j)
            else
              ParamName := Params[j].Name;
            RegisterToolLines.Add('      RequiredArr.Add(' + PascalStrLit(ParamName) + ');');
          end;
        end;
        RegisterToolLines.Add('      Success := RegisterTool(ToolDef);');
        RegisterToolLines.Add('      if Success then Inc(regCount);');
        RegisterToolLines.Add('      if DEBUG_LOG then');
        RegisterToolLines.Add('        if Success then');
        RegisterToolLines.Add('          DoStatus(''[RegisterTools] OK: ' + ApiName + ''')');
        RegisterToolLines.Add('        else');
        RegisterToolLines.Add('          DoStatus(''[RegisterTools] FAIL: ' + ApiName + ''');');
        RegisterToolLines.Add('    finally');
        RegisterToolLines.Add('      ToolDef.Free;');
        RegisterToolLines.Add('    end;');
        RegisterToolLines.Add('');
      end;
    end;

    RegisterToolLines.Add('    Result := (regCount = ' + umlIntToStr(Length(SupportedFuncs)).Text + ');');
    RegisterToolLines.Add('    if DEBUG_LOG then');
    RegisterToolLines.Add('      DoStatus(''[RegisterTools] Registered %d out of %d tools.'', [regCount, ' + umlIntToStr(Length(SupportedFuncs)).Text + ']);');
    RegisterToolLines.Add('  finally');
    RegisterToolLines.Add('  end;');
    RegisterToolLines.Add('end;');
    RegisterToolLines.Add('');

    // ---- 9. RegisterAPIs ----
    RegisterAPIsLines.Add('// ---- RegisterAPIs implementation ----');
    RegisterAPIsLines.Add('function RegisterAPIs: TAppHnd___;');
    RegisterAPIsLines.Add('var');
    RegisterAPIsLines.Add('  App: TAppHnd___;');
    RegisterAPIsLines.Add('begin');
    RegisterAPIsLines.Add('  Result := nil;');
    RegisterAPIsLines.Add('  App := LF_CreateAppEx(MY_APP_NAME, MY_APP_DESC);');
    RegisterAPIsLines.Add('  if DEBUG_LOG then');
    RegisterAPIsLines.Add('    DoStatus(''[RegisterAPIs] Application "%s" created.'', [MY_APP_NAME]);');
    RegisterAPIsLines.Add('');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);
        CallbackName := MakeCallbackName(Name) + '_' + ApiName;
        Description := GetFullDescription(Comment);
        if Description = '' then Description := 'Auto-generated call for ' + Name;
        RegisterAPIsLines.Add('  LF_RegisterCallEx(App, ' + PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) + ', nil, @' +
          CallbackName + ');  // Register API: ' + Name + ' -> ' + ApiName);
      end;
    end;
    RegisterAPIsLines.Add('  if DEBUG_LOG then');
    RegisterAPIsLines.Add('    DoStatus(''[RegisterAPIs] Registered APIs: ' + umlIntToStr(Length(SupportedFuncs)) + ' functions'');');
    RegisterAPIsLines.Add('  Result := App;');
    RegisterAPIsLines.Add('end;');
    RegisterAPIsLines.Add('');

    // ---- 10. Execute_And_Reg_all ----
    ExecuteLines := TPascalStringList.Create;
    ExecuteLines.Add('');
    ExecuteLines.Add('// ---- Execute_And_Reg_all implementation ----');
    ExecuteLines.Add('function Execute_And_Reg_all: Boolean;');
    ExecuteLines.Add('var');
    ExecuteLines.Add('  App: TAppHnd___;');
    ExecuteLines.Add('begin');
    ExecuteLines.Add('  Result := False;');
    ExecuteLines.Add('  App := RegisterAPIs();');
    ExecuteLines.Add('  if App = nil then');
    ExecuteLines.Add('  begin');
    ExecuteLines.Add('    if DEBUG_LOG then DoStatus(''[Execute_And_Reg_all] RegisterAPIs failed'');');
    ExecuteLines.Add('    Exit;');
    ExecuteLines.Add('  end;');
    ExecuteLines.Add('  if LF_CheckMainThreadEx then');
    ExecuteLines.Add('  begin');
    ExecuteLines.Add('    LF_PrepareClientEx(IPC_ENDPOINT, App);');
    ExecuteLines.Add('    Result := RegisterTools();');
    ExecuteLines.Add('  end');
    ExecuteLines.Add('  else');
    ExecuteLines.Add('  begin');
    ExecuteLines.Add('    LF_PrepareClientEx(IPC_ENDPOINT, App);');
    ExecuteLines.Add('    if LF_PrepareDone() > 0 then');
    ExecuteLines.Add('      Result := RegisterTools()');
    ExecuteLines.Add('    else');
    ExecuteLines.Add('    begin');
    ExecuteLines.Add('      if DEBUG_LOG then DoStatus(''[Execute_And_Reg_all] LF_PrepareDone failed'');');
    ExecuteLines.Add('    end;');
    ExecuteLines.Add('  end;');
    ExecuteLines.Add('end;');
    ExecuteLines.Add('');

    // ---- Assemble ----
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(InterfaceLines);
    ResultLines.Add('');
    ResultLines.AddStrings(Interface_InternalCallLines);
    ResultLines.Add('');
    ResultLines.Add('implementation');
    ResultLines.Add('');

    ResultLines.AddStrings(UsesLines);
    ResultLines.AddStrings(ForwardLines);
    ResultLines.AddStrings(InternalCallLines);

    ResultLines.Add('{$Region ''internal_''}');
    ResultLines.AddStrings(Ret2StrLines);
    ResultLines.AddStrings(LoggingLines);
    ResultLines.Add('{$EndRegion ''internal_''}');

    ResultLines.Add('{$Region ''callback_''}');
    ResultLines.AddStrings(CallbackLines);
    ResultLines.Add('{$EndRegion ''callback_''}');

    ResultLines.AddStrings(RegisterToolLines);
    ResultLines.AddStrings(RegisterAPIsLines);
    ResultLines.AddStrings(ExecuteLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generation completed: %d lines, %d supported functions.', [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    InterfaceLines.Free;
    UsesLines.Free;
    ForwardLines.Free;
    Interface_InternalCallLines.Free;
    InternalCallLines.Free;
    Ret2StrLines.Free;
    LoggingLines.Free;
    CallbackLines.Free;
    RegisterToolLines.Free;
    RegisterAPIsLines.Free;
    UsedApiNames.Free;
    ExecuteLines.Free;
  end;
end;

// =============================================================================
// SECTION 2 - Pascal README generator (English Markdown)
// =============================================================================

function MakeAppNameFromUnit(const UnitName: TP_String): TP_String;
var
  tmp: TP_String;
begin
  tmp := UnitName;
  if umlMultipleMatch('*.pas', tmp) then
    tmp := umlChangeFileExt(tmp.Text, '').Text;
  Result := tmp.ReplaceChar('.', '_').ReplaceChar('-', '_');
end;

function GeneratePascalReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  ValidFuncs: TValidFuncArray;
  UnitName, AppName: TP_String;
  i, j: integer;
  f: TFunctionStructure;
  desc, shortDesc, row: TP_String;

  // ---- Section emitters ----

  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - Pascal Tool Provider');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `pas_mcp_generator_tool.pas`;');
    L.Add('> stays in sync with the code file.');
    L.Add('>');
    L.Add('> **Source unit**   : `' + UnitName + '`');
    L.Add('> **Provider unit** : `' + UnitName + '_tool_provider_unit.pas`');
    L.Add('> **Exposed APIs**  : ' + umlIntToStr(Length(ValidFuncs)).Text);
    L.Add('');
    L.Add('---');
    L.Add('');
  end;

  procedure EmitOverview;
  begin
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('This README explains how to build, integrate, and test the auto-generated');
    L.Add('Pascal tool provider unit `' + UnitName + '_tool_provider_unit.pas`.');
    L.Add('');
    L.Add('The unit registers every top-level function of `' + UnitName + '` as a');
    L.Add('LingoFuse Call API and advertises them as MCP tools through the beacon.');
    L.Add('An LLM client discovers these tools through the beacon and invokes them');
    L.Add('over IPC.');
    L.Add('');
    L.Add('### 1.1 Required repositories');
    L.Add('');
    L.Add('The provider is **NOT standalone**. It requires three source repositories');
    L.Add('to be present on your disk and their source paths on the compiler search');
    L.Add('path:');
    L.Add('');
    L.Add('| Repository | Provides | Typical checkout path |');
    L.Add('|------------|----------|----------------------|');
    L.Add('| **ZCore** | Core infrastructure used by the provider unit: `TCompute`, `TCore_Thread`, `TAtomVar`, `TBigList`, `TOrderStruct`, and the low-level primitives under `Z.Core`. | `<your-roots>/ZNetV2/ZCore/` |');
    L.Add('| **ZNetV2** | LingoFuse runtime bindings and IPC network library. Provides the C4/`z_ipc_*.dll` runtime, `lingofuse_import.pas`, `lingofuse_helper.pas`. | `<your-roots>/ZNetV2/` |');
    L.Add('| **LingoFuse-pasAgent-v3** | Beacon server (`pascal_agent_service.exe`), agent API (`pascal_agent_api.exe`), working example provider (`CreateHealthCheck/`), and the LLM/MCP bridge tools (`mcp_api_tool.py`, `generate_agent_json.py`, etc.). | `<your-roots>/LingoFuse-pasAgent-v3/src/` |');
    L.Add('');
    L.Add('Clone them from their respective repositories. The URLs below are');
    L.Add('placeholders; replace them with the actual clone URLs of your');
    L.Add('deployments.');
    L.Add('');
    L.Add('```bash');
    L.Add('git clone <zcore-repo-url>      ZNetV2/ZCore');
    L.Add('git clone <znetv2-repo-url>     ZNetV2');
    L.Add('git clone <v3-repo-url>         LingoFuse-pasAgent-v3');
    L.Add('```');
    L.Add('');
    L.Add('### 1.2 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + UnitName + '_tool_provider_unit.pas` | Main provider unit (compile into your program) |');
    L.Add('| `' + UnitName + '_tool_provider_pascal.md` | This README |');
    L.Add('');
  end;

  procedure EmitArchitecture;
  begin
    L.Add('## 2. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph Runtime["LingoFuse Runtime"]');
    L.Add('        BEACON["pascal_agent_service.exe<br/>(agent_main_app)"]');
    L.Add('        IPC["ipc:agent"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Provider["Generated Tool Provider"]');
    L.Add('        REG_APIS["RegisterAPIs()<br/>create App + register Call APIs"]');
    L.Add('        PREPARE["LF_PrepareClient + LF_PrepareDone"]');
    L.Add('        REG_TOOLS["RegisterTools()<br/>advertise tools to beacon"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Tools["Exposed APIs"]');
    L.Add('        T_API["Call APIs from ' + UnitName + '"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["LLM / MCP Client"]');
    L.Add('        LLM["mcp_api_tool.py<br/>LLM Studio / Claude / ..."]');
    L.Add('    end');
    L.Add('');
    L.Add('    BEACON <--> IPC');
    L.Add('    REG_APIS --> PREPARE');
    L.Add('    PREPARE --> IPC');
    L.Add('    REG_TOOLS --> BEACON');
    L.Add('    LLM -->|discover| BEACON');
    L.Add('    LLM -->|invoke| IPC');
    L.Add('    IPC --> T_API');
    L.Add('');
    L.Add('    style Runtime fill:#e3f2fd,stroke:#1565c0');
    L.Add('    style Provider fill:#fff3e0,stroke:#e65100');
    L.Add('    style Tools fill:#e8f5e9,stroke:#2e7d32');
    L.Add('    style Client fill:#f3e5f5,stroke:#6a1b9a');
    L.Add('```');
    L.Add('');
    L.Add('**Call chain**');
    L.Add('');
    L.Add('1. Start `pascal_agent_service.exe` (the beacon); it listens on `ipc:agent`.');
    L.Add('2. Start the provider executable; it calls `Execute_And_Reg_all`.');
    L.Add('3. `RegisterAPIs` creates a LingoFuse App and registers every top-level');
    L.Add('   function of `' + UnitName + '` as a Call API.');
    L.Add('4. `LF_PrepareClient` connects to `ipc:agent`; `LF_PrepareDone` waits');
    L.Add('   for readiness.');
    L.Add('5. `RegisterTools` pushes the JSON schema of every API to the beacon');
    L.Add('   through the `register_agent` API.');
    L.Add('6. An LLM/MCP client (`mcp_api_tool.py` + LM Studio / Claude) discovers');
    L.Add('   the tools through the beacon and invokes them over IPC.');
    L.Add('');
  end;

  procedure EmitTestLpr;
  begin
    L.Add('## 3. Test Provider Program (`.lpr`)');
    L.Add('');
    L.Add('The program below is a **complete, copy-paste-ready** `.lpr` that');
    L.Add('compiles the generated unit into a runnable tool provider. Save it as');
    L.Add('`' + AppName + '_provider.lpr` in the same directory as the generated');
    L.Add('unit.');
    L.Add('');
    L.Add('Key points:');
    L.Add('');
    L.Add('- `{$mode objfpc}{$H+}` is required; the provider unit uses Delphi-mode');
    L.Add('  syntax through `{$mode delphi}` internally.');
    L.Add('- `cthreads` must be listed first on Unix so the runtime links the');
    L.Add('  thread-safe C library.');
    L.Add('- `Z.Core` is required because the provider uses `TCompute` and');
    L.Add('  `TCore_Thread` internally. Its location must be on the compiler');
    L.Add('  search path.');
    L.Add('- The unit `' + UnitName + '_tool_provider_unit` is the generated one.');
    L.Add('- Call `LF_ExitMainThread` then `LF_Shutdown` before exiting to release');
    L.Add('  all LingoFuse resources cleanly.');
    L.Add('');
    L.Add('```pascal');
    L.Add('program ' + AppName + '_provider;');
    L.Add('');
    L.Add('{ ' + AppName + ' Tool Provider - LingoFuse Test Program');
    L.Add('');
    L.Add('  This is the minimum runnable program that:');
    L.Add('    1. Creates the LingoFuse App and registers all Call APIs');
    L.Add('    2. Connects to ipc:agent');
    L.Add('    3. Advertises every tool to the beacon');
    L.Add('    4. Keeps running until the user presses Enter');
    L.Add('');
    L.Add('  Compile with:');
    L.Add('    fpc ' + AppName + '_provider.lpr');
    L.Add('  or open the .lpr in Lazarus and press F9.');
    L.Add('}');
    L.Add('');
    L.Add('{$mode objfpc}{$H+}');
    L.Add('{$CODEPAGE UTF8}');
    L.Add('');
    L.Add('uses');
    L.Add('  {$IFDEF UNIX}');
    L.Add('  cthreads,');
    L.Add('  {$ENDIF}');
    L.Add('  {$IFDEF MSWINDOWS}');
    L.Add('  Windows,');
    L.Add('  {$ENDIF}');
    L.Add('  SysUtils, Classes,');
    L.Add('  Z.Core,');
    L.Add('  ' + UnitName + '_tool_provider_unit;');
    L.Add('');
    L.Add('begin');
    L.Add('  WriteLn(''=== ' + AppName + ' Tool Provider ==='');');
    L.Add('  WriteLn(''Connecting to ipc:agent ...'');');
    L.Add('');
    L.Add('  if not Execute_And_Reg_all then');
    L.Add('  begin');
    L.Add('    WriteLn('''');');
    L.Add('    WriteLn(''[FATAL] Provider startup failed.'');');
    L.Add('    WriteLn(''Checklist:'');');
    L.Add('    WriteLn(''  1. Is pascal_agent_service.exe running?'');');
    L.Add('    WriteLn(''  2. Is the endpoint ipc:agent reachable?'');');
    L.Add('    WriteLn(''  3. Check DEBUG_LOG output above for details.'');');
    L.Add('    Halt(1);');
    L.Add('  end;');
    L.Add('');
    L.Add('  WriteLn('''');');
    L.Add('  WriteLn(''[OK] Provider is ready. All tools registered.'');');
    L.Add('  WriteLn(''You can now connect an MCP client.'');');
    L.Add('  WriteLn(''Press Enter to shut down.'');');
    L.Add('  ReadLn;');
    L.Add('');
    L.Add('  LF_ExitMainThread;');
    L.Add('  LF_Shutdown;');
    L.Add('  WriteLn(''[OK] Shutdown complete.'');');
    L.Add('end.');
    L.Add('```');
    L.Add('');
  end;

  procedure EmitBuildTestProcedure;
  begin
    L.Add('## 4. Build & Test Procedure');
    L.Add('');
    L.Add('Follow these steps in order. Each step is independent and can be');
    L.Add('verified before moving on.');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    S1["1. Prepare env<br/>(clone 3 repos, set search path)"]');
    L.Add('    S2["2. Compile .lpr<br/>(Lazarus / fpc)"]');
    L.Add('    S3["3. Start beacon<br/>(pascal_agent_service.exe)"]');
    L.Add('    S4["4. Start mcp_api_tool<br/>+ generate client config"]');
    L.Add('    S5["5. Start agent<br/>(LM Studio / Claude / ...)"]');
    L.Add('    S6["6. Test API<br/>(invoke tool from agent)"]');
    L.Add('');
    L.Add('    S1 --> S2 --> S3 --> S4 --> S5 --> S6');
    L.Add('');
    L.Add('    style S1 fill:#e3f2fd');
    L.Add('    style S2 fill:#fff3e0');
    L.Add('    style S3 fill:#e8f5e9');
    L.Add('    style S4 fill:#f3e5f5');
    L.Add('    style S5 fill:#fce4ec');
    L.Add('    style S6 fill:#e0f7fa');
    L.Add('```');
    L.Add('');

    // Step 1
    L.Add('### Step 1 - Prepare the environment');
    L.Add('');
    L.Add('Clone the three required repositories. The paths below are the ones');
    L.Add('used by the v3 build scripts; adjust to your layout if needed.');
    L.Add('');
    L.Add('```bash');
    L.Add('mkdir my-lingofuse-workspace');
    L.Add('cd my-lingofuse-workspace');
    L.Add('git clone <zcore-repo-url>      ZNetV2/ZCore');
    L.Add('git clone <znetv2-repo-url>     ZNetV2');
    L.Add('git clone <v3-repo-url>         LingoFuse-pasAgent-v3');
    L.Add('```');
    L.Add('');
    L.Add('Then place your generated files together with the test .lpr:');
    L.Add('');
    L.Add('```');
    L.Add('my-lingofuse-workspace/');
    L.Add('  ZNetV2/');
    L.Add('    ZCore/                 <- unit search path for Z.Core');
    L.Add('    ...                    <- lingofuse_import.pas, lingofuse_helper.pas');
    L.Add('  LingoFuse-pasAgent-v3/');
    L.Add('    src/');
    L.Add('      pascal_agent_service.exe');
    L.Add('      mcp_api_tool.py');
    L.Add('      generate_agent_json.py');
    L.Add('  my_provider/');
    L.Add('    ' + UnitName + '_tool_provider_unit.pas');
    L.Add('    ' + AppName + '_provider.lpr');
    L.Add('```');
    L.Add('');

    // Step 2
    L.Add('### Step 2 - Compile the .lpr with Lazarus + FPC');
    L.Add('');
    L.Add('Option A: open the `.lpr` in Lazarus and press **F9**.');
    L.Add('');
    L.Add('Option B: compile from the command line:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd my_provider');
    L.Add('fpc -Fu../ZNetV2/ZCore -Fu../ZNetV2 ' + AppName + '_provider.lpr');
    L.Add('```');
    L.Add('');
    L.Add('The `-Fu` switches add the two required search paths. If you placed the');
    L.Add('repositories elsewhere, adjust the paths.');
    L.Add('');
    L.Add('On success you get `' + AppName + '_provider.exe` (Windows) or');
    L.Add('`' + AppName + '_provider` (Linux/macOS).');
    L.Add('');

    // Step 3
    L.Add('### Step 3 - Start the beacon');
    L.Add('');
    L.Add('Open a new terminal and run:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('./pascal_agent_service.exe');
    L.Add('```');
    L.Add('');
    L.Add('The beacon listens on `ipc:agent`. Leave this terminal running.');
    L.Add('');
    L.Add('Now start your provider in a second terminal:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd my_provider');
    L.Add('./' + AppName + '_provider');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName + ' Tool Provider ===');
    L.Add('Connecting to ipc:agent ...');
    L.Add('[RegisterTools] Checking beacon availability: app=agent_main_app api=register_agent');
    L.Add('[RegisterTools] Beacon is available. Starting tool registration...');
    L.Add('[RegisterTool] Registering tool: <name> -> <app>.<api>');
    L.Add('[RegisterTool] Tool "<name>" registered successfully.');
    L.Add('...');
    L.Add('[RegisterTools] Registered N out of N tools.');
    L.Add('');
    L.Add('[OK] Provider is ready. All tools registered.');
    L.Add('Press Enter to shut down.');
    L.Add('```');
    L.Add('');

    // Step 4
    L.Add('### Step 4 - Start mcp_api_tool and generate the client config');
    L.Add('');
    L.Add('Open a third terminal. The MCP gateway connects to the same beacon');
    L.Add('(`ipc:agent`), discovers all registered tools, and exposes them to');
    L.Add('MCP clients.');
    L.Add('');
    L.Add('```bash');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('python mcp_api_tool.py --generate-configs --output-dir ./mcp_configs');
    L.Add('```');
    L.Add('');
    L.Add('This produces configuration files for LM Studio, Claude Desktop,');
    L.Add('Continue.dev, Jan, DeepSeek, and a generic MCP client, in both stdio');
    L.Add('and HTTP variants. Pick the file matching your agent:');
    L.Add('');
    L.Add('- `./mcp_configs/lmstudio_stdio.json`');
    L.Add('- `./mcp_configs/claude_stdio.json`');
    L.Add('- `./mcp_configs/generic_http.json`');
    L.Add('- ...');
    L.Add('');
    L.Add('Then start the MCP gateway:');
    L.Add('');
    L.Add('```bash');
    L.Add('python mcp_api_tool.py --transport stdio');
    L.Add('```');
    L.Add('');
    L.Add('(Or use `--transport http --port 8000` for a streamable HTTP endpoint.)');
    L.Add('');

    // Step 5
    L.Add('### Step 5 - Start the agent (LLM client)');
    L.Add('');
    L.Add('Depending on your agent:');
    L.Add('');
    L.Add('- **LM Studio**: Open settings > MCP Servers, and paste the content of');
    L.Add('  `lmstudio_stdio.json` (or `lmstudio_http.json`). Restart LM Studio.');
    L.Add('- **Claude Desktop**: Edit `claude_desktop_config.json` and merge the');
    L.Add('  `mcpServers` section from `claude_stdio.json`. Restart Claude.');
    L.Add('- **Continue.dev / Jan / DeepSeek**: Merge the corresponding JSON into');
    L.Add('  the client config and restart.');
    L.Add('');
    L.Add('Once restarted, the agent should list your tools alongside its own.');
    L.Add('');

    // Step 6
    L.Add('### Step 6 - Test the API');
    L.Add('');
    L.Add('In the agent, ask it to use one of the registered tools. For example,');
    L.Add('if your provider registered a tool `add(a: Int64, b: Int64): Int64`, ask:');
    L.Add('');
    L.Add('```');
    L.Add('Please call the "add" tool with a=5 and b=7.');
    L.Add('```');
    L.Add('');
    L.Add('You should see the agent:');
    L.Add('');
    L.Add('1. Discover the `add` tool through the beacon.');
    L.Add('2. Build the JSON arguments `{"a": 5, "b": 7}`.');
    L.Add('3. Send the call through `mcp_api_tool` to your provider.');
    L.Add('4. Receive the response `{"result": 12}`.');
    L.Add('5. Present the result to you.');
    L.Add('');
    L.Add('The provider terminal prints the following lines when the tool is');
    L.Add('invoked (with `DEBUG_LOG := True`):');
    L.Add('');
    L.Add('```');
    L.Add('[add] Input JSON: {"a": 5, "b": 7}');
    L.Add('[add] called with 5, 7 -> result: 12');
    L.Add('```');
    L.Add('');
    L.Add('If the invocation fails, see §7 (Debugging).');
    L.Add('');
  end;

  procedure EmitToolReference;
  var
    ii, jj: integer;
  begin
    L.Add('## 5. Tool Reference');
    L.Add('');
    L.Add('This section lists every API exposed by the generated provider. Each API');
    L.Add('corresponds to one top-level function of `' + UnitName + '`.');
    L.Add('');

    if Length(ValidFuncs) = 0 then
    begin
      L.Add('> **WARNING: this provider exposes no APIs.**');
      L.Add('>');
      L.Add('> Possible reasons:');
      L.Add('> 1. The source unit has no top-level functions');
      L.Add('>    (nested routines in `class` / `record` are skipped).');
      L.Add('> 2. Every function failed the type check.');
      L.Add('>');
      L.Add('> Supported types: `Int64`, `Double`, `string` only.');
      L.Add('');
      Exit;
    end;

    L.Add('Total APIs: **' + umlIntToStr(Length(ValidFuncs)).Text + '**.');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');
    for ii := 0 to High(ValidFuncs) do
    begin
      f := ValidFuncs[ii];
      shortDesc := GetTableCellText(f.Comment);
      if shortDesc.Len > 60 then
        shortDesc := shortDesc.GetString(1, 61) + '...';
      if f.IsFunction then
        row := '| ' + umlIntToStr(ii + 1).Text + ' | `' + MakeApiName(f.Name) + '` | function | ' + umlIntToStr(Length(f.Params)).Text +
          ' | `' + f.ReturnType + '` | ' + shortDesc + ' |'
      else
        row := '| ' + umlIntToStr(ii + 1).Text + ' | `' + MakeApiName(f.Name) + '` | procedure | ' + umlIntToStr(Length(f.Params)).Text + ' | - | ' + shortDesc + ' |';
      L.Add(row);
    end;
    L.Add('');

    for ii := 0 to High(ValidFuncs) do
    begin
      f := ValidFuncs[ii];
      desc := GetFullDescription(f.Comment);

      L.Add('### 5.' + umlIntToStr(ii + 1).Text + ' `' + MakeApiName(f.Name) + '`');
      L.Add('');
      L.Add('- Original Pascal function: `' + f.Name + '`');
      L.Add('- Exposed API name: `' + MakeApiName(f.Name) + '`');
      if f.IsFunction then
        L.Add('- Kind: `function`, returns `' + f.ReturnType + '`')
      else
        L.Add('- Kind: `procedure`');
      if desc.Len > 0 then
        L.Add('- Description: ' + desc);
      L.Add('');

      if Length(f.Params) > 0 then
      begin
        L.Add('**Parameters**');
        L.Add('');
        L.Add('| Name | Pascal type | JSON type | Description |');
        L.Add('|------|-------------|-----------|-------------|');
        for jj := 0 to High(f.Params) do
        begin
          L.Add('| `' + f.Params[jj].Name + '` | `' + f.Params[jj].PascalType + '` | `' + PascalTypeToJsonType(f.Params[jj].PascalType) +
            '` | ' + GetTableCellText(f.Params[jj].Description) + ' |');
        end;
        L.Add('');
      end;

      L.Add('**Input JSON example**');
      L.Add('');
      L.Add('```json');
      if Length(f.Params) = 0 then
        L.Add('{}')
      else
      begin
        L.Add('{');
        for jj := 0 to High(f.Params) do
        begin
          row := '  "' + f.Params[jj].Name + '": ' + PascalTypeToJsonLiteral(f.Params[jj].PascalType);
          if jj < High(f.Params) then row := row + ',';
          L.Add(row);
        end;
        L.Add('}');
      end;
      L.Add('```');
      L.Add('');

      L.Add('**Output JSON example**');
      L.Add('');
      L.Add('```json');
      if f.IsFunction then
        L.Add('{ "result": ' + PascalTypeToJsonLiteral(f.ReturnType) + ' }')
      else
        L.Add('{ "status": "ok" }');
      L.Add('```');
      L.Add('');
    end;
  end;

  procedure EmitJsonSchemaSpec;
  begin
    L.Add('## 6. JSON Schema Specification');
    L.Add('');
    L.Add('For each tool the provider sends a JSON Schema to the beacon through');
    L.Add('the `register_agent` API. The type whitelist is fixed by the');
    L.Add('normalized `TPascal_Func_Model` output.');
    L.Add('');
    L.Add('| Pascal normalized type | JSON Schema type | Example value |');
    L.Add('|------------------------|------------------|---------------|');
    L.Add('| `int64` | `integer` | `42` |');
    L.Add('| `double` | `number` | `3.14` |');
    L.Add('| `string` | `string` | `"hello"` |');
    L.Add('');
    L.Add('**Every other type** (for example `Boolean`, arrays, records, objects,');
    L.Add('enums, interfaces, function pointers) is **NOT supported**. Functions');
    L.Add('that use them are silently dropped from the generated provider. If you');
    L.Add('need to pass a complex value, serialize it into a `string` first.');
    L.Add('');
  end;

  procedure EmitTroubleshooting;
  begin
    L.Add('## 7. Debugging & Troubleshooting');
    L.Add('');
    L.Add('### 7.1 Global configuration variables');
    L.Add('');
    L.Add('The generated provider unit exposes the following global variables in');
    L.Add('its `interface` section. They can be modified at runtime (or before');
    L.Add('compilation) to adjust behaviour.');
    L.Add('');
    L.Add('| Variable | Default | Purpose |');
    L.Add('|----------|---------|---------|');
    L.Add('| `MY_APP_NAME` | `' + AppName + '` | LingoFuse application name |');
    L.Add('| `MY_APP_DESC` | (auto) | Application description |');
    L.Add('| `IPC_ENDPOINT` | `ipc:agent` | IPC endpoint |');
    L.Add('| `BEACON_APP` | `agent_main_app` | Beacon application name |');
    L.Add('| `REGISTER_API` | `register_agent` | Tool-registration API name |');
    L.Add('| `AGENT_LOG_API` | `agent_log` | Log API name |');
    L.Add('| `DEBUG_LOG` | `True` | Verbose logging toggle |');
    L.Add('');
    L.Add('### 7.2 Common problems');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `fpc: fatal: Can''t find unit Z.Core` | ZCore search path missing | Add `-Fu<ZNetV2>/ZCore` |');
    L.Add('| `fpc: fatal: Can''t find unit lingofuse_import` | ZNetV2 search path missing | Add `-Fu<ZNetV2>` |');
    L.Add('| `z_ipc_*.dll not found` | ZNetV2 binary not on PATH | Copy `z_ipc_*.dll` next to the .exe |');
    L.Add('| `Execute_And_Reg_all` returns False | Beacon not running | Start `pascal_agent_service.exe` first |');
    L.Add('| `LF_PrepareDone` returns 0 | Main thread already active in this process | Reuse the existing runtime, or call `LF_Shutdown` first |');
    L.Add('| `[RegisterTools] Beacon not available` | `ipc:agent` unreachable | Confirm beacon is running; check firewall |');
    L.Add('| `[RegisterTools] FAIL: <name>` | Tool rejected by beacon | Check `DEBUG_LOG` output; verify schema |');
    L.Add('| Tool missing from agent list | Function filtered out | Check param/return types against §6 whitelist |');
    L.Add('| `Callback_<name> Exception` | Exception in user code | Inspect the tool log; the callback wraps user code in try/except |');
    L.Add('| LLM cannot reach tool | `mcp_api_tool` not running | Start `python mcp_api_tool.py --transport stdio` |');
    L.Add('');
    L.Add('### 7.3 Enabling detailed logs');
    L.Add('');
    L.Add('Set `DEBUG_LOG := True` in the provider unit (default: `True`). Every');
    L.Add('callback then prints its input JSON, its result, and any error to the');
    L.Add('beacon via `agent_log`, and to `DoStatus` locally.');
    L.Add('');
    L.Add('To view the beacon-side log, run any LingoFuse console viewer that');
    L.Add('queries `agent_log`.');
    L.Add('');
  end;

  procedure EmitDelphiPortability;
  begin
    L.Add('## 8. Delphi Portability');
    L.Add('');
    L.Add('The `.lpr` file is the Free Pascal / Lazarus program entry point. It is');
    L.Add('**structurally identical** to a Delphi `.dpr` file: both are Pascal');
    L.Add('programs with the same `program` / `uses` / `begin` / `end.` structure.');
    L.Add('');
    L.Add('You can convert the test `.lpr` into a Delphi `.dpr` by:');
    L.Add('');
    L.Add('1. **Renaming** the file extension: `' + AppName + '_provider.lpr`');
    L.Add('   to `' + AppName + '_provider.dpr`.');
    L.Add('2. **Replacing** the top line');
    L.Add('   `{$mode objfpc}{$H+}` with a Delphi-compatible project header');
    L.Add('   (Delphi project files normally do not need `{$mode objfpc}`).');
    L.Add('3. **Adjusting the `uses` clause** if needed: `cthreads` is a Free');
    L.Add('   Pascal unit; on Delphi, remove the `{$IFDEF UNIX} cthreads`');
    L.Add('   block and use the standard Delphi runtime (threads are managed');
    L.Add('   automatically).');
    L.Add('4. **Setting the unit search paths** in the project options so that');
    L.Add('   `Z.Core` and `lingofuse_import` are found.');
    L.Add('');
    L.Add('The generated provider unit `' + UnitName + '_tool_provider_unit.pas`');
    L.Add('itself already uses `{$DEFINE FPC_DELPHI_MODE}` and is');
    L.Add('**Delphi-compatible as-is**. Only the program entry point needs the');
    L.Add('small adjustments above.');
    L.Add('');
    L.Add('Example Delphi `.dpr` equivalent:');
    L.Add('');
    L.Add('```pascal');
    L.Add('program ' + AppName + '_provider;');
    L.Add('');
    L.Add('uses');
    L.Add('  SysUtils, Classes,');
    L.Add('  Z.Core,');
    L.Add('  ' + UnitName + '_tool_provider_unit;');
    L.Add('');
    L.Add('begin');
    L.Add('  WriteLn(''=== ' + AppName + ' Tool Provider ==='');');
    L.Add('  if not Execute_And_Reg_all then');
    L.Add('  begin');
    L.Add('    WriteLn(''[FATAL] Provider startup failed.'');');
    L.Add('    Halt(1);');
    L.Add('  end;');
    L.Add('  WriteLn(''[OK] Provider is ready. Press Enter to shut down.'');');
    L.Add('  ReadLn;');
    L.Add('  LF_ExitMainThread;');
    L.Add('  LF_Shutdown;');
    L.Add('end.');
    L.Add('```');
    L.Add('');
  end;

  procedure EmitResources;
  begin
    L.Add('## 9. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| ZCore repository | Core primitives used by the provider |');
    L.Add('| ZNetV2 repository | LingoFuse runtime bindings |');
    L.Add('| LingoFuse-pasAgent-v3 | Beacon, examples, LLM/MCP bridge |');
    L.Add('| `CreateHealthCheck/` inside v3 | Complete runnable example provider |');
    L.Add('| `pascal_code_mcp_rule.md` | Code style and type whitelist |');
    L.Add('| `lingofuse_import.pas` | Low-level C ABI reference |');
    L.Add('| `mcp_api_tool.py` | MCP gateway that exposes the tools to LLM clients |');
    L.Add('| `generate_agent_json.py` | Generates MCP client config files |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('_End of document. Generated by `pas_mcp_generator_tool.pas`._');
    L.Add('');
  end;

begin
  Result := TPascalStringList.Create;
  L := Result;

  if Model = nil then
  begin
    L.Add('# README generation skipped');
    L.Add('');
    L.Add('Reason: supplied `TPascal_Func_Model` is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName = '' then
  begin
    L.Add('# README generation skipped');
    L.Add('');
    L.Add('Reason: `Model.UnitName` is empty.');
    Exit;
  end;

  AppName := MakeAppNameFromUnit(UnitName);
  ValidFuncs := CollectValidFunctions(Model);

  EmitHeader;
  EmitOverview;
  EmitArchitecture;
  EmitTestLpr;
  EmitBuildTestProcedure;
  EmitToolReference;
  EmitJsonSchemaSpec;
  EmitTroubleshooting;
  EmitDelphiPortability;
  EmitResources;

  Log(PFormat('GeneratePascalReadme: %d lines, %d APIs.', [L.Count, Length(ValidFuncs)]));
end;

end.
