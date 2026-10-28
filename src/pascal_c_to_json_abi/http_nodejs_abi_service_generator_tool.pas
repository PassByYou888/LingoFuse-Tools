unit http_nodejs_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceNodejsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_nodejs_abi_service_generator] %s', [Msg.Text]);
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

function ABI_Type_To_Js_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := #39#39
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'null';
end;

function ABI_Type_To_Json_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'null';
end;

function ABI_Type_To_Js_Converter(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'asString'
  else if ABI_Type_Is_Float(T) then
    Result := 'asFloat'
  else
    Result := 'asInt';
end;

function ABI_Type_To_Js_Stub_Return(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'return ' + #39 + #39 + ';'
  else if ABI_Type_Is_Float(T) then
    Result := 'return 0.0;'
  else
    Result := 'return 0;';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeInternalCallName(const ApiName: TP_String): TP_String;
begin
  Result := 'internal_call_' + ApiName;
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

function BuildJsDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Js_Default(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
  Result := Result + ']';
end;

function BuildJsNameList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + JsStrLit(Params[i].Name);
  end;
  Result := Result + ']';
end;

function BuildJsLocalNameList(const Params: TParamArray): TP_String;
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
    d := ABI_Type_To_Json_Default(Params[i].PascalType);
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

procedure EmitJsHeader(Lines: TPascalStringList;
  const AppName, Endpoint: TP_String);
begin
  Lines.Add(#39 + 'use strict' + #39 + ';');
  Lines.Add('');
  Lines.Add('let lf;');
  Lines.Add('try {');
  Lines.Add('    lf = require(' + #39 + 'lingofuse-js' + #39 + ');');
  Lines.Add('} catch (e) {');
  Lines.Add('    console.error(' + #39 + 'FATAL: cannot load "lingofuse-js".' + #39 + ');');
  Lines.Add('    console.error(' + #39 + 'Install it with: npm install lingofuse-js' + #39 + ');');
  Lines.Add('    console.error(' + #39 + 'Details: ' + #39 + ' + (e && e.message || e));');
  Lines.Add('    process.exit(1);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('const AppHandle = lf.AppHandle;');
  Lines.Add('const DataHandle = lf.DataHandle;');
  Lines.Add('const io = lf.io;');
  Lines.Add('const framework = lf.framework;');
  Lines.Add('');
  Lines.Add('const HTTP_SERVICE_APP_NAME = ' + JsStrLit(AppName).Text + ';');
  Lines.Add('const HTTP_SERVICE_APP_DESC = ' + JsStrLit('HTTP/JSON service for ' + AppName).Text + ';');
  Lines.Add('const HTTP_SERVICE_ENDPOINT = ' + JsStrLit(Endpoint).Text + ';');
  Lines.Add('');
  Lines.Add('let DEBUG_LOG = process.env.LINGOFUSE_DEBUG === ' + #39 + '1' + #39);
  Lines.Add('    || process.env.LINGOFUSE_DEBUG === ' + #39 + 'true' + #39 + ';');
  Lines.Add('');
end;

procedure EmitJsHelpers(Lines: TPascalStringList);
begin
  Lines.Add('function asInt(value, name) {');
  Lines.Add('    const n = Number(value);');
  Lines.Add('    if (!Number.isFinite(n)) {');
  Lines.Add('        throw new Error(' + #39 + 'Argument "' + #39 + ' + name +');
  Lines.Add('            ' + #39 + '" expects an integer, got: ' + #39 + ' + JSON.stringify(value));');
  Lines.Add('    }');
  Lines.Add('    return Math.trunc(n);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function asFloat(value, name) {');
  Lines.Add('    const n = Number(value);');
  Lines.Add('    if (!Number.isFinite(n)) {');
  Lines.Add('        throw new Error(' + #39 + 'Argument "' + #39 + ' + name +');
  Lines.Add('            ' + #39 + '" expects a number, got: ' + #39 + ' + JSON.stringify(value));');
  Lines.Add('    }');
  Lines.Add('    return n;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function asString(value, _name) {');
  Lines.Add('    if (value === null || value === undefined) {');
  Lines.Add('        return ' + #39#39 + ';');
  Lines.Add('    }');
  Lines.Add('    return String(value);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function extractArgs(req, paramNames, defaults) {');
  Lines.Add('    if (req.args !== undefined) {');
  Lines.Add('        if (!Array.isArray(req.args)) {');
  Lines.Add('            throw new Error(' + #39 + '"args" must be a JSON array' + #39 + ');');
  Lines.Add('        }');
  Lines.Add('        const arr = req.args;');
  Lines.Add('        return paramNames.map((_, i) =>');
  Lines.Add('            (i < arr.length && arr[i] !== null && arr[i] !== undefined)');
  Lines.Add('                ? arr[i]');
  Lines.Add('                : defaults[i]);');
  Lines.Add('    }');
  Lines.Add('    return paramNames.map((name, i) =>');
  Lines.Add('        (req[name] !== null && req[name] !== undefined)');
  Lines.Add('            ? req[name]');
  Lines.Add('            : defaults[i]);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function writeSuccess(output, result) {');
  Lines.Add('    io.writeJson(output, { code: 0, result: result });');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function writeError(output, message) {');
  Lines.Add('    try {');
  Lines.Add('        io.writeJson(output, { code: -1, error: String(message) });');
  Lines.Add('    } catch (_) {');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitJsStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamList, CallArgs, StubName: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := MakeInternalCallName(ApiName);

    ParamList := BuildJsLocalNameList(F.Params);
    CallArgs := BuildJsLocalNameList(F.Params);

    Lines.Add('function ' + StubName.Text + '(' + ParamList.Text + ') {');
    if F.IsFunction then
      Lines.Add('    ' + ABI_Type_To_Js_Stub_Return(F.ReturnType))
    else
      Lines.Add('    void 0;');
    Lines.Add('}');
    Lines.Add('');
  end;
end;

procedure EmitJsRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, Description: TP_String;
  NameList, DefaultList, ArgExpr, ConvExpr, LocalNames: TP_String;
  Args: TParamArray;
begin
  Lines.Add('function registerAllHttpJsonApis(app) {');

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
      Args := F.Params;
      NameList := BuildJsNameList(Args);
      DefaultList := BuildJsDefaultArgList(Args);
      LocalNames := BuildJsLocalNameList(Args);

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;

      Lines.Add('');
      Lines.Add('    app.registerCall(');
      Lines.Add('        ' + JsStrLit(ApiName).Text + ',');
      Lines.Add('        ' + JsStrLit(Description).Text + ',');
      Lines.Add('        function (input, output) {');
      Lines.Add('            try {');
      Lines.Add('                const req = io.readJson(input);');
      Lines.Add('                if (req === null || typeof req !== ' + #39 + 'object' + #39 + ') {');
      Lines.Add('                    throw new Error(' + #39 + 'Request must be a JSON object' + #39 + ');');
      Lines.Add('                }');
      Lines.Add('                const args = extractArgs(req, ' + NameList.Text + ',');
      Lines.Add('                    ' + DefaultList.Text + ');');

      for j := 0 to High(Args) do
      begin
        ArgExpr := MakeSafeJsIdent(Args[j].Name, j);
        ConvExpr := ABI_Type_To_Js_Converter(Args[j].PascalType);
        Lines.Add('                const ' + ArgExpr.Text + ' = ' + ConvExpr.Text + '(');
        Lines.Add('                    args[' + umlIntToStr(j).Text + '], ' +
          JsStrLit(Args[j].Name).Text + ');');
      end;

      if F.IsFunction then
        Lines.Add('                const result = ' + StubName.Text + '(' + LocalNames.Text + ');')
      else
        Lines.Add('                ' + StubName.Text + '(' + LocalNames.Text + ');');

      if F.IsFunction then
        Lines.Add('                writeSuccess(output, result);')
      else
        Lines.Add('                writeSuccess(output, null);');
      Lines.Add('            } catch (err) {');
      Lines.Add('                writeError(output, err && err.message || err);');
      Lines.Add('                console.error(');
      Lines.Add('                    ' + JsStrLit('[' + ApiName + '] callback threw:').Text + ' +');
      Lines.Add('                    (err && err.stack || err));');
      Lines.Add('            }');
      Lines.Add('        });');
    end;
    Lines.Add('    void app;');
  end;

  Lines.Add('}');
  Lines.Add('');
  Lines.Add('function createAndRegisterHttpJsonApp() {');
  Lines.Add('    let app;');
  Lines.Add('    try {');
  Lines.Add('        app = new AppHandle(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        console.error(' + #39 + 'Failed to create the LingoFuse App: ' + #39 + ' +');
  Lines.Add('            (e && e.message || e));');
  Lines.Add('        return null;');
  Lines.Add('    }');
  Lines.Add('    try {');
  Lines.Add('        registerAllHttpJsonApis(app);');
  Lines.Add('    } catch (e) {');
  Lines.Add('        console.error(' + #39 + 'Failed to register APIs: ' + #39 + ' +');
  Lines.Add('            (e && e.message || e));');
  Lines.Add('        try { app.dispose(); } catch (_) {}');
  Lines.Add('        return null;');
  Lines.Add('    }');
  Lines.Add('    return app;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitJsMain(Lines: TPascalStringList; const Endpoint: TP_String);
begin
  Lines.Add('function main() {');
  Lines.Add('    console.log(' + #39 + '=== ' + #39 + ' + HTTP_SERVICE_APP_NAME +');
  Lines.Add('        ' + #39 + ' HTTP/JSON service ===' + #39 + ');');
  Lines.Add('    console.log(' + #39 + 'Endpoint: ' + #39 + ' + HTTP_SERVICE_ENDPOINT);');
  Lines.Add('    console.log(' + #39#39 + ');');
  Lines.Add('');
  Lines.Add('    let app = null;');
  Lines.Add('');
  Lines.Add('    const cleanupOnFailure = function () {');
  Lines.Add('        if (app) {');
  Lines.Add('            try { app.dispose(); } catch (_) {}');
  Lines.Add('            app = null;');
  Lines.Add('        }');
  Lines.Add('        try { framework.exitMainThread(); } catch (_) {}');
  Lines.Add('        try { framework.shutdown(); } catch (_) {}');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    try {');
  Lines.Add('        framework.setOption(' + #39 + 'Wait_Connection_ReadyOk' + #39 + ', ' + #39 + 'False' + #39 + ');');
  Lines.Add('        framework.setOption(' + #39 + 'Overlap_Connection' + #39 + ', ' + #39 + 'True' + #39 + ');');
  Lines.Add('    } catch (_) {');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('    if (framework.prepareService(');
  Lines.Add('            HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT) < 0) {');
  Lines.Add('        console.error(' + #39 + '[FATAL] PrepareService failed for endpoint "' + #39 + ' +');
  Lines.Add('            HTTP_SERVICE_ENDPOINT + ' + #39 + '".' + #39 + ');');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    try {');
  Lines.Add('        app = createAndRegisterHttpJsonApp();');
  Lines.Add('    } catch (e) {');
  Lines.Add('        console.error(' + #39 + '[FATAL] createAndRegisterHttpJsonApp threw: ' + #39 + ' +');
  Lines.Add('            (e && e.message || e));');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('    if (!app) {');
  Lines.Add('        console.error(' + #39 + '[FATAL] Failed to create and register the App.' + #39 + ');');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (framework.prepareClient(HTTP_SERVICE_ENDPOINT, app) < 0) {');
  Lines.Add('        console.error(' + #39 + '[FATAL] PrepareClient failed for endpoint "' + #39 + ' +');
  Lines.Add('            HTTP_SERVICE_ENDPOINT + ' + #39 + '".' + #39 + ');');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (framework.prepareDone() !== 1) {');
  Lines.Add('        console.error(' + #39 + '[FATAL] PrepareDone failed.' + #39 + ');');
  Lines.Add('        cleanupOnFailure();');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    console.log(' + #39 + '[OK] Service ready. Press Ctrl+C to stop.' + #39 + ');');
  Lines.Add('');
  Lines.Add('    const shutdown = function (sigName) {');
  Lines.Add('        if (sigName) {');
  Lines.Add('            console.log(sigName + ' + #39 + ' received, shutting down...' + #39 + ');');
  Lines.Add('        }');
  Lines.Add('        try { framework.exitMainThread(); } catch (_) {}');
  Lines.Add('        if (app) { try { app.dispose(); } catch (_) {} }');
  Lines.Add('        try { framework.shutdown(); } catch (_) {}');
  Lines.Add('        console.log(' + #39 + 'Service stopped.' + #39 + ');');
  Lines.Add('        process.exit(0);');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    process.on(' + #39 + 'SIGINT' + #39 + ', function () { shutdown(' + #39 + 'SIGINT' + #39 + '); });');
  Lines.Add('    process.on(' + #39 + 'SIGTERM' + #39 + ', function () { shutdown(' + #39 + 'SIGTERM' + #39 + '); });');
  Lines.Add('');
  Lines.Add('    setInterval(function () {}, 1 << 30);');
  Lines.Add('    return 0;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitJsSmokeTest(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  ApiName, RequestJson: TP_String;
  F: TFunctionStructure;
begin
  Lines.Add('function runSmokeTest() {');
  Lines.Add('    console.log(' + #39 + '[smoke] running in-process LocalCall self-tests' + #39 + ');');
  Lines.Add('    console.log(' + #39 + '[smoke] this mode does NOT start LingoFuse and ' + #39 + ' +');
  Lines.Add('        ' + #39 + 'does NOT need the bridge' + #39 + ');');
  Lines.Add('    console.log(' + #39#39 + ');');
  Lines.Add('');
  Lines.Add('    const app = createAndRegisterHttpJsonApp();');
  Lines.Add('    if (!app) {');
  Lines.Add('        console.error(' + #39 + '[smoke] failed to create App' + #39 + ');');
  Lines.Add('        return 1;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    const cases = [');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    RequestJson := BuildSmokeJsonRequest(F.Params);
    Lines.Add('        [' + JsStrLit(ApiName).Text + ', ' +
      JsStrLit(RequestJson).Text + '],');
  end;
  if Length(SupportedFuncs) = 0 then
    Lines.Add('    ');
  Lines.Add('    ];');
  Lines.Add('');
  Lines.Add('    let ok = 0;');
  Lines.Add('    let fail = 0;');
  Lines.Add('');
  Lines.Add('    for (const [apiName, requestJson] of cases) {');
  Lines.Add('        let req = null;');
  Lines.Add('        let resp = null;');
  Lines.Add('        try {');
  Lines.Add('            req = new DataHandle(apiName);');
  Lines.Add('            io.writeString(req, requestJson);');
  Lines.Add('            resp = app.localCall(req);');
  Lines.Add('            const respObj = io.readJson(resp);');
  Lines.Add('            if (respObj && respObj.code === 0) {');
  Lines.Add('                console.log(' + #39 + '  ' + #39 + ' + apiName + ' + #39 + ': OK' + #39 + ');');
  Lines.Add('                ok += 1;');
  Lines.Add('            } else {');
  Lines.Add('                console.error(' + #39 + '  ' + #39 + ' + apiName +');
  Lines.Add('                    ' + #39 + ': non-zero code: ' + #39 + ' + JSON.stringify(respObj));');
  Lines.Add('                fail += 1;');
  Lines.Add('            }');
  Lines.Add('        } catch (e) {');
  Lines.Add('            console.error(' + #39 + '  ' + #39 + ' + apiName + ' + #39 + ': FAILED: ' + #39 + ' +');
  Lines.Add('                (e && e.message || e));');
  Lines.Add('            fail += 1;');
  Lines.Add('        } finally {');
  Lines.Add('            if (resp) { try { resp.dispose(); } catch (_) {} }');
  Lines.Add('            if (req) { try { req.dispose(); } catch (_) {} }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    try { app.dispose(); } catch (_) {}');
  Lines.Add('');
  Lines.Add('    console.log(' + #39#39 + ');');
  Lines.Add('    console.log(' + #39 + '=== Smoke test summary ===' + #39 + ');');
  Lines.Add('    console.log(' + #39 + 'Passed: ' + #39 + ' + ok);');
  Lines.Add('    console.log(' + #39 + 'Failed: ' + #39 + ' + fail);');
  Lines.Add('    return fail === 0 ? 0 : 1;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitJsExports(Lines: TPascalStringList);
begin
  Lines.Add('module.exports = {');
  Lines.Add('    HTTP_SERVICE_APP_NAME: HTTP_SERVICE_APP_NAME,');
  Lines.Add('    HTTP_SERVICE_APP_DESC: HTTP_SERVICE_APP_DESC,');
  Lines.Add('    HTTP_SERVICE_ENDPOINT: HTTP_SERVICE_ENDPOINT,');
  Lines.Add('    get DEBUG_LOG() { return DEBUG_LOG; },');
  Lines.Add('    set DEBUG_LOG(v) { DEBUG_LOG = Boolean(v); },');
  Lines.Add('    createAndRegisterHttpJsonApp: createAndRegisterHttpJsonApp,');
  Lines.Add('    registerAllHttpJsonApis: registerAllHttpJsonApis,');
  Lines.Add('    main: main,');
  Lines.Add('    runSmokeTest: runSmokeTest');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('if (require.main === module) {');
  Lines.Add('    if (process.argv.indexOf(' + #39 + '--smoke' + #39 + ') !== -1) {');
  Lines.Add('        process.exit(runSmokeTest());');
  Lines.Add('    } else {');
  Lines.Add('        const rc = main();');
  Lines.Add('        if (rc !== 0) {');
  Lines.Add('            process.exit(rc);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceNodejsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceNodejsCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceNodejsCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitJsHeader(Lines, AppName, Endpoint);
    EmitJsHelpers(Lines);
    EmitJsStubs(Lines, SupportedFuncs, ApiNames);
    EmitJsRegistration(Lines, SupportedFuncs, ApiNames);
    EmitJsMain(Lines, Endpoint);
    EmitJsSmokeTest(Lines, SupportedFuncs, ApiNames);
    EmitJsExports(Lines);

    Result := Lines;
    Log(PFormat('Generated Node.js service module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'nodejs', 'Node.js HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service_node.js', False,
    @GenerateHTTPServiceNodejsCode);
end.
