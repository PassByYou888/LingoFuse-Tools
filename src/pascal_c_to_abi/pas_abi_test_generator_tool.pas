unit pas_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestPascalCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestPascalCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function ABI_Type_Is_LF_Binary_Data(const T: TP_String): boolean;
begin
  Result := T.Same('tbytes') or T.Same('array of byte') or T.Same('cbytes');
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Pascal_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') then Result := 'Integer'
  else if T.Same('int64') then Result := 'Int64'
  else if T.Same('cardinal') then Result := 'Cardinal'
  else if T.Same('longint') then Result := 'LongInt'
  else if T.Same('dword') then Result := 'DWord'
  else if T.Same('word') then Result := 'Word'
  else if T.Same('smallint') then Result := 'SmallInt'
  else if T.Same('byte') then Result := 'Byte'
  else if T.Same('uint64') then Result := 'UInt64'
  else if T.Same('longword') then Result := 'LongWord'
  else if T.Same('double') then Result := 'Double'
  else if T.Same('single') then Result := 'Single'
  else if T.Same('extended') then Result := 'Extended'
  else if T.Same('real') then Result := 'Real'
  else if IsStringABIType(T) then Result := 'string'
  else if ABI_Type_Is_LF_Binary_Data(T) then Result := 'PLF_Binary_Data'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Pascal_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsPascalReservedWord(const S: TP_String): Boolean;
begin
  Result :=
    S.Same('and') or S.Same('array') or S.Same('as') or S.Same('asm') or
    S.Same('begin') or S.Same('case') or S.Same('class') or S.Same('const') or
    S.Same('constructor') or S.Same('destructor') or S.Same('div') or S.Same('do') or
    S.Same('downto') or S.Same('else') or S.Same('end') or S.Same('except') or
    S.Same('exports') or S.Same('file') or S.Same('finalization') or S.Same('finally') or
    S.Same('for') or S.Same('function') or S.Same('goto') or S.Same('if') or
    S.Same('implementation') or S.Same('in') or S.Same('inherited') or S.Same('initialization') or
    S.Same('inline') or S.Same('interface') or S.Same('is') or S.Same('label') or
    S.Same('library') or S.Same('mod') or S.Same('nil') or S.Same('not') or
    S.Same('object') or S.Same('of') or S.Same('or') or S.Same('out') or
    S.Same('packed') or S.Same('procedure') or S.Same('program') or S.Same('property') or
    S.Same('raise') or S.Same('record') or S.Same('repeat') or S.Same('resourcestring') or
    S.Same('set') or S.Same('shl') or S.Same('shr') or S.Same('string') or
    S.Same('then') or S.Same('threadvar') or S.Same('to') or S.Same('try') or
    S.Same('type') or S.Same('unit') or S.Same('until') or S.Same('uses') or
    S.Same('var') or S.Same('while') or S.Same('with') or S.Same('xor') or
    S.Same('result');
end;

function MakeSafePascalParamName(const Name: TP_String; Index: Integer): TP_String;
var
  i: Integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := '_a' + umlIntToStr(Index);
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
  if IsPascalReservedWord(Result) then
    Result := Result + '_';
end;

function PlaceholderValue(const ABIType: TP_String; const Index: Integer): TP_String;
begin
  if ABI_Type_Is_LF_Binary_Data(ABIType) then
    Result := 'MakeLF_Binary_Data(16, ' + umlIntToStr(Index) + ')'
  else if IsStringABIType(ABIType) then
    Result := #39 + 'test' + #39
  else if ABIType.Same('double') or ABIType.Same('single')
    or ABIType.Same('extended') or ABIType.Same('real') then
    Result := '3.14'
  else if ABIType.Same('int64') or ABIType.Same('uint64') then
    Result := 'Int64(42)'
  else
    Result := '42';
end;

function HasWaiterSupport(const RetType: TP_String): Boolean;
begin
  Result := ABI_Type_Is_LF_Binary_Data(RetType)
    or IsStringABIType(RetType)
    or RetType.Same('integer') or RetType.Same('int64') or RetType.Same('uint64')
    or RetType.Same('cardinal') or RetType.Same('longint') or RetType.Same('dword')
    or RetType.Same('longword') or RetType.Same('word') or RetType.Same('smallint')
    or RetType.Same('byte') or RetType.Same('double') or RetType.Same('single')
    or RetType.Same('extended') or RetType.Same('real');
end;

function WaiterClassName(const RetType: TP_String): TP_String;
begin
  if ABI_Type_Is_LF_Binary_Data(RetType) then Result := 'TLF_Binary_DataWaiter'
  else if IsStringABIType(RetType) then Result := 'TStringWaiter'
  else if RetType.Same('integer') then Result := 'TIntegerWaiter'
  else if RetType.Same('int64') then Result := 'TInt64Waiter'
  else if RetType.Same('uint64') then Result := 'TUInt64Waiter'
  else if RetType.Same('cardinal') then Result := 'TCardinalWaiter'
  else if RetType.Same('longint') then Result := 'TLongIntWaiter'
  else if RetType.Same('dword') then Result := 'TDWordWaiter'
  else if RetType.Same('longword') then Result := 'TLongWordWaiter'
  else if RetType.Same('word') then Result := 'TWordWaiter'
  else if RetType.Same('smallint') then Result := 'TSmallIntWaiter'
  else if RetType.Same('byte') then Result := 'TByteWaiter'
  else if RetType.Same('double') then Result := 'TDoubleWaiter'
  else if RetType.Same('single') then Result := 'TSingleWaiter'
  else if RetType.Same('extended') then Result := 'TExtendedWaiter'
  else if RetType.Same('real') then Result := 'TRealWaiter'
  else Result := 'TIntegerWaiter';
end;

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
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
      Supported := False;
    if Supported and (f.Name.Len = 0) then
      Supported := False;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

procedure EmitAllWaiterClasses(Lines: TPascalStringList);
  procedure EmitOne(const ClsName, DeclType: TP_String);
  begin
    Lines.Add('  ' + ClsName + ' = class(TAnyWaiter)');
    Lines.Add('  public');
    Lines.Add('    Value: ' + DeclType + ';');
    Lines.Add('    procedure OnSucc(const V: ' + DeclType + ');');
    Lines.Add('    procedure OnErr(const Msg: string; Code: Integer);');
    Lines.Add('  end;');
    Lines.Add('');
  end;
begin
  EmitOne('TIntegerWaiter',   'Integer');
  EmitOne('TInt64Waiter',     'Int64');
  EmitOne('TUInt64Waiter',    'UInt64');
  EmitOne('TCardinalWaiter',  'Cardinal');
  EmitOne('TLongIntWaiter',   'LongInt');
  EmitOne('TDWordWaiter',     'DWord');
  EmitOne('TLongWordWaiter',  'LongWord');
  EmitOne('TWordWaiter',      'Word');
  EmitOne('TSmallIntWaiter',  'SmallInt');
  EmitOne('TByteWaiter',      'Byte');
  EmitOne('TDoubleWaiter',    'Double');
  EmitOne('TSingleWaiter',    'Single');
  EmitOne('TExtendedWaiter',  'Extended');
  EmitOne('TRealWaiter',      'Real');
  EmitOne('TStringWaiter',    'string');
  EmitOne('TLF_Binary_DataWaiter', 'PLF_Binary_Data');
end;

procedure EmitAllWaiterImpls(Lines: TPascalStringList);
  procedure EmitOne(const ClsName, DeclType, ValueStrExpr: TP_String);
  begin
    Lines.Add('procedure ' + ClsName + '.OnSucc(const V: ' + DeclType + ');');
    Lines.Add('begin');
    Lines.Add('  OK := True;');
    Lines.Add('  Value := V;');
    Lines.Add('  ValueStr := ' + ValueStrExpr + ';');
    Lines.Add('  Done.SetEvent;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure ' + ClsName + '.OnErr(const Msg: string; Code: Integer);');
    Lines.Add('begin');
    Lines.Add('  OK := False;');
    Lines.Add('  ErrMsg := Msg + ' + #39 + ' (code=' + #39 + ' + IntToStr(Code);');
    Lines.Add('  Done.SetEvent;');
    Lines.Add('end;');
    Lines.Add('');
  end;
begin
  EmitOne('TIntegerWaiter',   'Integer',  'IntToStr(V)');
  EmitOne('TInt64Waiter',     'Int64',    'IntToStr(V)');
  EmitOne('TUInt64Waiter',    'UInt64',   'IntToStr(Int64(V))');
  EmitOne('TCardinalWaiter',  'Cardinal', 'IntToStr(Int64(V))');
  EmitOne('TLongIntWaiter',   'LongInt',  'IntToStr(V)');
  EmitOne('TDWordWaiter',     'DWord',    'IntToStr(Int64(V))');
  EmitOne('TLongWordWaiter',  'LongWord', 'IntToStr(Int64(V))');
  EmitOne('TWordWaiter',      'Word',     'IntToStr(V)');
  EmitOne('TSmallIntWaiter',  'SmallInt', 'IntToStr(V)');
  EmitOne('TByteWaiter',      'Byte',     'IntToStr(V)');
  EmitOne('TDoubleWaiter',    'Double',   'FloatToStr(V)');
  EmitOne('TSingleWaiter',    'Single',   'FloatToStr(V)');
  EmitOne('TExtendedWaiter',  'Extended', 'FloatToStr(V)');
  EmitOne('TRealWaiter',      'Real',     'FloatToStr(V)');
  EmitOne('TStringWaiter',    'string',   'V');
  EmitOne('TLF_Binary_DataWaiter', 'PLF_Binary_Data', 'LF_Binary_Data_ToStr(V)');
end;

function GenerateABIServiceTestPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  Norm: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  if Model.UnitName.Len = 0 then Exit;
  Norm := MakeApiName(Model.UnitName);

  Result := TPascalStringList.Create;
  Result.Add('unit ' + Norm + '_abi_service_test_unit;');
  Result.Add('');
  Result.Add('{$ifdef FPC}');
  Result.Add('  {$mode delphi}{$H+}');
  Result.Add('  {$MODESWITCH NestedProcVars}');
  Result.Add('  {$CODEPAGE UTF8}');
  Result.Add('{$endif}');
  Result.Add('{$R-}{$I-}{$Q-}{$B-}');
  Result.Add('');
  Result.Add('interface');
  Result.Add('');
  Result.Add('uses');
  Result.Add('  SysUtils, Classes,');
  Result.Add('  lingofuse_import,');
  Result.Add('  abi_wire_unit,');
  Result.Add('  ' + Norm + '_abi_service_unit;');
  Result.Add('');
  Result.Add('const');
  Result.Add('  SVC_TEST_WHOAMI_API = ' + #39 + 'LF_TEST_WHOAMI' + #39 + ';');
  Result.Add('  SVC_TEST_ASK_API = ' + #39 + 'LF_TEST_ASK_SERVICE_CALL_ME' + #39 + ';');
  Result.Add('  SVC_TEST_CLIENT_REPORT_API = ' + #39 + 'LF_TEST_REPORT_SERVICE_IDENTITY' + #39 + ';');
  Result.Add('  SVC_TEST_P2P_NAME = ' + #39 + Norm + '_service_test_p2p' + #39 + ';');
  Result.Add('');
  Result.Add('function Start_Service_Test: Boolean;');
  Result.Add('procedure Stop_Service_Test;');
  Result.Add('function Is_Service_Running: Boolean;');
  Result.Add('procedure Run_Service_Test_Main;');
  Result.Add('');
  Result.Add('implementation');
  Result.Add('');
  Result.Add('var');
  Result.Add('  G_App: TAppHnd___ = nil;');
  Result.Add('  G_Running: Boolean = False;');
  Result.Add('');
  Result.Add('type');
  Result.Add('  TAskCallMeThread = class(TThread)');
  Result.Add('  private');
  Result.Add('    FClientUID: TP2P_UID___;');
  Result.Add('  protected');
  Result.Add('    procedure Execute; override;');
  Result.Add('  public');
  Result.Add('    constructor Create(const ClientUID: TP2P_UID___);');
  Result.Add('  end;');
  Result.Add('');
  Result.Add('constructor TAskCallMeThread.Create(const ClientUID: TP2P_UID___);');
  Result.Add('begin');
  Result.Add('  inherited Create(True);');
  Result.Add('  FreeOnTerminate := True;');
  Result.Add('  FClientUID := ClientUID;');
  Result.Add('end;');
  Result.Add('');
  Result.Add('procedure TAskCallMeThread.Execute;');
  Result.Add('var');
  Result.Add('  req, res: TDataHnd___;');
  Result.Add('begin');
  Result.Add('  req := LF_CreateDataEx(SVC_TEST_CLIENT_REPORT_API);');
  Result.Add('  if req = nil then Exit;');
  Result.Add('  try');
  Result.Add('    LF_WriteString(req, ' + #39 + 'service-initiated-call' + #39 + ');');
  Result.Add('    res := LF_UID_Call(FClientUID, req, 5000);');
  Result.Add('    if res <> nil then LF_FreeData(res);');
  Result.Add('  finally');
  Result.Add('    LF_FreeData(req);');
  Result.Add('  end;');
  Result.Add('end;');
  Result.Add('');
  Result.Add('procedure Svc_CB_Whoami(_T: Pointer; _In, _Out: TDataHnd___); cdecl;');
  Result.Add('var');
  Result.Add('  uid: TP2P_UID___;');
  Result.Add('  uidPtr: PP2P_UID___;');
  Result.Add('  p2p: string;');
  Result.Add('begin');
  Result.Add('  FillChar(uid, SizeOf(uid), 0);');
  Result.Add('  uidPtr := LF_Get_P2P_UID(_In);');
  Result.Add('  if uidPtr <> nil then uid := uidPtr^;');
  Result.Add('  p2p := LF_Get_P2P_NameEx(_In);');
  Result.Add('  if not LF_WriteUInt8(_Out, 0) then Exit;');
  Result.Add('  if LF_WriteBuffer(_Out, @uid[0], SizeOf(uid)) <> Int64(SizeOf(uid)) then Exit;');
  Result.Add('  LF_WriteString(_Out, p2p);');
  Result.Add('end;');
  Result.Add('');
  Result.Add('procedure Svc_CB_AskCallMe(_T: Pointer; _In: TDataHnd___); cdecl;');
  Result.Add('var');
  Result.Add('  uid: TP2P_UID___;');
  Result.Add('  uidPtr: PP2P_UID___;');
  Result.Add('begin');
  Result.Add('  uidPtr := LF_Get_P2P_UID(_In);');
  Result.Add('  if uidPtr = nil then Exit;');
  Result.Add('  uid := uidPtr^;');
  Result.Add('  TAskCallMeThread.Create(uid).Start;');
  Result.Add('end;');
  Result.Add('');
  Result.Add('function Start_Service_Test: Boolean;');
  Result.Add('var');
  Result.Add('  EP: string;');
  Result.Add('  _fail_count: Integer;');
  Result.Add('begin');
  Result.Add('  Result := False;');
  Result.Add('  if G_Running then Exit;');
  Result.Add('  EP := ' + #39 + 'ipc:' + #39 + ' + DEFAULT_APP_NAME;');
  Result.Add('');
  Result.Add('  LF_ResetPrepare;');
  Result.Add('  LF_Set_Opt_Quiet(True);');
  Result.Add('  LF_Set_Opt_ConsoleOutput(True);');
  Result.Add('  LF_Set_Opt_Overlap_Connection(True);');
  Result.Add('  LF_Set_Opt_Wait_Connection_ReadyOk(True);');
  Result.Add('  LF_Set_Opt_Wait_Connection_Timeout(15000);');
  Result.Add('');
  Result.Add('  if LF_PrepareServiceEx(EP, EP) = -1 then Exit;');
  Result.Add('');
  Result.Add('  G_App := LF_CreateAppEx(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
  Result.Add('  if G_App = nil then');
  Result.Add('  begin');
  Result.Add('    LF_Shutdown;');
  Result.Add('    Exit;');
  Result.Add('  end;');
  Result.Add('');
  Result.Add('  _fail_count := Register_All_ABI_APIs(G_App);');
  Result.Add('  if _fail_count > 0 then');
  Result.Add('    try WriteLn(' + #39 + '[WARN] ' + #39 + ', _fail_count, ' + #39 + ' app-side ABI API(s) failed to register' + #39 + ') except end;');
  Result.Add('  LF_RegisterCallEx(G_App, SVC_TEST_WHOAMI_API, ' + #39 + 'service whoami' + #39 + ', nil, @Svc_CB_Whoami);');
  Result.Add('  LF_RegisterNotifyEx(G_App, SVC_TEST_ASK_API, ' + #39 + 'service ask call back' + #39 + ', nil, @Svc_CB_AskCallMe);');
  Result.Add('');
  Result.Add('  LF_Set_Opt_P2P_Name(SVC_TEST_P2P_NAME);');
  Result.Add('  _fail_count := Register_All_P2P_ABI_APIs;');
  Result.Add('  if _fail_count > 0 then');
  Result.Add('    try WriteLn(' + #39 + '[WARN] ' + #39 + ', _fail_count, ' + #39 + ' p2p-side ABI API(s) failed to register' + #39 + ') except end;');
  Result.Add('  LF_Register_P2P_CallEx(SVC_TEST_WHOAMI_API, ' + #39 + 'service whoami' + #39 + ', nil, @Svc_CB_Whoami);');
  Result.Add('  LF_Register_P2P_NotifyEx(SVC_TEST_ASK_API, ' + #39 + 'service ask call back' + #39 + ', nil, @Svc_CB_AskCallMe);');
  Result.Add('');
  Result.Add('  if LF_PrepareClientEx(EP, G_App) = -1 then');
  Result.Add('  begin');
  Result.Add('    LF_FreeApp(G_App);');
  Result.Add('    G_App := nil;');
  Result.Add('    LF_Shutdown;');
  Result.Add('    Exit;');
  Result.Add('  end;');
  Result.Add('');
  Result.Add('  if LF_PrepareDone <> 1 then');
  Result.Add('  begin');
  Result.Add('    LF_FreeApp(G_App);');
  Result.Add('    G_App := nil;');
  Result.Add('    LF_Shutdown;');
  Result.Add('    Exit;');
  Result.Add('  end;');
  Result.Add('');
  Result.Add('  G_Running := True;');
  Result.Add('  Result := True;');
  Result.Add('end;');
  Result.Add('');
  Result.Add('procedure Stop_Service_Test;');
  Result.Add('begin');
  Result.Add('  if not G_Running then Exit;');
  Result.Add('  G_Running := False;');
  Result.Add('  if G_App <> nil then');
  Result.Add('  begin');
  Result.Add('    LF_FreeApp(G_App);');
  Result.Add('    G_App := nil;');
  Result.Add('  end;');
  Result.Add('  LF_Shutdown;');
  Result.Add('end;');
  Result.Add('');
  Result.Add('function Is_Service_Running: Boolean;');
  Result.Add('begin');
  Result.Add('  Result := G_Running;');
  Result.Add('end;');
  Result.Add('');
  Result.Add('procedure Run_Service_Test_Main;');
  Result.Add('begin');
  Result.Add('  WriteLn(' + #39 + '=== ' + Norm + ' ABI service test ===' + #39 + ');');
  Result.Add('  if not Start_Service_Test then');
  Result.Add('  begin');
  Result.Add('    WriteLn(' + #39 + '[FATAL] Start_Service_Test failed' + #39 + ');');
  Result.Add('    Exit;');
  Result.Add('  end;');
  Result.Add('  WriteLn(' + #39 + '[OK] Service ready on ipc:' + #39 + ' + DEFAULT_APP_NAME);');
  Result.Add('  WriteLn(' + #39 + '[OK] Connect from any client (Pascal/C++/Python/...) and run the call test' + #39 + ');');
  Result.Add('  WriteLn(' + #39 + '[OK] Press Enter to shut down' + #39 + ');');
  Result.Add('  try');
  Result.Add('    ReadLn;');
  Result.Add('  except');
  Result.Add('  end;');
  Result.Add('  Stop_Service_Test;');
  Result.Add('  WriteLn(' + #39 + '[OK] Shutdown complete' + #39 + ');');
  Result.Add('end;');
  Result.Add('');
  Result.Add('end.');
end;

function GenerateABICallTestPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  Norm, TargetApp, TargetP2P: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  UsedApiNames: TPascalStringList;
  i, j: Integer;
  ApiName: TP_String;
  F: TFunctionStructure;
  RetType, VarName, DescStr: TP_String;
  HasLF_Binary_DataParam, HasAsync: Boolean;
  WaiterCls: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  if Model.UnitName.Len = 0 then Exit;

  Norm := MakeApiName(Model.UnitName);
  TargetApp := Norm + '_abi';
  TargetP2P := Norm + '_service_test_p2p';
  SupportedFuncs := CollectSupportedFunctions(Model);

  Result := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  try
    Result.Add('unit ' + Norm + '_abi_call_test_unit;');
    Result.Add('');
    Result.Add('{$ifdef FPC}');
    Result.Add('  {$mode delphi}{$H+}');
    Result.Add('  {$MODESWITCH NestedProcVars}');
    Result.Add('  {$CODEPAGE UTF8}');
    Result.Add('{$endif}');
    Result.Add('{$R-}{$I-}{$Q-}{$B-}');
    Result.Add('');
    Result.Add('interface');
    Result.Add('');
    Result.Add('uses');
    Result.Add('  SysUtils, Classes, SyncObjs,');
    Result.Add('  lingofuse_import,');
    Result.Add('  abi_wire_unit,');
    Result.Add('  ' + Norm + '_abi_call_unit;');
    Result.Add('');
    Result.Add('const');
    Result.Add('  CLI_TEST_REPORT_API = ' + #39 + 'LF_TEST_REPORT_SERVICE_IDENTITY' + #39 + ';');
    Result.Add('  CLI_TEST_WHOAMI_API = ' + #39 + 'LF_TEST_WHOAMI' + #39 + ';');
    Result.Add('  CLI_TEST_ASK_CALL_ME_API = ' + #39 + 'LF_TEST_ASK_SERVICE_CALL_ME' + #39 + ';');
    Result.Add('  CLI_TEST_TARGET_APP = ' + #39 + TargetApp + #39 + ';');
    Result.Add('  CLI_TEST_TARGET_P2P = ' + #39 + TargetP2P + #39 + ';');
    Result.Add('  CLI_TEST_TIMEOUT_MS = 5000;');
    Result.Add('');
    Result.Add('type');
    Result.Add('  TAnyWaiter = class');
    Result.Add('  public');
    Result.Add('    Done: TEvent;');
    Result.Add('    OK: Boolean;');
    Result.Add('    ErrMsg: string;');
    Result.Add('    ValueStr: string;');
    Result.Add('    constructor Create;');
    Result.Add('    destructor Destroy; override;');
    Result.Add('  end;');
    Result.Add('');

    EmitAllWaiterClasses(Result);

    Result.Add('procedure Report_Pass(const L: string; const V: string = ' + #39#39 + ');');
    Result.Add('procedure Report_Fail(const L, R: string);');
    Result.Add('procedure Report_Skip(const L, R: string);');
    Result.Add('function Get_Pass_Count: Integer;');
    Result.Add('function Get_Fail_Count: Integer;');
    Result.Add('function Get_Skip_Count: Integer;');
    Result.Add('');
    Result.Add('function Start_Call_Test: Boolean;');
    Result.Add('procedure Stop_Call_Test;');
    Result.Add('function Is_Call_Running: Boolean;');
    Result.Add('');
    Result.Add('function Probe_Client_Identity: Boolean;');
    Result.Add('function Probe_Service_UID: Boolean;');
    Result.Add('procedure Wait_Until_Service_Ready(const MaxMillisec: Integer);');
    Result.Add('');
    Result.Add('procedure Run_All_Tests;');
    Result.Add('procedure Run_Call_Test_Main;');
    Result.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      Result.Add('procedure Test_' + ApiName + ';');
    end;
    Result.Add('');
    Result.Add('implementation');
    Result.Add('');
    Result.Add('var');
    Result.Add('  G_App: TAppHnd___ = nil;');
    Result.Add('  G_Running: Boolean = False;');
    Result.Add('  G_ServiceUID: TP2P_UID___;');
    Result.Add('  G_ServiceP2PName: string;');
    Result.Add('  G_HasServiceUID: Boolean = False;');
    Result.Add('  G_ServiceCalledMe: Boolean = False;');
    Result.Add('  G_Lock: TCriticalSection = nil;');
    Result.Add('  G_Pass, G_Fail, G_Skip: Integer;');
    Result.Add('  G_OrphanedWaiters: TList = nil;');
    Result.Add('');
    Result.Add('constructor TAnyWaiter.Create;');
    Result.Add('begin');
    Result.Add('  inherited;');
    Result.Add('  Done := TEvent.Create(nil, True, False, ' + #39#39 + ');');
    Result.Add('end;');
    Result.Add('');
    Result.Add('destructor TAnyWaiter.Destroy;');
    Result.Add('begin');
    Result.Add('  Done.Free;');
    Result.Add('  inherited;');
    Result.Add('end;');
    Result.Add('');

    EmitAllWaiterImpls(Result);

    Result.Add('procedure Report_Pass(const L: string; const V: string = ' + #39#39 + ');');
    Result.Add('begin');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    Inc(G_Pass);');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('  if V <> ' + #39#39 + ' then');
    Result.Add('    WriteLn(' + #39 + '[PASS] ' + #39 + ' + L + ' + #39 + ' = ' + #39 + ' + V)');
    Result.Add('  else');
    Result.Add('    WriteLn(' + #39 + '[PASS] ' + #39 + ' + L);');
    Result.Add('end;');
    Result.Add('');
    Result.Add('procedure Report_Fail(const L, R: string);');
    Result.Add('begin');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    Inc(G_Fail);');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('  WriteLn(' + #39 + '[FAIL] ' + #39 + ' + L + ' + #39 + ' -- ' + #39 + ' + R);');
    Result.Add('end;');
    Result.Add('');
    Result.Add('procedure Report_Skip(const L, R: string);');
    Result.Add('begin');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    Inc(G_Skip);');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('  WriteLn(' + #39 + '[SKIP] ' + #39 + ' + L + ' + #39 + ' -- ' + #39 + ' + R);');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Get_Pass_Count: Integer;');
    Result.Add('begin');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    Result := G_Pass;');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Get_Fail_Count: Integer;');
    Result.Add('begin');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    Result := G_Fail;');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Get_Skip_Count: Integer;');
    Result.Add('begin');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    Result := G_Skip;');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('procedure Cli_CB_ReportIdentity(_T: Pointer; _In, _Out: TDataHnd___); cdecl;');
    Result.Add('var');
    Result.Add('  uid: TP2P_UID___;');
    Result.Add('  uidPtr: PP2P_UID___;');
    Result.Add('  p2p, msg: string;');
    Result.Add('begin');
    Result.Add('  FillChar(uid, SizeOf(uid), 0);');
    Result.Add('  uidPtr := LF_Get_P2P_UID(_In);');
    Result.Add('  if uidPtr <> nil then uid := uidPtr^;');
    Result.Add('  p2p := LF_Get_P2P_NameEx(_In);');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    G_ServiceUID := uid;');
    Result.Add('    G_ServiceP2PName := p2p;');
    Result.Add('    G_HasServiceUID := True;');
    Result.Add('    G_ServiceCalledMe := True;');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('  LF_SetPos(_In, 0);');
    Result.Add('  LF_ReadString(_In, msg);');
    Result.Add('  if not LF_WriteUInt8(_Out, 0) then Exit;');
    Result.Add('  LF_WriteString(_Out, ' + #39 + 'identity received' + #39 + ');');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Start_Call_Test: Boolean;');
    Result.Add('var');
    Result.Add('  EP: string;');
    Result.Add('begin');
    Result.Add('  Result := False;');
    Result.Add('  if G_Running then Exit;');
    Result.Add('  EP := ' + #39 + 'ipc:' + #39 + ' + CLI_TEST_TARGET_APP;');
    Result.Add('');
    Result.Add('  G_Pass := 0;');
    Result.Add('  G_Fail := 0;');
    Result.Add('  G_Skip := 0;');
    Result.Add('  G_HasServiceUID := False;');
    Result.Add('  G_ServiceCalledMe := False;');
    Result.Add('');
    Result.Add('  LF_ResetPrepare;');
    Result.Add('  LF_Set_Opt_Quiet(True);');
    Result.Add('  LF_Set_Opt_ConsoleOutput(True);');
    Result.Add('  LF_Set_Opt_Wait_Connection_ReadyOk(True);');
    Result.Add('  LF_Set_Opt_Wait_Connection_Timeout(15000);');
    Result.Add('');
    Result.Add('  G_App := LF_CreateAppEx(' + #39 + Norm + '_abi_test_client' + #39 + ', ' + #39 + 'client test app' + #39 + ');');
    Result.Add('  if G_App = nil then');
    Result.Add('  begin');
    Result.Add('    LF_Shutdown;');
    Result.Add('    Exit;');
    Result.Add('  end;');
    Result.Add('');
    Result.Add('  LF_RegisterCallEx(G_App, CLI_TEST_REPORT_API, ' + #39 + 'client report identity' + #39 + ', nil, @Cli_CB_ReportIdentity);');
    Result.Add('');
    Result.Add('  if LF_PrepareClientEx(EP, G_App) = -1 then');
    Result.Add('  begin');
    Result.Add('    LF_FreeApp(G_App);');
    Result.Add('    G_App := nil;');
    Result.Add('    LF_Shutdown;');
    Result.Add('    Exit;');
    Result.Add('  end;');
    Result.Add('');
    Result.Add('  if LF_PrepareDone <> 1 then');
    Result.Add('  begin');
    Result.Add('    LF_FreeApp(G_App);');
    Result.Add('    G_App := nil;');
    Result.Add('    LF_Shutdown;');
    Result.Add('    Exit;');
    Result.Add('  end;');
    Result.Add('');
    Result.Add('  G_Running := True;');
    Result.Add('  Result := True;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('procedure Stop_Call_Test;');
    Result.Add('begin');
    Result.Add('  if not G_Running then Exit;');
    Result.Add('  G_Running := False;');
    Result.Add('  if G_App <> nil then');
    Result.Add('  begin');
    Result.Add('    LF_FreeApp(G_App);');
    Result.Add('    G_App := nil;');
    Result.Add('  end;');
    Result.Add('  LF_Shutdown;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Is_Call_Running: Boolean;');
    Result.Add('begin');
    Result.Add('  Result := G_Running;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('procedure Wait_Until_Service_Ready(const MaxMillisec: Integer);');
    Result.Add('var');
    Result.Add('  StartTK: Cardinal;');
    Result.Add('  Req, Res: TDataHnd___;');
    Result.Add('  sz: Int64;');
    Result.Add('begin');
    Result.Add('  StartTK := TThread.GetTickCount;');
    Result.Add('  while (TThread.GetTickCount - StartTK) < Cardinal(MaxMillisec) do');
    Result.Add('  begin');
    Result.Add('    Req := LF_CreateDataEx(CLI_TEST_WHOAMI_API);');
    Result.Add('    if Req <> nil then');
    Result.Add('    begin');
    Result.Add('      try');
    Result.Add('        Res := LF_CallEx(CLI_TEST_TARGET_APP, Req, 500);');
    Result.Add('        if Res <> nil then');
    Result.Add('        begin');
    Result.Add('          try');
    Result.Add('            sz := LF_GetSize(Res);');
    Result.Add('            if sz >= 33 then Exit;');
    Result.Add('          finally');
    Result.Add('            LF_FreeData(Res);');
    Result.Add('          end;');
    Result.Add('        end;');
    Result.Add('      finally');
    Result.Add('        LF_FreeData(Req);');
    Result.Add('      end;');
    Result.Add('    end;');
    Result.Add('    Sleep(100);');
    Result.Add('  end;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Probe_Client_Identity: Boolean;');
    Result.Add('var');
    Result.Add('  req, res: TDataHnd___;');
    Result.Add('  status: UInt8;');
    Result.Add('  uid: TP2P_UID___;');
    Result.Add('  p2p, uidHex: string;');
    Result.Add('  i: Integer;');
    Result.Add('begin');
    Result.Add('  Result := False;');
    Result.Add('  req := LF_CreateDataEx(CLI_TEST_WHOAMI_API);');
    Result.Add('  if req = nil then Exit;');
    Result.Add('  try');
    Result.Add('    res := LF_CallEx(CLI_TEST_TARGET_APP, req, CLI_TEST_TIMEOUT_MS);');
    Result.Add('    if res = nil then Exit;');
    Result.Add('    try');
    Result.Add('      if LF_GetSize(res) < 33 then Exit;');
    Result.Add('      LF_SetPos(res, 0);');
    Result.Add('      if not LF_ReadUInt8(res, status) then Exit;');
    Result.Add('      if status <> 0 then Exit;');
    Result.Add('      if LF_ReadBuffer(res, @uid[0], 32) <> 32 then Exit;');
    Result.Add('      if not LF_ReadString(res, p2p) then Exit;');
    Result.Add('      uidHex := ' + #39#39 + ';');
    Result.Add('      for i := 0 to 31 do');
    Result.Add('        uidHex := uidHex + IntToHex(uid[i], 2);');
    Result.Add('      WriteLn(' + #39 + '[INFO] client UID = ' + #39 + ' + uidHex);');
    Result.Add('      WriteLn(' + #39 + '[INFO] client P2P = ' + #39 + ' + p2p);');
    Result.Add('      Result := True;');
    Result.Add('    finally');
    Result.Add('      LF_FreeData(res);');
    Result.Add('    end;');
    Result.Add('  finally');
    Result.Add('    LF_FreeData(req);');
    Result.Add('  end;');
    Result.Add('end;');
    Result.Add('');
    Result.Add('function Probe_Service_UID: Boolean;');
    Result.Add('var');
    Result.Add('  req: TDataHnd___;');
    Result.Add('  tk: Cardinal;');
    Result.Add('begin');
    Result.Add('  Result := False;');
    Result.Add('  G_Lock.Enter;');
    Result.Add('  try');
    Result.Add('    if G_HasServiceUID then');
    Result.Add('    begin');
    Result.Add('      Result := True;');
    Result.Add('      Exit;');
    Result.Add('    end;');
    Result.Add('  finally');
    Result.Add('    G_Lock.Leave;');
    Result.Add('  end;');
    Result.Add('  req := LF_CreateDataEx(CLI_TEST_ASK_CALL_ME_API);');
    Result.Add('  if req = nil then Exit;');
    Result.Add('  try');
    Result.Add('    LF_WriteString(req, CLI_TEST_REPORT_API);');
    Result.Add('    LF_NotifyEx(CLI_TEST_TARGET_APP, req);');
    Result.Add('  finally');
    Result.Add('    LF_FreeData(req);');
    Result.Add('  end;');
    Result.Add('  tk := TThread.GetTickCount;');
    Result.Add('  while (TThread.GetTickCount - tk) < 10000 do');
    Result.Add('  begin');
    Result.Add('    G_Lock.Enter;');
    Result.Add('    try');
    Result.Add('      if G_HasServiceUID then');
    Result.Add('      begin');
    Result.Add('        Result := True;');
    Result.Add('        Break;');
    Result.Add('      end;');
    Result.Add('    finally');
    Result.Add('      G_Lock.Leave;');
    Result.Add('    end;');
    Result.Add('    Sleep(10);');
    Result.Add('  end;');
    Result.Add('end;');
    Result.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      HasLF_Binary_DataParam := False;
      for j := 0 to High(F.Params) do
        if ABI_Type_Is_LF_Binary_Data(F.Params[j].PascalType) then
          HasLF_Binary_DataParam := True;
      HasAsync := F.IsFunction and HasWaiterSupport(F.ReturnType);
      WaiterCls := '';
      if HasAsync then
        WaiterCls := WaiterClassName(F.ReturnType);

      Result.Add('procedure Test_' + ApiName + ';');
      if F.IsFunction or (Length(F.Params) > 0) or HasAsync then
      begin
        Result.Add('var');
        if F.IsFunction then
          Result.Add('  _r: ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';');
        for j := 0 to High(F.Params) do
        begin
          VarName := '_a' + umlIntToStr(j);
          Result.Add('  ' + VarName + ': ' + ABI_Type_To_Pascal_Decl(F.Params[j].PascalType) + ';');
        end;
        if HasAsync then
        begin
          Result.Add('  _w: ' + WaiterCls + ';');
          Result.Add('  _wOwned: Boolean;');
        end;
      end;
      Result.Add('begin');
      for j := 0 to High(F.Params) do
      begin
        VarName := '_a' + umlIntToStr(j);
        Result.Add('  ' + VarName + ' := ' + PlaceholderValue(F.Params[j].PascalType, j) + ';');
      end;
      if HasLF_Binary_DataParam then
        Result.Add('  try');

      DescStr := #39 + ApiName + '(app call)' + #39;

      if F.IsFunction then
      begin
        RetType := F.ReturnType;
        if ABI_Type_Is_LF_Binary_Data(RetType) then
          Result.Add('    _r := nil;');
        Result.Add('    try');
        Result.Add('      _r := ' + ApiName + '(CLI_TEST_TARGET_APP');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
          Result.Add('      Report_Pass(' + DescStr + ', LF_Binary_Data_ToStr(_r));')
        else if IsStringABIType(RetType) then
          Result.Add('      Report_Pass(' + DescStr + ', _r);')
        else
          Result.Add('      Report_Pass(' + DescStr + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + DescStr + ', E.Message);');
        Result.Add('    end;');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
        begin
          Result.Add('    if _r <> nil then FreeLF_Binary_Data(_r);');
          Result.Add('    _r := nil;');
        end;

        if HasAsync then
        begin
          Result.Add('');
          Result.Add('    _w := ' + WaiterCls + '.Create;');
          Result.Add('    _wOwned := True;');
          Result.Add('    try');
          Result.Add('      if not ' + ApiName + '_Async(CLI_TEST_TARGET_APP');
          for j := 0 to High(F.Params) do
            Result.Add('        , _a' + umlIntToStr(j));
          Result.Add('        , _w.OnSucc, _w.OnErr) then');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(app async)' + #39 + ', ' + #39 + 'dispatch failed' + #39 + ')');
          Result.Add('      else if _w.Done.WaitFor(CLI_TEST_TIMEOUT_MS) <> wrSignaled then');
          Result.Add('      begin');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(app async)' + #39 + ', ' + #39 + 'timeout' + #39 + ');');
          Result.Add('        G_Lock.Enter;');
          Result.Add('        try');
          Result.Add('          G_OrphanedWaiters.Add(_w);');
          Result.Add('          _wOwned := False;');
          Result.Add('        finally');
          Result.Add('          G_Lock.Leave;');
          Result.Add('        end;');
          Result.Add('      end');
          Result.Add('      else if not _w.OK then');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(app async)' + #39 + ', _w.ErrMsg)');
          Result.Add('      else');
          Result.Add('        Report_Pass(' + #39 + ApiName + '(app async)' + #39 + ', _w.ValueStr);');
          Result.Add('    finally');
          Result.Add('      if _wOwned then _w.Free;');
          Result.Add('    end;');
          Result.Add('');
          Result.Add('    _w := ' + WaiterCls + '.Create;');
          Result.Add('    _wOwned := True;');
          Result.Add('    try');
          Result.Add('      if not ' + ApiName + '_AsyncSequenced(CLI_TEST_TARGET_APP');
          for j := 0 to High(F.Params) do
            Result.Add('        , _a' + umlIntToStr(j));
          Result.Add('        , _w.OnSucc, _w.OnErr) then');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(app asyncSeq)' + #39 + ', ' + #39 + 'dispatch failed' + #39 + ')');
          Result.Add('      else if _w.Done.WaitFor(CLI_TEST_TIMEOUT_MS) <> wrSignaled then');
          Result.Add('      begin');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(app asyncSeq)' + #39 + ', ' + #39 + 'timeout' + #39 + ');');
          Result.Add('        G_Lock.Enter;');
          Result.Add('        try');
          Result.Add('          G_OrphanedWaiters.Add(_w);');
          Result.Add('          _wOwned := False;');
          Result.Add('        finally');
          Result.Add('          G_Lock.Leave;');
          Result.Add('        end;');
          Result.Add('      end');
          Result.Add('      else if not _w.OK then');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(app asyncSeq)' + #39 + ', _w.ErrMsg)');
          Result.Add('      else');
          Result.Add('        Report_Pass(' + #39 + ApiName + '(app asyncSeq)' + #39 + ', _w.ValueStr);');
          Result.Add('    finally');
          Result.Add('      if _wOwned then _w.Free;');
          Result.Add('    end;');
        end;

        Result.Add('');
        Result.Add('    if G_HasServiceUID then');
        Result.Add('    begin');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
          Result.Add('      _r := nil;');
        Result.Add('      try');
        Result.Add('        _r := ' + ApiName + '_UID_Call(G_ServiceUID');
        for j := 0 to High(F.Params) do
          Result.Add('          , _a' + umlIntToStr(j));
        Result.Add('        );');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
          Result.Add('        Report_Pass(' + #39 + ApiName + '(uid call)' + #39 + ', LF_Binary_Data_ToStr(_r));')
        else if IsStringABIType(RetType) then
          Result.Add('        Report_Pass(' + #39 + ApiName + '(uid call)' + #39 + ', _r);')
        else
          Result.Add('        Report_Pass(' + #39 + ApiName + '(uid call)' + #39 + ');');
        Result.Add('      except');
        Result.Add('        on E: Exception do Report_Fail(' + #39 + ApiName + '(uid call)' + #39 + ', E.Message);');
        Result.Add('      end;');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
        begin
          Result.Add('      if _r <> nil then FreeLF_Binary_Data(_r);');
          Result.Add('      _r := nil;');
        end;
        if HasAsync then
        begin
          Result.Add('      _w := ' + WaiterCls + '.Create;');
          Result.Add('      _wOwned := True;');
          Result.Add('      try');
          Result.Add('        if not ' + ApiName + '_UID_Async(G_ServiceUID');
          for j := 0 to High(F.Params) do
            Result.Add('          , _a' + umlIntToStr(j));
          Result.Add('          , _w.OnSucc, _w.OnErr) then');
          Result.Add('          Report_Fail(' + #39 + ApiName + '(uid async)' + #39 + ', ' + #39 + 'dispatch failed' + #39 + ')');
          Result.Add('        else if _w.Done.WaitFor(CLI_TEST_TIMEOUT_MS) <> wrSignaled then');
          Result.Add('        begin');
          Result.Add('          Report_Fail(' + #39 + ApiName + '(uid async)' + #39 + ', ' + #39 + 'timeout' + #39 + ');');
          Result.Add('          G_Lock.Enter;');
          Result.Add('          try');
          Result.Add('            G_OrphanedWaiters.Add(_w);');
          Result.Add('            _wOwned := False;');
          Result.Add('          finally');
          Result.Add('            G_Lock.Leave;');
          Result.Add('          end;');
          Result.Add('        end');
          Result.Add('        else if not _w.OK then');
          Result.Add('          Report_Fail(' + #39 + ApiName + '(uid async)' + #39 + ', _w.ErrMsg)');
          Result.Add('        else');
          Result.Add('          Report_Pass(' + #39 + ApiName + '(uid async)' + #39 + ', _w.ValueStr);');
          Result.Add('      finally');
          Result.Add('        if _wOwned then _w.Free;');
          Result.Add('      end;');
        end;
        Result.Add('    end')
        ;
        Result.Add('    else');
        Result.Add('      Report_Skip(' + #39 + ApiName + '(uid)' + #39 + ', ' + #39 + 'no service UID' + #39 + ');');
        Result.Add('');

        if ABI_Type_Is_LF_Binary_Data(RetType) then
          Result.Add('    _r := nil;');
        Result.Add('    try');
        Result.Add('      _r := ' + ApiName + '_P2PName_Call(CLI_TEST_TARGET_P2P');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
          Result.Add('      Report_Pass(' + #39 + ApiName + '(p2pname call)' + #39 + ', LF_Binary_Data_ToStr(_r));')
        else if IsStringABIType(RetType) then
          Result.Add('      Report_Pass(' + #39 + ApiName + '(p2pname call)' + #39 + ', _r);')
        else
          Result.Add('      Report_Pass(' + #39 + ApiName + '(p2pname call)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(p2pname call)' + #39 + ', E.Message);');
        Result.Add('    end;');
        if ABI_Type_Is_LF_Binary_Data(RetType) then
        begin
          Result.Add('    if _r <> nil then FreeLF_Binary_Data(_r);');
          Result.Add('    _r := nil;');
        end;
        if HasAsync then
        begin
          Result.Add('    _w := ' + WaiterCls + '.Create;');
          Result.Add('    _wOwned := True;');
          Result.Add('    try');
          Result.Add('      if not ' + ApiName + '_P2PName_Async(CLI_TEST_TARGET_P2P');
          for j := 0 to High(F.Params) do
            Result.Add('        , _a' + umlIntToStr(j));
          Result.Add('        , _w.OnSucc, _w.OnErr) then');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(p2pname async)' + #39 + ', ' + #39 + 'dispatch failed' + #39 + ')');
          Result.Add('      else if _w.Done.WaitFor(CLI_TEST_TIMEOUT_MS) <> wrSignaled then');
          Result.Add('      begin');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(p2pname async)' + #39 + ', ' + #39 + 'timeout' + #39 + ');');
          Result.Add('        G_Lock.Enter;');
          Result.Add('        try');
          Result.Add('          G_OrphanedWaiters.Add(_w);');
          Result.Add('          _wOwned := False;');
          Result.Add('        finally');
          Result.Add('          G_Lock.Leave;');
          Result.Add('        end;');
          Result.Add('      end');
          Result.Add('      else if not _w.OK then');
          Result.Add('        Report_Fail(' + #39 + ApiName + '(p2pname async)' + #39 + ', _w.ErrMsg)');
          Result.Add('      else');
          Result.Add('        Report_Pass(' + #39 + ApiName + '(p2pname async)' + #39 + ', _w.ValueStr);');
          Result.Add('    finally');
          Result.Add('      if _wOwned then _w.Free;');
          Result.Add('    end;');
        end;
      end
      else
      begin
        Result.Add('    try');
        Result.Add('      ' + ApiName + '(CLI_TEST_TARGET_APP');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        Result.Add('      Report_Pass(' + #39 + ApiName + '(app notify)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(app notify)' + #39 + ', E.Message);');
        Result.Add('    end;');
        Result.Add('');
        Result.Add('    try');
        Result.Add('      ' + ApiName + '_SequencedNotify(CLI_TEST_TARGET_APP');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        Result.Add('      Report_Pass(' + #39 + ApiName + '(app seq notify)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(app seq notify)' + #39 + ', E.Message);');
        Result.Add('    end;');
        Result.Add('');
        Result.Add('    if G_HasServiceUID then');
        Result.Add('    try');
        Result.Add('      ' + ApiName + '_UID_Notify(G_ServiceUID');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        Result.Add('      Report_Pass(' + #39 + ApiName + '(uid notify)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(uid notify)' + #39 + ', E.Message);');
        Result.Add('    end');
        Result.Add('    else');
        Result.Add('      Report_Skip(' + #39 + ApiName + '(uid notify)' + #39 + ', ' + #39 + 'no service UID' + #39 + ');');
        Result.Add('');
        Result.Add('    if G_HasServiceUID then');
        Result.Add('    try');
        Result.Add('      ' + ApiName + '_UID_SequencedNotify(G_ServiceUID');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        Result.Add('      Report_Pass(' + #39 + ApiName + '(uid seq notify)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(uid seq notify)' + #39 + ', E.Message);');
        Result.Add('    end');
        Result.Add('    else');
        Result.Add('      Report_Skip(' + #39 + ApiName + '(uid seq notify)' + #39 + ', ' + #39 + 'no service UID' + #39 + ');');
        Result.Add('');
        Result.Add('    try');
        Result.Add('      ' + ApiName + '_P2PName_Notify(CLI_TEST_TARGET_P2P');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        Result.Add('      Report_Pass(' + #39 + ApiName + '(p2pname notify)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(p2pname notify)' + #39 + ', E.Message);');
        Result.Add('    end;');
        Result.Add('');
        Result.Add('    try');
        Result.Add('      ' + ApiName + '_P2PName_SequencedNotify(CLI_TEST_TARGET_P2P');
        for j := 0 to High(F.Params) do
          Result.Add('        , _a' + umlIntToStr(j));
        Result.Add('      );');
        Result.Add('      Report_Pass(' + #39 + ApiName + '(p2pname seq notify)' + #39 + ');');
        Result.Add('    except');
        Result.Add('      on E: Exception do Report_Fail(' + #39 + ApiName + '(p2pname seq notify)' + #39 + ', E.Message);');
        Result.Add('    end;');
      end;

      if HasLF_Binary_DataParam then
      begin
        Result.Add('  finally');
        for j := 0 to High(F.Params) do
          if ABI_Type_Is_LF_Binary_Data(F.Params[j].PascalType) then
          begin
            VarName := '_a' + umlIntToStr(j);
            Result.Add('    if ' + VarName + ' <> nil then FreeLF_Binary_Data(' + VarName + ');');
          end;
        Result.Add('  end;');
      end;
      Result.Add('end;');
      Result.Add('');
    end;

    Result.Add('procedure Run_All_Tests;');
    Result.Add('begin');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      Result.Add('  Test_' + ApiName + ';');
    end;
    Result.Add('  WriteLn(' + #39 + '=== Summary ===' + #39 + ');');
    Result.Add('  WriteLn(' + #39 + 'Pass: ' + #39 + ', Get_Pass_Count);');
    Result.Add('  WriteLn(' + #39 + 'Fail: ' + #39 + ', Get_Fail_Count);');
    Result.Add('  WriteLn(' + #39 + 'Skip: ' + #39 + ', Get_Skip_Count);');
    Result.Add('end;');
    Result.Add('');
    Result.Add('procedure Run_Call_Test_Main;');
    Result.Add('begin');
    Result.Add('  WriteLn(' + #39 + '=== ' + Norm + ' ABI call test ===' + #39 + ');');
    Result.Add('  if not Start_Call_Test then');
    Result.Add('  begin');
    Result.Add('    WriteLn(' + #39 + '[FATAL] Start_Call_Test failed' + #39 + ');');
    Result.Add('    Exit;');
    Result.Add('  end;');
    Result.Add('  try');
    Result.Add('    WriteLn(' + #39 + '[READY] Client online' + #39 + ');');
    Result.Add('    WriteLn(' + #39 + '[INFO] Waiting for service API broadcast...' + #39 + ');');
    Result.Add('    Wait_Until_Service_Ready(5000);');
    Result.Add('    WriteLn(' + #39#39 + ');');
    Result.Add('    if Probe_Client_Identity then');
    Result.Add('      WriteLn(' + #39 + '[OK] client identity probe' + #39 + ')');
    Result.Add('    else');
    Result.Add('      WriteLn(' + #39 + '[WARN] whoami failed, UID tests will be skipped' + #39 + ');');
    Result.Add('    if Probe_Service_UID then');
    Result.Add('      WriteLn(' + #39 + '[OK] service-initiated call ready' + #39 + ')');
    Result.Add('    else');
    Result.Add('      WriteLn(' + #39 + '[WARN] service UID not available, UID tests will be skipped' + #39 + ');');
    Result.Add('    WriteLn(' + #39#39 + ');');
    Result.Add('    Run_All_Tests;');
    Result.Add('  finally');
    Result.Add('    Stop_Call_Test;');
    Result.Add('  end;');
    Result.Add('  WriteLn(' + #39 + '[OK] Call test complete' + #39 + ');');
    Result.Add('end;');
    Result.Add('');
    Result.Add('initialization');
    Result.Add('  G_Lock := TCriticalSection.Create;');
    Result.Add('  G_OrphanedWaiters := TList.Create;');
    Result.Add('');
    Result.Add('finalization');
    Result.Add('  if G_OrphanedWaiters <> nil then');
    Result.Add('  begin');
    Result.Add('    while G_OrphanedWaiters.Count > 0 do');
    Result.Add('    begin');
    Result.Add('      TAnyWaiter(G_OrphanedWaiters[0]).Free;');
    Result.Add('      G_OrphanedWaiters.Delete(0);');
    Result.Add('    end;');
    Result.Add('    G_OrphanedWaiters.Free;');
    Result.Add('    G_OrphanedWaiters := nil;');
    Result.Add('  end;');
    Result.Add('  if G_Lock <> nil then');
    Result.Add('  begin');
    Result.Add('    G_Lock.Free;');
    Result.Add('    G_Lock := nil;');
    Result.Add('  end;');
    Result.Add('');
    Result.Add('end.');
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator('pascal', 'xxx_abi_service_test_unit.pas', gkTest,
    'Pascal ABI service test unit', @GenerateABIServiceTestPascalCode);

  RegisterGenerator('pascal', 'xxx_abi_call_test_unit.pas', gkTest,
    'Pascal ABI call test unit', @GenerateABICallTestPascalCode);

end.
