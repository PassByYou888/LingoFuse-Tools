unit http_ts_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine, Z.UReplace,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_call_generator] %s', [Msg.Text]);
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

function BuildTsParamListWithSep(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeTsIdent(Params[i].Name, i);
    T := ABI_Type_To_TS_Decl(Params[i].PascalType);
    Result := Result + n + ': ' + T + ', ';
  end;
end;

function BuildTsArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeTsIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ']';
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

procedure EmitTsConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('export const HttpJsonCallConfig = {');
  Lines.Add('    baseUrl: ' + TsStrLit(BaseUrl).Text + ',');
  Lines.Add('    httpTimeoutMs: 30000,');
  Lines.Add('    debugLog: false,');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('export interface HttpJsonCallOptions {');
  Lines.Add('    readonly timeoutMs?: number;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitTsException(Lines: TPascalStringList);
begin
  Lines.Add('export class HttpJsonCallError extends Error {');
  Lines.Add('    public readonly code: number;');
  Lines.Add('    public readonly httpStatus: number;');
  Lines.Add('');
  Lines.Add('    public constructor(');
  Lines.Add('        message: string,');
  Lines.Add('        code: number = -1,');
  Lines.Add('        httpStatus: number = 0,');
  Lines.Add('    ) {');
  Lines.Add('        super(message);');
  Lines.Add('        this.name = "HttpJsonCallError";');
  Lines.Add('        this.code = code;');
  Lines.Add('        this.httpStatus = httpStatus;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitTsTransport(Lines: TPascalStringList);
begin
  Lines.Add('interface ServiceBody {');
  Lines.Add('    readonly code?: number;');
  Lines.Add('    readonly result?: unknown;');
  Lines.Add('    readonly error?: string;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('async function callApi<TResult>(');
  Lines.Add('    apiName: string,');
  Lines.Add('    args: readonly unknown[],');
  Lines.Add('    timeoutMs: number,');
  Lines.Add('): Promise<TResult> {');
  Lines.Add('    const base = String(HttpJsonCallConfig.baseUrl).replace(/\/+$/, "");');
  Lines.Add('    const url = base + "/" + encodeURIComponent(apiName);');
  Lines.Add('    const body = JSON.stringify({ args: args });');
  Lines.Add('');
  Lines.Add('    if (HttpJsonCallConfig.debugLog) {');
  Lines.Add('        console.error("[http-json] POST " + url + " body=" + body);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    const controller = new AbortController();');
  Lines.Add('    let timer: ReturnType<typeof setTimeout> | null = null;');
  Lines.Add('    if (Number(timeoutMs) > 0) {');
  Lines.Add('        timer = setTimeout(function () { controller.abort(); }, Number(timeoutMs));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    let resp: Response;');
  Lines.Add('    try {');
  Lines.Add('        resp = await fetch(url, {');
  Lines.Add('            method: "POST",');
  Lines.Add('            headers: { "Content-Type": "application/json; charset=utf-8" },');
  Lines.Add('            body: body,');
  Lines.Add('            signal: controller.signal,');
  Lines.Add('        });');
  Lines.Add('    } catch (e: any) {');
  Lines.Add('        if (timer !== null) { clearTimeout(timer); }');
  Lines.Add('        if (e && e.name === "AbortError") {');
  Lines.Add('            throw new HttpJsonCallError(');
  Lines.Add('                "Request timed out after " + Number(timeoutMs) + " ms", -1, 0);');
  Lines.Add('        }');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "Network error: " + ((e && e.message) || e), -1, 0);');
  Lines.Add('    }');
  Lines.Add('    if (timer !== null) { clearTimeout(timer); }');
  Lines.Add('');
  Lines.Add('    let text: string;');
  Lines.Add('    try {');
  Lines.Add('        text = await resp.text();');
  Lines.Add('    } catch (e: any) {');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "Failed to read response body: " + ((e && e.message) || e),');
  Lines.Add('            -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (HttpJsonCallConfig.debugLog) {');
  Lines.Add('        console.error("[http-json] response " + resp.status + ": " + text);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (!resp.ok) {');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "HTTP " + resp.status + " " + (resp.statusText || ""),');
  Lines.Add('            -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (!text) {');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "Empty response from service", -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    let parsed: ServiceBody;');
  Lines.Add('    try {');
  Lines.Add('        parsed = JSON.parse(text) as ServiceBody;');
  Lines.Add('    } catch (e: any) {');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "Invalid JSON response: " + ((e && e.message) || e),');
  Lines.Add('            -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (parsed === null || typeof parsed !== "object") {');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "Response is not a JSON object", -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (typeof parsed.code !== "number") {');
  Lines.Add('        if (typeof parsed.error === "string") {');
  Lines.Add('            throw new HttpJsonCallError(parsed.error, -1, resp.status);');
  Lines.Add('        }');
  Lines.Add('        throw new HttpJsonCallError(');
  Lines.Add('            "Response has no ''code'' field", -4, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (parsed.code !== 0) {');
  Lines.Add('        const msg = typeof parsed.error === "string"');
  Lines.Add('            ? parsed.error');
  Lines.Add('            : "Remote call failed";');
  Lines.Add('        throw new HttpJsonCallError(msg, parsed.code, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    return parsed.result as TResult;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitTsApi(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamPart, ArgList, RetType, PromiseType: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamPart := BuildTsParamListWithSep(F.Params);
    ArgList := BuildTsArgList(F.Params);

    if F.IsFunction then
    begin
      RetType := ABI_Type_To_TS_Decl(F.ReturnType);
      PromiseType := 'Promise<' + RetType + '>';
    end
    else
    begin
      RetType := 'void';
      PromiseType := 'Promise<void>';
    end;

    Lines.Add('export function ' + ApiName.Text +
      '(' + ParamPart.Text + 'options: HttpJsonCallOptions = {}): ' +
      PromiseType.Text + ' {');
    if F.IsFunction then
      Lines.Add('    return callApi<' + RetType.Text + '>(' +
        TsStrLit(ApiName).Text + ', ' + ArgList.Text +
        ', options.timeoutMs ?? HttpJsonCallConfig.httpTimeoutMs);')
    else
      Lines.Add('    return callApi<void>(' +
        TsStrLit(ApiName).Text + ', ' + ArgList.Text +
        ', options.timeoutMs ?? HttpJsonCallConfig.httpTimeoutMs);');
    Lines.Add('}');
    Lines.Add('');
  end;
end;

function GenerateHTTPCallTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallTypeScriptCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallTypeScriptCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitTsConfig(Lines, BaseUrl);
    EmitTsException(Lines);
    EmitTsTransport(Lines);
    EmitTsApi(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated TypeScript call module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'typescript', 'TypeScript HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_ts.ts', False,
    @GenerateHTTPCallTypeScriptCode);
end.
