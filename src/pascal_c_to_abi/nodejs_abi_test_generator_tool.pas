unit nodejs_abi_test_generator_tool;

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

function GenerateABIServiceTestNodejsCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestNodejsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[nodejs_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[nodejs_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function IsInt64Type(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
end;

function ABI_Type_To_Js_Write_Fn(const T: TP_String): TP_String;
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
  Result := ABI_Type_To_Js_Write_Fn(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function MakeJsParamName(const Name: TP_String; Index: integer): TP_String;
begin
  if Name.Len = 0 then
    Result := '_arg' + umlIntToStr(Index).Text
  else
    Result := '_arg_' + Name.Text;
end;

function JsStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append('\');
      Result.Append(#39);
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
  Result.Append(#39);
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
      Result := Result + #39 + 'test' + #39
    else if IsInt64Type(Params[i].PascalType) then
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

procedure EmitServiceTestHeader(
  Lines: TPascalStringList;
  const UnitName, AppName, P2PName: TP_String);
begin
  Lines.Add(#39 + 'use strict' + #39 + ';');
  Lines.Add('');
  Lines.Add('const lf = require(' + JsStrLit('lingofuse-js') + ');');
  Lines.Add('const service = require(' + JsStrLit('./' + UnitName + '_abi_service.js') + ');');
  Lines.Add('const _binding = lf._binding;');
  Lines.Add('const _koffi = _binding.koffi;');
  Lines.Add('const funcs = _binding.getBinding().funcs;');
  Lines.Add('const LfCallFunc = _binding.LfCallFunc;');
  Lines.Add('const LfNotifyFunc = _binding.LfNotifyFunc;');
  Lines.Add('');
  Lines.Add('const ENDPOINT = ' + JsStrLit('ipc:' + AppName) + ';');
  Lines.Add('const APP_NAME = ' + JsStrLit(AppName) + ';');
  Lines.Add('const P2P_NAME = ' + JsStrLit(P2PName) + ';');
  Lines.Add('const WHOAMI_API = ' + JsStrLit('LF_TEST_WHOAMI') + ';');
  Lines.Add('const ASK_CALL_ME_API = ' + JsStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
  Lines.Add('');
  Lines.Add('const STATUS_OK = 0x00;');
  Lines.Add('const STATUS_ERROR = 0xFF;');
  Lines.Add('');
  Lines.Add('function whoAmICb(_trigger, input, output) {');
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
  Lines.Add('            outH.writeString((_e && _e.message) ? _e.message : String(_e));');
  Lines.Add('        } catch (_) {}');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function askCallMeCb(_trigger, input) {');
  Lines.Add('    const inH = lf.DataHandle.fromRaw(input, false);');
  Lines.Add('    try {');
  Lines.Add('        const uid = inH.getP2PUid();');
  Lines.Add('        const clientApi = ' + JsStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
  Lines.Add('        const data = new lf.DataHandle(clientApi);');
  Lines.Add('        try {');
  Lines.Add('            data.writeString(' + JsStrLit('service initiates call') + ');');
  Lines.Add('            const res = lf.framework.uidCall(uid, data, 5000);');
  Lines.Add('            try {');
  Lines.Add('                console.log(' + JsStrLit('[SERVICE] ask_call_me: client responded') + ');');
  Lines.Add('            } finally {');
  Lines.Add('                res.dispose();');
  Lines.Add('            }');
  Lines.Add('        } finally {');
  Lines.Add('            data.dispose();');
  Lines.Add('        }');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        console.error(' + JsStrLit('[SERVICE] ask_call_me error: ') + ' + ((_e && _e.message) ? _e.message : String(_e)));');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitServiceTestMain(Lines: TPascalStringList);
begin
  Lines.Add('function main() {');
  Lines.Add('    lf.loadLibrary();');
  Lines.Add('    lf.framework.setOption(' + JsStrLit('Quiet') + ', ' + JsStrLit('True') + ');');
  Lines.Add('    lf.framework.setOption(' + JsStrLit('ConsoleOutput') + ', ' + JsStrLit('True') + ');');
  Lines.Add('    lf.framework.setOption(' + JsStrLit('LF_P2P_name') + ', P2P_NAME);');
  Lines.Add('');
  Lines.Add('    const app = new lf.AppHandle(APP_NAME, ' + JsStrLit('ABI service test') + ');');
  Lines.Add('    try {');
  Lines.Add('        service.registerAll(app.raw);');
  Lines.Add('        service.registerAllP2P();');
  Lines.Add('');
  Lines.Add('        const cbWhoAmI = _koffi.register(whoAmICb, _koffi.pointer(LfCallFunc));');
  Lines.Add('        funcs.LF_RegisterCall(app.raw, WHOAMI_API, ' + JsStrLit('whoami helper') + ', null, cbWhoAmI);');
  Lines.Add('');
  Lines.Add('        const cbAskCallMe = _koffi.register(askCallMeCb, _koffi.pointer(LfNotifyFunc));');
  Lines.Add('        funcs.LF_RegisterNotify(app.raw, ASK_CALL_ME_API, ' + JsStrLit('ask service to call client') + ', null, cbAskCallMe);');
  Lines.Add('');
  Lines.Add('        lf.framework.resetPrepare();');
  Lines.Add('        lf.framework.prepareService(ENDPOINT, ENDPOINT);');
  Lines.Add('        lf.framework.prepareClient(ENDPOINT, app);');
  Lines.Add('');
  Lines.Add('        if (lf.framework.prepareDone() !== 1) {');
  Lines.Add('            console.error(' + JsStrLit('[FATAL] prepareDone failed') + ');');
  Lines.Add('            process.exit(1);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        console.log(' + JsStrLit('[OK] service ready on ') + ' + ENDPOINT);');
  Lines.Add('        console.log(' + JsStrLit('[OK] press Ctrl+C to exit') + ');');
  Lines.Add('        setInterval(() => {}, 1 << 30);');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        console.error(' + JsStrLit('[FATAL] ') + ' + ((_e && _e.message) ? _e.message : String(_e)));');
  Lines.Add('        process.exit(1);');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('process.on(' + JsStrLit('SIGINT') + ', () => {');
  Lines.Add('    console.log(' + JsStrLit('[OK] shutting down') + ');');
  Lines.Add('    try { lf.AsyncBridge.shutdownInstance(); } catch (_) {}');
  Lines.Add('    try { lf.network.clearNetworkEvent(); } catch (_) {}');
  Lines.Add('    try { lf.framework.exitMainThread(); } catch (_) {}');
  Lines.Add('    try { lf.framework.shutdown(); } catch (_) {}');
  Lines.Add('    process.exit(0);');
  Lines.Add('});');
  Lines.Add('');
  Lines.Add('main();');
end;

function GenerateABIServiceTestNodejsCode(Model: TPascal_Func_Model): TPascalStringList;
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

  Log(PFormat('Generating Node.js ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    EmitServiceTestHeader(Lines, UnitName, AppName, P2PName);
    EmitServiceTestMain(Lines);
    Result := Lines;
    Log(PFormat('Generated %d lines for the service test.', [Lines.Count]));
  finally
  end;
end;

procedure EmitCallTestHeader(
  Lines: TPascalStringList;
  const UnitName, AppName, P2PName: TP_String);
begin
  Lines.Add(#39 + 'use strict' + #39 + ';');
  Lines.Add('');
  Lines.Add('const lf = require(' + JsStrLit('lingofuse-js') + ');');
  Lines.Add('const call = require(' + JsStrLit('./' + UnitName + '_abi_call.js') + ');');
  Lines.Add('const _binding = lf._binding;');
  Lines.Add('const _koffi = _binding.koffi;');
  Lines.Add('const funcs = _binding.getBinding().funcs;');
  Lines.Add('const LfCallFunc = _binding.LfCallFunc;');
  Lines.Add('');
  Lines.Add('const ENDPOINT = ' + JsStrLit('ipc:' + AppName) + ';');
  Lines.Add('const APP_NAME = ' + JsStrLit(AppName) + ';');
  Lines.Add('const P2P_NAME = ' + JsStrLit(P2PName) + ';');
  Lines.Add('const WHOAMI_API = ' + JsStrLit('LF_TEST_WHOAMI') + ';');
  Lines.Add('const ASK_CALL_ME_API = ' + JsStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
  Lines.Add('const REPORT_IDENTITY_API = ' + JsStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
  Lines.Add('const CLIENT_APP_NAME = ' + JsStrLit('LF_TEST_CLIENT_SELF') + ';');
  Lines.Add('');
  Lines.Add('const STATUS_OK = 0x00;');
  Lines.Add('');
  Lines.Add('const _g = { pass: 0, fail: 0, skip: 0 };');
  Lines.Add('let _hasServiceUID = false;');
  Lines.Add('let _serviceUID = new Uint8Array(32);');
  Lines.Add('let _serviceP2P = ' + #39 + #39 + ';');
  Lines.Add('let _serviceCalledMe = false;');
  Lines.Add('');
  Lines.Add('function _race(promise, timeoutMs, label) {');
  Lines.Add('    let timer = null;');
  Lines.Add('    const timeout = new Promise((_, reject) => {');
  Lines.Add('        timer = setTimeout(() => {');
  Lines.Add('            reject(new Error(' + JsStrLit('race timeout after ') + ' + timeoutMs + ' + JsStrLit('ms') + '));');
  Lines.Add('        }, timeoutMs);');
  Lines.Add('    });');
  Lines.Add('    return Promise.race([promise, timeout]).then(');
  Lines.Add('        (v) => { if (timer) clearTimeout(timer); return v; },');
  Lines.Add('        (e) => { if (timer) clearTimeout(timer); throw e; }');
  Lines.Add('    );');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('process.on(' + JsStrLit('unhandledRejection') + ', (reason) => {');
  Lines.Add('    const msg = ' + JsStrLit('unhandledRejection: ') + ' + ((reason && reason.message) ? reason.message : String(reason));');
  Lines.Add('    console.log(' + JsStrLit('[FATAL] ') + ' + msg);');
  Lines.Add('    console.error(' + JsStrLit('[FATAL] ') + ' + msg);');
  Lines.Add('});');
  Lines.Add('');
  Lines.Add('process.on(' + JsStrLit('uncaughtException') + ', (err) => {');
  Lines.Add('    const msg = ' + JsStrLit('uncaughtException: ') + ' + ((err && err.message) ? err.message : String(err));');
  Lines.Add('    console.log(' + JsStrLit('[FATAL] ') + ' + msg);');
  Lines.Add('    console.error(' + JsStrLit('[FATAL] ') + ' + msg);');
  Lines.Add('    process.exit(3);');
  Lines.Add('});');
  Lines.Add('');
  Lines.Add('function _reportPass(label, value) {');
  Lines.Add('    _g.pass++;');
  Lines.Add('    let line;');
  Lines.Add('    if (value === undefined) {');
  Lines.Add('        line = ' + JsStrLit('[PASS] ') + ' + label;');
  Lines.Add('    } else if (value === ' + #39 + #39 + ') {');
  Lines.Add('        line = ' + JsStrLit('[PASS] ') + ' + label;');
  Lines.Add('    } else {');
  Lines.Add('        line = ' + JsStrLit('[PASS] ') + ' + label + ' + JsStrLit(' = ') + ' + String(value);');
  Lines.Add('    }');
  Lines.Add('    console.log(line);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _reportFail(label, reason) {');
  Lines.Add('    _g.fail++;');
  Lines.Add('    const line = ' + JsStrLit('[FAIL] ') + ' + label + ' + JsStrLit(' -- ') + ' + reason;');
  Lines.Add('    console.log(line);');
  Lines.Add('    console.error(line);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _reportSkip(label, reason) {');
  Lines.Add('    _g.skip++;');
  Lines.Add('    const line = ' + JsStrLit('[SKIP] ') + ' + label + ' + JsStrLit(' -- ') + ' + reason;');
  Lines.Add('    console.log(line);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _errMsg(e) {');
  Lines.Add('    if (e === null || e === undefined) return ' + JsStrLit('undefined') + ';');
  Lines.Add('    return (e && e.message) ? e.message : String(e);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _bytesToHex(uid) {');
  Lines.Add('    let s = ' + #39 + #39 + ';');
  Lines.Add('    for (let i = 0; i < uid.length; i++) {');
  Lines.Add('        s += uid[i].toString(16).padStart(2, ' + JsStrLit('0') + ').toUpperCase();');
  Lines.Add('    }');
  Lines.Add('    return s;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function reportIdentityCb(_trigger, input, output) {');
  Lines.Add('    const inH = lf.DataHandle.fromRaw(input, false);');
  Lines.Add('    const outH = lf.DataHandle.fromRaw(output, false);');
  Lines.Add('    try {');
  Lines.Add('        _serviceUID = inH.getP2PUid();');
  Lines.Add('        _serviceP2P = inH.getP2PName();');
  Lines.Add('        _hasServiceUID = true;');
  Lines.Add('        _serviceCalledMe = true;');
  Lines.Add('        let msg = ' + #39 + #39 + ';');
  Lines.Add('        try { msg = inH.readString(); } catch (_) {}');
  Lines.Add('        console.log(' + JsStrLit('[CLIENT] service called me: ') + ' + msg);');
  Lines.Add('        outH.writeUInt8(STATUS_OK);');
  Lines.Add('        outH.writeString(' + JsStrLit('identity received') + ');');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        try {');
  Lines.Add('            outH.size = 0;');
  Lines.Add('            outH.position = 0;');
  Lines.Add('            outH.writeUInt8(0xFF);');
  Lines.Add('            outH.writeString(_errMsg(_e));');
  Lines.Add('        } catch (_) {}');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function _probeIdentity() {');
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
  Lines.Add('                for (let i = 0; i < 32; i++) { if (uid[i] !== 0) { nonZero = true; break; } }');
  Lines.Add('                if (!nonZero) return false;');
  Lines.Add('                _serviceUID = uid;');
  Lines.Add('                _serviceP2P = p2p;');
  Lines.Add('                _hasServiceUID = true;');
  Lines.Add('                console.log(' + JsStrLit('[INFO] service UID = ') + ' + _bytesToHex(uid));');
  Lines.Add('                console.log(' + JsStrLit('[INFO] service P2P = ') + ' + p2p);');
  Lines.Add('                return true;');
  Lines.Add('            } finally {');
  Lines.Add('                res.dispose();');
  Lines.Add('            }');
  Lines.Add('        } finally {');
  Lines.Add('            param.dispose();');
  Lines.Add('        }');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        console.error(' + JsStrLit('[WARN] whoami probe failed: ') + ' + _errMsg(_e));');
  Lines.Add('        return false;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('async function _testServiceInitiatesCall() {');
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
  Lines.Add('        await new Promise(r => setTimeout(r, 10));');
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
  Lines.Add('    try { _reportPass(' + JsStrLit(Label_) + ', await _race(' + CallExpr + ', 10000, ' + JsStrLit(Label_) + ')); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(Label_) + ', _errMsg(e)); }');
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

  Lines.Add('async function test_' + ApiName + '() {');

  Lines.Add('    try { _reportPass(' + JsStrLit(ApiName + '(app call)') + ', call.' + ApiName + '(' + ActualArgs + ')); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(ApiName + '(app call)') + ', _errMsg(e)); }');
  Lines.Add('');

  EmitAsyncTestBlock(Lines, ApiName + '(app async)',
    'call.' + ApiName + 'Async(' + ActualArgs + ')');
  EmitAsyncTestBlock(Lines, ApiName + '(app asyncSeq)',
    'call.' + ApiName + 'Sequenced(' + ActualArgs + ')');
  Lines.Add('');

  Lines.Add('    if (_hasServiceUID) {');
  Lines.Add('        try { _reportPass(' + JsStrLit(ApiName + '(uid call)') + ', call.' + ApiName + 'ByUid(_serviceUID' + ArgsWithComma + ')); }');
  Lines.Add('        catch (e) { _reportFail(' + JsStrLit(ApiName + '(uid call)') + ', _errMsg(e)); }');
  EmitAsyncTestBlock(Lines, ApiName + '(uid async)',
    'call.' + ApiName + 'ByUidAsync(_serviceUID' + ArgsWithComma + ')');
  EmitAsyncTestBlock(Lines, ApiName + '(uid asyncSeq)',
    'call.' + ApiName + 'ByUidSequenced(_serviceUID' + ArgsWithComma + ')');
  Lines.Add('    } else {');
  Lines.Add('        _reportSkip(' + JsStrLit(ApiName + '(uid call)') + ', ' + JsStrLit('no service UID') + ');');
  Lines.Add('        _reportSkip(' + JsStrLit(ApiName + '(uid async)') + ', ' + JsStrLit('no service UID') + ');');
  Lines.Add('        _reportSkip(' + JsStrLit(ApiName + '(uid asyncSeq)') + ', ' + JsStrLit('no service UID') + ');');
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    try { _reportPass(' + JsStrLit(ApiName + '(p2pname call)') + ', call.' + ApiName + 'ByP2PName(P2P_NAME' + ArgsWithComma + ')); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(ApiName + '(p2pname call)') + ', _errMsg(e)); }');
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname async)',
    'call.' + ApiName + 'ByP2PNameAsync(P2P_NAME' + ArgsWithComma + ')');
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname asyncSeq)',
    'call.' + ApiName + 'ByP2PNameSequenced(P2P_NAME' + ArgsWithComma + ')');

  Lines.Add('}');
  Lines.Add('');
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

  Lines.Add('function test_' + ApiName + '() {');

  Lines.Add('    try { call.' + ApiName + '(' + ActualArgs + '); _reportPass(' + JsStrLit(ApiName + '(app notify)') + '); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(ApiName + '(app notify)') + ', _errMsg(e)); }');
  Lines.Add('');

  Lines.Add('    try { call.' + ApiName + 'Sequenced(' + ActualArgs + '); _reportPass(' + JsStrLit(ApiName + '(app seq notify)') + '); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(ApiName + '(app seq notify)') + ', _errMsg(e)); }');
  Lines.Add('');

  Lines.Add('    if (_hasServiceUID) {');
  Lines.Add('        try { call.' + ApiName + 'ByUid(_serviceUID' + ArgsWithComma + '); _reportPass(' + JsStrLit(ApiName + '(uid notify)') + '); }');
  Lines.Add('        catch (e) { _reportFail(' + JsStrLit(ApiName + '(uid notify)') + ', _errMsg(e)); }');
  Lines.Add('        try { call.' + ApiName + 'ByUidSequenced(_serviceUID' + ArgsWithComma + '); _reportPass(' + JsStrLit(ApiName + '(uid seq notify)') + '); }');
  Lines.Add('        catch (e) { _reportFail(' + JsStrLit(ApiName + '(uid seq notify)') + ', _errMsg(e)); }');
  Lines.Add('    } else {');
  Lines.Add('        _reportSkip(' + JsStrLit(ApiName + '(uid notify)') + ', ' + JsStrLit('no service UID') + ');');
  Lines.Add('        _reportSkip(' + JsStrLit(ApiName + '(uid seq notify)') + ', ' + JsStrLit('no service UID') + ');');
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    try { call.' + ApiName + 'ByP2PName(P2P_NAME' + ArgsWithComma + '); _reportPass(' + JsStrLit(ApiName + '(p2pname notify)') + '); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(ApiName + '(p2pname notify)') + ', _errMsg(e)); }');
  Lines.Add('    try { call.' + ApiName + 'ByP2PNameSequenced(P2P_NAME' + ArgsWithComma + '); _reportPass(' + JsStrLit(ApiName + '(p2pname seq notify)') + '); }');
  Lines.Add('    catch (e) { _reportFail(' + JsStrLit(ApiName + '(p2pname seq notify)') + ', _errMsg(e)); }');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestMain(
  Lines: TPascalStringList;
  const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('async function main() {');
  Lines.Add('    lf.loadLibrary();');
  Lines.Add('    lf.framework.setOption(' + JsStrLit('Quiet') + ', ' + JsStrLit('True') + ');');
  Lines.Add('    lf.framework.setOption(' + JsStrLit('ConsoleOutput') + ', ' + JsStrLit('True') + ');');
  Lines.Add('');
  Lines.Add('    call.ABI_TargetApp = APP_NAME;');
  Lines.Add('    call.ABI_Timeout = 5000;');
  Lines.Add('');
  Lines.Add('    const client = new lf.AppHandle(CLIENT_APP_NAME, ' + JsStrLit('client test') + ');');
  Lines.Add('');
  Lines.Add('    const cbReportIdentity = _koffi.register(reportIdentityCb, _koffi.pointer(LfCallFunc));');
  Lines.Add('    funcs.LF_RegisterCall(client.raw, REPORT_IDENTITY_API, ' + JsStrLit('report identity') + ', null, cbReportIdentity);');
  Lines.Add('');
  Lines.Add('    lf.framework.resetPrepare();');
  Lines.Add('    lf.framework.prepareClient(ENDPOINT, client);');
  Lines.Add('');
  Lines.Add('    if (lf.framework.prepareDone() !== 1) {');
  Lines.Add('        console.error(' + JsStrLit('[FATAL] prepareDone failed') + ');');
  Lines.Add('        process.exit(1);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    console.log(' + JsStrLit('[OK] client online') + ');');
  Lines.Add('');
  Lines.Add('    for (let i = 0; i < 200; i++) {');
  Lines.Add('        if (lf.status.checkApp(APP_NAME)) break;');
  Lines.Add('        await new Promise(r => setTimeout(r, 100));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (_probeIdentity()) {');
  Lines.Add('        console.log(' + JsStrLit('[OK] client identity probe') + ');');
  Lines.Add('    } else {');
  Lines.Add('        console.log(' + JsStrLit('[WARN] whoami failed, UID tests will be skipped') + ');');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (await _testServiceInitiatesCall()) {');
  Lines.Add('        console.log(' + JsStrLit('[OK] service-initiated call') + ');');
  Lines.Add('    } else {');
  Lines.Add('        _reportFail(' + JsStrLit('service-initiated call') + ', ' + JsStrLit('timeout or no service UID') + ');');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    console.log(' + JsStrLit('[INFO] total tests scheduled: ') + ' + ' + umlIntToStr(ApiNames.Count).Text + ');');

  for i := 0 to ApiNames.Count - 1 do
    Lines.Add('    await test_' + ApiNames[i] + '();');

  Lines.Add('');
  Lines.Add('    console.log(' + #39 + #39 + ');');
  Lines.Add('    console.log(' + JsStrLit('=== Summary ===') + ');');
  Lines.Add('    console.log(' + JsStrLit('Pass: ') + ' + _g.pass);');
  Lines.Add('    console.log(' + JsStrLit('Fail: ') + ' + _g.fail);');
  Lines.Add('    console.log(' + JsStrLit('Skip: ') + ' + _g.skip);');
  Lines.Add('');
  Lines.Add('    try { lf.AsyncBridge.shutdownInstance(); } catch (_) {}');
  Lines.Add('    try { lf.network.clearNetworkEvent(); } catch (_) {}');
  Lines.Add('    try { lf.framework.exitMainThread(); } catch (_) {}');
  Lines.Add('    try { lf.framework.shutdown(); } catch (_) {}');
  Lines.Add('    process.exit(_g.fail === 0 ? 0 : 2);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('main().catch(e => {');
  Lines.Add('    const msg = _errMsg(e);');
  Lines.Add('    console.log(' + JsStrLit('[FATAL] ') + ' + msg);');
  Lines.Add('    console.error(' + JsStrLit('[FATAL] ') + ' + msg);');
  Lines.Add('    process.exit(1);');
  Lines.Add('});');
end;

function GenerateABICallTestNodejsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, AppName, P2PName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
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

  Log(PFormat('Generating Node.js ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating a skeleton test.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    EmitCallTestHeader(Lines, UnitName, AppName, P2PName);

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

      if F.IsFunction then
        EmitCallTestFunctionBlock(Lines, ApiName, F)
      else
        EmitCallTestProcedureBlock(Lines, ApiName, F);
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
    'nodejs',
    'xxx_abi_service_test.js',
    gkTest,
    'Node.js ABI service test',
    @GenerateABIServiceTestNodejsCode);

  RegisterGenerator(
    'nodejs',
    'xxx_abi_call_test.js',
    gkTest,
    'Node.js ABI call test',
    @GenerateABICallTestNodejsCode);

end.
