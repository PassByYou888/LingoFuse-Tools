unit http_julia_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceJuliaTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallJuliaTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_julia_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_julia_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification
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

// Default literal used as a test argument in the SYNC call test.
function ABI_Type_To_Julia_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := 'Int64(0)'
  else
    Result := 'nothing';
end;

// Default literal used inside the SMOKE test's JSON request envelope.
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

function MakeSafeJuliaIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('abstract') or Result.Same('baremodule') or
    Result.Same('begin') or Result.Same('break') or Result.Same('catch') or
    Result.Same('const') or Result.Same('continue') or Result.Same('do') or
    Result.Same('else') or Result.Same('elseif') or Result.Same('end') or
    Result.Same('export') or Result.Same('false') or Result.Same('finally') or
    Result.Same('for') or Result.Same('function') or Result.Same('global') or
    Result.Same('if') or Result.Same('import') or Result.Same('in') or
    Result.Same('let') or Result.Same('local') or Result.Same('macro') or
    Result.Same('module') or Result.Same('quote') or Result.Same('return') or
    Result.Same('struct') or Result.Same('true') or Result.Same('try') or
    Result.Same('using') or Result.Same('while') then
    Result := Result + '_';
end;

function JuliaStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      '"':  Result.Append('\"');
      #92:  Result.Append('\\');
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
  Result.Append('"');
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

// ============================================================================
// SERVICE-SIDE TEST PROGRAM GENERATOR
// ============================================================================
//
// The generated service test program has two modes:
//
//   * Default:   starts the service and blocks until SIGINT.
//   * --smoke:   in-process LocalCall self-tests. No mesh, no bridge.
//
// Both modes are wrapped in a try/finally that starts and stops the
// LingoFuse consumer, because the C shim routes every callback through
// it. Without a running consumer, an unfilled stub would block forever.
//
// The --smoke mode exercises every exposed API through App.local_call,
// which invokes the registered handler synchronously on the calling
// thread. It verifies JSON request parsing, stub dispatch, and JSON
// response serialization. It does NOT exercise the transport layer.

function GenerateHTTPServiceJuliaTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i,j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, ServiceFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, RequestJson, ArgList: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceJuliaTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceJuliaTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := NormalizedUnit + 'HttpJsonService';
  ServiceFileName := NormalizedUnit + '_http_json_service.jl';
  TestFileName := NormalizedUnit + '_http_json_service_main_test___.jl';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // ---------------------------------------------------------------
    // File header
    // ---------------------------------------------------------------
    Lines.Add('# ' + TestFileName.Text);
    Lines.Add('#');
    Lines.Add('# Auto-generated by http_julia_abi_test_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Service-side test program for the Julia HTTP/JSON service.');
    Lines.Add('#');
    Lines.Add('# Modes:');
    Lines.Add('#   (default)   Start the service and block until SIGINT.');
    Lines.Add('#   --smoke     In-process LocalCall self-tests. No LingoFuse mesh,');
    Lines.Add('#               no bridge.py, no network.');
    Lines.Add('#');
    Lines.Add('# The --smoke mode exercises every exposed API through');
    Lines.Add('# App.local_call, which invokes the registered handler');
    Lines.Add('# synchronously on the calling thread. It verifies the JSON');
    Lines.Add('# request parsing, the stub dispatch, and the JSON response');
    Lines.Add('# serialization. It does NOT exercise the transport layer.');
    Lines.Add('#');
    Lines.Add('# Usage:');
    Lines.Add('#   julia --threads=2 ' + TestFileName.Text);
    Lines.Add('#   julia --threads=2 ' + TestFileName.Text + ' --smoke');
    Lines.Add('#');
    Lines.Add('# Prerequisite: this file must sit next to ' + ServiceFileName.Text + '.');
    Lines.Add('');
    Lines.Add('using LingoFuse');
    Lines.Add('import JSON3');
    Lines.Add('import LingoFuse: App, DataHandle, local_call, write_string!,');
    Lines.Add('                 read_string!, set_cursor_position!, dispose!,');
    Lines.Add('                 start_callback_consumer, stop_callback_consumer');
    Lines.Add('');
    Lines.Add('const _SERVICE_FILE = joinpath(@__DIR__, ' + JuliaStrLit(ServiceFileName).Text + ')');
    Lines.Add('if !isfile(_SERVICE_FILE)');
    Lines.Add('    println(stderr, "FATAL: missing ", _SERVICE_FILE)');
    Lines.Add('    println(stderr, "Place this test next to the generated service module.")');
    Lines.Add('    exit(1)');
    Lines.Add('end');
    Lines.Add('include(_SERVICE_FILE)');
    Lines.Add('');
    Lines.Add('import .' + ModuleName.Text);
    Lines.Add('');
    Lines.Add('const _SMOKE_CASES = [');
    Lines.Add('# each entry is (api_name, request_json)');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];

      if Length(F.Params) = 0 then
        RequestJson := '{}'
      else
      begin
        ArgList := '';
        for j := 0 to High(F.Params) do
        begin
          if j > 0 then
            ArgList := ArgList + ', ';
          ArgList := ArgList + ABI_Type_To_Json_Default_Literal(F.Params[j].PascalType);
        end;
        RequestJson := '{"args": [' + ArgList + ']}';
      end;

      Lines.Add('    (' + JuliaStrLit(ApiName).Text + ', ' +
        JuliaStrLit(RequestJson).Text + '),');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('    # (no supported routines)');

    Lines.Add(']');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function _response_is_ok(text::String)::Bool');
    Lines.Add('    if isempty(text)');
    Lines.Add('        return false');
    Lines.Add('    end');
    Lines.Add('    try');
    Lines.Add('        obj = JSON3.read(text, Dict{String,Any})');
    Lines.Add('    catch');
    Lines.Add('        return false');
    Lines.Add('    end');
    Lines.Add('    return get(obj, "code", -1) == 0');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function _smoke_call(app::App, api_name::String, request_json::String)::String');
    Lines.Add('    req = DataHandle(api_name)');
    Lines.Add('    try');
    Lines.Add('        write_string!(req, request_json)');
    Lines.Add('        resp = local_call(app, req)');
    Lines.Add('        try');
    Lines.Add('            set_cursor_position!(resp, 0)');
    Lines.Add('            return read_string!(resp)');
    Lines.Add('        finally');
    Lines.Add('            dispose!(resp)');
    Lines.Add('        end');
    Lines.Add('    finally');
    Lines.Add('        dispose!(req)');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function run_smoke()::Int32');
    Lines.Add('    println("[smoke] running in-process LocalCall self-tests")');
    Lines.Add('    println("[smoke] this mode does NOT start the LingoFuse mesh and does NOT need the bridge")');
    Lines.Add('    println()');
    Lines.Add('');
    Lines.Add('    start_callback_consumer()');
    Lines.Add('    app = nothing');
    Lines.Add('    try');
    Lines.Add('        app = App(' + ModuleName.Text + '.HTTP_SERVICE_APP_NAME,');
    Lines.Add('                   ' + ModuleName.Text + '.HTTP_SERVICE_APP_DESC)');
    Lines.Add('        ' + ModuleName.Text + '.register_all_http_json_apis(app)');
    Lines.Add('');
    Lines.Add('        ok = 0');
    Lines.Add('        fail = 0');
    Lines.Add('        for (api_name, request_json) in _SMOKE_CASES');
    Lines.Add('            try');
    Lines.Add('                resp_text = _smoke_call(app, api_name, request_json)');
    Lines.Add('                if _response_is_ok(resp_text)');
    Lines.Add('                    println("  ", api_name, ": OK")');
    Lines.Add('                    ok += 1');
    Lines.Add('                else');
    Lines.Add('                    println(stderr, "  ", api_name, ": non-zero code: ", resp_text)');
    Lines.Add('                    fail += 1');
    Lines.Add('                end');
    Lines.Add('            catch e');
    Lines.Add('                println(stderr, "  ", api_name, ": FAILED: ", e)');
    Lines.Add('                fail += 1');
    Lines.Add('            end');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        println()');
    Lines.Add('        println("=== Smoke test summary ===")');
    Lines.Add('        println("Passed: ", ok)');
    Lines.Add('        println("Failed: ", fail)');
    Lines.Add('        return fail == 0 ? Int32(0) : Int32(1)');
    Lines.Add('    finally');
    Lines.Add('        if app !== nothing');
    Lines.Add('            dispose!(app)');
    Lines.Add('        end');
    Lines.Add('        stop_callback_consumer()');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function main()::Int32');
    Lines.Add('    if Threads.nthreads() < 2');
    Lines.Add('        println(stderr, "FATAL: --threads=2 or more required")');
    Lines.Add('        return Int32(1)');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    if "--smoke" in ARGS');
    Lines.Add('        return run_smoke()');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    # Default mode: start the service and block until SIGINT.');
    Lines.Add('    # The generated service main() performs its own startup sequence.');
    Lines.Add('    # Start the consumer here so that the C shim has a consumer');
    Lines.Add('    # even if the generated main() does not start one.');
    Lines.Add('    start_callback_consumer()');
    Lines.Add('    try');
    Lines.Add('        return ' + ModuleName.Text + '.main()');
    Lines.Add('    finally');
    Lines.Add('        stop_callback_consumer()');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if abspath(PROGRAM_FILE) == @__FILE__');
    Lines.Add('    exit(main())');
    Lines.Add('end');

    Result := Lines;
    Log(PFormat('Generated Julia service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// ============================================================================
// CALL-SIDE TEST PROGRAM GENERATOR
// ============================================================================
//
// The call-side test program issues BOTH the sync and the async variant
// for every supported API. Sync tests are blocking; async tests submit
// a task and fetch it immediately, so the output stays readable.
//
// Requires bridge.py AND the service to be running, and Julia launched
// with --threads=2 (both the consumer and each async test's own task
// need a non-main thread).

function GenerateHTTPCallJuliaTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i,j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, CallFileName, TestFileName: TP_String;
  DefaultBaseUrl, DefaultEndpoint: TP_String;
  ApiNames: TPascalStringList;
  ApiName, DefaultArgs: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallJuliaTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallJuliaTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := NormalizedUnit + 'HttpJsonCall';
  CallFileName := NormalizedUnit + '_http_json_call.jl';
  TestFileName := NormalizedUnit + '_http_json_call_main_test___.jl';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  DefaultEndpoint := 'ipc:' + NormalizedUnit + '_http_json';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('# ' + TestFileName.Text);
    Lines.Add('#');
    Lines.Add('# Auto-generated by http_julia_abi_test_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Call-side test program for the Julia HTTP/JSON call wrapper.');
    Lines.Add('#');
    Lines.Add('# Prepares LingoFuse as a pure consumer, then issues BOTH the');
    Lines.Add('# sync and the async variant for every supported API. Sync');
    Lines.Add('# tests are blocking; async tests submit a task and fetch it');
    Lines.Add('# immediately. Prints OK / FAILED per call and a summary.');
    Lines.Add('#');
    Lines.Add('# Prerequisites:');
    Lines.Add('#   * Julia launched with --threads=2 or more');
    Lines.Add('#   * bridge.py running on the same LingoFuse endpoint');
    Lines.Add('#   * the matching service running on the same endpoint');
    Lines.Add('#');
    Lines.Add('# Usage:');
    Lines.Add('#   julia --threads=2 ' + TestFileName.Text);
    Lines.Add('#   julia --threads=2 ' + TestFileName.Text + ' <base_url> <endpoint>');
    Lines.Add('#');
    Lines.Add('# Defaults:');
    Lines.Add('#   base_url = ' + JuliaStrLit(DefaultBaseUrl).Text);
    Lines.Add('#   endpoint = ' + JuliaStrLit(DefaultEndpoint).Text);
    Lines.Add('');
    Lines.Add('using LingoFuse');
    Lines.Add('import JSON3');
    Lines.Add('import LingoFuse: reset_prepare, prepare_client, prepare_done,');
    Lines.Add('                 set_option, start_callback_consumer,');
    Lines.Add('                 stop_callback_consumer, check_api');
    Lines.Add('');
    Lines.Add('const _CALL_FILE = joinpath(@__DIR__, ' + JuliaStrLit(CallFileName).Text + ')');
    Lines.Add('const _DEFAULT_BASE_URL = ' + JuliaStrLit(DefaultBaseUrl).Text);
    Lines.Add('const _DEFAULT_ENDPOINT = ' + JuliaStrLit(DefaultEndpoint).Text);
    Lines.Add('if !isfile(_CALL_FILE)');
    Lines.Add('    println(stderr, "FATAL: missing ", _CALL_FILE)');
    Lines.Add('    println(stderr, "Place this test next to the generated call module.")');
    Lines.Add('    exit(1)');
    Lines.Add('end');
    Lines.Add('include(_CALL_FILE)');
    Lines.Add('');
    Lines.Add('import .' + ModuleName.Text);
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function _prepare_lingofuse(endpoint::String)::Bool');
    Lines.Add('    try');
    Lines.Add('        set_option("Wait_Connection_ReadyOk", "True")');
    Lines.Add('        set_option("Overlap_Connection", "True")');
    Lines.Add('        reset_prepare()');
    Lines.Add('        ret = prepare_client(endpoint, nothing)');
    Lines.Add('        if ret == -1');
    Lines.Add('            println(stderr, "[FATAL] prepare_client returned -1 for endpoint: ", endpoint)');
    Lines.Add('            return false');
    Lines.Add('        end');
    Lines.Add('        if prepare_done() != 1');
    Lines.Add('            println(stderr, "[FATAL] prepare_done failed")');
    Lines.Add('            return false');
    Lines.Add('        end');
    Lines.Add('        return true');
    Lines.Add('    catch e');
    Lines.Add('        println(stderr, "[FATAL] LingoFuse init failed: ", e)');
    Lines.Add('        return false');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function run_tests()::Int32');
    Lines.Add('    ok = 0');
    Lines.Add('    fail = 0');
    Lines.Add('');

    // ---- Per-API sync + async test blocks ----
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];

      if Length(F.Params) = 0 then
        DefaultArgs := ''
      else
      begin
        DefaultArgs := '';
        for j := 0 to High(F.Params) do
        begin
          if j > 0 then
            DefaultArgs := DefaultArgs + ', ';
          DefaultArgs := DefaultArgs + ABI_Type_To_Julia_Default_Literal(F.Params[j].PascalType);
        end;
      end;

      // ---- Sync block ----
      Lines.Add('    print("  ' + ApiName.Text + ' [sync] : ")');
      Lines.Add('    flush(stdout)');
      Lines.Add('    try');
      Lines.Add('        ' + ModuleName.Text + '.' + ApiName.Text + '(' + DefaultArgs + ')');
      Lines.Add('        println("OK")');
      Lines.Add('        ok += 1');
      Lines.Add('    catch e');
      Lines.Add('        println(stderr, "FAILED: ", e)');
      Lines.Add('        fail += 1');
      Lines.Add('    end');
      Lines.Add('');

      // ---- Async block ----
      Lines.Add('    print("  ' + ApiName.Text + ' [async]: ")');
      Lines.Add('    flush(stdout)');
      Lines.Add('    try');
      Lines.Add('        task = ' + ModuleName.Text + '.' + ApiName.Text + '_async(' + DefaultArgs + ')');
      Lines.Add('        fetch(task)');
      Lines.Add('        println("OK")');
      Lines.Add('        ok += 1');
      Lines.Add('    catch e');
      Lines.Add('        println(stderr, "FAILED: ", e)');
      Lines.Add('        fail += 1');
      Lines.Add('    end');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    println("no routines to test")');
      Lines.Add('');
    end;

    Lines.Add('    println()');
    Lines.Add('    println("=== Summary ===")');
    Lines.Add('    println("Passed: ", ok)');
    Lines.Add('    println("Failed: ", fail)');
    Lines.Add('    return fail == 0 ? Int32(0) : Int32(1)');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function main()::Int32');
    Lines.Add('    if Threads.nthreads() < 2');
    Lines.Add('        println(stderr, "FATAL: --threads=2 or more required")');
    Lines.Add('        return Int32(1)');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    base_url = length(ARGS) >= 1 ? ARGS[1] : _DEFAULT_BASE_URL');
    Lines.Add('    endpoint = length(ARGS) >= 2 ? ARGS[2] : _DEFAULT_ENDPOINT');
    Lines.Add('');
    Lines.Add('    println("=== ' + UnitName.Text + ' HTTP/JSON call test ===")');
    Lines.Add('    println()');
    Lines.Add('    println("Base URL: ", base_url)');
    Lines.Add('    println("Endpoint: ", endpoint)');
    Lines.Add('    println()');
    Lines.Add('');
    Lines.Add('    start_callback_consumer()');
    Lines.Add('    try');
    Lines.Add('        if !_prepare_lingofuse(endpoint)');
    Lines.Add('            return Int32(1)');
    Lines.Add('        end');
    Lines.Add('        ' + ModuleName.Text + '.HTTP_CALL_BASE_URL = base_url');
    Lines.Add('        return run_tests()');
    Lines.Add('    finally');
    Lines.Add('        stop_callback_consumer()');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if abspath(PROGRAM_FILE) == @__FILE__');
    Lines.Add('    exit(main())');
    Lines.Add('end');

    Result := Lines;
    Log(PFormat('Generated Julia call test program: %d lines, %d routines (sync + async).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'julia', 'Julia HTTP/JSON service test program',
    asService, akTestCode,
    '_http_json_service_main_test___.jl', False,
    @GenerateHTTPServiceJuliaTestCode);
  RegisterCodeGenEntry(
    'julia', 'Julia HTTP/JSON call test program',
    asCall, akTestCode,
    '_http_json_call_main_test___.jl', False,
    @GenerateHTTPCallJuliaTestCode);
end.
