unit ruby_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallRubyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[ruby_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[ruby_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Ruby_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'read_int32'
  else if T.Same('int64') then Result := 'read_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'read_uint32'
  else if T.Same('word') then Result := 'read_uint16'
  else if T.Same('smallint') then Result := 'read_int16'
  else if T.Same('byte') then Result := 'read_uint8'
  else if T.Same('uint64') then Result := 'read_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'read_double'
  else if T.Same('single') then Result := 'read_single'
  else if IsStringABIType(T) then Result := 'read_string'
  else Result := '';
end;

function ABI_Type_To_Ruby_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'write_int32'
  else if T.Same('int64') then Result := 'write_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'write_uint32'
  else if T.Same('word') then Result := 'write_uint16'
  else if T.Same('smallint') then Result := 'write_int16'
  else if T.Same('byte') then Result := 'write_uint8'
  else if T.Same('uint64') then Result := 'write_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'write_double'
  else if T.Same('single') then Result := 'write_single'
  else if IsStringABIType(T) then Result := 'write_string'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Ruby_Read_Func(T) <> '';
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

  if (Result.Len > 0) and (Result[1] >= 'A') and (Result[1] <= 'Z') then
  begin
    Result[1] := SystemChar(Ord(Result[1]) + 32);
    Result := Result + '_param';
  end;

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

function BuildRubyParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRubyIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function BuildRubyParamDeclWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Tmp := BuildRubyParamDecl(Params);
  if Tmp = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Tmp
  else
    Result := Prefix + ', ' + Tmp;
end;

procedure EmitWriteParamStatements(Lines: TPascalStringList; const Params: TParamArray; const Indent: TP_String);
var
  i: integer;
  PName, WriteFn: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRubyIdent(Params[i].Name, i);
    WriteFn := ABI_Type_To_Ruby_Write_Func(Params[i].PascalType);
    Lines.Add(Indent + 'param.' + WriteFn + '(' + PName + ')');
  end;
end;

procedure EmitReadResponseFunction(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ReadFn: TP_String;
begin
  ReadFn := ABI_Type_To_Ruby_Read_Func(F.ReturnType);

  Lines.Add('    def read_' + ApiName + '_response(h)');
  Lines.Add('      h.position = 0');
  Lines.Add('      status = h.read_uint8');
  Lines.Add('      unless status == STATUS_OK');
  Lines.Add('        msg = ' + #39 + #39);
  Lines.Add('        begin');
  Lines.Add('          msg = h.read_string');
  Lines.Add('        rescue StandardError');
  Lines.Add('          msg = ' + #39 + #39);
  Lines.Add('        end');
  Lines.Add('        raise LingoFuse::CallError.new("ABI call ' + ApiName + ' failed: #{msg}")');
  Lines.Add('      end');
  Lines.Add('      h.' + ReadFn);
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitSyncAppCall(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDecl(F.Params);
  Lines.Add('    def ' + ApiName + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        resp = LingoFuse::Framework.try_call(ABI_TARGET_APP, param, ABI_TIMEOUT_MS)');
  Lines.Add('        raise LingoFuse::CallError.new("ABI call ' + ApiName + ' returned an empty response (timeout or target not found)") if resp.nil?');
  Lines.Add('        begin');
  Lines.Add('          read_' + ApiName + '_response(resp)');
  Lines.Add('        ensure');
  Lines.Add('          resp.dispose');
  Lines.Add('        end');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitAsyncAppCallGeneric(Lines: TPascalStringList; const ApiName, Suffix, NativeCallFn: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDecl(F.Params);
  Lines.Add('    def ' + ApiName + Suffix + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        tramp = LingoFuse::NativeBridge.async_call_trampoline_addr');
  Lines.Add('        raw = handle_addr(param)');
  Lines.Add('        issue = lambda { |ref_addr| LingoFuse::Native.' + NativeCallFn + '(ABI_TARGET_APP, raw, ref_addr, tramp) }');
  Lines.Add('        deserialize = lambda do |result_addr|');
  Lines.Add('          next nil if result_addr.nil?');
  Lines.Add('          h = LingoFuse::DataHandle.from_raw(result_addr, false)');
  Lines.Add('          read_' + ApiName + '_response(h)');
  Lines.Add('        end');
  Lines.Add('        LingoFuse::AsyncSupport.run_async_with_future(');
  Lines.Add('          issue_fn: issue, deserialize: deserialize, timeout_ms: ABI_TIMEOUT_MS');
  Lines.Add('        )');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitSyncUIDCall(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDeclWithPrefix('uid', F.Params);
  Lines.Add('    def ' + ApiName + '_uid_call(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        raw_resp = LingoFuse::Native.lf_uid_call(uid, handle_addr(param), ABI_TIMEOUT_MS)');
  Lines.Add('        raise LingoFuse::CallError.new("ABI call ' + ApiName + ' returned an empty response (timeout or target not found)") if raw_resp.nil?');
  Lines.Add('        resp = LingoFuse::DataHandle.from_raw(raw_resp, true)');
  Lines.Add('        begin');
  Lines.Add('          read_' + ApiName + '_response(resp)');
  Lines.Add('        ensure');
  Lines.Add('          resp.dispose');
  Lines.Add('        end');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitAsyncUIDCallGeneric(Lines: TPascalStringList; const ApiName, Suffix, NativeCallFn: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDeclWithPrefix('uid', F.Params);
  Lines.Add('    def ' + ApiName + Suffix + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        tramp = LingoFuse::NativeBridge.async_call_trampoline_addr');
  Lines.Add('        raw = handle_addr(param)');
  Lines.Add('        issue = lambda { |ref_addr| LingoFuse::Native.' + NativeCallFn + '(uid, raw, ref_addr, tramp) }');
  Lines.Add('        deserialize = lambda do |result_addr|');
  Lines.Add('          next nil if result_addr.nil?');
  Lines.Add('          h = LingoFuse::DataHandle.from_raw(result_addr, false)');
  Lines.Add('          read_' + ApiName + '_response(h)');
  Lines.Add('        end');
  Lines.Add('        LingoFuse::AsyncSupport.run_async_with_future(');
  Lines.Add('          issue_fn: issue, deserialize: deserialize, timeout_ms: ABI_TIMEOUT_MS');
  Lines.Add('        )');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitSyncP2PNameCall(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDeclWithPrefix('p2p_name', F.Params);
  Lines.Add('    def ' + ApiName + '_p2pname_call(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        raw_resp = LingoFuse::Native.lf_p2pname_call(p2p_name, handle_addr(param), ABI_TIMEOUT_MS)');
  Lines.Add('        raise LingoFuse::CallError.new("ABI call ' + ApiName + ' returned an empty response (timeout or target not found)") if raw_resp.nil?');
  Lines.Add('        resp = LingoFuse::DataHandle.from_raw(raw_resp, true)');
  Lines.Add('        begin');
  Lines.Add('          read_' + ApiName + '_response(resp)');
  Lines.Add('        ensure');
  Lines.Add('          resp.dispose');
  Lines.Add('        end');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitAsyncP2PNameCallGeneric(Lines: TPascalStringList; const ApiName, Suffix, NativeCallFn: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDeclWithPrefix('p2p_name', F.Params);
  Lines.Add('    def ' + ApiName + Suffix + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        tramp = LingoFuse::NativeBridge.async_call_trampoline_addr');
  Lines.Add('        raw = handle_addr(param)');
  Lines.Add('        issue = lambda { |ref_addr| LingoFuse::Native.' + NativeCallFn + '(p2p_name, raw, ref_addr, tramp) }');
  Lines.Add('        deserialize = lambda do |result_addr|');
  Lines.Add('          next nil if result_addr.nil?');
  Lines.Add('          h = LingoFuse::DataHandle.from_raw(result_addr, false)');
  Lines.Add('          read_' + ApiName + '_response(h)');
  Lines.Add('        end');
  Lines.Add('        LingoFuse::AsyncSupport.run_async_with_future(');
  Lines.Add('          issue_fn: issue, deserialize: deserialize, timeout_ms: ABI_TIMEOUT_MS');
  Lines.Add('        )');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitNotifyGeneric(Lines: TPascalStringList; const ApiName, Suffix, NativeCallFn: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDecl(F.Params);
  Lines.Add('    def ' + ApiName + Suffix + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        LingoFuse::Native.' + NativeCallFn + '(ABI_TARGET_APP, handle_addr(param))');
  Lines.Add('        nil');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitNotifyVariantUID(Lines: TPascalStringList; const ApiName, Suffix, NativeCallFn: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDeclWithPrefix('uid', F.Params);
  Lines.Add('    def ' + ApiName + Suffix + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        LingoFuse::Native.' + NativeCallFn + '(uid, handle_addr(param))');
  Lines.Add('        nil');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitNotifyVariantP2PName(Lines: TPascalStringList; const ApiName, Suffix, NativeCallFn: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildRubyParamDeclWithPrefix('p2p_name', F.Params);
  Lines.Add('    def ' + ApiName + Suffix + '(' + ParamDecl + ')');
  Lines.Add('      param = LingoFuse::DataHandle.new(' + RubyStrLit(ApiName) + ')');
  Lines.Add('      begin');
  EmitWriteParamStatements(Lines, F.Params, '        ');
  Lines.Add('        param.position = 0');
  Lines.Add('        LingoFuse::Native.' + NativeCallFn + '(p2p_name, handle_addr(param))');
  Lines.Add('        nil');
  Lines.Add('      ensure');
  Lines.Add('        param.dispose');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitFunctionVariants(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitReadResponseFunction(Lines, ApiName, F);
  EmitSyncAppCall(Lines, ApiName, F);
  EmitAsyncAppCallGeneric(Lines, ApiName, '_async', 'lf_async_call', F);
  EmitAsyncAppCallGeneric(Lines, ApiName, '_async_sequenced', 'lf_async_sequenced_call', F);
  EmitSyncUIDCall(Lines, ApiName, F);
  EmitAsyncUIDCallGeneric(Lines, ApiName, '_uid_async', 'lf_uid_async_call', F);
  EmitAsyncUIDCallGeneric(Lines, ApiName, '_uid_async_sequenced', 'lf_uid_async_sequenced_call', F);
  EmitSyncP2PNameCall(Lines, ApiName, F);
  EmitAsyncP2PNameCallGeneric(Lines, ApiName, '_p2pname_async', 'lf_p2pname_async_call', F);
  EmitAsyncP2PNameCallGeneric(Lines, ApiName, '_p2pname_async_sequenced', 'lf_p2pname_async_sequenced_call', F);
end;

procedure EmitProcedureVariants(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitNotifyGeneric(Lines, ApiName, '', 'lf_notify', F);
  EmitNotifyGeneric(Lines, ApiName, '_sequenced_notify', 'lf_sequenced_notify', F);
  EmitNotifyVariantUID(Lines, ApiName, '_uid_notify', 'lf_uid_notify', F);
  EmitNotifyVariantUID(Lines, ApiName, '_uid_sequenced_notify', 'lf_uid_sequenced_notify', F);
  EmitNotifyVariantP2PName(Lines, ApiName, '_p2pname_notify', 'lf_p2pname_notify', F);
  EmitNotifyVariantP2PName(Lines, ApiName, '_p2pname_sequenced_notify', 'lf_p2pname_sequenced_notify', F);
end;

function GenerateABICallRubyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetApp: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallRubyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallRubyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';

  Log(PFormat('Generating Ruby ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('# frozen_string_literal: true');
    Lines.Add('');
    Lines.Add('require ' + #39 + 'lingofuse' + #39);
    Lines.Add('');
    Lines.Add('module ' + NormalizedUnit + '_abi');
    Lines.Add('  module Call');
    Lines.Add('    ABI_TARGET_APP = ' + RubyStrLit(TargetApp));
    Lines.Add('    ABI_TIMEOUT_MS = 5000');
    Lines.Add('    STATUS_OK = 0x00');
    Lines.Add('');
    Lines.Add('    module_function');
    Lines.Add('');
    Lines.Add('    def handle_addr(h)');
    Lines.Add('      r = h.raw');
    Lines.Add('      return nil if r.nil?');
    Lines.Add('      r.respond_to?(:to_i) ? r.to_i : r');
    Lines.Add('    end');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if not F.IsFunction then
        Continue;

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitFunctionVariants(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        Continue;

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitProcedureVariants(Lines, ApiName, F);
    end;

    Lines.Add('  end');
    Lines.Add('end');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Ruby ABI call', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'ruby',
    'xxx_abi_call.rb',
    gkCall,
    'Ruby ABI call implementation',
    @GenerateABICallRubyCode);

end.
