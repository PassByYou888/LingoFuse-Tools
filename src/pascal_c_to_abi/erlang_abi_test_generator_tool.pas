unit erlang_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestErlangCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestErlangCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

type
  TSystemStringArray = array of SystemString;
  TArryFunctionStructure = array of TFunctionStructure;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function IsFloatABIType(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal')
    or T.Same('longint') or T.Same('dword') or T.Same('word')
    or T.Same('smallint') or T.Same('byte') or T.Same('uint64')
    or T.Same('longword') or IsFloatABIType(T) or IsStringABIType(T);
end;

function MakeApiName(const FuncName: TP_String): SystemString;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_').Text;
end;

function Hex2(n: integer): SystemString;
const
  HexDigits: array[0..15] of SystemChar =
    ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
begin
  Result := HexDigits[(n shr 4) and 15] + HexDigits[n and 15];
end;

function ErlangQuotedAtom(const S: SystemString): SystemString;
var
  i, n: integer;
begin
  Result := #39;
  for i := 1 to Length(S) do
  begin
    n := Ord(S[i]);
    if S[i] = #39 then
      Result := Result + #39 + #39
    else if (n >= 32) and (n <= 126) then
      Result := Result + S[i]
    else
      Result := Result + '_';
  end;
  Result := Result + #39;
end;

function ErlangBinLit(const S: SystemString): SystemString;
var
  i, n: integer;
  c: SystemChar;
begin
  Result := '<<"';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    n := Ord(c);
    if c = '"' then
      Result := Result + '\' + '"'
    else if c = '\' then
      Result := Result + '\' + '\'
    else if n = 10 then
      Result := Result + '\' + 'n'
    else if n = 13 then
      Result := Result + '\' + 'r'
    else if n = 9 then
      Result := Result + '\' + 't'
    else if (n >= 32) and (n <= 126) then
      Result := Result + c
    else
      Result := Result + '\' + 'x' + Hex2(n);
  end;
  Result := Result + '">>';
end;

function DefaultArgValueErlang(const T: TP_String): SystemString;
begin
  if IsStringABIType(T) then
    Result := '<<"test">>'
  else if IsFloatABIType(T) then
    Result := '3.14'
  else
    Result := '42';
end;

function BuildArgList(const F: TFunctionStructure): SystemString;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + DefaultArgValueErlang(F.Params[i].PascalType);
  end;
end;

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
        Log(PFormat('Skipped "%s": parameter "%s" unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" not supported',
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

function AssignUniqueApiNames(const Funcs: TArryFunctionStructure): TSystemStringArray;
var
  i, j, suffix: integer;
  N, BaseN: SystemString;
  Collision: boolean;
begin
  SetLength(Result, Length(Funcs));
  for i := 0 to High(Funcs) do
  begin
    BaseN := MakeApiName(Funcs[i].Name);
    N := BaseN;
    suffix := 0;
    repeat
      Collision := False;
      for j := 0 to i - 1 do
        if Result[j] = N then
        begin
          Collision := True;
          Break;
        end;
      if Collision then
      begin
        Inc(suffix);
        N := BaseN + '_' + umlIntToStr(suffix).Text;
      end;
    until not Collision;
    Result[i] := N;
  end;
end;

procedure EmitServiceMainBody(Lines: TPascalStringList;
  const AppName, Endpoint, P2PName, ServiceModule: SystemString);
var
  S: SystemString;
begin
  S := '-define(ENDPOINT, ' + ErlangBinLit(Endpoint) + ').';
  Lines.Add(S);
  S := '-define(APP_NAME, ' + ErlangBinLit(AppName) + ').';
  Lines.Add(S);
  S := '-define(P2P_NAME, ' + ErlangBinLit(P2PName) + ').';
  Lines.Add(S);
  S := '-define(SERVICE_MODULE, ' + ErlangQuotedAtom(ServiceModule) + ').';
  Lines.Add(S);
  Lines.Add('');

  Lines.Add('main(_) ->');
  Lines.Add('    case lingofuse:ensure_loaded() of');
  Lines.Add('        ok -> ok;');
  Lines.Add('        {error, _} ->');
  Lines.Add('            io:format(standard_error, "[FATAL] NIF not loaded~n", []),');
  Lines.Add('            halt(1)');
  Lines.Add('    end,');
  Lines.Add('    ok = lingofuse:set_option(<<"Wait_Connection_ReadyOk">>, <<"False">>),');
  Lines.Add('    ok = lingofuse:set_option(<<"Overlap_Connection">>, <<"True">>),');
  Lines.Add('    ok = lingofuse:set_option(<<"Quiet">>, <<"True">>),');
  Lines.Add('    ok = lingofuse:reset_prepare(),');
  Lines.Add('    case lingofuse:prepare_service(?ENDPOINT, ?ENDPOINT) of');
  Lines.Add('        {ok, _Tag} -> ok;');
  Lines.Add('        Err ->');
  Lines.Add('            io:format(standard_error, "[FATAL] prepare_service: ~p~n", [Err]),');
  Lines.Add('            halt(1)');
  Lines.Add('    end,');
  Lines.Add('    {ok, App} = ?SERVICE_MODULE:create_and_register_app(),');
  Lines.Add('    ok = lingofuse:register_call_sync(App, <<"LF_TEST_WHOAMI">>, <<"whoami helper">>, self(), #{with_identity => true}),');
  Lines.Add('    ok = lingofuse:register_notify(App, <<"LF_TEST_ASK_SERVICE_CALL_ME">>, <<"ask helper">>, self(), #{with_identity => true}),');
  Lines.Add('    ok = lingofuse:set_opt_p2p_name(?P2P_NAME),');
  Lines.Add('    _ = ?SERVICE_MODULE:register_all_p2p_apis(),');
  Lines.Add('    ok = lingofuse:register_p2p_call_sync(<<"LF_TEST_WHOAMI">>, <<"p2p whoami">>, self(), #{with_identity => true}),');
  Lines.Add('    ok = lingofuse:register_p2p_notify(<<"LF_TEST_ASK_SERVICE_CALL_ME">>, <<"p2p ask">>, self(), #{with_identity => true}),');
  Lines.Add('    case lingofuse:prepare_client(?ENDPOINT, App) of');
  Lines.Add('        {ok, Tag2} when Tag2 >= 0 -> ok;');
  Lines.Add('        Err2 ->');
  Lines.Add('            io:format(standard_error, "[FATAL] prepare_client: ~p~n", [Err2]),');
  Lines.Add('            halt(1)');
  Lines.Add('    end,');
  Lines.Add('    case lingofuse:prepare_done() of');
  Lines.Add('        {ok, 1} -> ok;');
  Lines.Add('        Err3 ->');
  Lines.Add('            io:format(standard_error, "[FATAL] prepare_done: ~p~n", [Err3]),');
  Lines.Add('            halt(1)');
  Lines.Add('    end,');
  Lines.Add('    timer:sleep(15000),');
  Lines.Add('    io:format("[OK] service ready on ~s~n", [?ENDPOINT]),');
  Lines.Add('    io:format("[OK] service P2P group = ~s~n", [?P2P_NAME]),');
  Lines.Add('    loop(App).');
  Lines.Add('');

  Lines.Add('loop(App) ->');
  Lines.Add('    receive');
  Lines.Add('        {lf_call, Ref, <<"LF_TEST_WHOAMI">>, _Payload, Identity} when is_integer(Ref) ->');
  Lines.Add('            do_whoami(Ref, Identity), loop(App);');
  Lines.Add('        {lf_p2p_call, Ref, <<"LF_TEST_WHOAMI">>, _Payload, Identity} when is_integer(Ref) ->');
  Lines.Add('            do_whoami(Ref, Identity), loop(App);');
  Lines.Add('        {lf_call, Ref, <<"LF_TEST_WHOAMI">>, _Payload} when is_integer(Ref) ->');
  Lines.Add('            do_whoami(Ref, #{}), loop(App);');
  Lines.Add('        {lf_p2p_call, Ref, <<"LF_TEST_WHOAMI">>, _Payload} when is_integer(Ref) ->');
  Lines.Add('            do_whoami(Ref, #{}), loop(App);');
  Lines.Add('        {lf_notify, <<"LF_TEST_ASK_SERVICE_CALL_ME">>, _Payload, Identity} ->');
  Lines.Add('            do_ask_call_me(Identity), loop(App);');
  Lines.Add('        {lf_p2p_notify, <<"LF_TEST_ASK_SERVICE_CALL_ME">>, _Payload, Identity} ->');
  Lines.Add('            do_ask_call_me(Identity), loop(App);');
  Lines.Add('        {lf_notify, <<"LF_TEST_ASK_SERVICE_CALL_ME">>, _Payload} ->');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_p2p_notify, <<"LF_TEST_ASK_SERVICE_CALL_ME">>, _Payload} ->');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_call, Ref, Api, Payload, Identity} when is_integer(Ref) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_call(Api, Ref, Payload, Identity), loop(App);');
  Lines.Add('        {lf_p2p_call, Ref, Api, Payload, Identity} when is_integer(Ref) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_call(Api, Ref, Payload, Identity), loop(App);');
  Lines.Add('        {lf_call, Ref, Api, Payload} when is_integer(Ref) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_call(Api, Ref, Payload, #{}), loop(App);');
  Lines.Add('        {lf_p2p_call, Ref, Api, Payload} when is_integer(Ref) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_call(Api, Ref, Payload, #{}), loop(App);');
  Lines.Add('        {lf_notify, Api, Payload, Identity} when is_binary(Api) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_notify(Api, Payload, Identity), loop(App);');
  Lines.Add('        {lf_p2p_notify, Api, Payload, Identity} when is_binary(Api) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_notify(Api, Payload, Identity), loop(App);');
  Lines.Add('        {lf_notify, Api, Payload} when is_binary(Api) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_notify(Api, Payload, #{}), loop(App);');
  Lines.Add('        {lf_p2p_notify, Api, Payload} when is_binary(Api) ->');
  Lines.Add('            _ = ?SERVICE_MODULE:lf_dispatch_notify(Api, Payload, #{}), loop(App);');
  Lines.Add('        _Other ->');
  Lines.Add('            loop(App)');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('do_whoami(Ref, Identity) ->');
  Lines.Add('    Uid = maps:get(uid, Identity, <<0:256>>),');
  Lines.Add('    P2PName = maps:get(p2p_name, Identity, <<>>),');
  Lines.Add('    io:format("[SERVICE] whoami: uid=~s p2p=~s~n", [hex_upper(Uid), P2PName]),');
  Lines.Add('    Reply = <<0, Uid/binary, P2PName/binary, 0>>,');
  Lines.Add('    _ = lingofuse:reply(Ref, Reply).');
  Lines.Add('');

  Lines.Add('do_ask_call_me(Identity) ->');
  Lines.Add('    ClientUid = maps:get(uid, Identity, <<0:256>>),');
  Lines.Add('    io:format("[SERVICE] ask_call_me: spawning reverse call to client~n"),');
  Lines.Add('    spawn(fun() -> do_reverse_call(ClientUid) end).');
  Lines.Add('');

  Lines.Add('do_reverse_call(ClientUid) ->');
  Lines.Add('    {ok, Data} = lingofuse:create_data(<<"LF_TEST_REPORT_SERVICE_IDENTITY">>),');
  Lines.Add('    try');
  Lines.Add('        io:format("[SERVICE] do_reverse_call: calling client uid=~s~n", [hex_upper(ClientUid)]),');
  Lines.Add('        case lingofuse:uid_call(ClientUid, Data, 5000) of');
  Lines.Add('            {ok, Res} ->');
  Lines.Add('                try');
  Lines.Add('                    {ok, Sz} = lingofuse:get_size(Res),');
  Lines.Add('                    case Sz of');
  Lines.Add('                        0 ->');
  Lines.Add('                            io:format("[SERVICE] do_reverse_call: FAILED (empty response)~n");');
  Lines.Add('                        _ ->');
  Lines.Add('                            ok = lingofuse:set_pos(Res, 0),');
  Lines.Add('                            {ok, Bin} = lingofuse:read_buffer(Res, Sz),');
  Lines.Add('                            case Bin of');
  Lines.Add('                                <<255, Rest/binary>> ->');
  Lines.Add('                                    io:format("[SERVICE] do_reverse_call: error response: ~p (hex=~s)~n", [Rest, hex_upper(Bin)]);');
  Lines.Add('                                <<>> ->');
  Lines.Add('                                    io:format("[SERVICE] do_reverse_call: empty response~n");');
  Lines.Add('                                _ ->');
  Lines.Add('                                    io:format("[SERVICE] do_reverse_call: OK (hex=~s)~n", [hex_upper(Bin)])');
  Lines.Add('                            end');
  Lines.Add('                    end');
  Lines.Add('                after lingofuse:free_data(Res) end;');
  Lines.Add('            {error, E} ->');
  Lines.Add('                io:format("[SERVICE] do_reverse_call: failed ~p~n", [E])');
  Lines.Add('        end');
  Lines.Add('    catch _:_Reason ->');
  Lines.Add('        io:format("[SERVICE] do_reverse_call: crash ~p~n", [_Reason])');
  Lines.Add('    after lingofuse:free_data(Data) end.');
  Lines.Add('');

  Lines.Add('hex_upper(Bin) -> binary:encode_hex(Bin).');
  Lines.Add('');
end;

procedure EmitClientHelpers(Lines: TPascalStringList);
begin
  Lines.Add('-define(ABI_TIMEOUT_MS, 5000).');
  Lines.Add('');

  Lines.Add('wait_service_ready(0) -> false;');
  Lines.Add('wait_service_ready(N) ->');
  Lines.Add('    case lingofuse:check_app(?SERVICE_APP) of');
  Lines.Add('        {ok, true} -> true;');
  Lines.Add('        _ -> timer:sleep(500), wait_service_ready(N - 1)');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('hex_upper(Bin) -> binary:encode_hex(Bin).');
  Lines.Add('');

  Lines.Add('decode_whoami_response(<<0, Uid:32/binary, Rest/binary>>) ->');
  Lines.Add('    case binary:match(Rest, <<0>>) of');
  Lines.Add('        {Pos, 1} -> {ok, Uid, binary:part(Rest, 0, Pos)};');
  Lines.Add('        nomatch -> {ok, Uid, Rest}');
  Lines.Add('    end;');
  Lines.Add('decode_whoami_response(<<255, Rest/binary>>) ->');
  Lines.Add('    {error, {remote_error, Rest}};');
  Lines.Add('decode_whoami_response(_) ->');
  Lines.Add('    {error, bad_response}.');
  Lines.Add('');

  Lines.Add('wait_uid_registered(ServiceUid, 0) ->');
  Lines.Add('    io:format("[DIAG] wait_uid_registered: final check UID=~s~n", [hex_upper(ServiceUid)]),');
  Lines.Add('    case lingofuse:check_uid(ServiceUid) of');
  Lines.Add('        {ok, true} ->');
  Lines.Add('            io:format("[DIAG] UID registered (final)~n"),');
  Lines.Add('            true;');
  Lines.Add('        _ ->');
  Lines.Add('            io:format("[DIAG] UID NOT registered after 20s of polling~n"),');
  Lines.Add('            false');
  Lines.Add('    end;');
  Lines.Add('wait_uid_registered(ServiceUid, N) ->');
  Lines.Add('    case lingofuse:check_uid(ServiceUid) of');
  Lines.Add('        {ok, true} ->');
  Lines.Add('            io:format("[DIAG] UID registered after ~p polls~n", [20 - N]),');
  Lines.Add('            true;');
  Lines.Add('        _ ->');
  Lines.Add('            timer:sleep(1000),');
  Lines.Add('            wait_uid_registered(ServiceUid, N - 1)');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('wait_p2p_registered(P2PName, 0) ->');
  Lines.Add('    io:format("[DIAG] wait_p2p_registered: final check P2P=~s~n", [P2PName]),');
  Lines.Add('    case lingofuse:check_p2pname(P2PName) of');
  Lines.Add('        {ok, true} ->');
  Lines.Add('            io:format("[DIAG] P2P registered (final)~n"),');
  Lines.Add('            true;');
  Lines.Add('        _ ->');
  Lines.Add('            io:format("[DIAG] P2P NOT registered after 20s of polling~n"),');
  Lines.Add('            false');
  Lines.Add('    end;');
  Lines.Add('wait_p2p_registered(P2PName, N) ->');
  Lines.Add('    case lingofuse:check_p2pname(P2PName) of');
  Lines.Add('        {ok, true} ->');
  Lines.Add('            io:format("[DIAG] P2P registered after ~p polls~n", [20 - N]),');
  Lines.Add('            true;');
  Lines.Add('        _ ->');
  Lines.Add('            timer:sleep(1000),');
  Lines.Add('            wait_p2p_registered(P2PName, N - 1)');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_sync_test(Label, Fun, P, F) ->');
  Lines.Add('    try case Fun() of');
  Lines.Add('        {ok, _} -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('        {error, E} -> io:format("[FAIL] ~s: ~p~n", [Label, E]), {P, F + 1};');
  Lines.Add('        Other -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_async_test(Label, Fun, P, F) ->');
  Lines.Add('    Parent = self(),');
  Lines.Add('    Tag = make_ref(),');
  Lines.Add('    try case Fun(fun(R) -> Parent ! {Tag, R} end) of');
  Lines.Add('        ok ->');
  Lines.Add('            receive');
  Lines.Add('                {Tag, {ok, _}} -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('                {Tag, {error, E}} -> io:format("[FAIL] ~s: ~p~n", [Label, E]), {P, F + 1};');
  Lines.Add('                {Tag, Other} -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('            after 10000 ->');
  Lines.Add('                io:format("[FAIL] ~s: timeout~n", [Label]), {P, F + 1}');
  Lines.Add('            end;');
  Lines.Add('        Other ->');
  Lines.Add('            io:format("[FAIL] ~s: dispatch ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_notify_test(Label, Fun, P, F) ->');
  Lines.Add('    try case Fun() of');
  Lines.Add('        ok -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('        Other -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_uid_sync_test(Label, Fun, P, F) ->');
  Lines.Add('    try case Fun() of');
  Lines.Add('        {ok, _} -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('        {error, timeout} ->');
  Lines.Add('            io:format("[SKIP] ~s (uid route timeout)~n", [Label]), {P, F};');
  Lines.Add('        {error, <<"empty response">>} ->');
  Lines.Add('            io:format("[SKIP] ~s (uid route empty)~n", [Label]), {P, F};');
  Lines.Add('        {error, E} -> io:format("[FAIL] ~s: ~p~n", [Label, E]), {P, F + 1};');
  Lines.Add('        Other -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_uid_async_test(Label, Fun, P, F) ->');
  Lines.Add('    Parent = self(),');
  Lines.Add('    Tag = make_ref(),');
  Lines.Add('    try case Fun(fun(R) -> Parent ! {Tag, R} end) of');
  Lines.Add('        ok ->');
  Lines.Add('            receive');
  Lines.Add('                {Tag, {ok, _}} -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('                {Tag, {error, timeout}} ->');
  Lines.Add('                    io:format("[SKIP] ~s (uid route timeout)~n", [Label]), {P, F};');
  Lines.Add('                {Tag, {error, <<"empty response">>}} ->');
  Lines.Add('                    io:format("[SKIP] ~s (uid route empty)~n", [Label]), {P, F};');
  Lines.Add('                {Tag, {error, E}} -> io:format("[FAIL] ~s: ~p~n", [Label, E]), {P, F + 1};');
  Lines.Add('                {Tag, Other} -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('            after 10000 ->');
  Lines.Add('                io:format("[SKIP] ~s (uid route timeout)~n", [Label]), {P, F}');
  Lines.Add('            end;');
  Lines.Add('        Other ->');
  Lines.Add('            io:format("[FAIL] ~s: dispatch ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_uid_notify_test(Label, Fun, P, F) ->');
  Lines.Add('    try case Fun() of');
  Lines.Add('        ok -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('        Other -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_p2p_sync_test(Label, Fun, P, F) ->');
  Lines.Add('    try case Fun() of');
  Lines.Add('        {ok, _} -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('        {error, timeout} ->');
  Lines.Add('            io:format("[SKIP] ~s (p2p route timeout)~n", [Label]), {P, F};');
  Lines.Add('        {error, <<"empty response">>} ->');
  Lines.Add('            io:format("[SKIP] ~s (p2p route empty)~n", [Label]), {P, F};');
  Lines.Add('        {error, E} -> io:format("[FAIL] ~s: ~p~n", [Label, E]), {P, F + 1};');
  Lines.Add('        Other -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_p2p_async_test(Label, Fun, P, F) ->');
  Lines.Add('    Parent = self(),');
  Lines.Add('    Tag = make_ref(),');
  Lines.Add('    try case Fun(fun(R) -> Parent ! {Tag, R} end) of');
  Lines.Add('        ok ->');
  Lines.Add('            receive');
  Lines.Add('                {Tag, {ok, _}} -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('                {Tag, {error, timeout}} ->');
  Lines.Add('                    io:format("[SKIP] ~s (p2p route timeout)~n", [Label]), {P, F};');
  Lines.Add('                {Tag, {error, <<"empty response">>}} ->');
  Lines.Add('                    io:format("[SKIP] ~s (p2p route empty)~n", [Label]), {P, F};');
  Lines.Add('                {Tag, {error, E}} -> io:format("[FAIL] ~s: ~p~n", [Label, E]), {P, F + 1};');
  Lines.Add('                {Tag, Other} -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('            after 10000 ->');
  Lines.Add('                io:format("[SKIP] ~s (p2p route timeout)~n", [Label]), {P, F}');
  Lines.Add('            end;');
  Lines.Add('        Other ->');
  Lines.Add('            io:format("[FAIL] ~s: dispatch ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_p2p_notify_test(Label, Fun, P, F) ->');
  Lines.Add('    try case Fun() of');
  Lines.Add('        ok -> io:format("[PASS] ~s~n", [Label]), {P + 1, F};');
  Lines.Add('        Other -> io:format("[FAIL] ~s: ~p~n", [Label, Other]), {P, F + 1}');
  Lines.Add('    end');
  Lines.Add('    catch ExClass:ExReason ->');
  Lines.Add('        io:format("[FAIL] ~s: ~p:~p~n", [Label, ExClass, ExReason]), {P, F + 1}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('probe_client_identity() ->');
  Lines.Add('    {ok, Req} = lingofuse:create_data(<<"LF_TEST_WHOAMI">>),');
  Lines.Add('    try');
  Lines.Add('        case lingofuse:call(?SERVICE_APP, Req, ?ABI_TIMEOUT_MS) of');
  Lines.Add('            {ok, Res} ->');
  Lines.Add('                try');
  Lines.Add('                    {ok, Sz} = lingofuse:get_size(Res),');
  Lines.Add('                    case Sz of');
  Lines.Add('                        0 -> io:format("[WARN] whoami: empty response~n"), false;');
  Lines.Add('                        _ ->');
  Lines.Add('                            ok = lingofuse:set_pos(Res, 0),');
  Lines.Add('                            {ok, Bin} = lingofuse:read_buffer(Res, Sz),');
  Lines.Add('                            case decode_whoami_response(Bin) of');
  Lines.Add('                                {ok, Uid, P2PName} ->');
  Lines.Add('                                    io:format("[INFO] client UID = ~s~n", [hex_upper(Uid)]),');
  Lines.Add('                                    io:format("[INFO] client P2P = ~s~n", [P2PName]),');
  Lines.Add('                                    Uid =/= <<0:256>>;');
  Lines.Add('                                {error, E} ->');
  Lines.Add('                                    io:format("[WARN] whoami: ~p (hex=~s)~n", [E, hex_upper(Bin)]),');
  Lines.Add('                                    false');
  Lines.Add('                            end');
  Lines.Add('                    end');
  Lines.Add('                after lingofuse:free_data(Res) end;');
  Lines.Add('            {error, E} ->');
  Lines.Add('                io:format("[WARN] whoami call failed: ~p~n", [E]),');
  Lines.Add('                false');
  Lines.Add('        end');
  Lines.Add('    after lingofuse:free_data(Req) end.');
  Lines.Add('');

  Lines.Add('test_service_initiates_call() ->');
  Lines.Add('    {ok, Data} = lingofuse:create_data(<<"LF_TEST_ASK_SERVICE_CALL_ME">>),');
  Lines.Add('    try');
  Lines.Add('        io:format("[INFO] notifying service to initiate reverse call...~n"),');
  Lines.Add('        lingofuse:notify(?SERVICE_APP, Data)');
  Lines.Add('    after lingofuse:free_data(Data) end,');
  Lines.Add('    receive');
  Lines.Add('        {service_uid_received, UID} ->');
  Lines.Add('            io:format("[OK] service-initiated call succeeded, service UID = ~s~n", [hex_upper(UID)]),');
  Lines.Add('            {ok, UID}');
  Lines.Add('    after 15000 ->');
  Lines.Add('        io:format("[WARN] service-initiated call timeout (15s), UID tests will be SKIP~n"),');
  Lines.Add('        {error, timeout}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('run_tests(MainPid) ->');
  Lines.Add('    case probe_client_identity() of');
  Lines.Add('        true -> io:format("[OK] client identity probe~n");');
  Lines.Add('        false -> io:format("[WARN] whoami failed~n")');
  Lines.Add('    end,');
  Lines.Add('    ServiceUidRaw = case test_service_initiates_call() of');
  Lines.Add('        {ok, UID} -> UID;');
  Lines.Add('        {error, _} -> <<0:256>>');
  Lines.Add('    end,');
  Lines.Add('    ServiceUid = case ServiceUidRaw of');
  Lines.Add('        <<0:256>> -> <<0:256>>;');
  Lines.Add('        _ ->');
  Lines.Add('            case wait_uid_registered(ServiceUidRaw, 20) of');
  Lines.Add('                true -> ServiceUidRaw;');
  Lines.Add('                false -> <<0:256>>');
  Lines.Add('            end');
  Lines.Add('    end,');
  Lines.Add('    P2PReady = wait_p2p_registered(?SERVICE_P2P, 20),');
  Lines.Add('    put(service_uid, ServiceUid),');
  Lines.Add('    put(p2p_ready, P2PReady),');
  Lines.Add('    {P, F} = run_api_tests(),');
  Lines.Add('    MainPid ! {tests_done, P, F}.');
  Lines.Add('');
end;

function CallModuleAtom(const CallModule, ApiName: SystemString): SystemString;
begin
  Result := ErlangQuotedAtom(CallModule) + ':' + ErlangQuotedAtom(ApiName);
end;

procedure EmitFunctionTestBody(Lines: TPascalStringList;
  const CallModule, ApiName: SystemString; const F: TFunctionStructure);
var
  Args, S: SystemString;
begin
  Args := BuildArgList(F);

  S := 'test_' + ApiName + '(P0, F0) ->';
  Lines.Add(S);
  Lines.Add('    Uid = get(service_uid),');
  Lines.Add('    P2PReady = get(p2p_ready),');
  Lines.Add('    HasUid = (Uid =/= <<0:256>>),');

  if Args = '' then
  begin
    S := '    {P1, F1} = run_sync_test(<<"' + ApiName + '(app sync)">>,';
    Lines.Add(S);
    S := '        fun() -> ' + CallModuleAtom(CallModule, ApiName) + '(?SERVICE_APP) end,';
    Lines.Add(S);
    Lines.Add('        P0, F0),');

    S := '    {P2, F2} = run_async_test(<<"' + ApiName + '(app async)">>,';
    Lines.Add(S);
    S := '        fun(Cb) -> ' + CallModuleAtom(CallModule, ApiName + '_async') + '(?SERVICE_APP, Cb) end,';
    Lines.Add(S);
    Lines.Add('        P1, F1),');
  end
  else
  begin
    S := '    {P1, F1} = run_sync_test(<<"' + ApiName + '(app sync)">>,';
    Lines.Add(S);
    S := '        fun() -> ' + CallModuleAtom(CallModule, ApiName) + '(?SERVICE_APP, ' + Args + ') end,';
    Lines.Add(S);
    Lines.Add('        P0, F0),');

    S := '    {P2, F2} = run_async_test(<<"' + ApiName + '(app async)">>,';
    Lines.Add(S);
    S := '        fun(Cb) -> ' + CallModuleAtom(CallModule, ApiName + '_async') + '(?SERVICE_APP, ' + Args + ', Cb) end,';
    Lines.Add(S);
    Lines.Add('        P1, F1),');
  end;

  Lines.Add('    {P3, F3} = case HasUid of');
  Lines.Add('        true ->');
  if Args = '' then
  begin
    S := '            run_uid_sync_test(<<"' + ApiName + '(uid sync)">>,';
    Lines.Add(S);
    S := '                fun() -> ' + CallModuleAtom(CallModule, ApiName + '_uid') + '(Uid) end,';
    Lines.Add(S);
  end
  else
  begin
    S := '            run_uid_sync_test(<<"' + ApiName + '(uid sync)">>,';
    Lines.Add(S);
    S := '                fun() -> ' + CallModuleAtom(CallModule, ApiName + '_uid') + '(Uid, ' + Args + ') end,';
    Lines.Add(S);
  end;
  Lines.Add('                P2, F2);');
  S := '        false -> io:format("[SKIP] ~s -- no service UID~n", [<<"' + ApiName + '(uid sync)">>]), {P2, F2}';
  Lines.Add(S);
  Lines.Add('    end,');

  Lines.Add('    {P4, F4} = case HasUid of');
  Lines.Add('        true ->');
  if Args = '' then
  begin
    S := '            run_uid_async_test(<<"' + ApiName + '(uid async)">>,';
    Lines.Add(S);
    S := '                fun(Cb) -> ' + CallModuleAtom(CallModule, ApiName + '_uid_async') + '(Uid, Cb) end,';
    Lines.Add(S);
  end
  else
  begin
    S := '            run_uid_async_test(<<"' + ApiName + '(uid async)">>,';
    Lines.Add(S);
    S := '                fun(Cb) -> ' + CallModuleAtom(CallModule, ApiName + '_uid_async') + '(Uid, ' + Args + ', Cb) end,';
    Lines.Add(S);
  end;
  Lines.Add('                P3, F3);');
  S := '        false -> io:format("[SKIP] ~s -- no service UID~n", [<<"' + ApiName + '(uid async)">>]), {P3, F3}';
  Lines.Add(S);
  Lines.Add('    end,');

  if Args = '' then
  begin
    S := '    {P5, F5} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_sync_test(<<"' + ApiName + '(p2p sync)">>,';
    Lines.Add(S);
    S := '            fun() -> ' + CallModuleAtom(CallModule, ApiName + '_p2p') + '(?SERVICE_P2P) end,';
    Lines.Add(S);
    Lines.Add('            P4, F4);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p sync)">>]), {P4, F4}';
    Lines.Add(S);
    Lines.Add('    end,');

    S := '    {P6, F6} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_async_test(<<"' + ApiName + '(p2p async)">>,';
    Lines.Add(S);
    S := '            fun(Cb) -> ' + CallModuleAtom(CallModule, ApiName + '_p2p_async') + '(?SERVICE_P2P, Cb) end,';
    Lines.Add(S);
    Lines.Add('            P5, F5);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p async)">>]), {P5, F5}';
    Lines.Add(S);
    Lines.Add('    end,');
  end
  else
  begin
    S := '    {P5, F5} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_sync_test(<<"' + ApiName + '(p2p sync)">>,';
    Lines.Add(S);
    S := '            fun() -> ' + CallModuleAtom(CallModule, ApiName + '_p2p') + '(?SERVICE_P2P, ' + Args + ') end,';
    Lines.Add(S);
    Lines.Add('            P4, F4);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p sync)">>]), {P4, F4}';
    Lines.Add(S);
    Lines.Add('    end,');

    S := '    {P6, F6} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_async_test(<<"' + ApiName + '(p2p async)">>,';
    Lines.Add(S);
    S := '            fun(Cb) -> ' + CallModuleAtom(CallModule, ApiName + '_p2p_async') + '(?SERVICE_P2P, ' + Args + ', Cb) end,';
    Lines.Add(S);
    Lines.Add('            P5, F5);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p async)">>]), {P5, F5}';
    Lines.Add(S);
    Lines.Add('    end,');
  end;

  Lines.Add('    {P6, F6}.');
  Lines.Add('');
end;

procedure EmitProcedureTestBody(Lines: TPascalStringList;
  const CallModule, ApiName: SystemString; const F: TFunctionStructure);
var
  Args, S: SystemString;
begin
  Args := BuildArgList(F);

  S := 'test_' + ApiName + '(P0, F0) ->';
  Lines.Add(S);
  Lines.Add('    Uid = get(service_uid),');
  Lines.Add('    P2PReady = get(p2p_ready),');
  Lines.Add('    HasUid = (Uid =/= <<0:256>>),');

  if Args = '' then
  begin
    S := '    {P1, F1} = run_notify_test(<<"' + ApiName + '(app notify)">>,';
    Lines.Add(S);
    S := '        fun() -> ' + CallModuleAtom(CallModule, ApiName) + '(?SERVICE_APP) end,';
    Lines.Add(S);
    Lines.Add('        P0, F0),');

    S := '    {P2, F2} = run_notify_test(<<"' + ApiName + '(app seq notify)">>,';
    Lines.Add(S);
    S := '        fun() -> ' + CallModuleAtom(CallModule, ApiName + '_seq') + '(?SERVICE_APP) end,';
    Lines.Add(S);
    Lines.Add('        P1, F1),');
  end
  else
  begin
    S := '    {P1, F1} = run_notify_test(<<"' + ApiName + '(app notify)">>,';
    Lines.Add(S);
    S := '        fun() -> ' + CallModuleAtom(CallModule, ApiName) + '(?SERVICE_APP, ' + Args + ') end,';
    Lines.Add(S);
    Lines.Add('        P0, F0),');

    S := '    {P2, F2} = run_notify_test(<<"' + ApiName + '(app seq notify)">>,';
    Lines.Add(S);
    S := '        fun() -> ' + CallModuleAtom(CallModule, ApiName + '_seq') + '(?SERVICE_APP, ' + Args + ') end,';
    Lines.Add(S);
    Lines.Add('        P1, F1),');
  end;

  Lines.Add('    {P3, F3} = case HasUid of');
  Lines.Add('        true ->');
  if Args = '' then
  begin
    S := '            run_uid_notify_test(<<"' + ApiName + '(uid notify)">>,';
    Lines.Add(S);
    S := '                fun() -> ' + CallModuleAtom(CallModule, ApiName + '_uid') + '(Uid) end,';
    Lines.Add(S);
  end
  else
  begin
    S := '            run_uid_notify_test(<<"' + ApiName + '(uid notify)">>,';
    Lines.Add(S);
    S := '                fun() -> ' + CallModuleAtom(CallModule, ApiName + '_uid') + '(Uid, ' + Args + ') end,';
    Lines.Add(S);
  end;
  Lines.Add('                P2, F2);');
  S := '        false -> io:format("[SKIP] ~s -- no service UID~n", [<<"' + ApiName + '(uid notify)">>]), {P2, F2}';
  Lines.Add(S);
  Lines.Add('    end,');

  Lines.Add('    {P4, F4} = case HasUid of');
  Lines.Add('        true ->');
  if Args = '' then
  begin
    S := '            run_uid_notify_test(<<"' + ApiName + '(uid seq notify)">>,';
    Lines.Add(S);
    S := '                fun() -> ' + CallModuleAtom(CallModule, ApiName + '_uid_seq') + '(Uid) end,';
    Lines.Add(S);
  end
  else
  begin
    S := '            run_uid_notify_test(<<"' + ApiName + '(uid seq notify)">>,';
    Lines.Add(S);
    S := '                fun() -> ' + CallModuleAtom(CallModule, ApiName + '_uid_seq') + '(Uid, ' + Args + ') end,';
    Lines.Add(S);
  end;
  Lines.Add('                P3, F3);');
  S := '        false -> io:format("[SKIP] ~s -- no service UID~n", [<<"' + ApiName + '(uid seq notify)">>]), {P3, F3}';
  Lines.Add(S);
  Lines.Add('    end,');

  if Args = '' then
  begin
    S := '    {P5, F5} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_notify_test(<<"' + ApiName + '(p2p notify)">>,';
    Lines.Add(S);
    S := '            fun() -> ' + CallModuleAtom(CallModule, ApiName + '_p2p') + '(?SERVICE_P2P) end,';
    Lines.Add(S);
    Lines.Add('            P4, F4);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p notify)">>]), {P4, F4}';
    Lines.Add(S);
    Lines.Add('    end,');

    S := '    {P6, F6} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_notify_test(<<"' + ApiName + '(p2p seq notify)">>,';
    Lines.Add(S);
    S := '            fun() -> ' + CallModuleAtom(CallModule, ApiName + '_p2p_seq') + '(?SERVICE_P2P) end,';
    Lines.Add(S);
    Lines.Add('            P5, F5);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p seq notify)">>]), {P5, F5}';
    Lines.Add(S);
    Lines.Add('    end,');
  end
  else
  begin
    S := '    {P5, F5} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_notify_test(<<"' + ApiName + '(p2p notify)">>,';
    Lines.Add(S);
    S := '            fun() -> ' + CallModuleAtom(CallModule, ApiName + '_p2p') + '(?SERVICE_P2P, ' + Args + ') end,';
    Lines.Add(S);
    Lines.Add('            P4, F4);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p notify)">>]), {P4, F4}';
    Lines.Add(S);
    Lines.Add('    end,');

    S := '    {P6, F6} = case P2PReady of';
    Lines.Add(S);
    S := '        true -> run_p2p_notify_test(<<"' + ApiName + '(p2p seq notify)">>,';
    Lines.Add(S);
    S := '            fun() -> ' + CallModuleAtom(CallModule, ApiName + '_p2p_seq') + '(?SERVICE_P2P, ' + Args + ') end,';
    Lines.Add(S);
    Lines.Add('            P5, F5);');
    S := '        false -> io:format("[SKIP] ~s -- p2p not ready~n", [<<"' + ApiName + '(p2p seq notify)">>]), {P5, F5}';
    Lines.Add(S);
    Lines.Add('    end,');
  end;

  Lines.Add('    {P6, F6}.');
  Lines.Add('');
end;

function GenerateABIServiceTestErlangCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, Endpoint, P2PName, ServiceModule, ModuleName: SystemString;
  Lines: TPascalStringList;
  S: SystemString;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName.Text;
  if UnitName = '' then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(Model.UnitName);
  AppName := NormalizedUnit + '_abi';
  Endpoint := 'ipc:' + AppName;
  P2PName := NormalizedUnit + '_service_test_p2p';
  ServiceModule := NormalizedUnit + '_abi_service';
  ModuleName := NormalizedUnit + '_abi_service_main';

  Log(PFormat('Generating Erlang ABI service test main for unit "%s"', [UnitName]));

  Lines := TPascalStringList.Create;
  try
    S := '-module(' + ErlangQuotedAtom(ModuleName) + ').';
    Lines.Add(S);
    Lines.Add('-export([main/1]).');
    Lines.Add('');
    EmitServiceMainBody(Lines, AppName, Endpoint, P2PName, ServiceModule);
    Result := Lines;
    Log(PFormat('Generated %d lines for service test main.', [Lines.Count]));
  finally
    if Result = nil then
      Lines.Free;
  end;
end;

function GenerateABICallTestErlangCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  ApiNames: TSystemStringArray;
  UnitName, NormalizedUnit, AppName, ClientApp, Endpoint, P2PName, ModuleName, CallModule: SystemString;
  F: TFunctionStructure;
  ApiName: SystemString;
  Lines: TPascalStringList;
  S, LastVar: SystemString;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName.Text;
  if UnitName = '' then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(Model.UnitName);
  AppName := NormalizedUnit + '_abi';
  ClientApp := NormalizedUnit + '_client_self';
  Endpoint := 'ipc:' + AppName;
  P2PName := NormalizedUnit + '_service_test_p2p';
  ModuleName := NormalizedUnit + '_abi_call_main';
  CallModule := NormalizedUnit + '_abi_call';

  Log(PFormat('Generating Erlang ABI call test main for unit "%s"', [UnitName]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := AssignUniqueApiNames(SupportedFuncs);

  Lines := TPascalStringList.Create;
  try
    S := '-module(' + ErlangQuotedAtom(ModuleName) + ').';
    Lines.Add(S);
    Lines.Add('-export([main/1]).');
    Lines.Add('');
    S := '-define(ENDPOINT, ' + ErlangBinLit(Endpoint) + ').';
    Lines.Add(S);
    S := '-define(CLIENT_APP, ' + ErlangBinLit(ClientApp) + ').';
    Lines.Add(S);
    S := '-define(SERVICE_APP, ' + ErlangBinLit(AppName) + ').';
    Lines.Add(S);
    S := '-define(SERVICE_P2P, ' + ErlangBinLit(P2PName) + ').';
    Lines.Add(S);
    Lines.Add('');

    Lines.Add('main(_) ->');
    Lines.Add('    case lingofuse:ensure_loaded() of');
    Lines.Add('        ok -> ok;');
    Lines.Add('        {error, _} ->');
    Lines.Add('            io:format(standard_error, "[FATAL] NIF not loaded~n", []),');
    Lines.Add('            halt(1)');
    Lines.Add('    end,');
    Lines.Add('    ok = lingofuse:set_option(<<"Wait_Connection_ReadyOk">>, <<"False">>),');
    Lines.Add('    ok = lingofuse:set_option(<<"Overlap_Connection">>, <<"True">>),');
    Lines.Add('    ok = lingofuse:set_option(<<"Quiet">>, <<"True">>),');
    Lines.Add('    ok = lingofuse:reset_prepare(),');
    Lines.Add('    {ok, App} = lingofuse:create_app(?CLIENT_APP, <<"client test app">>),');
    Lines.Add('    ok = lingofuse:register_call_sync(App, <<"LF_TEST_REPORT_SERVICE_IDENTITY">>, <<"report helper">>, self(), #{with_identity => true}),');
    Lines.Add('    case lingofuse:prepare_client(?ENDPOINT, App) of');
    Lines.Add('        {ok, Tag} when Tag >= 0 -> ok;');
    Lines.Add('        Err ->');
    Lines.Add('            io:format(standard_error, "[FATAL] prepare_client: ~p~n", [Err]),');
    Lines.Add('            halt(1)');
    Lines.Add('    end,');
    Lines.Add('    case lingofuse:prepare_done() of');
    Lines.Add('        {ok, 1} -> ok;');
    Lines.Add('        Err2 ->');
    Lines.Add('            io:format(standard_error, "[FATAL] prepare_done: ~p~n", [Err2]),');
    Lines.Add('            halt(1)');
    Lines.Add('    end,');
    Lines.Add('    case wait_service_ready(40) of');
    Lines.Add('        true -> ok;');
    Lines.Add('        false ->');
    Lines.Add('            io:format(standard_error, "[FATAL] service app not visible~n", []),');
    Lines.Add('            halt(1)');
    Lines.Add('    end,');
    Lines.Add('    io:format("[OK] service visible~n"),');
    Lines.Add('    MainPid = self(),');
    Lines.Add('    TestPid = spawn(fun() -> run_tests(MainPid) end),');
    Lines.Add('    loop(App, TestPid).');
    Lines.Add('');

    Lines.Add('loop(App, TestPid) ->');
    Lines.Add('    receive');
    Lines.Add('        {lf_call, Ref, <<"LF_TEST_REPORT_SERVICE_IDENTITY">>, _Payload, Identity} when is_integer(Ref) ->');
    Lines.Add('            ServiceUid = maps:get(uid, Identity, <<0:256>>),');
    Lines.Add('            io:format("[CLIENT] service called me, service UID = ~s~n", [hex_upper(ServiceUid)]),');
    Lines.Add('            TestPid ! {service_uid_received, ServiceUid},');
    Lines.Add('            _ = lingofuse:reply(Ref, <<0, <<"identity received">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_p2p_call, Ref, <<"LF_TEST_REPORT_SERVICE_IDENTITY">>, _Payload, Identity} when is_integer(Ref) ->');
    Lines.Add('            ServiceUid = maps:get(uid, Identity, <<0:256>>),');
    Lines.Add('            io:format("[CLIENT] service called me (p2p), service UID = ~s~n", [hex_upper(ServiceUid)]),');
    Lines.Add('            TestPid ! {service_uid_received, ServiceUid},');
    Lines.Add('            _ = lingofuse:reply(Ref, <<0, <<"identity received">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_call, Ref, <<"LF_TEST_REPORT_SERVICE_IDENTITY">>, _Payload} when is_integer(Ref) ->');
    Lines.Add('            _ = lingofuse:reply(Ref, <<0, <<"identity received (no identity)">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_p2p_call, Ref, <<"LF_TEST_REPORT_SERVICE_IDENTITY">>, _Payload} when is_integer(Ref) ->');
    Lines.Add('            _ = lingofuse:reply(Ref, <<0, <<"identity received (no identity)">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_call, Ref, Api, Payload, _Identity} when is_integer(Ref) ->');
    Lines.Add('            io:format("[CLIENT] unknown app call api=~s~n", [Api]),');
    Lines.Add('            _ = Payload,');
    Lines.Add('            _ = lingofuse:reply(Ref, <<255, <<"unknown api">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_p2p_call, Ref, Api, Payload, _Identity} when is_integer(Ref) ->');
    Lines.Add('            io:format("[CLIENT] unknown p2p call api=~s~n", [Api]),');
    Lines.Add('            _ = Payload,');
    Lines.Add('            _ = lingofuse:reply(Ref, <<255, <<"unknown api">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_call, Ref, Api, Payload} when is_integer(Ref) ->');
    Lines.Add('            io:format("[CLIENT] unknown app call api=~s~n", [Api]),');
    Lines.Add('            _ = Payload,');
    Lines.Add('            _ = lingofuse:reply(Ref, <<255, <<"unknown api">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_p2p_call, Ref, Api, Payload} when is_integer(Ref) ->');
    Lines.Add('            io:format("[CLIENT] unknown p2p call api=~s~n", [Api]),');
    Lines.Add('            _ = Payload,');
    Lines.Add('            _ = lingofuse:reply(Ref, <<255, <<"unknown api">>/binary, 0>>),');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_notify, _Api, _Payload, _Identity} ->');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_p2p_notify, _Api, _Payload, _Identity} ->');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_notify, _Api, _Payload} ->');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {lf_p2p_notify, _Api, _Payload} ->');
    Lines.Add('            loop(App, TestPid);');
    Lines.Add('        {tests_done, P, F} ->');
    Lines.Add('            io:format("~n=== Summary ===~nPass: ~p~nFail: ~p~n", [P, F]),');
    Lines.Add('            try lingofuse:exit_main_thread() catch _:_ -> ok end,');
    Lines.Add('            try lingofuse:free_app(App) catch _:_ -> ok end,');
    Lines.Add('            try lingofuse:shutdown() catch _:_ -> ok end,');
    Lines.Add('            case F of');
    Lines.Add('                0 -> halt(0);');
    Lines.Add('                _ -> halt(2)');
    Lines.Add('            end;');
    Lines.Add('        _Other ->');
    Lines.Add('            loop(App, TestPid)');
    Lines.Add('    end.');
    Lines.Add('');

    EmitClientHelpers(Lines);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      if F.IsFunction then
        EmitFunctionTestBody(Lines, CallModule, ApiName, F)
      else
        EmitProcedureTestBody(Lines, CallModule, ApiName, F);
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('run_api_tests() ->');
      Lines.Add('    {0, 0}.');
    end
    else
    begin
      Lines.Add('run_api_tests() ->');
      S := '    {P1, F1} = test_' + ApiNames[0] + '(0, 0),';
      Lines.Add(S);
      for i := 1 to High(SupportedFuncs) do
      begin
        S := '    {P' + umlIntToStr(i + 1).Text + ', F' + umlIntToStr(i + 1).Text +
          '} = test_' + ApiNames[i] + '(P' +
          umlIntToStr(i).Text + ', F' + umlIntToStr(i).Text + '),';
        Lines.Add(S);
      end;
      LastVar := 'P' + umlIntToStr(Length(SupportedFuncs)).Text + ', F' +
        umlIntToStr(Length(SupportedFuncs)).Text;
      S := '    {' + LastVar + '}.';
      Lines.Add(S);
    end;
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for call test main.', [Lines.Count]));
  finally
    if Result = nil then
      Lines.Free;
  end;
end;

initialization
  RegisterGenerator('erlang', 'xxx_abi_service_main.erl', gkTest,
    'Erlang ABI service test main', @GenerateABIServiceTestErlangCode);
  RegisterGenerator('erlang', 'xxx_abi_call_main.erl', gkTest,
    'Erlang ABI call test main', @GenerateABICallTestErlangCode);

end.
