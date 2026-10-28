unit http_dart_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceDartCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_dart_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_dart_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Dart_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'double'
  else if ABI_Type_Is_Int(T) then
    Result := 'int'
  else
    Result := 'void';
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
    Result := '';
end;

function ABI_Type_To_Extract_Call(const ParamName, T: TP_String; Index: integer): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '_extractString(req, ' + #39 + ParamName + #39 + ', ' +
      umlIntToStr(Index).Text + ', ' + #39#39 + ')'
  else if ABI_Type_Is_Float(T) then
    Result := '_extractDouble(req, ' + #39 + ParamName + #39 + ', ' +
      umlIntToStr(Index).Text + ', 0.0)'
  else
    Result := '_extractInt(req, ' + #39 + ParamName + #39 + ', ' +
      umlIntToStr(Index).Text + ', 0)';
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
  else if ABI_Type_Is_String(T) then Result := 'string'
  else Result := '';
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

function BuildFunctionPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeDartIdent(F.Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    if i > 0 then
      ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

procedure EmitDartServiceHeader(Lines: TPascalStringList;
  const UnitName, NormalizedUnit: TP_String);
begin
  Lines.Add('import ' + #39 + 'dart:async' + #39 + ';');
  Lines.Add('import ' + #39 + 'dart:convert' + #39 + ';');
  Lines.Add('import ' + #39 + 'dart:io' + #39 + ';');
  Lines.Add('import ' + #39 + 'dart:typed_data' + #39 + ';');
  Lines.Add('');
  Lines.Add('import ' + #39 + 'package:lingofuse/lingofuse.dart' + #39 + ';');
  Lines.Add('');
  Lines.Add('const String HTTP_SERVICE_APP_NAME = ' +
    DartStrLit(NormalizedUnit).Text + ';');
  Lines.Add('');
  Lines.Add('const String HTTP_SERVICE_APP_DESC = ' +
    DartStrLit('HTTP/JSON service for ' + UnitName).Text + ';');
  Lines.Add('');
  Lines.Add('const String HTTP_SERVICE_ENDPOINT = ' +
    DartStrLit('ipc:' + NormalizedUnit + '_http_json').Text + ';');
  Lines.Add('');
  Lines.Add('bool DEBUG_LOG = false;');
  Lines.Add('');
end;

procedure EmitDartServiceHelpers(Lines: TPascalStringList);
begin
  Lines.Add('Map<String, dynamic>? _decodeRequest(Uint8List input) {');
  Lines.Add('  final nulIdx = input.indexOf(0);');
  Lines.Add('  final body = nulIdx >= 0 ? input.sublist(0, nulIdx) : input;');
  Lines.Add('  if (body.isEmpty) return null;');
  Lines.Add('  try {');
  Lines.Add('    final decoded = jsonDecode(utf8.decode(body));');
  Lines.Add('    if (decoded is Map<String, dynamic>) return decoded;');
  Lines.Add('    return null;');
  Lines.Add('  } catch (_) {');
  Lines.Add('    return null;');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('dynamic _extractRaw(Map<String, dynamic> req, String name, int index) {');
  Lines.Add('  final rawArgs = req[' + #39 + 'args' + #39 + '];');
  Lines.Add('  if (rawArgs is List) {');
  Lines.Add('    if (index < rawArgs.length) return rawArgs[index];');
  Lines.Add('    return null;');
  Lines.Add('  }');
  Lines.Add('  if (req.containsKey(name)) return req[name];');
  Lines.Add('  return null;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('int _extractInt(Map<String, dynamic> req, String name, int index,');
  Lines.Add('    int defaultValue) {');
  Lines.Add('  final v = _extractRaw(req, name, index);');
  Lines.Add('  if (v == null) return defaultValue;');
  Lines.Add('  if (v is num) return v.toInt();');
  Lines.Add('  throw FormatException(' + #39 + 'Argument "$name" is not an integer' + #39 + ');');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('double _extractDouble(Map<String, dynamic> req, String name, int index,');
  Lines.Add('    double defaultValue) {');
  Lines.Add('  final v = _extractRaw(req, name, index);');
  Lines.Add('  if (v == null) return defaultValue;');
  Lines.Add('  if (v is num) return v.toDouble();');
  Lines.Add('  throw FormatException(' + #39 + 'Argument "$name" is not a number' + #39 + ');');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('String _extractString(Map<String, dynamic> req, String name, int index,');
  Lines.Add('    String defaultValue) {');
  Lines.Add('  final v = _extractRaw(req, name, index);');
  Lines.Add('  if (v == null) return defaultValue;');
  Lines.Add('  if (v is String) return v;');
  Lines.Add('  return v.toString();');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Uint8List _encodeUtf8Nul(String text) {');
  Lines.Add('  final bytes = utf8.encode(text);');
  Lines.Add('  final out = Uint8List(bytes.length + 1);');
  Lines.Add('  out.setRange(0, bytes.length, bytes);');
  Lines.Add('  return out;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Uint8List _encodeSuccess(Object? result) {');
  Lines.Add('  return _encodeUtf8Nul(');
  Lines.Add('      jsonEncode(<String, dynamic>{' + #39 + 'code' + #39 + ': 0, ' +
    #39 + 'result' + #39 + ': result}));');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Uint8List _encodeError(String message, {int code = -1}) {');
  Lines.Add('  return _encodeUtf8Nul(');
  Lines.Add('      jsonEncode(<String, dynamic>{' + #39 + 'code' + #39 + ': code, ' +
    #39 + 'error' + #39 + ': message}));');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitDartStub(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  i: integer;
  ParamDecl, PName, PType: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeDartIdent(F.Params[i].Name, i);
    PType := ABI_Type_To_Dart_Type(F.Params[i].PascalType);
    if i > 0 then
      ParamDecl := ParamDecl + ', ';
    ParamDecl := ParamDecl + PType + ' ' + PName;
  end;

  Lines.Add(ABI_Type_To_Dart_Type(F.ReturnType) + ' internal_call_' +
    ApiName.Text + '(' + ParamDecl.Text + ') {');
  if F.IsFunction then
    Lines.Add('  return ' + ABI_Type_To_Dart_Default_Literal(F.ReturnType) + ';');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitDartCallback(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  i: integer;
  PName, ExtractExpr, CallArgs: TP_String;
  HasParams: boolean;
begin
  HasParams := Length(F.Params) > 0;

  Lines.Add('Uint8List _callback_' + ApiName.Text + '(CallContext ctx) {');
  Lines.Add('  try {');

  if HasParams then
  begin
    Lines.Add('    final req = _decodeRequest(ctx.payload);');
    Lines.Add('    if (req == null) {');
    Lines.Add('      return _encodeError(' + #39 +
      'Empty or invalid request body' + #39 + ');');
    Lines.Add('    }');

    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafeDartIdent(F.Params[i].Name, i);
      ExtractExpr := ABI_Type_To_Extract_Call(F.Params[i].Name,
        F.Params[i].PascalType, i);
      Lines.Add('    final ' + PName.Text + ' = ' + ExtractExpr.Text + ';');
    end;

    CallArgs := '';
    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafeDartIdent(F.Params[i].Name, i);
      if i > 0 then
        CallArgs := CallArgs + ', ';
      CallArgs := CallArgs + PName;
    end;

    if F.IsFunction then
    begin
      Lines.Add('    final result = internal_call_' + ApiName.Text +
        '(' + CallArgs.Text + ');');
      Lines.Add('    return _encodeSuccess(result);');
    end
    else
    begin
      Lines.Add('    internal_call_' + ApiName.Text + '(' + CallArgs.Text + ');');
      Lines.Add('    return _encodeSuccess(null);');
    end;
  end
  else
  begin
    if F.IsFunction then
    begin
      Lines.Add('    final result = internal_call_' + ApiName.Text + '();');
      Lines.Add('    return _encodeSuccess(result);');
    end
    else
    begin
      Lines.Add('    internal_call_' + ApiName.Text + '();');
      Lines.Add('    return _encodeSuccess(null);');
    end;
  end;

  Lines.Add('  } catch (e, st) {');
  Lines.Add('    stderr.writeln(' + #39 + '[' + ApiName.Text +
    '] handler raised: $e' + #39 + ');');
  Lines.Add('    stderr.writeln(st);');
  Lines.Add('    return _encodeError(e.toString());');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitDartRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  ApiName: TP_String;
begin
  Lines.Add('void register_all_http_json_apis(AppHandle app) {');

  for i := 0 to High(SupportedFuncs) do
  begin
    ApiName := ApiNames[i];

    Lines.Add('  app.registerCall(');
    Lines.Add('    ' + DartStrLit(ApiName).Text + ',');
    Lines.Add('    ' + DartStrLit(ApiName).Text + ',');
    Lines.Add('    _callback_' + ApiName.Text + ',');
    Lines.Add('  );');
  end;

  if Length(SupportedFuncs) = 0 then
    Lines.Add('  // no supported routines');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitDartServiceMain(Lines: TPascalStringList);
begin
  Lines.Add('Future<void> _waitForShutdown() async {');
  Lines.Add('  final completer = Completer<void>();');
  Lines.Add('  try {');
  Lines.Add('    ProcessSignal.sigint.watch().listen(');
  Lines.Add('      (_) {');
  Lines.Add('        if (!completer.isCompleted) {');
  Lines.Add('          print('''');');
  Lines.Add('          print(' + #39 + '[shutdown] SIGINT received.' + #39 + ');');
  Lines.Add('          completer.complete();');
  Lines.Add('        }');
  Lines.Add('      },');
  Lines.Add('      onError: (_) {},');
  Lines.Add('    );');
  Lines.Add('  } catch (_) {}');
  Lines.Add('');
  Lines.Add('  if (!Platform.isWindows) {');
  Lines.Add('    try {');
  Lines.Add('      ProcessSignal.sigterm.watch().listen(');
  Lines.Add('        (_) {');
  Lines.Add('          if (!completer.isCompleted) {');
  Lines.Add('            print(' + #39 + '[shutdown] SIGTERM received.' + #39 + ');');
  Lines.Add('            completer.complete();');
  Lines.Add('          }');
  Lines.Add('        },');
  Lines.Add('        onError: (_) {},');
  Lines.Add('      );');
  Lines.Add('    } catch (_) {}');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  var stdinOpen = true;');
  Lines.Add('  try {');
  Lines.Add('    stdin');
  Lines.Add('        .transform(utf8.decoder)');
  Lines.Add('        .transform(const LineSplitter())');
  Lines.Add('        .listen(');
  Lines.Add('      (_) {');
  Lines.Add('        if (stdinOpen && !completer.isCompleted) {');
  Lines.Add('          print(' + #39 + '[shutdown] Enter pressed.' + #39 + ');');
  Lines.Add('          completer.complete();');
  Lines.Add('        }');
  Lines.Add('      },');
  Lines.Add('      onDone: () {');
  Lines.Add('        stdinOpen = false;');
  Lines.Add('      },');
  Lines.Add('      onError: (_) {');
  Lines.Add('        stdinOpen = false;');
  Lines.Add('      },');
  Lines.Add('    );');
  Lines.Add('  } catch (_) {}');
  Lines.Add('');
  Lines.Add('  await completer.future;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Future<void> _shutdown(AppHandle app) async {');
  Lines.Add('  print(' + #39 + '[shutdown] stopping service...' + #39 + ');');
  Lines.Add('  try {');
  Lines.Add('    app.dispose();');
  Lines.Add('  } catch (_) {}');
  Lines.Add('  try {');
  Lines.Add('    Framework.exitMainThread();');
  Lines.Add('  } catch (_) {}');
  Lines.Add('  try {');
  Lines.Add('    Framework.shutdown();');
  Lines.Add('  } catch (_) {}');
  Lines.Add('  try {');
  Lines.Add('    BridgeHost.instance.stop();');
  Lines.Add('  } catch (_) {}');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Future<void> main(List<String> args) async {');
  Lines.Add('  print(' + #39 +
    '=== $HTTP_SERVICE_APP_NAME HTTP/JSON service ===' + #39 + ');');
  Lines.Add('  print(' + #39 + 'Endpoint: $HTTP_SERVICE_ENDPOINT' + #39 + ');');
  Lines.Add('');
  Lines.Add('  await BridgeHost.start();');
  Lines.Add('');
  Lines.Add('  final app = AppHandle(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
  Lines.Add('  register_all_http_json_apis(app);');
  Lines.Add('  print(' + #39 +
    'Registered APIs on LingoFuse app "$HTTP_SERVICE_APP_NAME"' + #39 + ');');
  Lines.Add('');
  Lines.Add('  Framework.setOption(' + #39 + 'Quiet' + #39 + ', ' + #39 + 'True' + #39 + ');');
  Lines.Add('  Framework.setOption(' + #39 + 'Wait_Connection_ReadyOk' + #39 + ', ' +
    #39 + 'False' + #39 + ');');
  Lines.Add('  Framework.setOption(' + #39 + 'Overlap_Connection' + #39 + ', ' +
    #39 + 'True' + #39 + ');');
  Lines.Add('  Framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('  Framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT);');
  Lines.Add('  Framework.prepareClient(HTTP_SERVICE_ENDPOINT, app: app);');
  Lines.Add('');
  Lines.Add('  if (!Framework.prepareDone()) {');
  Lines.Add('    stderr.writeln(' + #39 + '[FATAL] prepareDone returned false' + #39 + ');');
  Lines.Add('    await _shutdown(app);');
  Lines.Add('    exit(1);');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  print(' + #39 +
    'Waiting for the app to become visible on the mesh...' + #39 + ');');
  Lines.Add('  bool visible = false;');
  Lines.Add('  for (int i = 0; i < 30; i++) {');
  Lines.Add('    if (Framework.checkApp(HTTP_SERVICE_APP_NAME)) {');
  Lines.Add('      visible = true;');
  Lines.Add('      break;');
  Lines.Add('    }');
  Lines.Add('    await Future.delayed(const Duration(milliseconds: 100));');
  Lines.Add('  }');
  Lines.Add('  if (visible) {');
  Lines.Add('    print(' + #39 + '[OK] App is visible on the mesh.' + #39 + ');');
  Lines.Add('  } else {');
  Lines.Add('    stderr.writeln(' + #39 +
    '[WARN] App not visible after 3 seconds.' + #39 + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  print(' + #39 +
    '[OK] Service ready. Press Ctrl+C to stop.' + #39 + ');');
  Lines.Add('  await _waitForShutdown();');
  Lines.Add('  await _shutdown(app);');
  Lines.Add('  print(' + #39 + '[OK] Service stopped.' + #39 + ');');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceDartCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceDartCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceDartCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Dart service module for unit "%s"',
    [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitDartServiceHeader(Lines, UnitName, NormalizedUnit);
    EmitDartServiceHelpers(Lines);

    for i := 0 to High(SupportedFuncs) do
      EmitDartStub(Lines, SupportedFuncs[i], ApiNames[i]);

    for i := 0 to High(SupportedFuncs) do
      EmitDartCallback(Lines, SupportedFuncs[i], ApiNames[i]);

    EmitDartRegistration(Lines, SupportedFuncs, ApiNames);
    EmitDartServiceMain(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'dart', 'Dart HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.dart', False,
    @GenerateHTTPServiceDartCode);
end.
