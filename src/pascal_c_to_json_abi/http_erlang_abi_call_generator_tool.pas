unit http_erlang_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallErlangCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

procedure EmitErlangHeader(Lines: TPascalStringList;
  const UnitName, BaseUrl: TP_String);
begin
  Lines.Add('%% -*- coding: utf-8 -*-');
  Lines.Add('');
end;

procedure EmitErlangModuleDecl(Lines: TPascalStringList;
  const ModuleName, BaseUrl: TP_String);
begin
  Lines.Add('-module(' + #39 + ModuleName.Text + #39 + ').');
  Lines.Add('');
  Lines.Add('-on_load(init/0).');
  Lines.Add('');
end;

procedure EmitErlangExports(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  ErlFuncName: TP_String;
begin
  Lines.Add('-export([set_base_url/1, get_base_url/0, set_timeout/1, get_timeout/0]).');
  Lines.Add('');

  if Length(SupportedFuncs) > 0 then
  begin
    Lines.Add('-export([');
    for i := 0 to High(SupportedFuncs) do
    begin
      ErlFuncName := MakeErlangFuncName(ApiNames[i]);
      if i > 0 then
        Lines.Add('    , ' + ErlFuncName.Text + '/' + MdInt(Length(SupportedFuncs[i].Params)).Text)
      else
        Lines.Add('      ' + ErlFuncName.Text + '/' + MdInt(Length(SupportedFuncs[i].Params)).Text);
    end;
    Lines.Add(']).');
    Lines.Add('');

    Lines.Add('-export([');
    for i := 0 to High(SupportedFuncs) do
    begin
      ErlFuncName := MakeErlangFuncName(ApiNames[i]);
      if i > 0 then
        Lines.Add('    , ' + ErlFuncName.Text + '_async/' + MdInt(Length(SupportedFuncs[i].Params) + 1).Text)
      else
        Lines.Add('      ' + ErlFuncName.Text + '_async/' + MdInt(Length(SupportedFuncs[i].Params) + 1).Text);
    end;
    Lines.Add(']).');
    Lines.Add('');
  end;
end;

procedure EmitErlangMacros(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('-define(DEFAULT_BASE_URL, ' + ErlBinLit(BaseUrl) + ').');
  Lines.Add('-define(DEFAULT_TIMEOUT_MS, 30000).');
  Lines.Add('');
end;

procedure EmitErlangInit(Lines: TPascalStringList);
begin
  Lines.Add('init() ->');
  Lines.Add('    try');
  Lines.Add('        {ok, _} = application:ensure_all_started(inets),');
  Lines.Add('        {ok, _} = application:ensure_all_started(ssl),');
  Lines.Add('        ok');
  Lines.Add('    catch');
  Lines.Add('        _:_ -> ok');
  Lines.Add('    end.');
  Lines.Add('');
end;

procedure EmitErlangConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('set_base_url(Url) when is_binary(Url) ->');
  Lines.Add('    persistent_term:put({?MODULE, base_url}, Url),');
  Lines.Add('    ok;');
  Lines.Add('set_base_url(Url) when is_list(Url) ->');
  Lines.Add('    persistent_term:put({?MODULE, base_url}, iolist_to_binary(Url)),');
  Lines.Add('    ok.');
  Lines.Add('');
  Lines.Add('get_base_url() ->');
  Lines.Add('    persistent_term:get({?MODULE, base_url}, ?DEFAULT_BASE_URL).');
  Lines.Add('');
  Lines.Add('set_timeout(Ms) when is_integer(Ms), Ms >= 0 ->');
  Lines.Add('    persistent_term:put({?MODULE, timeout_ms}, Ms),');
  Lines.Add('    ok.');
  Lines.Add('');
  Lines.Add('get_timeout() ->');
  Lines.Add('    persistent_term:get({?MODULE, timeout_ms}, ?DEFAULT_TIMEOUT_MS).');
  Lines.Add('');
end;

procedure EmitErlangTransport(Lines: TPascalStringList);
begin
  Lines.Add('call(ApiName, Args) ->');
  Lines.Add('    call(ApiName, Args, get_timeout()).');
  Lines.Add('');
  Lines.Add('call(ApiName, Args, Timeout) when is_binary(ApiName), is_list(Args),');
  Lines.Add('                                   is_integer(Timeout), Timeout >= 0 ->');
  Lines.Add('    Url = build_url(ApiName),');
  Lines.Add('    Body = iolist_to_binary(json:encode(#{<<"args">> => Args})),');
  Lines.Add('    HttpOpts = [{timeout, Timeout}, {connect_timeout, 5000}],');
  Lines.Add('    Opts = [{body_format, binary}],');
  Lines.Add('    case httpc:request(');
  Lines.Add('            post,');
  Lines.Add('            {binary_to_list(Url),');
  Lines.Add('             [{"content-type", "application/json; charset=utf-8"}],');
  Lines.Add('             "application/json",');
  Lines.Add('             Body},');
  Lines.Add('            HttpOpts,');
  Lines.Add('            Opts) of');
  Lines.Add('        {ok, {{_, 200, _}, _RespHeaders, RespBody}} ->');
  Lines.Add('            parse_response(RespBody);');
  Lines.Add('        {ok, {{_, StatusCode, _}, _RespHeaders, RespBody}} ->');
  Lines.Add('            {error, {http_status, StatusCode, RespBody}};');
  Lines.Add('        {error, Reason} ->');
  Lines.Add('            {error, {http_error, Reason}}');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('build_url(ApiName) ->');
  Lines.Add('    Base0 = get_base_url(),');
  Lines.Add('    Base1 = strip_trailing_slash(Base0),');
  Lines.Add('    <<Base1/binary, "/", ApiName/binary>>.');
  Lines.Add('');
  Lines.Add('strip_trailing_slash(<<>>) -> <<>>;');
  Lines.Add('strip_trailing_slash(Bin) ->');
  Lines.Add('    case binary:last(Bin) of');
  Lines.Add('        $/ -> strip_trailing_slash(binary:part(Bin, 0, byte_size(Bin) - 1));');
  Lines.Add('        _  -> Bin');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('strip_trailing_nul(<<>>) -> <<>>;');
  Lines.Add('strip_trailing_nul(Bin) ->');
  Lines.Add('    case binary:last(Bin) of');
  Lines.Add('        0 -> binary:part(Bin, 0, byte_size(Bin) - 1);');
  Lines.Add('        _ -> Bin');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('parse_response(RespBody) ->');
  Lines.Add('    try json:decode(strip_trailing_nul(RespBody)) of');
  Lines.Add('        #{<<"code">> := 0, <<"result">> := R} ->');
  Lines.Add('            {ok, R};');
  Lines.Add('        #{<<"code">> := 0} ->');
  Lines.Add('            {ok, null};');
  Lines.Add('        #{<<"code">> := C, <<"error">> := E} ->');
  Lines.Add('            {error, {service_error, C, E}};');
  Lines.Add('        #{<<"code">> := C} ->');
  Lines.Add('            {error, {service_error, C, <<"no error message">>}};');
  Lines.Add('        Other ->');
  Lines.Add('            {error, {unexpected_response, Other}}');
  Lines.Add('    catch');
  Lines.Add('        _:Reason ->');
  Lines.Add('            {error, {json_decode_failed, Reason}}');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('call_async(ApiName, Args, Callback) when is_function(Callback, 1) ->');
  Lines.Add('    _ = spawn(fun() ->');
  Lines.Add('        R = call(ApiName, Args),');
  Lines.Add('        try Callback(R) catch _:_ -> ok end');
  Lines.Add('    end),');
  Lines.Add('    ok.');
  Lines.Add('');
end;

procedure EmitErlangFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ErlFuncName, ParamList, ArgList: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ErlFuncName := MakeErlangFuncName(ApiName);
    ParamList := BuildErlangParamList(F.Params);
    ArgList := BuildErlangArgList(F.Params);

    if Length(F.Params) = 0 then
      Lines.Add(ErlFuncName.Text + '() ->')
    else
      Lines.Add(ErlFuncName.Text + '(' + ParamList.Text + ') ->');
    Lines.Add('    call(' + ErlBinLit(ApiName) + ', [' + ArgList.Text + ']).');
    Lines.Add('');

    if Length(F.Params) = 0 then
      Lines.Add(ErlFuncName.Text + '_async(Callback) when is_function(Callback, 1) ->')
    else
      Lines.Add(ErlFuncName.Text + '_async(' + ParamList.Text + ', Callback) when is_function(Callback, 1) ->');
    Lines.Add('    call_async(' + ErlBinLit(ApiName) + ', [' + ArgList.Text + '], Callback).');
    Lines.Add('');
  end;
end;

function GenerateHTTPCallErlangCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallErlangCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallErlangCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  ModuleName := NormalizedUnit + '_http_json_call';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitErlangHeader(Lines, UnitName, BaseUrl);
    EmitErlangModuleDecl(Lines, ModuleName, BaseUrl);
    EmitErlangExports(Lines, SupportedFuncs, ApiNames);
    EmitErlangMacros(Lines, BaseUrl);
    EmitErlangInit(Lines);
    EmitErlangConfig(Lines, BaseUrl);
    EmitErlangTransport(Lines);
    EmitErlangFunctions(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated Erlang call module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'erlang', 'Erlang HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call.erl', False,
    @GenerateHTTPCallErlangCode);
end.
