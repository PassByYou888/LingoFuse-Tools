unit pas_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallPascalCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function ABI_Type_To_Pascal_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') then Result := 'Integer'
  else if T.Same('int64') then Result := 'Int64'
  else if T.Same('cardinal') then Result := 'Cardinal'
  else if T.Same('longint') then Result := 'LongInt'
  else if T.Same('dword') then Result := 'DWord'
  else if T.Same('word') then Result := 'Word'
  else if T.Same('smallint') then Result := 'SmallInt'
  else if T.Same('byte') then Result := 'Byte'
  else if T.Same('uint64') then Result := 'UInt64'
  else if T.Same('longword') then Result := 'LongWord'
  else if T.Same('double') then Result := 'Double'
  else if T.Same('single') then Result := 'Single'
  else if T.Same('extended') then Result := 'Extended'
  else if T.Same('real') then Result := 'Real'
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar') then
    Result := 'string'
  else
    Result := '';
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_WriteInt32'
  else if T.Same('int64') then Result := 'LF_WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'LF_WriteUInt32'
  else if T.Same('word') then Result := 'LF_WriteUInt16'
  else if T.Same('smallint') then Result := 'LF_WriteInt16'
  else if T.Same('byte') then Result := 'LF_WriteUInt8'
  else if T.Same('uint64') then Result := 'LF_WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'LF_WriteDouble'
  else if T.Same('single') then Result := 'LF_WriteSingle'
  else if IsStringABIType(T) then Result := 'LF_WriteString'
  else Result := '';
end;

function ABI_Type_To_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_ReadInt32'
  else if T.Same('int64') then Result := 'LF_ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'LF_ReadUInt32'
  else if T.Same('word') then Result := 'LF_ReadUInt16'
  else if T.Same('smallint') then Result := 'LF_ReadInt16'
  else if T.Same('byte') then Result := 'LF_ReadUInt8'
  else if T.Same('uint64') then Result := 'LF_ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'LF_ReadDouble'
  else if T.Same('single') then Result := 'LF_ReadSingle'
  else if IsStringABIType(T) then Result := 'LF_ReadString'
  else Result := '';
end;

function ABI_Type_Default_Expr(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := #39 + #39
  else if T.Same('double') or T.Same('single') or T.Same('extended')
    or T.Same('real') then
    Result := '0.0'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Pascal_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    if i > 0 then
      Result := Result + '; ';
    Result := Result + n + ': ' + ABI_Type_To_Pascal_Decl(Params[i].PascalType);
  end;
end;

function BuildLeadingParamList(const Leading_: TP_String;
  const Params: TParamArray): TP_String;
begin
  Result := Leading_;
  if Length(Params) > 0 then
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + BuildTypedParamDecl(Params);
  end;
end;

function BuildAsyncParamList(const Leading_: TP_String;
  const Params: TParamArray;
  const OnSuccessDecl, OnErrorDecl: TP_String): TP_String;
var
  Tmp: TP_String;
begin
  Tmp := BuildLeadingParamList(Leading_, Params);
  if Tmp <> '' then Tmp := Tmp + '; ';
  Result := Tmp + OnSuccessDecl + '; ' + OnErrorDecl;
end;

procedure EmitWriteParamStatements(Lines: TPascalStringList;
  const Params: TParamArray; const Indent: string);
var
  i: integer;
  n, fn: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    fn := ABI_Type_To_Write_Func(Params[i].PascalType);
    Lines.Add(Indent + 'if not ' + fn + '(_Data, ' + n + ') then');
    Lines.Add(Indent + '  raise EABI_RemoteError.Create(' + #39 +
      'failed to write parameter ' + #39 + ' + ' + #39 + n + #39 + ');');
  end;
end;

function StripAllCommentMarkers(const S: TP_String): TP_String;
var
  T: TP_String;
begin
  T := S.TrimChar(#32#9);
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

procedure EmitCommentBlock(Lines: TPascalStringList;
  const Indent, Comment: TP_String);
var
  StartPos, EndPos: Integer;
  Line: TP_String;
begin
  if Comment.Len = 0 then Exit;

  StartPos := 1;
  while StartPos <= Comment.Len do
  begin
    EndPos := StartPos;
    while (EndPos <= Comment.Len) and (Comment[EndPos] <> #10)
      and (Comment[EndPos] <> #13) do
      Inc(EndPos);

    if EndPos > StartPos then
    begin
      Line := Comment.GetString(StartPos, EndPos);
      Line := StripAllCommentMarkers(Line);
      if Line.Len > 0 then
        Lines.Add(Indent + '// ' + Line.Text);
    end;

    StartPos := EndPos;
    while (StartPos <= Comment.Len) and ((Comment[StartPos] = #10)
      or (Comment[StartPos] = #13)) do
      Inc(StartPos);
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

procedure EmitAsyncDispatch(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const Suffix: string);
var
  RetDecl, DefaultExpr, ReadFn: TP_String;
  HolderType, SuccessType, ErrorType: TP_String;
begin
  RetDecl := ABI_Type_To_Pascal_Decl(F.ReturnType);
  DefaultExpr := ABI_Type_Default_Expr(F.ReturnType);
  ReadFn := ABI_Type_To_Read_Func(F.ReturnType);
  HolderType := 'T' + ApiName + '_AsyncHolder' + Suffix;
  SuccessType := 'T' + ApiName + '_Success' + Suffix;
  ErrorType := 'TCallError' + Suffix;

  Lines.Add('type');
  Lines.Add('  P' + HolderType + ' = ^' + HolderType + ';');
  Lines.Add('  ' + HolderType + ' = record');
  Lines.Add('    Request: TDataHnd___;');
  Lines.Add('    OnSuccess: ' + SuccessType + ';');
  Lines.Add('    OnError: ' + ErrorType + ';');
  Lines.Add('  end;');
  Lines.Add('');
  Lines.Add('procedure ' + ApiName + '_AsyncDispatch' + Suffix +
    '(Data: Pointer; Result_: TDataHnd___); cdecl;');
  Lines.Add('var');
  Lines.Add('  _H: P' + HolderType + ';');
  Lines.Add('  _Status: uint8;');
  Lines.Add('  _ErrMsg: string;');
  Lines.Add('  _Value: ' + RetDecl + ';');
  Lines.Add('  _OK: Boolean;');
  Lines.Add('  _ErrCode: Integer;');
  Lines.Add('begin');
  Lines.Add('  _H := P' + HolderType + '(Data);');
  Lines.Add('  if _H = nil then Exit;');
  Lines.Add('  _Value := ' + DefaultExpr + ';');
  Lines.Add('  _ErrMsg := ' + #39 + #39 + ';');
  Lines.Add('  _ErrCode := 0;');
  Lines.Add('  _OK := False;');
  Lines.Add('  try');
  Lines.Add('    if Result_ = nil then');
  Lines.Add('    begin');
  Lines.Add('      _ErrCode := ABI_ERR_TIMEOUT;');
  Lines.Add('      _ErrMsg := ' + #39 + 'nil response (timeout or target not found)' + #39 + ';');
  Lines.Add('    end');
  Lines.Add('    else if LF_GetSize(Result_) <= 0 then');
  Lines.Add('    begin');
  Lines.Add('      _ErrCode := ABI_ERR_EMPTY_RESPONSE;');
  Lines.Add('      _ErrMsg := ' + #39 + 'empty response' + #39 + ';');
  Lines.Add('    end');
  Lines.Add('    else');
  Lines.Add('    begin');
  Lines.Add('      LF_SetPos(Result_, 0);');
  Lines.Add('      if not LF_ReadUInt8(Result_, _Status) then');
  Lines.Add('      begin');
  Lines.Add('        _ErrCode := ABI_ERR_TRUNCATED_STATUS;');
  Lines.Add('        _ErrMsg := ' + #39 + 'truncated status' + #39 + ';');
  Lines.Add('      end');
  Lines.Add('      else if _Status <> 0 then');
  Lines.Add('      begin');
  Lines.Add('        LF_ReadString(Result_, _ErrMsg);');
  Lines.Add('        _ErrCode := ABI_ERR_REMOTE_ERROR;');
  Lines.Add('        _ErrMsg := ' + #39 + 'remote error: ' + #39 + ' + _ErrMsg;');
  Lines.Add('      end');
  Lines.Add('      else if not ' + ReadFn + '(Result_, _Value) then');
  Lines.Add('      begin');
  Lines.Add('        _ErrCode := ABI_ERR_TRUNCATED_RESULT;');
  Lines.Add('        _ErrMsg := ' + #39 + 'truncated result' + #39 + ';');
  Lines.Add('      end');
  Lines.Add('      else');
  Lines.Add('        _OK := True;');
  Lines.Add('    end;');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do');
  Lines.Add('    begin');
  Lines.Add('      _OK := False;');
  Lines.Add('      _ErrCode := ABI_ERR_DISPATCH_EXCEPTION;');
  Lines.Add('      _ErrMsg := ' + #39 + 'dispatch exception: ' + #39 + ' + E.Message;');
  Lines.Add('    end;');
  Lines.Add('  end;');
  Lines.Add('  try');
  Lines.Add('    if _OK then');
  Lines.Add('    begin');
  Lines.Add('      if Assigned(_H^.OnSuccess) then');
  Lines.Add('        try _H^.OnSuccess(_Value) except end;');
  Lines.Add('    end');
  Lines.Add('    else');
  Lines.Add('    begin');
  Lines.Add('      if Assigned(_H^.OnError) then');
  Lines.Add('        try _H^.OnError(_ErrMsg, _ErrCode) except end;');
  Lines.Add('    end;');
  Lines.Add('  finally');
  Lines.Add('    if _H^.Request <> nil then');
  Lines.Add('    begin');
  Lines.Add('      LF_FreeData(_H^.Request);');
  Lines.Add('      _H^.Request := nil;');
  Lines.Add('    end;');
  Lines.Add('    Dispose(_H);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitSyncCallFunction(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const FuncName: TP_String;
  const ExtraParamPrefix: TP_String;
  const CallExFunc: TP_String;
  const FirstArgExpr: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildLeadingParamList(ExtraParamPrefix, F.Params);

  Lines.Add('function ' + FuncName + '(' + ParamDecl + '): ' +
    ABI_Type_To_Pascal_Decl(F.ReturnType) + ';');
  Lines.Add('var');
  Lines.Add('  _Data, _Res: TDataHnd___;');
  Lines.Add('  _Status: uint8;');
  Lines.Add('  _ErrMsg: string;');
  Lines.Add('begin');
  Lines.Add('  _Res := nil;');
  Lines.Add('  _Data := LF_CreateDataEx(' + #39 + ApiName + #39 + ');');
  Lines.Add('  if _Data = nil then');
  Lines.Add('    raise EABI_RemoteError.Create(' + #39 +
    'LF_CreateDataEx returned nil for API "' + ApiName + '"' + #39 + ');');
  Lines.Add('  try');

  EmitWriteParamStatements(Lines, F.Params, '    ');

  if Length(F.Params) > 0 then
    Lines.Add('');

  Lines.Add('    _Res := ' + CallExFunc + '(' + FirstArgExpr +
    ', _Data, ABI_Timeout);');
  Lines.Add('    if _Res = nil then');
  Lines.Add('      raise EABI_RemoteError.Create(' + #39 + 'call "' + ApiName +
    '" returned nil (timeout or target not found)' + #39 + ');');
  Lines.Add('    try');
  Lines.Add('      if LF_GetSize(_Res) <= 0 then');
  Lines.Add('        raise EABI_RemoteError.Create(' + #39 + 'call "' + ApiName +
    '" returned empty response' + #39 + ');');
  Lines.Add('      LF_SetPos(_Res, 0);');
  Lines.Add('      if not LF_ReadUInt8(_Res, _Status) then');
  Lines.Add('        raise EABI_RemoteError.Create(' + #39 + 'call "' + ApiName +
    '": response truncated (status)' + #39 + ');');
  Lines.Add('      if _Status <> 0 then');
  Lines.Add('      begin');
  Lines.Add('        LF_ReadString(_Res, _ErrMsg);');
  Lines.Add('        raise EABI_RemoteError.Create(' + #39 + 'call "' + ApiName +
    '" failed: ' + #39 + ' + _ErrMsg);');
  Lines.Add('      end;');
  Lines.Add('      if not ' + ABI_Type_To_Read_Func(F.ReturnType) +
    '(_Res, Result) then');
  Lines.Add('        raise EABI_RemoteError.Create(' + #39 + 'call "' + ApiName +
    '": response truncated (result)' + #39 + ');');
  Lines.Add('    finally');
  Lines.Add('      LF_FreeData(_Res);');
  Lines.Add('    end;');
  Lines.Add('  finally');
  Lines.Add('    LF_FreeData(_Data);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitAsyncCallFunction(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const FuncName: TP_String;
  const DispatcherSuffix: string;
  const ExtraParamPrefix: TP_String;
  const AsyncCallExFunc: TP_String;
  const FirstArgExpr: TP_String);
var
  ParamDecl, SuccessType, ErrorType, HolderType: TP_String;
begin
  SuccessType := 'T' + ApiName + '_Success' + DispatcherSuffix;
  ErrorType := 'TCallError' + DispatcherSuffix;
  HolderType := 'T' + ApiName + '_AsyncHolder' + DispatcherSuffix;

  ParamDecl := BuildAsyncParamList(ExtraParamPrefix, F.Params,
    'OnSuccess: ' + SuccessType, 'OnError: ' + ErrorType);

  Lines.Add('function ' + FuncName + '(' + ParamDecl + '): Boolean;');
  Lines.Add('var');
  Lines.Add('  _Data: TDataHnd___;');
  Lines.Add('  _H: P' + HolderType + ';');
  Lines.Add('begin');
  Lines.Add('  Result := False;');
  Lines.Add('  _Data := LF_CreateDataEx(' + #39 + ApiName + #39 + ');');
  Lines.Add('  if _Data = nil then');
  Lines.Add('  begin');
  Lines.Add('    if Assigned(OnError) then');
  Lines.Add('      try OnError(' + #39 +
    'LF_CreateDataEx returned nil for API "' + ApiName + '"' + #39 +
    ', ABI_ERR_CREATE_FAILED) except end;');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  _H := nil;');
  Lines.Add('  try');

  EmitWriteParamStatements(Lines, F.Params, '    ');

  Lines.Add('    New(_H);');
  Lines.Add('    _H^.Request := _Data;');
  Lines.Add('    _H^.OnSuccess := OnSuccess;');
  Lines.Add('    _H^.OnError := OnError;');
  Lines.Add('    try');
  Lines.Add('      Result := ' + AsyncCallExFunc + '(' + FirstArgExpr +
    ', _Data, _H, @' + ApiName + '_AsyncDispatch' + DispatcherSuffix + ') = 1;');
  Lines.Add('    except');
  Lines.Add('      on E: Exception do');
  Lines.Add('      begin');
  Lines.Add('        Result := False;');
  Lines.Add('        _H^.Request := nil;');
  Lines.Add('        Dispose(_H);');
  Lines.Add('        _H := nil;');
  Lines.Add('        if Assigned(OnError) then');
  Lines.Add('          try OnError(' + #39 + 'async exception: ' + #39 +
    ' + E.Message, ABI_ERR_DISPATCH_EXCEPTION) except end;');
  Lines.Add('        Exit;');
  Lines.Add('      end;');
  Lines.Add('    end;');
  Lines.Add('    if Result then');
  Lines.Add('      _Data := nil');
  Lines.Add('    else');
  Lines.Add('    begin');
  Lines.Add('      _H^.Request := nil;');
  Lines.Add('      Dispose(_H);');
  Lines.Add('      _H := nil;');
  Lines.Add('      if Assigned(OnError) then');
  Lines.Add('        try OnError(' + #39 + 'async call returned failure' + #39 +
    ', ABI_ERR_ASYNC_SUBMIT_FAILED) except end;');
  Lines.Add('    end;');
  Lines.Add('  finally');
  Lines.Add('    if _Data <> nil then');
  Lines.Add('      LF_FreeData(_Data);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitNotifyProcedure(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const ProcName: TP_String;
  const ExtraParamPrefix: TP_String;
  const NotifyExFunc: TP_String;
  const FirstArgExpr: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildLeadingParamList(ExtraParamPrefix, F.Params);

  Lines.Add('procedure ' + ProcName + '(' + ParamDecl + ');');
  Lines.Add('var');
  Lines.Add('  _Data: TDataHnd___;');
  Lines.Add('begin');
  Lines.Add('  _Data := LF_CreateDataEx(' + #39 + ApiName + #39 + ');');
  Lines.Add('  if _Data = nil then');
  Lines.Add('    raise EABI_RemoteError.Create(' + #39 +
    'LF_CreateDataEx returned nil for API "' + ApiName + '"' + #39 + ');');
  Lines.Add('  try');

  EmitWriteParamStatements(Lines, F.Params, '    ');

  if Length(F.Params) > 0 then
    Lines.Add('');

  Lines.Add('    ' + NotifyExFunc + '(' + FirstArgExpr + ', _Data);');
  Lines.Add('  finally');
  Lines.Add('    LF_FreeData(_Data);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

function GenerateABICallPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, RetDecl, LeadParamDecl: TP_String;
  F: TFunctionStructure;
  HeaderLines, TypeDeclLines, InterfaceDeclLines, ImplLines: TPascalStringList;
  ResultLines: TPascalStringList;
  HaveAsyncTypes: boolean;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallPascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallPascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  Log(PFormat('Generating ABI call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  TypeDeclLines := TPascalStringList.Create;
  InterfaceDeclLines := TPascalStringList.Create;
  ImplLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    HeaderLines.Add('unit ' + NormalizedUnit + '_abi_call_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('{$ifdef FPC}');
    HeaderLines.Add('  {$mode delphi}{$H+}');
    HeaderLines.Add('  {$MODESWITCH NestedProcVars}');
    HeaderLines.Add('  {$modeswitch advancedrecords}');
    HeaderLines.Add('  {$CODEPAGE UTF8}');
    HeaderLines.Add('{$endif}');
    HeaderLines.Add('{$R-}{$I-}{$Q-}{$B-}');
    HeaderLines.Add('');
    HeaderLines.Add('interface');
    HeaderLines.Add('');
    HeaderLines.Add('uses');
    HeaderLines.Add('  SysUtils, Classes,');
    HeaderLines.Add('  lingofuse_import;');
    HeaderLines.Add('');
    HeaderLines.Add('const');
    HeaderLines.Add('  ABI_ERR_CREATE_FAILED = 1;');
    HeaderLines.Add('  ABI_ERR_ASYNC_SUBMIT_FAILED = 2;');
    HeaderLines.Add('  ABI_ERR_DISPATCH_EXCEPTION = 3;');
    HeaderLines.Add('  ABI_ERR_TIMEOUT = 4;');
    HeaderLines.Add('  ABI_ERR_EMPTY_RESPONSE = 5;');
    HeaderLines.Add('  ABI_ERR_TRUNCATED_STATUS = 6;');
    HeaderLines.Add('  ABI_ERR_REMOTE_ERROR = 7;');
    HeaderLines.Add('  ABI_ERR_TRUNCATED_RESULT = 8;');
    HeaderLines.Add('');
    HeaderLines.Add('type');
    HeaderLines.Add('  EABI_RemoteError = class(Exception);');
    HeaderLines.Add('  TCallError_M = procedure(const ErrorMsg: string; ' +
      'Code: Integer) of object;');
    HeaderLines.Add('{$IFDEF FPC}');
    HeaderLines.Add('  TCallError_P = procedure(const ErrorMsg: string; ' +
      'Code: Integer) is nested;');
    HeaderLines.Add('{$ELSE}');
    HeaderLines.Add('  TCallError_P = reference to procedure(' +
      'const ErrorMsg: string; Code: Integer);');
    HeaderLines.Add('{$ENDIF}');
    HeaderLines.Add('');

    HaveAsyncTypes := False;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      RetDecl := ABI_Type_To_Pascal_Decl(F.ReturnType);

      if F.IsFunction then
      begin
        TypeDeclLines.Add('  T' + ApiName + '_Success_M = procedure(' +
          'const Value: ' + RetDecl + ') of object;');
        TypeDeclLines.Add('{$IFDEF FPC}');
        TypeDeclLines.Add('  T' + ApiName + '_Success_P = procedure(' +
          'const Value: ' + RetDecl + ') is nested;');
        TypeDeclLines.Add('{$ELSE}');
        TypeDeclLines.Add('  T' + ApiName + '_Success_P = reference to ' +
          'procedure(const Value: ' + RetDecl + ');');
        TypeDeclLines.Add('{$ENDIF}');
        HaveAsyncTypes := True;

        EmitCommentBlock(InterfaceDeclLines, '', F.Comment);
        LeadParamDecl := BuildLeadingParamList('const appName___: string',
          F.Params);
        InterfaceDeclLines.Add('function ' + ApiName +
          '(' + LeadParamDecl + '): ' + RetDecl + ';');

        LeadParamDecl := BuildLeadingParamList('const appName___: string',
          F.Params);
        InterfaceDeclLines.Add('function ' + ApiName +
          '_Async(' + BuildAsyncParamList('const appName___: string',
          F.Params, 'OnSuccess: T' + ApiName + '_Success_M',
          'OnError: TCallError_M') + '): Boolean;');

        LeadParamDecl := BuildLeadingParamList('const appName___: string',
          F.Params);
        InterfaceDeclLines.Add('function ' + ApiName +
          '_Async_P(' + BuildAsyncParamList('const appName___: string',
          F.Params, 'OnSuccess: T' + ApiName + '_Success_P',
          'OnError: TCallError_P') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_AsyncSequenced(' + BuildAsyncParamList('const appName___: string',
          F.Params, 'OnSuccess: T' + ApiName + '_Success_M',
          'OnError: TCallError_M') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_AsyncSequenced_P(' + BuildAsyncParamList(
          'const appName___: string', F.Params,
          'OnSuccess: T' + ApiName + '_Success_P',
          'OnError: TCallError_P') + '): Boolean;');

        LeadParamDecl := BuildLeadingParamList('const UID___: TP2P_UID___',
          F.Params);
        InterfaceDeclLines.Add('function ' + ApiName +
          '_UID_Call(' + LeadParamDecl + '): ' + RetDecl + ';');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_UID_Async(' + BuildAsyncParamList('const UID___: TP2P_UID___',
          F.Params, 'OnSuccess: T' + ApiName + '_Success_M',
          'OnError: TCallError_M') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_UID_Async_P(' + BuildAsyncParamList(
          'const UID___: TP2P_UID___', F.Params,
          'OnSuccess: T' + ApiName + '_Success_P',
          'OnError: TCallError_P') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_UID_AsyncSequenced(' + BuildAsyncParamList(
          'const UID___: TP2P_UID___', F.Params,
          'OnSuccess: T' + ApiName + '_Success_M',
          'OnError: TCallError_M') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_UID_AsyncSequenced_P(' + BuildAsyncParamList(
          'const UID___: TP2P_UID___', F.Params,
          'OnSuccess: T' + ApiName + '_Success_P',
          'OnError: TCallError_P') + '): Boolean;');

        LeadParamDecl := BuildLeadingParamList('const p2pName___: string',
          F.Params);
        InterfaceDeclLines.Add('function ' + ApiName +
          '_P2PName_Call(' + LeadParamDecl + '): ' + RetDecl + ';');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_P2PName_Async(' + BuildAsyncParamList(
          'const p2pName___: string', F.Params,
          'OnSuccess: T' + ApiName + '_Success_M',
          'OnError: TCallError_M') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_P2PName_Async_P(' + BuildAsyncParamList(
          'const p2pName___: string', F.Params,
          'OnSuccess: T' + ApiName + '_Success_P',
          'OnError: TCallError_P') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_P2PName_AsyncSequenced(' + BuildAsyncParamList(
          'const p2pName___: string', F.Params,
          'OnSuccess: T' + ApiName + '_Success_M',
          'OnError: TCallError_M') + '): Boolean;');

        InterfaceDeclLines.Add('function ' + ApiName +
          '_P2PName_AsyncSequenced_P(' + BuildAsyncParamList(
          'const p2pName___: string', F.Params,
          'OnSuccess: T' + ApiName + '_Success_P',
          'OnError: TCallError_P') + '): Boolean;');

        InterfaceDeclLines.Add('');

        ImplLines.Add('');
        EmitAsyncDispatch(ImplLines, ApiName, F, '_M');
        EmitAsyncDispatch(ImplLines, ApiName, F, '_P');

        EmitCommentBlock(ImplLines, '', F.Comment);
        EmitSyncCallFunction(ImplLines, ApiName, F, ApiName,
          'const appName___: string', 'LF_CallEx', 'appName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F, ApiName + '_Async',
          '_M', 'const appName___: string', 'LF_Async_CallEx', 'appName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F, ApiName + '_Async_P',
          '_P', 'const appName___: string', 'LF_Async_CallEx', 'appName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_AsyncSequenced', '_M',
          'const appName___: string', 'LF_Async_Sequenced_CallEx',
          'appName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_AsyncSequenced_P', '_P',
          'const appName___: string', 'LF_Async_Sequenced_CallEx',
          'appName___');
        EmitSyncCallFunction(ImplLines, ApiName, F, ApiName + '_UID_Call',
          'const UID___: TP2P_UID___', 'LF_UID_CallEx', 'UID___');
        EmitAsyncCallFunction(ImplLines, ApiName, F, ApiName + '_UID_Async',
          '_M', 'const UID___: TP2P_UID___', 'LF_UID_Async_CallEx', 'UID___');
        EmitAsyncCallFunction(ImplLines, ApiName, F, ApiName + '_UID_Async_P',
          '_P', 'const UID___: TP2P_UID___', 'LF_UID_Async_CallEx', 'UID___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_UID_AsyncSequenced', '_M',
          'const UID___: TP2P_UID___', 'LF_UID_Async_Sequenced_CallEx',
          'UID___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_UID_AsyncSequenced_P', '_P',
          'const UID___: TP2P_UID___', 'LF_UID_Async_Sequenced_CallEx',
          'UID___');
        EmitSyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_P2PName_Call',
          'const p2pName___: string', 'LF_P2PNAME_CallEx', 'p2pName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_P2PName_Async', '_M',
          'const p2pName___: string', 'LF_P2PNAME_Async_CallEx',
          'p2pName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_P2PName_Async_P', '_P',
          'const p2pName___: string', 'LF_P2PNAME_Async_CallEx',
          'p2pName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_P2PName_AsyncSequenced', '_M',
          'const p2pName___: string',
          'LF_P2PNAME_Async_Sequenced_CallEx', 'p2pName___');
        EmitAsyncCallFunction(ImplLines, ApiName, F,
          ApiName + '_P2PName_AsyncSequenced_P', '_P',
          'const p2pName___: string',
          'LF_P2PNAME_Async_Sequenced_CallEx', 'p2pName___');
      end
      else
      begin
        EmitCommentBlock(InterfaceDeclLines, '', F.Comment);
        LeadParamDecl := BuildLeadingParamList('const appName___: string',
          F.Params);
        InterfaceDeclLines.Add('procedure ' + ApiName +
          '(' + LeadParamDecl + ');');

        LeadParamDecl := BuildLeadingParamList('const appName___: string',
          F.Params);
        InterfaceDeclLines.Add('procedure ' + ApiName +
          '_SequencedNotify(' + LeadParamDecl + ');');

        LeadParamDecl := BuildLeadingParamList('const UID___: TP2P_UID___',
          F.Params);
        InterfaceDeclLines.Add('procedure ' + ApiName +
          '_UID_Notify(' + LeadParamDecl + ');');

        LeadParamDecl := BuildLeadingParamList('const UID___: TP2P_UID___',
          F.Params);
        InterfaceDeclLines.Add('procedure ' + ApiName +
          '_UID_SequencedNotify(' + LeadParamDecl + ');');

        LeadParamDecl := BuildLeadingParamList('const p2pName___: string',
          F.Params);
        InterfaceDeclLines.Add('procedure ' + ApiName +
          '_P2PName_Notify(' + LeadParamDecl + ');');

        LeadParamDecl := BuildLeadingParamList('const p2pName___: string',
          F.Params);
        InterfaceDeclLines.Add('procedure ' + ApiName +
          '_P2PName_SequencedNotify(' + LeadParamDecl + ');');
        InterfaceDeclLines.Add('');

        ImplLines.Add('');
        EmitCommentBlock(ImplLines, '', F.Comment);
        EmitNotifyProcedure(ImplLines, ApiName, F, ApiName,
          'const appName___: string', 'LF_NotifyEx', 'appName___');
        EmitNotifyProcedure(ImplLines, ApiName, F, ApiName + '_SequencedNotify',
          'const appName___: string', 'LF_Sequenced_NotifyEx', 'appName___');
        EmitNotifyProcedure(ImplLines, ApiName, F, ApiName + '_UID_Notify',
          'const UID___: TP2P_UID___', 'LF_UID_NotifyEx', 'UID___');
        EmitNotifyProcedure(ImplLines, ApiName, F,
          ApiName + '_UID_SequencedNotify',
          'const UID___: TP2P_UID___', 'LF_UID_Sequenced_NotifyEx', 'UID___');
        EmitNotifyProcedure(ImplLines, ApiName, F, ApiName + '_P2PName_Notify',
          'const p2pName___: string', 'LF_P2PNAME_NotifyEx', 'p2pName___');
        EmitNotifyProcedure(ImplLines, ApiName, F,
          ApiName + '_P2PName_SequencedNotify',
          'const p2pName___: string', 'LF_P2PNAME_Sequenced_NotifyEx',
          'p2pName___');
      end;
    end;

    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    if HaveAsyncTypes then
      ResultLines.AddStrings(TypeDeclLines);
    ResultLines.Add('');
    ResultLines.Add('var');
    ResultLines.Add('  ABI_Timeout: uint64 = 5000;');
    ResultLines.Add('');
    ResultLines.AddStrings(InterfaceDeclLines);
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(ImplLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    TypeDeclLines.Free;
    InterfaceDeclLines.Free;
    ImplLines.Free;
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'pascal',
    'xxx_abi_call_unit.pas',
    gkCall,
    'Pascal ABI call unit',
    @GenerateABICallPascalCode);

end.
