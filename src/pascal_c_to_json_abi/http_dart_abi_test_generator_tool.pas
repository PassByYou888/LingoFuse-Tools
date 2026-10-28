unit http_dart_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceDartTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallDartTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_dart_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_dart_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

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

function ABI_Type_To_Dart_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := #39#39
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := '0';
end;

function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := #39#39
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

function DartStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #39:  Result.Append('\' + #39);
      #92:  Result.Append('\\');
      #36:  Result.Append('\$');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\x');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
        end
        else
          Result.Append(c);
    end;
  end;
  Result.Append(#39);
end;

function BuildDartDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Dart_Default_Literal(Params[i].PascalType);
  end;
end;

function BuildSmokeArgsBody(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Json_Default_Literal(Params[i].PascalType);
  end;
end;

function BuildSmokePayloadLiteral(const Params: TParamArray): TP_String;
begin
  if Length(Params) = 0 then
    Result := '<String, dynamic>{}'
  else
    Result := '<String, dynamic>{' + #39 + 'args' + #39 + ': [' +
      BuildSmokeArgsBody(Params) + ']}';
end;

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  F: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    F := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(F.Params) do
      if not ABI_Type_Is_Supported(F.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and F.IsFunction and (not ABI_Type_Is_Supported(F.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [F.Name.Text, F.ReturnType.Text]));
    end;

    if Supported and (F.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: routine with empty Name');
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := F;
    end;
  end;
end;

procedure BuildDisambiguatedApiNames(
  const SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList);
var
  i, j: integer;
  ApiName: TP_String;
begin
  ApiNames.Clear;
  for i := 0 to High(SupportedFuncs) do
  begin
    ApiName := MakeApiName(SupportedFuncs[i].Name);
    if ApiNames.IndexOf(ApiName) >= 0 then
    begin
      j := 1;
      while ApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      ApiName := ApiName + '_' + umlIntToStr(j).Text;
    end;
    ApiNames.Add(ApiName);
  end;
end;

function GenerateHTTPServiceDartTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, PayloadLiteral: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceDartTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceDartTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceFileName := NormalizedUnit + '_http_json_service.dart';
  TestFileName := NormalizedUnit + '_http_json_service_main_test___.dart';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('import ' + #39 + 'dart:async' + #39 + ';');
    Lines.Add('import ' + #39 + 'dart:convert' + #39 + ';');
    Lines.Add('import ' + #39 + 'dart:io' + #39 + ';');
    Lines.Add('import ' + #39 + 'dart:typed_data' + #39 + ';');
    Lines.Add('');
    Lines.Add('import ' + #39 + 'package:lingofuse/lingofuse.dart' + #39 + ';');
    Lines.Add('');
    Lines.Add('import ' + #39 + ServiceFileName.Text + #39 + ' as svc;');
    Lines.Add('');
    Lines.Add('const String kP2PGroup = ' +
      DartStrLit(NormalizedUnit + '_test_p2p_group').Text + ';');
    Lines.Add('');
    Lines.Add('const int kP2PPropagationMs = 2000;');
    Lines.Add('');
    Lines.Add('const int kCallTimeoutMs = 5000;');
    Lines.Add('');
    Lines.Add('Future<bool> _callOne(');
    Lines.Add('  P2PNameTarget target,');
    Lines.Add('  String apiName,');
    Lines.Add('  Map<String, dynamic> payload,');
    Lines.Add(') async {');
    Lines.Add('  try {');
    Lines.Add('    final resp = await target');
    Lines.Add('        .callJson<Map<String, dynamic>>(');
    Lines.Add('          apiName,');
    Lines.Add('          payload: payload,');
    Lines.Add('          timeoutMs: kCallTimeoutMs,');
    Lines.Add('        )');
    Lines.Add('        .future;');
    Lines.Add('    final code = resp[' + #39 + 'code' + #39 + '];');
    Lines.Add('    if (code == 0) return true;');
    Lines.Add('    final err = resp[' + #39 + 'error' + #39 + '] ?? ' +
      DartStrLit('<no error message>').Text + ';');
    Lines.Add('    stderr.writeln(' + DartStrLit('    code=$code error=$err').Text + ');');
    Lines.Add('    return false;');
    Lines.Add('  } on TimeoutException {');
    Lines.Add('    stderr.writeln(' +
      DartStrLit('    timeout after ${kCallTimeoutMs}ms').Text + ');');
    Lines.Add('    return false;');
    Lines.Add('  } catch (e) {');
    Lines.Add('    stderr.writeln(' + DartStrLit('    exception: $e').Text + ');');
    Lines.Add('    return false;');
    Lines.Add('  }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('void _shutdown(AppHandle app) {');
    Lines.Add('  try { app.dispose(); } catch (_) {}');
    Lines.Add('  try { Framework.exitMainThread(); } catch (_) {}');
    Lines.Add('  try { Framework.shutdown(); } catch (_) {}');
    Lines.Add('  try { BridgeHost.instance.stop(); } catch (_) {}');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Future<void> main(List<String> args) async {');
    Lines.Add('  int passed = 0;');
    Lines.Add('  int failed = 0;');
    Lines.Add('');
    Lines.Add('  print(' +
      DartStrLit('=== ${svc.HTTP_SERVICE_APP_NAME} LingoFuse service smoke test ===').Text + ');');
    Lines.Add('  print(' +
      DartStrLit('Endpoint : ${svc.HTTP_SERVICE_ENDPOINT}').Text + ');');
    Lines.Add('  print(' +
      DartStrLit('API count: ' + umlIntToStr(Length(SupportedFuncs))).Text + ');');
    Lines.Add('  print(' + #39#39 + ');');
    Lines.Add('');
    Lines.Add('  print(' + DartStrLit('[setup] starting BridgeHost...').Text + ');');
    Lines.Add('  try {');
    Lines.Add('    await BridgeHost.start();');
    Lines.Add('  } catch (e) {');
    Lines.Add('    stderr.writeln(' +
      DartStrLit('[FATAL] BridgeHost.start failed: $e').Text + ');');
    Lines.Add('    exit(1);');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  print(' +
      DartStrLit('[setup] declaring P2P group "$kP2PGroup"...').Text + ');');
    Lines.Add('  Framework.setOptP2PName(kP2PGroup);');
    Lines.Add('');
    Lines.Add('  print(' +
      DartStrLit('[setup] creating AppHandle and registering APIs...').Text + ');');
    Lines.Add('  final app = AppHandle(');
    Lines.Add('    svc.HTTP_SERVICE_APP_NAME,');
    Lines.Add('    svc.HTTP_SERVICE_APP_DESC,');
    Lines.Add('  );');
    Lines.Add('  svc.register_all_http_json_apis(app);');
    Lines.Add('');
    Lines.Add('  print(' + DartStrLit('[setup] starting framework...').Text + ');');
    Lines.Add('  Framework.setOption(' + #39 + 'Quiet' + #39 + ', ' + #39 + 'True' + #39 + ');');
    Lines.Add('  Framework.setOption(' + #39 + 'Wait_Connection_ReadyOk' + #39 + ', ' +
      #39 + 'False' + #39 + ');');
    Lines.Add('  Framework.setOption(' + #39 + 'Overlap_Connection' + #39 + ', ' +
      #39 + 'True' + #39 + ');');
    Lines.Add('  Framework.resetPrepare();');
    Lines.Add('  Framework.prepareService(');
    Lines.Add('    svc.HTTP_SERVICE_ENDPOINT,');
    Lines.Add('    svc.HTTP_SERVICE_ENDPOINT,');
    Lines.Add('  );');
    Lines.Add('  Framework.prepareClient(svc.HTTP_SERVICE_ENDPOINT, app: app);');
    Lines.Add('');
    Lines.Add('  if (!Framework.prepareDone()) {');
    Lines.Add('    stderr.writeln(' +
      DartStrLit('[FATAL] Framework.prepareDone returned false').Text + ');');
    Lines.Add('    _shutdown(app);');
    Lines.Add('    exit(1);');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  print(' +
      DartStrLit('[setup] waiting for the app to become visible...').Text + ');');
    Lines.Add('  bool visible = false;');
    Lines.Add('  for (int i = 0; i < 30; i++) {');
    Lines.Add('    if (Framework.checkApp(svc.HTTP_SERVICE_APP_NAME)) {');
    Lines.Add('      visible = true;');
    Lines.Add('      break;');
    Lines.Add('    }');
    Lines.Add('    await Future.delayed(const Duration(milliseconds: 100));');
    Lines.Add('  }');
    Lines.Add('  if (!visible) {');
    Lines.Add('    stderr.writeln(' +
      DartStrLit('[FATAL] app did not become visible on the mesh').Text + ');');
    Lines.Add('    _shutdown(app);');
    Lines.Add('    exit(1);');
    Lines.Add('  }');
    Lines.Add('  print(' + DartStrLit('[setup] app is visible on the mesh').Text + ');');
    Lines.Add('');
    Lines.Add('  print(' +
      DartStrLit('[setup] waiting ${kP2PPropagationMs}ms for P2P name propagation...').Text + ');');
    Lines.Add('  await Future.delayed(const Duration(milliseconds: kP2PPropagationMs));');
    Lines.Add('');
    Lines.Add('  final target = P2PNameTarget(kP2PGroup);');
    Lines.Add('  print(' +
      DartStrLit('[setup] ready; target = ${target.describe()}').Text + ');');
    Lines.Add('  print(' + #39#39 + ');');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      PayloadLiteral := BuildSmokePayloadLiteral(F.Params);

      Lines.Add('  print(' + DartStrLit('  ' + ApiName + ': ').Text + ');');
      Lines.Add('  if (await _callOne(target, ' + DartStrLit(ApiName).Text +
        ', ' + PayloadLiteral.Text + ')) {');
      Lines.Add('    print(' + DartStrLit('    OK').Text + ');');
      Lines.Add('    passed++;');
      Lines.Add('  } else {');
      Lines.Add('    failed++;');
      Lines.Add('  }');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('  print(' + DartStrLit('  (no APIs to smoke-test)').Text + ');');

    Lines.Add('');
    Lines.Add('  print(' + #39#39 + ');');
    Lines.Add('  print(' + DartStrLit('=== Smoke test summary ===').Text + ');');
    Lines.Add('  print(' + DartStrLit('Passed: $passed').Text + ');');
    Lines.Add('  print(' + DartStrLit('Failed: $failed').Text + ');');
    Lines.Add('');
    Lines.Add('  _shutdown(app);');
    Lines.Add('');
    Lines.Add('  exit(failed == 0 ? 0 : 1);');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated service smoke test: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateHTTPCallDartTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl, CallFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, DefaultArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallDartTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallDartTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  CallFileName := NormalizedUnit + '_http_json_call.dart';
  TestFileName := NormalizedUnit + '_http_json_call_main_test___.dart';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('import ' + #39 + 'dart:async' + #39 + ';');
    Lines.Add('import ' + #39 + 'dart:io' + #39 + ';');
    Lines.Add('');
    Lines.Add('import ' + #39 + CallFileName.Text + #39 + ' as api;');
    Lines.Add('');
    Lines.Add('const String kDefaultBaseUrl = ' + DartStrLit(BaseUrl).Text + ';');
    Lines.Add('');
    Lines.Add('Future<void> main(List<String> args) async {');
    Lines.Add('  int passed = 0;');
    Lines.Add('  int failed = 0;');
    Lines.Add('');
    Lines.Add('  final baseUrl = args.isNotEmpty ? args[0] : kDefaultBaseUrl;');
    Lines.Add('');
    Lines.Add('  print(' + DartStrLit('=== ' + UnitName + ' HTTP/JSON call test ===').Text + ');');
    Lines.Add('  print(' + #39#39 + ');');
    Lines.Add('  print(' + DartStrLit('Base URL : $baseUrl').Text + ');');
    Lines.Add('  print(' +
      DartStrLit('API count: ' + umlIntToStr(Length(SupportedFuncs))).Text + ');');
    Lines.Add('  print(' + #39#39 + ');');
    Lines.Add('');
    Lines.Add('  api.setBaseUrl(baseUrl);');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildDartDefaultArgList(F.Params);

      Lines.Add('  print(' + DartStrLit('  ' + ApiName + ': ').Text + ');');
      Lines.Add('  try {');
      if Length(F.Params) > 0 then
        Lines.Add('    await api.' + ApiName + '(' + DefaultArgs.Text + ');')
      else
        Lines.Add('    await api.' + ApiName + '();');
      Lines.Add('    print(' + DartStrLit('    OK').Text + ');');
      Lines.Add('    passed++;');
      Lines.Add('  } on api.HttpCallError catch (e) {');
      Lines.Add('    stderr.writeln(' + DartStrLit('    FAILED: $e').Text + ');');
      Lines.Add('    failed++;');
      Lines.Add('  } catch (e) {');
      Lines.Add('    stderr.writeln(' + DartStrLit('    FAILED: $e').Text + ');');
      Lines.Add('    failed++;');
      Lines.Add('  }');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('  print(' + DartStrLit('  (no APIs to test)').Text + ');');

    Lines.Add('');
    Lines.Add('  print(' + #39#39 + ');');
    Lines.Add('  print(' + DartStrLit('=== Summary ===').Text + ');');
    Lines.Add('  print(' + DartStrLit('Passed: $passed').Text + ');');
    Lines.Add('  print(' + DartStrLit('Failed: $failed').Text + ');');
    Lines.Add('');
    Lines.Add('  exit(failed == 0 ? 0 : 1);');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated call e2e test: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'dart', 'Dart HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.dart', False,
    @GenerateHTTPServiceDartTestCode);
  RegisterCodeGenEntry(
    'dart', 'Dart HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.dart', False,
    @GenerateHTTPCallDartTestCode);
end.
