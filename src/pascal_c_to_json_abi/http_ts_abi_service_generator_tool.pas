unit http_ts_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_service_generator] %s', [Msg.Text]);
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

function ABI_Type_To_TS_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := #34#34
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'null';
end;

function ABI_Type_To_Json_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'null';
end;

function ABI_Type_To_Runtime_Converter(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'asString'
  else if ABI_Type_Is_Float(T) then
    Result := 'asFloat'
  else
    Result := 'asInt';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeInternalCallName(const ApiName: TP_String): TP_String;
begin
  Result := 'internal_call_' + ApiName;
end;

function MakeSafeTSIdent(const Name: TP_String; Index: integer): TP_String;
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
      Result := Result + c
    else
      Result := Result + '_';
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
    Result.Same('undefined') or Result.Same('any') or Result.Same('unknown') or
    Result.Same('never') or Result.Same('type') or Result.Same('declare') or
    Result.Same('module') or Result.Same('namespace') or Result.Same('require') or
    Result.Same('number') or Result.Same('string') or Result.Same('boolean') or
    Result.Same('symbol') or Result.Same('bigint') or Result.Same('keyof') or
    Result.Same('readonly') or Result.Same('infer') or Result.Same('is') or
    Result.Same('as') or Result.Same('asserts') then
    Result := Result + '_';
end;

function JsStrLit(const S: TP_String): TP_String;
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
      #34: Result := Result + '\"';
      #92: Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9:  Result := Result + '\t';
      #8:  Result := Result + '\b';
      #12: Result := Result + '\f';
      else
        if (code < 32) or (code = 127) then
        begin
          Result := Result + '\x';
          Result := Result + HEXDIG[((code shr 4) and $F) + 1];
          Result := Result + HEXDIG[(code and $F) + 1];
        end
        else
          Result := Result + c;
    end;
  end;
  Result := Result + #34;
end;

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);

  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);

  if T.Len > 0 then
  begin
    if T[1] = '{' then
      T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;

  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then
      T := T.GetString(1, T.Len).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then
      T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
  end;

  Result := T;
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var
  i, j: integer;
  Line: TP_String;
begin
  Result := '';
  if Comment.Len = 0 then
    Exit;

  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do
      Inc(j);

    if j > i then
    begin
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);

      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
        end
        else
        begin
          if Line[1] = '*' then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);

          if Line.Len > 0 then
          begin
            Result := Line;
            if Result.Len > 200 then
              Result := Result.GetString(1, 201);
            Exit;
          end;
        end;
      end;
    end;

    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
end;

function BuildTSParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, decl: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeTSIdent(Params[i].Name, i);
    decl := ABI_Type_To_TS_Decl(Params[i].PascalType);
    if i > 0 then Result := Result + ', ';
    Result := Result + n + ': ' + decl;
  end;
end;

function BuildTSArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + MakeSafeTSIdent(Params[i].Name, i);
  end;
end;

function BuildSmokeJsonRequest(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  if Length(Params) = 0 then
  begin
    Result := '{}';
    Exit;
  end;
  Result := '{"args": [';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + ABI_Type_To_Json_Default(Params[i].PascalType);
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

procedure EmitConfig(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('export const HTTP_SERVICE_APP_NAME = ' + JsStrLit(AppName).Text + ';');
  Lines.Add('export const HTTP_SERVICE_APP_DESC = ' + JsStrLit(AppDesc).Text + ';');
  Lines.Add('export const HTTP_SERVICE_ENDPOINT = ' + JsStrLit(Endpoint).Text + ';');
  Lines.Add('');
  Lines.Add('export let DEBUG_LOG: boolean =');
  Lines.Add('    process.env.LINGOFUSE_DEBUG === "1" ||');
  Lines.Add('    process.env.LINGOFUSE_DEBUG === "true";');
  Lines.Add('');
end;

procedure EmitHelpers(Lines: TPascalStringList);
begin
  Lines.Add('export function asInt(value: unknown, name: string): number {');
  Lines.Add('    const n = Number(value);');
  Lines.Add('    if (!Number.isFinite(n)) {');
  Lines.Add('        throw new Error(`Argument "${name}" expects an integer, got: ` + JSON.stringify(value));');
  Lines.Add('    }');
  Lines.Add('    return Math.trunc(n);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('export function asFloat(value: unknown, name: string): number {');
  Lines.Add('    const n = Number(value);');
  Lines.Add('    if (!Number.isFinite(n)) {');
  Lines.Add('        throw new Error(`Argument "${name}" expects a number, got: ` + JSON.stringify(value));');
  Lines.Add('    }');
  Lines.Add('    return n;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('export function asString(value: unknown, _name: string): string {');
  Lines.Add('    if (value === null || value === undefined) return "";');
  Lines.Add('    return String(value);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('export function extractArgs(');
  Lines.Add('    req: Record<string, unknown>,');
  Lines.Add('    paramNames: string[],');
  Lines.Add('    defaults: unknown[],');
  Lines.Add('): unknown[] {');
  Lines.Add('    if ("args" in req) {');
  Lines.Add('        const arr = req.args;');
  Lines.Add('        if (!Array.isArray(arr)) {');
  Lines.Add('            throw new Error(''"args" must be a JSON array'');');
  Lines.Add('        }');
  Lines.Add('        return paramNames.map((_, i) =>');
  Lines.Add('            i < arr.length && arr[i] !== null && arr[i] !== undefined ? arr[i] : defaults[i]);');
  Lines.Add('    }');
  Lines.Add('    return paramNames.map((name, i) =>');
  Lines.Add('        req[name] !== null && req[name] !== undefined ? req[name] : defaults[i]);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('export function writeSuccess(output: lf.DataHandle, result: unknown): void {');
  Lines.Add('    lf.io.writeJson(output, { code: 0, result });');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('export function writeError(output: lf.DataHandle, message: string): void {');
  Lines.Add('    try { lf.io.writeJson(output, { code: -1, error: message }); } catch { }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamList, StubName: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := MakeInternalCallName(ApiName);
    ParamList := BuildTSParamList(F.Params);

    if F.IsFunction then
    begin
      Lines.Add('export function ' + StubName.Text + '(' + ParamList.Text + '): ' +
        ABI_Type_To_TS_Decl(F.ReturnType).Text + ' {');
      Lines.Add('    return ' + ABI_Type_To_TS_Default(F.ReturnType).Text + ';');
      Lines.Add('}');
    end
    else
    begin
      Lines.Add('export function ' + StubName.Text + '(' + ParamList.Text + '): void {');
      Lines.Add('}');
    end;
    Lines.Add('');
  end;
end;

procedure EmitRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, Description, NameList, DefaultList, ConvName, ParamName: TP_String;
begin
  Lines.Add('export function registerAllHttpJsonApis(app: lf.AppHandle): void {');

  if Length(SupportedFuncs) = 0 then
  begin
    Lines.Add('    void app;');
  end
  else
  begin
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      StubName := MakeInternalCallName(ApiName);

      NameList := '[';
      DefaultList := '[';
      for j := 0 to High(F.Params) do
      begin
        if j > 0 then
        begin
          NameList := NameList + ', ';
          DefaultList := DefaultList + ', ';
        end;
        NameList := NameList + JsStrLit(F.Params[j].Name);
        DefaultList := DefaultList + ABI_Type_To_Json_Default(F.Params[j].PascalType);
      end;
      NameList := NameList + ']';
      DefaultList := DefaultList + ']';

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;

      Lines.Add('');
      Lines.Add('    app.registerCall(');
      Lines.Add('        ' + JsStrLit(ApiName).Text + ',');
      Lines.Add('        ' + JsStrLit(Description).Text + ',');
      Lines.Add('        (input, output) => {');
      Lines.Add('            try {');
      Lines.Add('                const req = lf.io.readJson<Record<string, unknown>>(input);');
      Lines.Add('                if (req === null || typeof req !== "object") {');
      Lines.Add('                    throw new Error("Request must be a JSON object");');
      Lines.Add('                }');
      Lines.Add('                const args = extractArgs(req, ' + NameList.Text + ', ' + DefaultList.Text + ');');

      for j := 0 to High(F.Params) do
      begin
        ParamName := MakeSafeTSIdent(F.Params[j].Name, j);
        ConvName := ABI_Type_To_Runtime_Converter(F.Params[j].PascalType);
        Lines.Add('                const ' + ParamName.Text + ' = ' + ConvName.Text +
          '(args[' + umlIntToStr(j).Text + '], ' + JsStrLit(F.Params[j].Name).Text + ');');
      end;

      Lines.Add('');
      if F.IsFunction then
        Lines.Add('                const result = ' + StubName.Text +
          '(' + BuildTSArgList(F.Params).Text + ');')
      else
        Lines.Add('                ' + StubName.Text +
          '(' + BuildTSArgList(F.Params).Text + ');');

      if F.IsFunction then
        Lines.Add('                writeSuccess(output, result);')
      else
        Lines.Add('                writeSuccess(output, null);');

      Lines.Add('            } catch (err) {');
      Lines.Add('                writeError(output, (err as Error)?.message ?? String(err));');
      Lines.Add('                console.error(' + JsStrLit('[' + ApiName + '] callback threw:').Text + ', err);');
      Lines.Add('            }');
      Lines.Add('        });');
    end;
  end;

  Lines.Add('}');
  Lines.Add('');
  Lines.Add('export function createAndRegisterHttpJsonApp(): lf.AppHandle | null {');
  Lines.Add('    let app: lf.AppHandle;');
  Lines.Add('    try {');
  Lines.Add('        app = new lf.AppHandle(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        console.error("Failed to create the LingoFuse App:", e);');
  Lines.Add('        return null;');
  Lines.Add('    }');
  Lines.Add('    try {');
  Lines.Add('        registerAllHttpJsonApis(app);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        console.error("Failed to register APIs:", e);');
  Lines.Add('        try { app.dispose(); } catch { }');
  Lines.Add('        return null;');
  Lines.Add('    }');
  Lines.Add('    return app;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitMain(Lines: TPascalStringList);
begin
  Lines.Add('export function main(): number {');
  Lines.Add('    console.log(`=== ${HTTP_SERVICE_APP_NAME} HTTP/JSON service ===`);');
  Lines.Add('    console.log(`Endpoint: ${HTTP_SERVICE_ENDPOINT}`);');
  Lines.Add('    console.log("");');
  Lines.Add('');
  Lines.Add('    let app: lf.AppHandle | null = null;');
  Lines.Add('');
  Lines.Add('    const cleanupOnFailure = (): void => {');
  Lines.Add('        if (app) {');
  Lines.Add('            try { app.dispose(); } catch { }');
  Lines.Add('            app = null;');
  Lines.Add('        }');
  Lines.Add('        try { lf.network.clearNetworkEvent(); } catch { }');
  Lines.Add('        try { lf.AsyncBridge.shutdownInstance(); } catch { }');
  Lines.Add('        try { lf.framework.exitMainThread(); } catch { }');
  Lines.Add('        try { lf.framework.shutdown(); } catch { }');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    try {');
  Lines.Add('        lf.options.setOptWaitConnectionReadyOk(false);');
  Lines.Add('        lf.options.setOptOverlapConnection(true);');
  Lines.Add('    } catch { }');
  Lines.Add('');
  Lines.Add('    lf.framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('    if (lf.framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT) < 0) {');
  Lines.Add('        console.error(`[FATAL] PrepareService failed for endpoint "${HTTP_SERVICE_ENDPOINT}".`);');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    try {');
  Lines.Add('        app = createAndRegisterHttpJsonApp();');
  Lines.Add('    } catch (e) {');
  Lines.Add('        console.error("[FATAL] createAndRegisterHttpJsonApp threw:", e);');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('    if (!app) {');
  Lines.Add('        console.error("[FATAL] Failed to create and register the App.");');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (lf.framework.prepareClient(HTTP_SERVICE_ENDPOINT, app) < 0) {');
  Lines.Add('        console.error(`[FATAL] PrepareClient failed for endpoint "${HTTP_SERVICE_ENDPOINT}".`);');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (lf.framework.prepareDone() !== 1) {');
  Lines.Add('        console.error("[FATAL] PrepareDone failed.");');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    console.log("[OK] Service ready. Press Ctrl+C to stop.");');
  Lines.Add('');
  Lines.Add('    const shutdown = (sigName: string | null): void => {');
  Lines.Add('        if (sigName) console.log(`${sigName} received, shutting down...`);');
  Lines.Add('        try { lf.network.clearNetworkEvent(); } catch { }');
  Lines.Add('        try { lf.AsyncBridge.shutdownInstance(); } catch { }');
  Lines.Add('        try { lf.framework.exitMainThread(); } catch { }');
  Lines.Add('        if (app) { try { app.dispose(); } catch { } app = null; }');
  Lines.Add('        try { lf.framework.shutdown(); } catch { }');
  Lines.Add('        console.log("Service stopped.");');
  Lines.Add('        process.exit(0);');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    process.on("SIGINT", () => shutdown("SIGINT"));');
  Lines.Add('    process.on("SIGTERM", () => shutdown("SIGTERM"));');
  Lines.Add('');
  Lines.Add('    setInterval(() => { }, 1 << 30);');
  Lines.Add('    return 0;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSmokeTest(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, RequestJson: TP_String;
begin
  Lines.Add('export function runSmokeTest(): number {');
  Lines.Add('    console.log("[smoke] Running in-process LocalCall self-tests.");');
  Lines.Add('    console.log("[smoke] This does NOT start LingoFuse and does NOT need the bridge.");');
  Lines.Add('    console.log("");');
  Lines.Add('');
  Lines.Add('    const app = createAndRegisterHttpJsonApp();');
  Lines.Add('    if (!app) {');
  Lines.Add('        console.error("[smoke] failed to create App");');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    const cases: Array<[string, unknown]> = [');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    RequestJson := BuildSmokeJsonRequest(F.Params);
    Lines.Add('        [' + JsStrLit(ApiName).Text + ', ' + RequestJson.Text + '],');
  end;

  if Length(SupportedFuncs) = 0 then
    Lines.Add('        ');

  Lines.Add('    ];');
  Lines.Add('');
  Lines.Add('    let ok = 0;');
  Lines.Add('    let fail = 0;');
  Lines.Add('');
  Lines.Add('    for (const [apiName, requestJson] of cases) {');
  Lines.Add('        let req: lf.DataHandle | null = null;');
  Lines.Add('        let resp: lf.DataHandle | null = null;');
  Lines.Add('        try {');
  Lines.Add('            req = new lf.DataHandle(apiName);');
  Lines.Add('            lf.io.writeJson(req, requestJson);');
  Lines.Add('            resp = app.localCall(req);');
  Lines.Add('            const respObj = lf.io.readJson<{ code: number }>(resp);');
  Lines.Add('            if (respObj && respObj.code === 0) {');
  Lines.Add('                console.log(`  ${apiName}: OK`);');
  Lines.Add('                ok++;');
  Lines.Add('            } else {');
  Lines.Add('                console.error(`  ${apiName}: non-zero code: ${JSON.stringify(respObj)}`);');
  Lines.Add('                fail++;');
  Lines.Add('            }');
  Lines.Add('        } catch (e) {');
  Lines.Add('            console.error(`  ${apiName}: FAILED: ${(e as Error)?.message ?? e}`);');
  Lines.Add('            fail++;');
  Lines.Add('        } finally {');
  Lines.Add('            if (resp) { try { resp.dispose(); } catch { } }');
  Lines.Add('            if (req) { try { req.dispose(); } catch { } }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    try { app.dispose(); } catch { }');
  Lines.Add('');
  Lines.Add('    console.log("");');
  Lines.Add('    console.log("=== Smoke test summary ===");');
  Lines.Add('    console.log(`Passed: ${ok}`);');
  Lines.Add('    console.log(`Failed: ${fail}`);');
  Lines.Add('    return fail === 0 ? 0 : 1;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitModuleEntry(Lines: TPascalStringList);
begin
  Lines.Add('if (require.main === module) {');
  Lines.Add('    if (process.argv.includes("--smoke")) {');
  Lines.Add('        process.exit(runSmokeTest());');
  Lines.Add('    } else {');
  Lines.Add('        const rc = main();');
  Lines.Add('        if (rc !== 0) process.exit(rc);');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('import * as lf from "lingofuse-ts";');
    Lines.Add('');
    EmitConfig(Lines, AppName, AppDesc, Endpoint);
    EmitHelpers(Lines);
    EmitStubs(Lines, SupportedFuncs, ApiNames);
    EmitRegistration(Lines, SupportedFuncs, ApiNames);
    EmitMain(Lines);
    EmitSmokeTest(Lines, SupportedFuncs, ApiNames);
    EmitModuleEntry(Lines);

    Result := Lines;
    Log(PFormat('Generated TypeScript service module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'typescript', 'TypeScript HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.ts', False,
    @GenerateHTTPServiceTypeScriptCode);
end.
