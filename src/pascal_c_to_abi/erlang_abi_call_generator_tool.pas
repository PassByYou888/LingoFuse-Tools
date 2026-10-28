unit erlang_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses SysUtils, Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallErlangCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

type
  TSystemStringArray = array of SystemString;
  TArryFunctionStructure = array of TFunctionStructure;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function EncodeParamExpr(const T: TP_String; const VarName: SystemString): SystemString;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := '<<' + VarName + ':32/little-signed>>'
  else if T.Same('int64') then
    Result := '<<' + VarName + ':64/little-signed>>'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := '<<' + VarName + ':32/little-unsigned>>'
  else if T.Same('word') then
    Result := '<<' + VarName + ':16/little-unsigned>>'
  else if T.Same('smallint') then
    Result := '<<' + VarName + ':16/little-signed>>'
  else if T.Same('byte') then
    Result := '<<' + VarName + ':8/unsigned>>'
  else if T.Same('uint64') then
    Result := '<<' + VarName + ':64/little-unsigned>>'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := '<<' + VarName + ':64/little-float>>'
  else if T.Same('single') then
    Result := '<<' + VarName + ':32/little-float>>'
  else if IsStringABIType(T) then
    Result := 'lf_enc_string(' + VarName + ')'
  else
    Result := '';
end;

function DecodeFuncName(const T: TP_String): SystemString;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'lf_decode_ret_int32'
  else if T.Same('int64') then
    Result := 'lf_decode_ret_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'lf_decode_ret_uint32'
  else if T.Same('word') then
    Result := 'lf_decode_ret_uint16'
  else if T.Same('smallint') then
    Result := 'lf_decode_ret_int16'
  else if T.Same('byte') then
    Result := 'lf_decode_ret_uint8'
  else if T.Same('uint64') then
    Result := 'lf_decode_ret_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'lf_decode_ret_double'
  else if T.Same('single') then
    Result := 'lf_decode_ret_single'
  else if IsStringABIType(T) then
    Result := 'lf_decode_ret_string'
  else
    Result := '';
end;

function BuildBodyIolist(const F: TFunctionStructure): SystemString;
var
  i: integer;
  Parts: SystemString;
begin
  if Length(F.Params) = 0 then
  begin
    Result := '<<>>';
    Exit;
  end;
  Parts := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then
      Parts := Parts + ', ';
    Parts := Parts + EncodeParamExpr(F.Params[i].PascalType,
      'P' + umlIntToStr(i + 1).Text);
  end;
  Result := 'iolist_to_binary([' + Parts + '])';
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
    Result := Result + 'P' + umlIntToStr(i + 1).Text;
  end;
end;

function SyncArity(const F: TFunctionStructure): integer;
begin
  Result := 1 + Length(F.Params);
end;

function AsyncArity(const F: TFunctionStructure): integer;
begin
  Result := 1 + Length(F.Params) + 1;
end;

procedure EmitSyncFunc(Lines: TPascalStringList;
  const FuncName, TargetKind, TargetVar, ApiName: SystemString;
  const F: TFunctionStructure; const Decoder: SystemString);
var
  Head, Body: SystemString;
begin
  Head := ErlangQuotedAtom(FuncName) + '(' + TargetVar;
  if Length(F.Params) > 0 then
    Head := Head + ', ' + BuildParamVarList(F);
  Head := Head + ') ->';
  Lines.Add(Head);
  Body := BuildBodyIolist(F);
  Lines.Add('    lf_do_call_sync(' + TargetKind + ', ' + TargetVar + ', ' +
    ErlangBinLit(ApiName) + ',');
  Lines.Add('        ' + Body + ',');
  Lines.Add('        fun ' + Decoder + '/1).');
  Lines.Add('');
end;

procedure EmitAsyncFunc(Lines: TPascalStringList;
  const FuncName, TargetKind, TargetVar, ApiName: SystemString;
  const F: TFunctionStructure; const Decoder: SystemString);
var
  Head, Body: SystemString;
begin
  Head := ErlangQuotedAtom(FuncName) + '(' + TargetVar;
  if Length(F.Params) > 0 then
    Head := Head + ', ' + BuildParamVarList(F);
  Head := Head + ', Callback) ->';
  Lines.Add(Head);
  Body := BuildBodyIolist(F);
  Lines.Add('    lf_do_call_async(' + TargetKind + ', ' + TargetVar + ', ' +
    ErlangBinLit(ApiName) + ',');
  Lines.Add('        ' + Body + ',');
  Lines.Add('        fun ' + Decoder + '/1,');
  Lines.Add('        Callback).');
  Lines.Add('');
end;

procedure EmitNotifyProc(Lines: TPascalStringList;
  const FuncName, TargetKind, TargetVar, ApiName: SystemString;
  const F: TFunctionStructure);
var
  Head, Body: SystemString;
begin
  Head := ErlangQuotedAtom(FuncName) + '(' + TargetVar;
  if Length(F.Params) > 0 then
    Head := Head + ', ' + BuildParamVarList(F);
  Head := Head + ') ->';
  Lines.Add(Head);
  Body := BuildBodyIolist(F);
  Lines.Add('    lf_do_notify(' + TargetKind + ', ' + TargetVar + ', ' +
    ErlangBinLit(ApiName) + ',');
  Lines.Add('        ' + Body + ').');
  Lines.Add('');
end;

procedure EmitCommonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('-define(ABI_TIMEOUT_MS, 5000).');
  Lines.Add('');

  Lines.Add('-compile({nowarn_unused_function, [');
  Lines.Add('    {lf_enc_string, 1},');
  Lines.Add('    {lf_decode_error, 1},');
  Lines.Add('    {lf_decode_ret_int32, 1},');
  Lines.Add('    {lf_decode_ret_int64, 1},');
  Lines.Add('    {lf_decode_ret_uint32, 1},');
  Lines.Add('    {lf_decode_ret_uint16, 1},');
  Lines.Add('    {lf_decode_ret_int16, 1},');
  Lines.Add('    {lf_decode_ret_uint8, 1},');
  Lines.Add('    {lf_decode_ret_uint64, 1},');
  Lines.Add('    {lf_decode_ret_single, 1},');
  Lines.Add('    {lf_decode_ret_double, 1},');
  Lines.Add('    {lf_decode_ret_string, 1},');
  Lines.Add('    {lf_do_call_sync, 5},');
  Lines.Add('    {lf_do_call_async, 6},');
  Lines.Add('    {lf_do_notify, 4},');
  Lines.Add('    {lf_raw_call_sync, 3},');
  Lines.Add('    {lf_raw_call_async, 4}');
  Lines.Add(']}).');
  Lines.Add('');

  Lines.Add('lf_enc_string(Bin) when is_binary(Bin) -> <<Bin/binary, 0>>;');
  Lines.Add('lf_enc_string(List) when is_list(List) ->');
  Lines.Add('    case unicode:characters_to_binary(List) of');
  Lines.Add('        B when is_binary(B) -> <<B/binary, 0>>;');
  Lines.Add('        _ -> erlang:error(badarg)');
  Lines.Add('    end;');
  Lines.Add('lf_enc_string(_) -> erlang:error(badarg).');
  Lines.Add('');

  Lines.Add('lf_decode_error(Rest) ->');
  Lines.Add('    case binary:match(Rest, <<0>>) of');
  Lines.Add('        {Pos, 1} -> {error, binary:part(Rest, 0, Pos)};');
  Lines.Add('        nomatch -> {error, Rest}');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_int32(<<0, V:32/little-signed, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_int32(<<0, _/binary>>) -> {error, <<"truncated int32">>};');
  Lines.Add('lf_decode_ret_int32(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_int32(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_int32(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_int64(<<0, V:64/little-signed, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_int64(<<0, _/binary>>) -> {error, <<"truncated int64">>};');
  Lines.Add('lf_decode_ret_int64(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_int64(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_int64(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_uint32(<<0, V:32/little-unsigned, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_uint32(<<0, _/binary>>) -> {error, <<"truncated uint32">>};');
  Lines.Add('lf_decode_ret_uint32(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_uint32(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_uint32(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_uint16(<<0, V:16/little-unsigned, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_uint16(<<0, _/binary>>) -> {error, <<"truncated uint16">>};');
  Lines.Add('lf_decode_ret_uint16(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_uint16(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_uint16(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_int16(<<0, V:16/little-signed, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_int16(<<0, _/binary>>) -> {error, <<"truncated int16">>};');
  Lines.Add('lf_decode_ret_int16(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_int16(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_int16(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_uint8(<<0, V:8/unsigned, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_uint8(<<0, _/binary>>) -> {error, <<"truncated uint8">>};');
  Lines.Add('lf_decode_ret_uint8(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_uint8(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_uint8(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_uint64(<<0, V:64/little-unsigned, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_uint64(<<0, _/binary>>) -> {error, <<"truncated uint64">>};');
  Lines.Add('lf_decode_ret_uint64(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_uint64(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_uint64(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_single(<<0, V:32/little-float, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_single(<<0, _/binary>>) -> {error, <<"truncated single">>};');
  Lines.Add('lf_decode_ret_single(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_single(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_single(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_double(<<0, V:64/little-float, _/binary>>) -> {ok, V};');
  Lines.Add('lf_decode_ret_double(<<0, _/binary>>) -> {error, <<"truncated double">>};');
  Lines.Add('lf_decode_ret_double(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_double(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_double(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_decode_ret_string(<<0, Rest/binary>>) ->');
  Lines.Add('    case binary:match(Rest, <<0>>) of');
  Lines.Add('        {Pos, 1} -> {ok, binary:part(Rest, 0, Pos)};');
  Lines.Add('        nomatch -> {ok, Rest}');
  Lines.Add('    end;');
  Lines.Add('lf_decode_ret_string(<<255, Rest/binary>>) -> lf_decode_error(Rest);');
  Lines.Add('lf_decode_ret_string(<<S, _/binary>>) -> {error, {unexpected_status, S}};');
  Lines.Add('lf_decode_ret_string(_) -> {error, <<"empty response">>}.');
  Lines.Add('');

  Lines.Add('lf_do_call_sync(Kind, Target, Api, Body, Decoder) ->');
  Lines.Add('    {ok, Data} = lingofuse:create_data(Api),');
  Lines.Add('    try');
  Lines.Add('        case lingofuse:write_buffer(Data, Body) of');
  Lines.Add('            {ok, _} -> ok;');
  Lines.Add('            {error, WriteReason} -> erlang:error({write_failed, WriteReason})');
  Lines.Add('        end,');
  Lines.Add('        case lf_raw_call_sync(Kind, Target, Data) of');
  Lines.Add('            {ok, ResHnd} ->');
  Lines.Add('                try');
  Lines.Add('                    ok = lingofuse:set_pos(ResHnd, 0),');
  Lines.Add('                    {ok, Sz} = lingofuse:get_size(ResHnd),');
  Lines.Add('                    case Sz of');
  Lines.Add('                        0 -> {error, <<"empty response">>};');
  Lines.Add('                        _ ->');
  Lines.Add('                            {ok, Bin} = lingofuse:read_buffer(ResHnd, Sz),');
  Lines.Add('                            Decoder(Bin)');
  Lines.Add('                    end');
  Lines.Add('                after lingofuse:free_data(ResHnd) end;');
  Lines.Add('            {error, CallReason} -> {error, CallReason}');
  Lines.Add('        end');
  Lines.Add('    after lingofuse:free_data(Data) end.');
  Lines.Add('');

  Lines.Add('lf_raw_call_sync(app, App, Data) -> lingofuse:call(App, Data, ?ABI_TIMEOUT_MS);');
  Lines.Add('lf_raw_call_sync(uid, Uid, Data) -> lingofuse:uid_call(Uid, Data, ?ABI_TIMEOUT_MS);');
  Lines.Add('lf_raw_call_sync(p2p, P2p, Data) -> lingofuse:p2pname_call(P2p, Data, ?ABI_TIMEOUT_MS).');
  Lines.Add('');

  Lines.Add('lf_do_call_async(Kind, Target, Api, Body, Decoder, Callback) ->');
  Lines.Add('    {ok, Data} = lingofuse:create_data(Api),');
  Lines.Add('    case lingofuse:write_buffer(Data, Body) of');
  Lines.Add('        {ok, _} ->');
  Lines.Add('            Collector = spawn(fun() ->');
  Lines.Add('                receive');
  Lines.Add('                    {lf_async_result, _Ref, {ok, Bin}} ->');
  Lines.Add('                        Callback(Decoder(Bin));');
  Lines.Add('                    {lf_async_result, _Ref, {error, AsyncReason}} ->');
  Lines.Add('                        Callback({error, AsyncReason});');
  Lines.Add('                    {lf_async_result, _Ref, AsyncOther} ->');
  Lines.Add('                        Callback({error, {unexpected, AsyncOther}})');
  Lines.Add('                after ?ABI_TIMEOUT_MS ->');
  Lines.Add('                    Callback({error, timeout})');
  Lines.Add('                end');
  Lines.Add('            end),');
  Lines.Add('            case lf_raw_call_async(Kind, Target, Data, Collector) of');
  Lines.Add('                {ok, _Ref} ->');
  Lines.Add('                    lingofuse:free_data(Data),');
  Lines.Add('                    ok;');
  Lines.Add('                {error, DispatchReason} ->');
  Lines.Add('                    exit(Collector, kill),');
  Lines.Add('                    lingofuse:free_data(Data),');
  Lines.Add('                    Callback({error, DispatchReason}),');
  Lines.Add('                    ok');
  Lines.Add('            end;');
  Lines.Add('        {error, WriteReason2} ->');
  Lines.Add('            lingofuse:free_data(Data),');
  Lines.Add('            Callback({error, WriteReason2}),');
  Lines.Add('            ok');
  Lines.Add('    end.');
  Lines.Add('');

  Lines.Add('lf_raw_call_async(app, App, Data, Pid) -> lingofuse:async_call_raw(App, Data, Pid);');
  Lines.Add('lf_raw_call_async(uid, Uid, Data, Pid) -> lingofuse:async_uid_call_raw(Uid, Data, Pid);');
  Lines.Add('lf_raw_call_async(p2p, P2p, Data, Pid) -> lingofuse:async_p2pname_call_raw(P2p, Data, Pid).');
  Lines.Add('');

  Lines.Add('lf_do_notify(Kind, Target, Api, Body) ->');
  Lines.Add('    {ok, Data} = lingofuse:create_data(Api),');
  Lines.Add('    try');
  Lines.Add('        case lingofuse:write_buffer(Data, Body) of');
  Lines.Add('            {ok, _} -> ok;');
  Lines.Add('            {error, NotifyWriteReason} -> erlang:error({write_failed, NotifyWriteReason})');
  Lines.Add('        end,');
  Lines.Add('        case Kind of');
  Lines.Add('            app -> lingofuse:notify(Target, Data);');
  Lines.Add('            app_seq -> lingofuse:sequenced_notify(Target, Data);');
  Lines.Add('            uid -> lingofuse:uid_notify(Target, Data);');
  Lines.Add('            uid_seq -> lingofuse:uid_sequenced_notify(Target, Data);');
  Lines.Add('            p2p -> lingofuse:p2pname_notify(Target, Data);');
  Lines.Add('            p2p_seq -> lingofuse:p2pname_sequenced_notify(Target, Data)');
  Lines.Add('        end');
  Lines.Add('    after lingofuse:free_data(Data) end.');
  Lines.Add('');
end;

function GenerateABICallErlangCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  ApiNames: TSystemStringArray;
  UnitName, NormalizedUnit: SystemString;
  F: TFunctionStructure;
  ApiName, S, DecoderName: SystemString;
  Lines, ExportLines: TPascalStringList;
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

  Log(PFormat('Generating Erlang ABI call module for unit "%s"', [UnitName]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := AssignUniqueApiNames(SupportedFuncs);

  Lines := TPascalStringList.Create;
  ExportLines := TPascalStringList.Create;
  try
    S := '-module(' + ErlangQuotedAtom(NormalizedUnit + '_abi_call') + ').';
    Lines.Add(S);
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];

      if F.IsFunction then
      begin
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName) + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_async') + '/' +
          umlIntToStr(AsyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_uid') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_uid_async') + '/' +
          umlIntToStr(AsyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_p2p') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_p2p_async') + '/' +
          umlIntToStr(AsyncArity(F)).Text + ',');
      end
      else
      begin
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName) + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_seq') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_uid') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_uid_seq') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_p2p') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
        ExportLines.Add('    ' + ErlangQuotedAtom(ApiName + '_p2p_seq') + '/' +
          umlIntToStr(SyncArity(F)).Text + ',');
      end;
    end;

    Lines.Add('-export([');
    for i := 0 to ExportLines.Count - 1 do
    begin
      S := ExportLines[i];
      if (i = ExportLines.Count - 1) and (Length(S) > 0) and (S[Length(S)] = ',') then
        S := Copy(S, 1, Length(S) - 1);
      Lines.Add(S);
    end;
    Lines.Add(']).');
    Lines.Add('');

    EmitCommonHelpers(Lines);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];

      if F.IsFunction then
      begin
        DecoderName := DecodeFuncName(F.ReturnType);
        EmitSyncFunc(Lines, ApiName, 'app', 'App', ApiName, F, DecoderName);
        EmitAsyncFunc(Lines, ApiName + '_async', 'app', 'App', ApiName, F, DecoderName);
        EmitSyncFunc(Lines, ApiName + '_uid', 'uid', 'Uid', ApiName, F, DecoderName);
        EmitAsyncFunc(Lines, ApiName + '_uid_async', 'uid', 'Uid', ApiName, F, DecoderName);
        EmitSyncFunc(Lines, ApiName + '_p2p', 'p2p', 'P2p', ApiName, F, DecoderName);
        EmitAsyncFunc(Lines, ApiName + '_p2p_async', 'p2p', 'P2p', ApiName, F, DecoderName);
      end
      else
      begin
        EmitNotifyProc(Lines, ApiName, 'app', 'App', ApiName, F);
        EmitNotifyProc(Lines, ApiName + '_seq', 'app_seq', 'App', ApiName, F);
        EmitNotifyProc(Lines, ApiName + '_uid', 'uid', 'Uid', ApiName, F);
        EmitNotifyProc(Lines, ApiName + '_uid_seq', 'uid_seq', 'Uid', ApiName, F);
        EmitNotifyProc(Lines, ApiName + '_p2p', 'p2p', 'P2p', ApiName, F);
        EmitNotifyProc(Lines, ApiName + '_p2p_seq', 'p2p_seq', 'P2p', ApiName, F);
      end;
    end;

    Result := Lines;
    Log(PFormat('Generated %d lines for Erlang ABI call module.', [Lines.Count]));
  finally
    if Result = nil then
    begin
      Lines.Free;
      ExportLines.Free;
    end
    else
      ExportLines.Free;
  end;
end;

initialization
  RegisterGenerator('erlang', 'xxx_abi_call.erl', gkCall,
    'Erlang ABI call module', @GenerateABICallErlangCode);

end.
