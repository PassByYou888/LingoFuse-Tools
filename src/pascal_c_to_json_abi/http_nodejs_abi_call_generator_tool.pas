unit http_nodejs_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallNodejsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_nodejs_abi_call_generator] %s', [Msg.Text]);
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

function BuildJsParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJsIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildJsArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJsIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ']';
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

procedure EmitJsHeader(Lines: TPascalStringList);
begin
  Lines.Add(#39 + 'use strict' + #39 + ';');
  Lines.Add('');
end;

procedure EmitJsConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('let HTTP_CALL_BASE_URL = ' + JsStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('let HTTP_CALL_TIMEOUT_MS = 30000;');
  Lines.Add('');
  Lines.Add('let DEBUG_LOG = process.env.LINGOFUSE_DEBUG === ' + #39 + '1' + #39);
  Lines.Add('    || process.env.LINGOFUSE_DEBUG === ' + #39 + 'true' + #39 + ';');
  Lines.Add('');
end;

procedure EmitJsTransport(Lines: TPascalStringList);
begin
  Lines.Add('class HTTPCallError extends Error {');
  Lines.Add('    constructor(message, code, httpStatus) {');
  Lines.Add('        super(message);');
  Lines.Add('        this.name = ' + #39 + 'HTTPCallError' + #39 + ';');
  Lines.Add('        this.code = (typeof code === ' + #39 + 'number' + #39 + ') ? code : -1;');
  Lines.Add('        this.httpStatus = (typeof httpStatus === ' + #39 + 'number' + #39 + ')');
  Lines.Add('            ? httpStatus : 0;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('async function callApi(apiName, args) {');
  Lines.Add('    const base = String(HTTP_CALL_BASE_URL).replace(/\/+$/, ' + #39#39 + ');');
  Lines.Add('    const url = base + ' + #39 + '/' + #39 + ' + encodeURIComponent(apiName);');
  Lines.Add('    const body = JSON.stringify({ args: args });');
  Lines.Add('');
  Lines.Add('    if (DEBUG_LOG) {');
  Lines.Add('        console.error(' + #39 + '[http-json] POST ' + #39 + ' + url + ' + #39 + ' body=' + #39 + ' + body);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    const controller = new AbortController();');
  Lines.Add('    let timer = null;');
  Lines.Add('    if (Number(HTTP_CALL_TIMEOUT_MS) > 0) {');
  Lines.Add('        timer = setTimeout(');
  Lines.Add('            function () { controller.abort(); },');
  Lines.Add('            Number(HTTP_CALL_TIMEOUT_MS));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    let resp;');
  Lines.Add('    try {');
  Lines.Add('        resp = await fetch(url, {');
  Lines.Add('            method: ' + #39 + 'POST' + #39 + ',');
  Lines.Add('            headers: {');
  Lines.Add('                ' + #39 + 'Content-Type' + #39 + ': ' + #39 + 'application/json; charset=utf-8' + #39);
  Lines.Add('            },');
  Lines.Add('            body: body,');
  Lines.Add('            signal: controller.signal');
  Lines.Add('        });');
  Lines.Add('    } catch (e) {');
  Lines.Add('        if (timer !== null) { clearTimeout(timer); }');
  Lines.Add('        if (e && e.name === ' + #39 + 'AbortError' + #39 + ') {');
  Lines.Add('            throw new HTTPCallError(');
  Lines.Add('                ' + #39 + 'Request timed out after ' + #39 + ' +');
  Lines.Add('                Number(HTTP_CALL_TIMEOUT_MS) + ' + #39 + ' ms' + #39 + ', -1, 0);');
  Lines.Add('        }');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'Network error: ' + #39 + ' + (e && e.message || e), -1, 0);');
  Lines.Add('    }');
  Lines.Add('    if (timer !== null) { clearTimeout(timer); }');
  Lines.Add('');
  Lines.Add('    let text;');
  Lines.Add('    try {');
  Lines.Add('        text = await resp.text();');
  Lines.Add('    } catch (e) {');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'Failed to read response body: ' + #39 + ' +');
  Lines.Add('            (e && e.message || e), -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (DEBUG_LOG) {');
  Lines.Add('        console.error(' + #39 + '[http-json] response ' + #39 + ' + resp.status +');
  Lines.Add('            ' + #39 + ': ' + #39 + ' + text);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (!resp.ok) {');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'HTTP ' + #39 + ' + resp.status + ' + #39 + ' ' + #39 + ' + (resp.statusText || ' + #39#39 + ') +');
  Lines.Add('            (text ? ' + #39 + ': ' + #39 + ' + text : ' + #39#39 + '), -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (!text) {');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'Empty response from bridge' + #39 + ', -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    let parsed;');
  Lines.Add('    try {');
  Lines.Add('        parsed = JSON.parse(text);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'Invalid JSON response: ' + #39 + ' + (e && e.message || e),');
  Lines.Add('            -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (parsed === null || typeof parsed !== ' + #39 + 'object' + #39 + ') {');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'Response is not a JSON object' + #39 + ', -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (parsed.code === undefined) {');
  Lines.Add('        if (typeof parsed.error === ' + #39 + 'string' + #39 + ') {');
  Lines.Add('            throw new HTTPCallError(parsed.error, -1, resp.status);');
  Lines.Add('        }');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            ' + #39 + 'Response has no "code" field' + #39 + ', -1, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (parsed.code !== 0) {');
  Lines.Add('        throw new HTTPCallError(');
  Lines.Add('            parsed.error || ' + #39 + 'Remote call failed' + #39 + ',');
  Lines.Add('            parsed.code, resp.status);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    return parsed.result;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitJsFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ArgList: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ArgList := BuildJsArgList(F.Params);

    Lines.Add('async function ' + ApiName.Text + '(' +
      BuildJsParamDecl(F.Params).Text + ') {');
    Lines.Add('    return callApi(' + JsStrLit(ApiName).Text + ', ' +
      ArgList.Text + ');');
    Lines.Add('}');
    Lines.Add('');
  end;
end;

procedure EmitJsExports(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('module.exports = {');
  Lines.Add('    HTTPCallError: HTTPCallError,');
  Lines.Add('    callApi: callApi,');
  Lines.Add('    get HTTP_CALL_BASE_URL() { return HTTP_CALL_BASE_URL; },');
  Lines.Add('    set HTTP_CALL_BASE_URL(v) { HTTP_CALL_BASE_URL = String(v); },');
  Lines.Add('    get HTTP_CALL_TIMEOUT_MS() { return HTTP_CALL_TIMEOUT_MS; },');
  Lines.Add('    set HTTP_CALL_TIMEOUT_MS(v) {');
  Lines.Add('        HTTP_CALL_TIMEOUT_MS = Number(v);');
  Lines.Add('    },');
  Lines.Add('    get DEBUG_LOG() { return DEBUG_LOG; },');
  Lines.Add('    set DEBUG_LOG(v) { DEBUG_LOG = Boolean(v); }');

  for i := 0 to High(SupportedFuncs) do
    Lines.Add('    , ' + ApiNames[i].Text + ': ' + ApiNames[i].Text);

  Lines.Add('};');
  Lines.Add('');
end;

function GenerateHTTPCallNodejsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallNodejsCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallNodejsCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitJsHeader(Lines);
    EmitJsConfig(Lines, BaseUrl);
    EmitJsTransport(Lines);
    EmitJsFunctions(Lines, SupportedFuncs, ApiNames);
    EmitJsExports(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated Node.js call module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'nodejs', 'Node.js HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_node.js', False,
    @GenerateHTTPCallNodejsCode);
end.
