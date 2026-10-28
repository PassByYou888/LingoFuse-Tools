unit erlang_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses SysUtils, Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceErlangCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

type
  TSystemStringArray = array of SystemString;
  TArryFunctionStructure = array of TFunctionStructure;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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
      Result := Result + '\' + 'x{' + IntToHex(n, 4) + '}';
  end;
  Result := Result + '">>';
end;

function DefaultResultFor(const T: TP_String): SystemString;
begin
  if IsStringABIType(T) then
    Result := '<<>>'
  else if IsFloatABIType(T) then
    Result := '0.0'
  else
    Result := '0';
end;

function ArgVar(const Index: integer): SystemString;
begin
  Result := 'P' + umlIntToStr(Index + 1).Text;
end;

function StubVar(const Index: integer): SystemString;
begin
  Result := '_P' + umlIntToStr(Index + 1).Text;
end;

function BuildCallArgs(const F: TFunctionStructure; const StubForm: boolean): SystemString;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    if StubForm then
      Result := Result + StubVar(i)
    else
      Result := Result + ArgVar(i);
  end;
end;

function BuildParamVarList(const F: TFunctionStructure): SystemString;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ArgVar(i);
  end;
end;

function DecodeFuncFor(const T: TP_String): SystemString;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'decode_int32'
  else if T.Same('int64') then
    Result := 'decode_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'decode_uint32'
  else if T.Same('word') then
    Result := 'decode_uint16'
  else if T.Same('smallint') then
    Result := 'decode_int16'
  else if T.Same('byte') then
    Result := 'decode_uint8'
  else if T.Same('uint64') then
    Result := 'decode_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'decode_double'
  else if T.Same('single') then
    Result := 'decode_single'
  else if IsStringABIType(T) then
    Result := 'decode_string'
  else
    Result := '';
end;

function EncodeOkFuncFor(const T: TP_String): SystemString;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'encode_ok_int32'
  else if T.Same('int64') then
    Result := 'encode_ok_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'encode_ok_uint32'
  else if T.Same('word') then
    Result := 'encode_ok_uint16'
  else if T.Same('smallint') then
    Result := 'encode_ok_int16'
  else if T.Same('byte') then
    Result := 'encode_ok_uint8'
  else if T.Same('uint64') then
    Result := 'encode_ok_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'encode_ok_double'
  else if T.Same('single') then
    Result := 'encode_ok_single'
  else if IsStringABIType(T) then
    Result := 'encode_ok_string'
  else
    Result := '';
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

procedure EmitRegisterBody(Lines: TPascalStringList;
  const Funcs: TArryFunctionStructure; const ApiNames: TSystemStringArray;
  const IsP2P: boolean);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, FailedVar, RegFn: SystemString;
  S, SumExpr: SystemString;
begin
  Lines.Add('    F0 = 0,');
  SumExpr := 'F0';
  for i := 0 to High(Funcs) do
  begin
    F := Funcs[i];
    ApiName := ApiNames[i];
    FailedVar := 'F' + umlIntToStr(i + 1).Text;

    if IsP2P then
    begin
      if F.IsFunction then
        RegFn := 'lingofuse:register_p2p_call_sync'
      else
        RegFn := 'lingofuse:register_p2p_notify';
      S := '    ' + FailedVar + ' = lf_reg_or_zero(' + RegFn + '(' +
        ErlangBinLit(ApiName) + ', ' + ErlangBinLit('api for ' + ApiName) +
        ', self(), #{with_identity => true})),';
    end
    else
    begin
      if F.IsFunction then
        RegFn := 'lingofuse:register_call_sync'
      else
        RegFn := 'lingofuse:register_notify';
      S := '    ' + FailedVar + ' = lf_reg_or_zero(' + RegFn + '(' +
        'AppHnd, ' + ErlangBinLit(ApiName) + ', ' +
        ErlangBinLit('api for ' + ApiName) +
        ', self(), #{with_identity => true})),';
    end;
    Lines.Add(S);
    SumExpr := SumExpr + ' + ' + FailedVar;
  end;
  Lines.Add('    ' + SumExpr + '.');
end;

procedure EmitDispatchCallClause(Lines: TPascalStringList;
  const ApiName: SystemString);
var
  S: SystemString;
begin
  S := 'lf_dispatch_call(' + ErlangBinLit(ApiName) +
    ', Ref, Payload, Identity) ->';
  Lines.Add(S);
  S := '    handle_call_' + ApiName + '(Ref, Payload, Identity);';
  Lines.Add(S);
end;

procedure EmitDispatchNotifyClause(Lines: TPascalStringList;
  const ApiName: SystemString);
var
  S: SystemString;
begin
  S := 'lf_dispatch_notify(' + ErlangBinLit(ApiName) +
    ', Payload, Identity) ->';
  Lines.Add(S);
  S := '    handle_notify_' + ApiName + '(Payload, Identity);';
  Lines.Add(S);
end;

procedure EmitCallHandler(Lines: TPascalStringList; const ApiName: SystemString;
  const F: TFunctionStructure);
var
  S, EncodeFn: SystemString;
begin
  S := 'handle_call_' + ApiName + '(Ref, Payload, _Identity) ->';
  Lines.Add(S);
  Lines.Add('    try');

  if Length(F.Params) = 0 then
  begin
    Lines.Add('        _ = Payload,');
    S := '        _Ret = internal_call_' + ApiName + '(),';
    Lines.Add(S);
    EncodeFn := EncodeOkFuncFor(F.ReturnType);
    S := '        _ = lingofuse:reply(Ref, ' + EncodeFn + '(_Ret)),';
    Lines.Add(S);
    Lines.Add('        ok');
  end
  else
  begin
    S := '        case decode_params_' + ApiName + '(Payload) of';
    Lines.Add(S);
    S := '            {ok, {' + BuildParamVarList(F) + '}, _} ->';
    Lines.Add(S);
    S := '                _Ret = internal_call_' + ApiName + '(' +
      BuildCallArgs(F, False) + '),';
    Lines.Add(S);
    EncodeFn := EncodeOkFuncFor(F.ReturnType);
    S := '                _ = lingofuse:reply(Ref, ' + EncodeFn + '(_Ret)),';
    Lines.Add(S);
    Lines.Add('                ok;');
    Lines.Add('            {error, E} ->');
    Lines.Add('                _ = lingofuse:reply(Ref, encode_error(E)),');
    Lines.Add('                ok');
    Lines.Add('        end');
  end;

  Lines.Add('    catch');
  Lines.Add('        _:_ ->');
  Lines.Add('            _ = lingofuse:reply(Ref, encode_error(<<"internal error">>)),');
  Lines.Add('            ok');
  Lines.Add('    end.');
end;

procedure EmitNotifyHandler(Lines: TPascalStringList; const ApiName: SystemString;
  const F: TFunctionStructure);
var
  S: SystemString;
begin
  S := 'handle_notify_' + ApiName + '(Payload, _Identity) ->';
  Lines.Add(S);
  Lines.Add('    try');

  if Length(F.Params) = 0 then
  begin
    Lines.Add('        _ = Payload,');
    S := '        _ = internal_call_' + ApiName + '(),';
    Lines.Add(S);
    Lines.Add('        ok');
  end
  else
  begin
    S := '        case decode_params_' + ApiName + '(Payload) of';
    Lines.Add(S);
    S := '            {ok, {' + BuildParamVarList(F) + '}, _} ->';
    Lines.Add(S);
    S := '                _ = internal_call_' + ApiName + '(' +
      BuildCallArgs(F, False) + '),';
    Lines.Add(S);
    Lines.Add('                ok;');
    Lines.Add('            {error, _} ->');
    Lines.Add('                ok');
    Lines.Add('        end');
  end;

  Lines.Add('    catch');
  Lines.Add('        _:_ -> ok');
  Lines.Add('    end.');
end;

procedure EmitDecodeParamsFunc(Lines: TPascalStringList;
  const ApiName: SystemString; const F: TFunctionStructure);
var
  i: integer;
  S, DecodeFn, ParamVar, RestVar, NextRestVar: SystemString;
begin
  S := 'decode_params_' + ApiName + '(Bin) ->';
  Lines.Add(S);
  Lines.Add('    try');

  if Length(F.Params) = 0 then
  begin
    Lines.Add('        {ok, {}, Bin}');
  end
  else
  begin
    RestVar := 'Bin';
    for i := 0 to High(F.Params) do
    begin
      DecodeFn := DecodeFuncFor(F.Params[i].PascalType);
      ParamVar := 'P' + umlIntToStr(i + 1).Text;
      NextRestVar := 'R' + umlIntToStr(i + 1).Text;
      S := '        {' + ParamVar + ', ' + NextRestVar + '} = ' +
        DecodeFn + '(' + RestVar + '),';
      Lines.Add(S);
      RestVar := NextRestVar;
    end;
    S := '        {ok, {' + BuildParamVarList(F) + '}, ' + RestVar + '}';
    Lines.Add(S);
  end;

  Lines.Add('    catch');
  Lines.Add('        throw:{decode_error, E} -> {error, E}');
  Lines.Add('    end.');
  Lines.Add('');
end;

procedure EmitInternalStub(Lines: TPascalStringList; const ApiName: SystemString;
  const F: TFunctionStructure);
var
  S: SystemString;
begin
  if Length(F.Params) > 0 then
    S := 'internal_call_' + ApiName + '(' + BuildCallArgs(F, True) + ') ->'
  else
    S := 'internal_call_' + ApiName + '() ->';
  Lines.Add(S);
  if F.IsFunction then
  begin
    S := '    ' + DefaultResultFor(F.ReturnType) + '.';
    Lines.Add(S);
  end
  else
    Lines.Add('    ok.');
end;

procedure EmitNowarnPragma(Lines: TPascalStringList;
  const Funcs: TArryFunctionStructure);
var
  Items: TPascalStringList;
  i: integer;
  ApiName: SystemString;
begin
  Items := TPascalStringList.Create;
  try
    Items.Add('{decode_int8,1}');
    Items.Add('{decode_uint8,1}');
    Items.Add('{decode_int16,1}');
    Items.Add('{decode_uint16,1}');
    Items.Add('{decode_int32,1}');
    Items.Add('{decode_uint32,1}');
    Items.Add('{decode_int64,1}');
    Items.Add('{decode_uint64,1}');
    Items.Add('{decode_single,1}');
    Items.Add('{decode_double,1}');
    Items.Add('{decode_string,1}');
    Items.Add('{encode_ok_void,0}');
    Items.Add('{encode_ok_int8,1}');
    Items.Add('{encode_ok_uint8,1}');
    Items.Add('{encode_ok_int16,1}');
    Items.Add('{encode_ok_uint16,1}');
    Items.Add('{encode_ok_int32,1}');
    Items.Add('{encode_ok_uint32,1}');
    Items.Add('{encode_ok_int64,1}');
    Items.Add('{encode_ok_uint64,1}');
    Items.Add('{encode_ok_single,1}');
    Items.Add('{encode_ok_double,1}');
    Items.Add('{encode_ok_string,1}');
    Items.Add('{encode_error,1}');
    Items.Add('{lf_reg_or_zero,1}');
    for i := 0 to High(Funcs) do
    begin
      ApiName := MakeApiName(Funcs[i].Name);
      Items.Add('{decode_params_' + ApiName + ',1}');
    end;
    Lines.Add('-compile({nowarn_unused_function, [');
    for i := 0 to Items.Count - 1 do
    begin
      if i < Items.Count - 1 then
        Lines.Add('    ' + Items[i] + ',')
      else
        Lines.Add('    ' + Items[i]);
    end;
    Lines.Add(']}).');
    Lines.Add('');
  finally
    Items.Free;
  end;
end;

procedure EmitCommonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('lf_reg_or_zero(ok) -> 0;');
  Lines.Add('lf_reg_or_zero({error, _}) -> 1;');
  Lines.Add('lf_reg_or_zero(_) -> 1.');
  Lines.Add('');
  Lines.Add('decode_int8(<<V:8/little-signed, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_int8(_) -> throw({decode_error, <<"int8">>}).');
  Lines.Add('');
  Lines.Add('decode_uint8(<<V:8/unsigned, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_uint8(_) -> throw({decode_error, <<"uint8">>}).');
  Lines.Add('');
  Lines.Add('decode_int16(<<V:16/little-signed, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_int16(_) -> throw({decode_error, <<"int16">>}).');
  Lines.Add('');
  Lines.Add('decode_uint16(<<V:16/little-unsigned, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_uint16(_) -> throw({decode_error, <<"uint16">>}).');
  Lines.Add('');
  Lines.Add('decode_int32(<<V:32/little-signed, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_int32(_) -> throw({decode_error, <<"int32">>}).');
  Lines.Add('');
  Lines.Add('decode_uint32(<<V:32/little-unsigned, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_uint32(_) -> throw({decode_error, <<"uint32">>}).');
  Lines.Add('');
  Lines.Add('decode_int64(<<V:64/little-signed, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_int64(_) -> throw({decode_error, <<"int64">>}).');
  Lines.Add('');
  Lines.Add('decode_uint64(<<V:64/little-unsigned, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_uint64(_) -> throw({decode_error, <<"uint64">>}).');
  Lines.Add('');
  Lines.Add('decode_single(<<V:32/little-float, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_single(_) -> throw({decode_error, <<"single">>}).');
  Lines.Add('');
  Lines.Add('decode_double(<<V:64/little-float, Rest/binary>>) -> {V, Rest};');
  Lines.Add('decode_double(_) -> throw({decode_error, <<"double">>}).');
  Lines.Add('');
  Lines.Add('decode_string(Bin) ->');
  Lines.Add('    case binary:match(Bin, <<0>>) of');
  Lines.Add('        {Pos, 1} ->');
  Lines.Add('            <<S:Pos/binary, 0, Rest/binary>> = Bin,');
  Lines.Add('            {S, Rest};');
  Lines.Add('        nomatch ->');
  Lines.Add('            throw({decode_error, <<"string">>})');
  Lines.Add('    end.');
  Lines.Add('');
  Lines.Add('encode_ok_void() -> <<0>>.');
  Lines.Add('');
  Lines.Add('encode_ok_int8(V) -> <<0, V:8/little-signed>>.');
  Lines.Add('encode_ok_uint8(V) -> <<0, V:8/unsigned>>.');
  Lines.Add('encode_ok_int16(V) -> <<0, V:16/little-signed>>.');
  Lines.Add('encode_ok_uint16(V) -> <<0, V:16/little-unsigned>>.');
  Lines.Add('encode_ok_int32(V) -> <<0, V:32/little-signed>>.');
  Lines.Add('encode_ok_uint32(V) -> <<0, V:32/little-unsigned>>.');
  Lines.Add('encode_ok_int64(V) -> <<0, V:64/little-signed>>.');
  Lines.Add('encode_ok_uint64(V) -> <<0, V:64/little-unsigned>>.');
  Lines.Add('encode_ok_single(V) -> <<0, V:32/little-float>>.');
  Lines.Add('encode_ok_double(V) -> <<0, V:64/little-float>>.');
  Lines.Add('encode_ok_string(S) -> <<0, S/binary, 0>>.');
  Lines.Add('');
  Lines.Add('encode_error(Msg) -> <<255, Msg/binary, 0>>.');
end;

function GenerateABIServiceErlangCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  ApiNames: TSystemStringArray;
  UnitName, NormalizedUnit, AppName, AppDesc: SystemString;
  F: TFunctionStructure;
  ApiName: SystemString;
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
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Erlang ABI service module for unit "%s"', [UnitName]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := AssignUniqueApiNames(SupportedFuncs);

  Lines := TPascalStringList.Create;
  try
    S := '-module(' + ErlangQuotedAtom(NormalizedUnit + '_abi_service') + ').';
    Lines.Add(S);
    Lines.Add('');
    Lines.Add('-export([register_all_apis/1,');
    Lines.Add('         register_all_p2p_apis/0,');
    Lines.Add('         create_and_register_app/0,');
    Lines.Add('         lf_dispatch_call/4,');
    Lines.Add('         lf_dispatch_notify/3]).');
    Lines.Add('');
    S := '-define(DEFAULT_APP_NAME, ' + ErlangBinLit(AppName) + ').';
    Lines.Add(S);
    S := '-define(DEFAULT_APP_DESC, ' + ErlangBinLit(AppDesc) + ').';
    Lines.Add(S);
    Lines.Add('');

    EmitNowarnPragma(Lines, SupportedFuncs);

    Lines.Add('register_all_apis(AppHnd) when is_reference(AppHnd) ->');
    EmitRegisterBody(Lines, SupportedFuncs, ApiNames, False);
    Lines.Add('');

    Lines.Add('register_all_p2p_apis() ->');
    EmitRegisterBody(Lines, SupportedFuncs, ApiNames, True);
    Lines.Add('');

    Lines.Add('create_and_register_app() ->');
    Lines.Add('    {ok, App} = lingofuse:create_app(?DEFAULT_APP_NAME, ?DEFAULT_APP_DESC),');
    Lines.Add('    _ = register_all_apis(App),');
    Lines.Add('    {ok, App}.');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      if F.IsFunction then
        EmitDispatchCallClause(Lines, ApiName);
    end;
    Lines.Add('lf_dispatch_call(_OtherApi, Ref, _Payload, _Identity) ->');
    Lines.Add('    _ = lingofuse:reply(Ref, encode_error(<<"unknown api">>)),');
    Lines.Add('    ok.');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      if not F.IsFunction then
        EmitDispatchNotifyClause(Lines, ApiName);
    end;
    Lines.Add('lf_dispatch_notify(_OtherApi, _Payload, _Identity) ->');
    Lines.Add('    ok.');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      if F.IsFunction then
        EmitCallHandler(Lines, ApiName, F)
      else
        EmitNotifyHandler(Lines, ApiName, F);
      Lines.Add('');
    end;

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      EmitDecodeParamsFunc(Lines, ApiName, F);
    end;

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      EmitInternalStub(Lines, ApiName, F);
      Lines.Add('');
    end;

    EmitCommonHelpers(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines for Erlang ABI service module.', [Lines.Count]));
  finally
    if Result = nil then
      Lines.Free;
  end;
end;

initialization
  RegisterGenerator('erlang', 'xxx_abi_service.erl', gkService,
    'Erlang ABI service module', @GenerateABIServiceErlangCode);

end.
