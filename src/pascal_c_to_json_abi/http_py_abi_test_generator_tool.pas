unit http_py_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServicePythonTestCode - generate the service-side test
// program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServicePythonTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallPythonTestCode - generate the call-side test program.
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPCallPythonTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_py_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_py_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification (mirrors the call/service generators)
// -----------------------------------------------------------------------------

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

// ABI_Type_To_Py_Default_Literal - default value used as a sync test
// argument. Matches the type annotation of the generated call function.
function ABI_Type_To_Py_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'None';
end;

// ABI_Type_To_Json_Default_Literal - default value used inside the
// service-side smoke test's JSON request envelope.
function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
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

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafePyIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('False') or Result.Same('None') or Result.Same('True') or
    Result.Same('and') or Result.Same('as') or Result.Same('assert') or
    Result.Same('async') or Result.Same('await') or Result.Same('break') or
    Result.Same('class') or Result.Same('continue') or Result.Same('def') or
    Result.Same('del') or Result.Same('elif') or Result.Same('else') or
    Result.Same('except') or Result.Same('finally') or Result.Same('for') or
    Result.Same('from') or Result.Same('global') or Result.Same('if') or
    Result.Same('import') or Result.Same('in') or Result.Same('is') or
    Result.Same('lambda') or Result.Same('nonlocal') or Result.Same('not') or
    Result.Same('or') or Result.Same('pass') or Result.Same('raise') or
    Result.Same('return') or Result.Same('try') or Result.Same('while') or
    Result.Same('with') or Result.Same('yield') then
    Result := Result + '_';
end;

// PyStrLit - produce a complete Python string literal (single quoted,
// with the surrounding quotes included).
function PyStrLit(const S: TP_String): TP_String;
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

function UniqueName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while Used.IndexOf(Base + '_' + umlIntToStr(i).Text) >= 0 do
    Inc(i);
  Result := Base + '_' + umlIntToStr(i).Text;
end;

// -----------------------------------------------------------------------------
// Markdown helpers
// -----------------------------------------------------------------------------

function MdCellEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '|' then
      Result.Append('\|')
    else if c = #10 then
      Result.Append(' ')
    else if c = #13 then
      // skip
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// -----------------------------------------------------------------------------
// Comment description extraction
// -----------------------------------------------------------------------------

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
          // Skip Doxygen tag lines.
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

// -----------------------------------------------------------------------------
// Parameter helpers
// -----------------------------------------------------------------------------

// BuildPyArgList - "a, b, c" for a parameter list.
function BuildPyArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildPyDefaultArgList - `0, 0.0, ""` for a parameter list.
function BuildPyDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Py_Default_Literal(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
end;

// BuildJsonArgsBody - the body of the "args": [...] JSON array,
// WITHOUT the surrounding brackets. Empty for a parameterless routine.
function BuildJsonArgsBody(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Json_Default_Literal(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
end;

// BuildSmokeJsonRequest - the JSON request envelope used by the
// service-side smoke test. A routine with no parameters gets "{}",
// which is equivalent to "call with default arguments". A routine
// with parameters gets '{"args": [...]}' with per-type defaults.
function BuildSmokeJsonRequest(const Params: TParamArray): TP_String;
begin
  if Length(Params) = 0 then
    Result := '{}'
  else
    Result := '{"args": [' + BuildJsonArgsBody(Params) + ']}';
end;

// -----------------------------------------------------------------------------
// Supported-function filtering
// -----------------------------------------------------------------------------

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

// BuildDisambiguatedApiNames - apply the same overload-suffix logic
// every other generator uses, so the tests reference exactly the
// names the generated service / call modules export.
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

// =============================================================================
// SERVICE-SIDE TEST PROGRAM GENERATOR
// =============================================================================
//
// The service-side test program does NOT duplicate the service's
// startup sequence. In default mode it delegates to the service
// module's own `main()`. In `--smoke` mode it drives App.local_call
// directly, bypassing the LingoFuse mesh entirely, so the smoke test
// needs neither bridge.py nor a running service.

function GenerateHTTPServicePythonTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceModuleName, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, RequestJson: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServicePythonTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServicePythonTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceModuleName := NormalizedUnit + '_http_json_service';
  FileName := NormalizedUnit + '_http_json_service_main_test___.py';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('# -*- coding: utf-8 -*-');
    Lines.Add('"""');
    Lines.Add('Auto-generated by http_py_abi_test_generator_tool.pas.');
    Lines.Add('Source model unit: ' + UnitName.Text + '.');
    Lines.Add('Do not edit by hand unless you know what you are doing.');
    Lines.Add('');
    Lines.Add('Service-side test program for the Python HTTP/JSON service.');
    Lines.Add('');
    Lines.Add('Modes:');
    Lines.Add('    (default)   Start the service and block until SIGINT / SIGTERM.');
    Lines.Add('    --smoke     In-process LocalCall self-tests. No LingoFuse mesh,');
    Lines.Add('                no bridge.py, no network.');
    Lines.Add('');
    Lines.Add('The --smoke mode exercises every exposed API through');
    Lines.Add('App.local_call, which invokes the registered handler');
    Lines.Add('synchronously on the calling thread. It verifies the JSON');
    Lines.Add('request parsing, the stub dispatch, and the JSON response');
    Lines.Add('serialization. It does not exercise the transport layer.');
    Lines.Add('');
    Lines.Add('Usage:');
    Lines.Add('    python3 ' + FileName.Text);
    Lines.Add('    python3 ' + FileName.Text + ' --smoke');
    Lines.Add('');
    Lines.Add('Prerequisite: this file must sit next to ' + ServiceModuleName.Text + '.py,');
    Lines.Add('because the module is imported by name.');
    Lines.Add('"""');
    Lines.Add('');
    Lines.Add('import importlib');
    Lines.Add('import json');
    Lines.Add('import sys');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('_SERVICE_MODULE_NAME = ' + PyStrLit(ServiceModuleName).Text);
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _import_service():');
    Lines.Add('    return importlib.import_module(_SERVICE_MODULE_NAME)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _response_is_ok(text):');
    Lines.Add('    """Return True when the JSON text carries {"code": 0}."""');
    Lines.Add('    if not text:');
    Lines.Add('        return False');
    Lines.Add('    try:');
    Lines.Add('        obj = json.loads(text)');
    Lines.Add('    except (ValueError, TypeError):');
    Lines.Add('        return False');
    Lines.Add('    if not isinstance(obj, dict):');
    Lines.Add('        return False');
    Lines.Add('    return obj.get(''code'') == 0');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _smoke_call(app, api_name, request_json):');
    Lines.Add('    """');
    Lines.Add('    Invoke one API through App.local_call and return the response');
    Lines.Add('    text. The request is written as a NUL-terminated UTF-8 string,');
    Lines.Add('    matching what the generated service handlers expect.');
    Lines.Add('    """');
    Lines.Add('    from lingofuse.core import DataHandle');
    Lines.Add('    req = DataHandle(api_name)');
    Lines.Add('    try:');
    Lines.Add('        req.write_string(request_json)');
    Lines.Add('        resp = app.local_call(req)');
    Lines.Add('        try:');
    Lines.Add('            return resp.read_string()');
    Lines.Add('        finally:');
    Lines.Add('            resp.free()');
    Lines.Add('    finally:');
    Lines.Add('        req.free()');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def run_smoke(svc):');
    Lines.Add('    print(''[smoke] running in-process LocalCall self-tests'')');
    Lines.Add('    print(''[smoke] this mode does NOT start LingoFuse and does NOT need the bridge'')');
    Lines.Add('    print()');
    Lines.Add('');
    Lines.Add('    try:');
    Lines.Add('        app = svc.create_and_register_http_json_app()');
    Lines.Add('    except Exception as e:');
    Lines.Add('        print(''[smoke] failed to create App: %s'' % e, file=sys.stderr)');
    Lines.Add('        return 1');
    Lines.Add('    if app is None:');
    Lines.Add('        print(''[smoke] create_and_register_http_json_app returned None'',');
    Lines.Add('              file=sys.stderr)');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    ok = 0');
    Lines.Add('    fail = 0');
    Lines.Add('    try:');
    Lines.Add('        for api_name, request_json in SMOKE_CASES:');
    Lines.Add('            try:');
    Lines.Add('                resp_text = _smoke_call(app, api_name, request_json)');
    Lines.Add('                if _response_is_ok(resp_text):');
    Lines.Add('                    print(''  %s: OK'' % api_name)');
    Lines.Add('                    ok += 1');
    Lines.Add('                else:');
    Lines.Add('                    print(''  %s: non-zero code: %s''');
    Lines.Add('                          % (api_name, resp_text), file=sys.stderr)');
    Lines.Add('                    fail += 1');
    Lines.Add('            except Exception as e:');
    Lines.Add('                print(''  %s: FAILED: %s'' % (api_name, e),');
    Lines.Add('                      file=sys.stderr)');
    Lines.Add('                fail += 1');
    Lines.Add('    finally:');
    Lines.Add('        try:');
    Lines.Add('            app.free()');
    Lines.Add('        except Exception:');
    Lines.Add('            pass');
    Lines.Add('');
    Lines.Add('    print()');
    Lines.Add('    print(''=== Smoke test summary ==='')');
    Lines.Add('    print(''Passed: %d'' % ok)');
    Lines.Add('    print(''Failed: %d'' % fail)');
    Lines.Add('    return 0 if fail == 0 else 1');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def main():');
    Lines.Add('    svc = _import_service()');
    Lines.Add('    if ''--smoke'' in sys.argv[1:]:');
    Lines.Add('        return run_smoke(svc)');
    Lines.Add('    return svc.main()');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# Each entry is (api_name, request_json).');
    Lines.Add('# The request uses the "args" positional form. APIs with no');
    Lines.Add('# parameters send "{}", which the generated handler interprets');
    Lines.Add('# as "call with default arguments".');
    Lines.Add('SMOKE_CASES = [');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      RequestJson := BuildSmokeJsonRequest(F.Params);
      Lines.Add('    (' + PyStrLit(ApiName).Text + ', ' + PyStrLit(RequestJson).Text + '),');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('    # (no supported routines)');

    Lines.Add(']');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if __name__ == ''__main__'':');
    Lines.Add('    sys.exit(main())');

    Result := Lines;
    Log(PFormat('Generated service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// CALL-SIDE TEST PROGRAM GENERATOR
// =============================================================================
//
// The call-side test program exercises every supported routine TWICE:
// once through the synchronous variant and once through the async
// variant. Both variants share a single LingoFuse consumer
// connection; the async variants run under ONE asyncio.run(...) so
// that all coroutine tests share one event loop.

function GenerateHTTPCallPythonTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, CallModuleName, DefaultBaseUrl, DefaultEndpoint, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, DefaultArgs: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  HasParams: boolean;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPythonTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPythonTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  CallModuleName := NormalizedUnit + '_http_json_call';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  DefaultEndpoint := 'ipc:' + NormalizedUnit + '_http_json';
  FileName := NormalizedUnit + '_http_json_call_main_test___.py';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('# -*- coding: utf-8 -*-');
    Lines.Add('"""');
    Lines.Add('Auto-generated by http_py_abi_test_generator_tool.pas.');
    Lines.Add('Source model unit: ' + UnitName.Text + '.');
    Lines.Add('Do not edit by hand unless you know what you are doing.');
    Lines.Add('');
    Lines.Add('Call-side test program for the Python HTTP/JSON call wrapper.');
    Lines.Add('');
    Lines.Add('Prepares LingoFuse as a pure consumer, then issues BOTH the');
    Lines.Add('sync and the async variant for every supported API. The sync');
    Lines.Add('variants run in the main thread; the async variants run under');
    Lines.Add('a SINGLE asyncio.run(...) so that all coroutine tests share');
    Lines.Add('one event loop. Prints OK / FAILED per call and a summary at');
    Lines.Add('the end.');
    Lines.Add('');
    Lines.Add('Prerequisites:');
    Lines.Add('    * bridge.py must be running on the same LingoFuse endpoint;');
    Lines.Add('    * the matching service must be running on the same endpoint.');
    Lines.Add('');
    Lines.Add('Usage:');
    Lines.Add('    python3 ' + FileName.Text);
    Lines.Add('    python3 ' + FileName.Text + ' <base_url> <endpoint>');
    Lines.Add('');
    Lines.Add('Defaults:');
    Lines.Add('    base_url = ' + PyStrLit(DefaultBaseUrl).Text);
    Lines.Add('    endpoint = ' + PyStrLit(DefaultEndpoint).Text);
    Lines.Add('');
    Lines.Add('Prerequisite: this file must sit next to ' + CallModuleName.Text + '.py,');
    Lines.Add('because the module is imported by name.');
    Lines.Add('"""');
    Lines.Add('');
    Lines.Add('import asyncio');
    Lines.Add('import importlib');
    Lines.Add('import sys');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('_CALL_MODULE_NAME = ' + PyStrLit(CallModuleName).Text);
    Lines.Add('_DEFAULT_BASE_URL = ' + PyStrLit(DefaultBaseUrl).Text);
    Lines.Add('_DEFAULT_ENDPOINT = ' + PyStrLit(DefaultEndpoint).Text);
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _import_call_module():');
    Lines.Add('    return importlib.import_module(_CALL_MODULE_NAME)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _prepare_lingofuse(endpoint):');
    Lines.Add('    """');
    Lines.Add('    Initialize LingoFuse as a pure consumer (no exposed App).');
    Lines.Add('    Returns True on success, False on any fatal error.');
    Lines.Add('    """');
    Lines.Add('    try:');
    Lines.Add('        import lingofuse');
    Lines.Add('        if hasattr(lingofuse, ''set_option''):');
    Lines.Add('            lingofuse.set_option(''Wait_Connection_ReadyOk'', ''True'')');
    Lines.Add('            lingofuse.set_option(''Overlap_Connection'', ''True'')');
    Lines.Add('    except Exception:');
    Lines.Add('        pass');
    Lines.Add('    try:');
    Lines.Add('        from lingofuse._lf_native import (');
    Lines.Add('            LF_ResetPrepare, LF_PrepareClient, LF_PrepareDone,');
    Lines.Add('        )');
    Lines.Add('        from lingofuse.lf_io import cstr');
    Lines.Add('        LF_ResetPrepare()');
    Lines.Add('        LF_PrepareClient(cstr(endpoint), None)');
    Lines.Add('        return LF_PrepareDone() == 1');
    Lines.Add('    except Exception as e:');
    Lines.Add('        print(''[FATAL] LingoFuse init failed: %s'' % e, file=sys.stderr)');
    Lines.Add('        return False');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _shutdown_lingofuse():');
    Lines.Add('    try:');
    Lines.Add('        from lingofuse._lf_native import LF_ExitMainThread, LF_Shutdown');
    Lines.Add('        try:');
    Lines.Add('            LF_ExitMainThread()');
    Lines.Add('        except Exception:');
    Lines.Add('            pass');
    Lines.Add('        try:');
    Lines.Add('            LF_Shutdown()');
    Lines.Add('        except Exception:');
    Lines.Add('            pass');
    Lines.Add('    except Exception:');
    Lines.Add('        pass');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def _run_all_sync(call_module, results):');
    Lines.Add('    """');
    Lines.Add('    Run every sync test in the main thread. Each entry of');
    Lines.Add('    SYNC_TESTS is (api_name, fn); fn is called with the call');
    Lines.Add('    module as its only argument.');
    Lines.Add('    """');
    Lines.Add('    for api_name, fn in SYNC_TESTS:');
    Lines.Add('        try:');
    Lines.Add('            fn(call_module)');
    Lines.Add('            print(''  %s [sync] : OK'' % api_name)');
    Lines.Add('            results.append(True)');
    Lines.Add('        except Exception as e:');
    Lines.Add('            print(''  %s [sync] : FAILED: %s'' % (api_name, e),');
    Lines.Add('                  file=sys.stderr)');
    Lines.Add('            results.append(False)');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('async def _run_all_async(call_module, results):');
    Lines.Add('    """');
    Lines.Add('    Run every async test under a SINGLE event loop. Each entry of');
    Lines.Add('    ASYNC_TESTS is (api_name, coro_fn); coro_fn is awaited with');
    Lines.Add('    the call module as its only argument.');
    Lines.Add('    """');
    Lines.Add('    for api_name, coro_fn in ASYNC_TESTS:');
    Lines.Add('        try:');
    Lines.Add('            await coro_fn(call_module)');
    Lines.Add('            print(''  %s [async]: OK'' % api_name)');
    Lines.Add('            results.append(True)');
    Lines.Add('        except Exception as e:');
    Lines.Add('            print(''  %s [async]: FAILED: %s'' % (api_name, e),');
    Lines.Add('                  file=sys.stderr)');
    Lines.Add('            results.append(False)');
    Lines.Add('');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Per-API sync + async test helpers
    // -------------------------------------------------------------------------
    Lines.Add('# Each helper invokes one API with default arguments. The sync');
    Lines.Add('# helpers are plain functions; the async helpers are coroutines.');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildPyDefaultArgList(F.Params);

      Lines.Add('def _test_' + ApiName.Text + '_sync(call_module):');
      Lines.Add('    call_module.' + ApiName.Text + '(' + DefaultArgs.Text + ')');
      Lines.Add('');
      Lines.Add('');
      Lines.Add('async def _test_' + ApiName.Text + '_async(call_module):');
      Lines.Add('    await call_module.' + ApiName.Text + '_async(' + DefaultArgs.Text + ')');
      Lines.Add('');
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // Test lists
    // -------------------------------------------------------------------------
    Lines.Add('SYNC_TESTS = [');
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Lines.Add('    (' + PyStrLit(ApiName).Text + ', _test_' + ApiName.Text + '_sync),');
    end;
    if Length(SupportedFuncs) = 0 then
      Lines.Add('    # (no supported routines)');
    Lines.Add(']');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('ASYNC_TESTS = [');
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Lines.Add('    (' + PyStrLit(ApiName).Text + ', _test_' + ApiName.Text + '_async),');
    end;
    if Length(SupportedFuncs) = 0 then
      Lines.Add('    # (no supported routines)');
    Lines.Add(']');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('def main():');
    Lines.Add('    call_module = _import_call_module()');
    Lines.Add('');
    Lines.Add('    base_url = sys.argv[1] if len(sys.argv) >= 2 else _DEFAULT_BASE_URL');
    Lines.Add('    endpoint = sys.argv[2] if len(sys.argv) >= 3 else _DEFAULT_ENDPOINT');
    Lines.Add('');
    Lines.Add('    print(''=== ' + UnitName.Text + ' HTTP/JSON call test ==='')');
    Lines.Add('    print()');
    Lines.Add('    print(''Base URL: %s'' % base_url)');
    Lines.Add('    print(''Endpoint: %s'' % endpoint)');
    Lines.Add('    print()');
    Lines.Add('');
    Lines.Add('    if not _prepare_lingofuse(endpoint):');
    Lines.Add('        print(''[FATAL] LingoFuse init failed'', file=sys.stderr)');
    Lines.Add('        return 1');
    Lines.Add('');
    Lines.Add('    call_module.HTTP_CALL_BASE_URL = base_url');
    Lines.Add('');
    Lines.Add('    results = []');
    Lines.Add('    try:');
    Lines.Add('        _run_all_sync(call_module, results)');
    Lines.Add('        asyncio.run(_run_all_async(call_module, results))');
    Lines.Add('    finally:');
    Lines.Add('        _shutdown_lingofuse()');
    Lines.Add('');
    Lines.Add('    ok = sum(1 for r in results if r)');
    Lines.Add('    fail = sum(1 for r in results if not r)');
    Lines.Add('');
    Lines.Add('    print()');
    Lines.Add('    print(''=== Summary ==='')');
    Lines.Add('    print(''Passed: %d'' % ok)');
    Lines.Add('    print(''Failed: %d'' % fail)');
    Lines.Add('    return 0 if fail == 0 else 1');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if __name__ == ''__main__'':');
    Lines.Add('    sys.exit(main())');

    Result := Lines;
    Log(PFormat('Generated call test program: %d lines, %d routines (sync + async).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'python', 'Python HTTP/JSON service test program',
    asService, akTestCode,
    '_http_json_service_main_test___.py', False,
    @GenerateHTTPServicePythonTestCode);
  RegisterCodeGenEntry(
    'python', 'Python HTTP/JSON call test program',
    asCall, akTestCode,
    '_http_json_call_main_test___.py', False,
    @GenerateHTTPCallPythonTestCode);
end.
