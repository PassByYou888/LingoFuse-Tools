unit rust_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestRsCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestRsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[rust_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[rust_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Rust_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'i32'
  else if T.Same('int64') then
    Result := 'i64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'u32'
  else if T.Same('word') then
    Result := 'u16'
  else if T.Same('smallint') then
    Result := 'i16'
  else if T.Same('byte') then
    Result := 'u8'
  else if T.Same('uint64') then
    Result := 'u64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'f64'
  else if T.Same('single') then
    Result := 'f32'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Rust_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function CStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
    begin
      Result.Append('\');
      Result.Append('"');
    end
    else if c = '\' then
    begin
      Result.Append('\');
      Result.Append('\');
    end
    else if c = #10 then
    begin
      Result.Append('\');
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append('\');
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append('\');
      Result.Append('t');
    end
    else
      Result.Append(c);
  end;
  Result.Append('"');
end;

function PlaceholderArg(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := CStrLit('test')
  else if ABIType.Same('double') or ABIType.Same('single') or
          ABIType.Same('extended') or ABIType.Same('real') then
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
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PlaceholderArg(Params[i].PascalType);
  end;
end;

function CombineCallArgs(const Prefix, Args: TP_String): TP_String;
begin
  if (Prefix = '') and (Args = '') then
    Result := ''
  else if Args = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Args
  else
    Result := Prefix + ', ' + Args;
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

function BuildUniqueApiNames(const Funcs: TArryFunctionStructure): TPascalStringList;
var
  i, j: integer;
  ApiName: TP_String;
begin
  Result := TPascalStringList.Create;
  for i := 0 to High(Funcs) do
  begin
    ApiName := MakeApiName(Funcs[i].Name);
    if Result.IndexOf(ApiName) >= 0 then
    begin
      j := 1;
      while Result.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      ApiName := ApiName + '_' + umlIntToStr(j).Text;
    end;
    Result.Add(ApiName);
  end;
end;

procedure EmitSyncTestBlock(Lines: TPascalStringList;
  const Label_, FuncName, Prefix, Args, RetType: TP_String;
  IsFunction: boolean);
var
  FullArgs, FullCall: TP_String;
begin
  FullArgs := CombineCallArgs(Prefix, Args);

  if FullArgs = '' then
    FullCall := 'call::' + FuncName + '()'
  else
    FullCall := 'call::' + FuncName + '(' + FullArgs + ')';

  if IsFunction then
  begin
    Lines.Add('    match ' + FullCall + ' {');
    Lines.Add('        Ok(v) => report_pass(' + CStrLit(Label_) + ', Some(describe_' + RetType + '(v))),');
    Lines.Add('        Err(e) => report_fail(' + CStrLit(Label_) + ', &format!("{}", e)),');
    Lines.Add('    }');
  end
  else
  begin
    Lines.Add('    match ' + FullCall + ' {');
    Lines.Add('        Ok(()) => report_pass(' + CStrLit(Label_) + ', None),');
    Lines.Add('        Err(e) => report_fail(' + CStrLit(Label_) + ', &format!("{}", e)),');
    Lines.Add('    }');
  end;
end;

procedure EmitAsyncTestBlock(Lines: TPascalStringList;
  const Label_, FuncName, Prefix, Args, RetType: TP_String);
var
  FullArgs, CbArg: TP_String;
begin
  CbArg := 'move |r| { let _ = tx.send(r); }';
  FullArgs := CombineCallArgs(Prefix, Args);
  if FullArgs = '' then
    FullArgs := CbArg
  else
    FullArgs := FullArgs + ', ' + CbArg;

  Lines.Add('    {');
  Lines.Add('        let (tx, rx) = mpsc::channel::<Result<' + RetType + ', Error>>();');
  Lines.Add('        match call::' + FuncName + '(' + FullArgs + ') {');
  Lines.Add('            Ok(()) => match rx.recv_timeout(Duration::from_secs(10)) {');
  Lines.Add('                Ok(Ok(v)) => report_pass(' + CStrLit(Label_) + ', Some(describe_' + RetType + '(v))),');
  Lines.Add('                Ok(Err(e)) => report_fail(' + CStrLit(Label_) + ', &format!("{}", e)),');
  Lines.Add('                Err(_) => report_fail(' + CStrLit(Label_) + ', "timeout"),');
  Lines.Add('            },');
  Lines.Add('            Err(e) => report_fail(' + CStrLit(Label_) + ', &format!("{}", e)),');
  Lines.Add('        }');
  Lines.Add('    }');
end;

procedure EmitGuardedSyncTest(Lines: TPascalStringList;
  const Label_, FuncName, Prefix, Args, RetType, SkipReason: TP_String;
  IsFunction: boolean);
begin
  Lines.Add('    if has_service_uid() {');
  EmitSyncTestBlock(Lines, Label_, FuncName, Prefix, Args, RetType, IsFunction);
  Lines.Add('    } else {');
  Lines.Add('        report_skip(' + CStrLit(Label_) + ', ' + CStrLit(SkipReason) + ');');
  Lines.Add('    }');
end;

procedure EmitGuardedAsyncTest(Lines: TPascalStringList;
  const Label_, FuncName, Prefix, Args, RetType, SkipReason: TP_String);
begin
  Lines.Add('    if has_service_uid() {');
  EmitAsyncTestBlock(Lines, Label_, FuncName, Prefix, Args, RetType);
  Lines.Add('    } else {');
  Lines.Add('        report_skip(' + CStrLit(Label_) + ', ' + CStrLit(SkipReason) + ');');
  Lines.Add('    }');
end;

procedure EmitFunctionTest(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  Args, RetType: TP_String;
begin
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);
  Args := BuildPlaceholderArgs(F.Params);

  Lines.Add('fn test_' + ApiName + '() {');

  EmitSyncTestBlock(Lines, ApiName + '(app call)', ApiName, '', Args, RetType, True);
  EmitGuardedSyncTest(Lines, ApiName + '(uid call)',
    ApiName + '_UID_Call', 'service_uid()', Args, RetType, 'no service UID', True);
  EmitSyncTestBlock(Lines, ApiName + '(p2pname call)',
    ApiName + '_P2PName_Call', 'target_p2p_name()', Args, RetType, True);

  EmitAsyncTestBlock(Lines, ApiName + '(app async)', ApiName + '_Async', '', Args, RetType);
  EmitAsyncTestBlock(Lines, ApiName + '(app async seq)', ApiName + '_AsyncSequenced', '', Args, RetType);
  EmitGuardedAsyncTest(Lines, ApiName + '(uid async)',
    ApiName + '_UID_Async', 'service_uid()', Args, RetType, 'no service UID');
  EmitGuardedAsyncTest(Lines, ApiName + '(uid async seq)',
    ApiName + '_UID_AsyncSequenced', 'service_uid()', Args, RetType, 'no service UID');
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname async)',
    ApiName + '_P2PName_Async', 'target_p2p_name()', Args, RetType);
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname async seq)',
    ApiName + '_P2PName_AsyncSequenced', 'target_p2p_name()', Args, RetType);

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcedureTest(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  Args, RetType: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);
  RetType := '';

  Lines.Add('fn test_' + ApiName + '() {');

  EmitSyncTestBlock(Lines, ApiName + '(app notify)', ApiName, '', Args, RetType, False);
  EmitSyncTestBlock(Lines, ApiName + '(app seq notify)',
    ApiName + '_SequencedNotify', '', Args, RetType, False);
  EmitGuardedSyncTest(Lines, ApiName + '(uid notify)',
    ApiName + '_UID_Notify', 'service_uid()', Args, RetType, 'no service UID', False);
  EmitGuardedSyncTest(Lines, ApiName + '(uid seq notify)',
    ApiName + '_UID_SequencedNotify', 'service_uid()', Args, RetType, 'no service UID', False);
  EmitSyncTestBlock(Lines, ApiName + '(p2pname notify)',
    ApiName + '_P2PName_Notify', 'target_p2p_name()', Args, RetType, False);
  EmitSyncTestBlock(Lines, ApiName + '(p2pname seq notify)',
    ApiName + '_P2PName_SequencedNotify', 'target_p2p_name()', Args, RetType, False);

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitDescribeHelpers(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure);
var
  SeenTypes: TPascalStringList;
  i: integer;
  T: TP_String;
begin
  SeenTypes := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      if not SupportedFuncs[i].IsFunction then
        Continue;
      T := ABI_Type_To_Rust_Decl(SupportedFuncs[i].ReturnType);
      if T = '' then
        Continue;
      if SeenTypes.IndexOf(T) >= 0 then
        Continue;
      SeenTypes.Add(T);

      if IsStringABIType(SupportedFuncs[i].ReturnType) then
      begin
        Lines.Add('fn describe_' + T + '(v: ' + T + ') -> String { v }');
      end
      else
      begin
        Lines.Add('fn describe_' + T + '(v: ' + T + ') -> String { format!("{}", v) }');
      end;
    end;
  finally
    SeenTypes.Free;
  end;
  Lines.Add('');
end;

function GenerateABIServiceTestRsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, P2PName, Endpoint: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestRsCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestRsCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + AppName;

  Log(PFormat('Generating Rust ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('#![allow(non_snake_case)]');
    Lines.Add('#![allow(dead_code)]');
    Lines.Add('');
    Lines.Add('use std::io::Read;');
    Lines.Add('');
    Lines.Add('use lingofuse::data_handle::DataHandle;');
    Lines.Add('use lingofuse::framework;');
    Lines.Add('use lingofuse::io;');
    Lines.Add('use lingofuse::options;');
    Lines.Add('use lingofuse::p2p;');
    Lines.Add('');
    Lines.Add('use ' + NormalizedUnit + '_abi::service;');
    Lines.Add('');
    Lines.Add('const DEFAULT_ENDPOINT: &' + #39 + 'static str = ' + CStrLit(Endpoint) + ';');
    Lines.Add('const DEFAULT_APP_NAME: &' + #39 + 'static str = ' + CStrLit(AppName) + ';');
    Lines.Add('const DEFAULT_P2P_NAME: &' + #39 + 'static str = ' + CStrLit(P2PName) + ';');
    Lines.Add('const WHOAMI_API: &' + #39 + 'static str = "LF_TEST_WHOAMI";');
    Lines.Add('const ASK_CALL_ME_API: &' + #39 + 'static str = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('const REPORT_IDENTITY_API: &' + #39 + 'static str = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('');
    Lines.Add('fn cb_whoami(input: &mut DataHandle, output: &mut DataHandle) {');
    Lines.Add('    let uid = input.p2p_uid().unwrap_or_default();');
    Lines.Add('    let p2p = input.p2p_name().unwrap_or_default();');
    Lines.Add('    println!("[SERVICE] whoami: p2p={}", p2p);');
    Lines.Add('');
    Lines.Add('    let mut buf: Vec<u8> = Vec::with_capacity(1 + 32 + p2p.len() + 1);');
    Lines.Add('    buf.push(0x00);');
    Lines.Add('    buf.extend_from_slice(&uid.to_bytes());');
    Lines.Add('    buf.extend_from_slice(p2p.as_bytes());');
    Lines.Add('    buf.push(0);');
    Lines.Add('    let _ = output.write_bytes(&buf);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn cb_ask_call_me(input: &mut DataHandle) {');
    Lines.Add('    let uid = match input.p2p_uid() {');
    Lines.Add('        Ok(v) => v,');
    Lines.Add('        Err(_) => return,');
    Lines.Add('    };');
    Lines.Add('    if uid.is_null() {');
    Lines.Add('        eprintln!("[SERVICE] ask_call_me: no UID");');
    Lines.Add('        return;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    let mut req = match DataHandle::new(REPORT_IDENTITY_API) {');
    Lines.Add('        Ok(h) => h,');
    Lines.Add('        Err(_) => return,');
    Lines.Add('    };');
    Lines.Add('    let _ = io::write_string(&mut req, "service initiates call");');
    Lines.Add('    let _ = req.set_position(0);');
    Lines.Add('');
    Lines.Add('    match framework::call_by_uid(uid, &req, 5000) {');
    Lines.Add('        Ok(resp) if resp.size().unwrap_or(0) > 0 => {');
    Lines.Add('            println!("[SERVICE] ask_call_me: client responded ok");');
    Lines.Add('        }');
    Lines.Add('        _ => {');
    Lines.Add('            println!("[SERVICE] ask_call_me: client did not respond");');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn main() -> Result<(), Box<dyn std::error::Error>> {');
    Lines.Add('    println!("=== ' + UnitName.Text + ' ABI service test ===");');
    Lines.Add('');
    Lines.Add('    options::set_quiet(true)?;');
    Lines.Add('    options::set_overlap_connection(true)?;');
    Lines.Add('    options::set_wait_connection_ready_ok(false)?;');
    Lines.Add('');
    Lines.Add('    framework::reset_prepare();');
    Lines.Add('    framework::prepare_service(DEFAULT_ENDPOINT, DEFAULT_ENDPOINT)?;');
    Lines.Add('');
    Lines.Add('    let app = service::create_and_register_abi_app()?;');
    Lines.Add('    app.register_call(WHOAMI_API, "service-side whoami helper", cb_whoami)?;');
    Lines.Add('    app.register_notify(ASK_CALL_ME_API, "ask service to call back client", cb_ask_call_me)?;');
    Lines.Add('');
    Lines.Add('    options::set_p2p_name(DEFAULT_P2P_NAME)?;');
    Lines.Add('    service::register_all_p2p_abi_apis()?;');
    Lines.Add('    p2p::register_p2p_call(WHOAMI_API, "service-side whoami helper", cb_whoami)?;');
    Lines.Add('    p2p::register_p2p_notify(ASK_CALL_ME_API, "ask service to call back client", cb_ask_call_me)?;');
    Lines.Add('');
    Lines.Add('    framework::prepare_client(DEFAULT_ENDPOINT, Some(&app))?;');
    Lines.Add('    if !framework::prepare_done()? {');
    Lines.Add('        return Err("prepare_done returned false".into());');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    println!("[OK] Service ready on {}", DEFAULT_ENDPOINT);');
    Lines.Add('    println!("[OK] App: {}", DEFAULT_APP_NAME);');
    Lines.Add('    println!("[OK] P2P: {}", DEFAULT_P2P_NAME);');
    Lines.Add('    println!("[OK] Press Enter to shut down");');
    Lines.Add('');
    Lines.Add('    let _ = std::io::stdin().read(&mut [0u8]);');
    Lines.Add('');
    Lines.Add('    drop(app);');
    Lines.Add('    framework::exit_main_thread();');
    Lines.Add('    framework::shutdown();');
    Lines.Add('    Ok(())');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Rust ABI service test', [Lines.Count]));
  finally
  end;
end;

function GenerateABICallTestRsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList;
  UnitName, NormalizedUnit, TargetApp, TargetP2P, Endpoint: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestRsCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestRsCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';
  TargetP2P := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + TargetApp;

  Log(PFormat('Generating Rust ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call test exercises %d ABI APIs', [Length(SupportedFuncs)]));

  ApiNames := BuildUniqueApiNames(SupportedFuncs);
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#![allow(non_snake_case)]');
    Lines.Add('#![allow(dead_code)]');
    Lines.Add('#![allow(unused_imports)]');
    Lines.Add('');
    Lines.Add('use std::sync::mpsc;');
    Lines.Add('use std::sync::{Mutex, OnceLock};');
    Lines.Add('use std::time::Duration;');
    Lines.Add('');
    Lines.Add('use lingofuse::app_handle::AppHandle;');
    Lines.Add('use lingofuse::data_handle::DataHandle;');
    Lines.Add('use lingofuse::error::Error;');
    Lines.Add('use lingofuse::framework;');
    Lines.Add('use lingofuse::io;');
    Lines.Add('use lingofuse::options;');
    Lines.Add('use lingofuse::uid::Uid;');
    Lines.Add('');
    Lines.Add('use ' + NormalizedUnit + '_abi::call;');
    Lines.Add('');
    Lines.Add('const DEFAULT_ENDPOINT: &' + #39 + 'static str = ' + CStrLit(Endpoint) + ';');
    Lines.Add('const DEFAULT_TARGET_APP: &' + #39 + 'static str = ' + CStrLit(TargetApp) + ';');
    Lines.Add('const DEFAULT_TARGET_P2P: &' + #39 + 'static str = ' + CStrLit(TargetP2P) + ';');
    Lines.Add('const CLIENT_APP_NAME: &' + #39 + 'static str = "LF_TEST_CLIENT_SELF";');
    Lines.Add('const WHOAMI_API: &' + #39 + 'static str = "LF_TEST_WHOAMI";');
    Lines.Add('const ASK_CALL_ME_API: &' + #39 + 'static str = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('const REPORT_IDENTITY_API: &' + #39 + 'static str = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('');
    Lines.Add('struct TestState {');
    Lines.Add('    pass: usize,');
    Lines.Add('    fail: usize,');
    Lines.Add('    skip: usize,');
    Lines.Add('    service_uid: Uid,');
    Lines.Add('    service_p2p: String,');
    Lines.Add('    has_service_uid: bool,');
    Lines.Add('    service_called_me: bool,');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('impl TestState {');
    Lines.Add('    fn new() -> Self {');
    Lines.Add('        Self {');
    Lines.Add('            pass: 0,');
    Lines.Add('            fail: 0,');
    Lines.Add('            skip: 0,');
    Lines.Add('            service_uid: Uid::NULL,');
    Lines.Add('            service_p2p: String::new(),');
    Lines.Add('            has_service_uid: false,');
    Lines.Add('            service_called_me: false,');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn state() -> &' + #39 + 'static Mutex<TestState> {');
    Lines.Add('    static S: OnceLock<Mutex<TestState>> = OnceLock::new();');
    Lines.Add('    S.get_or_init(|| Mutex::new(TestState::new()))');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn has_service_uid() -> bool {');
    Lines.Add('    state().lock().unwrap().has_service_uid');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn service_uid() -> Uid {');
    Lines.Add('    state().lock().unwrap().service_uid');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn target_p2p_name() -> &' + #39 + 'static str {');
    Lines.Add('    DEFAULT_TARGET_P2P');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn report_pass(label: &str, value: Option<String>) {');
    Lines.Add('    {');
    Lines.Add('        let mut s = state().lock().unwrap();');
    Lines.Add('        s.pass += 1;');
    Lines.Add('    }');
    Lines.Add('    match value {');
    Lines.Add('        Some(v) => println!("[PASS] {} = {}", label, v),');
    Lines.Add('        None => println!("[PASS] {}", label),');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn report_fail(label: &str, reason: &str) {');
    Lines.Add('    {');
    Lines.Add('        let mut s = state().lock().unwrap();');
    Lines.Add('        s.fail += 1;');
    Lines.Add('    }');
    Lines.Add('    eprintln!("[FAIL] {} -- {}", label, reason);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn report_skip(label: &str, reason: &str) {');
    Lines.Add('    {');
    Lines.Add('        let mut s = state().lock().unwrap();');
    Lines.Add('        s.skip += 1;');
    Lines.Add('    }');
    Lines.Add('    println!("[SKIP] {} -- {}", label, reason);');
    Lines.Add('}');
    Lines.Add('');
    EmitDescribeHelpers(Lines, SupportedFuncs);

    Lines.Add('fn cb_report_service_identity(input: &mut DataHandle, output: &mut DataHandle) {');
    Lines.Add('    let uid = input.p2p_uid().unwrap_or_default();');
    Lines.Add('    let p2p = input.p2p_name().unwrap_or_default();');
    Lines.Add('    {');
    Lines.Add('        let mut s = state().lock().unwrap();');
    Lines.Add('        s.service_uid = uid;');
    Lines.Add('        s.service_p2p = p2p.clone();');
    Lines.Add('        s.has_service_uid = !uid.is_null();');
    Lines.Add('        s.service_called_me = true;');
    Lines.Add('    }');
    Lines.Add('    let mut msg = String::new();');
    Lines.Add('    let _ = input.read_string().map(|v| msg = v);');
    Lines.Add('    println!("[CLIENT] service called me: msg={}", msg);');
    Lines.Add('    let _ = io::write_string(output, "identity received");');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn probe_client_identity() -> bool {');
    Lines.Add('    let mut req = match DataHandle::new(WHOAMI_API) {');
    Lines.Add('        Ok(h) => h,');
    Lines.Add('        Err(_) => return false,');
    Lines.Add('    };');
    Lines.Add('    let _ = io::write_string(&mut req, "");');
    Lines.Add('    let _ = req.set_position(0);');
    Lines.Add('');
    Lines.Add('    let mut resp = match framework::call(DEFAULT_TARGET_APP, &req, 10000) {');
    Lines.Add('        Ok(r) => r,');
    Lines.Add('        Err(e) => {');
    Lines.Add('            eprintln!("[WARN] whoami failed: {}", e);');
    Lines.Add('            return false;');
    Lines.Add('        }');
    Lines.Add('    };');
    Lines.Add('    if resp.size().unwrap_or(0) < 34 {');
    Lines.Add('        return false;');
    Lines.Add('    }');
    Lines.Add('    let _ = resp.set_position(0);');
    Lines.Add('    let status = resp.read::<u8>().unwrap_or(0xff);');
    Lines.Add('    if status != 0x00 {');
    Lines.Add('        return false;');
    Lines.Add('    }');
    Lines.Add('    let uid_bytes = match resp.read_bytes_exact(32) {');
    Lines.Add('        Ok(v) => v,');
    Lines.Add('        Err(_) => return false,');
    Lines.Add('    };');
    Lines.Add('    let mut arr = [0u8; 32];');
    Lines.Add('    arr.copy_from_slice(&uid_bytes);');
    Lines.Add('    let client_uid = Uid::from_bytes(arr);');
    Lines.Add('    let client_p2p = resp.read_string().unwrap_or_default();');
    Lines.Add('    let has_uid = !client_uid.is_null();');
    Lines.Add('    println!("[INFO] client UID = {}", client_uid.to_hex());');
    Lines.Add('    println!("[INFO] client P2P = {}", client_p2p);');
    Lines.Add('    has_uid');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn test_service_initiates_call() -> bool {');
    Lines.Add('    {');
    Lines.Add('        let mut s = state().lock().unwrap();');
    Lines.Add('        s.service_called_me = false;');
    Lines.Add('        s.has_service_uid = false;');
    Lines.Add('        s.service_uid = Uid::NULL;');
    Lines.Add('        s.service_p2p.clear();');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    let mut req = match DataHandle::new(ASK_CALL_ME_API) {');
    Lines.Add('        Ok(h) => h,');
    Lines.Add('        Err(_) => return false,');
    Lines.Add('    };');
    Lines.Add('    let _ = io::write_string(&mut req, REPORT_IDENTITY_API);');
    Lines.Add('    let _ = req.set_position(0);');
    Lines.Add('    if framework::notify(DEFAULT_TARGET_APP, &req).is_err() {');
    Lines.Add('        return false;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    for _ in 0..1000 {');
    Lines.Add('        {');
    Lines.Add('            let s = state().lock().unwrap();');
    Lines.Add('            if s.service_called_me {');
    Lines.Add('                return s.has_service_uid;');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('        std::thread::sleep(Duration::from_millis(10));');
    Lines.Add('    }');
    Lines.Add('    false');
    Lines.Add('}');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if not F.IsFunction then
        Continue;
      EmitFunctionTest(Lines, ApiNames[i], F);
    end;

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        Continue;
      EmitProcedureTest(Lines, ApiNames[i], F);
    end;

    Lines.Add('fn main() -> Result<(), Box<dyn std::error::Error>> {');
    Lines.Add('    println!("=== ' + UnitName.Text + ' ABI client test ===");');
    Lines.Add('');
    Lines.Add('    options::set_quiet(true)?;');
    Lines.Add('    options::set_overlap_connection(true)?;');
    Lines.Add('    options::set_wait_connection_ready_ok(false)?;');
    Lines.Add('');
    Lines.Add('    framework::reset_prepare();');
    Lines.Add('    framework::prepare_service(DEFAULT_ENDPOINT, DEFAULT_ENDPOINT)?;');
    Lines.Add('');
    Lines.Add('    let client_app = AppHandle::new(CLIENT_APP_NAME, "client test app")?;');
    Lines.Add('    client_app.register_call(REPORT_IDENTITY_API, "report service identity", cb_report_service_identity)?;');
    Lines.Add('');
    Lines.Add('    framework::prepare_client(DEFAULT_ENDPOINT, Some(&client_app))?;');
    Lines.Add('    if !framework::prepare_done()? {');
    Lines.Add('        return Err("prepare_done returned false".into());');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    println!("[READY] Client online");');
    Lines.Add('');
    Lines.Add('    let mut ready = false;');
    Lines.Add('    for _ in 0..30 {');
    Lines.Add('        if framework::check_api(DEFAULT_TARGET_APP, WHOAMI_API).unwrap_or(false) {');
    Lines.Add('            ready = true;');
    Lines.Add('            break;');
    Lines.Add('        }');
    Lines.Add('        std::thread::sleep(Duration::from_millis(200));');
    Lines.Add('    }');
    Lines.Add('    if !ready {');
    Lines.Add('        eprintln!("[WARN] Target service not ready on the mesh");');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if probe_client_identity() {');
    Lines.Add('        println!("[OK] client identity probe");');
    Lines.Add('    } else {');
    Lines.Add('        println!("[WARN] whoami failed, UID tests will be skipped");');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if test_service_initiates_call() {');
    Lines.Add('        println!("[OK] service-initiated call");');
    Lines.Add('        {');
    Lines.Add('            let s = state().lock().unwrap();');
    Lines.Add('            println!("[INFO] service UID = {}", s.service_uid.to_hex());');
    Lines.Add('            println!("[INFO] service P2P = {}", s.service_p2p);');
    Lines.Add('        }');
    Lines.Add('    } else {');
    Lines.Add('        report_fail("service-initiated call", "timeout or no UID");');
    Lines.Add('    }');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      Lines.Add('    test_' + ApiNames[i] + '();');

    Lines.Add('');
    Lines.Add('    let (pass, fail, skip) = {');
    Lines.Add('        let s = state().lock().unwrap();');
    Lines.Add('        (s.pass, s.fail, s.skip)');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    println!();');
    Lines.Add('    println!("=== Summary ===");');
    Lines.Add('    println!("Pass: {}", pass);');
    Lines.Add('    println!("Fail: {}", fail);');
    Lines.Add('    println!("Skip: {}", skip);');
    Lines.Add('');
    Lines.Add('    drop(client_app);');
    Lines.Add('    framework::exit_main_thread();');
    Lines.Add('    framework::shutdown();');
    Lines.Add('');
    Lines.Add('    if fail == 0 {');
    Lines.Add('        Ok(())');
    Lines.Add('    } else {');
    Lines.Add('        std::process::exit(2);');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Rust ABI call test', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'rust',
    'xxx_abi_service_test.rs',
    gkTest,
    'Rust ABI service test program',
    @GenerateABIServiceTestRsCode);

  RegisterGenerator(
    'rust',
    'xxx_abi_call_test.rs',
    gkTest,
    'Rust ABI call test program',
    @GenerateABICallTestRsCode);

end.
