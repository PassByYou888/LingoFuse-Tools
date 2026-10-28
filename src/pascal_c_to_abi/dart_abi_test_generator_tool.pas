unit dart_abi_test_generator_tool;

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

function GenerateABIServiceTestDartCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestDartCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Dart_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'int'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'int'
  else if T.Same('word') then
    Result := 'int'
  else if T.Same('smallint') then
    Result := 'int'
  else if T.Same('byte') then
    Result := 'int'
  else if T.Same('uint64') then
    Result := 'int'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'double'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Dart_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsDartKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('assert') or S.Same('async') or
    S.Same('await') or S.Same('break') or S.Same('case') or S.Same('catch') or
    S.Same('class') or S.Same('const') or S.Same('continue') or S.Same('covariant') or
    S.Same('default') or S.Same('deferred') or S.Same('do') or S.Same('dynamic') or
    S.Same('else') or S.Same('enum') or S.Same('export') or S.Same('extends') or
    S.Same('extension') or S.Same('external') or S.Same('factory') or S.Same('false') or
    S.Same('final') or S.Same('finally') or S.Same('for') or S.Same('Function') or
    S.Same('get') or S.Same('hide') or S.Same('if') or S.Same('implements') or
    S.Same('import') or S.Same('in') or S.Same('interface') or S.Same('is') or
    S.Same('late') or S.Same('library') or S.Same('mixin') or S.Same('new') or
    S.Same('null') or S.Same('on') or S.Same('operator') or S.Same('part') or
    S.Same('required') or S.Same('rethrow') or S.Same('return') or S.Same('set') or
    S.Same('show') or S.Same('static') or S.Same('super') or S.Same('switch') or
    S.Same('sync') or S.Same('this') or S.Same('throw') or S.Same('true') or
    S.Same('try') or S.Same('typedef') or S.Same('var') or S.Same('void') or
    S.Same('while') or S.Same('with') or S.Same('yield');
end;

function IsDartReservedLocal(const S: TP_String): boolean;
begin
  Result :=
    S.Same('ctx') or S.Same('uid') or S.Same('onResult') or
    S.Same('param') or S.Same('target') or S.Same('p2pName') or
    S.Same('name') or S.Same('abi');
end;

function MakeSafeDartIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsDartKeyword(Result) then
    Result := Result + '_';

  if IsDartReservedLocal(Result) then
    Result := Result + '_param';

  if Result.ComparePos(1, '_lf_') or Result.ComparePos(1, '_u_') then
    Result := '_u_' + Result;
end;

function DartStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
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
      Result.Append(c);
  end;
  Result.Append(#39);
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

function BuildDartArgPlaceholderList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    if IsStringABIType(Params[i].PascalType) then
      Result := Result + DartStrLit('test')
    else if Params[i].PascalType.Same('double') or
      Params[i].PascalType.Same('single') or
      Params[i].PascalType.Same('extended') or
      Params[i].PascalType.Same('real') then
      Result := Result + '42.0'
    else
      Result := Result + '42';
  end;
end;

function MakeUniqueApiName(const Source: TP_String; Used: TPascalStringList): TP_String;
var
  j: integer;
begin
  Result := MakeApiName(Source);
  if Used.IndexOf(Result) >= 0 then
  begin
    j := 1;
    while Used.IndexOf(Result + '_' + umlIntToStr(j).Text) >= 0 do
      Inc(j);
    Result := Result + '_' + umlIntToStr(j).Text;
  end;
  Used.Add(Result);
end;

procedure EmitServiceTestHeader(Lines: TPascalStringList;
  const ImportFileName, AppName, AppDesc, P2PName, Endpoint: TP_String);
begin
  Lines.Add('// ignore_for_file: non_constant_identifier_names, unused_local_variable, unnecessary_statements');
  Lines.Add('');
  Lines.Add('import ' + DartStrLit('dart:async') + ';');
  Lines.Add('import ' + DartStrLit('dart:io') + ';');
  Lines.Add('import ' + DartStrLit('dart:typed_data') + ';');
  Lines.Add('');
  Lines.Add('import ' + DartStrLit('package:lingofuse/lingofuse.dart') + ';');
  Lines.Add('import ' + DartStrLit(ImportFileName) + ' as svc;');
  Lines.Add('');
  Lines.Add('const String kEndpoint = ' + DartStrLit(Endpoint) + ';');
  Lines.Add('const String kAppName = ' + DartStrLit(AppName) + ';');
  Lines.Add('const String kAppDesc = ' + DartStrLit(AppDesc) + ';');
  Lines.Add('const String kP2PName = ' + DartStrLit(P2PName) + ';');
  Lines.Add('const String kWhoAmIApi = ' + DartStrLit('LF_TEST_WHOAMI') + ';');
  Lines.Add('const String kAskCallMeApi = ' + DartStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
  Lines.Add('const String kReportIdentityApi = ' + DartStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
  Lines.Add('const String kStatsApi = ' + DartStrLit('LF_TEST_STATS') + ';');
  Lines.Add('');
  Lines.Add('const int STATUS_OK = 0x00;');
  Lines.Add('const int STATUS_ERROR = 0xFF;');
  Lines.Add('');
  Lines.Add('AppHandle? gApp;');
  Lines.Add('');
end;

procedure EmitServiceTestSpecialCallbacks(Lines: TPascalStringList);
begin
  Lines.Add('Uint8List cbWhoAmI(CallContext ctx) {');
  Lines.Add('  final w = AbiWriter();');
  Lines.Add('  w.writeUInt8(STATUS_OK);');
  Lines.Add('  final uid = ctx.senderUid;');
  Lines.Add('  if (uid.length == 32) {');
  Lines.Add('    w.writeBytes(uid);');
  Lines.Add('  } else {');
  Lines.Add('    w.writeBytes(Uint8List(32));');
  Lines.Add('  }');
  Lines.Add('  w.writeString(ctx.senderP2PName);');
  Lines.Add('  return w.takeBytes();');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('void cbAskServiceCallMe(CallContext ctx) {');
  Lines.Add('  final uid = ctx.senderUid;');
  Lines.Add('  if (uid.length != 32) {');
  Lines.Add('    stdout.writeln(' + DartStrLit('[SERVICE] ask_call_me: sender UID missing') + ');');
  Lines.Add('    return;');
  Lines.Add('  }');
  Lines.Add('  final req = DataHandle(kReportIdentityApi);');
  Lines.Add('  try {');
  Lines.Add('    final w = AbiWriter();');
  Lines.Add('    w.writeString(' + DartStrLit('service initiates call') + ');');
  Lines.Add('    req.writeBytes(w.takeBytes());');
  Lines.Add('    req.position = 0;');
  Lines.Add('    Framework.uidCallAsync(uid, req, (result, error) {');
  Lines.Add('      if (error != null) {');
  Lines.Add('        stdout.writeln(' + DartStrLit('[SERVICE] ask_call_me: error = ') + ' + error.toString());');
  Lines.Add('      } else {');
  Lines.Add('        stdout.writeln(' + DartStrLit('[SERVICE] ask_call_me: client responded') + ');');
  Lines.Add('      }');
  Lines.Add('    });');
  Lines.Add('  } finally {');
  Lines.Add('    req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Uint8List cbGetStats(CallContext ctx) {');
  Lines.Add('  final w = AbiWriter();');
  Lines.Add('  try {');
  Lines.Add('    final r = AbiReader(ctx.payload);');
  Lines.Add('    final apiName = r.readString();');
  Lines.Add('    final count = svc.lf_get_call_stats()[apiName] ?? 0;');
  Lines.Add('    w.writeUInt8(STATUS_OK);');
  Lines.Add('    w.writeInt64(count);');
  Lines.Add('  } catch (e) {');
  Lines.Add('    w.writeUInt8(STATUS_ERROR);');
  Lines.Add('    w.writeString(e.toString());');
  Lines.Add('  }');
  Lines.Add('  return w.takeBytes();');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitServiceTestMain(Lines: TPascalStringList);
begin
  Lines.Add('Future<void> _waitForShutdown() async {');
  Lines.Add('  final done = Completer<void>();');
  Lines.Add('  final sigintSub = ProcessSignal.sigint.watch().listen((_) {');
  Lines.Add('    if (!done.isCompleted) done.complete();');
  Lines.Add('  });');
  Lines.Add('  StreamSubscription<List<int>>? stdinSub;');
  Lines.Add('  try {');
  Lines.Add('    if (stdin.hasTerminal) {');
  Lines.Add('      stdinSub = stdin.listen((_) {');
  Lines.Add('        if (!done.isCompleted) done.complete();');
  Lines.Add('      }, onError: (_) {}, cancelOnError: false);');
  Lines.Add('    }');
  Lines.Add('  } catch (_) {}');
  Lines.Add('  try {');
  Lines.Add('    await done.future;');
  Lines.Add('  } finally {');
  Lines.Add('    await sigintSub.cancel();');
  Lines.Add('    await stdinSub?.cancel();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Future<void> main() async {');
  Lines.Add('  await BridgeHost.start();');
  Lines.Add('  Framework.setOptQuiet(true);');
  Lines.Add('  Framework.setOptOverlapConnection(true);');
  Lines.Add('  Framework.setOptWaitConnectionReadyOk(true);');
  Lines.Add('  Framework.setOptWaitConnectionTimeout(15000);');
  Lines.Add('  Framework.setOptP2PName(kP2PName);');
  Lines.Add('  Framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('  try {');
  Lines.Add('    gApp = svc.create_and_register_abi_app();');
  Lines.Add('    svc.register_all_p2p_abi_apis();');
  Lines.Add('    gApp!.registerCall(kWhoAmIApi, ' + DartStrLit('service whoami') + ', cbWhoAmI);');
  Lines.Add('    gApp!.registerNotify(kAskCallMeApi, ' + DartStrLit('service callback client') + ', cbAskServiceCallMe);');
  Lines.Add('    gApp!.registerCall(kStatsApi, ' + DartStrLit('service call stats') + ', cbGetStats);');
  Lines.Add('    BridgeHost.instance.registerP2PCall(kWhoAmIApi, ' + DartStrLit('service whoami') + ', cbWhoAmI);');
  Lines.Add('    BridgeHost.instance.registerP2PNotify(kAskCallMeApi, ' + DartStrLit('service callback client') + ', cbAskServiceCallMe);');
  Lines.Add('    BridgeHost.instance.registerP2PCall(kStatsApi, ' + DartStrLit('service call stats') + ', cbGetStats);');
  Lines.Add('');
  Lines.Add('    final tag = Framework.prepareService(kEndpoint, kEndpoint);');
  Lines.Add('    if (tag < 0) {');
  Lines.Add('      stderr.writeln(' + DartStrLit('[FATAL] prepareService returned ') + ' + tag.toString());');
  Lines.Add('      exit(1);');
  Lines.Add('    }');
  Lines.Add('    final ctag = Framework.prepareClient(kEndpoint, app: gApp);');
  Lines.Add('    if (ctag < 0) {');
  Lines.Add('      stderr.writeln(' + DartStrLit('[FATAL] prepareClient returned ') + ' + ctag.toString());');
  Lines.Add('      exit(1);');
  Lines.Add('    }');
  Lines.Add('    if (!Framework.prepareDone()) {');
  Lines.Add('      stderr.writeln(' + DartStrLit('[FATAL] prepareDone failed') + ');');
  Lines.Add('      exit(1);');
  Lines.Add('    }');
  Lines.Add('  } catch (e) {');
  Lines.Add('    stderr.writeln(' + DartStrLit('[FATAL] init failed: ') + ' + e.toString());');
  Lines.Add('    exit(1);');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] service ready on ') + ' + kEndpoint);');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] App: ') + ' + kAppName);');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] P2P: ') + ' + kP2PName);');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] Press Enter to shut down') + ');');
  Lines.Add('');
  Lines.Add('  await _waitForShutdown();');
  Lines.Add('');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] shutting down') + ');');
  Lines.Add('  try { Framework.exitMainThread(); } catch (_) {}');
  Lines.Add('  if (gApp != null) {');
  Lines.Add('    try { gApp!.dispose(); } catch (_) {}');
  Lines.Add('    gApp = null;');
  Lines.Add('  }');
  Lines.Add('  try { Framework.shutdown(); } catch (_) {}');
  Lines.Add('  try { BridgeHost.instance.stop(); } catch (_) {}');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] shutdown complete') + ');');
  Lines.Add('  exit(0);');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceTestDartCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, AppDesc, P2PName, Endpoint, ImportFileName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestDartCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestDartCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;
  P2PName := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + AppName;
  ImportFileName := NormalizedUnit + '_abi_service.dart';

  Log(PFormat('Generating Dart ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    EmitServiceTestHeader(Lines, ImportFileName, AppName, AppDesc, P2PName, Endpoint);
    EmitServiceTestSpecialCallbacks(Lines);
    EmitServiceTestMain(Lines);
    Result := Lines;
    Log(PFormat('Generated %d lines for Dart ABI service test', [Lines.Count]));
  finally
  end;
end;

procedure EmitCallTestHeader(Lines: TPascalStringList;
  const ImportFileName, Endpoint, AppName, P2PName, ClientApp: TP_String);
begin
  Lines.Add('// ignore_for_file: non_constant_identifier_names, unused_local_variable, unnecessary_statements');
  Lines.Add('');
  Lines.Add('import ' + DartStrLit('dart:async') + ';');
  Lines.Add('import ' + DartStrLit('dart:io') + ';');
  Lines.Add('import ' + DartStrLit('dart:isolate') + ';');
  Lines.Add('import ' + DartStrLit('dart:typed_data') + ';');
  Lines.Add('');
  Lines.Add('import ' + DartStrLit('package:lingofuse/lingofuse.dart') + ';');
  Lines.Add('import ' + DartStrLit(ImportFileName) + ' as abi;');
  Lines.Add('');
  Lines.Add('const String kEndpoint = ' + DartStrLit(Endpoint) + ';');
  Lines.Add('const String kServiceApp = ' + DartStrLit(AppName) + ';');
  Lines.Add('const String kServiceP2PName = ' + DartStrLit(P2PName) + ';');
  Lines.Add('const String kClientApp = ' + DartStrLit(ClientApp) + ';');
  Lines.Add('const String kWhoAmIApi = ' + DartStrLit('LF_TEST_WHOAMI') + ';');
  Lines.Add('const String kAskCallMeApi = ' + DartStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ';');
  Lines.Add('const String kReportIdentityApi = ' + DartStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ';');
  Lines.Add('const String kStatsApi = ' + DartStrLit('LF_TEST_STATS') + ';');
  Lines.Add('');
  Lines.Add('int gPass = 0;');
  Lines.Add('int gFail = 0;');
  Lines.Add('int gSkip = 0;');
  Lines.Add('bool gServiceCalledMe = false;');
  Lines.Add('Uint8List gClientUid = Uint8List(32);');
  Lines.Add('String gClientP2P = ' + DartStrLit('') + ';');
  Lines.Add('Uint8List gServiceUid = Uint8List(32);');
  Lines.Add('String gServiceP2P = ' + DartStrLit('') + ';');
  Lines.Add('bool gStatsAvailable = false;');
  Lines.Add('');
  Lines.Add('void _reportPass(String label, [String? detail]) {');
  Lines.Add('  if (detail != null && detail.isNotEmpty) {');
  Lines.Add('    stdout.writeln(' + DartStrLit('[PASS] ') + ' + label + ' + DartStrLit(' = ') + ' + detail);');
  Lines.Add('  } else {');
  Lines.Add('    stdout.writeln(' + DartStrLit('[PASS] ') + ' + label);');
  Lines.Add('  }');
  Lines.Add('  gPass++;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('void _reportFail(String label, String reason) {');
  Lines.Add('  stdout.writeln(' + DartStrLit('[FAIL] ') + ' + label + ' + DartStrLit(' -- ') + ' + reason);');
  Lines.Add('  gFail++;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('void _reportSkip(String label, String reason) {');
  Lines.Add('  stdout.writeln(' + DartStrLit('[SKIP] ') + ' + label + ' + DartStrLit(' -- ') + ' + reason);');
  Lines.Add('  gSkip++;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('String _uidPrefixHex(Uint8List uid) {');
  Lines.Add('  if (uid.isEmpty) return ' + DartStrLit('') + ';');
  Lines.Add('  final n = uid.length < 8 ? uid.length : 8;');
  Lines.Add('  final sb = StringBuffer();');
  Lines.Add('  for (int i = 0; i < n; i++) {');
  Lines.Add('    sb.write(uid[i].toRadixString(16).padLeft(2, ' + DartStrLit('0') + '));');
  Lines.Add('  }');
  Lines.Add('  return sb.toString();');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('bool _uidIsNonZero(Uint8List uid) {');
  Lines.Add('  for (final b in uid) {');
  Lines.Add('    if (b != 0) return true;');
  Lines.Add('  }');
  Lines.Add('  return false;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Uint8List cbReportIdentity(CallContext ctx) {');
  Lines.Add('  gServiceCalledMe = true;');
  Lines.Add('  gServiceUid = Uint8List.fromList(ctx.senderUid);');
  Lines.Add('  gServiceP2P = ctx.senderP2PName;');
  Lines.Add('  String msg = ' + DartStrLit('') + ';');
  Lines.Add('  try {');
  Lines.Add('    final r = AbiReader(ctx.payload);');
  Lines.Add('    msg = r.readString();');
  Lines.Add('  } catch (_) {}');
  Lines.Add('  stdout.writeln(' + DartStrLit('[CLIENT] service called me: msg=') + ' + msg);');
  Lines.Add('  final w = AbiWriter();');
  Lines.Add('  w.writeUInt8(0x00);');
  Lines.Add('  w.writeString(' + DartStrLit('identity received') + ');');
  Lines.Add('  return w.takeBytes();');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestHelpers(Lines: TPascalStringList);
begin
  Lines.Add('Future<void> _waitAsync<T>(String label, void Function(void Function(T?, String?)) starter) async {');
  Lines.Add('  final completer = Completer<T?>();');
  Lines.Add('  starter((result, error) {');
  Lines.Add('    if (completer.isCompleted) return;');
  Lines.Add('    if (error != null) {');
  Lines.Add('      completer.completeError(StateError(error));');
  Lines.Add('    } else {');
  Lines.Add('      completer.complete(result);');
  Lines.Add('    }');
  Lines.Add('  });');
  Lines.Add('  try {');
  Lines.Add('    final r = await completer.future.timeout(Duration(seconds: 10));');
  Lines.Add('    _reportPass(label, r?.toString() ?? ' + DartStrLit('null') + ');');
  Lines.Add('  } catch (e) {');
  Lines.Add('    _reportFail(label, e.toString());');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Future<int?> _getStats(String apiName) async {');
  Lines.Add('  final req = DataHandle(kStatsApi);');
  Lines.Add('  try {');
  Lines.Add('    final w = AbiWriter();');
  Lines.Add('    w.writeString(apiName);');
  Lines.Add('    req.writeBytes(w.takeBytes());');
  Lines.Add('    req.position = 0;');
  Lines.Add('    final resp = Framework.call(kServiceApp, req, timeoutMs: 3000);');
  Lines.Add('    try {');
  Lines.Add('      final bytes = resp.readAllBytes();');
  Lines.Add('      if (bytes.isEmpty) return null;');
  Lines.Add('      final r = AbiReader(bytes);');
  Lines.Add('      if (r.readUInt8() != 0) return null;');
  Lines.Add('      return r.readInt64();');
  Lines.Add('    } finally {');
  Lines.Add('      resp.dispose();');
  Lines.Add('    }');
  Lines.Add('  } catch (_) {');
  Lines.Add('    return null;');
  Lines.Add('  } finally {');
  Lines.Add('    req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Future<void> _probeStats() async {');
  Lines.Add('  for (int i = 0; i < 15; i++) {');
  Lines.Add('    if (Framework.checkApi(kServiceApp, kStatsApi)) {');
  Lines.Add('      gStatsAvailable = true;');
  Lines.Add('      return;');
  Lines.Add('    }');
  Lines.Add('    await Future.delayed(Duration(milliseconds: 200));');
  Lines.Add('  }');
  Lines.Add('  gStatsAvailable = false;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestWhoAmI(Lines: TPascalStringList);
begin
  Lines.Add('Future<void> testWhoAmI() async {');
  Lines.Add('  try {');
  Lines.Add('    final result = await Isolate.run(() {');
  Lines.Add('      final req = DataHandle(kWhoAmIApi);');
  Lines.Add('      try {');
  Lines.Add('        final w = AbiWriter();');
  Lines.Add('        w.writeString(' + DartStrLit('') + ');');
  Lines.Add('        req.writeBytes(w.takeBytes());');
  Lines.Add('        req.position = 0;');
  Lines.Add('        final resp = Framework.call(kServiceApp, req, timeoutMs: 10000);');
  Lines.Add('        try {');
  Lines.Add('          return resp.readAllBytes().toList();');
  Lines.Add('        } finally {');
  Lines.Add('          resp.dispose();');
  Lines.Add('        }');
  Lines.Add('      } finally {');
  Lines.Add('        req.dispose();');
  Lines.Add('      }');
  Lines.Add('    });');
  Lines.Add('    if (result.isEmpty) {');
  Lines.Add('      _reportFail(' + DartStrLit('whoami') + ', ' + DartStrLit('empty response') + ');');
  Lines.Add('      return;');
  Lines.Add('    }');
  Lines.Add('    final r = AbiReader(Uint8List.fromList(result));');
  Lines.Add('    if (r.readUInt8() != 0x00) {');
  Lines.Add('      _reportFail(' + DartStrLit('whoami') + ', ' + DartStrLit('status != OK') + ');');
  Lines.Add('      return;');
  Lines.Add('    }');
  Lines.Add('    gClientUid = Uint8List.fromList(r.readBytes(32));');
  Lines.Add('    gClientP2P = r.readString();');
  Lines.Add('    if (_uidIsNonZero(gClientUid)) {');
  Lines.Add('      _reportPass(' + DartStrLit('whoami') + ', ' + DartStrLit('client uid=') + ' + _uidPrefixHex(gClientUid) + ' + DartStrLit('... p2p=') + ' + gClientP2P);');
  Lines.Add('    } else {');
  Lines.Add('      _reportFail(' + DartStrLit('whoami') + ', ' + DartStrLit('client UID is all-zero') + ');');
  Lines.Add('    }');
  Lines.Add('  } catch (e) {');
  Lines.Add('    _reportFail(' + DartStrLit('whoami') + ', e.toString());');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestAskCallMe(Lines: TPascalStringList);
begin
  Lines.Add('Future<void> testAskCallMe() async {');
  Lines.Add('  if (!_uidIsNonZero(gClientUid)) {');
  Lines.Add('    _reportSkip(' + DartStrLit('ask_call_me') + ', ' + DartStrLit('no client UID') + ');');
  Lines.Add('    return;');
  Lines.Add('  }');
  Lines.Add('  gServiceCalledMe = false;');
  Lines.Add('  gServiceUid = Uint8List(32);');
  Lines.Add('  gServiceP2P = ' + DartStrLit('') + ';');
  Lines.Add('');
  Lines.Add('  final req = DataHandle(kAskCallMeApi);');
  Lines.Add('  try {');
  Lines.Add('    final w = AbiWriter();');
  Lines.Add('    w.writeString(' + DartStrLit('') + ');');
  Lines.Add('    req.writeBytes(w.takeBytes());');
  Lines.Add('    req.position = 0;');
  Lines.Add('    Framework.notify(kServiceApp, req);');
  Lines.Add('  } finally {');
  Lines.Add('    req.dispose();');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  for (int i = 0; i < 200; i++) {');
  Lines.Add('    if (gServiceCalledMe) break;');
  Lines.Add('    await Future.delayed(Duration(milliseconds: 50));');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (!gServiceCalledMe) {');
  Lines.Add('    _reportFail(' + DartStrLit('ask_call_me') + ', ' + DartStrLit('service did not call back within 10s') + ');');
  Lines.Add('    return;');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (_uidIsNonZero(gServiceUid)) {');
  Lines.Add('    _reportPass(' + DartStrLit('ask_call_me') + ', ' + DartStrLit('service uid=') + ' + _uidPrefixHex(gServiceUid) + ' + DartStrLit('... p2p=') + ' + gServiceP2P);');
  Lines.Add('  } else {');
  Lines.Add('    _reportFail(' + DartStrLit('ask_call_me') + ', ' + DartStrLit('service UID is all-zero') + ');');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestOneFunction(Lines: TPascalStringList;
  const TestFnName, AbiName: TP_String; const F: TFunctionStructure);
var
  Args: TP_String;
  HasArgs: Boolean;
  RetType: TP_String;
  StatsExpectedWithUid, StatsExpectedNoUid: Integer;
begin
  Args := BuildDartArgPlaceholderList(F.Params);
  HasArgs := Args <> '';
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);
  StatsExpectedWithUid := 9;
  StatsExpectedNoUid := 6;

  Lines.Add('Future<void> ' + TestFnName + '() async {');
  Lines.Add('  int? _statsBefore;');
  Lines.Add('  if (gStatsAvailable) { _statsBefore = await _getStats(' + DartStrLit(AbiName) + '); }');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    final v = await abi.' + AbiName + '(' + Args + ');')
  else
    Lines.Add('    final v = await abi.' + AbiName + '();');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(app call)') + ', v.toString());');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(app call)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  await _waitAsync<' + RetType + '>(' + DartStrLit(AbiName + '(app async)') + ', (finish) {');
  if HasArgs then
    Lines.Add('    abi.' + AbiName + 'Async(' + Args + ', finish);')
  else
    Lines.Add('    abi.' + AbiName + 'Async(finish);');
  Lines.Add('  });');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    final v = await abi.' + AbiName + 'Sequenced(' + Args + ');')
  else
    Lines.Add('    final v = await abi.' + AbiName + 'Sequenced();');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(app sequenced)') + ', v.toString());');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(app sequenced)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  if (_uidIsNonZero(gServiceUid)) {');
  Lines.Add('    try {');
  if HasArgs then
    Lines.Add('      final v = await abi.' + AbiName + 'ByUid(gServiceUid, ' + Args + ');')
  else
    Lines.Add('      final v = await abi.' + AbiName + 'ByUid(gServiceUid);');
  Lines.Add('      _reportPass(' + DartStrLit(AbiName + '(uid call)') + ', v.toString());');
  Lines.Add('    } catch (e) { _reportFail(' + DartStrLit(AbiName + '(uid call)') + ', e.toString()); }');
  Lines.Add('  } else {');
  Lines.Add('    _reportSkip(' + DartStrLit(AbiName + '(uid call)') + ', ' + DartStrLit('no service UID') + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (_uidIsNonZero(gServiceUid)) {');
  Lines.Add('    await _waitAsync<' + RetType + '>(' + DartStrLit(AbiName + '(uid async)') + ', (finish) {');
  if HasArgs then
    Lines.Add('      abi.' + AbiName + 'ByUidAsync(gServiceUid, ' + Args + ', finish);')
  else
    Lines.Add('      abi.' + AbiName + 'ByUidAsync(gServiceUid, finish);');
  Lines.Add('    });');
  Lines.Add('  } else {');
  Lines.Add('    _reportSkip(' + DartStrLit(AbiName + '(uid async)') + ', ' + DartStrLit('no service UID') + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (_uidIsNonZero(gServiceUid)) {');
  Lines.Add('    try {');
  if HasArgs then
    Lines.Add('      final v = await abi.' + AbiName + 'ByUidSequenced(gServiceUid, ' + Args + ');')
  else
    Lines.Add('      final v = await abi.' + AbiName + 'ByUidSequenced(gServiceUid);');
  Lines.Add('      _reportPass(' + DartStrLit(AbiName + '(uid sequenced)') + ', v.toString());');
  Lines.Add('    } catch (e) { _reportFail(' + DartStrLit(AbiName + '(uid sequenced)') + ', e.toString()); }');
  Lines.Add('  } else {');
  Lines.Add('    _reportSkip(' + DartStrLit(AbiName + '(uid sequenced)') + ', ' + DartStrLit('no service UID') + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    final v = await abi.' + AbiName + 'ByP2PName(kServiceP2PName, ' + Args + ');')
  else
    Lines.Add('    final v = await abi.' + AbiName + 'ByP2PName(kServiceP2PName);');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(p2pname call)') + ', v.toString());');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(p2pname call)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  await _waitAsync<' + RetType + '>(' + DartStrLit(AbiName + '(p2pname async)') + ', (finish) {');
  if HasArgs then
    Lines.Add('    abi.' + AbiName + 'ByP2PNameAsync(kServiceP2PName, ' + Args + ', finish);')
  else
    Lines.Add('    abi.' + AbiName + 'ByP2PNameAsync(kServiceP2PName, finish);');
  Lines.Add('  });');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    final v = await abi.' + AbiName + 'ByP2PNameSequenced(kServiceP2PName, ' + Args + ');')
  else
    Lines.Add('    final v = await abi.' + AbiName + 'ByP2PNameSequenced(kServiceP2PName);');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(p2pname sequenced)') + ', v.toString());');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(p2pname sequenced)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  if (gStatsAvailable && _statsBefore != null) {');
  Lines.Add('    await Future.delayed(Duration(milliseconds: 500));');
  Lines.Add('    final _statsAfter = await _getStats(' + DartStrLit(AbiName) + ');');
  Lines.Add('    if (_statsAfter != null) {');
  Lines.Add('      final expected = _uidIsNonZero(gServiceUid) ? ' + umlIntToStr(StatsExpectedWithUid).Text + ' : ' + umlIntToStr(StatsExpectedNoUid).Text + ';');
  Lines.Add('      final delta = _statsAfter - _statsBefore!;');
  Lines.Add('      if (delta >= expected) {');
  Lines.Add('        _reportPass(' + DartStrLit(AbiName + '(stats)') + ', ' + DartStrLit('delta=') + ' + delta.toString());');
  Lines.Add('      } else {');
  Lines.Add('        _reportFail(' + DartStrLit(AbiName + '(stats)') + ', ' + DartStrLit('delta=') + ' + delta.toString() + ' + DartStrLit(' expected>=') + ' + expected.toString());');
  Lines.Add('      }');
  Lines.Add('    } else {');
  Lines.Add('      _reportSkip(' + DartStrLit(AbiName + '(stats)') + ', ' + DartStrLit('stats read failed') + ');');
  Lines.Add('    }');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestOneProcedure(Lines: TPascalStringList;
  const TestFnName, AbiName: TP_String; const F: TFunctionStructure);
var
  Args: TP_String;
  HasArgs: Boolean;
  StatsExpectedWithUid, StatsExpectedNoUid: Integer;
begin
  Args := BuildDartArgPlaceholderList(F.Params);
  HasArgs := Args <> '';
  StatsExpectedWithUid := 6;
  StatsExpectedNoUid := 4;

  Lines.Add('Future<void> ' + TestFnName + '() async {');
  Lines.Add('  int? _statsBefore;');
  Lines.Add('  if (gStatsAvailable) { _statsBefore = await _getStats(' + DartStrLit(AbiName) + '); }');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    abi.' + AbiName + 'Notify(' + Args + ');')
  else
    Lines.Add('    abi.' + AbiName + 'Notify();');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(app notify)') + ', ' + DartStrLit('dispatched') + ');');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(app notify)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    abi.' + AbiName + 'SequencedNotify(' + Args + ');')
  else
    Lines.Add('    abi.' + AbiName + 'SequencedNotify();');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(app sequenced notify)') + ', ' + DartStrLit('dispatched') + ');');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(app sequenced notify)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  if (_uidIsNonZero(gServiceUid)) {');
  Lines.Add('    try {');
  if HasArgs then
    Lines.Add('      abi.' + AbiName + 'NotifyByUid(gServiceUid, ' + Args + ');')
  else
    Lines.Add('      abi.' + AbiName + 'NotifyByUid(gServiceUid);');
  Lines.Add('      _reportPass(' + DartStrLit(AbiName + '(uid notify)') + ', ' + DartStrLit('dispatched') + ');');
  Lines.Add('    } catch (e) { _reportFail(' + DartStrLit(AbiName + '(uid notify)') + ', e.toString()); }');
  Lines.Add('  } else {');
  Lines.Add('    _reportSkip(' + DartStrLit(AbiName + '(uid notify)') + ', ' + DartStrLit('no service UID') + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (_uidIsNonZero(gServiceUid)) {');
  Lines.Add('    try {');
  if HasArgs then
    Lines.Add('      abi.' + AbiName + 'SequencedNotifyByUid(gServiceUid, ' + Args + ');')
  else
    Lines.Add('      abi.' + AbiName + 'SequencedNotifyByUid(gServiceUid);');
  Lines.Add('      _reportPass(' + DartStrLit(AbiName + '(uid sequenced notify)') + ', ' + DartStrLit('dispatched') + ');');
  Lines.Add('    } catch (e) { _reportFail(' + DartStrLit(AbiName + '(uid sequenced notify)') + ', e.toString()); }');
  Lines.Add('  } else {');
  Lines.Add('    _reportSkip(' + DartStrLit(AbiName + '(uid sequenced notify)') + ', ' + DartStrLit('no service UID') + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    abi.' + AbiName + 'NotifyByP2PName(kServiceP2PName, ' + Args + ');')
  else
    Lines.Add('    abi.' + AbiName + 'NotifyByP2PName(kServiceP2PName);');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(p2pname notify)') + ', ' + DartStrLit('dispatched') + ');');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(p2pname notify)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  try {');
  if HasArgs then
    Lines.Add('    abi.' + AbiName + 'SequencedNotifyByP2PName(kServiceP2PName, ' + Args + ');')
  else
    Lines.Add('    abi.' + AbiName + 'SequencedNotifyByP2PName(kServiceP2PName);');
  Lines.Add('    _reportPass(' + DartStrLit(AbiName + '(p2pname sequenced notify)') + ', ' + DartStrLit('dispatched') + ');');
  Lines.Add('  } catch (e) { _reportFail(' + DartStrLit(AbiName + '(p2pname sequenced notify)') + ', e.toString()); }');
  Lines.Add('');
  Lines.Add('  if (gStatsAvailable && _statsBefore != null) {');
  Lines.Add('    await Future.delayed(Duration(milliseconds: 500));');
  Lines.Add('    final _statsAfter = await _getStats(' + DartStrLit(AbiName) + ');');
  Lines.Add('    if (_statsAfter != null) {');
  Lines.Add('      final expected = _uidIsNonZero(gServiceUid) ? ' + umlIntToStr(StatsExpectedWithUid).Text + ' : ' + umlIntToStr(StatsExpectedNoUid).Text + ';');
  Lines.Add('      final delta = _statsAfter - _statsBefore!;');
  Lines.Add('      if (delta >= expected) {');
  Lines.Add('        _reportPass(' + DartStrLit(AbiName + '(stats)') + ', ' + DartStrLit('delta=') + ' + delta.toString());');
  Lines.Add('      } else {');
  Lines.Add('        _reportFail(' + DartStrLit(AbiName + '(stats)') + ', ' + DartStrLit('delta=') + ' + delta.toString() + ' + DartStrLit(' expected>=') + ' + expected.toString());');
  Lines.Add('      }');
  Lines.Add('    } else {');
  Lines.Add('      _reportSkip(' + DartStrLit(AbiName + '(stats)') + ', ' + DartStrLit('stats read failed') + ');');
  Lines.Add('    }');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestMain(Lines: TPascalStringList;
  const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('Future<void> main() async {');
  Lines.Add('  await BridgeHost.start();');
  Lines.Add('  Framework.setOptQuiet(true);');
  Lines.Add('  Framework.setOptOverlapConnection(true);');
  Lines.Add('  Framework.setOptWaitConnectionReadyOk(true);');
  Lines.Add('  Framework.setOptWaitConnectionTimeout(15000);');
  Lines.Add('  Framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('  final clientApp = AppHandle(kClientApp, ' + DartStrLit('client test app') + ');');
  Lines.Add('  clientApp.registerCall(kReportIdentityApi, ' + DartStrLit('report service identity') + ', cbReportIdentity);');
  Lines.Add('');
  Lines.Add('  final tag = Framework.prepareClient(kEndpoint, app: clientApp);');
  Lines.Add('  if (tag < 0) {');
  Lines.Add('    stderr.writeln(' + DartStrLit('[FATAL] prepareClient returned ') + ' + tag.toString());');
  Lines.Add('    exit(1);');
  Lines.Add('  }');
  Lines.Add('  if (!Framework.prepareDone()) {');
  Lines.Add('    stderr.writeln(' + DartStrLit('[FATAL] prepareDone failed') + ');');
  Lines.Add('    exit(1);');
  Lines.Add('  }');
  Lines.Add('  stdout.writeln(' + DartStrLit('[READY] Client online.') + ');');
  Lines.Add('');
  Lines.Add('  bool serviceVisible = false;');
  Lines.Add('  for (int i = 0; i < 30; i++) {');
  Lines.Add('    if (Framework.checkApi(kServiceApp, kWhoAmIApi)) {');
  Lines.Add('      serviceVisible = true;');
  Lines.Add('      break;');
  Lines.Add('    }');
  Lines.Add('    await Future.delayed(Duration(milliseconds: 200));');
  Lines.Add('  }');
  Lines.Add('  if (!serviceVisible) {');
  Lines.Add('    stderr.writeln(' + DartStrLit('[FATAL] service not visible after 6s') + ');');
  Lines.Add('    exit(2);');
  Lines.Add('  }');
  Lines.Add('  stdout.writeln(' + DartStrLit('[OK] service visible.') + ');');
  Lines.Add('');
  Lines.Add('  await _probeStats();');
  Lines.Add('  if (gStatsAvailable) {');
  Lines.Add('    stdout.writeln(' + DartStrLit('[OK] stats API available.') + ');');
  Lines.Add('  } else {');
  Lines.Add('    stdout.writeln(' + DartStrLit('[WARN] stats API not available (cross-language service). Stats verification will be skipped.') + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  await testWhoAmI();');
  Lines.Add('  await testAskCallMe();');
  Lines.Add('');

  for i := 0 to ApiNames.Count - 1 do
    Lines.Add('  await test_' + ApiNames[i] + '();');

  Lines.Add('');
  Lines.Add('  stdout.writeln(' + DartStrLit('') + ');');
  Lines.Add('  stdout.writeln(' + DartStrLit('=== Summary ===') + ');');
  Lines.Add('  stdout.writeln(' + DartStrLit('Pass: ') + ' + gPass.toString());');
  Lines.Add('  stdout.writeln(' + DartStrLit('Fail: ') + ' + gFail.toString());');
  Lines.Add('  stdout.writeln(' + DartStrLit('Skip: ') + ' + gSkip.toString());');
  Lines.Add('');
  Lines.Add('  try { Framework.exitMainThread(); } catch (_) {}');
  Lines.Add('  try { clientApp.dispose(); } catch (_) {}');
  Lines.Add('  try { Framework.shutdown(); } catch (_) {}');
  Lines.Add('  try { BridgeHost.instance.stop(); } catch (_) {}');
  Lines.Add('');
  Lines.Add('  exit(gFail == 0 ? 0 : 2);');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallTestDartCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, P2PName, ClientApp, ImportFileName, Endpoint: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, TestFnName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestDartCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestDartCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  ClientApp := NormalizedUnit + '_client_test';
  ImportFileName := NormalizedUnit + '_abi_call.dart';
  Endpoint := 'ipc:' + AppName;

  Log(PFormat('Generating Dart ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    EmitCallTestHeader(Lines, ImportFileName, Endpoint, AppName, P2PName, ClientApp);
    EmitCallTestHelpers(Lines);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeUniqueApiName(SupportedFuncs[i].Name, UsedApiNames);
      TestFnName := 'test_' + ApiName.Text;
      if SupportedFuncs[i].IsFunction then
        EmitCallTestOneFunction(Lines, TestFnName, ApiName, SupportedFuncs[i])
      else
        EmitCallTestOneProcedure(Lines, TestFnName, ApiName, SupportedFuncs[i]);
    end;

    EmitCallTestWhoAmI(Lines);
    EmitCallTestAskCallMe(Lines);
    EmitCallTestMain(Lines, UsedApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines for Dart ABI call test', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'dart',
    'xxx_abi_service_test.dart',
    gkTest,
    'Dart ABI service test program',
    @GenerateABIServiceTestDartCode);

  RegisterGenerator(
    'dart',
    'xxx_abi_call_test.dart',
    gkTest,
    'Dart ABI call test program',
    @GenerateABICallTestDartCode);

end.
