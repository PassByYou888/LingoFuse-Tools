unit cpp_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallHppCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallCppCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Cpp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'std::int32_t'
  else if T.Same('int64') then
    Result := 'std::int64_t'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'std::uint32_t'
  else if T.Same('word') then
    Result := 'std::uint16_t'
  else if T.Same('smallint') then
    Result := 'std::int16_t'
  else if T.Same('byte') then
    Result := 'std::uint8_t'
  else if T.Same('uint64') then
    Result := 'std::uint64_t'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'std::string'
  else
    Result := '';
end;

function ABI_Type_To_Cpp_Param_Decl(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'const std::string&'
  else
    Result := ABI_Type_To_Cpp_Decl(T);
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Cpp_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsCppKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('alignas') or S.Same('alignof') or S.Same('and') or S.Same('and_eq') or
    S.Same('asm') or S.Same('auto') or S.Same('bitand') or S.Same('bitor') or
    S.Same('bool') or S.Same('break') or S.Same('case') or S.Same('catch') or
    S.Same('char') or S.Same('char8_t') or S.Same('char16_t') or S.Same('char32_t') or
    S.Same('class') or S.Same('compl') or S.Same('concept') or S.Same('const') or
    S.Same('consteval') or S.Same('constexpr') or S.Same('constinit') or
    S.Same('const_cast') or S.Same('continue') or S.Same('co_await') or
    S.Same('co_return') or S.Same('co_yield') or S.Same('decltype') or
    S.Same('default') or S.Same('delete') or S.Same('do') or S.Same('double') or
    S.Same('dynamic_cast') or S.Same('else') or S.Same('enum') or
    S.Same('explicit') or S.Same('export') or S.Same('extern') or S.Same('false') or
    S.Same('float') or S.Same('for') or S.Same('friend') or S.Same('goto') or
    S.Same('if') or S.Same('inline') or S.Same('int') or S.Same('long') or
    S.Same('mutable') or S.Same('namespace') or S.Same('new') or S.Same('noexcept') or
    S.Same('not') or S.Same('not_eq') or S.Same('nullptr') or S.Same('operator') or
    S.Same('or') or S.Same('or_eq') or S.Same('private') or S.Same('protected') or
    S.Same('public') or S.Same('register') or S.Same('reinterpret_cast') or
    S.Same('requires') or S.Same('return') or S.Same('short') or S.Same('signed') or
    S.Same('sizeof') or S.Same('static') or S.Same('static_assert') or
    S.Same('static_cast') or S.Same('struct') or S.Same('switch') or
    S.Same('template') or S.Same('this') or S.Same('thread_local') or S.Same('throw') or
    S.Same('true') or S.Same('try') or S.Same('typedef') or S.Same('typeid') or
    S.Same('typename') or S.Same('union') or S.Same('unsigned') or S.Same('using') or
    S.Same('virtual') or S.Same('void') or S.Same('volatile') or S.Same('wchar_t') or
    S.Same('while') or S.Same('xor') or S.Same('xor_eq');
end;

function MakeSafeCppParamName(const Name: TP_String; Index: integer): TP_String;
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

  if IsCppKeyword(Result) then
    Result := Result + '_';
end;

function CppStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
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
    else
      Result.Append(c);
  end;
  Result.Append('"');
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

procedure EmitComment(Lines: TPascalStringList; const Comment: TP_String);
var
  StartPos, EndPos: integer;
  Line: TP_String;
begin
  if Comment.Len = 0 then
    Exit;

  StartPos := 1;
  while StartPos <= Comment.Len do
  begin
    EndPos := StartPos;
    while (EndPos <= Comment.Len) and (Comment[EndPos] <> #10) and (Comment[EndPos] <> #13) do
      Inc(EndPos);

    if EndPos > StartPos then
    begin
      Line := Comment.GetString(StartPos, EndPos);
      Line := StripCommentMarkers(Line);
      if Line.Len > 0 then
        Lines.Add('// ' + Line.Text);
    end;

    StartPos := EndPos;
    while (StartPos <= Comment.Len) and ((Comment[StartPos] = #10) or (Comment[StartPos] = #13)) do
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

function BuildParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCppParamName(Params[i].Name, i);
    PTyp := ABI_Type_To_Cpp_Param_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PTyp + ' ' + PName;
  end;
end;

function BuildArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCppParamName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function BuildParamDeclWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Tmp := BuildParamDecl(Params);
  if Tmp = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Tmp
  else
    Result := Prefix + ', ' + Tmp;
end;

procedure EmitWriteStatements(Lines: TPascalStringList; const Params: TParamArray; const Indent: string);
var
  i: integer;
  PName: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCppParamName(Params[i].Name, i);
    Lines.Add(Indent + 'param.write(' + PName + ');');
  end;
end;

procedure EmitReadSuccessResult(Lines: TPascalStringList; const F: TFunctionStructure; const Indent: string);
var
  RetType: TP_String;
begin
  if IsStringABIType(F.ReturnType) then
  begin
    Lines.Add(Indent + 'std::string _ret;');
    Lines.Add(Indent + 'if (!_res.read(_ret)) {');
    Lines.Add(Indent + '    throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
      '\": response truncated (result)"));');
    Lines.Add(Indent + '}');
    Lines.Add(Indent + 'return _ret;');
  end
  else
  begin
    RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
    Lines.Add(Indent + RetType + ' _ret = 0;');
    Lines.Add(Indent + 'if (!_res.read(_ret)) {');
    Lines.Add(Indent + '    throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
      '\": response truncated (result)"));');
    Lines.Add(Indent + '}');
    Lines.Add(Indent + 'return _ret;');
  end;
end;

procedure EmitCallCheckResponse(Lines: TPascalStringList; const F: TFunctionStructure; const Indent: string);
begin
  Lines.Add(Indent + 'if (_res.size() == 0) {');
  Lines.Add(Indent + '    throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
    '\" returned empty response (timeout or target not found)"));');
  Lines.Add(Indent + '}');
  Lines.Add(Indent + '_res.seek(0);');
  Lines.Add(Indent + 'std::uint8_t _status = 0;');
  Lines.Add(Indent + 'if (!_res.read(_status)) {');
  Lines.Add(Indent + '    throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
    '\": response truncated (status byte)"));');
  Lines.Add(Indent + '}');
  Lines.Add(Indent + 'if (_status != STATUS_OK) {');
  Lines.Add(Indent + '    std::string _err;');
  Lines.Add(Indent + '    try { _res.read(_err); } catch (...) {}');
  Lines.Add(Indent + '    throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
    '\" failed: ") + _err);');
  Lines.Add(Indent + '}');
end;

procedure EmitFuncDecl_AppCall(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  ParamDecl := BuildParamDecl(F.Params);
  Lines.Add(RetType + ' ' + ApiName + '(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_AppAsync(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('', F.Params);
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + 'std::function<void(lingofuse::AsyncResult)> _on_complete';
  Lines.Add('void ' + ApiName + '_Async(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_AppAsyncSeq(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('', F.Params);
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + 'std::function<void(lingofuse::AsyncResult)> _on_complete';
  Lines.Add('void ' + ApiName + '_AsyncSequenced(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_UidCall(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  Lines.Add(RetType + ' ' + ApiName + '_UID_Call(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_UidAsync(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';
  Lines.Add('void ' + ApiName + '_UID_Async(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_UidAsyncSeq(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';
  Lines.Add('void ' + ApiName + '_UID_AsyncSequenced(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_P2PCall(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  Lines.Add(RetType + ' ' + ApiName + '_P2PName_Call(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_P2PAsync(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';
  Lines.Add('void ' + ApiName + '_P2PName_Async(' + ParamDecl + ');');
end;

procedure EmitFuncDecl_P2PAsyncSeq(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';
  Lines.Add('void ' + ApiName + '_P2PName_AsyncSequenced(' + ParamDecl + ');');
end;

procedure EmitProcDecl_AppNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);
  Lines.Add('void ' + ApiName + '(' + ParamDecl + ');');
end;

procedure EmitProcDecl_AppSeqNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);
  Lines.Add('void ' + ApiName + '_SequencedNotify(' + ParamDecl + ');');
end;

procedure EmitProcDecl_UidNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  Lines.Add('void ' + ApiName + '_UID_Notify(' + ParamDecl + ');');
end;

procedure EmitProcDecl_UidSeqNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  Lines.Add('void ' + ApiName + '_UID_SequencedNotify(' + ParamDecl + ');');
end;

procedure EmitProcDecl_P2PNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  Lines.Add('void ' + ApiName + '_P2PName_Notify(' + ParamDecl + ');');
end;

procedure EmitProcDecl_P2PSeqNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  Lines.Add('void ' + ApiName + '_P2PName_SequencedNotify(' + ParamDecl + ');');
end;

procedure EmitFuncImpl_AppCall(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  ParamDecl := BuildParamDecl(F.Params);

  Lines.Add(RetType + ' ' + ApiName + '(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    auto _res_opt = lingofuse::tryCall(ABI_TargetApp, param, ABI_Timeout);');
  Lines.Add('    if (!_res_opt) {');
  Lines.Add('        throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
    '\" returned nil (timeout or target not found)"));');
  Lines.Add('    }');
  Lines.Add('    lingofuse::DataHandle& _res = *_res_opt;');
  EmitCallCheckResponse(Lines, F, '    ');
  EmitReadSuccessResult(Lines, F, '    ');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_AppAsync(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('', F.Params);
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + 'std::function<void(lingofuse::AsyncResult)> _on_complete';

  Lines.Add('void ' + ApiName + '_Async(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    lingofuse::callAsync(ABI_TargetApp, param, std::move(_on_complete));');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_AppAsyncSeq(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('', F.Params);
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + 'std::function<void(lingofuse::AsyncResult)> _on_complete';

  Lines.Add('void ' + ApiName + '_AsyncSequenced(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    lingofuse::callAsyncSequenced(ABI_TargetApp, param, std::move(_on_complete));');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_UidCall(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);

  Lines.Add(RetType + ' ' + ApiName + '_UID_Call(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    TP2P_UID _raw_uid;');
  Lines.Add('    std::memcpy(_raw_uid.bytes, _uid.data(), 32);');
  Lines.Add('    TDataHnd _raw_res = LF_UID_Call(_raw_uid, param.get(), ABI_Timeout);');
  Lines.Add('    if (_raw_res == nullptr) {');
  Lines.Add('        throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
    '\" returned nil (timeout or target not found)"));');
  Lines.Add('    }');
  Lines.Add('    lingofuse::DataHandle _res(_raw_res, true);');
  EmitCallCheckResponse(Lines, F, '    ');
  EmitReadSuccessResult(Lines, F, '    ');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_UidAsync(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';

  Lines.Add('void ' + ApiName + '_UID_Async(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    TP2P_UID _raw_uid;');
  Lines.Add('    std::memcpy(_raw_uid.bytes, _uid.data(), 32);');
  Lines.Add('    lingofuse::callAsyncByUid(_raw_uid, param, std::move(_on_complete));');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_UidAsyncSeq(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';

  Lines.Add('void ' + ApiName + '_UID_AsyncSequenced(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    TP2P_UID _raw_uid;');
  Lines.Add('    std::memcpy(_raw_uid.bytes, _uid.data(), 32);');
  Lines.Add('    auto* _h = new _lf_async_holder{ std::move(_on_complete) };');
  Lines.Add('    int _rc = LF_UID_Async_Sequenced_Call(_raw_uid, param.get(), _h, &_lf_async_trampoline);');
  Lines.Add('    if (_rc != 1) {');
  Lines.Add('        try { _h->cb(lingofuse::AsyncResult(std::string("async call was not dispatched"))); } catch (...) {}');
  Lines.Add('        delete _h;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_P2PCall(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);

  Lines.Add(RetType + ' ' + ApiName + '_P2PName_Call(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    TDataHnd _raw_res = LF_P2PNAME_Call(_p2p_name.c_str(), param.get(), ABI_Timeout);');
  Lines.Add('    if (_raw_res == nullptr) {');
  Lines.Add('        throw EABI_RemoteError(std::string("ABI call \"' + F.Name.Text +
    '\" returned nil (timeout or target not found)"));');
  Lines.Add('    }');
  Lines.Add('    lingofuse::DataHandle _res(_raw_res, true);');
  EmitCallCheckResponse(Lines, F, '    ');
  EmitReadSuccessResult(Lines, F, '    ');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_P2PAsync(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';

  Lines.Add('void ' + ApiName + '_P2PName_Async(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    lingofuse::callAsyncByP2PName(_p2p_name, param, std::move(_on_complete));');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFuncImpl_P2PAsyncSeq(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);
  ParamDecl := ParamDecl + ', std::function<void(lingofuse::AsyncResult)> _on_complete';

  Lines.Add('void ' + ApiName + '_P2PName_AsyncSequenced(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    auto* _h = new _lf_async_holder{ std::move(_on_complete) };');
  Lines.Add('    int _rc = LF_P2PNAME_Async_Sequenced_Call(_p2p_name.c_str(), param.get(), _h, &_lf_async_trampoline);');
  Lines.Add('    if (_rc != 1) {');
  Lines.Add('        try { _h->cb(lingofuse::AsyncResult(std::string("async call was not dispatched"))); } catch (...) {}');
  Lines.Add('        delete _h;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcImpl_AppNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);

  Lines.Add('void ' + ApiName + '(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    lingofuse::notify(ABI_TargetApp, param);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcImpl_AppSeqNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);

  Lines.Add('void ' + ApiName + '_SequencedNotify(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    lingofuse::sequencedNotify(ABI_TargetApp, param);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcImpl_UidNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);

  Lines.Add('void ' + ApiName + '_UID_Notify(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    TP2P_UID _raw_uid;');
  Lines.Add('    std::memcpy(_raw_uid.bytes, _uid.data(), 32);');
  Lines.Add('    LF_UID_Notify(_raw_uid, param.get());');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcImpl_UidSeqNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::array<std::uint8_t, 32>& _uid', F.Params);

  Lines.Add('void ' + ApiName + '_UID_SequencedNotify(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    TP2P_UID _raw_uid;');
  Lines.Add('    std::memcpy(_raw_uid.bytes, _uid.data(), 32);');
  Lines.Add('    LF_UID_Sequenced_Notify(_raw_uid, param.get());');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcImpl_P2PNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);

  Lines.Add('void ' + ApiName + '_P2PName_Notify(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    LF_P2PNAME_Notify(_p2p_name.c_str(), param.get());');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcImpl_P2PSeqNotify(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('const std::string& _p2p_name', F.Params);

  Lines.Add('void ' + ApiName + '_P2PName_SequencedNotify(' + ParamDecl + ') {');
  Lines.Add('    lingofuse::DataHandle param(' + CppStrLit(ApiName) + ');');
  EmitWriteStatements(Lines, F.Params, '    ');
  Lines.Add('    LF_P2PNAME_Sequenced_Notify(_p2p_name.c_str(), param.get());');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallHppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, TargetAppName: TP_String;
  ProtocolGuard: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallHppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallHppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  TargetAppName := NormalizedUnit + '_abi';
  ProtocolGuard := 'LINGOFUSE_ABI_WIRE_PROTOCOL_' + NsName + '_DEFINED';

  Log(PFormat('Generating C++ ABI call header for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty header.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#pragma once');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <array>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <functional>');
    Lines.Add('#include <optional>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');
    Lines.Add('extern std::string ABI_TargetApp;');
    Lines.Add('extern std::uint64_t ABI_Timeout;');
    Lines.Add('');
    Lines.Add('#ifndef ' + ProtocolGuard);
    Lines.Add('#define ' + ProtocolGuard);
    Lines.Add('constexpr std::uint8_t STATUS_OK    = 0x00;');
    Lines.Add('constexpr std::uint8_t STATUS_ERROR = 0xFF;');
    Lines.Add('#endif');
    Lines.Add('');
    Lines.Add('class EABI_RemoteError : public std::runtime_error {');
    Lines.Add('public:');
    Lines.Add('    explicit EABI_RemoteError(const std::string& msg)');
    Lines.Add('        : std::runtime_error(msg) {}');
    Lines.Add('};');
    Lines.Add('');

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

      if F.IsFunction then
      begin
        EmitComment(Lines, F.Comment);
        EmitFuncDecl_AppCall(Lines, F, ApiName);
        EmitFuncDecl_AppAsync(Lines, F, ApiName);
        EmitFuncDecl_AppAsyncSeq(Lines, F, ApiName);
        EmitFuncDecl_UidCall(Lines, F, ApiName);
        EmitFuncDecl_UidAsync(Lines, F, ApiName);
        EmitFuncDecl_UidAsyncSeq(Lines, F, ApiName);
        EmitFuncDecl_P2PCall(Lines, F, ApiName);
        EmitFuncDecl_P2PAsync(Lines, F, ApiName);
        EmitFuncDecl_P2PAsyncSeq(Lines, F, ApiName);
      end
      else
      begin
        EmitComment(Lines, F.Comment);
        EmitProcDecl_AppNotify(Lines, F, ApiName);
        EmitProcDecl_AppSeqNotify(Lines, F, ApiName);
        EmitProcDecl_UidNotify(Lines, F, ApiName);
        EmitProcDecl_UidSeqNotify(Lines, F, ApiName);
        EmitProcDecl_P2PNotify(Lines, F, ApiName);
        EmitProcDecl_P2PSeqNotify(Lines, F, ApiName);
      end;
      Lines.Add('');
    end;

    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call header.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

function GenerateABICallCppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallCppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallCppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C++ ABI call implementation for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty implementation.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#include "' + NormalizedUnit + '_abi_call.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <array>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstring>');
    Lines.Add('#include <functional>');
    Lines.Add('#include <optional>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');
    Lines.Add('std::string ABI_TargetApp = ' + CppStrLit(TargetAppName) + ';');
    Lines.Add('std::uint64_t ABI_Timeout = 5000;');
    Lines.Add('');

    Lines.Add('namespace {');
    Lines.Add('');
    Lines.Add('struct _lf_async_holder {');
    Lines.Add('    std::function<void(lingofuse::AsyncResult)> cb;');
    Lines.Add('};');
    Lines.Add('');
    Lines.Add('void LF_CDECL _lf_async_trampoline(void* data, void* result) {');
    Lines.Add('    auto* h = static_cast<_lf_async_holder*>(data);');
    Lines.Add('    if (h == nullptr) return;');
    Lines.Add('    try {');
    Lines.Add('        if (result == nullptr) {');
    Lines.Add('            h->cb(lingofuse::AsyncResult(std::string("nil response (timeout or target not found)")));');
    Lines.Add('        } else {');
    Lines.Add('            h->cb(lingofuse::AsyncResult(static_cast<TDataHnd>(result)));');
    Lines.Add('        }');
    Lines.Add('    } catch (...) {}');
    Lines.Add('    delete h;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('} // namespace');
    Lines.Add('');

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

      if F.IsFunction then
      begin
        EmitFuncImpl_AppCall(Lines, F, ApiName);
        EmitFuncImpl_AppAsync(Lines, F, ApiName);
        EmitFuncImpl_AppAsyncSeq(Lines, F, ApiName);
        EmitFuncImpl_UidCall(Lines, F, ApiName);
        EmitFuncImpl_UidAsync(Lines, F, ApiName);
        EmitFuncImpl_UidAsyncSeq(Lines, F, ApiName);
        EmitFuncImpl_P2PCall(Lines, F, ApiName);
        EmitFuncImpl_P2PAsync(Lines, F, ApiName);
        EmitFuncImpl_P2PAsyncSeq(Lines, F, ApiName);
      end
      else
      begin
        EmitProcImpl_AppNotify(Lines, F, ApiName);
        EmitProcImpl_AppSeqNotify(Lines, F, ApiName);
        EmitProcImpl_UidNotify(Lines, F, ApiName);
        EmitProcImpl_UidSeqNotify(Lines, F, ApiName);
        EmitProcImpl_P2PNotify(Lines, F, ApiName);
        EmitProcImpl_P2PSeqNotify(Lines, F, ApiName);
      end;
    end;

    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call implementation.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'cpp',
    'xxx_abi_call.hpp',
    gkCall,
    'C++ ABI call header',
    @GenerateABICallHppCode);

  RegisterGenerator(
    'cpp',
    'xxx_abi_call.cpp',
    gkCall,
    'C++ ABI call implementation',
    @GenerateABICallCppCode);

end.
