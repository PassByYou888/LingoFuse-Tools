unit http_pas_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServicePascalTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallPascalTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification
// -----------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal') or
    T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function ABI_Type_To_Pascal_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := ''''''
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
end;

function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else
    Result := '0';
end;

// SuccessMethodName - pick the correct OnSuccess_X method name of
// TAsyncWaiter for a given ABI return type. The mapping is deliberately
// exhaustive so the generator emits a method whose signature exactly
// matches the per-API T<Api>_Success_M method type.
function SuccessMethodName(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'OnSuccess_String'
  else if T.Same('integer') or T.Same('longint') then
    Result := 'OnSuccess_Int32'
  else if T.Same('int64') then
    Result := 'OnSuccess_Int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'OnSuccess_UInt32'
  else if T.Same('word') then
    Result := 'OnSuccess_UInt16'
  else if T.Same('smallint') then
    Result := 'OnSuccess_Int16'
  else if T.Same('byte') then
    Result := 'OnSuccess_UInt8'
  else if T.Same('uint64') then
    Result := 'OnSuccess_UInt64'
  else if T.Same('double') or T.Same('real') then
    Result := 'OnSuccess_Double'
  else if T.Same('single') then
    Result := 'OnSuccess_Single'
  else if T.Same('extended') then
    Result := 'OnSuccess_Extended'
  else
    Result := 'OnSuccess_Void';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafePascalIdent(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'p' + umlIntToStr(Index);
    Exit;
  end;

  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
      ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

function PascalStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '''';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '''' then
    begin
      Result.Append('''');
      Result.Append('''');
    end
    else
      Result.Append(c);
  end;
  Result.Append('''');
end;

function UniqueName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while Used.IndexOf(Base + '_' + umlIntToStr(i).Text) >= 0 do
    Inc(i);
  Result := Base + '_' + umlIntToStr(i).Text;
end;

// -----------------------------------------------------------------------------
// Markdown helpers
// -----------------------------------------------------------------------------

function MdCellEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '|' then
      Result.Append('\|')
    else if c = #10 then
      Result.Append(' ')
    else if c = #13 then
      // skip
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// -----------------------------------------------------------------------------
// Supported-function filtering (mirrors every generator in the toolchain)
// -----------------------------------------------------------------------------

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(f.Params) do
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not ABI_Type_Is_Supported(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: routine with empty Name');
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

// =============================================================================
// SERVICE-SIDE TEST PROGRAM GENERATOR
// =============================================================================
//
// The service-side TAsyncWaiter is intentionally a MINIMAL class:
// only the fields and a Reset method. The service-side async bridge
// (AsyncOnResult_Common) writes to the fields directly and never
// uses a method pointer.

function GenerateHTTPServicePascalTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint, FileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, ArgsJson: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServicePascalTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServicePascalTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  FileName := NormalizedUnit + '_http_json_service_main_test___.pas';

  SupportedFuncs := CollectSupportedFunctions(Model);
  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('program ' + NormalizedUnit.Text + '_http_json_service_main_test___;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by http_pas_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service-side test program for the Pascal HTTP/JSON service.');
    Lines.Add('//');
    Lines.Add('// Pairs with ' + NormalizedUnit.Text + '_http_json_service_unit.pas.');
    Lines.Add('//');
    Lines.Add('// Modes:');
    Lines.Add('//   (default)  Start the service and block until ReadLn / Ctrl+C.');
    Lines.Add('//   --smoke    Prepare LingoFuse, then issue TWO self-call');
    Lines.Add('//              variants per exposed API:');
    Lines.Add('//                 - App name  sync');
    Lines.Add('//                 - App name  async M');
    Lines.Add('//              No bridge.py is required; the self-calls stay inside');
    Lines.Add('//              the local App registration.');
    Lines.Add('//');
    Lines.Add('// Why only App-name addressing:');
    Lines.Add('//   The HTTP/JSON transport reaches the service through the');
    Lines.Add('//   fixed bridge application. UID and P2PName routing belong to');
    Lines.Add('//   the LingoFuse mesh layer and cannot be expressed through the');
    Lines.Add('//   HTTP bridge''s fixed entry point, so they are not tested here.');
    Lines.Add('//');
    Lines.Add('// Compile:');
    Lines.Add('//   fpc ' + FileName.Text);
    Lines.Add('//');
    Lines.Add('// Run:');
    Lines.Add('//   ' + NormalizedUnit.Text + '_http_json_service_main_test___');
    Lines.Add('//   ' + NormalizedUnit.Text + '_http_json_service_main_test___ --smoke');
    Lines.Add('//');
    Lines.Add('// Target: FPC 3.2+ or Delphi 10.4+.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('{$ifdef FPC}');
    Lines.Add('  {$mode objfpc}{$H+}');
    Lines.Add('  {$CODEPAGE UTF8}');
    Lines.Add('{$endif}');
    Lines.Add('{$apptype console}');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  {$IFDEF UNIX}');
    Lines.Add('  cthreads,');
    Lines.Add('  {$ENDIF}');
    Lines.Add('  SysUtils, Classes,');
    Lines.Add('  Z.Core,');
    Lines.Add('  Z.PascalStrings, Z.UPascalStrings,');
    Lines.Add('  Z.Json,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  lingofuse_helper,');
    Lines.Add('  ' + NormalizedUnit.Text + '_http_json_service_unit;');
    Lines.Add('');
    Lines.Add('const');
    Lines.Add('  EXIT_OK = 0;');
    Lines.Add('  EXIT_FAILED = 1;');
    Lines.Add('  SERVICE_ENDPOINT = ' + PascalStrLit(Endpoint).Text + ';');
    Lines.Add('');
    Lines.Add('type');
    Lines.Add('  // TAsyncWaiter - the shared per-call state object for one');
    Lines.Add('  // asynchronous self-call.');
    Lines.Add('  //');
    Lines.Add('  // The service-side async bridge (AsyncOnResult_Common, defined');
    Lines.Add('  // below) accesses the fields directly. No method pointers are');
    Lines.Add('  // used here, which keeps this class minimal and free of the');
    Lines.Add('  // compiler hints that would otherwise fire on unused parameters.');
    Lines.Add('  TAsyncWaiter = class');
    Lines.Add('  public');
    Lines.Add('    Done: Boolean;');
    Lines.Add('    Success: Boolean;');
    Lines.Add('    ErrMsg: string;');
    Lines.Add('    ErrCode: Integer;');
    Lines.Add('    procedure Reset;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  g_App: TAppHnd___ = nil;');
    Lines.Add('  g_SmokeDone: Boolean = False;');
    Lines.Add('  g_SmokePass: Integer = 0;');
    Lines.Add('  g_SmokeFail: Integer = 0;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// TAsyncWaiter');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.Reset;');
    Lines.Add('begin');
    Lines.Add('  Done := False;');
    Lines.Add('  Success := False;');
    Lines.Add('  ErrMsg := '''';');
    Lines.Add('  ErrCode := 0;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// Forward declaration: SelfCall_Async below takes @AsyncOnResult_Common');
    Lines.Add('// as the LF_Async_CallEx callback. Pascal requires the identifier to be');
    Lines.Add('// known before use, so we forward-declare it here.');
    Lines.Add('procedure AsyncOnResult_Common(Data: Pointer; Result_: TDataHnd___); cdecl; forward;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// LingoFuse preparation / shutdown');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('function PrepareLingoFuse: Boolean;');
    Lines.Add('begin');
    Lines.Add('  Result := False;');
    Lines.Add('');
    Lines.Add('  LF_ResetPrepare;');
    Lines.Add('  LF_SetOptionEx(''Wait_Connection_ReadyOk'', ''False'');');
    Lines.Add('  LF_SetOptionEx(''Overlap_Connection'', ''True'');');
    Lines.Add('');
    Lines.Add('  if LF_PrepareServiceEx(SERVICE_ENDPOINT, SERVICE_ENDPOINT) < 0 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] LF_PrepareService failed for endpoint "'' +');
    Lines.Add('      SERVICE_ENDPOINT + ''".'');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  g_App := CreateAndRegisterHTTPJsonApp;');
    Lines.Add('  if g_App = nil then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] CreateAndRegisterHTTPJsonApp returned nil.'');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if LF_PrepareClientEx(SERVICE_ENDPOINT, g_App) < 0 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] LF_PrepareClient failed for endpoint "'' +');
    Lines.Add('      SERVICE_ENDPOINT + ''".'');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if LF_PrepareDone() <> 1 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] LF_PrepareDone failed.'');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  Result := True;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure ShutdownLingoFuse;');
    Lines.Add('begin');
    Lines.Add('  try');
    Lines.Add('    LF_ExitMainThread;');
    Lines.Add('  except');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if g_App <> nil then');
    Lines.Add('  begin');
    Lines.Add('    try');
    Lines.Add('      LF_FreeApp(g_App);');
    Lines.Add('    except');
    Lines.Add('    end;');
    Lines.Add('    g_App := nil;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  try');
    Lines.Add('    LF_Shutdown;');
    Lines.Add('  except');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Smoke-test helpers');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('procedure WaitForAsync(W: TAsyncWaiter; TimeoutMs: Cardinal);');
    Lines.Add('var');
    Lines.Add('  tk: UInt64;');
    Lines.Add('begin');
    Lines.Add('  tk := GetTimeTick;');
    Lines.Add('  while (not W.Done) and (GetTimeTick - tk < TimeoutMs) do');
    Lines.Add('    Sleep(10);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure SelfCall_Sync(const ApiName, RequestJson: string);');
    Lines.Add('var');
    Lines.Add('  req, resp: TDataHnd___;');
    Lines.Add('  reqBytes, respBytes: TBytes;');
    Lines.Add('  respJo: TZ_JsonObject;');
    Lines.Add('  code: Integer;');
    Lines.Add('  respText: string;');
    Lines.Add('begin');
    Lines.Add('  code := -1;');
    Lines.Add('  respText := '''';');
    Lines.Add('  req := LF_CreateDataEx(ApiName);');
    Lines.Add('  if req = nil then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''  '' + ApiName + '' [sync]: FAILED: CreateData'');');
    Lines.Add('    Inc(g_SmokeFail);');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('  try');
    Lines.Add('    reqBytes := TEncoding.UTF8.GetBytes(RequestJson);');
    Lines.Add('    LF_WriteStringBytes(req, reqBytes);');
    Lines.Add('');
    Lines.Add('    resp := LF_CallEx(HTTP_SERVICE_APP_NAME, req, 5000);');
    Lines.Add('');
    Lines.Add('    if resp = nil then');
    Lines.Add('    begin');
    Lines.Add('      WriteLn(ErrOutput, ''  '' + ApiName + '' [sync]: FAILED: nil handle'');');
    Lines.Add('      Inc(g_SmokeFail);');
    Lines.Add('      Exit;');
    Lines.Add('    end;');
    Lines.Add('    try');
    Lines.Add('      respBytes := LF_ReadStringBytes(resp);');
    Lines.Add('      if Length(respBytes) = 0 then');
    Lines.Add('      begin');
    Lines.Add('        WriteLn(ErrOutput, ''  '' + ApiName + '' [sync]: FAILED: empty'');');
    Lines.Add('        Inc(g_SmokeFail);');
    Lines.Add('        Exit;');
    Lines.Add('      end;');
    Lines.Add('      respText := TEncoding.UTF8.GetString(respBytes);');
    Lines.Add('      respJo := TZ_JsonObject.Create;');
    Lines.Add('      try');
    Lines.Add('        if respJo.Parae(respBytes) and respJo.Exists(''code'') then');
    Lines.Add('          code := respJo.I[''code''];');
    Lines.Add('      finally');
    Lines.Add('        respJo.Free;');
    Lines.Add('      end;');
    Lines.Add('    finally');
    Lines.Add('      LF_FreeData(resp);');
    Lines.Add('    end;');
    Lines.Add('  finally');
    Lines.Add('    LF_FreeData(req);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if code = 0 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(''  '' + ApiName + '' [sync]: OK'');');
    Lines.Add('    Inc(g_SmokePass);');
    Lines.Add('  end');
    Lines.Add('  else');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''  '' + ApiName + '' [sync]: FAILED (code='' +');
    Lines.Add('      IntToStr(code) + ''): '' + respText);');
    Lines.Add('    Inc(g_SmokeFail);');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure SelfCall_Async(const ApiName, RequestJson: string);');
    Lines.Add('var');
    Lines.Add('  req: TDataHnd___;');
    Lines.Add('  reqBytes: TBytes;');
    Lines.Add('  W: TAsyncWaiter;');
    Lines.Add('  rc: Integer;');
    Lines.Add('begin');
    Lines.Add('  W := TAsyncWaiter.Create;');
    Lines.Add('  try');
    Lines.Add('    W.Reset;');
    Lines.Add('    req := LF_CreateDataEx(ApiName);');
    Lines.Add('    if req = nil then');
    Lines.Add('    begin');
    Lines.Add('      WriteLn(ErrOutput, ''  '' + ApiName + '' [async]: FAILED: CreateData'');');
    Lines.Add('      Inc(g_SmokeFail);');
    Lines.Add('      Exit;');
    Lines.Add('    end;');
    Lines.Add('    try');
    Lines.Add('      reqBytes := TEncoding.UTF8.GetBytes(RequestJson);');
    Lines.Add('      LF_WriteStringBytes(req, reqBytes);');
    Lines.Add('');
    Lines.Add('      rc := LF_Async_CallEx(HTTP_SERVICE_APP_NAME, req, W,');
    Lines.Add('        @AsyncOnResult_Common);');
    Lines.Add('');
    Lines.Add('      if rc = 0 then');
    Lines.Add('      begin');
    Lines.Add('        WriteLn(ErrOutput, ''  '' + ApiName + '' [async]: FAILED: submit'');');
    Lines.Add('        Inc(g_SmokeFail);');
    Lines.Add('        Exit;');
    Lines.Add('      end;');
    Lines.Add('');
    Lines.Add('      WaitForAsync(W, 5000);');
    Lines.Add('      if not W.Done then');
    Lines.Add('      begin');
    Lines.Add('        WriteLn(ErrOutput, ''  '' + ApiName + '' [async]: FAILED: timeout'');');
    Lines.Add('        Inc(g_SmokeFail);');
    Lines.Add('      end');
    Lines.Add('      else if W.Success then');
    Lines.Add('      begin');
    Lines.Add('        WriteLn(''  '' + ApiName + '' [async]: OK'');');
    Lines.Add('        Inc(g_SmokePass);');
    Lines.Add('      end');
    Lines.Add('      else');
    Lines.Add('      begin');
    Lines.Add('        WriteLn(ErrOutput, ''  '' + ApiName + '' [async]: FAILED: '' +');
    Lines.Add('          W.ErrMsg);');
    Lines.Add('        Inc(g_SmokeFail);');
    Lines.Add('      end;');
    Lines.Add('    finally');
    Lines.Add('      LF_FreeData(req);');
    Lines.Add('    end;');
    Lines.Add('  finally');
    Lines.Add('    W.Free;');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure SmokeRun;');
    Lines.Add('begin');
    Lines.Add('  try');
    Lines.Add('    Sleep(2000);');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ArgsJson := '';
      if Length(F.Params) > 0 then
      begin
        ArgsJson := '{"args": [';
        for j := 0 to High(F.Params) do
        begin
          if j > 0 then ArgsJson := ArgsJson + ', ';
          ArgsJson := ArgsJson + ABI_Type_To_Json_Default_Literal(F.Params[j].PascalType);
        end;
        ArgsJson := ArgsJson + ']}';
      end
      else
        ArgsJson := '{}';

      Lines.Add('    SelfCall_Sync(' + PascalStrLit(ApiName).Text + ', ' +
        PascalStrLit(ArgsJson).Text + ');');
      Lines.Add('    SelfCall_Async(' + PascalStrLit(ApiName).Text + ', ' +
        PascalStrLit(ArgsJson).Text + ');');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('    WriteLn(''  (no APIs to smoke-test)'');');

    Lines.Add('  finally');
    Lines.Add('    g_SmokeDone := True;');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// AsyncOnResult_Common - cdecl bridge that translates the raw');
    Lines.Add('// LF_Async_CallEx callback into the TAsyncWaiter it carries as Data.');
    Lines.Add('//');
    Lines.Add('// The result handle is framework-owned: it is valid only during this');
    Lines.Add('// callback and is freed by the framework after we return. We must');
    Lines.Add('// therefore read every byte we need here and copy it out; the handle');
    Lines.Add('// itself is never stored or passed to user code.');
    Lines.Add('procedure AsyncOnResult_Common(Data: Pointer; Result_: TDataHnd___); cdecl;');
    Lines.Add('var');
    Lines.Add('  W: TAsyncWaiter;');
    Lines.Add('  respBytes: TBytes;');
    Lines.Add('  respJo: TZ_JsonObject;');
    Lines.Add('  code: Integer;');
    Lines.Add('begin');
    Lines.Add('  W := TAsyncWaiter(Data);');
    Lines.Add('  if W = nil then Exit;');
    Lines.Add('  try');
    Lines.Add('    if Result_ = nil then');
    Lines.Add('    begin');
    Lines.Add('      W.ErrMsg := ''nil handle'';');
    Lines.Add('      Exit;');
    Lines.Add('    end;');
    Lines.Add('    respBytes := LF_ReadStringBytes(Result_);');
    Lines.Add('    if Length(respBytes) = 0 then');
    Lines.Add('    begin');
    Lines.Add('      W.ErrMsg := ''empty response'';');
    Lines.Add('      Exit;');
    Lines.Add('    end;');
    Lines.Add('    respJo := TZ_JsonObject.Create;');
    Lines.Add('    try');
    Lines.Add('      if not respJo.Parae(respBytes) then');
    Lines.Add('        W.ErrMsg := ''invalid JSON''');
    Lines.Add('      else if not respJo.Exists(''code'') then');
    Lines.Add('        W.ErrMsg := ''missing code''');
    Lines.Add('      else');
    Lines.Add('      begin');
    Lines.Add('        code := respJo.I[''code''];');
    Lines.Add('        if code = 0 then');
    Lines.Add('          W.Success := True');
    Lines.Add('        else');
    Lines.Add('        begin');
    Lines.Add('          W.ErrMsg := ''service code='' + IntToStr(code);');
    Lines.Add('          if respJo.Exists(''error'') then');
    Lines.Add('            W.ErrMsg := W.ErrMsg + '': '' + respJo.S[''error''];');
    Lines.Add('        end;');
    Lines.Add('      end;');
    Lines.Add('    finally');
    Lines.Add('      respJo.Free;');
    Lines.Add('    end;');
    Lines.Add('  except');
    Lines.Add('    on E: Exception do');
    Lines.Add('      W.ErrMsg := ''exception: '' + E.Message;');
    Lines.Add('  end;');
    Lines.Add('  W.Done := True;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Modes');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('function RunDefault: Integer;');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''=== '' + HTTP_SERVICE_APP_NAME + '' HTTP/JSON service test ==='');');
    Lines.Add('  WriteLn(''Endpoint: '' + SERVICE_ENDPOINT);');
    Lines.Add('  WriteLn(''API count: ' + MdInt(Length(SupportedFuncs)).Text + ''');');
    Lines.Add('  WriteLn;');
    Lines.Add('');
    Lines.Add('  if not PrepareLingoFuse then');
    Lines.Add('  begin');
    Lines.Add('    ShutdownLingoFuse;');
    Lines.Add('    Exit(EXIT_FAILED);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  WriteLn(''[OK] Service ready. Press Enter to stop (or send SIGINT).'');');
    Lines.Add('  try ReadLn; except end;');
    Lines.Add('');
    Lines.Add('  WriteLn(''[OK] Stopping service...'');');
    Lines.Add('  ShutdownLingoFuse;');
    Lines.Add('  WriteLn(''[OK] Service stopped cleanly.'');');
    Lines.Add('  Result := EXIT_OK;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('function RunSmoke: Integer;');
    Lines.Add('var');
    Lines.Add('  tk: UInt64;');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''=== '' + HTTP_SERVICE_APP_NAME + '' HTTP/JSON service test ==='');');
    Lines.Add('  WriteLn(''Endpoint: '' + SERVICE_ENDPOINT);');
    Lines.Add('  WriteLn(''API count: ' + MdInt(Length(SupportedFuncs)).Text + ''');');
    Lines.Add('  WriteLn;');
    Lines.Add('  WriteLn(''[smoke] Running App-name sync + async self-calls.'');');
    Lines.Add('  WriteLn(''[smoke] No bridge.py is required.'');');
    Lines.Add('  WriteLn;');
    Lines.Add('');
    Lines.Add('  if not PrepareLingoFuse then');
    Lines.Add('  begin');
    Lines.Add('    ShutdownLingoFuse;');
    Lines.Add('    Exit(EXIT_FAILED);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  g_SmokeDone := False;');
    Lines.Add('  g_SmokePass := 0;');
    Lines.Add('  g_SmokeFail := 0;');
    Lines.Add('  TCompute.RunC_NP(@SmokeRun);');
    Lines.Add('');
    Lines.Add('  tk := GetTimeTick;');
    Lines.Add('  while (not g_SmokeDone) and (GetTimeTick - tk < 180000) do');
    Lines.Add('    Check_Soft_Thread_Synchronize(20);');
    Lines.Add('');
    Lines.Add('  if not g_SmokeDone then');
    Lines.Add('    WriteLn(ErrOutput, ''[smoke] Timeout.'');');
    Lines.Add('');
    Lines.Add('  WriteLn;');
    Lines.Add('  WriteLn(''=== Smoke test summary ==='');');
    Lines.Add('  WriteLn(''Passed: '' + IntToStr(g_SmokePass));');
    Lines.Add('  WriteLn(''Failed: '' + IntToStr(g_SmokeFail));');
    Lines.Add('');
    Lines.Add('  ShutdownLingoFuse;');
    Lines.Add('');
    Lines.Add('  if (g_SmokeFail = 0) and g_SmokeDone then');
    Lines.Add('    Result := EXIT_OK');
    Lines.Add('  else');
    Lines.Add('    Result := EXIT_FAILED;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('begin');
    Lines.Add('  if (ParamCount > 0) and (ParamStr(1) = ''--smoke'') then');
    Lines.Add('    ExitCode := RunSmoke');
    Lines.Add('  else');
    Lines.Add('    ExitCode := RunDefault;');
    Lines.Add('end.');

    Result := Lines;
    Log(PFormat('Generated Pascal service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// CALL-SIDE TEST PROGRAM GENERATOR
// =============================================================================
//
// The client-side TAsyncWaiter exposes the full set of OnSuccess_X methods
// because the generated call wrapper accepts them as T<Api>_Success_M
// method pointers. Each OnSuccess_X names its parameter `_` so the
// compiler does not warn about an unused parameter (the test cares only
// about success/failure, not the value).
//
// At the call sites we pass `@W.OnSuccess_X` and `@W.OnError`. Writing
// `W.OnSuccess_X` without the `@` would make the compiler try to call
// the method (parameter-count mismatch), not take a pointer.

function GenerateHTTPCallPascalTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint, BaseUrl, FileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, ArgList: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPascalTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPascalTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  FileName := NormalizedUnit + '_http_json_call_main_test___.pas';

  SupportedFuncs := CollectSupportedFunctions(Model);
  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('program ' + NormalizedUnit.Text + '_http_json_call_main_test___;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by http_pas_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side test program for the Pascal HTTP/JSON call wrapper.');
    Lines.Add('//');
    Lines.Add('// Pairs with ' + NormalizedUnit.Text + '_http_json_call_unit.pas.');
    Lines.Add('//');
    Lines.Add('// Flow:');
    Lines.Add('//   1. Prepare LingoFuse as a pure consumer.');
    Lines.Add('//   2. For each exposed API, issue TWO variants:');
    Lines.Add('//        - <Api>              sync / App');
    Lines.Add('//        - <Api>_Async         async / App (M)');
    Lines.Add('//   3. Print OK / FAILED per variant, then a summary.');
    Lines.Add('//');
    Lines.Add('// Why only App-name addressing:');
    Lines.Add('//   The HTTP/JSON transport reaches the service through the');
    Lines.Add('//   fixed bridge application. UID and P2PName routing belong to');
    Lines.Add('//   the LingoFuse mesh layer and cannot be expressed through the');
    Lines.Add('//   HTTP bridge''s fixed entry point.');
    Lines.Add('//');
    Lines.Add('// The `_P` variants are NOT tested: under FPC the callbacks are');
    Lines.Add('// `is nested` and cannot be invoked from a worker thread. See the');
    Lines.Add('// call-generator README for details.');
    Lines.Add('//');
    Lines.Add('// METHOD-POINTER SYNTAX: every async call passes @W.OnSuccess_X and');
    Lines.Add('// @W.OnError. Without the leading @, Pascal would try to call the');
    Lines.Add('// method (parameter-count mismatch) instead of taking a pointer.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * bridge.py must be running on the same LingoFuse endpoint;');
    Lines.Add('//   * the matching service must be running on the same endpoint.');
    Lines.Add('//');
    Lines.Add('// Compile:');
    Lines.Add('//   fpc ' + FileName.Text);
    Lines.Add('//');
    Lines.Add('// Run:');
    Lines.Add('//   ' + NormalizedUnit.Text + '_http_json_call_main_test___');
    Lines.Add('//   ' + NormalizedUnit.Text + '_http_json_call_main_test___ <base_url> <endpoint>');
    Lines.Add('//');
    Lines.Add('// Target: FPC 3.2+ or Delphi 10.4+.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('{$ifdef FPC}');
    Lines.Add('  {$mode objfpc}{$H+}');
    Lines.Add('  {$CODEPAGE UTF8}');
    Lines.Add('{$endif}');
    Lines.Add('{$apptype console}');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  {$IFDEF UNIX}');
    Lines.Add('  cthreads,');
    Lines.Add('  {$ENDIF}');
    Lines.Add('  SysUtils, Classes,');
    Lines.Add('  Z.Core,');
    Lines.Add('  Z.PascalStrings, Z.UPascalStrings,');
    Lines.Add('  Z.Json,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  lingofuse_helper,');
    Lines.Add('  ' + NormalizedUnit.Text + '_http_json_call_unit;');
    Lines.Add('');
    Lines.Add('const');
    Lines.Add('  EXIT_OK = 0;');
    Lines.Add('  EXIT_FAILED = 1;');
    Lines.Add('  SERVICE_APP_NAME = ' + PascalStrLit(AppName).Text + ';');
    Lines.Add('  DEFAULT_BASE_URL = ' + PascalStrLit(BaseUrl).Text + ';');
    Lines.Add('  DEFAULT_ENDPOINT = ' + PascalStrLit(Endpoint).Text + ';');
    Lines.Add('');
    Lines.Add('type');
    Lines.Add('  // TAsyncWaiter - receives the outcome of one asynchronous call.');
    Lines.Add('  //');
    Lines.Add('  // One instance is created per async call. The success callbacks');
    Lines.Add('  // are per-type so the instance can be passed as the T<Api>_Success_M');
    Lines.Add('  // method pointer required by the generated call wrapper without');
    Lines.Add('  // any casts. The error callback is the shared TCallError_M.');
    Lines.Add('  //');
    Lines.Add('  // Each OnSuccess_X names its parameter `_` to avoid Hint 5024');
    Lines.Add('  // (unused parameter) - the test only cares about success/failure.');
    Lines.Add('  TAsyncWaiter = class');
    Lines.Add('  public');
    Lines.Add('    Done: Boolean;');
    Lines.Add('    Success: Boolean;');
    Lines.Add('    ErrMsg: string;');
    Lines.Add('    ErrCode: Integer;');
    Lines.Add('    procedure Reset;');
    Lines.Add('    procedure OnSuccess_Void();');
    Lines.Add('    procedure OnSuccess_Int16(const _: SmallInt);');
    Lines.Add('    procedure OnSuccess_Int32(const _: Integer);');
    Lines.Add('    procedure OnSuccess_Int64(const _: Int64);');
    Lines.Add('    procedure OnSuccess_UInt8(const _: Byte);');
    Lines.Add('    procedure OnSuccess_UInt16(const _: Word);');
    Lines.Add('    procedure OnSuccess_UInt32(const _: Cardinal);');
    Lines.Add('    procedure OnSuccess_UInt64(const _: UInt64);');
    Lines.Add('    procedure OnSuccess_Single(const _: Single);');
    Lines.Add('    procedure OnSuccess_Double(const _: Double);');
    Lines.Add('    procedure OnSuccess_Extended(const _: Extended);');
    Lines.Add('    procedure OnSuccess_String(const _: string);');
    Lines.Add('    procedure OnError(const Msg: string; Code: Integer);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  g_CallDone: Boolean = False;');
    Lines.Add('  g_Pass: Integer = 0;');
    Lines.Add('  g_Fail: Integer = 0;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// TAsyncWaiter');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.Reset;');
    Lines.Add('begin');
    Lines.Add('  Done := False;');
    Lines.Add('  Success := False;');
    Lines.Add('  ErrMsg := '''';');
    Lines.Add('  ErrCode := 0;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Void();');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Int16(const _: SmallInt);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Int32(const _: Integer);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Int64(const _: Int64);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_UInt8(const _: Byte);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_UInt16(const _: Word);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_UInt32(const _: Cardinal);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_UInt64(const _: UInt64);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Single(const _: Single);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Double(const _: Double);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_Extended(const _: Extended);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnSuccess_String(const _: string);');
    Lines.Add('begin Success := True; Done := True; end;');
    Lines.Add('');
    Lines.Add('procedure TAsyncWaiter.OnError(const Msg: string; Code: Integer);');
    Lines.Add('begin ErrMsg := Msg; ErrCode := Code; Done := True; end;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Helpers');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('procedure ReportOk(const Tag_: string);');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''  '' + Tag_ + '': OK'');');
    Lines.Add('  Inc(g_Pass);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure ReportFail(const Tag_, Msg: string);');
    Lines.Add('begin');
    Lines.Add('  WriteLn(ErrOutput, ''  '' + Tag_ + '': FAILED: '' + Msg);');
    Lines.Add('  Inc(g_Fail);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('function WaitForAsync(W: TAsyncWaiter; TimeoutMs: Cardinal): Boolean;');
    Lines.Add('var tk: UInt64;');
    Lines.Add('begin');
    Lines.Add('  tk := GetTimeTick;');
    Lines.Add('  while (not W.Done) and (GetTimeTick - tk < TimeoutMs) do');
    Lines.Add('    Sleep(10);');
    Lines.Add('  Result := W.Done;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Per-API tests');
    Lines.Add('//');
    Lines.Add('// Two variants per API. Each variant runs in the CallWorker thread.');
    Lines.Add('// Sync variants rely on the wrapper''s built-in transport; async variants');
    Lines.Add('// submit and then poll a per-call TAsyncWaiter.');
    Lines.Add('//');
    Lines.Add('// Every async call passes @W.OnSuccess_X and @W.OnError. The `@` is');
    Lines.Add('// required: without it, `W.OnSuccess_X` is parsed as a method call and');
    Lines.Add('// rejected with "Wrong number of parameters".');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');

    // Per-API tests.
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ArgList := '';
      if Length(F.Params) > 0 then
      begin
        for j := 0 to High(F.Params) do
        begin
          if j > 0 then ArgList := ArgList + ', ';
          ArgList := ArgList + ABI_Type_To_Pascal_Default_Literal(F.Params[j].PascalType);
        end;
      end;

      // Sync / App
      Lines.Add('procedure Test_' + ApiName.Text + '_Sync;');
      Lines.Add('begin');
      Lines.Add('  try');
      if ArgList = '' then
        Lines.Add('    ' + ApiName.Text + '();')
      else
        Lines.Add('    ' + ApiName.Text + '(' + ArgList + ');');
      Lines.Add('    ReportOk(' + PascalStrLit(ApiName + '[sync]').Text + ');');
      Lines.Add('  except');
      Lines.Add('    on E: Exception do');
      Lines.Add('      ReportFail(' + PascalStrLit(ApiName + '[sync]').Text + ', E.Message);');
      Lines.Add('  end;');
      Lines.Add('end;');
      Lines.Add('');

      // Async / App / M
      Lines.Add('procedure Test_' + ApiName.Text + '_AsyncM;');
      Lines.Add('var');
      Lines.Add('  W: TAsyncWaiter;');
      Lines.Add('begin');
      Lines.Add('  W := TAsyncWaiter.Create;');
      Lines.Add('  try');
      Lines.Add('    W.Reset;');
      Lines.Add('    try');
      if F.IsFunction then
      begin
        if ArgList = '' then
          Lines.Add('      if not ' + ApiName.Text + '_Async(@W.' + SuccessMethodName(F.ReturnType) + ', @W.OnError) then')
        else
          Lines.Add('      if not ' + ApiName.Text + '_Async(' + ArgList + ', @W.' + SuccessMethodName(F.ReturnType) + ', @W.OnError) then');
      end
      else
      begin
        if ArgList = '' then
          Lines.Add('      if not ' + ApiName.Text + '_Async(@W.OnSuccess_Void, @W.OnError) then')
        else
          Lines.Add('      if not ' + ApiName.Text + '_Async(' + ArgList + ', @W.OnSuccess_Void, @W.OnError) then');
      end;
      Lines.Add('      begin');
      Lines.Add('        ReportFail(' + PascalStrLit(ApiName + '[asyncM]').Text + ', ''submit failed'');');
      Lines.Add('        Exit;');
      Lines.Add('      end;');
      Lines.Add('      if not WaitForAsync(W, 5000) then');
      Lines.Add('      begin');
      Lines.Add('        ReportFail(' + PascalStrLit(ApiName + '[asyncM]').Text + ', ''timeout'');');
      Lines.Add('        Exit;');
      Lines.Add('      end;');
      Lines.Add('      if W.Success then');
      Lines.Add('        ReportOk(' + PascalStrLit(ApiName + '[asyncM]').Text + ')');
      Lines.Add('      else');
      Lines.Add('        ReportFail(' + PascalStrLit(ApiName + '[asyncM]').Text + ', W.ErrMsg);');
      Lines.Add('    except');
      Lines.Add('      on E: Exception do');
      Lines.Add('        ReportFail(' + PascalStrLit(ApiName + '[asyncM]').Text + ', E.Message);');
      Lines.Add('    end;');
      Lines.Add('  finally');
      Lines.Add('    W.Free;');
      Lines.Add('  end;');
      Lines.Add('end;');
      Lines.Add('');
    end;

    // CallWorker
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Worker');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('procedure CallWorker;');
    Lines.Add('begin');
    Lines.Add('  try');
    Lines.Add('    WriteLn;');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Lines.Add('    Test_' + ApiName.Text + '_Sync;');
      Lines.Add('    Test_' + ApiName.Text + '_AsyncM;');
    end;
    Lines.Add('  finally');
    Lines.Add('    g_CallDone := True;');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Main');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  baseUrl, endpoint: string;');
    Lines.Add('  tk: UInt64;');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''=== ' + UnitName.Text + ' HTTP/JSON call test ==='');');
    Lines.Add('');
    Lines.Add('  if (ParamCount >= 1) and (ParamStr(1) <> '''') then');
    Lines.Add('    baseUrl := ParamStr(1)');
    Lines.Add('  else');
    Lines.Add('    baseUrl := DEFAULT_BASE_URL;');
    Lines.Add('');
    Lines.Add('  if (ParamCount >= 2) and (ParamStr(2) <> '''') then');
    Lines.Add('    endpoint := ParamStr(2)');
    Lines.Add('  else');
    Lines.Add('    endpoint := DEFAULT_ENDPOINT;');
    Lines.Add('');
    Lines.Add('  WriteLn(''Base URL: '' + baseUrl);');
    Lines.Add('  WriteLn(''Endpoint: '' + endpoint);');
    Lines.Add('  WriteLn;');
    Lines.Add('');
    Lines.Add('  LF_ResetPrepare;');
    Lines.Add('  LF_SetOptionEx(''Wait_Connection_ReadyOk'', ''True'');');
    Lines.Add('  LF_SetOptionEx(''Overlap_Connection'', ''True'');');
    Lines.Add('');
    Lines.Add('  if LF_PrepareClientEx(endpoint, nil) < 0 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] LF_PrepareClient failed.'');');
    Lines.Add('    ExitCode := EXIT_FAILED;');
    Lines.Add('    Halt(EXIT_FAILED);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if LF_PrepareDone() <> 1 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] LF_PrepareDone failed.'');');
    Lines.Add('    ExitCode := EXIT_FAILED;');
    Lines.Add('    Halt(EXIT_FAILED);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  HTTP_CALL_BASE_URL := baseUrl;');
    Lines.Add('');
    Lines.Add('  Sleep(2000);');
    Lines.Add('');
    Lines.Add('  g_CallDone := False;');
    Lines.Add('  g_Pass := 0;');
    Lines.Add('  g_Fail := 0;');
    Lines.Add('  TCompute.RunC_NP(@CallWorker);');
    Lines.Add('');
    Lines.Add('  tk := GetTimeTick;');
    Lines.Add('  while (not g_CallDone) and (GetTimeTick - tk < 180000) do');
    Lines.Add('    Check_Soft_Thread_Synchronize(20);');
    Lines.Add('');
    Lines.Add('  if not g_CallDone then');
    Lines.Add('    WriteLn(ErrOutput, ''[FATAL] Worker timed out.'');');
    Lines.Add('');
    Lines.Add('  WriteLn;');
    Lines.Add('  WriteLn(''=== Summary ==='');');
    Lines.Add('  WriteLn(''Passed: '' + IntToStr(g_Pass));');
    Lines.Add('  WriteLn(''Failed: '' + IntToStr(g_Fail));');
    Lines.Add('');
    Lines.Add('  try LF_ExitMainThread; except end;');
    Lines.Add('  try LF_Shutdown;      except end;');
    Lines.Add('');
    Lines.Add('  if (g_Fail = 0) and g_CallDone then');
    Lines.Add('    ExitCode := EXIT_OK');
    Lines.Add('  else');
    Lines.Add('    ExitCode := EXIT_FAILED;');
    Lines.Add('end.');

    Result := Lines;
    Log(PFormat('Generated Pascal call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'pascal', 'Pascal HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.pas', False,
    @GenerateHTTPServicePascalTestCode);
  RegisterCodeGenEntry(
    'pascal', 'Pascal HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.pas', False,
    @GenerateHTTPCallPascalTestCode);
end.
