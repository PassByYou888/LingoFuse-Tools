unit http_erlang_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceErlangTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallErlangTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_test_generator] %s', [PFormat(Fmt, Args)]);
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
  Result := T.Same('integer') or T.Same('longint') or
    T.Same('int64') or T.Same('cardinal') or T.Same('dword') or
    T.Same('longword') or T.Same('word') or T.Same('smallint') or
    T.Same('byte') or T.Same('uint64');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function ABI_Type_To_Erlang_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '<<>>'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
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

function BuildErlangDefaultArgs(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Erlang_Default_Literal(Params[i].PascalType);
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

procedure EmitEscriptShebang(Lines: TPascalStringList);
begin
  Lines.Add('#!/usr/bin/env escript');
  Lines.Add('%% -*- erlang -*-');
  Lines.Add('%%! -noshell +B d');
  Lines.Add('');
  Lines.Add('-mode(compile).');
  Lines.Add('');
end;

procedure EmitCodePathSetup(Lines: TPascalStringList);
begin
  Lines.Add('setup_code_path(Unit) ->');
  Lines.Add('    ScriptPath = filename:absname(escript:script_name()),');
  Lines.Add('    Dir = filename:dirname(ScriptPath),');
  Lines.Add('    Candidates = [');
  Lines.Add('        Dir,');
  Lines.Add('        filename:join([Dir, "_build", "default", "lib", "lingofuse", "ebin"]),');
  Lines.Add('        filename:join([Dir, "_build", "default", "lib", Unit, "ebin"]),');
  Lines.Add('        filename:join([Dir, "ebin"])');
  Lines.Add('    ],');
  Lines.Add('    lists:foreach(');
  Lines.Add('        fun(P) ->');
  Lines.Add('            case filelib:is_dir(P) of');
  Lines.Add('                true -> code:add_patha(P);');
  Lines.Add('                false -> ok');
  Lines.Add('            end');
  Lines.Add('        end, Candidates),');
  Lines.Add('    ok.');
  Lines.Add('');
end;

function GenerateHTTPServiceErlangTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceModuleName, FileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceErlangTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceErlangTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceModuleName := NormalizedUnit + '_http_json_service';
  FileName := NormalizedUnit + '_http_json_service_main_test___.escript';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitEscriptShebang(Lines);

    Lines.Add('-export([main/1]).');
    Lines.Add('');
    Lines.Add('-define(SERVICE_MODULE_ATOM, ' + #39 + ServiceModuleName.Text + #39 + ').');
    Lines.Add('');

    EmitCodePathSetup(Lines);

    Lines.Add('main(Args) ->');
    Lines.Add('    ok = setup_code_path(' + ErlStrLit(NormalizedUnit) + '),');
    Lines.Add('    io:format("=== ' + NormalizedUnit.Text + ' HTTP/JSON service test ===~n"),');
    Lines.Add('    io:format("API count: ' + MdInt(Length(SupportedFuncs)).Text + '~n"),');
    Lines.Add('    io:format("~n"),');
    Lines.Add('    IsSmoke = lists:member("--smoke", Args),');
    Lines.Add('    case IsSmoke of');
    Lines.Add('        true ->');
    Lines.Add('            run_smoke();');
    Lines.Add('        false ->');
    Lines.Add('            run_service()');
    Lines.Add('    end.');
    Lines.Add('');

    Lines.Add('run_smoke() ->');
    Lines.Add('    io:format("[smoke] delegating to ' + ServiceModuleName.Text + ':run_smoke_test/0~n"),');
    Lines.Add('    io:format("~n"),');
    Lines.Add('    try ?SERVICE_MODULE_ATOM:run_smoke_test() of');
    Lines.Add('        ok ->');
    Lines.Add('            io:format("~n[OK] smoke test completed~n"),');
    Lines.Add('            erlang:halt(0)');
    Lines.Add('    catch');
    Lines.Add('        Class:Reason:Stack ->');
    Lines.Add('            io:format(standard_error,');
    Lines.Add('                      "~n[FATAL] smoke test failed: ~p:~p~n~p~n",');
    Lines.Add('                      [Class, Reason, Stack]),');
    Lines.Add('            erlang:halt(1)');
    Lines.Add('    end.');
    Lines.Add('');

    Lines.Add('run_service() ->');
    Lines.Add('    io:format("[default] delegating to ' + ServiceModuleName.Text + ':main/0~n"),');
    Lines.Add('    io:format("[default] press Enter to stop the service (or Ctrl+C to force quit)~n"),');
    Lines.Add('    io:format("~n"),');
    Lines.Add('    try ?SERVICE_MODULE_ATOM:main() of');
    Lines.Add('        ok ->');
    Lines.Add('            io:format("[OK] service returned normally~n"),');
    Lines.Add('            erlang:halt(0)');
    Lines.Add('    catch');
    Lines.Add('        Class:Reason:Stack ->');
    Lines.Add('            io:format(standard_error,');
    Lines.Add('                      "[FATAL] service failed: ~p:~p~n~p~n",');
    Lines.Add('                      [Class, Reason, Stack]),');
    Lines.Add('            erlang:halt(1)');
    Lines.Add('    end.');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateHTTPCallErlangTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, CallModuleName, DefaultBaseUrl, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, DefaultArgs, ProbeApiName, ProbeArgs: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  IsLast: boolean;
  SyncComma, AsyncComma: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallErlangTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallErlangTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and
     (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  CallModuleName := NormalizedUnit + '_http_json_call';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  FileName := NormalizedUnit + '_http_json_call_main_test___.escript';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitEscriptShebang(Lines);

    Lines.Add('-export([main/1]).');
    Lines.Add('');
    Lines.Add('-define(CALL_MODULE_ATOM, ' + #39 + CallModuleName.Text + #39 + ').');
    Lines.Add('-define(DEFAULT_BASE_URL, ' + ErlBinLit(DefaultBaseUrl) + ').');
    Lines.Add('-define(ASYNC_TIMEOUT_MS, 30000).');
    Lines.Add('-define(PROBE_RETRIES, 30).');
    Lines.Add('-define(PROBE_INTERVAL_MS, 2000).');
    Lines.Add('');

    EmitCodePathSetup(Lines);

    Lines.Add('run_case(Label, CaseFun) ->');
    Lines.Add('    io:format("  ~s: ", [Label]),');
    Lines.Add('    try CaseFun() of');
    Lines.Add('        {ok, _} ->');
    Lines.Add('            io:format("OK~n"),');
    Lines.Add('            ok;');
    Lines.Add('        {error, Reason} ->');
    Lines.Add('            io:format("FAILED: ~p~n", [Reason]),');
    Lines.Add('            error;');
    Lines.Add('        Other ->');
    Lines.Add('            io:format("FAILED (unexpected): ~p~n", [Other]),');
    Lines.Add('            error');
    Lines.Add('    catch');
    Lines.Add('        Class:Reason:Stack ->');
    Lines.Add('            io:format("FAILED: ~p:~p~n  ~p~n",');
    Lines.Add('                      [Class, Reason, Stack]),');
    Lines.Add('            error');
    Lines.Add('    end.');
    Lines.Add('');

    Lines.Add('run_cases(Cases) ->');
    Lines.Add('    lists:foldl(');
    Lines.Add('        fun({Label, CaseFun}, {Passed, Failed}) ->');
    Lines.Add('            case run_case(Label, CaseFun) of');
    Lines.Add('                ok    -> {Passed + 1, Failed};');
    Lines.Add('                error -> {Passed, Failed + 1}');
    Lines.Add('            end');
    Lines.Add('        end,');
    Lines.Add('        {0, 0}, Cases).');
    Lines.Add('');

    Lines.Add('run_async(StartFun) ->');
    Lines.Add('    Self = self(),');
    Lines.Add('    StartFun(fun(Result) -> Self ! {async_result, Result} end),');
    Lines.Add('    receive');
    Lines.Add('        {async_result, Result} -> Result');
    Lines.Add('    after ?ASYNC_TIMEOUT_MS ->');
    Lines.Add('        {error, timeout}');
    Lines.Add('    end.');
    Lines.Add('');

    if Length(SupportedFuncs) > 0 then
    begin
      F := SupportedFuncs[0];
      ProbeApiName := MakeErlangFuncName(ApiNames[0]);
      ProbeArgs := BuildErlangDefaultArgs(F.Params);

      Lines.Add('probe_call() ->');
      if ProbeArgs = '' then
        Lines.Add('    case ?CALL_MODULE_ATOM:' + ProbeApiName.Text + '() of')
      else
        Lines.Add('    case ?CALL_MODULE_ATOM:' + ProbeApiName.Text + '(' + ProbeArgs.Text + ') of');
      Lines.Add('        {ok, _} -> ok;');
      Lines.Add('        {error, {service_error, _, _}} -> ok;');
      Lines.Add('        {error, _} = E -> E');
      Lines.Add('    end.');
      Lines.Add('');

      Lines.Add('wait_for_service_visible(RetriesLeft) ->');
      Lines.Add('    case probe_call() of');
      Lines.Add('        ok ->');
      Lines.Add('            io:format("[OK] service is visible.~n"),');
      Lines.Add('            ok;');
      Lines.Add('        _ when RetriesLeft =< 0 ->');
      Lines.Add('            io:format(standard_error,');
      Lines.Add('                      "[FATAL] service did not become visible within timeout.~n"),');
      Lines.Add('            error(service_not_visible);');
      Lines.Add('        _ ->');
      Lines.Add('            io:format("       waiting for service (retries left: ~p)~n",');
      Lines.Add('                      [RetriesLeft]),');
      Lines.Add('            timer:sleep(?PROBE_INTERVAL_MS),');
      Lines.Add('            wait_for_service_visible(RetriesLeft - 1)');
      Lines.Add('    end.');
      Lines.Add('');
    end;

    Lines.Add('main(Args) ->');
    Lines.Add('    ok = setup_code_path(' + ErlStrLit(NormalizedUnit) + '),');
    Lines.Add('    BaseUrl = case Args of');
    Lines.Add('        [] -> ?DEFAULT_BASE_URL;');
    Lines.Add('        [First | _] -> iolist_to_binary(First)');
    Lines.Add('    end,');
    Lines.Add('    ok = ?CALL_MODULE_ATOM:set_base_url(BaseUrl),');
    Lines.Add('    io:format("=== ' + NormalizedUnit.Text + ' HTTP/JSON call test ===~n"),');
    Lines.Add('    io:format("~n"),');
    Lines.Add('    io:format("Base URL: ~s~n", [BaseUrl]),');
    Lines.Add('    io:format("~n"),');
    Lines.Add('');

    if Length(SupportedFuncs) > 0 then
    begin
      Lines.Add('    ok = wait_for_service_visible(?PROBE_RETRIES),');
      Lines.Add('    io:format("~n"),');
      Lines.Add('');
    end;

    Lines.Add('    Cases = [');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildErlangDefaultArgs(F.Params);
      IsLast := (i = High(SupportedFuncs));

      SyncComma := ',';
      if IsLast then
        AsyncComma := ''
      else
        AsyncComma := ',';

      Lines.Add('        {"' + ApiName.Text + ' [sync]",');
      if DefaultArgs = '' then
        Lines.Add('         fun() -> ?CALL_MODULE_ATOM:' + MakeErlangFuncName(ApiName).Text + '() end}' + SyncComma)
      else
        Lines.Add('         fun() -> ?CALL_MODULE_ATOM:' + MakeErlangFuncName(ApiName).Text +
          '(' + DefaultArgs.Text + ') end}' + SyncComma);

      Lines.Add('        {"' + ApiName.Text + ' [async]",');
      if DefaultArgs = '' then
        Lines.Add('         fun() -> run_async(fun(Cb) -> ?CALL_MODULE_ATOM:' +
          MakeErlangFuncName(ApiName).Text + '_async(Cb) end) end}' + AsyncComma)
      else
        Lines.Add('         fun() -> run_async(fun(Cb) -> ?CALL_MODULE_ATOM:' +
          MakeErlangFuncName(ApiName).Text + '_async(' +
          DefaultArgs.Text + ', Cb) end) end}' + AsyncComma);
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('        %% (no supported routines)');

    Lines.Add('    ],');
    Lines.Add('');
    Lines.Add('    {Passed, Failed} = run_cases(Cases),');
    Lines.Add('');
    Lines.Add('    io:format("~n=== Summary ===~n"),');
    Lines.Add('    io:format("Passed: ~p~n", [Passed]),');
    Lines.Add('    io:format("Failed: ~p~n", [Failed]),');
    Lines.Add('');
    Lines.Add('    case Failed of');
    Lines.Add('        0 -> erlang:halt(0);');
    Lines.Add('        _ -> erlang:halt(1)');
    Lines.Add('    end.');
    Lines.Add('');

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
    'erlang', 'Erlang HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.escript', False,
    @GenerateHTTPServiceErlangTestCode);
  RegisterCodeGenEntry(
    'erlang', 'Erlang HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.escript', False,
    @GenerateHTTPCallErlangTestCode);
end.
