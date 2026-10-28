unit http_erlang_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceErlangCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Stub_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '<<>>'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'ok';
end;

function ABI_Type_To_Getter(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'get_string_arg'
  else if ABI_Type_Is_Float(T) then
    Result := 'get_float_arg'
  else if ABI_Type_Is_Int(T) then
    Result := 'get_int_arg'
  else
    Result := 'get_arg';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeErlangFuncName(const ApiName: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to ApiName.Len do
  begin
    c := ApiName[i];
    if (c >= 'A') and (c <= 'Z') then
      Result.Append(TP_Char(Ord(c) + 32))
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
      ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len = 0) or ((Result[1] >= '0') and (Result[1] <= '9')) then
    Result := 'api_' + Result;
end;

function MakeErlangVarName(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'Arg' + umlIntToStr(Index);
    Exit;
  end;

  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
      ((c >= 'A') and (c <= 'Z')) or
      ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= 'a') and (Result[1] <= 'z') then
    Result[1] := TP_Char(Ord(Result[1]) - 32);

  if (Result.Len = 0) or ((Result[1] >= '0') and (Result[1] <= '9')) then
    Result := 'Arg' + umlIntToStr(Index);
end;

function EscapeErlangStringBody(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := '';
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
      #27: Result.Append('\e');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\x{');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
          Result.Append('}');
        end
        else
          Result.Append(c);
    end;
  end;
end;

function ErlStrLit(const S: TP_String): TP_String;
begin
  Result := '"' + EscapeErlangStringBody(S) + '"';
end;

function ErlBinLit(const S: TP_String): TP_String;
begin
  Result := '<<"' + EscapeErlangStringBody(S) + '">>';
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
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
          // Skip Doxygen tag lines.
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

function BuildErlangParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeErlangVarName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildErlangArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeErlangVarName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildStubSignature(const F: TFunctionStructure; const StubName: TP_String): TP_String;
begin
  if Length(F.Params) = 0 then
    Result := StubName + '()'
  else
    Result := StubName + '(' + BuildErlangParamList(F.Params) + ')';
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

procedure EmitServiceHeader(Lines: TPascalStringList;
  const UnitName, AppName, Endpoint: TP_String);
begin
  Lines.Add('%% -*- coding: utf-8 -*-');
  Lines.Add('%% Auto-generated by http_erlang_abi_service_generator_tool.pas.');
  Lines.Add('%% Source model unit: ' + UnitName.Text + '.');
  Lines.Add('%%');
  Lines.Add('%% Wire protocol (HTTP/JSON path, both directions):');
  Lines.Add('%%   request  = JSON object');
  Lines.Add('%%              { "args": [v1, v2, ...] }     positional arguments');
  Lines.Add('%%              { "A": v1, "B": v2, ... }     named arguments');
  Lines.Add('%%   response = JSON object');
  Lines.Add('%%              { "code": 0,  "result": ... }  on success');
  Lines.Add('%%              { "code": -1, "error":  ... }  on failure');
  Lines.Add('%%');
  Lines.Add('%% This module is a LingoFuse Call service. It becomes a beacon');
  Lines.Add('%% via prepare_service AND a self-connected client via');
  Lines.Add('%% prepare_client. bridge.py connects to the beacon endpoint as');
  Lines.Add('%% a client, and the mesh routes incoming HTTP requests to this');
  Lines.Add('%% service.');
  Lines.Add('%%');
  Lines.Add('%% Why a self-connected client is needed:');
  Lines.Add('%%   App name routing requires the target client to be in the');
  Lines.Add('%%   mesh. prepare_client gives this process its own client');
  Lines.Add('%%   entry, which is what bridge.py and the generated call');
  Lines.Add('%%   module route to.');
  Lines.Add('%%');
  Lines.Add('%% The user is expected to:');
  Lines.Add('%%   1. Fill in each internal_call_<api> stub with a call to the');
  Lines.Add('%%      real implementation.');
  Lines.Add('%%   2. Compile the module:');
  Lines.Add('%%        erlc ' + AppName.Text + '_http_json_service.erl');
  Lines.Add('%%   3. Run it:');
  Lines.Add('%%        erl -noshell -s ' + AppName.Text + '_http_json_service main');
  Lines.Add('%%   4. Start bridge.py with the SAME endpoint:');
  Lines.Add('%%        python bridge.py --endpoint ' + Endpoint.Text + ' --no-precheck');
  Lines.Add('%%');
  Lines.Add('%% All comments and status output in this file are English.');
  Lines.Add('');
end;

procedure EmitServiceModuleDecl(Lines: TPascalStringList;
  const ModuleName: TP_String);
begin
  Lines.Add('-module(' + #39 + ModuleName.Text + #39 + ').');
  Lines.Add('');
  Lines.Add('-export([main/0]).');
  Lines.Add('-export([run_smoke_test/0]).');
  Lines.Add('');
end;

procedure EmitServiceConfig(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('app_name() -> ' + ErlBinLit(AppName) + '.');
  Lines.Add('');
  Lines.Add('app_desc() -> ' + ErlBinLit(AppDesc) + '.');
  Lines.Add('');
  Lines.Add('bridge_endpoint() -> ' + ErlBinLit(Endpoint) + '.');
  Lines.Add('');
end;

procedure EmitServiceLifecycle(Lines: TPascalStringList);
begin
  Lines.Add('main() ->');
  Lines.Add('    ok = ensure_native(),');
  Lines.Add('    AppName = app_name(),');
  Lines.Add('    AppDesc = app_desc(),');
  Lines.Add('    Endpoint = bridge_endpoint(),');
  Lines.Add('    io:format("[OK] LingoFuse native library is loaded.~n"),');
  Lines.Add('    io:format("[OK] App name    : ~s~n", [AppName]),');
  Lines.Add('    io:format("[OK] Endpoint    : ~s~n", [Endpoint]),');
  Lines.Add('    {ok, App} = lingofuse:create_app(AppName, AppDesc),');
  Lines.Add('    run_app(App, AppName, Endpoint).');
  Lines.Add('');
  Lines.Add('run_app(App, AppName, Endpoint) ->');
  Lines.Add('    try');
  Lines.Add('        ok = set_deployment_mode(),');
  Lines.Add('        ok = do_reset_prepare(),');
  Lines.Add('        ok = do_prepare_service(Endpoint),');
  Lines.Add('        ok = register_all_apis(App, self()),');
  Lines.Add('        ok = do_prepare_client(Endpoint, App),');
  Lines.Add('        ok = do_prepare_done(),');
  Lines.Add('        ok = wait_self_registered(AppName, 15000),');
  Lines.Add('        ok = spawn_enter_watcher(),');
  Lines.Add('        io:format("[OK] Service ready.~n"),');
  Lines.Add('        io:format("[OK] Press Enter to stop, or send the atom ' + #39 + 'stop' + #39 + '.~n"),');
  Lines.Add('        loop(App)');
  Lines.Add('    catch');
  Lines.Add('        Class:Reason:Stack ->');
  Lines.Add('            io:format(standard_error,');
  Lines.Add('                      "[FATAL] startup failed: ~p:~p~n~p~n",');
  Lines.Add('                      [Class, Reason, Stack]),');
  Lines.Add('            cleanup(App),');
  Lines.Add('            erlang:raise(Class, Reason, Stack)');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('loop(App) ->');
  Lines.Add('    receive');
  Lines.Add('        {lf_call, Ref, Api, Payload} when is_integer(Ref) ->');
  Lines.Add('            _ = spawn(fun() -> handle_request(Api, Ref, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_call, Ref, Api, Payload, _Identity} when is_integer(Ref) ->');
  Lines.Add('            _ = spawn(fun() -> handle_request(Api, Ref, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_p2p_call, Ref, Api, Payload} when is_integer(Ref) ->');
  Lines.Add('            _ = spawn(fun() -> handle_request(Api, Ref, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_p2p_call, Ref, Api, Payload, _Identity} when is_integer(Ref) ->');
  Lines.Add('            _ = spawn(fun() -> handle_request(Api, Ref, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_notify, Api, Payload} when is_binary(Api) ->');
  Lines.Add('            _ = spawn(fun() -> handle_notify(Api, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_notify, Api, Payload, _Identity} when is_binary(Api) ->');
  Lines.Add('            _ = spawn(fun() -> handle_notify(Api, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_p2p_notify, Api, Payload} when is_binary(Api) ->');
  Lines.Add('            _ = spawn(fun() -> handle_notify(Api, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_p2p_notify, Api, Payload, _Identity} when is_binary(Api) ->');
  Lines.Add('            _ = spawn(fun() -> handle_notify(Api, Payload) end),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_connect, Addr} ->');
  Lines.Add('            io:format("[event] connected: ~s~n", [Addr]),');
  Lines.Add('            loop(App);');
  Lines.Add('        {lf_disconnect, Addr} ->');
  Lines.Add('            io:format("[event] disconnected: ~s~n", [Addr]),');
  Lines.Add('            loop(App);');
  Lines.Add('        stop ->');
  Lines.Add('            io:format("[OK] stop received, shutting down...~n"),');
  Lines.Add('            cleanup(App),');
  Lines.Add('            io:format("[OK] service stopped.~n"),');
  Lines.Add('            ok;');
  Lines.Add('        _Other ->');
  Lines.Add('            loop(App)');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('cleanup(App) ->');
  Lines.Add('    try lingofuse:exit_main_thread() catch _:_ -> ok end,');
  Lines.Add('    try lingofuse:free_app(App)       catch _:_ -> ok end,');
  Lines.Add('    try lingofuse:shutdown()           catch _:_ -> ok end,');
  Lines.Add('    ok.');
  Lines.Add('');
  Lines.Add('spawn_enter_watcher() ->');
  Lines.Add('    Self = self(),');
  Lines.Add('    _ = spawn(fun() -> enter_watcher_loop(Self) end),');
  Lines.Add('    ok.');
  Lines.Add('');
  Lines.Add('enter_watcher_loop(Parent) ->');
  Lines.Add('    case io:get_line("") of');
  Lines.Add('        eof -> ok;');
  Lines.Add('        _Line -> Parent ! stop, ok');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('set_deployment_mode() ->');
  Lines.Add('    try lingofuse:set_option(<<"Wait_Connection_ReadyOk">>, <<"False">>)');
  Lines.Add('    catch _:_ -> ok end,');
  Lines.Add('    try lingofuse:set_option(<<"Overlap_Connection">>, <<"True">>)');
  Lines.Add('    catch _:_ -> ok end,');
  Lines.Add('    ok.');
  Lines.Add('');
  Lines.Add('do_reset_prepare() ->');
  Lines.Add('    case lingofuse:reset_prepare() of');
  Lines.Add('        ok        -> ok;');
  Lines.Add('        {ok, _}   -> ok;');
  Lines.Add('        {error,R} -> error({reset_prepare_failed, R})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('do_prepare_service(Endpoint) ->');
  Lines.Add('    case lingofuse:prepare_service(Endpoint, Endpoint) of');
  Lines.Add('        {ok, _Tag} -> ok;');
  Lines.Add('        {error,R}  -> error({prepare_service_failed, R})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('do_prepare_client(Endpoint, App) ->');
  Lines.Add('    case lingofuse:prepare_client(Endpoint, App) of');
  Lines.Add('        {ok, _Tag} -> ok;');
  Lines.Add('        {error,R}  -> error({prepare_client_failed, R})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('do_prepare_done() ->');
  Lines.Add('    case lingofuse:prepare_done() of');
  Lines.Add('        {ok, 1}  -> ok;');
  Lines.Add('        {ok, 0}  -> ok;');
  Lines.Add('        {error,R} -> error({prepare_done_failed, R})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('wait_self_registered(AppName, TimeoutMs) ->');
  Lines.Add('    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,');
  Lines.Add('    wait_self_registered_loop(AppName, Deadline).');
  Lines.Add('');
  Lines.Add('wait_self_registered_loop(AppName, Deadline) ->');
  Lines.Add('    case lingofuse:check_app(AppName) of');
  Lines.Add('        {ok, true} ->');
  Lines.Add('            io:format("[OK] SelfClient registered App ~p.~n", [AppName]),');
  Lines.Add('            ok;');
  Lines.Add('        _ ->');
  Lines.Add('            Now = erlang:monotonic_time(millisecond),');
  Lines.Add('            case Now >= Deadline of');
  Lines.Add('                true ->');
  Lines.Add('                    io:format(standard_error,');
  Lines.Add('                              "[FATAL] App ~p was not registered within timeout.~n",');
  Lines.Add('                              [AppName]),');
  Lines.Add('                    error({app_not_registered, AppName});');
  Lines.Add('                false ->');
  Lines.Add('                    timer:sleep(100),');
  Lines.Add('                    wait_self_registered_loop(AppName, Deadline)');
  Lines.Add('            end');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('ensure_native() ->');
  Lines.Add('    case lingofuse:ensure_loaded() of');
  Lines.Add('        ok -> ok;');
  Lines.Add('        {error, Reason} -> error({lingofuse_not_loaded, Reason})');
  Lines.Add('    end.');
  Lines.Add('');
end;

procedure EmitServiceRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  ApiName, Description: TP_String;
begin
  Lines.Add('register_all_apis(App, CallbackPid) ->');
  if Length(SupportedFuncs) = 0 then
  begin
    Lines.Add('    _ = App,');
    Lines.Add('    _ = CallbackPid,');
    Lines.Add('    ok.');
  end
  else
  begin
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Description := GetFullDescription(SupportedFuncs[i].Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;
      Lines.Add('    case lingofuse:register_call_sync(');
      Lines.Add('            App,');
      Lines.Add('            ' + ErlBinLit(ApiName) + ',');
      Lines.Add('            ' + ErlBinLit(Description) + ',');
      Lines.Add('            CallbackPid) of');
      Lines.Add('        ok -> ok;');
      Lines.Add('        {error, R_' + umlIntToStr(i + 1).Text + '} ->');
      Lines.Add('            error({register_failed, ' + ErlBinLit(ApiName) + ', R_' + umlIntToStr(i + 1).Text + '})');
      Lines.Add('    end,');
    end;
    Lines.Add('    ok.');
  end;
  Lines.Add('');
end;

procedure EmitServiceDispatch(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, Getter, ArgExprs, ParamName: TP_String;
begin
  Lines.Add('handle_request(Api, Ref, Payload) ->');
  Lines.Add('    Response =');
  Lines.Add('        try');
  Lines.Add('            Req = lingofuse_json:loads(normalize_payload(Payload)),');
  Lines.Add('            case is_map(Req) of');
  Lines.Add('                true -> ok;');
  Lines.Add('                false -> error({invalid_request,');
  Lines.Add('                                   <<"request must be a JSON object">>})');
  Lines.Add('            end,');
  Lines.Add('            Result = dispatch(Api, Req),');
  Lines.Add('            #{<<"code">> => 0, <<"result">> => Result}');
  Lines.Add('        catch');
  Lines.Add('            error:{invalid_arg, Name, Detail, Value} ->');
  Lines.Add('                #{<<"code">> => -1,');
  Lines.Add('                  <<"error">> => format_invalid_arg(Name, Detail, Value)};');
  Lines.Add('            error:{unknown_api, ApiName} ->');
  Lines.Add('                #{<<"code">> => -1,');
  Lines.Add('                  <<"error">> => iolist_to_binary(');
  Lines.Add('                      [<<"Unknown API: ">>, format_term(ApiName)])};');
  Lines.Add('            error:{invalid_request, Msg} ->');
  Lines.Add('                #{<<"code">> => -1, <<"error">> => Msg};');
  Lines.Add('            Class:Reason:Stack ->');
  Lines.Add('                #{<<"code">> => -1,');
  Lines.Add('                  <<"error">> => format_exception(Class, Reason, Stack)}');
  Lines.Add('        end,');
  Lines.Add('    ResultBin = lingofuse_json:dumps(Response),');
  Lines.Add('    safe_reply(Ref, ResultBin).');
  Lines.Add('');
  Lines.Add('handle_notify(_Api, _Payload) ->');
  Lines.Add('    ok.');
  Lines.Add('');
  Lines.Add('safe_reply(Ref, Bin) ->');
  Lines.Add('    Framed = <<Bin/binary, 0>>,');
  Lines.Add('    try lingofuse:reply(Ref, Framed) of');
  Lines.Add('        ok -> ok;');
  Lines.Add('        {error, R} ->');
  Lines.Add('            io:format(standard_error,');
  Lines.Add('                      "[warn] reply failed: ~p~n", [R])');
  Lines.Add('    catch');
  Lines.Add('        C:R ->');
  Lines.Add('            io:format(standard_error,');
  Lines.Add('                      "[warn] reply raised: ~p:~p~n", [C, R])');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('normalize_payload(Bin) when is_binary(Bin) ->');
  Lines.Add('    case byte_size(Bin) > 0 andalso binary:last(Bin) =:= 0 of');
  Lines.Add('        true -> binary:part(Bin, 0, byte_size(Bin) - 1);');
  Lines.Add('        false -> Bin');
  Lines.Add('    end;');
  Lines.Add('normalize_payload(undefined) -> <<>>;');
  Lines.Add('normalize_payload(_Other) -> <<>>.');
  Lines.Add('');
  Lines.Add('get_arg(Req, Pos, Name, Default) ->');
  Lines.Add('    case Req of');
  Lines.Add('        #{<<"args">> := Args} when is_list(Args) ->');
  Lines.Add('            case Pos < length(Args) of');
  Lines.Add('                true ->');
  Lines.Add('                    case lists:nth(Pos + 1, Args) of');
  Lines.Add('                        null -> Default;');
  Lines.Add('                        undefined -> Default;');
  Lines.Add('                        V -> V');
  Lines.Add('                    end;');
  Lines.Add('                false -> Default');
  Lines.Add('            end;');
  Lines.Add('        _ when is_map(Req) ->');
  Lines.Add('            case maps:get(Name, Req, Default) of');
  Lines.Add('                null -> Default;');
  Lines.Add('                undefined -> Default;');
  Lines.Add('                V -> V');
  Lines.Add('            end;');
  Lines.Add('        _ -> Default');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('get_int_arg(Req, Pos, Name) ->');
  Lines.Add('    case get_arg(Req, Pos, Name, 0) of');
  Lines.Add('        V when is_integer(V) -> V;');
  Lines.Add('        V when is_float(V) ->');
  Lines.Add('            error({invalid_arg, Name,');
  Lines.Add('                   <<"expects an integer, got a float">>, V});');
  Lines.Add('        V ->');
  Lines.Add('            error({invalid_arg, Name, <<"expects an integer">>, V})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('get_float_arg(Req, Pos, Name) ->');
  Lines.Add('    case get_arg(Req, Pos, Name, 0.0) of');
  Lines.Add('        V when is_float(V) -> V;');
  Lines.Add('        V when is_integer(V) -> float(V);');
  Lines.Add('        V ->');
  Lines.Add('            error({invalid_arg, Name, <<"expects a number">>, V})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('get_string_arg(Req, Pos, Name) ->');
  Lines.Add('    case get_arg(Req, Pos, Name, <<>>) of');
  Lines.Add('        V when is_binary(V) -> V;');
  Lines.Add('        V ->');
  Lines.Add('            error({invalid_arg, Name,');
  Lines.Add('                   <<"expects a binary (UTF-8 string)">>, V})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('format_invalid_arg(Name, Detail, Value) ->');
  Lines.Add('    iolist_to_binary(');
  Lines.Add('      io_lib:format("Argument ~s ~s, got: ~p", [Name, Detail, Value])).');
  Lines.Add('');
  Lines.Add('format_exception(Class, Reason, _Stack) ->');
  Lines.Add('    iolist_to_binary(io_lib:format("~p:~p", [Class, Reason])).');
  Lines.Add('');
  Lines.Add('format_term(T) when is_binary(T) -> T;');
  Lines.Add('format_term(T) -> iolist_to_binary(io_lib:format("~p", [T])).');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := 'internal_call_' + MakeErlangFuncName(ApiName);
    ArgExprs := '';

    for j := 0 to High(F.Params) do
    begin
      Getter := ABI_Type_To_Getter(F.Params[j].PascalType);
      ParamName := F.Params[j].Name;
      if j > 0 then
        ArgExprs := ArgExprs + ',' + #13#10 + '            ';
      ArgExprs := ArgExprs + Getter + '(Req, ' + umlIntToStr(j).Text + ', ' +
        ErlBinLit(ParamName) + ')';
    end;

    Lines.Add('dispatch(' + ErlBinLit(ApiName) + ', Req) ->');
    if Length(F.Params) = 0 then
      Lines.Add('    ' + StubName + '();')
    else
    begin
      Lines.Add('    ' + StubName + '(');
      Lines.Add('            ' + ArgExprs + ');');
    end;
    Lines.Add('');
  end;

  Lines.Add('dispatch(Unknown, _Req) ->');
  Lines.Add('    error({unknown_api, Unknown}).');
  Lines.Add('');
end;

procedure EmitServiceStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  StubName, Sig, Description, SuggestCall: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    StubName := 'internal_call_' + MakeErlangFuncName(ApiNames[i]);
    Sig := BuildStubSignature(F, StubName);
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiNames[i];
    if Length(F.Params) = 0 then
      SuggestCall := F.Name.Text + '()'
    else
      SuggestCall := F.Name.Text + '(' + BuildErlangArgList(F.Params) + ')';

    Lines.Add('%% ' + Description.Text);
    Lines.Add(Sig.Text + ' ->');
    Lines.Add('    %% Suggested call: ' + SuggestCall.Text + '.');
    Lines.Add('    ' + ABI_Type_To_Stub_Default(F.ReturnType) + '.');
    Lines.Add('');
  end;
end;

procedure EmitServiceSmokeTest(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, CasesLine: TP_String;
begin
  Lines.Add('run_smoke_test() ->');
  Lines.Add('    ok = ensure_native(),');
  Lines.Add('    io:format("[smoke] running in-process LocalCall self-tests~n"),');
  Lines.Add('    io:format("[smoke] this mode does NOT start LingoFuse and "');
  Lines.Add('              "does NOT need the bridge~n"),');
  Lines.Add('    io:format("~n"),');
  Lines.Add('    {ok, App} = lingofuse:create_app(app_name(), app_desc()),');
  Lines.Add('    HandlerPid = spawn(fun() -> smoke_callback_loop() end),');
  Lines.Add('    try');
  Lines.Add('        ok = register_all_apis(App, HandlerPid),');
  Lines.Add('        Cases = [');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    CasesLine := '            {' + ErlBinLit(ApiName) + ', #{<<"args">> => [';
    for j := 0 to High(F.Params) do
    begin
      if j > 0 then
        CasesLine := CasesLine + ', ';
      if ABI_Type_Is_String(F.Params[j].PascalType) then
        CasesLine := CasesLine + '<<>>'
      else if ABI_Type_Is_Float(F.Params[j].PascalType) then
        CasesLine := CasesLine + '0.0'
      else
        CasesLine := CasesLine + '0';
    end;
    CasesLine := CasesLine + ']}}';
    if i < High(SupportedFuncs) then
      CasesLine := CasesLine + ',';
    Lines.Add(CasesLine.Text);
  end;

  if Length(SupportedFuncs) = 0 then
    Lines.Add('            %% (no supported routines)');

  Lines.Add('        ],');
  Lines.Add('        Passed = lists:foldl(');
  Lines.Add('            fun({Api, Req}, Acc) ->');
  Lines.Add('                case smoke_case(App, Api, Req) of');
  Lines.Add('                    ok -> Acc + 1;');
  Lines.Add('                    error -> Acc');
  Lines.Add('                end');
  Lines.Add('            end, 0, Cases),');
  Lines.Add('        Failed = length(Cases) - Passed,');
  Lines.Add('        io:format("~n=== Smoke test summary ===~n"),');
  Lines.Add('        io:format("Passed: ~p~n", [Passed]),');
  Lines.Add('        io:format("Failed: ~p~n", [Failed]),');
  Lines.Add('        case Failed of');
  Lines.Add('            0 -> ok;');
  Lines.Add('            _ -> error({smoke_test_failed, Failed})');
  Lines.Add('        end');
  Lines.Add('    after');
  Lines.Add('        HandlerPid ! stop,');
  Lines.Add('        try lingofuse:free_app(App) catch _:_ -> ok end');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('smoke_callback_loop() ->');
  Lines.Add('    receive');
  Lines.Add('        {lf_call, Ref, Api, Payload} ->');
  Lines.Add('            handle_request(Api, Ref, Payload),');
  Lines.Add('            smoke_callback_loop();');
  Lines.Add('        stop ->');
  Lines.Add('            ok');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('smoke_case(App, Api, Req) ->');
  Lines.Add('    try');
  Lines.Add('        {ok, InH} = lingofuse:create_data(Api),');
  Lines.Add('        try');
  Lines.Add('            ok = lingofuse_json:write_json(InH, Req),');
  Lines.Add('            case lingofuse:local_call(App, InH) of');
  Lines.Add('                {ok, OutH} ->');
  Lines.Add('                    try');
  Lines.Add('                        Resp = lingofuse_json:read_json(OutH),');
  Lines.Add('                        case Resp of');
  Lines.Add('                            #{<<"code">> := 0} ->');
  Lines.Add('                                io:format("  ~s: OK~n", [Api]),');
  Lines.Add('                                ok;');
  Lines.Add('                            #{<<"code">> := C, <<"error">> := E} ->');
  Lines.Add('                                io:format("  ~s: non-zero code ~p: ~s~n",');
  Lines.Add('                                          [Api, C, E]),');
  Lines.Add('                                error;');
  Lines.Add('                            Other ->');
  Lines.Add('                                io:format("  ~s: unexpected response: ~p~n",');
  Lines.Add('                                          [Api, Other]),');
  Lines.Add('                                error');
  Lines.Add('                        end');
  Lines.Add('                    after');
  Lines.Add('                        try lingofuse:free_data(OutH) catch _:_ -> ok end');
  Lines.Add('                    end;');
  Lines.Add('                {error, Reason} ->');
  Lines.Add('                    io:format("  ~s: local_call failed: ~p~n",');
  Lines.Add('                              [Api, Reason]),');
  Lines.Add('                    error');
  Lines.Add('            end');
  Lines.Add('        after');
  Lines.Add('            try lingofuse:free_data(InH) catch _:_ -> ok end');
  Lines.Add('        end');
  Lines.Add('    catch');
  Lines.Add('        Class:Reason2:Stack ->');
  Lines.Add('            io:format("  ~s: FAILED: ~p:~p~n  ~p~n",');
  Lines.Add('                      [Api, Class, Reason2, Stack]),');
  Lines.Add('            error');
  Lines.Add('    end.');
  Lines.Add('');
end;

function GenerateHTTPServiceErlangCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceErlangCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceErlangCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  ModuleName := NormalizedUnit + '_http_json_service';

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitServiceHeader(Lines, UnitName, AppName, Endpoint);
    EmitServiceModuleDecl(Lines, ModuleName);
    EmitServiceConfig(Lines, AppName, AppDesc, Endpoint);
    EmitServiceLifecycle(Lines);
    EmitServiceRegistration(Lines, SupportedFuncs, ApiNames);
    EmitServiceDispatch(Lines, SupportedFuncs, ApiNames);
    EmitServiceStubs(Lines, SupportedFuncs, ApiNames);
    EmitServiceSmokeTest(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated Erlang service module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'erlang', 'Erlang HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.erl', False,
    @GenerateHTTPServiceErlangCode);
end.
