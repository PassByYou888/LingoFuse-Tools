unit ts_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib,
  Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function IsInt64ABIType(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
end;

function ABI_Type_To_Ts_Write_Fn(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'writeInt32'
  else if T.Same('int64') then Result := 'writeInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'writeUInt32'
  else if T.Same('word') then Result := 'writeUInt16'
  else if T.Same('smallint') then Result := 'writeInt16'
  else if T.Same('byte') then Result := 'writeUInt8'
  else if T.Same('uint64') then Result := 'writeUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'writeDouble'
  else if T.Same('single') then Result := 'writeSingle'
  else if IsStringABIType(T) then Result := 'writeString'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Ts_Write_Fn(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function TsStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
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
    begin
      Code := Ord(c);
      if Code < 32 then
      begin
        Result.Append('\');
        Result.Append('x');
        if Code < 16 then
        begin
          Result.Append('0');
          Result.Append(TP_String(IntToHex(Code, 1)));
        end
        else
          Result.Append(TP_String(IntToHex(Code, 2)));
      end
      else
        Result.Append(c);
    end;
  end;
  Result.Append('"');
end;

function BuildArgValues(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    if IsStringABIType(Params[i].PascalType) then
      Result := Result + TsStrLit('test')
    else if IsInt64ABIType(Params[i].PascalType) then
      Result := Result + '0n'
    else if Params[i].PascalType.Same('double') or
            Params[i].PascalType.Same('extended') or
            Params[i].PascalType.Same('real') or
            Params[i].PascalType.Same('single') then
      Result := Result + '0.0'
    else
      Result := Result + '0';
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

procedure AssignUniqueApiNames(const Funcs: TArryFunctionStructure; Names: TPascalStringList);
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

procedure EmitServiceTestHeader(
  Lines: TPascalStringList;
  const UnitName, AppName, P2PName: TP_String);
begin
  Lines.Add('import * as lf from "lingofuse-ts";');
  Lines.Add('import * as service from "./' + UnitName + '_abi_service";');
  Lines.Add('');
  Lines.Add('const _binding = (lf as any)._binding;');
  Lines.Add('const _koffi = _binding.koffi;');
  Lines.Add('const LfCallFuncPtr = _binding.LfCallFuncPtr;');
  Lines.Add('const LfNotifyFuncPtr = _binding.LfNotifyFuncPtr;');
  Lines.Add('const funcs = lf.getBinding().funcs;');
  Lines.Add('');
  Lines.Add('const ENDPOINT = ' + TsStrLit('ipc:' + AppName) + ';');
  Lines.Add('const APP_NAME = ' + TsStrLit(AppName) + ';');
  Lines.Add('const P2P_NAME = ' + TsStrLit(P2PName) + ';');
  Lines.Add('const WHOAMI_API = ' + TsStrLit('LF_TEST_WHOAMI') + ';');
  Lines.Add('const ASK_CALL_ME_API = ' + TsStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
  Lines.Add('');
  Lines.Add('const STATUS_OK = 0x00;');
  Lines.Add('const STATUS_ERROR = 0xFF;');
  Lines.Add('');
  Lines.Add('function _errMsg(e: unknown): string {');
  Lines.Add('    if (e === null || e === undefined) return "undefined";');
  Lines.Add('    return e instanceof Error ? e.message : String(e);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function whoAmICb(_trigger: unknown, input: unknown, output: unknown): void {');
  Lines.Add('    const inH = lf.DataHandle.fromRaw(input, false);');
  Lines.Add('    const outH = lf.DataHandle.fromRaw(output, false);');
  Lines.Add('    try {');
  Lines.Add('        const uid = inH.getP2PUid();');
  Lines.Add('        const p2p = inH.getP2PName();');
  Lines.Add('        outH.writeUInt8(STATUS_OK);');
  Lines.Add('        outH.writeBytes(uid);');
  Lines.Add('        outH.writeString(p2p);');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        try {');
  Lines.Add('            outH.size = 0;');
  Lines.Add('            outH.position = 0;');
  Lines.Add('            outH.writeUInt8(STATUS_ERROR);');
  Lines.Add('            outH.writeString(_errMsg(_e));');
  Lines.Add('        } catch (_) { }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function askCallMeCb(_trigger: unknown, input: unknown): void {');
  Lines.Add('    const inH = lf.DataHandle.fromRaw(input, false);');
  Lines.Add('    try {');
  Lines.Add('        const uid = inH.getP2PUid();');
  Lines.Add('        const clientApi = "LF_TEST_REPORT_SERVICE_IDENTITY";');
  Lines.Add('        const data = new lf.DataHandle(clientApi);');
  Lines.Add('        try {');
  Lines.Add('            data.writeString("service initiates call");');
  Lines.Add('            const res = lf.framework.uidCall(uid, data, 5000);');
  Lines.Add('            try {');
  Lines.Add('                console.log("[SERVICE] ask_call_me: client responded ok");');
  Lines.Add('            } finally {');
  Lines.Add('                res.dispose();');
  Lines.Add('            }');
  Lines.Add('        } finally {');
  Lines.Add('            data.dispose();');
  Lines.Add('        }');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        console.error("[SERVICE] ask_call_me error: " + _errMsg(_e));');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('const cbWhoAmI = _koffi.register(whoAmICb, LfCallFuncPtr);');
  Lines.Add('const cbAskCallMe = _koffi.register(askCallMeCb, LfNotifyFuncPtr);');
  Lines.Add('');
end;

procedure EmitServiceTestMain(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('function main(): void {');
  Lines.Add('    lf.loadLibrary();');
  Lines.Add('    lf.framework.setOption("Quiet", "True");');
  Lines.Add('    lf.framework.setOption("ConsoleOutput", "True");');
  Lines.Add('    lf.framework.setOption("LF_P2P_name", P2P_NAME);');
  Lines.Add('');
  Lines.Add('    const app = new lf.AppHandle(APP_NAME, ' + TsStrLit('ABI service test') + ');');
  Lines.Add('    try {');
  Lines.Add('        const failed1 = service.registerAll(app.raw);');
  Lines.Add('        if (failed1 !== 0) {');
  Lines.Add('            console.error("[FATAL] registerAll reported " + failed1 + " failed registrations");');
  Lines.Add('            process.exit(1);');
  Lines.Add('        }');
  Lines.Add('        const failed2 = service.registerAllP2P();');
  Lines.Add('        if (failed2 !== 0) {');
  Lines.Add('            console.error("[FATAL] registerAllP2P reported " + failed2 + " failed registrations");');
  Lines.Add('            process.exit(1);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        funcs.LF_RegisterCall(app.raw, WHOAMI_API, "whoami helper", null, cbWhoAmI);');
  Lines.Add('        funcs.LF_RegisterNotify(app.raw, ASK_CALL_ME_API, "ask service to call client", null, cbAskCallMe);');
  Lines.Add('');
  Lines.Add('        lf.framework.resetPrepare();');
  Lines.Add('        lf.framework.prepareService(ENDPOINT, ENDPOINT);');
  Lines.Add('        lf.framework.prepareClient(ENDPOINT, app);');
  Lines.Add('');
  Lines.Add('        if (lf.framework.prepareDone() !== 1) {');
  Lines.Add('            console.error("[FATAL] prepareDone failed");');
  Lines.Add('            process.exit(1);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        console.log("[OK] service ready on " + ENDPOINT);');
  Lines.Add('        console.log("[OK] press Ctrl+C to exit");');
  Lines.Add('        setInterval(() => { }, 1 << 30);');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        console.error("[FATAL] " + _errMsg(_e));');
  Lines.Add('        process.exit(1);');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('process.on("SIGINT", () => {');
  Lines.Add('    console.log("[OK] shutting down");');
  Lines.Add('    try { lf.AsyncBridge.shutdownInstance(); } catch (_) { }');
  Lines.Add('    try { lf.network.clearNetworkEvent(); } catch (_) { }');
  Lines.Add('    try { lf.framework.exitMainThread(); } catch (_) { }');
  Lines.Add('    try { lf.framework.shutdown(); } catch (_) { }');
  Lines.Add('    process.exit(0);');
  Lines.Add('});');
  Lines.Add('');
  Lines.Add('main();');
end;

function GenerateABIServiceTestTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, AppName, P2PName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  UnitName := MakeApiName(Model.UnitName);
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  AppName := UnitName + '_abi';
  P2PName := UnitName + '_service_test_p2p';

  Log(PFormat('Generating TypeScript ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    EmitServiceTestHeader(Lines, UnitName, AppName, P2PName);
    EmitServiceTestMain(Lines, UnitName);
    Result := Lines;
    Log(PFormat('Generated %d lines for the service test.', [Lines.Count]));
  finally
  end;
end;

procedure EmitCallTestHeader(
  Lines: TPascalStringList;
  const UnitName, AppName, P2PName: TP_String);
begin
  Lines.Add('import * as lf from "lingofuse-ts";');
  Lines.Add('import * as call from "./' + UnitName + '_abi_call";');
  Lines.Add('');
  Lines.Add('const _binding = (lf as any)._binding;');
  Lines.Add('const _koffi = _binding.koffi;');
  Lines.Add('const LfCallFuncPtr = _binding.LfCallFuncPtr;');
  Lines.Add('const funcs = lf.getBinding().funcs;');
  Lines.Add('');
  Lines.Add('const ENDPOINT = ' + TsStrLit('ipc:' + AppName) + ';');
  Lines.Add('const APP_NAME = ' + TsStrLit(AppName) + ';');
  Lines.Add('const P2P_NAME = ' + TsStrLit(P2PName) + ';');
  Lines.Add('const WHOAMI_API = ' + TsStrLit('LF_TEST_WHOAMI') + ';');
  Lines.Add('const ASK_CALL_ME_API = ' + TsStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
  Lines.Add('const REPORT_IDENTITY_API = ' + TsStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
  Lines.Add('const CLIENT_APP_NAME = ' + TsStrLit('LF_TEST_CLIENT_SELF') + ';');
  Lines.Add('');
  Lines.Add('const STATUS_OK = 0x00;');
  Lines.Add('');
  Lines.Add('const _g = { pass: 0, fail: 0, skip: 0 };');
  Lines.Add('let _hasServiceUID = false;');
  Lines.Add('let _serviceUID: Uint8Array = new Uint8Array(32);');
  Lines.Add('let _serviceP2P = "";');
  Lines.Add('let _serviceCalledMe = false;');
  Lines.Add('');
  Lines.Add('function _race<T>(promise: PromiseLike<T>, timeoutMs: number, _label: string): Promise<T> {');
  Lines.Add('    let timer: ReturnType<typeof setTimeout> | null = null;');
  Lines.Add('    const timeout = new Promise<T>((_, reject) => {');
  Lines.Add('        timer = setTimeout(() => {');
  Lines.Add('            reject(new Error("race timeout after " + timeoutMs + "ms"));');
  Lines.Add('        }, timeoutMs);');
  Lines.Add('    });');
  Lines.Add('    return Promise.race([Promise.resolve(promise), timeout]).then(');
  Lines.Add('        (v) => { if (timer) clearTimeout(timer); return v; },');
  Lines.Add('        (e) => { if (timer) clearTimeout(timer); throw e; }');
  Lines.Add('    );');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('process.on("unhandledRejection", (reason: unknown) => {');
  Lines.Add('    const msg = "unhandledRejection: " + (reason instanceof Error ? reason.message : String(reason));');
  Lines.Add('    console.log("[FATAL] " + msg);');
  Lines.Add('    console.error("[FATAL] " + msg);');
  Lines.Add('});');
  Lines.Add('');
  Lines.Add('process.on("uncaughtException", (err: Error) => {');
  Lines.Add('    const msg = "uncaughtException: " + (err && err.message ? err.message : String(err));');
  Lines.Add('    console.log("[FATAL] " + msg);');
  Lines.Add('    console.error("[FATAL] " + msg);');
  Lines.Add('    process.exit(3);');
  Lines.Add('});');
  Lines.Add('');
  Lines.Add('function _reportPass(label: string, value?: unknown): void {');
  Lines.Add('    _g.pass++;');
  Lines.Add('    let line: string;');
  Lines.Add('    if (value === undefined || value === "") {');
  Lines.Add('        line = "[PASS] " + label;');
  Lines.Add('    } else {');
  Lines.Add('        line = "[PASS] " + label + " = " + String(value);');
  Lines.Add('    }');
  Lines.Add('    console.log(line);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _reportFail(label: string, reason: string): void {');
  Lines.Add('    _g.fail++;');
  Lines.Add('    const line = "[FAIL] " + label + " -- " + reason;');
  Lines.Add('    console.log(line);');
  Lines.Add('    console.error(line);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _reportSkip(label: string, reason: string): void {');
  Lines.Add('    _g.skip++;');
  Lines.Add('    const line = "[SKIP] " + label + " -- " + reason;');
  Lines.Add('    console.log(line);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _errMsg(e: unknown): string {');
  Lines.Add('    if (e === null || e === undefined) return "undefined";');
  Lines.Add('    return e instanceof Error ? e.message : String(e);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _bytesToHex(uid: Uint8Array): string {');
  Lines.Add('    let s = "";');
  Lines.Add('    for (let i = 0; i < uid.length; i++) {');
  Lines.Add('        s += uid[i].toString(16).padStart(2, "0").toUpperCase();');
  Lines.Add('    }');
  Lines.Add('    return s;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function reportIdentityCb(_trigger: unknown, input: unknown, output: unknown): void {');
  Lines.Add('    const inH = lf.DataHandle.fromRaw(input, false);');
  Lines.Add('    const outH = lf.DataHandle.fromRaw(output, false);');
  Lines.Add('    try {');
  Lines.Add('        _serviceUID = inH.getP2PUid();');
  Lines.Add('        _serviceP2P = inH.getP2PName();');
  Lines.Add('        _hasServiceUID = true;');
  Lines.Add('        _serviceCalledMe = true;');
  Lines.Add('        let msg = "";');
  Lines.Add('        try { msg = inH.readString(); } catch (_) { }');
  Lines.Add('        console.log("[CLIENT] service called me: " + msg);');
  Lines.Add('        outH.writeUInt8(STATUS_OK);');
  Lines.Add('        outH.writeString("identity received");');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        try {');
  Lines.Add('            outH.size = 0;');
  Lines.Add('            outH.position = 0;');
  Lines.Add('            outH.writeUInt8(0xFF);');
  Lines.Add('            outH.writeString(_errMsg(_e));');
  Lines.Add('        } catch (_) { }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('const cbReportIdentity = _koffi.register(reportIdentityCb, LfCallFuncPtr);');
  Lines.Add('');
  Lines.Add('function _probeIdentity(): boolean {');
  Lines.Add('    try {');
  Lines.Add('        const param = new lf.DataHandle(WHOAMI_API);');
  Lines.Add('        try {');
  Lines.Add('            const res = lf.framework.call(APP_NAME, param, 5000);');
  Lines.Add('            try {');
  Lines.Add('                if (res.size < 34) return false;');
  Lines.Add('                res.position = 0;');
  Lines.Add('                const status = res.readUInt8();');
  Lines.Add('                if (status !== STATUS_OK) return false;');
  Lines.Add('                const uid = res.readBytesExact(32);');
  Lines.Add('                const p2p = res.readString();');
  Lines.Add('                let nonZero = false;');
  Lines.Add('                for (let i = 0; i < 32; i++) {');
  Lines.Add('                    if (uid[i] !== 0) { nonZero = true; break; }');
  Lines.Add('                }');
  Lines.Add('                if (!nonZero) return false;');
  Lines.Add('                _serviceUID = uid;');
  Lines.Add('                _serviceP2P = p2p;');
  Lines.Add('                _hasServiceUID = true;');
  Lines.Add('                console.log("[INFO] service UID = " + _bytesToHex(uid));');
  Lines.Add('                console.log("[INFO] service P2P = " + p2p);');
  Lines.Add('                return true;');
  Lines.Add('            } finally {');
  Lines.Add('                res.dispose();');
  Lines.Add('            }');
  Lines.Add('        } finally {');
  Lines.Add('            param.dispose();');
  Lines.Add('        }');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        console.error("[WARN] whoami probe failed: " + _errMsg(_e));');
  Lines.Add('        return false;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('async function _testServiceInitiatesCall(): Promise<boolean> {');
  Lines.Add('    _serviceCalledMe = false;');
  Lines.Add('    const param = new lf.DataHandle(ASK_CALL_ME_API);');
  Lines.Add('    try {');
  Lines.Add('        param.writeString(REPORT_IDENTITY_API);');
  Lines.Add('        lf.framework.notify(APP_NAME, param);');
  Lines.Add('    } finally {');
  Lines.Add('        param.dispose();');
  Lines.Add('    }');
  Lines.Add('    for (let i = 0; i < 1000; i++) {');
  Lines.Add('        if (_serviceCalledMe) return true;');
  Lines.Add('        await new Promise<void>((resolve) => setTimeout(resolve, 10));');
  Lines.Add('    }');
  Lines.Add('    return false;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAsyncTestBlock(
  Lines: TPascalStringList;
  const Label_: TP_String;
  const CallExpr: TP_String);
begin
  Lines.Add('    try {');
  Lines.Add('        const _v = await _race(' + CallExpr + ', 10000, ' + TsStrLit(Label_) + ');');
  Lines.Add('        _reportPass(' + TsStrLit(Label_) + ', _v);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        _reportFail(' + TsStrLit(Label_) + ', _errMsg(e));');
  Lines.Add('    }');
end;

procedure EmitCallTestFunctionBlock(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ActualArgs: TP_String;
  ArgsWithComma: TP_String;
begin
  ActualArgs := BuildArgValues(F.Params);
  if ActualArgs <> '' then
    ArgsWithComma := ', ' + ActualArgs
  else
    ArgsWithComma := '';

  Lines.Add('async function test_' + ApiName + '(): Promise<void> {');

  Lines.Add('    try {');
  Lines.Add('        const _r = call.' + ApiName + '(' + ActualArgs + ');');
  Lines.Add('        _reportPass(' + TsStrLit(ApiName + '(app call)') + ', _r);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        _reportFail(' + TsStrLit(ApiName + '(app call)') + ', _errMsg(e));');
  Lines.Add('    }');
  Lines.Add('');

  EmitAsyncTestBlock(Lines, ApiName + '(app async)',
    'call.' + ApiName + 'Async(' + ActualArgs + ')');
  EmitAsyncTestBlock(Lines, ApiName + '(app asyncSeq)',
    'call.' + ApiName + 'Sequenced(' + ActualArgs + ')');
  Lines.Add('');

  Lines.Add('    if (_hasServiceUID) {');
  Lines.Add('        try {');
  Lines.Add('            const _r = call.' + ApiName + 'ByUid(_serviceUID' + ArgsWithComma + ');');
  Lines.Add('            _reportPass(' + TsStrLit(ApiName + '(uid call)') + ', _r);');
  Lines.Add('        } catch (e) {');
  Lines.Add('            _reportFail(' + TsStrLit(ApiName + '(uid call)') + ', _errMsg(e));');
  Lines.Add('        }');
  EmitAsyncTestBlock(Lines, ApiName + '(uid async)',
    'call.' + ApiName + 'ByUidAsync(_serviceUID' + ArgsWithComma + ')');
  EmitAsyncTestBlock(Lines, ApiName + '(uid asyncSeq)',
    'call.' + ApiName + 'ByUidSequenced(_serviceUID' + ArgsWithComma + ')');
  Lines.Add('    } else {');
  Lines.Add('        _reportSkip(' + TsStrLit(ApiName + '(uid call)') + ', "no service UID");');
  Lines.Add('        _reportSkip(' + TsStrLit(ApiName + '(uid async)') + ', "no service UID");');
  Lines.Add('        _reportSkip(' + TsStrLit(ApiName + '(uid asyncSeq)') + ', "no service UID");');
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    try {');
  Lines.Add('        const _r = call.' + ApiName + 'ByP2PName(P2P_NAME' + ArgsWithComma + ');');
  Lines.Add('        _reportPass(' + TsStrLit(ApiName + '(p2pname call)') + ', _r);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        _reportFail(' + TsStrLit(ApiName + '(p2pname call)') + ', _errMsg(e));');
  Lines.Add('    }');
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname async)',
    'call.' + ApiName + 'ByP2PNameAsync(P2P_NAME' + ArgsWithComma + ')');
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname asyncSeq)',
    'call.' + ApiName + 'ByP2PNameSequenced(P2P_NAME' + ArgsWithComma + ')');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNotifyTestBlock(
  Lines: TPascalStringList;
  const Label_: TP_String;
  const CallExpr: TP_String;
  const Indent: string);
begin
  Lines.Add(Indent + 'try {');
  Lines.Add(Indent + '    ' + CallExpr + ';');
  Lines.Add(Indent + '    _reportPass(' + TsStrLit(Label_) + ');');
  Lines.Add(Indent + '} catch (e) {');
  Lines.Add(Indent + '    _reportFail(' + TsStrLit(Label_) + ', _errMsg(e));');
  Lines.Add(Indent + '}');
end;

procedure EmitCallTestProcedureBlock(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ActualArgs: TP_String;
  ArgsWithComma: TP_String;
begin
  ActualArgs := BuildArgValues(F.Params);
  if ActualArgs <> '' then
    ArgsWithComma := ', ' + ActualArgs
  else
    ArgsWithComma := '';

  Lines.Add('function test_' + ApiName + '(): void {');

  EmitNotifyTestBlock(Lines, ApiName + '(app notify)',
    'call.' + ApiName + '(' + ActualArgs + ')', '    ');
  Lines.Add('');

  EmitNotifyTestBlock(Lines, ApiName + '(app seq notify)',
    'call.' + ApiName + 'Sequenced(' + ActualArgs + ')', '    ');
  Lines.Add('');

  Lines.Add('    if (_hasServiceUID) {');
  EmitNotifyTestBlock(Lines, ApiName + '(uid notify)',
    'call.' + ApiName + 'ByUid(_serviceUID' + ArgsWithComma + ')', '        ');
  EmitNotifyTestBlock(Lines, ApiName + '(uid seq notify)',
    'call.' + ApiName + 'ByUidSequenced(_serviceUID' + ArgsWithComma + ')', '        ');
  Lines.Add('    } else {');
  Lines.Add('        _reportSkip(' + TsStrLit(ApiName + '(uid notify)') + ', "no service UID");');
  Lines.Add('        _reportSkip(' + TsStrLit(ApiName + '(uid seq notify)') + ', "no service UID");');
  Lines.Add('    }');
  Lines.Add('');

  EmitNotifyTestBlock(Lines, ApiName + '(p2pname notify)',
    'call.' + ApiName + 'ByP2PName(P2P_NAME' + ArgsWithComma + ')', '    ');
  EmitNotifyTestBlock(Lines, ApiName + '(p2pname seq notify)',
    'call.' + ApiName + 'ByP2PNameSequenced(P2P_NAME' + ArgsWithComma + ')', '    ');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestMain(
  Lines: TPascalStringList;
  const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('async function main(): Promise<void> {');
  Lines.Add('    lf.loadLibrary();');
  Lines.Add('    lf.framework.setOption("Quiet", "True");');
  Lines.Add('    lf.framework.setOption("ConsoleOutput", "True");');
  Lines.Add('');
  Lines.Add('    call.ABI.TargetApp = APP_NAME;');
  Lines.Add('    call.ABI.Timeout = 5000;');
  Lines.Add('');
  Lines.Add('    const client = new lf.AppHandle(CLIENT_APP_NAME, ' + TsStrLit('client test') + ');');
  Lines.Add('');
  Lines.Add('    funcs.LF_RegisterCall(client.raw, REPORT_IDENTITY_API, "report identity", null, cbReportIdentity);');
  Lines.Add('');
  Lines.Add('    lf.framework.resetPrepare();');
  Lines.Add('    lf.framework.prepareClient(ENDPOINT, client);');
  Lines.Add('');
  Lines.Add('    if (lf.framework.prepareDone() !== 1) {');
  Lines.Add('        console.error("[FATAL] prepareDone failed");');
  Lines.Add('        process.exit(1);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    console.log("[OK] client online");');
  Lines.Add('');
  Lines.Add('    for (let i = 0; i < 200; i++) {');
  Lines.Add('        if (lf.status.checkApp(APP_NAME)) break;');
  Lines.Add('        await new Promise<void>((resolve) => setTimeout(resolve, 100));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (_probeIdentity()) {');
  Lines.Add('        console.log("[OK] client identity probe");');
  Lines.Add('    } else {');
  Lines.Add('        console.log("[WARN] whoami failed, UID tests will be skipped");');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (await _testServiceInitiatesCall()) {');
  Lines.Add('        console.log("[OK] service-initiated call");');
  Lines.Add('    } else {');
  Lines.Add('        _reportFail("service-initiated call", "timeout or no service UID");');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    console.log("[INFO] total tests scheduled: ' + umlIntToStr(ApiNames.Count).Text + '");');

  for i := 0 to ApiNames.Count - 1 do
    Lines.Add('    await test_' + ApiNames[i] + '();');

  Lines.Add('');
  Lines.Add('    console.log("");');
  Lines.Add('    console.log("=== Summary ===");');
  Lines.Add('    console.log("Pass: " + _g.pass);');
  Lines.Add('    console.log("Fail: " + _g.fail);');
  Lines.Add('    console.log("Skip: " + _g.skip);');
  Lines.Add('');
  Lines.Add('    try { lf.AsyncBridge.shutdownInstance(); } catch (_) { }');
  Lines.Add('    try { lf.network.clearNetworkEvent(); } catch (_) { }');
  Lines.Add('    try { lf.framework.exitMainThread(); } catch (_) { }');
  Lines.Add('    try { lf.framework.shutdown(); } catch (_) { }');
  Lines.Add('    process.exit(_g.fail === 0 ? 0 : 2);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('main().catch((e) => {');
  Lines.Add('    const msg = _errMsg(e);');
  Lines.Add('    console.log("[FATAL] " + msg);');
  Lines.Add('    console.error("[FATAL] " + msg);');
  Lines.Add('    process.exit(1);');
  Lines.Add('});');
end;

function GenerateABICallTestTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, AppName, P2PName: TP_String;
  UsedApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  UnitName := MakeApiName(Model.UnitName);
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  AppName := UnitName + '_abi';
  P2PName := UnitName + '_service_test_p2p';

  Log(PFormat('Generating TypeScript ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating a skeleton test.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    EmitCallTestHeader(Lines, UnitName, AppName, P2PName);

    AssignUniqueApiNames(SupportedFuncs, UsedApiNames);

    for i := 0 to High(SupportedFuncs) do
    begin
      if SupportedFuncs[i].IsFunction then
        EmitCallTestFunctionBlock(Lines, UsedApiNames[i], SupportedFuncs[i])
      else
        EmitCallTestProcedureBlock(Lines, UsedApiNames[i], SupportedFuncs[i]);
    end;

    EmitCallTestMain(Lines, UsedApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'http_ts',
    'xxx_abi_service_test.ts',
    gkTest,
    'TypeScript ABI service test',
    @GenerateABIServiceTestTypeScriptCode);

  RegisterGenerator(
    'http_ts',
    'xxx_abi_call_test.ts',
    gkTest,
    'TypeScript ABI call test',
    @GenerateABICallTestTypeScriptCode);

end.
