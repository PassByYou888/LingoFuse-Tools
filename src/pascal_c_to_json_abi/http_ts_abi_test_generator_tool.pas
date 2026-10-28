unit http_ts_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallTypeScriptTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPServiceTypeScriptTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_test_generator] %s', [Msg.Text]);
end;

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or
    T.Same('unicodestring') or T.Same('tpascalstring') or
    T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or
    T.Same('extended') or T.Same('real');
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

function ABI_Type_To_TS_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := 'unknown';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsTypeScriptReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('any') or S.Same('as') or
    S.Same('asserts') or S.Same('async') or S.Same('await') or
    S.Same('bigint') or S.Same('boolean') or S.Same('break') or
    S.Same('case') or S.Same('catch') or S.Same('class') or
    S.Same('const') or S.Same('constructor') or S.Same('continue') or
    S.Same('debugger') or S.Same('declare') or S.Same('default') or
    S.Same('delete') or S.Same('do') or S.Same('else') or
    S.Same('enum') or S.Same('export') or S.Same('extends') or
    S.Same('false') or S.Same('finally') or S.Same('for') or
    S.Same('from') or S.Same('function') or S.Same('get') or
    S.Same('if') or S.Same('implements') or S.Same('import') or
    S.Same('in') or S.Same('infer') or S.Same('instanceof') or
    S.Same('interface') or S.Same('is') or S.Same('keyof') or
    S.Same('let') or S.Same('module') or S.Same('namespace') or
    S.Same('never') or S.Same('new') or S.Same('null') or
    S.Same('number') or S.Same('object') or S.Same('of') or
    S.Same('package') or S.Same('private') or S.Same('protected') or
    S.Same('public') or S.Same('readonly') or S.Same('require') or
    S.Same('return') or S.Same('set') or S.Same('static') or
    S.Same('string') or S.Same('super') or S.Same('switch') or
    S.Same('symbol') or S.Same('this') or S.Same('throw') or
    S.Same('true') or S.Same('try') or S.Same('type') or
    S.Same('typeof') or S.Same('undefined') or S.Same('unique') or
    S.Same('unknown') or S.Same('var') or S.Same('void') or
    S.Same('while') or S.Same('with') or S.Same('yield');
end;

function MakeSafeTsIdent(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or (c = '$') or
       ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if IsTypeScriptReservedWord(Result) then
    Result := Result + '_';
end;

function TsStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #34;
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #34: Result.Append('\"');
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
  Result.Append(#34);
end;

function BuildTsDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := #34#34
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else
      d := '0';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
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
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and
       (not ABI_Type_Is_Supported(f.ReturnType)) then
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

function GenerateHTTPCallTypeScriptTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, CallModuleName, DefaultBaseUrl, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, DefaultArgs: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  HasParams: boolean;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallTypeScriptTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallTypeScriptTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  CallModuleName := NormalizedUnit + '_http_json_call_ts';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  FileName := NormalizedUnit + '_http_json_call_main_test___.ts';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('import * as api from "./' + CallModuleName.Text + '";');
    Lines.Add('');
    Lines.Add('const DEFAULT_BASE_URL = ' + TsStrLit(DefaultBaseUrl).Text + ';');
    Lines.Add('');
    Lines.Add('interface CaseResult {');
    Lines.Add('    readonly name: string;');
    Lines.Add('    readonly style: "await" | "promise";');
    Lines.Add('    readonly ok: boolean;');
    Lines.Add('    readonly message: string;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('async function runAll(): Promise<CaseResult[]> {');
    Lines.Add('    const results: CaseResult[] = [];');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    void api;');
    end
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        DefaultArgs := BuildTsDefaultArgList(F.Params);
        HasParams := Length(F.Params) > 0;

        Lines.Add('    try {');
        if F.IsFunction then
        begin
          if HasParams then
            Lines.Add('        const r = await api.' + ApiName.Text + '(' + DefaultArgs.Text + ');')
          else
            Lines.Add('        const r = await api.' + ApiName.Text + '();');
          Lines.Add('        void r;');
        end
        else
        begin
          if HasParams then
            Lines.Add('        await api.' + ApiName.Text + '(' + DefaultArgs.Text + ');')
          else
            Lines.Add('        await api.' + ApiName.Text + '();');
        end;
        Lines.Add('        results.push({ name: ' + TsStrLit(ApiName).Text +
          ', style: "await", ok: true, message: "" });');
        Lines.Add('    } catch (e) {');
        Lines.Add('        const msg = e instanceof Error ? e.message : String(e);');
        Lines.Add('        results.push({ name: ' + TsStrLit(ApiName).Text +
          ', style: "await", ok: false, message: msg });');
        Lines.Add('    }');
        Lines.Add('');

        Lines.Add('    try {');
        if F.IsFunction then
        begin
          if HasParams then
            Lines.Add('        const r = await api.' + ApiName.Text + '(' +
              DefaultArgs.Text + ').then((v) => v);')
          else
            Lines.Add('        const r = await api.' + ApiName.Text + '().then((v) => v);');
          Lines.Add('        void r;');
        end
        else
        begin
          if HasParams then
            Lines.Add('        await api.' + ApiName.Text + '(' +
              DefaultArgs.Text + ').then(() => undefined);')
          else
            Lines.Add('        await api.' + ApiName.Text + '().then(() => undefined);');
        end;
        Lines.Add('        results.push({ name: ' + TsStrLit(ApiName).Text +
          ', style: "promise", ok: true, message: "" });');
        Lines.Add('    } catch (e) {');
        Lines.Add('        const msg = e instanceof Error ? e.message : String(e);');
        Lines.Add('        results.push({ name: ' + TsStrLit(ApiName).Text +
          ', style: "promise", ok: false, message: msg });');
        Lines.Add('    }');
        Lines.Add('');
      end;
    end;

    Lines.Add('    return results;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('async function main(): Promise<number> {');
    Lines.Add('    const argv = process.argv.slice(2);');
    Lines.Add('    const baseUrl = (argv.length >= 1 && argv[0]) ? argv[0] : DEFAULT_BASE_URL;');
    Lines.Add('');
    Lines.Add('    console.log(' + TsStrLit('=== ' + UnitName.Text + ' HTTP/JSON call test ===').Text + ');');
    Lines.Add('    console.log("");');
    Lines.Add('    console.log("Base URL: " + baseUrl);');
    Lines.Add('    console.log("");');
    Lines.Add('');
    Lines.Add('    api.HttpJsonCallConfig.baseUrl = baseUrl;');
    Lines.Add('');
    Lines.Add('    const results = await runAll();');
    Lines.Add('');
    Lines.Add('    let ok = 0;');
    Lines.Add('    let fail = 0;');
    Lines.Add('    for (const r of results) {');
    Lines.Add('        if (r.ok) {');
    Lines.Add('            console.log("  " + r.name + " [" + r.style + "]: OK");');
    Lines.Add('            ok++;');
    Lines.Add('        } else {');
    Lines.Add('            console.error("  " + r.name + " [" + r.style + "]: FAILED: " + r.message);');
    Lines.Add('            fail++;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    console.log("");');
    Lines.Add('    console.log("=== Summary ===");');
    Lines.Add('    console.log("Passed: " + ok);');
    Lines.Add('    console.log("Failed: " + fail);');
    Lines.Add('');
    Lines.Add('    return fail === 0 ? 0 : 1;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('main().then((rc) => {');
    Lines.Add('    process.exit(rc);');
    Lines.Add('}).catch((e) => {');
    Lines.Add('    console.error("[FATAL] " + (e instanceof Error ? e.stack : String(e)));');
    Lines.Add('    process.exit(1);');
    Lines.Add('});');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated TypeScript call test program: %d lines, %d routines (await + promise).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateHTTPServiceTypeScriptTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceModuleName, FileName: TP_String;
  Lines: TPascalStringList;
  ApiNames: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceTypeScriptTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceTypeScriptTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  ServiceModuleName := NormalizedUnit + '_http_json_service';
  FileName := NormalizedUnit + '_http_json_service_main_test___.ts';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('const svc: {');
    Lines.Add('    readonly HTTP_SERVICE_APP_NAME: string;');
    Lines.Add('    readonly HTTP_SERVICE_ENDPOINT: string;');
    Lines.Add('    readonly main: () => number;');
    Lines.Add('    readonly runSmokeTest: () => number;');
    Lines.Add('} = require("./' + ServiceModuleName.Text + '");');
    Lines.Add('');
    Lines.Add('const argv = process.argv.slice(2);');
    Lines.Add('const smoke = argv.indexOf("--smoke") !== -1;');
    Lines.Add('');
    Lines.Add('console.log("=== " + svc.HTTP_SERVICE_APP_NAME + " HTTP/JSON service test ===");');
    Lines.Add('console.log("Endpoint: " + svc.HTTP_SERVICE_ENDPOINT);');
    Lines.Add('console.log("API count: ' + umlIntToStr(Length(SupportedFuncs)) + '");');
    Lines.Add('console.log("");');
    Lines.Add('');
    Lines.Add('if (smoke) {');
    Lines.Add('    console.log("[smoke] Running in-process LocalCall self-tests.");');
    Lines.Add('    console.log("[smoke] This does NOT start LingoFuse and does NOT need the bridge.");');
    Lines.Add('    console.log("");');
    Lines.Add('    const smokeRc = svc.runSmokeTest();');
    Lines.Add('    process.exit(smokeRc);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('const rc = svc.main();');
    Lines.Add('if (rc !== 0) {');
    Lines.Add('    process.exit(rc);');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated TypeScript service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'typescript', 'TypeScript HTTP/JSON call test program',
    asCall, akTestCode,
    '_http_json_call_main_test___.ts', False,
    @GenerateHTTPCallTypeScriptTestCode);
  RegisterCodeGenEntry(
    'typescript', 'TypeScript HTTP/JSON service test program',
    asService, akTestCode,
    '_http_json_service_main_test___.ts', False,
    @GenerateHTTPServiceTypeScriptTestCode);
end.
