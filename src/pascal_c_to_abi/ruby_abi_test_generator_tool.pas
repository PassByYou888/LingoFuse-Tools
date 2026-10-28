unit ruby_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestRubyCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestRubyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[ruby_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[ruby_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('longint') or T.Same('int64') or
    T.Same('cardinal') or T.Same('dword') or T.Same('longword') or
    T.Same('word') or T.Same('smallint') or T.Same('byte') or
    T.Same('uint64') or T.Same('double') or T.Same('single') or
    T.Same('extended') or T.Same('real') or IsStringABIType(T);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsRubyKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('alias') or S.Same('and') or S.Same('begin') or S.Same('break') or
    S.Same('case') or S.Same('class') or S.Same('def') or S.Same('do') or
    S.Same('else') or S.Same('elsif') or S.Same('end') or S.Same('ensure') or
    S.Same('false') or S.Same('for') or S.Same('if') or S.Same('in') or
    S.Same('module') or S.Same('next') or S.Same('nil') or S.Same('not') or
    S.Same('or') or S.Same('redo') or S.Same('rescue') or S.Same('retry') or
    S.Same('return') or S.Same('self') or S.Same('super') or S.Same('then') or
    S.Same('true') or S.Same('undef') or S.Same('unless') or S.Same('until') or
    S.Same('when') or S.Same('while') or S.Same('yield');
end;

function MakeSafeRubyIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsRubyKeyword(Result) then
    Result := Result + '_';

  if Result.Same('uid') or Result.Same('p2p_name') or Result.Same('input') or
     Result.Same('output') or Result.Same('param') or Result.Same('target') or
     Result.Same('result') or Result.Same('status') or Result.Same('msg') or
     Result.Same('handle') or Result.Same('resp') or Result.Same('raw') or
     Result.Same('app') or Result.Same('tramp') or Result.Same('issue') or
     Result.Same('deserialize') or Result.Same('ref_addr') or Result.Same('result_addr') then
    Result := Result + '_param';
end;

function RubyNeedsDoubleQuote(const S: TP_String): boolean;
var
  i: integer;
  c: TP_Char;
begin
  Result := False;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if (c < #32) or (c = #127) then
      Exit(True);
  end;
end;

function RubyStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if RubyNeedsDoubleQuote(S) then
  begin
    Result := '"';
    for i := 1 to S.Len do
    begin
      c := S[i];
      if c = '"' then
      begin
        Result.Append('\');
        Result.Append('"');
      end
      else if c = '\' then
      begin
        Result.Append('\');
        Result.Append('\');
      end
      else if c = #10 then
      begin
        Result.Append('\');
        Result.Append('n');
      end
      else if c = #13 then
      begin
        Result.Append('\');
        Result.Append('r');
      end
      else if c = #9 then
      begin
        Result.Append('\');
        Result.Append('t');
      end
      else if c = #0 then
      begin
        Result.Append('\');
        Result.Append('0');
      end
      else
        Result.Append(c);
    end;
    Result.Append('"');
  end
  else
  begin
    Result := #39;
    for i := 1 to S.Len do
    begin
      c := S[i];
      if c = #39 then
      begin
        Result.Append('\');
        Result.Append(#39);
      end
      else if c = '\' then
      begin
        Result.Append('\');
        Result.Append('\');
      end
      else
        Result.Append(c);
    end;
    Result.Append(#39);
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
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
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

function BuildPlaceholderArgsLiteral(const Params: TParamArray): TP_String;
var
  i: integer;
  T: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result.Append(', ');
    T := Params[i].PascalType;
    if IsStringABIType(T) then
      Result.Append(RubyStrLit('test'))
    else if T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real') then
      Result.Append('3.14')
    else
      Result.Append('42');
  end;
  Result.Append(']');
end;

procedure EmitServiceTestBody(Lines: TPascalStringList;
  const UnitName, NormalizedUnit, AppName, P2PName, Endpoint: TP_String);
begin
  Lines.Add('# frozen_string_literal: true');
  Lines.Add('');
  Lines.Add('require ' + RubyStrLit('lingofuse'));
  Lines.Add('require ' + RubyStrLit(NormalizedUnit + '_abi_service'));
  Lines.Add('');
  Lines.Add('module ' + NormalizedUnit + '_abi');
  Lines.Add('  module ServiceTest');
  Lines.Add('    DEFAULT_ENDPOINT = ' + RubyStrLit(Endpoint));
  Lines.Add('    DEFAULT_APP_NAME = ' + RubyStrLit(AppName));
  Lines.Add('    DEFAULT_P2P_NAME = ' + RubyStrLit(P2PName));
  Lines.Add('    WHOAMI_API = ' + RubyStrLit('LF_TEST_WHOAMI'));
  Lines.Add('    ASK_CALL_ME_API = ' + RubyStrLit('LF_TEST_ASK_SERVICE_CALL_ME'));
  Lines.Add('    REPORT_IDENTITY_API = ' + RubyStrLit('LF_TEST_REPORT_SERVICE_IDENTITY'));
  Lines.Add('    STATUS_OK = 0x00');
  Lines.Add('');
  Lines.Add('    module_function');
  Lines.Add('');
  Lines.Add('    def safe_addr(h)');
  Lines.Add('      r = h.raw');
  Lines.Add('      return nil if r.nil?');
  Lines.Add('      r.respond_to?(:to_i) ? r.to_i : r');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def cb_whoami(input, output)');
  Lines.Add('      uid = input.p2p_uid');
  Lines.Add('      uid = (0.chr * 32).b if uid.nil? || uid.bytesize != 32');
  Lines.Add('      p2p_name = input.p2p_name || ' + #39 + #39);
  Lines.Add('      puts "[SERVICE] whoami: p2p=#{p2p_name}"');
  Lines.Add('      output.write_uint8(STATUS_OK)');
  Lines.Add('      output.write_bytes(uid)');
  Lines.Add('      output.write_string(p2p_name)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def cb_ask_call_me(input)');
  Lines.Add('      uid = input.p2p_uid');
  Lines.Add('      if uid.nil? || uid.bytesize != 32');
  Lines.Add('        puts ' + RubyStrLit('[SERVICE] ask_call_me: no uid in input'));
  Lines.Add('        return');
  Lines.Add('      end');
  Lines.Add('      puts ' + RubyStrLit('[SERVICE] ask_call_me: calling client via uid'));
  Lines.Add('      param = LingoFuse::DataHandle.new(REPORT_IDENTITY_API)');
  Lines.Add('      begin');
  Lines.Add('        param.write_string(' + RubyStrLit('service initiates call') + ')');
  Lines.Add('        param.position = 0');
  Lines.Add('        raw = LingoFuse::Native.lf_uid_call(uid, safe_addr(param), 5000)');
  Lines.Add('        if raw.nil?');
  Lines.Add('          puts ' + RubyStrLit('[SERVICE] ask_call_me: uid call returned nil (timeout)'));
  Lines.Add('        else');
  Lines.Add('          resp = LingoFuse::DataHandle.from_raw(raw, true)');
  Lines.Add('          begin');
  Lines.Add('            puts ' + RubyStrLit('[SERVICE] ask_call_me: client responded ok'));
  Lines.Add('          ensure');
  Lines.Add('            resp.dispose');
  Lines.Add('          end');
  Lines.Add('        end');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def main');
  Lines.Add('      puts ' + RubyStrLit('=== ' + UnitName.Text + ' ABI service test ==='));
  Lines.Add('');
  Lines.Add('      LingoFuse::Options.set_opt_quiet(true)');
  Lines.Add('      LingoFuse::Options.set_opt_overlap_connection(true)');
  Lines.Add('      LingoFuse::Options.set_opt_wait_connection_ready_ok(false)');
  Lines.Add('');
  Lines.Add('      LingoFuse::NativeBridge.start if LingoFuse::NativeBridge.available?');
  Lines.Add('');
  Lines.Add('      LingoFuse::Framework.reset_prepare');
  Lines.Add('      LingoFuse::Framework.prepare_service(DEFAULT_ENDPOINT, DEFAULT_ENDPOINT)');
  Lines.Add('');
  Lines.Add('      app = Service.create_and_register_abi_app');
  Lines.Add('      app.register_call(WHOAMI_API, ' + RubyStrLit('service-side whoami helper') + ', &method(:cb_whoami))');
  Lines.Add('      app.register_notify(ASK_CALL_ME_API, ' + RubyStrLit('ask service to call back client') + ', &method(:cb_ask_call_me))');
  Lines.Add('');
  Lines.Add('      LingoFuse::Options.set_opt_p2p_name(DEFAULT_P2P_NAME)');
  Lines.Add('      Service.register_all_p2p_abi_apis');
  Lines.Add('      LingoFuse.register_p2p_call(WHOAMI_API, ' + RubyStrLit('service-side whoami helper') + ', &method(:cb_whoami))');
  Lines.Add('      LingoFuse.register_p2p_notify(ASK_CALL_ME_API, ' + RubyStrLit('ask service to call back client') + ', &method(:cb_ask_call_me))');
  Lines.Add('');
  Lines.Add('      LingoFuse::Framework.prepare_client(DEFAULT_ENDPOINT, app)');
  Lines.Add('      unless LingoFuse::Framework.prepare_done');
  Lines.Add('        puts ' + RubyStrLit('[FATAL] prepare_done returned false'));
  Lines.Add('        exit 1');
  Lines.Add('      end');
  Lines.Add('');
  Lines.Add('      puts "[OK] Service ready on #{DEFAULT_ENDPOINT}"');
  Lines.Add('      puts "[OK] App: #{DEFAULT_APP_NAME}"');
  Lines.Add('      puts "[OK] P2P: #{DEFAULT_P2P_NAME}"');
  Lines.Add('      puts ' + RubyStrLit('[OK] Press Enter to shut down'));
  Lines.Add('');
  Lines.Add('      $stdin.gets');
  Lines.Add('');
  Lines.Add('      app.dispose');
  Lines.Add('      LingoFuse::Framework.exit_main_thread');
  Lines.Add('      LingoFuse::Framework.shutdown');
  Lines.Add('      puts ' + RubyStrLit('[OK] Service shutdown complete'));
  Lines.Add('    end');
  Lines.Add('  end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add(NormalizedUnit + '_abi::ServiceTest.main');
  Lines.Add('');
end;

procedure EmitCallTestPrelude(Lines: TPascalStringList;
  const UnitName, NormalizedUnit, AppName, P2PName, Endpoint: TP_String);
begin
  Lines.Add('# frozen_string_literal: true');
  Lines.Add('');
  Lines.Add('require ' + RubyStrLit('lingofuse'));
  Lines.Add('require ' + RubyStrLit(NormalizedUnit + '_abi_call'));
  Lines.Add('');
  Lines.Add('module ' + NormalizedUnit + '_abi');
  Lines.Add('  module CallTest');
  Lines.Add('    DEFAULT_ENDPOINT = ' + RubyStrLit(Endpoint));
  Lines.Add('    DEFAULT_TARGET_APP = ' + RubyStrLit(AppName));
  Lines.Add('    DEFAULT_TARGET_P2P = ' + RubyStrLit(P2PName));
  Lines.Add('    CLIENT_APP_NAME = ' + RubyStrLit('LF_TEST_CLIENT_SELF'));
  Lines.Add('    WHOAMI_API = ' + RubyStrLit('LF_TEST_WHOAMI'));
  Lines.Add('    ASK_CALL_ME_API = ' + RubyStrLit('LF_TEST_ASK_SERVICE_CALL_ME'));
  Lines.Add('    REPORT_IDENTITY_API = ' + RubyStrLit('LF_TEST_REPORT_SERVICE_IDENTITY'));
  Lines.Add('    STATUS_OK = 0x00');
  Lines.Add('');
  Lines.Add('    STATE = {');
  Lines.Add('      pass: 0,');
  Lines.Add('      fail: 0,');
  Lines.Add('      skip: 0,');
  Lines.Add('      service_uid: nil,');
  Lines.Add('      service_p2p: ' + #39 + #39 + ',');
  Lines.Add('      service_called_me: false,');
  Lines.Add('      mutex: Mutex.new');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    module_function');
  Lines.Add('');
  Lines.Add('    def safe_addr(h)');
  Lines.Add('      r = h.raw');
  Lines.Add('      return nil if r.nil?');
  Lines.Add('      r.respond_to?(:to_i) ? r.to_i : r');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def report_pass(label, value_str = nil)');
  Lines.Add('      STATE[:mutex].synchronize { STATE[:pass] += 1 }');
  Lines.Add('      if value_str.nil?');
  Lines.Add('        puts "[PASS] #{label}"');
  Lines.Add('      else');
  Lines.Add('        puts "[PASS] #{label} = #{value_str}"');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def report_fail(label, reason)');
  Lines.Add('      STATE[:mutex].synchronize { STATE[:fail] += 1 }');
  Lines.Add('      puts "[FAIL] #{label} -- #{reason}"');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def report_skip(label, reason)');
  Lines.Add('      STATE[:mutex].synchronize { STATE[:skip] += 1 }');
  Lines.Add('      puts "[SKIP] #{label} -- #{reason}"');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def cb_report_service_identity(input, output)');
  Lines.Add('      uid = input.p2p_uid');
  Lines.Add('      p2p_name = input.p2p_name || ' + #39 + #39);
  Lines.Add('      STATE[:mutex].synchronize do');
  Lines.Add('        STATE[:service_uid] = uid');
  Lines.Add('        STATE[:service_p2p] = p2p_name');
  Lines.Add('        STATE[:service_called_me] = true');
  Lines.Add('      end');
  Lines.Add('      msg = ' + #39 + #39);
  Lines.Add('      begin');
  Lines.Add('        msg = input.read_string');
  Lines.Add('      rescue StandardError');
  Lines.Add('        msg = ' + #39 + #39);
  Lines.Add('      end');
  Lines.Add('      puts "[CLIENT] service called me: msg=#{msg}"');
  Lines.Add('      output.write_uint8(STATUS_OK)');
  Lines.Add('      output.write_string(' + RubyStrLit('identity received') + ')');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def probe_client_identity');
  Lines.Add('      param = LingoFuse::DataHandle.new(WHOAMI_API)');
  Lines.Add('      begin');
  Lines.Add('        param.write_string(' + #39 + #39 + ')');
  Lines.Add('        param.position = 0');
  Lines.Add('        raw = LingoFuse::Native.lf_call(DEFAULT_TARGET_APP, safe_addr(param), 10000)');
  Lines.Add('        return false if raw.nil?');
  Lines.Add('        resp = LingoFuse::DataHandle.from_raw(raw, true)');
  Lines.Add('        begin');
  Lines.Add('          return false if resp.size < 34');
  Lines.Add('          resp.position = 0');
  Lines.Add('          status = resp.read_uint8');
  Lines.Add('          return false unless status == STATUS_OK');
  Lines.Add('          uid_bytes = resp.read_bytes_exact(32)');
  Lines.Add('          p2p_name = resp.read_string');
  Lines.Add('          is_null = uid_bytes.bytes.all? { |b| b == 0 }');
  Lines.Add('          puts "[INFO] client uid  = #{uid_bytes.unpack1(' + RubyStrLit('H*') + ')}"');
  Lines.Add('          puts "[INFO] client p2p  = #{p2p_name}"');
  Lines.Add('          !is_null');
  Lines.Add('        ensure');
  Lines.Add('          resp.dispose');
  Lines.Add('        end');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def test_service_initiates_call');
  Lines.Add('      STATE[:mutex].synchronize do');
  Lines.Add('        STATE[:service_called_me] = false');
  Lines.Add('        STATE[:service_uid] = nil');
  Lines.Add('        STATE[:service_p2p] = ' + #39 + #39);
  Lines.Add('      end');
  Lines.Add('      param = LingoFuse::DataHandle.new(ASK_CALL_ME_API)');
  Lines.Add('      begin');
  Lines.Add('        param.write_string(REPORT_IDENTITY_API)');
  Lines.Add('        param.position = 0');
  Lines.Add('        LingoFuse::Native.lf_notify(DEFAULT_TARGET_APP, safe_addr(param))');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('      100.times do');
  Lines.Add('        called = STATE[:mutex].synchronize { STATE[:service_called_me] }');
  Lines.Add('        if called');
  Lines.Add('          uid = STATE[:mutex].synchronize { STATE[:service_uid] }');
  Lines.Add('          return false if uid.nil?');
  Lines.Add('          return true if uid.bytesize == 32 && !uid.bytes.all? { |b| b == 0 }');
  Lines.Add('          return false');
  Lines.Add('        end');
  Lines.Add('        sleep(0.1)');
  Lines.Add('      end');
  Lines.Add('      false');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    def wait_for_service');
  Lines.Add('      30.times do');
  Lines.Add('        return true if LingoFuse::Framework.check_api(DEFAULT_TARGET_APP, WHOAMI_API)');
  Lines.Add('        sleep(0.2)');
  Lines.Add('      end');
  Lines.Add('      false');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitFunctionTest(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgsLit: TP_String;
begin
  ArgsLit := BuildPlaceholderArgsLiteral(F.Params);

  Lines.Add('    def test_' + ApiName);
  Lines.Add('      args = ' + ArgsLit);
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        v = Call.' + ApiName + '(*args)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(app call)') + ', v.to_s)');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(app call)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        f = Call.' + ApiName + '_async(*args)');
  Lines.Add('        v = f.value(timeout_ms: 10000)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(app async)') + ', v.to_s)');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(app async)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        f = Call.' + ApiName + '_async_sequenced(*args)');
  Lines.Add('        v = f.value(timeout_ms: 10000)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(app async seq)') + ', v.to_s)');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(app async seq)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      uid = STATE[:mutex].synchronize { STATE[:service_uid] }');
  Lines.Add('      if uid');
  Lines.Add('        begin');
  Lines.Add('          v = Call.' + ApiName + '_uid_call(uid, *args)');
  Lines.Add('          report_pass(' + RubyStrLit(ApiName.Text + '(uid call)') + ', v.to_s)');
  Lines.Add('        rescue StandardError => e');
  Lines.Add('          report_fail(' + RubyStrLit(ApiName.Text + '(uid call)') + ', e.message)');
  Lines.Add('        end');
  Lines.Add('');
  Lines.Add('        begin');
  Lines.Add('          f = Call.' + ApiName + '_uid_async(uid, *args)');
  Lines.Add('          v = f.value(timeout_ms: 10000)');
  Lines.Add('          report_pass(' + RubyStrLit(ApiName.Text + '(uid async)') + ', v.to_s)');
  Lines.Add('        rescue StandardError => e');
  Lines.Add('          report_fail(' + RubyStrLit(ApiName.Text + '(uid async)') + ', e.message)');
  Lines.Add('        end');
  Lines.Add('');
  Lines.Add('        begin');
  Lines.Add('          f = Call.' + ApiName + '_uid_async_sequenced(uid, *args)');
  Lines.Add('          v = f.value(timeout_ms: 10000)');
  Lines.Add('          report_pass(' + RubyStrLit(ApiName.Text + '(uid async seq)') + ', v.to_s)');
  Lines.Add('        rescue StandardError => e');
  Lines.Add('          report_fail(' + RubyStrLit(ApiName.Text + '(uid async seq)') + ', e.message)');
  Lines.Add('        end');
  Lines.Add('      else');
  Lines.Add('        report_skip(' + RubyStrLit(ApiName.Text + '(uid call)') + ', ' + RubyStrLit('no service uid') + ')');
  Lines.Add('        report_skip(' + RubyStrLit(ApiName.Text + '(uid async)') + ', ' + RubyStrLit('no service uid') + ')');
  Lines.Add('        report_skip(' + RubyStrLit(ApiName.Text + '(uid async seq)') + ', ' + RubyStrLit('no service uid') + ')');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        v = Call.' + ApiName + '_p2pname_call(DEFAULT_TARGET_P2P, *args)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(p2pname call)') + ', v.to_s)');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(p2pname call)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        f = Call.' + ApiName + '_p2pname_async(DEFAULT_TARGET_P2P, *args)');
  Lines.Add('        v = f.value(timeout_ms: 10000)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(p2pname async)') + ', v.to_s)');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(p2pname async)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        f = Call.' + ApiName + '_p2pname_async_sequenced(DEFAULT_TARGET_P2P, *args)');
  Lines.Add('        v = f.value(timeout_ms: 10000)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(p2pname async seq)') + ', v.to_s)');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(p2pname async seq)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitProcedureTest(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgsLit: TP_String;
begin
  ArgsLit := BuildPlaceholderArgsLiteral(F.Params);

  Lines.Add('    def test_' + ApiName);
  Lines.Add('      args = ' + ArgsLit);
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        Call.' + ApiName + '(*args)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(app notify)') + ')');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(app notify)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        Call.' + ApiName + '_sequenced_notify(*args)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(app seq notify)') + ')');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(app seq notify)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      uid = STATE[:mutex].synchronize { STATE[:service_uid] }');
  Lines.Add('      if uid');
  Lines.Add('        begin');
  Lines.Add('          Call.' + ApiName + '_uid_notify(uid, *args)');
  Lines.Add('          report_pass(' + RubyStrLit(ApiName.Text + '(uid notify)') + ')');
  Lines.Add('        rescue StandardError => e');
  Lines.Add('          report_fail(' + RubyStrLit(ApiName.Text + '(uid notify)') + ', e.message)');
  Lines.Add('        end');
  Lines.Add('');
  Lines.Add('        begin');
  Lines.Add('          Call.' + ApiName + '_uid_sequenced_notify(uid, *args)');
  Lines.Add('          report_pass(' + RubyStrLit(ApiName.Text + '(uid seq notify)') + ')');
  Lines.Add('        rescue StandardError => e');
  Lines.Add('          report_fail(' + RubyStrLit(ApiName.Text + '(uid seq notify)') + ', e.message)');
  Lines.Add('        end');
  Lines.Add('      else');
  Lines.Add('        report_skip(' + RubyStrLit(ApiName.Text + '(uid notify)') + ', ' + RubyStrLit('no service uid') + ')');
  Lines.Add('        report_skip(' + RubyStrLit(ApiName.Text + '(uid seq notify)') + ', ' + RubyStrLit('no service uid') + ')');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        Call.' + ApiName + '_p2pname_notify(DEFAULT_TARGET_P2P, *args)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(p2pname notify)') + ')');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(p2pname notify)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('');

  Lines.Add('      begin');
  Lines.Add('        Call.' + ApiName + '_p2pname_sequenced_notify(DEFAULT_TARGET_P2P, *args)');
  Lines.Add('        report_pass(' + RubyStrLit(ApiName.Text + '(p2pname seq notify)') + ')');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        report_fail(' + RubyStrLit(ApiName.Text + '(p2pname seq notify)') + ', e.message)');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitCallTestTail(Lines: TPascalStringList;
  const UnitName: TP_String;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('    def main');
  Lines.Add('      puts ' + RubyStrLit('=== ' + UnitName.Text + ' ABI client test ==='));
  Lines.Add('');
  Lines.Add('      LingoFuse::Options.set_opt_quiet(true)');
  Lines.Add('      LingoFuse::Options.set_opt_overlap_connection(true)');
  Lines.Add('      LingoFuse::Options.set_opt_wait_connection_ready_ok(false)');
  Lines.Add('');
  Lines.Add('      LingoFuse::NativeBridge.start if LingoFuse::NativeBridge.available?');
  Lines.Add('');
  Lines.Add('      LingoFuse::Framework.reset_prepare');
  Lines.Add('      LingoFuse::Framework.prepare_service(DEFAULT_ENDPOINT, DEFAULT_ENDPOINT)');
  Lines.Add('');
  Lines.Add('      client_app = LingoFuse::AppHandle.new(CLIENT_APP_NAME, ' + RubyStrLit('client test app') + ')');
  Lines.Add('      client_app.register_call(REPORT_IDENTITY_API, ' + RubyStrLit('report service identity') + ', &method(:cb_report_service_identity))');
  Lines.Add('');
  Lines.Add('      LingoFuse::Framework.prepare_client(DEFAULT_ENDPOINT, client_app)');
  Lines.Add('      unless LingoFuse::Framework.prepare_done');
  Lines.Add('        puts ' + RubyStrLit('[FATAL] prepare_done returned false'));
  Lines.Add('        exit 1');
  Lines.Add('      end');
  Lines.Add('      puts ' + RubyStrLit('[READY] Client online'));
  Lines.Add('');
  Lines.Add('      if wait_for_service');
  Lines.Add('        puts ' + RubyStrLit('[OK] target service is online'));
  Lines.Add('      else');
  Lines.Add('        puts ' + RubyStrLit('[WARN] target service is not visible on the mesh'));
  Lines.Add('      end');
  Lines.Add('');
  Lines.Add('      if probe_client_identity');
  Lines.Add('        puts ' + RubyStrLit('[OK] client identity probe'));
  Lines.Add('      else');
  Lines.Add('        puts ' + RubyStrLit('[WARN] whoami failed; uid tests will be skipped'));
  Lines.Add('      end');
  Lines.Add('');
  Lines.Add('      if test_service_initiates_call');
  Lines.Add('        puts ' + RubyStrLit('[OK] service-initiated call'));
  Lines.Add('        uid = STATE[:mutex].synchronize { STATE[:service_uid] }');
  Lines.Add('        p2p = STATE[:mutex].synchronize { STATE[:service_p2p] }');
  Lines.Add('        puts "[INFO] service uid = #{uid.unpack1(' + RubyStrLit('H*') + ')}" if uid');
  Lines.Add('        puts "[INFO] service p2p = #{p2p}"');
  Lines.Add('      else');
  Lines.Add('        report_fail(' + RubyStrLit('service-initiated call') + ', ' + RubyStrLit('timeout or no uid') + ')');
  Lines.Add('      end');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
    Lines.Add('      test_' + ApiNames[i]);

  Lines.Add('');
  Lines.Add('      pass = STATE[:mutex].synchronize { STATE[:pass] }');
  Lines.Add('      fail = STATE[:mutex].synchronize { STATE[:fail] }');
  Lines.Add('      skip = STATE[:mutex].synchronize { STATE[:skip] }');
  Lines.Add('      puts ' + #39 + #39);
  Lines.Add('      puts ' + RubyStrLit('=== Summary ==='));
  Lines.Add('      puts "Pass: #{pass}"');
  Lines.Add('      puts "Fail: #{fail}"');
  Lines.Add('      puts "Skip: #{skip}"');
  Lines.Add('');
  Lines.Add('      client_app.dispose');
  Lines.Add('      LingoFuse::Framework.exit_main_thread');
  Lines.Add('      LingoFuse::Framework.shutdown');
  Lines.Add('');
  Lines.Add('      fail.zero? ? exit(0) : exit(2)');
  Lines.Add('    end');
  Lines.Add('  end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add(UnitName.ReplaceChar(#32#9'./\@', '_') + '_abi::CallTest.main');
  Lines.Add('');
end;

function GenerateABIServiceTestRubyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, P2PName, Endpoint: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestRubyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestRubyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + AppName;

  Log(PFormat('Generating Ruby ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    EmitServiceTestBody(Lines, UnitName, NormalizedUnit, AppName, P2PName, Endpoint);
    Result := Lines;
    Log(PFormat('Generated %d lines for Ruby ABI service test', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateABICallTestRubyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList;
  UnitName, NormalizedUnit, AppName, P2PName, Endpoint: TP_String;
  F: TFunctionStructure;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestRubyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestRubyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  Endpoint := 'ipc:' + AppName;

  Log(PFormat('Generating Ruby ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call test exercises %d ABI APIs', [Length(SupportedFuncs)]));

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if ApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while ApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      ApiNames.Add(ApiName);
    end;

    EmitCallTestPrelude(Lines, UnitName, NormalizedUnit, AppName, P2PName, Endpoint);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        EmitFunctionTest(Lines, ApiNames[i], F)
      else
        EmitProcedureTest(Lines, ApiNames[i], F);
    end;

    EmitCallTestTail(Lines, UnitName, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines for Ruby ABI call test', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'ruby',
    'xxx_abi_service_test.rb',
    gkTest,
    'Ruby ABI service test program',
    @GenerateABIServiceTestRubyCode);

  RegisterGenerator(
    'ruby',
    'xxx_abi_call_test.rb',
    gkTest,
    'Ruby ABI call test program',
    @GenerateABICallTestRubyCode);

end.
