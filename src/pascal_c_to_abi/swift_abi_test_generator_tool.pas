unit swift_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestSwiftCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[swift_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[swift_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Swift_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'Int32'
  else if T.Same('int64') then
    Result := 'Int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'UInt32'
  else if T.Same('word') then
    Result := 'UInt16'
  else if T.Same('smallint') then
    Result := 'Int16'
  else if T.Same('byte') then
    Result := 'UInt8'
  else if T.Same('uint64') then
    Result := 'UInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'Double'
  else if T.Same('single') then
    Result := 'Float'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Swift_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsSwiftKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('associatedtype') or S.Same('class') or S.Same('deinit') or
    S.Same('enum') or S.Same('extension') or S.Same('fileprivate') or
    S.Same('func') or S.Same('import') or S.Same('init') or
    S.Same('inout') or S.Same('internal') or S.Same('let') or
    S.Same('open') or S.Same('operator') or S.Same('private') or
    S.Same('protocol') or S.Same('public') or S.Same('rethrows') or
    S.Same('static') or S.Same('struct') or S.Same('subscript') or
    S.Same('typealias') or S.Same('var') or
    S.Same('break') or S.Same('case') or S.Same('continue') or
    S.Same('default') or S.Same('defer') or S.Same('do') or
    S.Same('else') or S.Same('fallthrough') or S.Same('for') or
    S.Same('guard') or S.Same('if') or S.Same('in') or
    S.Same('repeat') or S.Same('return') or S.Same('switch') or
    S.Same('where') or S.Same('while') or
    S.Same('as') or S.Same('Any') or S.Same('catch') or
    S.Same('false') or S.Same('is') or S.Same('nil') or
    S.Same('super') or S.Same('self') or S.Same('Self') or S.Same('throw') or
    S.Same('throws') or S.Same('true') or S.Same('try');
end;

function MakeSafeSwiftFuncName(const Name: TP_String): TP_String;
begin
  Result := Name;
  if (Result.Len > 0) and IsSwiftKeyword(Result) then
    Result := Result + '_';
end;

function SwiftStrLit(const S: TP_String): TP_String;
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

function SwiftPlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := '"test"'
  else if ABIType.Same('single') then
    Result := 'Float(3.14)'
  else if ABIType.Same('double') or ABIType.Same('extended') or ABIType.Same('real') then
    Result := '3.14'
  else if ABIType.Same('int64') then
    Result := 'Int64(42)'
  else if ABIType.Same('uint64') then
    Result := 'UInt64(42)'
  else if ABIType.Same('integer') or ABIType.Same('longint') then
    Result := 'Int32(42)'
  else if ABIType.Same('cardinal') or ABIType.Same('dword') or ABIType.Same('longword') then
    Result := 'UInt32(42)'
  else if ABIType.Same('word') then
    Result := 'UInt16(42)'
  else if ABIType.Same('smallint') then
    Result := 'Int16(42)'
  else if ABIType.Same('byte') then
    Result := 'UInt8(42)'
  else
    Result := '42';
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

function AssignUniqueApiNames(const Funcs: TArryFunctionStructure): TPascalStringList;
var
  i, j: integer;
  ApiName: TP_String;
begin
  Result := TPascalStringList.Create;
  for i := 0 to High(Funcs) do
  begin
    ApiName := MakeSafeSwiftFuncName(MakeApiName(Funcs[i].Name));
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

function BuildPlaceholderArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + SwiftPlaceholderValue(Params[i].PascalType);
  end;
end;

function JoinArgs(const Prefix, Args: TP_String): TP_String;
begin
  if Args = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Args
  else
    Result := Prefix + ', ' + Args;
end;

function GenerateABIServiceTestSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, EnumName, AppName, P2PName, Endpoint: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestSwiftCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestSwiftCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  EnumName := NormalizedUnit + 'ABIService';
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + AppName;

  Log(PFormat('Generating Swift ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('import Foundation');
    Lines.Add('import LingoFuse');
    Lines.Add('import ' + NormalizedUnit + '_abi_service');
    Lines.Add('');
    Lines.Add('let SERVICE_TEST_ENDPOINT: String = ' + SwiftStrLit(Endpoint));
    Lines.Add('let SERVICE_TEST_P2P_NAME: String = ' + SwiftStrLit(P2PName));
    Lines.Add('let SERVICE_TEST_WHOAMI_API: String = "LF_TEST_WHOAMI"');
    Lines.Add('let SERVICE_TEST_ASK_CALL_ME_API: String = "LF_TEST_ASK_SERVICE_CALL_ME"');
    Lines.Add('let SERVICE_TEST_REPORT_IDENTITY_API: String = "LF_TEST_REPORT_SERVICE_IDENTITY"');
    Lines.Add('');
    Lines.Add('func serviceTestCbWhoAmI(_ input: DataHandle, _ output: DataHandle) {');
    Lines.Add('    let uid = input.p2pUid()');
    Lines.Add('    let p2p = input.p2pName()');
    Lines.Add('    try? output.writeUInt8(0x00)');
    Lines.Add('    try? output.writeBytes(uid.rawBytes)');
    Lines.Add('    try? output.writeString(p2p)');
    Lines.Add('    print("[SERVICE] whoami: p2p=\(p2p)")');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func serviceTestCbAskCallMe(_ input: DataHandle) {');
    Lines.Add('    let uid = input.p2pUid()');
    Lines.Add('    if uid.isNull {');
    Lines.Add('        print("[SERVICE] ask_call_me: no UID")');
    Lines.Add('        return');
    Lines.Add('    }');
    Lines.Add('    do {');
    Lines.Add('        let param = try DataHandle(apiName: SERVICE_TEST_REPORT_IDENTITY_API)');
    Lines.Add('        defer { param.dispose() }');
    Lines.Add('        try param.writeString("service initiates call")');
    Lines.Add('        param.position = 0');
    Lines.Add('        let resp = try Framework.callByUid(uid, param, timeoutMs: 5000)');
    Lines.Add('        resp.dispose()');
    Lines.Add('        print("[SERVICE] ask_call_me: client responded ok")');
    Lines.Add('    } catch {');
    Lines.Add('        print("[SERVICE] ask_call_me: client did not respond \(error)")');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func serviceTestRun() -> Int32 {');
    Lines.Add('    var app: AppHandle? = nil');
    Lines.Add('    do {');
    Lines.Add('        Framework.setOption("Wait_Connection_ReadyOk", "False")');
    Lines.Add('        Framework.setOption("Overlap_Connection", "True")');
    Lines.Add('        Framework.setOption("ConsoleOutput", "True")');
    Lines.Add('        Options.setQuiet(true)');
    Lines.Add('        Framework.resetPrepare()');
    Lines.Add('        try Framework.prepareService(listeningAddr: SERVICE_TEST_ENDPOINT, physicsAddr: SERVICE_TEST_ENDPOINT)');
    Lines.Add('        let createdApp = try ' + EnumName + '.createAndRegisterABIApp()');
    Lines.Add('        app = createdApp');
    Lines.Add('        try createdApp.registerCall(SERVICE_TEST_WHOAMI_API, "whoami", serviceTestCbWhoAmI)');
    Lines.Add('        try createdApp.registerNotify(SERVICE_TEST_ASK_CALL_ME_API, "ask service to call back client", serviceTestCbAskCallMe)');
    Lines.Add('        Options.setP2PName(SERVICE_TEST_P2P_NAME)');
    Lines.Add('        try ' + EnumName + '.registerAllP2PABIAPIs()');
    Lines.Add('        try P2P.registerCall(SERVICE_TEST_WHOAMI_API, description: "whoami", handler: serviceTestCbWhoAmI)');
    Lines.Add('        try P2P.registerNotify(SERVICE_TEST_ASK_CALL_ME_API, description: "ask", handler: serviceTestCbAskCallMe)');
    Lines.Add('        try Framework.prepareClient(physicsAddr: SERVICE_TEST_ENDPOINT, app: createdApp)');
    Lines.Add('        if !Framework.prepareDone() {');
    Lines.Add('            FileHandle.standardError.write("[FATAL] prepareDone failed\n".data(using: .utf8)!)');
    Lines.Add('            Framework.exitMainThread()');
    Lines.Add('            createdApp.dispose()');
    Lines.Add('            Framework.shutdown()');
    Lines.Add('            return 1');
    Lines.Add('        }');
    Lines.Add('        print("[OK] Service ready on \(SERVICE_TEST_ENDPOINT)")');
    Lines.Add('        print("[OK] App: ' + AppName.Text + '")');
    Lines.Add('        print("[OK] P2P: \(SERVICE_TEST_P2P_NAME)")');
    Lines.Add('        print("[OK] Press Enter to shut down")');
    Lines.Add('        _ = readLine()');
    Lines.Add('        Framework.exitMainThread()');
    Lines.Add('        createdApp.dispose()');
    Lines.Add('        Framework.shutdown()');
    Lines.Add('        return 0');
    Lines.Add('    } catch {');
    Lines.Add('        FileHandle.standardError.write("[FATAL] service test: \(error)\n".data(using: .utf8)!)');
    Lines.Add('        Framework.exitMainThread()');
    Lines.Add('        if let a = app { a.dispose() }');
    Lines.Add('        Framework.shutdown()');
    Lines.Add('        return 1');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('print("=== ' + UnitName.Text + ' ABI service test ===")');
    Lines.Add('if LF_LoadLibrary() != 1 {');
    Lines.Add('    FileHandle.standardError.write("[FATAL] LF_LoadLibrary failed\n".data(using: .utf8)!)');
    Lines.Add('    exit(1)');
    Lines.Add('}');
    Lines.Add('let SERVICE_TEST_EXIT_CODE: Int32 = serviceTestRun()');
    Lines.Add('LF_FreeLibrary()');
    Lines.Add('if SERVICE_TEST_EXIT_CODE != 0 { exit(SERVICE_TEST_EXIT_CODE) }');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the Swift ABI service test', [Lines.Count]));
  finally
  end;
end;

procedure EmitTestFunctionHeader(Lines: TPascalStringList; const ApiName: TP_String);
begin
  Lines.Add('func test_' + ApiName + '() {');
end;

procedure EmitTestFunctionFooter(Lines: TPascalStringList);
begin
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSyncCallTest(Lines: TPascalStringList;
  const EnumName, ApiName, CallExpr, Label_, Args, ExtraPrefix: TP_String);
var
  FullArgs: TP_String;
begin
  FullArgs := JoinArgs(ExtraPrefix, Args);
  Lines.Add('    do {');
  if FullArgs = '' then
    Lines.Add('        let r = try ' + CallExpr + '()')
  else
    Lines.Add('        let r = try ' + CallExpr + '(' + FullArgs + ')');
  Lines.Add('        reportPass(' + SwiftStrLit(Label_) + ', "\(r)")');
  Lines.Add('    } catch {');
  Lines.Add('        reportFail(' + SwiftStrLit(Label_) + ', "\(error)")');
  Lines.Add('    }');
end;

procedure EmitAsyncCallTest(Lines: TPascalStringList;
  const EnumName, ApiName, CallExpr, Label_, Args, ExtraPrefix: TP_String);
var
  FullArgs: TP_String;
begin
  FullArgs := JoinArgs(ExtraPrefix, Args);
  Lines.Add('    switch runAsyncWithSema(' + SwiftStrLit(Label_) + ', {');
  if FullArgs = '' then
    Lines.Add('        try await ' + CallExpr + '()')
  else
    Lines.Add('        try await ' + CallExpr + '(' + FullArgs + ')');
  Lines.Add('    }) {');
  Lines.Add('    case .success(let v): reportPass(' + SwiftStrLit(Label_) + ', "\(v)")');
  Lines.Add('    case .failure(let e): reportFail(' + SwiftStrLit(Label_) + ', "\(e)")');
  Lines.Add('    }');
end;

procedure EmitSyncNotifyTest(Lines: TPascalStringList;
  const CallExpr, Label_, Args, ExtraPrefix: TP_String);
var
  FullArgs: TP_String;
begin
  FullArgs := JoinArgs(ExtraPrefix, Args);
  Lines.Add('    do {');
  if FullArgs = '' then
    Lines.Add('        try ' + CallExpr + '()')
  else
    Lines.Add('        try ' + CallExpr + '(' + FullArgs + ')');
  Lines.Add('        reportPass(' + SwiftStrLit(Label_) + ')');
  Lines.Add('    } catch {');
  Lines.Add('        reportFail(' + SwiftStrLit(Label_) + ', "\(error)")');
  Lines.Add('    }');
end;

procedure EmitFunctionTestBody(Lines: TPascalStringList;
  const EnumName, ApiName: TP_String; const F: TFunctionStructure);
var
  Args, CallBase: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);
  CallBase := EnumName + '.' + ApiName;

  EmitSyncCallTest(Lines, EnumName, ApiName,
    CallBase, ApiName + '(app call)', Args, '');
  Lines.Add('');

  EmitAsyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_Async', ApiName + '(app async)', Args, '');
  Lines.Add('');

  EmitAsyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_AsyncSequenced', ApiName + '(app asyncSeq)', Args, '');
  Lines.Add('');

  Lines.Add('    let hasUID: Bool = {');
  Lines.Add('        stateLock.lock()');
  Lines.Add('        defer { stateLock.unlock() }');
  Lines.Add('        return hasServiceUID');
  Lines.Add('    }()');
  Lines.Add('    let currentUID: Uid = {');
  Lines.Add('        stateLock.lock()');
  Lines.Add('        defer { stateLock.unlock() }');
  Lines.Add('        return serviceUID');
  Lines.Add('    }()');
  Lines.Add('');

  Lines.Add('    if hasUID {');
  EmitSyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_UID_Call', ApiName + '(uid call)', Args, 'currentUID');
  Lines.Add('');
  EmitAsyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_UID_Async', ApiName + '(uid async)', Args, 'currentUID');
  Lines.Add('');
  EmitAsyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_UID_AsyncSequenced', ApiName + '(uid asyncSeq)', Args, 'currentUID');
  Lines.Add('    } else {');
  Lines.Add('        reportSkip(' + SwiftStrLit(ApiName + '(uid call)') + ', "no service UID")');
  Lines.Add('        reportSkip(' + SwiftStrLit(ApiName + '(uid async)') + ', "no service UID")');
  Lines.Add('        reportSkip(' + SwiftStrLit(ApiName + '(uid asyncSeq)') + ', "no service UID")');
  Lines.Add('    }');
  Lines.Add('');

  EmitSyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_P2PName_Call', ApiName + '(p2pname call)', Args, 'targetP2PName');
  Lines.Add('');

  EmitAsyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_P2PName_Async', ApiName + '(p2pname async)', Args, 'targetP2PName');
  Lines.Add('');

  EmitAsyncCallTest(Lines, EnumName, ApiName,
    CallBase + '_P2PName_AsyncSequenced', ApiName + '(p2pname asyncSeq)', Args, 'targetP2PName');
end;

procedure EmitProcedureTestBody(Lines: TPascalStringList;
  const EnumName, ApiName: TP_String; const F: TFunctionStructure);
var
  Args, CallBase: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);
  CallBase := EnumName + '.' + ApiName;

  EmitSyncNotifyTest(Lines,
    CallBase, ApiName + '(app notify)', Args, '');
  Lines.Add('');

  EmitSyncNotifyTest(Lines,
    CallBase + '_SequencedNotify', ApiName + '(app seq notify)', Args, '');
  Lines.Add('');

  Lines.Add('    let hasUID: Bool = {');
  Lines.Add('        stateLock.lock()');
  Lines.Add('        defer { stateLock.unlock() }');
  Lines.Add('        return hasServiceUID');
  Lines.Add('    }()');
  Lines.Add('    let currentUID: Uid = {');
  Lines.Add('        stateLock.lock()');
  Lines.Add('        defer { stateLock.unlock() }');
  Lines.Add('        return serviceUID');
  Lines.Add('    }()');
  Lines.Add('');

  Lines.Add('    if hasUID {');
  EmitSyncNotifyTest(Lines,
    CallBase + '_UID_Notify', ApiName + '(uid notify)', Args, 'currentUID');
  Lines.Add('');
  EmitSyncNotifyTest(Lines,
    CallBase + '_UID_SequencedNotify', ApiName + '(uid seq notify)', Args, 'currentUID');
  Lines.Add('    } else {');
  Lines.Add('        reportSkip(' + SwiftStrLit(ApiName + '(uid notify)') + ', "no service UID")');
  Lines.Add('        reportSkip(' + SwiftStrLit(ApiName + '(uid seq notify)') + ', "no service UID")');
  Lines.Add('    }');
  Lines.Add('');

  EmitSyncNotifyTest(Lines,
    CallBase + '_P2PName_Notify', ApiName + '(p2pname notify)', Args, 'targetP2PName');
  Lines.Add('');

  EmitSyncNotifyTest(Lines,
    CallBase + '_P2PName_SequencedNotify', ApiName + '(p2pname seq notify)', Args, 'targetP2PName');
end;

function GenerateABICallTestSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, EnumName, AppName, P2PName, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestSwiftCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestSwiftCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  EnumName := NormalizedUnit + 'ABICall';
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + AppName;

  Log(PFormat('Generating Swift ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call test exercises %d ABI APIs', [Length(SupportedFuncs)]));

  ApiNames := AssignUniqueApiNames(SupportedFuncs);
  Lines := TPascalStringList.Create;
  try
    Lines.Add('import Foundation');
    Lines.Add('import LingoFuse');
    Lines.Add('import ' + NormalizedUnit + '_abi_call');
    Lines.Add('');
    Lines.Add('let CALL_TEST_TARGET_APP: String = ' + SwiftStrLit(AppName));
    Lines.Add('let CALL_TEST_TARGET_P2P: String = ' + SwiftStrLit(P2PName));
    Lines.Add('let CALL_TEST_ENDPOINT: String = ' + SwiftStrLit(Endpoint));
    Lines.Add('let CALL_TEST_CLIENT_APP: String = "LF_TEST_CLIENT_SELF"');
    Lines.Add('let CALL_TEST_REPORT_IDENTITY_API: String = "LF_TEST_REPORT_SERVICE_IDENTITY"');
    Lines.Add('let CALL_TEST_WHOAMI_API: String = "LF_TEST_WHOAMI"');
    Lines.Add('let CALL_TEST_ASK_CALL_ME_API: String = "LF_TEST_ASK_SERVICE_CALL_ME"');
    Lines.Add('');
    Lines.Add('var passCount: Int = 0');
    Lines.Add('var failCount: Int = 0');
    Lines.Add('var skipCount: Int = 0');
    Lines.Add('var serviceUID: Uid = .null');
    Lines.Add('var hasServiceUID: Bool = false');
    Lines.Add('var serviceCalledMe: Bool = false');
    Lines.Add('let stateLock: NSLock = NSLock()');
    Lines.Add('var targetP2PName: String = CALL_TEST_TARGET_P2P');
    Lines.Add('');
    Lines.Add('final class ResultBox<T>: @unchecked Sendable {');
    Lines.Add('    private let lock: NSLock = NSLock()');
    Lines.Add('    private var value: Result<T, Error>? = nil');
    Lines.Add('    func set(_ r: Result<T, Error>) {');
    Lines.Add('        lock.lock()');
    Lines.Add('        value = r');
    Lines.Add('        lock.unlock()');
    Lines.Add('    }');
    Lines.Add('    func take() -> Result<T, Error>? {');
    Lines.Add('        lock.lock()');
    Lines.Add('        defer { lock.unlock() }');
    Lines.Add('        let v = value');
    Lines.Add('        value = nil');
    Lines.Add('        return v');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func runAsyncWithSema<T>(_ label: String, _ body: @escaping () async throws -> T) -> Result<T, Error> {');
    Lines.Add('    let sema = DispatchSemaphore(value: 0)');
    Lines.Add('    let box = ResultBox<T>()');
    Lines.Add('    Task.detached {');
    Lines.Add('        do {');
    Lines.Add('            let v = try await body()');
    Lines.Add('            box.set(.success(v))');
    Lines.Add('        } catch {');
    Lines.Add('            box.set(.failure(error))');
    Lines.Add('        }');
    Lines.Add('        sema.signal()');
    Lines.Add('    }');
    Lines.Add('    if sema.wait(timeout: .now() + 10) == .timedOut {');
    Lines.Add('        return .failure(LingoFuseError.timeout(targetApp: label))');
    Lines.Add('    }');
    Lines.Add('    guard let r = box.take() else {');
    Lines.Add('        return .failure(LingoFuseError.generic(message: "no result for " + label))');
    Lines.Add('    }');
    Lines.Add('    return r');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func reportPass(_ label: String, _ value: String = "") {');
    Lines.Add('    stateLock.lock()');
    Lines.Add('    passCount += 1');
    Lines.Add('    stateLock.unlock()');
    Lines.Add('    if value.isEmpty {');
    Lines.Add('        print("[PASS] \(label)")');
    Lines.Add('    } else {');
    Lines.Add('        print("[PASS] \(label) = \(value)")');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func reportFail(_ label: String, _ reason: String) {');
    Lines.Add('    stateLock.lock()');
    Lines.Add('    failCount += 1');
    Lines.Add('    stateLock.unlock()');
    Lines.Add('    FileHandle.standardError.write("[FAIL] \(label) -- \(reason)\n".data(using: .utf8)!)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func reportSkip(_ label: String, _ reason: String) {');
    Lines.Add('    stateLock.lock()');
    Lines.Add('    skipCount += 1');
    Lines.Add('    stateLock.unlock()');
    Lines.Add('    print("[SKIP] \(label) -- \(reason)")');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func callTestCbReportIdentity(_ input: DataHandle, _ output: DataHandle) {');
    Lines.Add('    stateLock.lock()');
    Lines.Add('    serviceUID = input.p2pUid()');
    Lines.Add('    hasServiceUID = !serviceUID.isNull');
    Lines.Add('    serviceCalledMe = true');
    Lines.Add('    stateLock.unlock()');
    Lines.Add('    try? output.writeString("identity received")');
    Lines.Add('    print("[CLIENT] service called me")');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func callTestProbeClientIdentity() -> Bool {');
    Lines.Add('    do {');
    Lines.Add('        let param = try DataHandle(apiName: CALL_TEST_WHOAMI_API)');
    Lines.Add('        defer { param.dispose() }');
    Lines.Add('        let resp = try Framework.call(CALL_TEST_TARGET_APP, param, timeoutMs: 5000)');
    Lines.Add('        defer { resp.dispose() }');
    Lines.Add('        if resp.size < 34 { return false }');
    Lines.Add('        resp.position = 0');
    Lines.Add('        let status: UInt8 = try resp.readUInt8()');
    Lines.Add('        if status != 0x00 { return false }');
    Lines.Add('        let uidBytes = try resp.readBytesExact(32)');
    Lines.Add('        let _: String = try resp.readString()');
    Lines.Add('        var nonZero: Bool = false');
    Lines.Add('        for b in uidBytes {');
    Lines.Add('            if b != 0 {');
    Lines.Add('                nonZero = true');
    Lines.Add('                break');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('        if nonZero {');
    Lines.Add('            let hex = uidBytes.map { String(format: "%02x", $0) }.joined()');
    Lines.Add('            print("[INFO] client UID = \(hex)")');
    Lines.Add('        }');
    Lines.Add('        return nonZero');
    Lines.Add('    } catch {');
    Lines.Add('        return false');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func callTestServiceInitiatesCall() -> Bool {');
    Lines.Add('    stateLock.lock()');
    Lines.Add('    serviceCalledMe = false');
    Lines.Add('    hasServiceUID = false');
    Lines.Add('    serviceUID = .null');
    Lines.Add('    stateLock.unlock()');
    Lines.Add('    do {');
    Lines.Add('        let param = try DataHandle(apiName: CALL_TEST_ASK_CALL_ME_API)');
    Lines.Add('        defer { param.dispose() }');
    Lines.Add('        try param.writeString(CALL_TEST_REPORT_IDENTITY_API)');
    Lines.Add('        param.position = 0');
    Lines.Add('        Framework.notify(CALL_TEST_TARGET_APP, param)');
    Lines.Add('    } catch {');
    Lines.Add('        return false');
    Lines.Add('    }');
    Lines.Add('    var i: Int = 0');
    Lines.Add('    while i < 1000 {');
    Lines.Add('        stateLock.lock()');
    Lines.Add('        let called = serviceCalledMe');
    Lines.Add('        let has = hasServiceUID');
    Lines.Add('        stateLock.unlock()');
    Lines.Add('        if called {');
    Lines.Add('            if has {');
    Lines.Add('                let hex = serviceUID.toHex()');
    Lines.Add('                print("[INFO] service UID = \(hex)")');
    Lines.Add('            }');
    Lines.Add('            return has');
    Lines.Add('        }');
    Lines.Add('        Thread.sleep(forTimeInterval: 0.01)');
    Lines.Add('        i += 1');
    Lines.Add('    }');
    Lines.Add('    return false');
    Lines.Add('}');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      EmitTestFunctionHeader(Lines, ApiNames[i]);
      if F.IsFunction then
        EmitFunctionTestBody(Lines, EnumName, ApiNames[i], F)
      else
        EmitProcedureTestBody(Lines, EnumName, ApiNames[i], F);
      EmitTestFunctionFooter(Lines);
    end;

    Lines.Add('func callTestRun() -> Int32 {');
    Lines.Add('    print("=== ' + UnitName.Text + ' ABI call test ===")');
    Lines.Add('    print("Endpoint: \(CALL_TEST_ENDPOINT)")');
    Lines.Add('    print("AppName : \(CALL_TEST_TARGET_APP)")');
    Lines.Add('    print("P2PName : \(CALL_TEST_TARGET_P2P)")');
    Lines.Add('    print("")');
    Lines.Add('');
    Lines.Add('    var clientApp: AppHandle? = nil');
    Lines.Add('    do {');
    Lines.Add('        Framework.setOption("Wait_Connection_ReadyOk", "False")');
    Lines.Add('        Framework.setOption("Overlap_Connection", "True")');
    Lines.Add('        Framework.setOption("ConsoleOutput", "True")');
    Lines.Add('        Options.setQuiet(true)');
    Lines.Add('        Framework.resetPrepare()');
    Lines.Add('        let createdApp = try AppHandle(name: CALL_TEST_CLIENT_APP, description: "client test app")');
    Lines.Add('        clientApp = createdApp');
    Lines.Add('        try createdApp.registerCall(CALL_TEST_REPORT_IDENTITY_API, "report service identity", callTestCbReportIdentity)');
    Lines.Add('        try Framework.prepareClient(physicsAddr: CALL_TEST_ENDPOINT, app: createdApp)');
    Lines.Add('        if !Framework.prepareDone() {');
    Lines.Add('            FileHandle.standardError.write("[FATAL] prepareDone failed\n".data(using: .utf8)!)');
    Lines.Add('            Framework.exitMainThread()');
    Lines.Add('            createdApp.dispose()');
    Lines.Add('            Framework.shutdown()');
    Lines.Add('            return 1');
    Lines.Add('        }');
    Lines.Add('        print("[READY] Client online.")');
    Lines.Add('        print("")');
    Lines.Add('');
    Lines.Add('        var targetReady = false');
    Lines.Add('        for _ in 0..<30 {');
    Lines.Add('            if Framework.checkApi(CALL_TEST_TARGET_APP, CALL_TEST_WHOAMI_API) {');
    Lines.Add('                targetReady = true');
    Lines.Add('                break');
    Lines.Add('            }');
    Lines.Add('            Thread.sleep(forTimeInterval: 0.2)');
    Lines.Add('        }');
    Lines.Add('        if targetReady {');
    Lines.Add('            print("[OK] Target service ready on the mesh")');
    Lines.Add('        } else {');
    Lines.Add('            FileHandle.standardError.write("[WARN] Target service not ready on the mesh\n".data(using: .utf8)!)');
    Lines.Add('        }');
    Lines.Add('        print("")');
    Lines.Add('');
    Lines.Add('        if callTestProbeClientIdentity() {');
    Lines.Add('            print("[OK] client identity probe")');
    Lines.Add('        } else {');
    Lines.Add('            print("[WARN] whoami failed, UID tests will be skipped")');
    Lines.Add('        }');
    Lines.Add('        print("")');
    Lines.Add('');
    Lines.Add('        if callTestServiceInitiatesCall() {');
    Lines.Add('            reportPass("service-initiated call", "ok")');
    Lines.Add('        } else {');
    Lines.Add('            reportFail("service-initiated call", "timeout or no UID")');
    Lines.Add('        }');
    Lines.Add('        print("")');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      Lines.Add('        test_' + ApiNames[i] + '()');

    Lines.Add('');
    Lines.Add('        print("")');
    Lines.Add('        print("=== Summary ===")');
    Lines.Add('        print("Pass: \(passCount)")');
    Lines.Add('        print("Fail: \(failCount)")');
    Lines.Add('        print("Skip: \(skipCount)")');
    Lines.Add('        print("")');
    Lines.Add('        Framework.exitMainThread()');
    Lines.Add('        createdApp.dispose()');
    Lines.Add('        Framework.shutdown()');
    Lines.Add('        if failCount == 0 { return 0 }');
    Lines.Add('        return 2');
    Lines.Add('    } catch {');
    Lines.Add('        FileHandle.standardError.write("[FATAL] call test: \(error)\n".data(using: .utf8)!)');
    Lines.Add('        Framework.exitMainThread()');
    Lines.Add('        if let a = clientApp { a.dispose() }');
    Lines.Add('        Framework.shutdown()');
    Lines.Add('        return 1');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('if LF_LoadLibrary() != 1 {');
    Lines.Add('    FileHandle.standardError.write("[FATAL] LF_LoadLibrary failed\n".data(using: .utf8)!)');
    Lines.Add('    exit(1)');
    Lines.Add('}');
    Lines.Add('let CALL_TEST_EXIT_CODE: Int32 = callTestRun()');
    Lines.Add('LF_FreeLibrary()');
    Lines.Add('if CALL_TEST_EXIT_CODE != 0 { exit(CALL_TEST_EXIT_CODE) }');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the Swift ABI call test', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'swift',
    'xxx_abi_service_test.swift',
    gkTest,
    'Swift ABI service test',
    @GenerateABIServiceTestSwiftCode);

  RegisterGenerator(
    'swift',
    'xxx_abi_call_test.swift',
    gkTest,
    'Swift ABI call test',
    @GenerateABICallTestSwiftCode);

end.
