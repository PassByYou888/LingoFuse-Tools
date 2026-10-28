unit R_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib,
  Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestRCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestRCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[R_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[R_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function RStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append(#92);
      Result.Append(#39);
    end
    else if c = #92 then
    begin
      Result.Append(#92);
      Result.Append(#92);
    end
    else if c = #10 then
    begin
      Result.Append(#92);
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append(#92);
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append(#92);
      Result.Append('t');
    end
    else
      Result.Append(c);
  end;
  Result.Append(#39);
end;

function RStrLitNL(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append(#92);
      Result.Append(#39);
    end
    else if c = #92 then
    begin
      Result.Append(#92);
      Result.Append(#92);
    end
    else if c = #10 then
    begin
      Result.Append(#92);
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append(#92);
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append(#92);
      Result.Append('t');
    end
    else
      Result.Append(c);
  end;
  Result.Append(#92);
  Result.Append('n');
  Result.Append(#39);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function IsInt64ABIType(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
end;

function ABI_Type_To_R_Pack_Fn(const T: TP_String): TP_String;
begin
  if T.Same('shortint') then Result := 'abi_pack_int8'
  else if T.Same('smallint') then Result := 'abi_pack_int16'
  else if T.Same('integer') or T.Same('longint') then Result := 'abi_pack_int32'
  else if T.Same('int64') then Result := 'abi_pack_int64'
  else if T.Same('byte') then Result := 'abi_pack_uint8'
  else if T.Same('word') then Result := 'abi_pack_uint16'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'abi_pack_uint32'
  else if T.Same('uint64') then Result := 'abi_pack_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'abi_pack_double'
  else if T.Same('single') then Result := 'abi_pack_single'
  else if IsStringABIType(T) then Result := 'abi_pack_string'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_R_Pack_Fn(T) <> '';
end;

function PlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := RStrLit('test')
  else if ABIType.Same('double') or ABIType.Same('single')
    or ABIType.Same('extended') or ABIType.Same('real') then
    Result := '3.14'
  else if IsInt64ABIType(ABIType) then
    Result := 'bit64::as.integer64(' + RStrLit('42') + ')'
  else
    Result := '42L';
end;

function BuildTestArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + PlaceholderValue(Params[i].PascalType);
  end;
end;

function FunctionNeedsBit64(const F: TFunctionStructure): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to High(F.Params) do
    if IsInt64ABIType(F.Params[i].PascalType) then
    begin
      Result := True;
      Exit;
    end;
  if F.IsFunction and IsInt64ABIType(F.ReturnType) then
    Result := True;
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
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
      Supported := False;
    if Supported and (f.Name.Len = 0) then
      Supported := False;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

procedure AssignUniqueApiNames(const Funcs: TArryFunctionStructure; Names: TPascalStringList);
var
  i, j: integer;
  N: TP_String;
begin
  Names.Clear;
  for i := 0 to High(Funcs) do
  begin
    N := MakeApiName(Funcs[i].Name);
    if Names.IndexOf(N.Text) >= 0 then
    begin
      j := 1;
      while Names.IndexOf(N.Text + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      N := N + '_' + umlIntToStr(j).Text;
    end;
    Names.Add(N.Text);
  end;
end;

procedure EmitRuntimeBootstrap(Lines: TPascalStringList);
begin
  Lines.Add('get_script_dir <- function() {');
  Lines.Add('  args <- commandArgs(trailingOnly = FALSE)');
  Lines.Add('  file_arg <- grep(' + RStrLit('^--file=') + ', args, value = TRUE)');
  Lines.Add('  if (length(file_arg) > 0) {');
  Lines.Add('    return(dirname(normalizePath(sub(' + RStrLit('^--file=') + ', ' + RStrLit('') + ', file_arg[1]))))');
  Lines.Add('  }');
  Lines.Add('  return(getwd())');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('find_runtime <- function() {');
  Lines.Add('  env_dir <- Sys.getenv(' + RStrLit('LINGOFUSE_RUNTIME') + ', ' + RStrLit('') + ')');
  Lines.Add('  if (nzchar(env_dir) && dir.exists(env_dir)) {');
  Lines.Add('    return(normalizePath(env_dir))');
  Lines.Add('  }');
  Lines.Add('  script_dir <- get_script_dir()');
  Lines.Add('  candidates <- c(');
  Lines.Add('    file.path(script_dir, ' + RStrLit('Binary') + '),');
  Lines.Add('    file.path(script_dir, ' + RStrLit('..') + ', ' + RStrLit('Binary') + '),');
  Lines.Add('    file.path(script_dir, ' + RStrLit('..') + ', ' + RStrLit('..') + ', ' + RStrLit('Binary') + '),');
  Lines.Add('    file.path(script_dir, ' + RStrLit('runtime') + '),');
  Lines.Add('    file.path(script_dir, ' + RStrLit('..') + ', ' + RStrLit('runtime') + ')');
  Lines.Add('  )');
  Lines.Add('  for (c in candidates) {');
  Lines.Add('    if (dir.exists(c) && file.exists(file.path(c, ' + RStrLit('LingoFuse64.dll') + '))) {');
  Lines.Add('      return(normalizePath(c))');
  Lines.Add('    }');
  Lines.Add('  }');
  Lines.Add('  NULL');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('runtime_dir <- find_runtime()');
  Lines.Add('if (is.null(runtime_dir)) {');
  Lines.Add('  stop(' + RStrLit('LingoFuse runtime not found. Set LINGOFUSE_RUNTIME or place LingoFuse64.dll nearby.') + ')');
  Lines.Add('}');
  Lines.Add('lf_load(runtime_dir)');
  Lines.Add('if (!isTRUE(lf_is_loaded())) {');
  Lines.Add('  stop(' + RStrLit('lf_load failed; check the runtime directory contents.') + ')');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitTestHeader(Lines: TPascalStringList);
begin
  Lines.Add('library(lingofuse)');
  Lines.Add('');
end;

procedure EmitServiceTestMain(Lines: TPascalStringList;
  const UnitName, AppName: TP_String);
begin
  Lines.Add('script_dir <- get_script_dir()');
  Lines.Add('source(file.path(script_dir, ' + RStrLit(UnitName + '_abi_service.R') + '))');
  Lines.Add('');
  Lines.Add('lf_set_opt_quiet(TRUE)');
  Lines.Add('lf_set_opt_console_output(TRUE)');
  Lines.Add('');
  Lines.Add('p2p_group_name <- ' + RStrLit(UnitName + '_service_test_p2p'));
  Lines.Add('lf_set_opt_p2p_name(p2p_group_name)');
  Lines.Add('');
  Lines.Add('endpoint <- sprintf(' + RStrLit('ipc:%s') + ', DEFAULT_APP_NAME)');
  Lines.Add('lf_prepare_service(endpoint, endpoint)');
  Lines.Add('');
  Lines.Add('service_app <- lf_create_app(DEFAULT_APP_NAME, DEFAULT_APP_DESC)');
  Lines.Add('if (is.null(service_app)) {');
  Lines.Add('  stop(' + RStrLit('lf_create_app returned NULL') + ')');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('register_all_abi_apis(service_app)');
  Lines.Add('register_all_p2p_abi_apis()');
  Lines.Add('');
  Lines.Add('abi_test_whoami_callback <- function(input_raw, ctx) {');
  Lines.Add('  tryCatch({');
  Lines.Add('    uid <- ctx$sender_uid');
  Lines.Add('    p2p <- ctx$sender_p2p_name');
  Lines.Add('    if (is.null(uid) || length(uid) != 32L) uid <- as.raw(rep(0L, 32L))');
  Lines.Add('    if (is.null(p2p) || is.na(p2p)) p2p <- ' + RStrLit('') );
  Lines.Add('    c(STATUS_OK, uid, charToRaw(enc2utf8(p2p)), as.raw(0L))');
  Lines.Add('  }, error = function(e) {');
  Lines.Add('    abi_write_error(conditionMessage(e))');
  Lines.Add('  })');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('abi_test_ask_call_me_callback <- function(input_raw, ctx) {');
  Lines.Add('  tryCatch({');
  Lines.Add('    cat(' + RStrLitNL('[SERVICE] ask_call_me: scheduling async call to client') + ')');
  Lines.Add('    lf_async_call(');
  Lines.Add('      ' + RStrLit('LF_TEST_CLIENT_SELF') + ',');
  Lines.Add('      ' + RStrLit('LF_TEST_REPORT_SERVICE_IDENTITY') + ',');
  Lines.Add('      ' + RStrLit('service initiates call') + ',');
  Lines.Add('      on_success = function(result, user_data) {');
  Lines.Add('        cat(sprintf(' + RStrLitNL('[SERVICE] ask_call_me: client responded: %s') + ', result))');
  Lines.Add('      },');
  Lines.Add('      on_error = function(msg, kind, user_data) {');
  Lines.Add('        cat(sprintf(' + RStrLitNL('[SERVICE] ask_call_me: async failed (kind=%d): %s') + ', as.integer(kind), msg))');
  Lines.Add('      },');
  Lines.Add('      timeout_ms = 5000L');
  Lines.Add('    )');
  Lines.Add('  }, error = function(e) {');
  Lines.Add('    cat(sprintf(' + RStrLitNL('[SERVICE] ask_call_me: error: %s') + ', conditionMessage(e)))');
  Lines.Add('  })');
  Lines.Add('  invisible(NULL)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('lf_register_call(service_app, ' + RStrLit('LF_TEST_WHOAMI') + ', ' + RStrLit('whoami helper') + ', abi_test_whoami_callback, bin = TRUE, with_context = TRUE)');
  Lines.Add('lf_register_notify(service_app, ' + RStrLit('LF_TEST_ASK_SERVICE_CALL_ME') + ', ' + RStrLit('ask service to call back client') + ', abi_test_ask_call_me_callback, bin = TRUE, with_context = TRUE)');
  Lines.Add('');
  Lines.Add('lf_prepare_client(endpoint, service_app)');
  Lines.Add('');
  Lines.Add('if (lf_prepare_done() != 1) {');
  Lines.Add('  stop(' + RStrLit('lf_prepare_done failed') + ')');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('cat(' + RStrLitNL('[READY]') + ')');
  Lines.Add('cat(sprintf(' + RStrLitNL('Endpoint: %s') + ', endpoint))');
  Lines.Add('cat(sprintf(' + RStrLitNL('P2P name: %s') + ', p2p_group_name))');
  Lines.Add('flush.console()');
  Lines.Add('');
  Lines.Add('idle_timeout_sec <- as.numeric(Sys.getenv(' + RStrLit('ABI_SERVICE_TIMEOUT') + ', ' + RStrLit('30') + '))');
  Lines.Add('if (is.na(idle_timeout_sec) || idle_timeout_sec <= 0) idle_timeout_sec <- 30');
  Lines.Add('cat(sprintf(' + RStrLitNL('[INFO] idle timeout: %d seconds (resets on every request)') + ', idle_timeout_sec))');
  Lines.Add('last_activity <- Sys.time()');
  Lines.Add('while (TRUE) {');
  Lines.Add('  handled <- lf_poll(50)');
  Lines.Add('  if (isTRUE(handled)) {');
  Lines.Add('    last_activity <- Sys.time()');
  Lines.Add('  }');
  Lines.Add('  idle_sec <- as.numeric(difftime(Sys.time(), last_activity, units = ' + RStrLit('secs') + '))');
  Lines.Add('  if (idle_sec > idle_timeout_sec) break');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('cat(' + RStrLitNL('[DONE]') + ')');
  Lines.Add('');
  Lines.Add('lf_cleanup(service_app)');
  Lines.Add('');
end;

procedure EmitCallTestWait(Lines: TPascalStringList);
begin
  Lines.Add('lf_set_opt_quiet(TRUE)');
  Lines.Add('lf_set_opt_console_output(TRUE)');
  Lines.Add('');
  Lines.Add('endpoint <- sprintf(' + RStrLit('ipc:%s') + ', ABI_TARGET_APP)');
  Lines.Add('lf_prepare_client(endpoint, NULL)');
  Lines.Add('');
  Lines.Add('if (lf_prepare_done() != 1) {');
  Lines.Add('  stop(' + RStrLit('lf_prepare_done failed') + ')');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('wait_app <- function(app_name, timeout_ms = 20000L) {');
  Lines.Add('  t0 <- Sys.time()');
  Lines.Add('  while (as.numeric(difftime(Sys.time(), t0, units = ' + RStrLit('secs') + ')) * 1000 < timeout_ms) {');
  Lines.Add('    if (isTRUE(lf_check_app(app_name))) return(TRUE)');
  Lines.Add('    lf_poll(100)');
  Lines.Add('  }');
  Lines.Add('  FALSE');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (!wait_app(ABI_TARGET_APP)) {');
  Lines.Add('  cat(' + RStrLitNL('[FATAL] service not ready') + ')');
  Lines.Add('  lf_cleanup(NULL)');
  Lines.Add('  quit(status = 1L)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('cat(sprintf(' + RStrLitNL('=== %s ABI call test ===') + ', ABI_TARGET_APP))');
  Lines.Add('cat(sprintf(' + RStrLitNL('Endpoint: ipc:%s') + ', ABI_TARGET_APP))');
  Lines.Add('cat(' + RStrLitNL('') + ')');
  Lines.Add('');
  Lines.Add('pass <- 0L');
  Lines.Add('fail <- 0L');
  Lines.Add('skip <- 0L');
  Lines.Add('');
  Lines.Add('run_test <- function(label, fn) {');
  Lines.Add('  tryCatch({');
  Lines.Add('    result <- fn()');
  Lines.Add('    cat(sprintf(' + RStrLitNL('[PASS] %s') + ', label))');
  Lines.Add('    pass <<- pass + 1L');
  Lines.Add('  }, error = function(e) {');
  Lines.Add('    cat(sprintf(' + RStrLitNL('[FAIL] %s: %s') + ', label, conditionMessage(e)))');
  Lines.Add('    fail <<- fail + 1L');
  Lines.Add('  })');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('run_test_skip_if_no_bit64 <- function(label, fn) {');
  Lines.Add('  if (!requireNamespace(' + RStrLit('bit64') + ', quietly = TRUE)) {');
  Lines.Add('    cat(sprintf(' + RStrLitNL('[SKIP] %s -- bit64 not installed') + ', label))');
  Lines.Add('    skip <<- skip + 1L');
  Lines.Add('    return(invisible(NULL))');
  Lines.Add('  }');
  Lines.Add('  run_test(label, fn)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitTestBlock(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgList: TP_String;
  NeedsBit64: boolean;
begin
  NeedsBit64 := FunctionNeedsBit64(F);
  ArgList := BuildTestArgList(F.Params);

  if NeedsBit64 then
  begin
    Lines.Add('run_test_skip_if_no_bit64(' + RStrLit(ApiName) + ', function() {');
    if ArgList = '' then
      Lines.Add('  ' + ApiName + '()')
    else
      Lines.Add('  ' + ApiName + '(' + ArgList + ')');
    Lines.Add('})');
  end
  else
  begin
    Lines.Add('run_test(' + RStrLit(ApiName) + ', function() {');
    if ArgList = '' then
      Lines.Add('  ' + ApiName + '()')
    else
      Lines.Add('  ' + ApiName + '(' + ArgList + ')');
    Lines.Add('})');
  end;
  Lines.Add('');
end;

procedure EmitCallTestFooter(Lines: TPascalStringList);
begin
  Lines.Add('cat(' + RStrLitNL('') + ')');
  Lines.Add('cat(' + RStrLitNL('=== Summary ===') + ')');
  Lines.Add('cat(sprintf(' + RStrLitNL('Pass: %d') + ', pass))');
  Lines.Add('cat(sprintf(' + RStrLitNL('Fail: %d') + ', fail))');
  Lines.Add('cat(sprintf(' + RStrLitNL('Skip: %d') + ', skip))');
  Lines.Add('');
  Lines.Add('lf_cleanup(NULL)');
  Lines.Add('');
  Lines.Add('if (fail > 0L) quit(status = 2L)');
  Lines.Add('');
end;

function GenerateABIServiceTestRCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating R ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    EmitTestHeader(Lines);
    EmitRuntimeBootstrap(Lines);
    EmitServiceTestMain(Lines, NormalizedUnit, AppName);
    Result := Lines;
    Log(PFormat('Generated %d lines for the service test.', [Lines.Count]));
  finally
  end;
end;

function GenerateABICallTestRCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating R ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    AssignUniqueApiNames(SupportedFuncs, ApiNames);

    EmitTestHeader(Lines);
    EmitRuntimeBootstrap(Lines);
    Lines.Add('script_dir <- get_script_dir()');
    Lines.Add('source(file.path(script_dir, ' + RStrLit(UnitName + '_abi_call.R') + '))');
    Lines.Add('');
    EmitCallTestWait(Lines);

    for i := 0 to High(SupportedFuncs) do
      EmitTestBlock(Lines, ApiNames[i], SupportedFuncs[i]);

    EmitCallTestFooter(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test.', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'r',
    'xxx_abi_service_test.R',
    gkTest,
    'R ABI service test program',
    @GenerateABIServiceTestRCode);

  RegisterGenerator(
    'r',
    'xxx_abi_call_test.R',
    gkTest,
    'R ABI call test program',
    @GenerateABICallTestRCode);

end.
