unit http_nodejs_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceNodejsTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallNodejsTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_nodejs_abi_test_generator] %s', [Msg.Text]);
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
  Result := T.Same('integer') or T.Same('longint') or
    T.Same('int64') or T.Same('cardinal') or T.Same('dword') or
    T.Same('longword') or T.Same('word') or T.Same('smallint') or
    T.Same('byte') or T.Same('uint64');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafeJsIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('arguments') or Result.Same('await') or Result.Same('break') or
    Result.Same('case') or Result.Same('catch') or Result.Same('class') or
    Result.Same('const') or Result.Same('continue') or Result.Same('debugger') or
    Result.Same('default') or Result.Same('delete') or Result.Same('do') or
    Result.Same('else') or Result.Same('enum') or Result.Same('eval') or
    Result.Same('export') or Result.Same('extends') or Result.Same('false') or
    Result.Same('finally') or Result.Same('for') or Result.Same('function') or
    Result.Same('if') or Result.Same('implements') or Result.Same('import') or
    Result.Same('in') or Result.Same('instanceof') or Result.Same('interface') or
    Result.Same('let') or Result.Same('new') or Result.Same('null') or
    Result.Same('package') or Result.Same('private') or Result.Same('protected') or
    Result.Same('public') or Result.Same('return') or Result.Same('static') or
    Result.Same('super') or Result.Same('switch') or Result.Same('this') or
    Result.Same('throw') or Result.Same('true') or Result.Same('try') or
    Result.Same('typeof') or Result.Same('var') or Result.Same('void') or
    Result.Same('while') or Result.Same('with') or Result.Same('yield') or
    Result.Same('undefined') then
    Result := Result + '_';
end;

function JsStrLit(const S: TP_String): TP_String;
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
      #39: Result.Append('\' + #39);
      #92: Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9:  Result.Append('\t');
      #8:  Result.Append('\b');
      #12: Result.Append('\f');
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

function BuildJsDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := #39#39
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else
      d := '0';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
end;

function BuildSmokeJsonRequest(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := '{}';
    Exit;
  end;
  Result := '{"args": [';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := '""'
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else
      d := '0';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
  Result := Result + ']}';
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
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not ABI_Type_Is_Supported(f.ReturnType)) then
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

function GenerateHTTPServiceNodejsTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceModuleName, FileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceNodejsTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceNodejsTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceModuleName := NormalizedUnit + '_http_json_service_node';
  FileName := NormalizedUnit + '_http_json_service_main_test___.js';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add(#39 + 'use strict' + #39 + ';');
    Lines.Add('');
    Lines.Add('const SERVICE_MODULE_FILE = ' + JsStrLit(ServiceModuleName + '.js').Text + ';');
    Lines.Add('');
    Lines.Add('let svc;');
    Lines.Add('try {');
    Lines.Add('    svc = require(' + #39 + './' + #39 + ' + SERVICE_MODULE_FILE);');
    Lines.Add('} catch (e) {');
    Lines.Add('    console.error(' + #39 + '[FATAL] cannot load the service module.' + #39 + ');');
    Lines.Add('    console.error(' + #39 + '        File: ' + #39 + ' + SERVICE_MODULE_FILE);');
    Lines.Add('    console.error(' + #39 + '        Expected in: ' + #39 + ' + __dirname);');
    Lines.Add('    console.error(' + #39 + '        Details: ' + #39 + ' + ((e && e.stack) || e));');
    Lines.Add('    process.exit(1);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('const __argv = process.argv.slice(2);');
    Lines.Add('const __smoke = __argv.indexOf(' + #39 + '--smoke' + #39 + ') !== -1;');
    Lines.Add('');
    Lines.Add('console.log(' + #39 + '=== ' + #39 + ' + svc.HTTP_SERVICE_APP_NAME +');
    Lines.Add('    ' + #39 + ' HTTP/JSON service test ===' + #39 + ');');
    Lines.Add('console.log(' + #39 + 'Endpoint: ' + #39 + ' + svc.HTTP_SERVICE_ENDPOINT);');
    Lines.Add('console.log(' + #39 + 'API count: ' + umlIntToStr(Length(SupportedFuncs)) + #39 + ');');
    Lines.Add('console.log(' + #39#39 + ');');
    Lines.Add('');
    Lines.Add('if (__smoke) {');
    Lines.Add('    console.log(' + #39 + '[smoke] Running in-process LocalCall self-tests.' + #39 + ');');
    Lines.Add('    console.log(' + #39 + '[smoke] This does NOT start LingoFuse and does NOT need the bridge.' + #39 + ');');
    Lines.Add('    console.log(' + #39#39 + ');');
    Lines.Add('    const __smokeRc = svc.runSmokeTest();');
    Lines.Add('    process.exit(__smokeRc);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('const __rc = svc.main();');
    Lines.Add('if (__rc !== 0) {');
    Lines.Add('    process.exit(__rc);');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateHTTPCallNodejsTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, CallModuleName, DefaultBaseUrl, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, DefaultArgs: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallNodejsTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallNodejsTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  CallModuleName := NormalizedUnit + '_http_json_call_node';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  FileName := NormalizedUnit + '_http_json_call_main_test___.js';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add(#39 + 'use strict' + #39 + ';');
    Lines.Add('');
    Lines.Add('const CALL_MODULE_FILE = ' + JsStrLit(CallModuleName + '.js').Text + ';');
    Lines.Add('');
    Lines.Add('let api;');
    Lines.Add('try {');
    Lines.Add('    api = require(' + #39 + './' + #39 + ' + CALL_MODULE_FILE);');
    Lines.Add('} catch (e) {');
    Lines.Add('    console.error(' + #39 + '[FATAL] cannot load the call module.' + #39 + ');');
    Lines.Add('    console.error(' + #39 + '        File: ' + #39 + ' + CALL_MODULE_FILE);');
    Lines.Add('    console.error(' + #39 + '        Expected in: ' + #39 + ' + __dirname);');
    Lines.Add('    console.error(' + #39 + '        Details: ' + #39 + ' + ((e && e.stack) || e));');
    Lines.Add('    process.exit(1);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('const DEFAULT_BASE_URL = ' + JsStrLit(DefaultBaseUrl).Text + ';');
    Lines.Add('');
    Lines.Add('const CASES = [');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildJsDefaultArgList(F.Params);

      Lines.Add('    { name: ' + JsStrLit(ApiName).Text + ', style: ' + #39 + 'await' + #39 + ',');
      Lines.Add('      run: async function () {');
      if DefaultArgs = '' then
        Lines.Add('        await api.' + ApiName.Text + '();')
      else
        Lines.Add('        await api.' + ApiName.Text + '(' + DefaultArgs + ');');
      Lines.Add('      } },');
      Lines.Add('    { name: ' + JsStrLit(ApiName).Text + ', style: ' + #39 + 'promise' + #39 + ',');
      Lines.Add('      run: function () {');
      if DefaultArgs = '' then
        Lines.Add('        return api.' + ApiName.Text + '().then(function () {});')
      else
      begin
        Lines.Add('        return api.' + ApiName.Text + '(' + DefaultArgs + ')');
        Lines.Add('            .then(function () {});');
      end;
      Lines.Add('      } },');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('    ');

    Lines.Add('];');
    Lines.Add('');
    Lines.Add('async function runAll() {');
    Lines.Add('    let ok = 0;');
    Lines.Add('    let fail = 0;');
    Lines.Add('    for (let i = 0; i < CASES.length; i++) {');
    Lines.Add('        const c = CASES[i];');
    Lines.Add('        try {');
    Lines.Add('            await c.run();');
    Lines.Add('            console.log(' + #39 + '  ' + #39 + ' + c.name + ' + #39 + ' [' + #39 + ' + c.style + ' + #39 + ']: OK' + #39 + ');');
    Lines.Add('            ok++;');
    Lines.Add('        } catch (e) {');
    Lines.Add('            const msg = (e && e.message) || String(e);');
    Lines.Add('            const code = (e && e.code !== undefined) ? e.code : ' + #39 + '-' + #39 + ';');
    Lines.Add('            const httpStatus = (e && e.httpStatus !== undefined) ? e.httpStatus : ' + #39 + '-' + #39 + ';');
    Lines.Add('            console.error(' + #39 + '  ' + #39 + ' + c.name + ' + #39 + ' [' + #39 + ' + c.style + ' + #39 + ']: FAILED: ' + #39 + ' + msg');
    Lines.Add('                + ' + #39 + ' (code=' + #39 + ' + code + ' + #39 + ', http=' + #39 + ' + httpStatus + ' + #39 + ')' + #39 + ');');
    Lines.Add('            fail++;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('    return { ok: ok, fail: fail };');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('async function main() {');
    Lines.Add('    const argv = process.argv.slice(2);');
    Lines.Add('    const baseUrl = (argv.length >= 1 && argv[0]) ? argv[0] : DEFAULT_BASE_URL;');
    Lines.Add('    api.HTTP_CALL_BASE_URL = baseUrl;');
    Lines.Add('');
    Lines.Add('    console.log(' + #39 + '=== ' + #39 + ' + ' + #39 + UnitName.Text + #39 + ' + ' + #39 + ' HTTP/JSON call test ===' + #39 + ');');
    Lines.Add('    console.log(' + #39#39 + ');');
    Lines.Add('    console.log(' + #39 + 'Base URL: ' + #39 + ' + baseUrl);');
    Lines.Add('    console.log(' + #39#39 + ');');
    Lines.Add('');
    Lines.Add('    await new Promise(function (resolve) { setTimeout(resolve, 1000); });');
    Lines.Add('');
    Lines.Add('    const r = await runAll();');
    Lines.Add('');
    Lines.Add('    console.log(' + #39#39 + ');');
    Lines.Add('    console.log(' + #39 + '=== Summary ===' + #39 + ');');
    Lines.Add('    console.log(' + #39 + 'Passed: ' + #39 + ' + r.ok);');
    Lines.Add('    console.log(' + #39 + 'Failed: ' + #39 + ' + r.fail);');
    Lines.Add('    return r.fail === 0 ? 0 : 1;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('main().then(function (rc) {');
    Lines.Add('    process.exit(rc);');
    Lines.Add('}).catch(function (e) {');
    Lines.Add('    console.error(' + #39 + '[FATAL] ' + #39 + ' + ((e && e.stack) || e));');
    Lines.Add('    process.exit(1);');
    Lines.Add('});');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated call test program: %d lines, %d routines (await + promise).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'nodejs', 'Node.js HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.js', False,
    @GenerateHTTPServiceNodejsTestCode);
  RegisterCodeGenEntry(
    'nodejs', 'Node.js HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.js', False,
    @GenerateHTTPCallNodejsTestCode);
end.
