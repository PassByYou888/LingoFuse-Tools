unit py_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestPyCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestPyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function IsFloatABIType(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('extended') or T.Same('real');
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := IsStringABIType(T) or IsFloatABIType(T) or T.Same('single') or
    T.Same('integer') or T.Same('longint') or T.Same('cardinal') or
    T.Same('dword') or T.Same('longword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('int64') or T.Same('uint64');
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function PyStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
      Result.Append('\' + #39)
    else if c = #92 then
      Result.Append('\\')
    else if c = #10 then
      Result.Append('\n')
    else if c = #13 then
      Result.Append('\r')
    else if c = #9 then
      Result.Append('\t')
    else
      Result.Append(c);
  end;
  Result.Append(#39);
end;

function PlaceholderArg(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := '"test"'
  else if ABIType.Same('single') or IsFloatABIType(ABIType) then
    Result := '0.0'
  else
    Result := '0';
end;

function BuildPlaceholderArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + PlaceholderArg(Params[i].PascalType);
  end;
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
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
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

procedure CollectUniqueApiNames(const Funcs: TArryFunctionStructure; Names: TPascalStringList);
var
  i, j: integer;
  N: TP_String;
begin
  Names.Clear;
  for i := 0 to High(Funcs) do
  begin
    N := MakeApiName(Funcs[i].Name);
    if Names.IndexOf(N) >= 0 then
    begin
      j := 1;
      while Names.IndexOf(N + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      N := N + '_' + umlIntToStr(j).Text;
    end;
    Names.Add(N);
  end;
end;

function GenerateABIServiceTestPyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, P2PName: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  Lines: TPascalStringList;
  ApiCount: integer;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestPyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestPyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiCount := Length(SupportedFuncs);

  Log(PFormat('Generating Python ABI service test for unit "%s" (%d APIs)',
    [UnitName.Text, ApiCount]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('# -*- coding: utf-8 -*-');
    Lines.Add('');
    Lines.Add('import sys');
    Lines.Add('');
    Lines.Add('from lingofuse._lf_native import (');
    Lines.Add('    LFCallFunc,');
    Lines.Add('    LFNotifyFunc,');
    Lines.Add('    LF_CreateData,');
    Lines.Add('    LF_FreeData,');
    Lines.Add('    LF_RegisterCall,');
    Lines.Add('    LF_RegisterNotify,');
    Lines.Add('    LF_Register_P2P_Call,');
    Lines.Add('    LF_Register_P2P_Notify,');
    Lines.Add('    LF_ResetPrepare,');
    Lines.Add('    LF_PrepareService,');
    Lines.Add('    LF_PrepareClient,');
    Lines.Add('    LF_PrepareDone,');
    Lines.Add('    LF_ExitMainThread,');
    Lines.Add('    LF_Shutdown,');
    Lines.Add('    LF_UID_Call,');
    Lines.Add('    LF_WriteBuffer,');
    Lines.Add(')');
    Lines.Add('from lingofuse.lf_io import cstr, write_string as _lf_write_string');
    Lines.Add('from lingofuse.core import DataHandle');
    Lines.Add('from lingofuse.address import to_tp2p_uid');
    Lines.Add('from lingofuse.options import set_opt_p2p_name');
    Lines.Add('');
    Lines.Add('import ' + NormalizedUnit + '_abi_service as svc');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('P2P_NAME = ' + PyStrLit(P2PName));
    Lines.Add('WHOAMI_API = ' + PyStrLit('LF_TEST_WHOAMI'));
    Lines.Add('ASK_CALL_ME_API = ' + PyStrLit('LF_TEST_ASK_SERVICE_CALL_ME'));
    Lines.Add('REPORT_IDENTITY_API = ' + PyStrLit('LF_TEST_REPORT_SERVICE_IDENTITY'));
    Lines.Add('');
    Lines.Add('');
    Lines.Add('@LFCallFunc');
    Lines.Add('def cb_whoami(_Trigger, _In, _Out):');
    Lines.Add('    in_h = DataHandle._from_raw(_In, owned=False)');
    Lines.Add('    try:');
    Lines.Add('        uid = in_h.get_p2p_uid()');
    Lines.Add('        p2p = in_h.get_p2p_name()');
    Lines.Add('    except Exception:');
    Lines.Add('        uid = b"\\x00" * 32');
    Lines.Add('        p2p = ""');
    Lines.Add('    payload = b"\\x00" + uid + p2p.encode("utf-8") + b"\\x00"');
    Lines.Add('    LF_WriteBuffer(_Out, payload, len(payload))');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('@LFNotifyFunc');
    Lines.Add('def cb_ask_service_call_me(_Trigger, _In):');
    Lines.Add('    in_h = DataHandle._from_raw(_In, owned=False)');
    Lines.Add('    try:');
    Lines.Add('        client_uid = in_h.get_p2p_uid()');
    Lines.Add('    except Exception:');
    Lines.Add('        return');
    Lines.Add('    if client_uid == b"\\x00" * 32:');
    Lines.Add('        print("[SERVICE] ask_call_me: no UID in input", file=sys.stderr)');
    Lines.Add('        return');
    Lines.Add('');
    Lines.Add('    data = LF_CreateData(cstr(REPORT_IDENTITY_API))');
    Lines.Add('    if not data:');
    Lines.Add('        return');
    Lines.Add('    try:');
    Lines.Add('        _lf_write_string(data, "service initiates call")');
    Lines.Add('        uid_arr = to_tp2p_uid(client_uid)');
    Lines.Add('        res = LF_UID_Call(uid_arr, data, 5000)');
    Lines.Add('        if res:');
    Lines.Add('            LF_FreeData(res)');
    Lines.Add('            print("[SERVICE] ask_call_me: client responded ok")');
    Lines.Add('        else:');
    Lines.Add('            print("[SERVICE] ask_call_me: UID call returned nil", file=sys.stderr)');
    Lines.Add('    except Exception as e:');
    Lines.Add('        print("[SERVICE] ask_call_me failed: %s" % str(e), file=sys.stderr)');
    Lines.Add('    finally:');
    Lines.Add('        LF_FreeData(data)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _register_test_helpers_app(app):');
    Lines.Add('    if LF_RegisterCall(app, cstr(WHOAMI_API), cstr("service-side whoami helper"), None, cb_whoami) != 1:');
    Lines.Add('        print("[WARN] failed to register " + WHOAMI_API, file=sys.stderr)');
    Lines.Add('    if LF_RegisterNotify(app, cstr(ASK_CALL_ME_API), cstr("ask service to call back client"), None, cb_ask_service_call_me) != 1:');
    Lines.Add('        print("[WARN] failed to register " + ASK_CALL_ME_API, file=sys.stderr)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _register_test_helpers_p2p():');
    Lines.Add('    if LF_Register_P2P_Call(cstr(WHOAMI_API), cstr("service-side whoami helper"), None, cb_whoami) != 1:');
    Lines.Add('        print("[WARN] failed to register P2P " + WHOAMI_API, file=sys.stderr)');
    Lines.Add('    if LF_Register_P2P_Notify(cstr(ASK_CALL_ME_API), cstr("ask service to call back client"), None, cb_ask_service_call_me) != 1:');
    Lines.Add('        print("[WARN] failed to register P2P " + ASK_CALL_ME_API, file=sys.stderr)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def main():');
    Lines.Add('    print("=== ' + UnitName.Text + ' ABI service test ===")');
    Lines.Add('    endpoint = "ipc:" + svc.DEFAULT_APP_NAME');
    Lines.Add('');
    Lines.Add('    LF_ResetPrepare()');
    Lines.Add('    LF_PrepareService(cstr(endpoint), cstr(endpoint))');
    Lines.Add('');
    Lines.Add('    app = svc.Create_And_Register_ABI_App()');
    Lines.Add('    if not app:');
    Lines.Add('        print("[FATAL] Create_And_Register_ABI_App failed", file=sys.stderr)');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    _register_test_helpers_app(app)');
    Lines.Add('');
    Lines.Add('    set_opt_p2p_name(P2P_NAME)');
    Lines.Add('    svc.Register_All_P2P_ABI_APIs()');
    Lines.Add('    _register_test_helpers_p2p()');
    Lines.Add('');
    Lines.Add('    if LF_PrepareClient(cstr(endpoint), app) == -1:');
    Lines.Add('        print("[FATAL] LF_PrepareClient failed", file=sys.stderr)');
    Lines.Add('        LF_Shutdown()');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    if LF_PrepareDone() != 1:');
    Lines.Add('        print("[FATAL] LF_PrepareDone failed", file=sys.stderr)');
    Lines.Add('        LF_ExitMainThread()');
    Lines.Add('        LF_Shutdown()');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    print("[OK] Service ready on " + endpoint)');
    Lines.Add('    print("[OK] Registered ' + umlIntToStr(ApiCount).Text + ' API(s)")');
    Lines.Add('    print("[OK] Press Enter to shut down")');
    Lines.Add('');
    Lines.Add('    try:');
    Lines.Add('        input()');
    Lines.Add('    except (KeyboardInterrupt, EOFError):');
    Lines.Add('        pass');
    Lines.Add('');
    Lines.Add('    LF_ExitMainThread()');
    Lines.Add('    LF_Shutdown()');
    Lines.Add('    print("[OK] Shutdown complete")');
    Lines.Add('    return 0');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if __name__ == "__main__":');
    Lines.Add('    sys.exit(main())');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service test.', [Lines.Count]));
  finally
    if Result = nil then
      Lines.Free;
  end;
end;

procedure EmitFunctionSyncTest(Lines: TPascalStringList;
  const Indent, Label_, CallExpr: TP_String);
begin
  Lines.Add(Indent + 'try:');
  Lines.Add(Indent + '    _r = ' + CallExpr);
  Lines.Add(Indent + '    _report_pass(' + PyStrLit(Label_) + ', repr(_r))');
  Lines.Add(Indent + 'except Exception as _e:');
  Lines.Add(Indent + '    _report_fail(' + PyStrLit(Label_) + ', str(_e))');
end;

procedure EmitFunctionFutureTest(Lines: TPascalStringList;
  const Indent, Label_, CallExpr: TP_String);
begin
  Lines.Add(Indent + 'try:');
  Lines.Add(Indent + '    _fut = ' + CallExpr);
  Lines.Add(Indent + '    _r = _fut.result(timeout=5.0)');
  Lines.Add(Indent + '    _report_pass(' + PyStrLit(Label_) + ', repr(_r))');
  Lines.Add(Indent + 'except Exception as _e:');
  Lines.Add(Indent + '    _report_fail(' + PyStrLit(Label_) + ', str(_e))');
end;

procedure EmitFunctionAioTest(Lines: TPascalStringList;
  const Indent, Label_, CallExpr: TP_String);
begin
  Lines.Add(Indent + 'try:');
  Lines.Add(Indent + '    _r = asyncio.run(' + CallExpr + ')');
  Lines.Add(Indent + '    _report_pass(' + PyStrLit(Label_) + ', repr(_r))');
  Lines.Add(Indent + 'except Exception as _e:');
  Lines.Add(Indent + '    _report_fail(' + PyStrLit(Label_) + ', str(_e))');
end;

procedure EmitProcedureSyncTest(Lines: TPascalStringList;
  const Indent, Label_, CallExpr: TP_String);
begin
  Lines.Add(Indent + 'try:');
  Lines.Add(Indent + '    ' + CallExpr);
  Lines.Add(Indent + '    _report_pass(' + PyStrLit(Label_) + ')');
  Lines.Add(Indent + 'except Exception as _e:');
  Lines.Add(Indent + '    _report_fail(' + PyStrLit(Label_) + ', str(_e))');
end;

procedure EmitFunctionTestPy(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  Args: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);

  Lines.Add('def _test_' + ApiName + '_function():');

  EmitFunctionSyncTest(Lines, '    ', ApiName + '(app call)',
    'abi.' + ApiName + '(' + Args + ')');

  Lines.Add('    if _G_HAS_SERVICE_UID:');
  EmitFunctionSyncTest(Lines, '        ', ApiName + '(uid call)',
    'abi.' + ApiName + '_UID_Call(_G_SERVICE_UID, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid call)') + ', "no service UID")');

  Lines.Add('    if _G_HAS_SERVICE_UID and _G_SERVICE_P2P:');
  EmitFunctionSyncTest(Lines, '        ', ApiName + '(p2pname call)',
    'abi.' + ApiName + '_P2PName_Call(_G_SERVICE_P2P, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname call)') + ', "no service P2PName")');

  EmitFunctionFutureTest(Lines, '    ', ApiName + '(app async)',
    'abi.' + ApiName + '_Async(' + Args + ')');
  EmitFunctionFutureTest(Lines, '    ', ApiName + '(app asyncSeq)',
    'abi.' + ApiName + '_AsyncSequenced(' + Args + ')');

  Lines.Add('    if _G_HAS_SERVICE_UID:');
  EmitFunctionFutureTest(Lines, '        ', ApiName + '(uid async)',
    'abi.' + ApiName + '_UID_Async(_G_SERVICE_UID, ' + Args + ')');
  EmitFunctionFutureTest(Lines, '        ', ApiName + '(uid asyncSeq)',
    'abi.' + ApiName + '_UID_AsyncSequenced(_G_SERVICE_UID, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid async)') + ', "no service UID")');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid asyncSeq)') + ', "no service UID")');

  Lines.Add('    if _G_HAS_SERVICE_UID and _G_SERVICE_P2P:');
  EmitFunctionFutureTest(Lines, '        ', ApiName + '(p2pname async)',
    'abi.' + ApiName + '_P2PName_Async(_G_SERVICE_P2P, ' + Args + ')');
  EmitFunctionFutureTest(Lines, '        ', ApiName + '(p2pname asyncSeq)',
    'abi.' + ApiName + '_P2PName_AsyncSequenced(_G_SERVICE_P2P, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname async)') + ', "no service P2PName")');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname asyncSeq)') + ', "no service P2PName")');

  EmitFunctionAioTest(Lines, '    ', ApiName + '(app aio)',
    'abi.' + ApiName + '_Aio(' + Args + ')');
  EmitFunctionAioTest(Lines, '    ', ApiName + '(app seq aio)',
    'abi.' + ApiName + '_Sequenced_Aio(' + Args + ')');

  Lines.Add('    if _G_HAS_SERVICE_UID:');
  EmitFunctionAioTest(Lines, '        ', ApiName + '(uid aio)',
    'abi.' + ApiName + '_UID_Aio(_G_SERVICE_UID, ' + Args + ')');
  EmitFunctionAioTest(Lines, '        ', ApiName + '(uid seq aio)',
    'abi.' + ApiName + '_UID_Sequenced_Aio(_G_SERVICE_UID, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid aio)') + ', "no service UID")');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid seq aio)') + ', "no service UID")');

  Lines.Add('    if _G_HAS_SERVICE_UID and _G_SERVICE_P2P:');
  EmitFunctionAioTest(Lines, '        ', ApiName + '(p2pname aio)',
    'abi.' + ApiName + '_P2PName_Aio(_G_SERVICE_P2P, ' + Args + ')');
  EmitFunctionAioTest(Lines, '        ', ApiName + '(p2pname seq aio)',
    'abi.' + ApiName + '_P2PName_Sequenced_Aio(_G_SERVICE_P2P, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname aio)') + ', "no service P2PName")');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname seq aio)') + ', "no service P2PName")');

  Lines.Add('');
  Lines.Add('');
end;

procedure EmitProcedureTestPy(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  Args: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);

  Lines.Add('def _test_' + ApiName + '_procedure():');

  EmitProcedureSyncTest(Lines, '    ', ApiName + '(app notify)',
    'abi.' + ApiName + '(' + Args + ')');
  EmitProcedureSyncTest(Lines, '    ', ApiName + '(app seq notify)',
    'abi.' + ApiName + '_SequencedNotify(' + Args + ')');

  Lines.Add('    if _G_HAS_SERVICE_UID:');
  EmitProcedureSyncTest(Lines, '        ', ApiName + '(uid notify)',
    'abi.' + ApiName + '_UID_Notify(_G_SERVICE_UID, ' + Args + ')');
  EmitProcedureSyncTest(Lines, '        ', ApiName + '(uid seq notify)',
    'abi.' + ApiName + '_UID_SequencedNotify(_G_SERVICE_UID, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid notify)') + ', "no service UID")');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(uid seq notify)') + ', "no service UID")');

  Lines.Add('    if _G_HAS_SERVICE_UID and _G_SERVICE_P2P:');
  EmitProcedureSyncTest(Lines, '        ', ApiName + '(p2pname notify)',
    'abi.' + ApiName + '_P2PName_Notify(_G_SERVICE_P2P, ' + Args + ')');
  EmitProcedureSyncTest(Lines, '        ', ApiName + '(p2pname seq notify)',
    'abi.' + ApiName + '_P2PName_SequencedNotify(_G_SERVICE_P2P, ' + Args + ')');
  Lines.Add('    else:');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname notify)') + ', "no service P2PName")');
  Lines.Add('        _report_skip(' + PyStrLit(ApiName + '(p2pname seq notify)') + ', "no service P2PName")');

  Lines.Add('');
  Lines.Add('');
end;

function GenerateABICallTestPyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
  FuncCount, ProcCount: integer;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestPyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestPyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  SupportedFuncs := CollectSupportedFunctions(Model);

  FuncCount := 0;
  ProcCount := 0;
  for i := 0 to High(SupportedFuncs) do
    if SupportedFuncs[i].IsFunction then
      Inc(FuncCount)
    else
      Inc(ProcCount);

  Log(PFormat('Generating Python ABI call test for unit "%s" (%d functions, %d procedures)',
    [UnitName.Text, FuncCount, ProcCount]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    CollectUniqueApiNames(SupportedFuncs, UsedApiNames);

    Lines.Add('# -*- coding: utf-8 -*-');
    Lines.Add('');
    Lines.Add('import asyncio');
    Lines.Add('import sys');
    Lines.Add('import time');
    Lines.Add('');
    Lines.Add('from lingofuse._lf_native import (');
    Lines.Add('    LFCallFunc,');
    Lines.Add('    LF_CreateData,');
    Lines.Add('    LF_FreeData,');
    Lines.Add('    LF_RegisterCall,');
    Lines.Add('    LF_ResetPrepare,');
    Lines.Add('    LF_PrepareClient,');
    Lines.Add('    LF_PrepareDone,');
    Lines.Add('    LF_ExitMainThread,');
    Lines.Add('    LF_Shutdown,');
    Lines.Add('    LF_CreateApp,');
    Lines.Add('    LF_Notify,');
    Lines.Add(')');
    Lines.Add('from lingofuse.lf_io import cstr, write_string as _lf_write_string');
    Lines.Add('from lingofuse.core import DataHandle');
    Lines.Add('');
    Lines.Add('import ' + NormalizedUnit + '_abi_call as abi');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('REPORT_IDENTITY_API = ' + PyStrLit('LF_TEST_REPORT_SERVICE_IDENTITY'));
    Lines.Add('ASK_CALL_ME_API = ' + PyStrLit('LF_TEST_ASK_SERVICE_CALL_ME'));
    Lines.Add('WHOAMI_API = ' + PyStrLit('LF_TEST_WHOAMI'));
    Lines.Add('');
    Lines.Add('_G_PASS = 0');
    Lines.Add('_G_FAIL = 0');
    Lines.Add('_G_SKIP = 0');
    Lines.Add('_G_HAS_CLIENT_UID = False');
    Lines.Add('_G_CLIENT_UID = b"\\x00" * 32');
    Lines.Add('_G_CLIENT_P2P = ""');
    Lines.Add('_G_HAS_SERVICE_UID = False');
    Lines.Add('_G_SERVICE_UID = b"\\x00" * 32');
    Lines.Add('_G_SERVICE_P2P = ""');
    Lines.Add('_G_SERVICE_CALLED_ME = False');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _report_pass(label, value=""):');
    Lines.Add('    global _G_PASS');
    Lines.Add('    _G_PASS += 1');
    Lines.Add('    if value:');
    Lines.Add('        print("[PASS] %s = %s" % (label, value))');
    Lines.Add('    else:');
    Lines.Add('        print("[PASS] %s" % label)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _report_fail(label, reason):');
    Lines.Add('    global _G_FAIL');
    Lines.Add('    _G_FAIL += 1');
    Lines.Add('    print("[FAIL] %s -- %s" % (label, reason), file=sys.stderr)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _report_skip(label, reason):');
    Lines.Add('    global _G_SKIP');
    Lines.Add('    _G_SKIP += 1');
    Lines.Add('    print("[SKIP] %s -- %s" % (label, reason))');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('@LFCallFunc');
    Lines.Add('def cb_client_report_identity(_Trigger, _In, _Out):');
    Lines.Add('    global _G_HAS_SERVICE_UID, _G_SERVICE_UID, _G_SERVICE_P2P, _G_SERVICE_CALLED_ME');
    Lines.Add('    in_h = DataHandle._from_raw(_In, owned=False)');
    Lines.Add('    out_h = DataHandle._from_raw(_Out, owned=False)');
    Lines.Add('    try:');
    Lines.Add('        _G_SERVICE_UID = in_h.get_p2p_uid()');
    Lines.Add('        _G_SERVICE_P2P = in_h.get_p2p_name()');
    Lines.Add('        _G_HAS_SERVICE_UID = _G_SERVICE_UID != b"\\x00" * 32');
    Lines.Add('        _G_SERVICE_CALLED_ME = True');
    Lines.Add('    except Exception:');
    Lines.Add('        pass');
    Lines.Add('    try:');
    Lines.Add('        msg = in_h.read_string()');
    Lines.Add('    except Exception:');
    Lines.Add('        msg = ""');
    Lines.Add('    print("[CLIENT] service called me: msg=%r" % msg)');
    Lines.Add('    try:');
    Lines.Add('        out_h.write_string("identity received")');
    Lines.Add('    except Exception:');
    Lines.Add('        pass');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _probe_client_identity():');
    Lines.Add('    global _G_CLIENT_UID, _G_CLIENT_P2P, _G_HAS_CLIENT_UID');
    Lines.Add('    data = LF_CreateData(cstr(WHOAMI_API))');
    Lines.Add('    if not data:');
    Lines.Add('        return False');
    Lines.Add('    try:');
    Lines.Add('        res = abi.LF_Call(cstr(abi.ABI_TARGET_APP), data, 5000)');
    Lines.Add('        if not res:');
    Lines.Add('            return False');
    Lines.Add('        try:');
    Lines.Add('            if abi.LF_GetSize(res) < 33:');
    Lines.Add('                return False');
    Lines.Add('            abi.LF_SetPos(res, 0)');
    Lines.Add('            status = abi._read_uint8(res)');
    Lines.Add('            if status != 0:');
    Lines.Add('                return False');
    Lines.Add('            uid = abi._read_exact(res, 32)');
    Lines.Add('            p2p = abi._read_string(res)');
    Lines.Add('            _G_CLIENT_UID = uid');
    Lines.Add('            _G_CLIENT_P2P = p2p');
    Lines.Add('            _G_HAS_CLIENT_UID = uid != b"\\x00" * 32');
    Lines.Add('            print("[INFO] client UID = " + uid.hex())');
    Lines.Add('            print("[INFO] client P2P = " + p2p)');
    Lines.Add('            return _G_HAS_CLIENT_UID');
    Lines.Add('        finally:');
    Lines.Add('            abi.LF_FreeData(res)');
    Lines.Add('    finally:');
    Lines.Add('        LF_FreeData(data)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _test_service_initiates_call():');
    Lines.Add('    global _G_SERVICE_CALLED_ME, _G_HAS_SERVICE_UID, _G_SERVICE_UID, _G_SERVICE_P2P');
    Lines.Add('    _G_SERVICE_CALLED_ME = False');
    Lines.Add('    _G_HAS_SERVICE_UID = False');
    Lines.Add('    _G_SERVICE_UID = b"\\x00" * 32');
    Lines.Add('    _G_SERVICE_P2P = ""');
    Lines.Add('');
    Lines.Add('    data = LF_CreateData(cstr(ASK_CALL_ME_API))');
    Lines.Add('    if not data:');
    Lines.Add('        return False');
    Lines.Add('    try:');
    Lines.Add('        _lf_write_string(data, "service initiates call")');
    Lines.Add('        LF_Notify(cstr(abi.ABI_TARGET_APP), data)');
    Lines.Add('    finally:');
    Lines.Add('        LF_FreeData(data)');
    Lines.Add('');
    Lines.Add('    deadline = time.time() + 10.0');
    Lines.Add('    while time.time() < deadline:');
    Lines.Add('        if _G_SERVICE_CALLED_ME:');
    Lines.Add('            break');
    Lines.Add('        time.sleep(0.01)');
    Lines.Add('');
    Lines.Add('    return _G_SERVICE_CALLED_ME and _G_HAS_SERVICE_UID');
    Lines.Add('');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UsedApiNames[i];
      if SupportedFuncs[i].IsFunction then
        EmitFunctionTestPy(Lines, ApiName, SupportedFuncs[i])
      else
        EmitProcedureTestPy(Lines, ApiName, SupportedFuncs[i]);
    end;

    Lines.Add('def main():');
    Lines.Add('    print("=== ' + UnitName.Text + ' ABI client test ===")');
    Lines.Add('    endpoint = "ipc:" + abi.ABI_TARGET_APP');
    Lines.Add('');
    Lines.Add('    LF_ResetPrepare()');
    Lines.Add('');
    Lines.Add('    client_app = LF_CreateApp(cstr("LF_TEST_CLIENT_SELF"), cstr("client test app"))');
    Lines.Add('    if not client_app:');
    Lines.Add('        print("[FATAL] LF_CreateApp failed", file=sys.stderr)');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    if LF_RegisterCall(client_app, cstr(REPORT_IDENTITY_API), cstr("report service identity"), None, cb_client_report_identity) != 1:');
    Lines.Add('        print("[WARN] failed to register " + REPORT_IDENTITY_API, file=sys.stderr)');
    Lines.Add('');
    Lines.Add('    if LF_PrepareClient(cstr(endpoint), client_app) == -1:');
    Lines.Add('        print("[FATAL] LF_PrepareClient failed", file=sys.stderr)');
    Lines.Add('        LF_Shutdown()');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    if LF_PrepareDone() != 1:');
    Lines.Add('        print("[FATAL] LF_PrepareDone failed", file=sys.stderr)');
    Lines.Add('        LF_ExitMainThread()');
    Lines.Add('        LF_Shutdown()');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    print("[READY] Client online")');
    Lines.Add('    print()');
    Lines.Add('');
    Lines.Add('    if _probe_client_identity():');
    Lines.Add('        print("[OK] client identity probe")');
    Lines.Add('    else:');
    Lines.Add('        print("[WARN] whoami failed, UID tests will be skipped")');
    Lines.Add('');
    Lines.Add('    if _test_service_initiates_call():');
    Lines.Add('        print("[OK] service-initiated call")');
    Lines.Add('        print("[INFO] service UID = " + _G_SERVICE_UID.hex())');
    Lines.Add('        print("[INFO] service P2P = " + _G_SERVICE_P2P)');
    Lines.Add('    else:');
    Lines.Add('        _report_fail("service-initiated call", "timeout or no UID")');
    Lines.Add('');
    Lines.Add('    print()');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UsedApiNames[i];
      if SupportedFuncs[i].IsFunction then
        Lines.Add('    _test_' + ApiName + '_function()')
      else
        Lines.Add('    _test_' + ApiName + '_procedure()');
    end;

    Lines.Add('');
    Lines.Add('    print()');
    Lines.Add('    print("=== Summary ===")');
    Lines.Add('    print("Pass: %d" % _G_PASS)');
    Lines.Add('    print("Fail: %d" % _G_FAIL)');
    Lines.Add('    print("Skip: %d" % _G_SKIP)');
    Lines.Add('');
    Lines.Add('    LF_ExitMainThread()');
    Lines.Add('    LF_Shutdown()');
    Lines.Add('    return 0 if _G_FAIL == 0 else 2');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if __name__ == "__main__":');
    Lines.Add('    sys.exit(main())');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test.', [Lines.Count]));
  finally
    if Result = nil then
      Lines.Free;
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'python',
    'xxx_abi_service_test.py',
    gkTest,
    'Python ABI service test program',
    @GenerateABIServiceTestPyCode);

  RegisterGenerator(
    'python',
    'xxx_abi_call_test.py',
    gkTest,
    'Python ABI call test program',
    @GenerateABICallTestPyCode);

end.
