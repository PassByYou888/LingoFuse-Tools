unit java_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestJavaCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestJavaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or
    T.Same('pwidechar');
end;

function ABI_Type_To_Java_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'long'
  else if T.Same('word') then
    Result := 'int'
  else if T.Same('smallint') then
    Result := 'short'
  else if T.Same('byte') then
    Result := 'byte'
  else if T.Same('uint64') then
    Result := 'long'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Java_Boxed(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'Integer'
  else if T.Same('int64') then
    Result := 'Long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'Long'
  else if T.Same('word') then
    Result := 'Integer'
  else if T.Same('smallint') then
    Result := 'Short'
  else if T.Same('byte') then
    Result := 'Byte'
  else if T.Same('uint64') then
    Result := 'Long'
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
  Result := ABI_Type_To_Java_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function JavaStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
begin
  Result := TP_String('"');
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
      Result := Result + TP_String('\') + TP_String('"')
    else if c = '\' then
      Result := Result + TP_String('\') + TP_String('\')
    else if c = #10 then
      Result := Result + TP_String('\') + TP_String('n')
    else if c = #13 then
      Result := Result + TP_String('\') + TP_String('r')
    else if c = #9 then
      Result := Result + TP_String('\') + TP_String('t')
    else if (Ord(c) < 32) or (Ord(c) > 126) then
    begin
      Code := Ord(c);
      Result := Result + TP_String('\') + TP_String('u') +
        TP_String(IntToHex(Code, 4));
    end
    else
      Result.Append(c);
  end;
  Result := Result + TP_String('"');
end;

function JavaPackageName(const UnitName: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := TP_String('lingofuse.abi.');
  for i := 1 to UnitName.Len do
  begin
    c := UnitName[i];
    if (c >= 'A') and (c <= 'Z') then
      Result.Append(TP_Char(Ord(c) + 32))
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append(TP_Char('_'));
  end;
end;

function PlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := JavaStrLit(TP_String('test'))
  else if ABIType.Same('double') or ABIType.Same('extended') or
          ABIType.Same('real') then
    Result := TP_String('0.0')
  else if ABIType.Same('single') then
    Result := TP_String('0.0f')
  else if ABIType.Same('int64') or ABIType.Same('uint64') then
    Result := TP_String('0L')
  else if ABIType.Same('cardinal') or ABIType.Same('dword') or
          ABIType.Same('longword') then
    Result := TP_String('0L')
  else if ABIType.Same('byte') then
    Result := TP_String('(byte) 0')
  else if ABIType.Same('smallint') then
    Result := TP_String('(short) 0')
  else
    Result := TP_String('0');
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
        Log(TP_String(PFormat(
          'Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text])));
        Break;
      end;
    if Supported and f.IsFunction and
       (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(TP_String(PFormat(
        'Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text])));
    end;
    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log(TP_String('Skipped: routine with empty Name'));
    end;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function TestParamName(Index: integer): TP_String;
begin
  Result := TP_String('_p') + TP_String(umlIntToStr(Index).Text);
end;

procedure EmitTestParamDecl(Lines: TPascalStringList; const Params: TParamArray);
var
  i: integer;
  PTyp: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PTyp := ABI_Type_To_Java_Decl(Params[i].PascalType);
    Lines.Add('        ' + PTyp.Text + ' ' + TestParamName(i).Text + ';');
  end;
end;

procedure EmitTestParamInit(Lines: TPascalStringList; const Params: TParamArray);
var
  i: integer;
begin
  for i := 0 to High(Params) do
  begin
    Lines.Add('        ' + TestParamName(i).Text + ' = ' +
      PlaceholderValue(Params[i].PascalType).Text + ';');
  end;
end;

function BuildTestArgListSuffix(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := TP_String('');
  for i := 0 to High(Params) do
  begin
    Result := Result + TP_String(', ') + TestParamName(i);
  end;
end;

procedure EmitReportHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    static int gPass = 0;');
  Lines.Add('    static int gFail = 0;');
  Lines.Add('    static int gSkip = 0;');
  Lines.Add('');
  Lines.Add('    static void reportPass(String label) {');
  Lines.Add('        reportPass(label, "");');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    static void reportPass(String label, String value) {');
  Lines.Add('        gPass++;');
  Lines.Add('        if (value == null || value.isEmpty()) {');
  Lines.Add('            System.out.println("[PASS] " + label);');
  Lines.Add('        } else {');
  Lines.Add('            System.out.println("[PASS] " + label + " = " + value);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    static void reportFail(String label, String reason) {');
  Lines.Add('        gFail++;');
  Lines.Add('        String r = (reason == null) ? "unknown error" : reason;');
  Lines.Add('        System.out.println("[FAIL] " + label + " -- " + r);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    static void reportSkip(String label, String reason) {');
  Lines.Add('        gSkip++;');
  Lines.Add('        String r = (reason == null) ? "skipped" : reason;');
  Lines.Add('        System.out.println("[SKIP] " + label + " -- " + r);');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitBytesHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    static String bytesToHex(byte[] b) {');
  Lines.Add('        if (b == null) {');
  Lines.Add('            return "";');
  Lines.Add('        }');
  Lines.Add('        StringBuilder sb = new StringBuilder(b.length * 2);');
  Lines.Add('        for (byte v : b) {');
  Lines.Add('            sb.append(Character.forDigit((v >> 4) & 0x0F, 16));');
  Lines.Add('            sb.append(Character.forDigit(v & 0x0F, 16));');
  Lines.Add('        }');
  Lines.Add('        return sb.toString();');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    static boolean isNonZero(byte[] b) {');
  Lines.Add('        if (b == null) {');
  Lines.Add('            return false;');
  Lines.Add('        }');
  Lines.Add('        for (byte v : b) {');
  Lines.Add('            if (v != 0) {');
  Lines.Add('                return true;');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        return false;');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSyncBlock(
  Lines: TPascalStringList;
  const Indent: string;
  const LabelText: TP_String;
  const CallExpr: TP_String;
  const RetDecl: TP_String);
var
  L: TP_String;
begin
  L := TP_String(Indent);
  Lines.Add(L.Text + 'try {');
  Lines.Add(L.Text + '    ' + RetDecl.Text + ' _r = ' + CallExpr.Text + ';');
  Lines.Add(L.Text + '    reportPass(' + JavaStrLit(LabelText).Text +
    ', String.valueOf(_r));');
  Lines.Add(L.Text + '} catch (Throwable t) {');
  Lines.Add(L.Text + '    reportFail(' + JavaStrLit(LabelText).Text +
    ', t.getMessage());');
  Lines.Add(L.Text + '}');
end;

procedure EmitAsyncBlock(
  Lines: TPascalStringList;
  const Indent: string;
  const LabelText: TP_String;
  const CallPrefix: TP_String;
  const TargetExpr: TP_String;
  const ArgsSuffix: TP_String;
  const BoxedType: TP_String);
var
  L: TP_String;
begin
  L := TP_String(Indent);
  Lines.Add(L.Text + 'try {');
  Lines.Add(L.Text +
    '    final java.util.concurrent.CountDownLatch _latch = ' +
    'new java.util.concurrent.CountDownLatch(1);');
  Lines.Add(L.Text +
    '    final java.util.concurrent.atomic.AtomicReference<' +
    BoxedType.Text + '> _v = ' +
    'new java.util.concurrent.atomic.AtomicReference<>();');
  Lines.Add(L.Text +
    '    final java.util.concurrent.atomic.AtomicReference<Throwable> _e = ' +
    'new java.util.concurrent.atomic.AtomicReference<>();');
  Lines.Add(L.Text + '    boolean _dispatched = ' + CallPrefix.Text +
    '(' + TargetExpr.Text + ArgsSuffix.Text + ', (_cv, _ce) -> {');
  Lines.Add(L.Text + '        _v.set(_cv);');
  Lines.Add(L.Text + '        _e.set(_ce);');
  Lines.Add(L.Text + '        _latch.countDown();');
  Lines.Add(L.Text + '    });');
  Lines.Add(L.Text + '    if (!_dispatched) {');
  Lines.Add(L.Text + '        reportFail(' + JavaStrLit(LabelText).Text +
    ', "dispatch failed");');
  Lines.Add(L.Text +
    '    } else if (!_latch.await(5000L, ' +
    'java.util.concurrent.TimeUnit.MILLISECONDS)) {');
  Lines.Add(L.Text + '        reportFail(' + JavaStrLit(LabelText).Text +
    ', "timeout");');
  Lines.Add(L.Text + '    } else if (_e.get() != null) {');
  Lines.Add(L.Text + '        reportFail(' + JavaStrLit(LabelText).Text +
    ', _e.get().getMessage());');
  Lines.Add(L.Text + '    } else {');
  Lines.Add(L.Text + '        reportPass(' + JavaStrLit(LabelText).Text +
    ', String.valueOf(_v.get()));');
  Lines.Add(L.Text + '    }');
  Lines.Add(L.Text + '} catch (Throwable t) {');
  Lines.Add(L.Text + '    reportFail(' + JavaStrLit(LabelText).Text +
    ', t.getMessage());');
  Lines.Add(L.Text + '}');
end;

procedure EmitNotifyBlock(
  Lines: TPascalStringList;
  const Indent: string;
  const LabelText: TP_String;
  const CallExpr: TP_String);
var
  L: TP_String;
begin
  L := TP_String(Indent);
  Lines.Add(L.Text + 'try {');
  Lines.Add(L.Text + '    ' + CallExpr.Text + ';');
  Lines.Add(L.Text + '    reportPass(' + JavaStrLit(LabelText).Text + ');');
  Lines.Add(L.Text + '} catch (Throwable t) {');
  Lines.Add(L.Text + '    reportFail(' + JavaStrLit(LabelText).Text +
    ', t.getMessage());');
  Lines.Add(L.Text + '}');
end;

procedure EmitFunctionTestMethod(
  Lines: TPascalStringList;
  const ClassName: TP_String;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ArgsSuffix, RetDecl, BoxedType: TP_String;
begin
  ArgsSuffix := BuildTestArgListSuffix(F.Params);
  RetDecl := ABI_Type_To_Java_Decl(F.ReturnType);
  BoxedType := ABI_Type_To_Java_Boxed(F.ReturnType);

  Lines.Add('    private static void test_' + ApiName.Text + '() {');
  EmitTestParamDecl(Lines, F.Params);
  EmitTestParamInit(Lines, F.Params);
  Lines.Add('');

  Lines.Add('        try {');
  Lines.Add('            ' + RetDecl.Text + ' _r = ' + ClassName.Text +
    '.call' + ApiName.Text + '(kTargetApp' + ArgsSuffix.Text + ');');
  Lines.Add('            reportPass(' +
    JavaStrLit(ApiName + TP_String('(app call)')).Text +
    ', String.valueOf(_r));');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            reportFail(' +
    JavaStrLit(ApiName + TP_String('(app call)')).Text +
    ', t.getMessage());');
  Lines.Add('        }');
  Lines.Add('');

  EmitAsyncBlock(Lines, '        ',
    ApiName + TP_String('(app async)'),
    ClassName + TP_String('.call') + ApiName + TP_String('Async'),
    TP_String('kTargetApp'), ArgsSuffix, BoxedType);
  Lines.Add('');

  EmitAsyncBlock(Lines, '        ',
    ApiName + TP_String('(app asyncSeq)'),
    ClassName + TP_String('.call') + ApiName + TP_String('SequencedAsync'),
    TP_String('kTargetApp'), ArgsSuffix, BoxedType);
  Lines.Add('');

  Lines.Add('        if (gHasServiceUid) {');
  EmitSyncBlock(Lines, '            ',
    ApiName + TP_String('(uid call)'),
    ClassName + TP_String('.call') + ApiName + TP_String('ByUid') +
    TP_String('(gServiceUid') + ArgsSuffix + TP_String(')'),
    RetDecl);
  Lines.Add('');
  EmitAsyncBlock(Lines, '            ',
    ApiName + TP_String('(uid async)'),
    ClassName + TP_String('.call') + ApiName + TP_String('AsyncByUid'),
    TP_String('gServiceUid'), ArgsSuffix, BoxedType);
  Lines.Add('');
  EmitAsyncBlock(Lines, '            ',
    ApiName + TP_String('(uid asyncSeq)'),
    ClassName + TP_String('.call') + ApiName +
    TP_String('SequencedAsyncByUid'),
    TP_String('gServiceUid'), ArgsSuffix, BoxedType);
  Lines.Add('        } else {');
  Lines.Add('            reportSkip(' +
    JavaStrLit(ApiName + TP_String('(uid call)')).Text +
    ', "no service UID");');
  Lines.Add('            reportSkip(' +
    JavaStrLit(ApiName + TP_String('(uid async)')).Text +
    ', "no service UID");');
  Lines.Add('            reportSkip(' +
    JavaStrLit(ApiName + TP_String('(uid asyncSeq)')).Text +
    ', "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  EmitSyncBlock(Lines, '        ',
    ApiName + TP_String('(p2pname call)'),
    ClassName + TP_String('.call') + ApiName + TP_String('ByP2PName') +
    TP_String('(kTargetP2P') + ArgsSuffix + TP_String(')'),
    RetDecl);
  Lines.Add('');
  EmitAsyncBlock(Lines, '        ',
    ApiName + TP_String('(p2pname async)'),
    ClassName + TP_String('.call') + ApiName + TP_String('AsyncByP2PName'),
    TP_String('kTargetP2P'), ArgsSuffix, BoxedType);
  Lines.Add('');
  EmitAsyncBlock(Lines, '        ',
    ApiName + TP_String('(p2pname asyncSeq)'),
    ClassName + TP_String('.call') + ApiName +
    TP_String('SequencedAsyncByP2PName'),
    TP_String('kTargetP2P'), ArgsSuffix, BoxedType);
  Lines.Add('');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitProcedureTestMethod(
  Lines: TPascalStringList;
  const ClassName: TP_String;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ArgsSuffix: TP_String;
begin
  ArgsSuffix := BuildTestArgListSuffix(F.Params);

  Lines.Add('    private static void test_' + ApiName.Text + '() {');
  EmitTestParamDecl(Lines, F.Params);
  EmitTestParamInit(Lines, F.Params);
  Lines.Add('');

  EmitNotifyBlock(Lines, '        ',
    ApiName + TP_String('(app notify)'),
    ClassName + TP_String('.notify') + ApiName +
    TP_String('(kTargetApp') + ArgsSuffix + TP_String(')'));
  Lines.Add('');

  EmitNotifyBlock(Lines, '        ',
    ApiName + TP_String('(app seq notify)'),
    ClassName + TP_String('.notify') + ApiName + TP_String('Sequenced') +
    TP_String('(kTargetApp') + ArgsSuffix + TP_String(')'));
  Lines.Add('');

  Lines.Add('        if (gHasServiceUid) {');
  EmitNotifyBlock(Lines, '            ',
    ApiName + TP_String('(uid notify)'),
    ClassName + TP_String('.notify') + ApiName + TP_String('ByUid') +
    TP_String('(gServiceUid') + ArgsSuffix + TP_String(')'));
  Lines.Add('');
  EmitNotifyBlock(Lines, '            ',
    ApiName + TP_String('(uid seq notify)'),
    ClassName + TP_String('.notify') + ApiName +
    TP_String('SequencedByUid') +
    TP_String('(gServiceUid') + ArgsSuffix + TP_String(')'));
  Lines.Add('        } else {');
  Lines.Add('            reportSkip(' +
    JavaStrLit(ApiName + TP_String('(uid notify)')).Text +
    ', "no service UID");');
  Lines.Add('            reportSkip(' +
    JavaStrLit(ApiName + TP_String('(uid seq notify)')).Text +
    ', "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  EmitNotifyBlock(Lines, '        ',
    ApiName + TP_String('(p2pname notify)'),
    ClassName + TP_String('.notify') + ApiName + TP_String('ByP2PName') +
    TP_String('(kTargetP2P') + ArgsSuffix + TP_String(')'));
  Lines.Add('');

  EmitNotifyBlock(Lines, '        ',
    ApiName + TP_String('(p2pname seq notify)'),
    ClassName + TP_String('.notify') + ApiName +
    TP_String('SequencedByP2PName') +
    TP_String('(kTargetP2P') + ArgsSuffix + TP_String(')'));
  Lines.Add('');

  Lines.Add('    }');
  Lines.Add('');
end;

function GenerateABIServiceTestJavaCode(
  Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, PackageName, ClassName, AppName, P2PName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log(TP_String('GenerateABIServiceTestJavaCode: Model is nil'));
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log(TP_String('GenerateABIServiceTestJavaCode: UnitName is empty'));
    Exit;
  end;

  PackageName := JavaPackageName(UnitName);
  ClassName := UnitName + TP_String('AbiServiceMain');
  AppName := MakeApiName(UnitName) + TP_String('_abi');
  P2PName := MakeApiName(UnitName) + TP_String('_service_test_p2p');

  Log(TP_String(PFormat('Generating Java ABI service test for unit "%s"',
    [UnitName.Text])));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('package ' + PackageName.Text + ';');
    Lines.Add('');
    Lines.Add('import lingofuse.AppHandle;');
    Lines.Add('import lingofuse.DataHandle;');
    Lines.Add('import lingofuse.Framework;');
    Lines.Add('import lingofuse.Options;');
    Lines.Add('import lingofuse.P2PRegistry;');
    Lines.Add('import lingofuse.async.AsyncBridge;');
    Lines.Add('import lingofuse.ffi.LibraryLoader;');
    Lines.Add('');
    Lines.Add('public final class ' + ClassName.Text + ' {');
    Lines.Add('');
    Lines.Add('    static final String kTargetApp = ' +
      JavaStrLit(AppName).Text + ';');
    Lines.Add('    static final String kTargetP2P = ' +
      JavaStrLit(P2PName).Text + ';');
    Lines.Add('    static final String kEndpoint  = ' +
      JavaStrLit(TP_String('ipc:') + AppName).Text + ';');
    Lines.Add('    static final String kWhoAmI         = "LF_TEST_WHOAMI";');
    Lines.Add('    static final String kAskCallMe      = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('    static final String kReportIdentity = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('');
    Lines.Add('    private ' + ClassName.Text + '() {');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    public static void main(String[] args) throws Exception {');
    Lines.Add('        try {');
    Lines.Add('            LibraryLoader.selectPlatformFileName();');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[FATAL] LingoFuse native library not found: " + t.getMessage());');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        System.out.println("=== ' + UnitName.Text +
      ' ABI service test ===");');
    Lines.Add('        System.out.println("Endpoint: " + kEndpoint);');
    Lines.Add('        System.out.println("AppName : " + kTargetApp);');
    Lines.Add('        System.out.println("P2PName : " + kTargetP2P);');
    Lines.Add('        System.out.println();');
    Lines.Add('');
    Lines.Add('        Framework.resetPrepare();');
    Lines.Add('        Options.setQuiet(true);');
    Lines.Add('        Options.setConsoleOutput(true);');
    Lines.Add('        Options.setOverlapConnection(true);');
    Lines.Add('        Options.setWaitConnectionReadyOk(true);');
    Lines.Add('        Options.setWaitConnectionTimeout(15000L);');
    Lines.Add('');
    Lines.Add('        Framework.prepareService(kEndpoint, kEndpoint);');
    Lines.Add('');
    Lines.Add('        AppHandle app = ' + UnitName.Text +
      'AbiService.createAndRegisterAbiApp();');
    Lines.Add('        if (app == null) {');
    Lines.Add('            System.err.println("[FATAL] createAndRegisterAbiApp failed");');
    Lines.Add('            Framework.shutdown();');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        app.registerCall(kWhoAmI, "service-side whoami helper",');
    Lines.Add('                ' + ClassName.Text + '::handleWhoAmI);');
    Lines.Add('        app.registerNotify(kAskCallMe, "ask service to call back client",');
    Lines.Add('                ' + ClassName.Text + '::handleAskServiceCallMe);');
    Lines.Add('');
    Lines.Add('        Options.setP2pName(kTargetP2P);');
    Lines.Add('        ' + UnitName.Text + 'AbiService.registerAllP2PAbiApis();');
    Lines.Add('        try {');
    Lines.Add('            P2PRegistry.registerCall(kWhoAmI, "service-side whoami helper",');
    Lines.Add('                    ' + ClassName.Text + '::handleWhoAmI);');
    Lines.Add('            P2PRegistry.registerNotify(kAskCallMe, "ask service to call back client",');
    Lines.Add('                    ' + ClassName.Text + '::handleAskServiceCallMe);');
    Lines.Add('        } catch (Throwable ignored) {');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        if (Framework.prepareClient(kEndpoint, app) == -1) {');
    Lines.Add('            System.err.println("[FATAL] prepareClient failed");');
    Lines.Add('            app.close();');
    Lines.Add('            Framework.shutdown();');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('        if (Framework.prepareDone() != 1) {');
    Lines.Add('            System.err.println("[FATAL] prepareDone failed");');
    Lines.Add('            Framework.exitMainThread();');
    Lines.Add('            app.close();');
    Lines.Add('            Framework.shutdown();');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        System.out.println("[OK] Service ready on " + kEndpoint);');
    Lines.Add('        System.out.println("[OK] Press Enter to shut down.");');
    Lines.Add('        System.in.read();');
    Lines.Add('');
    Lines.Add('        AsyncBridge.shutdownInstance();');
    Lines.Add('        Framework.exitMainThread();');
    Lines.Add('        app.close();');
    Lines.Add('        Framework.shutdown();');
    Lines.Add('        System.out.println("[OK] Shutdown complete.");');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static void handleWhoAmI(DataHandle in, DataHandle out) {');
    Lines.Add('        try {');
    Lines.Add('            byte[] uid = in.getP2pUid();');
    Lines.Add('            String p2p = in.getP2pName();');
    Lines.Add('            out.writeInt8((byte) 0);');
    Lines.Add('            out.writeBytes(uid);');
    Lines.Add('            out.writeString(p2p);');
    Lines.Add('            System.out.println("[SERVICE] whoami: p2p=" + p2p);');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[SERVICE] whoami failed: " + t.getMessage());');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static void handleAskServiceCallMe(DataHandle in) {');
    Lines.Add('        try {');
    Lines.Add('            byte[] uid = in.getP2pUid();');
    Lines.Add('            System.out.println("[SERVICE] ask_call_me: received notify, uid=" + bytesToHex(uid));');
    Lines.Add('            try (DataHandle req = new DataHandle(kReportIdentity)) {');
    Lines.Add('                req.writeString("service initiates call");');
    Lines.Add('                System.out.println("[SERVICE] ask_call_me: calling client via UID");');
    Lines.Add('                try (DataHandle res = Framework.uidCall(uid, req, 5000L)) {');
    Lines.Add('                    if (res.size() > 0) {');
    Lines.Add('                        System.out.println("[SERVICE] ask_call_me: client responded ok");');
    Lines.Add('                    } else {');
    Lines.Add('                        System.out.println("[SERVICE] ask_call_me: empty response");');
    Lines.Add('                    }');
    Lines.Add('                } catch (Throwable t) {');
    Lines.Add('                    System.out.println("[SERVICE] ask_call_me: UID call failed: " + t.getMessage());');
    Lines.Add('                }');
    Lines.Add('            }');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[SERVICE] ask_call_me failed: " + t.getMessage());');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static String bytesToHex(byte[] b) {');
    Lines.Add('        if (b == null) {');
    Lines.Add('            return "";');
    Lines.Add('        }');
    Lines.Add('        StringBuilder sb = new StringBuilder(b.length * 2);');
    Lines.Add('        for (byte v : b) {');
    Lines.Add('            sb.append(Character.forDigit((v >> 4) & 0x0F, 16));');
    Lines.Add('            sb.append(Character.forDigit(v & 0x0F, 16));');
    Lines.Add('        }');
    Lines.Add('        return sb.toString();');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(TP_String(PFormat('Generated service main: %d lines', [Lines.Count])));
  finally
  end;
end;

function GenerateABICallTestJavaCode(
  Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, PackageName, ClassName, CallClassName, AppName, P2PName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log(TP_String('GenerateABICallTestJavaCode: Model is nil'));
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log(TP_String('GenerateABICallTestJavaCode: UnitName is empty'));
    Exit;
  end;

  PackageName := JavaPackageName(UnitName);
  ClassName := UnitName + TP_String('AbiCallTestMain');
  CallClassName := UnitName + TP_String('AbiCall');
  AppName := MakeApiName(UnitName) + TP_String('_abi');
  P2PName := MakeApiName(UnitName) + TP_String('_service_test_p2p');

  Log(TP_String(PFormat('Generating Java ABI call test for unit "%s"',
    [UnitName.Text])));

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('package ' + PackageName.Text + ';');
    Lines.Add('');
    Lines.Add('import lingofuse.AppHandle;');
    Lines.Add('import lingofuse.DataHandle;');
    Lines.Add('import lingofuse.Framework;');
    Lines.Add('import lingofuse.LingoFuseStatus;');
    Lines.Add('import lingofuse.Options;');
    Lines.Add('import lingofuse.async.AsyncBridge;');
    Lines.Add('import lingofuse.ffi.LibraryLoader;');
    Lines.Add('');
    Lines.Add('public final class ' + ClassName.Text + ' {');
    Lines.Add('');
    Lines.Add('    static final String kTargetApp      = ' +
      JavaStrLit(AppName).Text + ';');
    Lines.Add('    static final String kTargetP2P      = ' +
      JavaStrLit(P2PName).Text + ';');
    Lines.Add('    static final String kEndpoint       = ' +
      JavaStrLit(TP_String('ipc:') + AppName).Text + ';');
    Lines.Add('    static final String kClientAppName  = "LF_TEST_CLIENT_SELF";');
    Lines.Add('    static final String kReportIdentity = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('    static final String kWhoAmI         = "LF_TEST_WHOAMI";');
    Lines.Add('    static final String kAskCallMe      = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('');
    Lines.Add('    static final Object gLock = new Object();');
    Lines.Add('    static volatile byte[] gServiceUid = null;');
    Lines.Add('    static volatile String gServiceP2P = "";');
    Lines.Add('    static volatile boolean gHasServiceUid = false;');
    Lines.Add('    static volatile boolean gServiceCalledMe = false;');
    Lines.Add('    static volatile byte[] gClientUid = null;');
    Lines.Add('    static volatile String gClientP2P = "";');
    Lines.Add('    static volatile boolean gHasClientUid = false;');
    Lines.Add('');

    EmitReportHelpers(Lines);
    EmitBytesHelpers(Lines);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);

      if F.IsFunction then
        EmitFunctionTestMethod(Lines, CallClassName, ApiName, F)
      else
        EmitProcedureTestMethod(Lines, CallClassName, ApiName, F);
    end;

    Lines.Add('    static void handleReportIdentity(DataHandle in, DataHandle out) {');
    Lines.Add('        synchronized (gLock) {');
    Lines.Add('            gServiceUid = in.getP2pUid();');
    Lines.Add('            gServiceP2P = in.getP2pName();');
    Lines.Add('            gHasServiceUid = isNonZero(gServiceUid);');
    Lines.Add('            gServiceCalledMe = true;');
    Lines.Add('        }');
    Lines.Add('        String msg;');
    Lines.Add('        try {');
    Lines.Add('            msg = in.readString();');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            msg = "<unreadable>";');
    Lines.Add('        }');
    Lines.Add('        System.out.println("[CLIENT] service called me, msg=\"" + msg + "\"");');
    Lines.Add('        try {');
    Lines.Add('            out.writeString("identity received");');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static boolean probeClientIdentity() {');
    Lines.Add('        synchronized (gLock) {');
    Lines.Add('            gHasClientUid = false;');
    Lines.Add('            gClientUid = new byte[32];');
    Lines.Add('            gClientP2P = "";');
    Lines.Add('        }');
    Lines.Add('        try (DataHandle req = new DataHandle(kWhoAmI)) {');
    Lines.Add('            try (DataHandle res = Framework.call(kTargetApp, req, 5000L)) {');
    Lines.Add('                if (res.size() <= 0) {');
    Lines.Add('                    return false;');
    Lines.Add('                }');
    Lines.Add('                res.setPosition(0);');
    Lines.Add('                byte status = res.readInt8();');
    Lines.Add('                if (status != 0) {');
    Lines.Add('                    return false;');
    Lines.Add('                }');
    Lines.Add('                byte[] uid = res.readBytesExact(32);');
    Lines.Add('                String p2p = res.readString();');
    Lines.Add('                synchronized (gLock) {');
    Lines.Add('                    gClientUid = uid;');
    Lines.Add('                    gClientP2P = p2p;');
    Lines.Add('                    gHasClientUid = isNonZero(uid);');
    Lines.Add('                }');
    Lines.Add('                return gHasClientUid;');
    Lines.Add('            }');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[WARN] probeClientIdentity: " + t.getMessage());');
    Lines.Add('            return false;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static boolean testServiceInitiatesCall() {');
    Lines.Add('        synchronized (gLock) {');
    Lines.Add('            gServiceCalledMe = false;');
    Lines.Add('            gHasServiceUid = false;');
    Lines.Add('            gServiceUid = null;');
    Lines.Add('            gServiceP2P = "";');
    Lines.Add('        }');
    Lines.Add('        try (DataHandle req = new DataHandle(kAskCallMe)) {');
    Lines.Add('            req.writeString(kReportIdentity);');
    Lines.Add('            Framework.notify(kTargetApp, req);');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[WARN] testServiceInitiatesCall dispatch: " + t.getMessage());');
    Lines.Add('            return false;');
    Lines.Add('        }');
    Lines.Add('        try {');
    Lines.Add('            Thread.sleep(500L);');
    Lines.Add('        } catch (InterruptedException ie) {');
    Lines.Add('            Thread.currentThread().interrupt();');
    Lines.Add('        }');
    Lines.Add('        long deadline = System.currentTimeMillis() + 20000L;');
    Lines.Add('        while (System.currentTimeMillis() < deadline) {');
    Lines.Add('            synchronized (gLock) {');
    Lines.Add('                if (gServiceCalledMe) {');
    Lines.Add('                    break;');
    Lines.Add('                }');
    Lines.Add('            }');
    Lines.Add('            try {');
    Lines.Add('                Thread.sleep(10);');
    Lines.Add('            } catch (InterruptedException ie) {');
    Lines.Add('                Thread.currentThread().interrupt();');
    Lines.Add('                break;');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('        synchronized (gLock) {');
    Lines.Add('            return gServiceCalledMe && gHasServiceUid;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    public static void main(String[] args) throws Exception {');
    Lines.Add('        try {');
    Lines.Add('            LibraryLoader.selectPlatformFileName();');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[FATAL] LingoFuse native library not found: " + t.getMessage());');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        System.out.println("=== ' + UnitName.Text +
      ' ABI client test ===");');
    Lines.Add('        System.out.println("Endpoint: " + kEndpoint);');
    Lines.Add('        System.out.println("AppName : " + kTargetApp);');
    Lines.Add('        System.out.println("P2PName : " + kTargetP2P);');
    Lines.Add('        System.out.println();');
    Lines.Add('');
    Lines.Add('        Framework.resetPrepare();');
    Lines.Add('        Options.setQuiet(true);');
    Lines.Add('        Options.setConsoleOutput(true);');
    Lines.Add('        Options.setOverlapConnection(true);');
    Lines.Add('        Options.setWaitConnectionReadyOk(true);');
    Lines.Add('        Options.setWaitConnectionTimeout(15000L);');
    Lines.Add('');
    Lines.Add('        ' + CallClassName.Text + '.ABI_TARGET_APP = kTargetApp;');
    Lines.Add('        ' + CallClassName.Text + '.ABI_TIMEOUT = 5000L;');
    Lines.Add('');
    Lines.Add('        AppHandle clientApp = new AppHandle(kClientAppName, "client test app");');
    Lines.Add('        clientApp.registerCall(kReportIdentity, "report service identity",');
    Lines.Add('                ' + ClassName.Text + '::handleReportIdentity);');
    Lines.Add('');
    Lines.Add('        if (Framework.prepareClient(kEndpoint, clientApp) == -1) {');
    Lines.Add('            System.err.println("[FATAL] prepareClient failed");');
    Lines.Add('            clientApp.close();');
    Lines.Add('            Framework.shutdown();');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('        if (Framework.prepareDone() != 1) {');
    Lines.Add('            System.err.println("[FATAL] prepareDone failed");');
    Lines.Add('            Framework.exitMainThread();');
    Lines.Add('            clientApp.close();');
    Lines.Add('            Framework.shutdown();');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        System.out.println("[OK] Client online.");');
    Lines.Add('');
    Lines.Add('        boolean _targetVisible = false;');
    Lines.Add('        for (int _wait = 0; _wait < 100; _wait++) {');
    Lines.Add('            if (LingoFuseStatus.checkApi(kTargetApp, kWhoAmI)) {');
    Lines.Add('                _targetVisible = true;');
    Lines.Add('                break;');
    Lines.Add('            }');
    Lines.Add('            try {');
    Lines.Add('                Thread.sleep(100L);');
    Lines.Add('            } catch (InterruptedException ie) {');
    Lines.Add('                Thread.currentThread().interrupt();');
    Lines.Add('                break;');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('        if (!_targetVisible) {');
    Lines.Add('            System.out.println("[WARN] target app ' + #39 + '" + kTargetApp + "' + #39 + ' not visible after 10s; continuing anyway.");');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        System.out.println();');
    Lines.Add('');
    Lines.Add('        if (probeClientIdentity()) {');
    Lines.Add('            System.out.println("[INFO] client UID = " + bytesToHex(gClientUid));');
    Lines.Add('            System.out.println("[INFO] client P2P = " + gClientP2P);');
    Lines.Add('        } else {');
    Lines.Add('            System.out.println("[WARN] whoami failed, UID tests will be skipped");');
    Lines.Add('        }');
    Lines.Add('        System.out.println();');
    Lines.Add('');
    Lines.Add('        if (testServiceInitiatesCall()) {');
    Lines.Add('            System.out.println("[INFO] service UID = " + bytesToHex(gServiceUid));');
    Lines.Add('            System.out.println("[INFO] service P2P = " + gServiceP2P);');
    Lines.Add('            reportPass("service-initiated call");');
    Lines.Add('        } else {');
    Lines.Add('            reportFail("service-initiated call", "timeout or no UID");');
    Lines.Add('        }');
    Lines.Add('        System.out.println();');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);
      Lines.Add('        test_' + ApiName.Text + '();');
    end;

    Lines.Add('');
    Lines.Add('        System.out.println();');
    Lines.Add('        System.out.println("=== Summary ===");');
    Lines.Add('        System.out.println("Pass: " + gPass);');
    Lines.Add('        System.out.println("Fail: " + gFail);');
    Lines.Add('        System.out.println("Skip: " + gSkip);');
    Lines.Add('');
    Lines.Add('        AsyncBridge.shutdownInstance();');
    Lines.Add('        Framework.exitMainThread();');
    Lines.Add('        clientApp.close();');
    Lines.Add('        Framework.shutdown();');
    Lines.Add('');
    Lines.Add('        System.exit(gFail == 0 ? 0 : 2);');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(TP_String(PFormat('Generated call test: %d lines', [Lines.Count])));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'java',
    'xxxAbiServiceMain.java',
    gkProject,
    'Java ABI service test program',
    @GenerateABIServiceTestJavaCode);

  RegisterGenerator(
    'java',
    'xxxAbiCallTestMain.java',
    gkProject,
    'Java ABI call test program',
    @GenerateABICallTestJavaCode);

end.
