unit pas_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
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

function PascalStrLit(const S: SystemString): TP_String;
var
  i: integer;
  c: SystemChar;
  Current, OutStr: string;
  NeedBreak: Boolean;
begin
  Current := ''; OutStr := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    NeedBreak := (Ord(c) < 32) or (c = #39) or (Ord(c) > 126);
    if NeedBreak then
    begin
      if Current <> '' then
      begin
        if OutStr <> '' then OutStr := OutStr + ' + ';
        OutStr := OutStr + #39 + Current + #39;
        Current := '';
      end;
      if OutStr <> '' then OutStr := OutStr + ' + ';
      if c = #39 then OutStr := OutStr + #39#39
      else OutStr := OutStr + '#' + umlIntToStr(Ord(c)).Text;
    end
    else Current := Current + c;
  end;
  if Current <> '' then
  begin
    if OutStr <> '' then OutStr := OutStr + ' + ';
    OutStr := OutStr + #39 + Current + #39;
  end;
  if OutStr = '' then OutStr := #39#39;
  Result := OutStr;
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
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar') then Result := 'string'
  else Result := '';
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_ReadInt32'
  else if T.Same('int64') then Result := 'LF_ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'LF_ReadUInt32'
  else if T.Same('word') then Result := 'LF_ReadUInt16'
  else if T.Same('smallint') then Result := 'LF_ReadInt16'
  else if T.Same('byte') then Result := 'LF_ReadUInt8'
  else if T.Same('uint64') then Result := 'LF_ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'LF_ReadDouble'
  else if T.Same('single') then Result := 'LF_ReadSingle'
  else if IsStringABIType(T) then Result := 'LF_ReadString'
  else Result := '';
end;

function ABI_Type_To_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_WriteInt32'
  else if T.Same('int64') then Result := 'LF_WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'LF_WriteUInt32'
  else if T.Same('word') then Result := 'LF_WriteUInt16'
  else if T.Same('smallint') then Result := 'LF_WriteInt16'
  else if T.Same('byte') then Result := 'LF_WriteUInt8'
  else if T.Same('uint64') then Result := 'LF_WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'LF_WriteDouble'
  else if T.Same('single') then Result := 'LF_WriteSingle'
  else if IsStringABIType(T) then Result := 'LF_WriteString'
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

function PlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then Result := PascalStrLit('test')
  else if ABIType.Same('double') or ABIType.Same('single') or
    ABIType.Same('extended') or ABIType.Same('real') then Result := '3.14'
  else if ABIType.Same('int64') then Result := 'Int64(42)'
  else if ABIType.Same('uint64') then Result := 'UInt64(42)'
  else Result := '42';
end;

function ValueToStrExpr(const ABIType, ValueVar: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then Result := ValueVar
  else if ABIType.Same('double') or ABIType.Same('single') or
    ABIType.Same('extended') or ABIType.Same('real') then
    Result := 'FloatToStr(' + ValueVar + ')'
  else Result := 'IntToStr(' + ValueVar + ')';
end;

function StripCommentMarkers(const Line: TP_String): TP_String;
var T: TP_String;
begin
  T := Line.TrimChar(#32#9);
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  if T.Len > 0 then
  begin
    if T[1] = '{' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;
  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then T := T.GetString(1, T.Len).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then
      T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
  end;
  Result := T;
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var i, j: integer; Line: TP_String;
begin
  Result := ''; if Comment.Len = 0 then Exit;
  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do Inc(j);
    if j > i then
    begin
      Line := StripCommentMarkers(Comment.GetString(i, j));
      if Line.Len > 0 then
      begin
        if Line[1] <> '@' then
        begin
          if Line[1] = '*' then Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if Line.Len > 0 then
          begin
            Result := Line;
            if Result.Len > 200 then Result := Result.GetString(1, 201);
            Exit;
          end;
        end;
      end;
    end;
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do Inc(i);
  end;
end;

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var i, j: integer; f: TFunctionStructure; Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i]; Supported := True;
    for j := 0 to High(f.Params) do
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin Supported := False; Break; end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
      Supported := False;
    if Supported and (f.Name.Len = 0) then Supported := False;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

procedure AssignUniqueApiNames(const Funcs: TArryFunctionStructure; Names: TPascalStringList);
var i, j: integer; N: TP_String;
begin
  Names.Clear;
  for i := 0 to High(Funcs) do
  begin
    N := MakeApiName(Funcs[i].Name);
    if Names.IndexOf(N) >= 0 then
    begin
      j := 1;
      while Names.IndexOf(N + '_' + umlIntToStr(j).Text) >= 0 do Inc(j);
      N := N + '_' + umlIntToStr(j).Text;
    end;
    Names.Add(N);
  end;
end;

function GenerateABIServiceTestPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, P2PName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  Lines := TPascalStringList.Create;
  try
    Lines.Add('unit ' + NormalizedUnit.Text + '_abi_service_test_unit;');
    Lines.Add('');
    Lines.Add('{$ifdef FPC}');
    Lines.Add('  {$mode delphi}{$H+}');
    Lines.Add('  {$MODESWITCH NestedProcVars}');
    Lines.Add('  {$modeswitch advancedrecords}');
    Lines.Add('  {$CODEPAGE UTF8}');
    Lines.Add('{$endif}');
    Lines.Add('{$R-}{$I-}{$Q-}{$B-}');
    Lines.Add('');
    Lines.Add('interface');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  SysUtils, Classes,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  ' + NormalizedUnit.Text + '_abi_service_unit;');
    Lines.Add('');
    Lines.Add('const');
    Lines.Add('  SERVICE_TEST_DEFAULT_ENDPOINT = ' + PascalStrLit('ipc:' + AppName.Text) + ';');
    Lines.Add('  SERVICE_TEST_DEFAULT_APP_NAME = ' + PascalStrLit(AppName.Text) + ';');
    Lines.Add('  SERVICE_TEST_DEFAULT_P2P_NAME = ' + PascalStrLit(P2PName.Text) + ';');
    Lines.Add('  SERVICE_TEST_WHOAMI_API = ' + PascalStrLit('LF_TEST_WHOAMI') + ';');
    Lines.Add('  SERVICE_TEST_ASK_CALL_ME_API = ' + PascalStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
    Lines.Add('');
    Lines.Add('function Start_Service_Test: Boolean;');
    Lines.Add('procedure Stop_Service_Test;');
    Lines.Add('function Is_Service_Test_Running: Boolean;');
    Lines.Add('');
    Lines.Add('implementation');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  G_Running: Boolean = False;');
    Lines.Add('  G_App: TAppHnd___ = nil;');
    Lines.Add('');
    Lines.Add('function Is_Service_Test_Running: Boolean;');
    Lines.Add('begin');
    Lines.Add('  Result := G_Running;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Test_CB_WHOAMI(_Trigger: Pointer; _In_, _Out_: TDataHnd___); cdecl;');
    Lines.Add('var');
    Lines.Add('  _uidPtr: PP2P_UID___;');
    Lines.Add('  _uid_: TP2P_UID___;');
    Lines.Add('  _p2p_: string;');
    Lines.Add('begin');
    Lines.Add('  FillChar(_uid_, SizeOf(_uid_), 0);');
    Lines.Add('  _uidPtr := LF_Get_P2P_UID(_In_);');
    Lines.Add('  if _uidPtr <> nil then _uid_ := _uidPtr^;');
    Lines.Add('  _p2p_ := LF_Get_P2P_NameEx(_In_);');
    Lines.Add('  WriteLn(Format(' + PascalStrLit('[SERVICE] whoami: p2p="%s"') + ', [_p2p_]));');
    Lines.Add('  LF_WriteUInt8(_Out_, $00);');
    Lines.Add('  LF_WriteBuffer(_Out_, @_uid_[0], SizeOf(_uid_));');
    Lines.Add('  LF_WriteString(_Out_, _p2p_);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Test_CB_ASK_SERVICE_CALL_ME(_Trigger: Pointer; _In_: TDataHnd___); cdecl;');
    Lines.Add('var');
    Lines.Add('  _uidPtr: PP2P_UID___;');
    Lines.Add('  _uid_: TP2P_UID___;');
    Lines.Add('  _clientApi: string;');
    Lines.Add('  _data, _res: TDataHnd___;');
    Lines.Add('begin');
    Lines.Add('  FillChar(_uid_, SizeOf(_uid_), 0);');
    Lines.Add('  _uidPtr := LF_Get_P2P_UID(_In_);');
    Lines.Add('  if _uidPtr = nil then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(' + PascalStrLit('[SERVICE] ask_call_me: no UID in input') + ');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('  _uid_ := _uidPtr^;');
    Lines.Add('  _clientApi := ' + PascalStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
    Lines.Add('  WriteLn(Format(' + PascalStrLit('[SERVICE] ask_call_me: calling client API "%s" via UID') + ', [_clientApi]));');
    Lines.Add('  _data := LF_CreateDataEx(_clientApi);');
    Lines.Add('  if _data = nil then Exit;');
    Lines.Add('  try');
    Lines.Add('    LF_WriteString(_data, ' + PascalStrLit('service initiates call') + ');');
    Lines.Add('    _res := LF_UID_Call(_uid_, _data, 5000);');
    Lines.Add('    if _res <> nil then');
    Lines.Add('    begin');
    Lines.Add('      try');
    Lines.Add('        WriteLn(' + PascalStrLit('[SERVICE] ask_call_me: client responded ok') + ');');
    Lines.Add('      finally');
    Lines.Add('        LF_FreeData(_res);');
    Lines.Add('      end;');
    Lines.Add('    end');
    Lines.Add('    else');
    Lines.Add('      WriteLn(' + PascalStrLit('[SERVICE] ask_call_me: UID call returned nil (timeout)') + ');');
    Lines.Add('  finally');
    Lines.Add('    LF_FreeData(_data);');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('function Start_Service_Test: Boolean;');
    Lines.Add('begin');
    Lines.Add('  Result := False;');
    Lines.Add('  if G_Running then Exit;');
    Lines.Add('  LF_ResetPrepare;');
    Lines.Add('  LF_Set_Opt_Quiet(True);');
    Lines.Add('  LF_Set_Opt_ConsoleOutput(True);');
    Lines.Add('  LF_PrepareServiceEx(SERVICE_TEST_DEFAULT_ENDPOINT, SERVICE_TEST_DEFAULT_ENDPOINT);');
    Lines.Add('  G_App := LF_CreateAppEx(SERVICE_TEST_DEFAULT_APP_NAME, SERVICE_TEST_DEFAULT_APP_NAME);');
    Lines.Add('  if G_App = nil then Exit;');
    Lines.Add('  Register_All_ABI_APIs(G_App);');
    Lines.Add('  LF_RegisterCallEx(G_App, SERVICE_TEST_WHOAMI_API, ' +
      PascalStrLit('service-side whoami helper') + ', nil, @Test_CB_WHOAMI);');
    Lines.Add('  LF_RegisterNotifyEx(G_App, SERVICE_TEST_ASK_CALL_ME_API, ' +
      PascalStrLit('ask service to call back client') + ', nil, @Test_CB_ASK_SERVICE_CALL_ME);');
    Lines.Add('  LF_Set_Opt_P2P_Name(SERVICE_TEST_DEFAULT_P2P_NAME);');
    Lines.Add('  Register_All_P2P_ABI_APIs();');
    Lines.Add('  LF_Register_P2P_CallEx(SERVICE_TEST_WHOAMI_API, ' +
      PascalStrLit('service-side whoami helper') + ', nil, @Test_CB_WHOAMI);');
    Lines.Add('  LF_Register_P2P_NotifyEx(SERVICE_TEST_ASK_CALL_ME_API, ' +
      PascalStrLit('ask service to call back client') + ', nil, @Test_CB_ASK_SERVICE_CALL_ME);');
    Lines.Add('  if LF_PrepareClientEx(SERVICE_TEST_DEFAULT_ENDPOINT, G_App) = -1 then');
    Lines.Add('  begin');
    Lines.Add('    LF_FreeApp(G_App); G_App := nil; Exit;');
    Lines.Add('  end;');
    Lines.Add('  if LF_PrepareDone() <> 1 then');
    Lines.Add('  begin');
    Lines.Add('    LF_ExitMainThread;');
    Lines.Add('    LF_FreeApp(G_App); G_App := nil;');
    Lines.Add('    LF_Shutdown; Exit;');
    Lines.Add('  end;');
    Lines.Add('  G_Running := True;');
    Lines.Add('  Result := True;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Stop_Service_Test;');
    Lines.Add('begin');
    Lines.Add('  if not G_Running then Exit;');
    Lines.Add('  G_Running := False;');
    Lines.Add('  LF_ExitMainThread;');
    Lines.Add('  if G_App <> nil then');
    Lines.Add('  begin');
    Lines.Add('    LF_FreeApp(G_App);');
    Lines.Add('    G_App := nil;');
    Lines.Add('  end;');
    Lines.Add('  LF_Shutdown;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('end.');

    Result := Lines;
  finally
  end;
end;

procedure Emit_Waiter_Class(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var RetType, ValExpr: TP_String;
begin
  RetType := ABI_Type_To_Pascal_Decl(F.ReturnType);
  ValExpr := ValueToStrExpr(F.ReturnType, 'V');
  Lines.Add('type');
  Lines.Add('  T' + ApiName + '_Waiter = class(TAnyWaiter)');
  Lines.Add('  public');
  Lines.Add('    procedure OnSuccess(const V: ' + RetType + ');');
  Lines.Add('    procedure OnError(const Msg: string; Code: Integer);');
  Lines.Add('  end;');
  Lines.Add('');
  Lines.Add('procedure T' + ApiName + '_Waiter.OnSuccess(const V: ' + RetType + ');');
  Lines.Add('begin');
  Lines.Add('  Success := True;');
  Lines.Add('  ValueStr := ' + ValExpr + ';');
  Lines.Add('  Event.SetEvent;');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('procedure T' + ApiName + '_Waiter.OnError(const Msg: string; Code: Integer);');
  Lines.Add('begin');
  Lines.Add('  Success := False;');
  Lines.Add('  ErrMsg := Msg;');
  Lines.Add('  Event.SetEvent;');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure Emit_Test_Function(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  ParamType, ValueExpr, ArgList: TP_String;
  HasParam: Boolean;
begin
  HasParam := Length(F.Params) > 0;

  ArgList := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then ArgList := ArgList + ', ';
    ArgList := ArgList + '_a' + umlIntToStr(i).Text;
  end;

  Lines.Add('procedure Test_' + ApiName + ';');
  Lines.Add('var');
  Lines.Add('  _r_: ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';');
  Lines.Add('  _w_: T' + ApiName + '_Waiter;');
  for i := 0 to High(F.Params) do
  begin
    ParamType := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    Lines.Add('  _a' + umlIntToStr(i).Text + ': ' + ParamType + ';');
  end;
  Lines.Add('begin');
  for i := 0 to High(F.Params) do
  begin
    ValueExpr := PlaceholderValue(F.Params[i].PascalType);
    Lines.Add('  _a' + umlIntToStr(i).Text + ' := ' + ValueExpr + ';');
  end;

  Lines.Add('');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    _r_ := ' + ApiName + '(CALL_TEST_DEFAULT_TARGET_APP, ' + ArgList + ');')
  else
    Lines.Add('    _r_ := ' + ApiName + '(CALL_TEST_DEFAULT_TARGET_APP);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(app call)') + ', ' +
    ValueToStrExpr(F.ReturnType, '_r_') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(app call)') + ', E.Message);');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  _w_ := T' + ApiName + '_Waiter.Create;');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(app async)') + ', ' +
      ApiName + '_Async(CALL_TEST_DEFAULT_TARGET_APP, ' + ArgList + ', _w_.OnSuccess, _w_.OnError), _w_, 5000);')
  else
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(app async)') + ', ' +
      ApiName + '_Async(CALL_TEST_DEFAULT_TARGET_APP, _w_.OnSuccess, _w_.OnError), _w_, 5000);');
  Lines.Add('  finally');
  Lines.Add('    _w_.Free;');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  _w_ := T' + ApiName + '_Waiter.Create;');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(app asyncSeq)') + ', ' +
      ApiName + '_AsyncSequenced(CALL_TEST_DEFAULT_TARGET_APP, ' + ArgList + ', _w_.OnSuccess, _w_.OnError), _w_, 5000);')
  else
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(app asyncSeq)') + ', ' +
      ApiName + '_AsyncSequenced(CALL_TEST_DEFAULT_TARGET_APP, _w_.OnSuccess, _w_.OnError), _w_, 5000);');
  Lines.Add('  finally');
  Lines.Add('    _w_.Free;');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  if G_HasServiceUID then');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    _r_ := ' + ApiName + '_UID_Call(G_ServiceUID, ' + ArgList + ');')
  else
    Lines.Add('    _r_ := ' + ApiName + '_UID_Call(G_ServiceUID);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(uid call)') + ', ' +
    ValueToStrExpr(F.ReturnType, '_r_') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(uid call)') + ', E.Message);');
  Lines.Add('  end');
  Lines.Add('  else');
  Lines.Add('    Report_Skip(' + PascalStrLit(ApiName.Text + '(uid call)') + ', ' + PascalStrLit('no service UID') + ');');

  Lines.Add('');
  Lines.Add('  if G_HasServiceUID then');
  Lines.Add('  begin');
  Lines.Add('    _w_ := T' + ApiName + '_Waiter.Create;');
  Lines.Add('    try');
  if HasParam then
    Lines.Add('      Do_Async_Test(' + PascalStrLit(ApiName.Text + '(uid async)') + ', ' +
      ApiName + '_UID_Async(G_ServiceUID, ' + ArgList + ', _w_.OnSuccess, _w_.OnError), _w_, 5000);')
  else
    Lines.Add('      Do_Async_Test(' + PascalStrLit(ApiName.Text + '(uid async)') + ', ' +
      ApiName + '_UID_Async(G_ServiceUID, _w_.OnSuccess, _w_.OnError), _w_, 5000);');
  Lines.Add('    finally');
  Lines.Add('      _w_.Free;');
  Lines.Add('    end;');
  Lines.Add('  end');
  Lines.Add('  else');
  Lines.Add('    Report_Skip(' + PascalStrLit(ApiName.Text + '(uid async)') + ', ' + PascalStrLit('no service UID') + ');');

  Lines.Add('');
  Lines.Add('  if G_HasServiceUID then');
  Lines.Add('  begin');
  Lines.Add('    _w_ := T' + ApiName + '_Waiter.Create;');
  Lines.Add('    try');
  if HasParam then
    Lines.Add('      Do_Async_Test(' + PascalStrLit(ApiName.Text + '(uid asyncSeq)') + ', ' +
      ApiName + '_UID_AsyncSequenced(G_ServiceUID, ' + ArgList + ', _w_.OnSuccess, _w_.OnError), _w_, 5000);')
  else
    Lines.Add('      Do_Async_Test(' + PascalStrLit(ApiName.Text + '(uid asyncSeq)') + ', ' +
      ApiName + '_UID_AsyncSequenced(G_ServiceUID, _w_.OnSuccess, _w_.OnError), _w_, 5000);');
  Lines.Add('    finally');
  Lines.Add('      _w_.Free;');
  Lines.Add('    end;');
  Lines.Add('  end');
  Lines.Add('  else');
  Lines.Add('    Report_Skip(' + PascalStrLit(ApiName.Text + '(uid asyncSeq)') + ', ' + PascalStrLit('no service UID') + ');');

  Lines.Add('');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    _r_ := ' + ApiName + '_P2PName_Call(CALL_TEST_DEFAULT_TARGET_P2P_NAME, ' + ArgList + ');')
  else
    Lines.Add('    _r_ := ' + ApiName + '_P2PName_Call(CALL_TEST_DEFAULT_TARGET_P2P_NAME);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(p2pname call)') + ', ' +
    ValueToStrExpr(F.ReturnType, '_r_') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(p2pname call)') + ', E.Message);');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  _w_ := T' + ApiName + '_Waiter.Create;');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(p2pname async)') + ', ' +
      ApiName + '_P2PName_Async(CALL_TEST_DEFAULT_TARGET_P2P_NAME, ' + ArgList + ', _w_.OnSuccess, _w_.OnError), _w_, 5000);')
  else
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(p2pname async)') + ', ' +
      ApiName + '_P2PName_Async(CALL_TEST_DEFAULT_TARGET_P2P_NAME, _w_.OnSuccess, _w_.OnError), _w_, 5000);');
  Lines.Add('  finally');
  Lines.Add('    _w_.Free;');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  _w_ := T' + ApiName + '_Waiter.Create;');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(p2pname asyncSeq)') + ', ' +
      ApiName + '_P2PName_AsyncSequenced(CALL_TEST_DEFAULT_TARGET_P2P_NAME, ' + ArgList + ', _w_.OnSuccess, _w_.OnError), _w_, 5000);')
  else
    Lines.Add('    Do_Async_Test(' + PascalStrLit(ApiName.Text + '(p2pname asyncSeq)') + ', ' +
      ApiName + '_P2PName_AsyncSequenced(CALL_TEST_DEFAULT_TARGET_P2P_NAME, _w_.OnSuccess, _w_.OnError), _w_, 5000);');
  Lines.Add('  finally');
  Lines.Add('    _w_.Free;');
  Lines.Add('  end;');

  Lines.Add('end;');
  Lines.Add('');
end;

procedure Emit_Test_Procedure(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  ParamType, ValueExpr, ArgList: TP_String;
  HasParam: Boolean;
begin
  HasParam := Length(F.Params) > 0;

  ArgList := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then ArgList := ArgList + ', ';
    ArgList := ArgList + '_a' + umlIntToStr(i).Text;
  end;

  Lines.Add('procedure Test_' + ApiName + ';');
  if HasParam then
    Lines.Add('var');
  for i := 0 to High(F.Params) do
  begin
    ParamType := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    Lines.Add('  _a' + umlIntToStr(i).Text + ': ' + ParamType + ';');
  end;
  Lines.Add('begin');
  for i := 0 to High(F.Params) do
  begin
    ValueExpr := PlaceholderValue(F.Params[i].PascalType);
    Lines.Add('  _a' + umlIntToStr(i).Text + ' := ' + ValueExpr + ';');
  end;

  Lines.Add('');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    ' + ApiName + '(CALL_TEST_DEFAULT_TARGET_APP, ' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '(CALL_TEST_DEFAULT_TARGET_APP);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(app notify)') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(app notify)') + ', E.Message);');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    ' + ApiName + '_SequencedNotify(CALL_TEST_DEFAULT_TARGET_APP, ' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '_SequencedNotify(CALL_TEST_DEFAULT_TARGET_APP);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(app seq notify)') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(app seq notify)') + ', E.Message);');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  if G_HasServiceUID then');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    ' + ApiName + '_UID_Notify(G_ServiceUID, ' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '_UID_Notify(G_ServiceUID);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(uid notify)') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(uid notify)') + ', E.Message);');
  Lines.Add('  end');
  Lines.Add('  else');
  Lines.Add('    Report_Skip(' + PascalStrLit(ApiName.Text + '(uid notify)') + ', ' + PascalStrLit('no service UID') + ');');

  Lines.Add('');
  Lines.Add('  if G_HasServiceUID then');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    ' + ApiName + '_UID_SequencedNotify(G_ServiceUID, ' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '_UID_SequencedNotify(G_ServiceUID);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(uid seq notify)') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(uid seq notify)') + ', E.Message);');
  Lines.Add('  end');
  Lines.Add('  else');
  Lines.Add('    Report_Skip(' + PascalStrLit(ApiName.Text + '(uid seq notify)') + ', ' + PascalStrLit('no service UID') + ');');

  Lines.Add('');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    ' + ApiName + '_P2PName_Notify(CALL_TEST_DEFAULT_TARGET_P2P_NAME, ' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '_P2PName_Notify(CALL_TEST_DEFAULT_TARGET_P2P_NAME);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(p2pname notify)') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(p2pname notify)') + ', E.Message);');
  Lines.Add('  end;');

  Lines.Add('');
  Lines.Add('  try');
  if HasParam then
    Lines.Add('    ' + ApiName + '_P2PName_SequencedNotify(CALL_TEST_DEFAULT_TARGET_P2P_NAME, ' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '_P2PName_SequencedNotify(CALL_TEST_DEFAULT_TARGET_P2P_NAME);');
  Lines.Add('    Report_Pass(' + PascalStrLit(ApiName.Text + '(p2pname seq notify)') + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do Report_Fail(' + PascalStrLit(ApiName.Text + '(p2pname seq notify)') + ', E.Message);');
  Lines.Add('  end;');

  Lines.Add('end;');
  Lines.Add('');
end;

function GenerateABICallTestPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, P2PName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    AssignUniqueApiNames(SupportedFuncs, ApiNames);

    Lines.Add('unit ' + NormalizedUnit.Text + '_abi_call_test_unit;');
    Lines.Add('');
    Lines.Add('{$ifdef FPC}');
    Lines.Add('  {$mode delphi}{$H+}');
    Lines.Add('  {$MODESWITCH NestedProcVars}');
    Lines.Add('  {$modeswitch advancedrecords}');
    Lines.Add('  {$CODEPAGE UTF8}');
    Lines.Add('{$endif}');
    Lines.Add('{$R-}{$I-}{$Q-}{$B-}');
    Lines.Add('');
    Lines.Add('interface');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  SysUtils, Classes, SyncObjs,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  ' + NormalizedUnit.Text + '_abi_call_unit;');
    Lines.Add('');
    Lines.Add('type');
    Lines.Add('  TCallTestReport = record');
    Lines.Add('    TotalTests: Integer;');
    Lines.Add('    PassCount: Integer;');
    Lines.Add('    FailCount: Integer;');
    Lines.Add('    SkipCount: Integer;');
    Lines.Add('    ElapsedMs: Int64;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  TAnyWaiter = class');
    Lines.Add('  public');
    Lines.Add('    Event: TEvent;');
    Lines.Add('    Success: Boolean;');
    Lines.Add('    ErrMsg: string;');
    Lines.Add('    ValueStr: string;');
    Lines.Add('    constructor Create;');
    Lines.Add('    destructor Destroy; override;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('const');
    Lines.Add('  CALL_TEST_DEFAULT_ENDPOINT = ' + PascalStrLit('ipc:' + AppName.Text) + ';');
    Lines.Add('  CALL_TEST_DEFAULT_TARGET_APP = ' + PascalStrLit(AppName.Text) + ';');
    Lines.Add('  CALL_TEST_DEFAULT_TARGET_P2P_NAME = ' + PascalStrLit(P2PName.Text) + ';');
    Lines.Add('  CALL_TEST_CLIENT_APP = ' + PascalStrLit('LF_TEST_CLIENT_SELF') + ';');
    Lines.Add('  CALL_TEST_REPORT_IDENTITY_API = ' + PascalStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
    Lines.Add('  CALL_TEST_WHOAMI_API = ' + PascalStrLit('LF_TEST_WHOAMI') + ';');
    Lines.Add('  CALL_TEST_ASK_CALL_ME_API = ' + PascalStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
    Lines.Add('');
    Lines.Add('function Run_Call_Test: TCallTestReport;');
    Lines.Add('');
    Lines.Add('implementation');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  G_Pass: Integer = 0;');
    Lines.Add('  G_Fail: Integer = 0;');
    Lines.Add('  G_Skip: Integer = 0;');
    Lines.Add('  G_StartTick: Int64 = 0;');
    Lines.Add('  G_Report: TCallTestReport;');
    Lines.Add('  G_ClientApp: TAppHnd___ = nil;');
    Lines.Add('  G_ClientUID: TP2P_UID___;');
    Lines.Add('  G_ClientP2PName: string;');
    Lines.Add('  G_HasClientUID: Boolean = False;');
    Lines.Add('  G_ServiceUID: TP2P_UID___;');
    Lines.Add('  G_ServiceP2PName: string;');
    Lines.Add('  G_HasServiceUID: Boolean = False;');
    Lines.Add('  G_ServiceCalledMe: Boolean = False;');
    Lines.Add('  G_Lock: TCriticalSection = nil;');
    Lines.Add('');
    Lines.Add('function BytesToHex(const Buf; Len: Integer): string;');
    Lines.Add('var P: PByte; i: Integer;');
    Lines.Add('begin');
    Lines.Add('  Result := ' + #39#39 + ';');
    Lines.Add('  P := @Buf;');
    Lines.Add('  for i := 0 to Len - 1 do');
    Lines.Add('    Result := Result + IntToHex(P[i], 2);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('function IsNullUID(const UID: TP2P_UID___): Boolean;');
    Lines.Add('var i: Integer;');
    Lines.Add('begin');
    Lines.Add('  for i := 0 to High(UID) do');
    Lines.Add('    if UID[i] <> 0 then Exit(False);');
    Lines.Add('  Result := True;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Report_Pass(const LabelName: string; const ValueStr_: string = ' + #39#39 + ');');
    Lines.Add('begin');
    Lines.Add('  Inc(G_Pass);');
    Lines.Add('  if ValueStr_ <> ' + #39#39 + ' then WriteLn(' + PascalStrLit('[PASS] ') + ', LabelName, ' + PascalStrLit(' = ') + ', ValueStr_)');
    Lines.Add('  else WriteLn(' + PascalStrLit('[PASS] ') + ', LabelName);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Report_Fail(const LabelName, Reason: string);');
    Lines.Add('begin');
    Lines.Add('  Inc(G_Fail);');
    Lines.Add('  WriteLn(' + PascalStrLit('[FAIL] ') + ', LabelName, ' + PascalStrLit(' -- ') + ', Reason);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Report_Skip(const LabelName, Reason: string);');
    Lines.Add('begin');
    Lines.Add('  Inc(G_Skip);');
    Lines.Add('  WriteLn(' + PascalStrLit('[SKIP] ') + ', LabelName, ' + PascalStrLit(' -- ') + ', Reason);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('constructor TAnyWaiter.Create;');
    Lines.Add('begin');
    Lines.Add('  inherited;');
    Lines.Add('  Event := TEvent.Create(nil, True, False, ' + #39#39 + ');');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('destructor TAnyWaiter.Destroy;');
    Lines.Add('begin');
    Lines.Add('  Event.Free;');
    Lines.Add('  inherited;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Do_Async_Test(const LabelName: string; Dispatched: Boolean;');
    Lines.Add('  W: TAnyWaiter; TimeoutMs: Cardinal);');
    Lines.Add('begin');
    Lines.Add('  if not Dispatched then');
    Lines.Add('  begin');
    Lines.Add('    Report_Fail(LabelName, ' + PascalStrLit('dispatch failed') + ');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('  if W.Event.WaitFor(TimeoutMs) <> wrSignaled then');
    Lines.Add('  begin');
    Lines.Add('    Report_Fail(LabelName, ' + PascalStrLit('timeout') + ');');
    Lines.Add('    Exit;');
    Lines.Add('  end;');
    Lines.Add('  if W.Success then');
    Lines.Add('    Report_Pass(LabelName, W.ValueStr)');
    Lines.Add('  else');
    Lines.Add('    Report_Fail(LabelName, W.ErrMsg);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure Client_CB_ReportIdentity(_Trigger: Pointer; _In_, _Out_: TDataHnd___); cdecl;');
    Lines.Add('var');
    Lines.Add('  _uidPtr: PP2P_UID___;');
    Lines.Add('  _msg: string;');
    Lines.Add('begin');
    Lines.Add('  G_Lock.Enter;');
    Lines.Add('  try');
    Lines.Add('    FillChar(G_ServiceUID, SizeOf(G_ServiceUID), 0);');
    Lines.Add('    _uidPtr := LF_Get_P2P_UID(_In_);');
    Lines.Add('    if _uidPtr <> nil then G_ServiceUID := _uidPtr^;');
    Lines.Add('    G_ServiceP2PName := LF_Get_P2P_NameEx(_In_);');
    Lines.Add('    G_HasServiceUID := not IsNullUID(G_ServiceUID);');
    Lines.Add('    G_ServiceCalledMe := True;');
    Lines.Add('  finally');
    Lines.Add('    G_Lock.Leave;');
    Lines.Add('  end;');
    Lines.Add('  LF_SetPos(_In_, 0);');
    Lines.Add('  LF_ReadString(_In_, _msg);');
    Lines.Add('  WriteLn(' + PascalStrLit('[CLIENT] service called me, msg="') + ', _msg, ' + PascalStrLit('"') + ');');
    Lines.Add('  LF_WriteUInt8(_Out_, $00);');
    Lines.Add('  LF_WriteString(_Out_, ' + PascalStrLit('identity received') + ');');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('function Probe_Client_Identity: Boolean;');
    Lines.Add('var');
    Lines.Add('  _data, _res: TDataHnd___;');
    Lines.Add('  _status: uint8;');
    Lines.Add('begin');
    Lines.Add('  Result := False;');
    Lines.Add('  G_HasClientUID := False;');
    Lines.Add('  FillChar(G_ClientUID, SizeOf(G_ClientUID), 0);');
    Lines.Add('  G_ClientP2PName := ' + #39#39 + ';');
    Lines.Add('  _data := LF_CreateDataEx(CALL_TEST_WHOAMI_API);');
    Lines.Add('  if _data = nil then Exit;');
    Lines.Add('  try');
    Lines.Add('    _res := LF_CallEx(CALL_TEST_DEFAULT_TARGET_APP, _data, 5000);');
    Lines.Add('    if _res = nil then Exit;');
    Lines.Add('    try');
    Lines.Add('      if LF_GetSize(_res) < SizeOf(TP2P_UID___) + 2 then Exit;');
    Lines.Add('      LF_SetPos(_res, 0);');
    Lines.Add('      if not LF_ReadUInt8(_res, _status) then Exit;');
    Lines.Add('      if _status <> 0 then Exit;');
    Lines.Add('      LF_ReadBuffer(_res, @G_ClientUID[0], SizeOf(TP2P_UID___));');
    Lines.Add('      LF_ReadString(_res, G_ClientP2PName);');
    Lines.Add('      G_HasClientUID := not IsNullUID(G_ClientUID);');
    Lines.Add('      Result := G_HasClientUID;');
    Lines.Add('    finally');
    Lines.Add('      LF_FreeData(_res);');
    Lines.Add('    end;');
    Lines.Add('  finally');
    Lines.Add('    LF_FreeData(_data);');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('function Test_ServiceInitiatesCall: Boolean;');
    Lines.Add('var _data: TDataHnd___; _endTick: Int64;');
    Lines.Add('begin');
    Lines.Add('  G_Lock.Enter;');
    Lines.Add('  try');
    Lines.Add('    G_ServiceCalledMe := False;');
    Lines.Add('    G_HasServiceUID := False;');
    Lines.Add('    FillChar(G_ServiceUID, SizeOf(G_ServiceUID), 0);');
    Lines.Add('    G_ServiceP2PName := ' + #39#39 + ';');
    Lines.Add('  finally');
    Lines.Add('    G_Lock.Leave;');
    Lines.Add('  end;');
    Lines.Add('  _data := LF_CreateDataEx(CALL_TEST_ASK_CALL_ME_API);');
    Lines.Add('  if _data = nil then begin Result := False; Exit; end;');
    Lines.Add('  try');
    Lines.Add('    LF_WriteString(_data, CALL_TEST_REPORT_IDENTITY_API);');
    Lines.Add('    LF_NotifyEx(CALL_TEST_DEFAULT_TARGET_APP, _data);');
    Lines.Add('  finally');
    Lines.Add('    LF_FreeData(_data);');
    Lines.Add('  end;');
    Lines.Add('  _endTick := Int64(TThread.GetTickCount) + 10000;');
    Lines.Add('  while Int64(TThread.GetTickCount) < _endTick do');
    Lines.Add('  begin');
    Lines.Add('    TThread.Sleep(10);');
    Lines.Add('    G_Lock.Enter;');
    Lines.Add('    try');
    Lines.Add('      if G_ServiceCalledMe then Break;');
    Lines.Add('    finally');
    Lines.Add('      G_Lock.Leave;');
    Lines.Add('    end;');
    Lines.Add('  end;');
    Lines.Add('  G_Lock.Enter;');
    Lines.Add('  try');
    Lines.Add('    Result := G_ServiceCalledMe and G_HasServiceUID;');
    Lines.Add('  finally');
    Lines.Add('    G_Lock.Leave;');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      if SupportedFuncs[i].IsFunction then
        Emit_Waiter_Class(Lines, ApiNames[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
      if SupportedFuncs[i].IsFunction then
        Emit_Test_Function(Lines, ApiNames[i], SupportedFuncs[i])
      else
        Emit_Test_Procedure(Lines, ApiNames[i], SupportedFuncs[i]);

    Lines.Add('function Run_Call_Test: TCallTestReport;');
    Lines.Add('begin');
    Lines.Add('  FillChar(G_Report, SizeOf(G_Report), 0);');
    Lines.Add('  G_Pass := 0; G_Fail := 0; G_Skip := 0;');
    Lines.Add('  G_StartTick := Int64(TThread.GetTickCount);');
    Lines.Add('');
    Lines.Add('  WriteLn(' + PascalStrLit('=== ' + UnitName.Text + ' ABI call test ===') + ');');
    Lines.Add('  WriteLn(' + PascalStrLit('Endpoint: ') + ', CALL_TEST_DEFAULT_ENDPOINT);');
    Lines.Add('  WriteLn(' + PascalStrLit('AppName : ') + ', CALL_TEST_DEFAULT_TARGET_APP);');
    Lines.Add('  WriteLn(' + PascalStrLit('P2PName : ') + ', CALL_TEST_DEFAULT_TARGET_P2P_NAME);');
    Lines.Add('  WriteLn;');
    Lines.Add('');
    Lines.Add('  G_Lock := TCriticalSection.Create;');
    Lines.Add('  try');
    Lines.Add('    LF_ResetPrepare;');
    Lines.Add('    LF_Set_Opt_Quiet(True);');
    Lines.Add('    LF_Set_Opt_ConsoleOutput(True);');
    Lines.Add('    ABI_Timeout := 5000;');
    Lines.Add('');
    Lines.Add('    G_ClientApp := LF_CreateAppEx(CALL_TEST_CLIENT_APP, ' + PascalStrLit('client test app') + ');');
    Lines.Add('    if G_ClientApp = nil then');
    Lines.Add('    begin');
    Lines.Add('      Report_Fail(' + PascalStrLit('LF_CreateAppEx') + ', ' + PascalStrLit('returned nil') + ');');
    Lines.Add('      G_Report.PassCount := G_Pass; G_Report.FailCount := G_Fail;');
    Lines.Add('      G_Report.SkipCount := G_Skip; G_Report.TotalTests := G_Pass + G_Fail + G_Skip;');
    Lines.Add('      G_Report.ElapsedMs := Int64(TThread.GetTickCount) - G_StartTick;');
    Lines.Add('      Result := G_Report; Exit;');
    Lines.Add('    end;');
    Lines.Add('    LF_RegisterCallEx(G_ClientApp, CALL_TEST_REPORT_IDENTITY_API, ' +
      PascalStrLit('report service identity') + ', nil, @Client_CB_ReportIdentity);');
    Lines.Add('');
    Lines.Add('    if LF_PrepareClientEx(CALL_TEST_DEFAULT_ENDPOINT, G_ClientApp) = -1 then');
    Lines.Add('    begin');
    Lines.Add('      Report_Fail(' + PascalStrLit('LF_PrepareClient') + ', ' + PascalStrLit('returned -1') + ');');
    Lines.Add('      LF_FreeApp(G_ClientApp); G_ClientApp := nil;');
    Lines.Add('      G_Report.PassCount := G_Pass; G_Report.FailCount := G_Fail;');
    Lines.Add('      G_Report.SkipCount := G_Skip; G_Report.TotalTests := G_Pass + G_Fail + G_Skip;');
    Lines.Add('      G_Report.ElapsedMs := Int64(TThread.GetTickCount) - G_StartTick;');
    Lines.Add('      Result := G_Report; Exit;');
    Lines.Add('    end;');
    Lines.Add('');
    Lines.Add('    if LF_PrepareDone() <> 1 then');
    Lines.Add('    begin');
    Lines.Add('      Report_Fail(' + PascalStrLit('LF_PrepareDone') + ', ' + PascalStrLit('not-1') + ');');
    Lines.Add('      LF_ExitMainThread;');
    Lines.Add('      LF_FreeApp(G_ClientApp); G_ClientApp := nil;');
    Lines.Add('      LF_Shutdown;');
    Lines.Add('      G_Report.PassCount := G_Pass; G_Report.FailCount := G_Fail;');
    Lines.Add('      G_Report.SkipCount := G_Skip; G_Report.TotalTests := G_Pass + G_Fail + G_Skip;');
    Lines.Add('      G_Report.ElapsedMs := Int64(TThread.GetTickCount) - G_StartTick;');
    Lines.Add('      Result := G_Report; Exit;');
    Lines.Add('    end;');
    Lines.Add('');
    Lines.Add('    WriteLn(' + PascalStrLit('[READY] Client online.') + ');');
    Lines.Add('    WriteLn;');
    Lines.Add('');
    Lines.Add('    if Probe_Client_Identity then');
    Lines.Add('    begin');
    Lines.Add('      WriteLn(' + PascalStrLit('[INFO] client UID = ') + ', BytesToHex(G_ClientUID, SizeOf(G_ClientUID)));');
    Lines.Add('      WriteLn(' + PascalStrLit('[INFO] client P2P = ') + ', G_ClientP2PName);');
    Lines.Add('    end');
    Lines.Add('    else');
    Lines.Add('      WriteLn(' + PascalStrLit('[WARN] whoami failed, UID tests will be skipped') + ');');
    Lines.Add('    WriteLn;');
    Lines.Add('');
    Lines.Add('    if Test_ServiceInitiatesCall then');
    Lines.Add('    begin');
    Lines.Add('      WriteLn(' + PascalStrLit('[INFO] service UID = ') + ', BytesToHex(G_ServiceUID, SizeOf(G_ServiceUID)));');
    Lines.Add('      WriteLn(' + PascalStrLit('[INFO] service P2P = ') + ', G_ServiceP2PName);');
    Lines.Add('      Report_Pass(' + PascalStrLit('service-initiated call') + ');');
    Lines.Add('    end');
    Lines.Add('    else');
    Lines.Add('      Report_Fail(' + PascalStrLit('service-initiated call') + ', ' + PascalStrLit('timeout or no UID') + ');');
    Lines.Add('    WriteLn;');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      Lines.Add('    Test_' + ApiNames[i] + ';');

    Lines.Add('');
    Lines.Add('    WriteLn;');
    Lines.Add('    WriteLn(' + PascalStrLit('=== Summary ===') + ');');
    Lines.Add('    WriteLn(' + PascalStrLit('Pass: ') + ', G_Pass);');
    Lines.Add('    WriteLn(' + PascalStrLit('Fail: ') + ', G_Fail);');
    Lines.Add('    WriteLn(' + PascalStrLit('Skip: ') + ', G_Skip);');
    Lines.Add('');
    Lines.Add('    LF_ExitMainThread;');
    Lines.Add('    LF_FreeApp(G_ClientApp);');
    Lines.Add('    G_ClientApp := nil;');
    Lines.Add('    LF_Shutdown;');
    Lines.Add('');
    Lines.Add('    G_Report.PassCount := G_Pass;');
    Lines.Add('    G_Report.FailCount := G_Fail;');
    Lines.Add('    G_Report.SkipCount := G_Skip;');
    Lines.Add('    G_Report.TotalTests := G_Pass + G_Fail + G_Skip;');
    Lines.Add('    G_Report.ElapsedMs := Int64(TThread.GetTickCount) - G_StartTick;');
    Lines.Add('    Result := G_Report;');
    Lines.Add('  finally');
    Lines.Add('    G_Lock.Free;');
    Lines.Add('    G_Lock := nil;');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('end.');

    Result := Lines;
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator('pascal', 'xxx_abi_service_test_unit.pas', gkTest,
    'Pascal ABI service test unit', @GenerateABIServiceTestPascalCode);

  RegisterGenerator('pascal', 'xxx_abi_call_test_unit.pas', gkTest,
    'Pascal ABI call test unit', @GenerateABICallTestPascalCode);

end.
