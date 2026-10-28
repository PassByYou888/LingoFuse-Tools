unit dart_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallDartCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Dart_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'int'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'int'
  else if T.Same('word') then
    Result := 'int'
  else if T.Same('smallint') then
    Result := 'int'
  else if T.Same('byte') then
    Result := 'int'
  else if T.Same('uint64') then
    Result := 'int'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'double'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Writer_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'writeInt32'
  else if T.Same('int64') then
    Result := 'writeInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'writeUInt32'
  else if T.Same('word') then
    Result := 'writeUInt16'
  else if T.Same('smallint') then
    Result := 'writeInt16'
  else if T.Same('byte') then
    Result := 'writeUInt8'
  else if T.Same('uint64') then
    Result := 'writeUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'writeDouble'
  else if T.Same('single') then
    Result := 'writeSingle'
  else if IsStringABIType(T) then
    Result := 'writeString'
  else
    Result := '';
end;

function ABI_Type_To_Reader_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'readInt32'
  else if T.Same('int64') then
    Result := 'readInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'readUInt32'
  else if T.Same('word') then
    Result := 'readUInt16'
  else if T.Same('smallint') then
    Result := 'readInt16'
  else if T.Same('byte') then
    Result := 'readUInt8'
  else if T.Same('uint64') then
    Result := 'readUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'readDouble'
  else if T.Same('single') then
    Result := 'readSingle'
  else if IsStringABIType(T) then
    Result := 'readString'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Dart_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsDartKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('assert') or S.Same('async') or
    S.Same('await') or S.Same('break') or S.Same('case') or S.Same('catch') or
    S.Same('class') or S.Same('const') or S.Same('continue') or S.Same('covariant') or
    S.Same('default') or S.Same('deferred') or S.Same('do') or S.Same('dynamic') or
    S.Same('else') or S.Same('enum') or S.Same('export') or S.Same('extends') or
    S.Same('extension') or S.Same('external') or S.Same('factory') or S.Same('false') or
    S.Same('final') or S.Same('finally') or S.Same('for') or S.Same('Function') or
    S.Same('get') or S.Same('hide') or S.Same('if') or S.Same('implements') or
    S.Same('import') or S.Same('in') or S.Same('interface') or S.Same('is') or
    S.Same('late') or S.Same('library') or S.Same('mixin') or S.Same('new') or
    S.Same('null') or S.Same('on') or S.Same('operator') or S.Same('part') or
    S.Same('required') or S.Same('rethrow') or S.Same('return') or S.Same('set') or
    S.Same('show') or S.Same('static') or S.Same('super') or S.Same('switch') or
    S.Same('sync') or S.Same('this') or S.Same('throw') or S.Same('true') or
    S.Same('try') or S.Same('typedef') or S.Same('var') or S.Same('void') or
    S.Same('while') or S.Same('with') or S.Same('yield');
end;

function IsDartReservedLocal(const S: TP_String): boolean;
begin
  Result :=
    S.Same('ctx') or S.Same('uid') or S.Same('onResult') or
    S.Same('param') or S.Same('target') or S.Same('p2pName') or
    S.Same('name') or S.Same('abi') or S.Same('_lf_target') or
    S.Same('_lf_req') or S.Same('_lf_resp') or S.Same('_lf_bytes') or
    S.Same('_lf_w') or S.Same('_lf_r') or S.Same('_lf_completer');
end;

function MakeSafeDartIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsDartKeyword(Result) then
    Result := Result + '_';

  if IsDartReservedLocal(Result) then
    Result := Result + '_param';

  if Result.ComparePos(1, '_lf_') or Result.ComparePos(1, '_u_') then
    Result := '_u_' + Result;
end;

function DartStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
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
  Result.Append(#39);
end;

type
  TArryFunctionStructure = array of TFunctionStructure;

procedure PartitionByKind(const src: TArryFunctionStructure;
  var funcs, procs: TArryFunctionStructure);
var
  i, nf, np: integer;
begin
  SetLength(funcs, Length(src));
  SetLength(procs, Length(src));
  nf := 0;
  np := 0;
  for i := 0 to High(src) do
  begin
    if src[i].IsFunction then
    begin
      funcs[nf] := src[i];
      Inc(nf);
    end
    else
    begin
      procs[np] := src[i];
      Inc(np);
    end;
  end;
  SetLength(funcs, nf);
  SetLength(procs, np);
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
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not supported',
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

function BuildDartParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeDartIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Dart_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PTyp + ' ' + PName;
  end;
end;

function BuildDartArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeDartIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

procedure EmitWriteParams(Lines: TPascalStringList; const F: TFunctionStructure;
  const Indent: string);
var
  i: integer;
  PName, WriteFn: TP_String;
begin
  Lines.Add(Indent + 'final _lf_w = AbiWriter();');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeDartIdent(F.Params[i].Name, i);
    WriteFn := ABI_Type_To_Writer_Method(F.Params[i].PascalType);
    Lines.Add(Indent + '_lf_w.' + WriteFn + '(' + PName + ');');
  end;
  Lines.Add(Indent + '_lf_req.writeBytes(_lf_w.takeBytes());');
  Lines.Add(Indent + '_lf_req.position = 0;');
end;

procedure EmitDecodeResult_Return(Lines: TPascalStringList;
  const F: TFunctionStructure; const BytesVar, Indent: string);
var
  ReadFn: TP_String;
begin
  ReadFn := ABI_Type_To_Reader_Method(F.ReturnType);
  Lines.Add(Indent + 'if (' + BytesVar + '.isEmpty) {');
  Lines.Add(Indent + '  throw StateError(' + DartStrLit('empty response') + ');');
  Lines.Add(Indent + '}');
  Lines.Add(Indent + 'final _lf_r = AbiReader(' + BytesVar + ');');
  Lines.Add(Indent + 'if (_lf_r.readUInt8() != STATUS_OK) {');
  Lines.Add(Indent + '  throw StateError(' + DartStrLit('remote error: ') + ' + _lf_r.readString());');
  Lines.Add(Indent + '}');
  Lines.Add(Indent + 'return _lf_r.' + ReadFn + '();');
end;

procedure EmitDecodeResult_Complete(Lines: TPascalStringList;
  const F: TFunctionStructure; const BytesVar, CompleterVar, Indent: string);
var
  ReadFn: TP_String;
begin
  ReadFn := ABI_Type_To_Reader_Method(F.ReturnType);
  Lines.Add(Indent + 'try {');
  Lines.Add(Indent + '  if (' + BytesVar + ' == null || ' + BytesVar + '.isEmpty) {');
  Lines.Add(Indent + '    ' + CompleterVar + '.completeError(StateError(' + DartStrLit('empty response') + '));');
  Lines.Add(Indent + '    return;');
  Lines.Add(Indent + '  }');
  Lines.Add(Indent + '  final _lf_r = AbiReader(' + BytesVar + ');');
  Lines.Add(Indent + '  if (_lf_r.readUInt8() != STATUS_OK) {');
  Lines.Add(Indent + '    ' + CompleterVar + '.completeError(StateError(' + DartStrLit('remote error: ') + ' + _lf_r.readString()));');
  Lines.Add(Indent + '    return;');
  Lines.Add(Indent + '  }');
  Lines.Add(Indent + '  ' + CompleterVar + '.complete(_lf_r.' + ReadFn + '());');
  Lines.Add(Indent + '} catch (e) {');
  Lines.Add(Indent + '  ' + CompleterVar + '.completeError(e);');
  Lines.Add(Indent + '}');
end;

procedure EmitDecodeResult_Callback(Lines: TPascalStringList;
  const F: TFunctionStructure; const BytesVar, Indent: string);
var
  ReadFn: TP_String;
begin
  ReadFn := ABI_Type_To_Reader_Method(F.ReturnType);
  Lines.Add(Indent + 'try {');
  Lines.Add(Indent + '  if (' + BytesVar + ' == null || ' + BytesVar + '.isEmpty) {');
  Lines.Add(Indent + '    onResult(null, ' + DartStrLit('empty response') + ');');
  Lines.Add(Indent + '    return;');
  Lines.Add(Indent + '  }');
  Lines.Add(Indent + '  final _lf_r = AbiReader(' + BytesVar + ');');
  Lines.Add(Indent + '  if (_lf_r.readUInt8() != STATUS_OK) {');
  Lines.Add(Indent + '    onResult(null, ' + DartStrLit('remote error: ') + ' + _lf_r.readString());');
  Lines.Add(Indent + '    return;');
  Lines.Add(Indent + '  }');
  Lines.Add(Indent + '  onResult(_lf_r.' + ReadFn + '(), null);');
  Lines.Add(Indent + '} catch (e) {');
  Lines.Add(Indent + '  onResult(null, e.toString());');
  Lines.Add(Indent + '}');
end;

function MakeUniqueApiName(const Source: TP_String; Used: TPascalStringList): TP_String;
var
  j: integer;
begin
  Result := MakeApiName(Source);
  if Used.IndexOf(Result) >= 0 then
  begin
    j := 1;
    while Used.IndexOf(Result + '_' + umlIntToStr(j).Text) >= 0 do
      Inc(j);
    Result := Result + '_' + umlIntToStr(j).Text;
  end;
  Used.Add(Result);
end;

procedure EmitSyncFunction(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  if ParamDecl <> '' then
    FullParamDecl := 'String _lf_target, ' + ParamDecl
  else
    FullParamDecl := 'String _lf_target';

  Lines.Add(RetType + ' _sync' + ApiName + '(' + FullParamDecl + ') {');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    final _lf_resp = Framework.call(_lf_target, _lf_req, timeoutMs: ABI_TIMEOUT_MS);');
  Lines.Add('    try {');
  Lines.Add('      final _lf_bytes = _lf_resp.readAllBytes();');
  EmitDecodeResult_Return(Lines, F, '_lf_bytes', '      ');
  Lines.Add('    } finally {');
  Lines.Add('      _lf_resp.dispose();');
  Lines.Add('    }');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAppCall_Future(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, ArgList, RetType, CallExpr: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  ArgList := BuildDartArgList(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  if ArgList <> '' then
    CallExpr := '_sync' + ApiName + '(ABI_TARGET_APP, ' + ArgList + ')'
  else
    CallExpr := '_sync' + ApiName + '(ABI_TARGET_APP)';

  Lines.Add('Future<' + RetType + '> ' + ApiName + '(' + ParamDecl + ') {');
  Lines.Add('  return Isolate.run(() => ' + CallExpr + ');');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAppCall_Async(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, ArgList, RetType, FullParamDecl, CallbackType: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);
  CallbackType := 'void Function(' + RetType + '? result, String? error)';

  if ParamDecl <> '' then
    FullParamDecl := ParamDecl + ', ' + CallbackType + ' onResult'
  else
    FullParamDecl := CallbackType + ' onResult';

  Lines.Add('void ' + ApiName + 'Async(' + FullParamDecl + ') {');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    Framework.callAsync(ABI_TARGET_APP, _lf_req, (result, error) {');
  Lines.Add('      if (error != null) { onResult(null, error); return; }');
  EmitDecodeResult_Callback(Lines, F, 'result', '      ');
  Lines.Add('    });');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAppCall_Sequenced(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  Lines.Add('Future<' + RetType + '> ' + ApiName + 'Sequenced(' + ParamDecl + ') {');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    final _lf_completer = Completer<' + RetType + '>();');
  Lines.Add('    Framework.callAsyncSequenced(ABI_TARGET_APP, _lf_req, (result, error) {');
  Lines.Add('      if (_lf_completer.isCompleted) return;');
  Lines.Add('      if (error != null) { _lf_completer.completeError(StateError(error)); return; }');
  EmitDecodeResult_Complete(Lines, F, 'result', '_lf_completer', '      ');
  Lines.Add('    });');
  Lines.Add('    return _lf_completer.future;');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitByUid_Future(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  if ParamDecl <> '' then
    FullParamDecl := 'Uint8List uid, ' + ParamDecl
  else
    FullParamDecl := 'Uint8List uid';

  Lines.Add('Future<' + RetType + '> ' + ApiName + 'ByUid(' + FullParamDecl + ') {');
  Lines.Add('  if (uid.length != 32) {');
  Lines.Add('    throw RangeError(' + DartStrLit('UID must be exactly 32 bytes') + ');');
  Lines.Add('  }');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    final _lf_completer = Completer<' + RetType + '>();');
  Lines.Add('    Framework.uidCallAsync(uid, _lf_req, (result, error) {');
  Lines.Add('      if (_lf_completer.isCompleted) return;');
  Lines.Add('      if (error != null) { _lf_completer.completeError(StateError(error)); return; }');
  EmitDecodeResult_Complete(Lines, F, 'result', '_lf_completer', '      ');
  Lines.Add('    });');
  Lines.Add('    return _lf_completer.future;');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitByUid_Async(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl, CallbackType: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);
  CallbackType := 'void Function(' + RetType + '? result, String? error)';

  if ParamDecl <> '' then
    FullParamDecl := 'Uint8List uid, ' + ParamDecl + ', ' + CallbackType + ' onResult'
  else
    FullParamDecl := 'Uint8List uid, ' + CallbackType + ' onResult';

  Lines.Add('void ' + ApiName + 'ByUidAsync(' + FullParamDecl + ') {');
  Lines.Add('  if (uid.length != 32) {');
  Lines.Add('    onResult(null, ' + DartStrLit('UID must be exactly 32 bytes') + ');');
  Lines.Add('    return;');
  Lines.Add('  }');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    Framework.uidCallAsync(uid, _lf_req, (result, error) {');
  Lines.Add('      if (error != null) { onResult(null, error); return; }');
  EmitDecodeResult_Callback(Lines, F, 'result', '      ');
  Lines.Add('    });');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitByUid_Sequenced(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  if ParamDecl <> '' then
    FullParamDecl := 'Uint8List uid, ' + ParamDecl
  else
    FullParamDecl := 'Uint8List uid';

  Lines.Add('Future<' + RetType + '> ' + ApiName + 'ByUidSequenced(' + FullParamDecl + ') {');
  Lines.Add('  if (uid.length != 32) {');
  Lines.Add('    throw RangeError(' + DartStrLit('UID must be exactly 32 bytes') + ');');
  Lines.Add('  }');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    final _lf_completer = Completer<' + RetType + '>();');
  Lines.Add('    Framework.uidCallAsyncSequenced(uid, _lf_req, (result, error) {');
  Lines.Add('      if (_lf_completer.isCompleted) return;');
  Lines.Add('      if (error != null) { _lf_completer.completeError(StateError(error)); return; }');
  EmitDecodeResult_Complete(Lines, F, 'result', '_lf_completer', '      ');
  Lines.Add('    });');
  Lines.Add('    return _lf_completer.future;');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitByP2PName_Future(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  if ParamDecl <> '' then
    FullParamDecl := 'String p2pName, ' + ParamDecl
  else
    FullParamDecl := 'String p2pName';

  Lines.Add('Future<' + RetType + '> ' + ApiName + 'ByP2PName(' + FullParamDecl + ') {');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    final _lf_completer = Completer<' + RetType + '>();');
  Lines.Add('    Framework.p2pnameCallAsync(p2pName, _lf_req, (result, error) {');
  Lines.Add('      if (_lf_completer.isCompleted) return;');
  Lines.Add('      if (error != null) { _lf_completer.completeError(StateError(error)); return; }');
  EmitDecodeResult_Complete(Lines, F, 'result', '_lf_completer', '      ');
  Lines.Add('    });');
  Lines.Add('    return _lf_completer.future;');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitByP2PName_Async(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl, CallbackType: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);
  CallbackType := 'void Function(' + RetType + '? result, String? error)';

  if ParamDecl <> '' then
    FullParamDecl := 'String p2pName, ' + ParamDecl + ', ' + CallbackType + ' onResult'
  else
    FullParamDecl := 'String p2pName, ' + CallbackType + ' onResult';

  Lines.Add('void ' + ApiName + 'ByP2PNameAsync(' + FullParamDecl + ') {');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    Framework.p2pnameCallAsync(p2pName, _lf_req, (result, error) {');
  Lines.Add('      if (error != null) { onResult(null, error); return; }');
  EmitDecodeResult_Callback(Lines, F, 'result', '      ');
  Lines.Add('    });');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitByP2PName_Sequenced(Lines: TPascalStringList; const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl, RetType, FullParamDecl: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);

  if ParamDecl <> '' then
    FullParamDecl := 'String p2pName, ' + ParamDecl
  else
    FullParamDecl := 'String p2pName';

  Lines.Add('Future<' + RetType + '> ' + ApiName + 'ByP2PNameSequenced(' + FullParamDecl + ') {');
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  Lines.Add('    final _lf_completer = Completer<' + RetType + '>();');
  Lines.Add('    Framework.p2pnameCallAsyncSequenced(p2pName, _lf_req, (result, error) {');
  Lines.Add('      if (_lf_completer.isCompleted) return;');
  Lines.Add('      if (error != null) { _lf_completer.completeError(StateError(error)); return; }');
  EmitDecodeResult_Complete(Lines, F, 'result', '_lf_completer', '      ');
  Lines.Add('    });');
  Lines.Add('    return _lf_completer.future;');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNotifyVariant(Lines: TPascalStringList;
  const FuncName, ApiName: TP_String;
  const F: TFunctionStructure; const ParamPrefix: TP_String;
  const RequiresUidCheck: boolean;
  const NotifyCall: TP_String);
var
  ParamDecl, FullParamDecl: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);

  if ParamPrefix <> '' then
  begin
    if ParamDecl <> '' then
      FullParamDecl := ParamPrefix + ', ' + ParamDecl
    else
      FullParamDecl := ParamPrefix;
  end
  else
    FullParamDecl := ParamDecl;

  Lines.Add('void ' + FuncName + '(' + FullParamDecl + ') {');
  if RequiresUidCheck then
  begin
    Lines.Add('  if (uid.length != 32) {');
    Lines.Add('    throw RangeError(' + DartStrLit('UID must be exactly 32 bytes') + ');');
    Lines.Add('  }');
  end;
  Lines.Add('  final _lf_req = DataHandle(' + DartStrLit(ApiName) + ');');
  Lines.Add('  try {');
  EmitWriteParams(Lines, F, '    ');
  if NotifyCall = 'notify' then
    Lines.Add('    Framework.notify(ABI_TARGET_APP, _lf_req);')
  else if NotifyCall = 'sequencedNotify' then
    Lines.Add('    Framework.sequencedNotify(ABI_TARGET_APP, _lf_req);')
  else if NotifyCall = 'uidNotify' then
    Lines.Add('    Framework.uidNotify(uid, _lf_req);')
  else if NotifyCall = 'uidSequencedNotify' then
    Lines.Add('    Framework.uidSequencedNotify(uid, _lf_req);')
  else if NotifyCall = 'p2pnameNotify' then
    Lines.Add('    Framework.p2pnameNotify(p2pName, _lf_req);')
  else if NotifyCall = 'p2pnameSequencedNotify' then
    Lines.Add('    Framework.p2pnameSequencedNotify(p2pName, _lf_req);');
  Lines.Add('  } finally {');
  Lines.Add('    _lf_req.dispose();');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallDartCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs, Funcs, Procs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetApp: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  HasAnyFunction: boolean;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallDartCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallDartCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';

  Log(PFormat('Generating Dart ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call covers %d ABI APIs', [Length(SupportedFuncs)]));

  PartitionByKind(SupportedFuncs, Funcs, Procs);

  HasAnyFunction := Length(Funcs) > 0;

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('// ignore_for_file: non_constant_identifier_names, unused_local_variable, unnecessary_statements');
    Lines.Add('');
    if HasAnyFunction then
    begin
      Lines.Add('import ' + DartStrLit('dart:async') + ';');
      Lines.Add('import ' + DartStrLit('dart:isolate') + ';');
    end;
    Lines.Add('import ' + DartStrLit('dart:typed_data') + ';');
    Lines.Add('');
    Lines.Add('import ' + DartStrLit('package:lingofuse/lingofuse.dart') + ';');
    Lines.Add('');
    Lines.Add('const String ABI_TARGET_APP = ' + DartStrLit(TargetApp) + ';');
    Lines.Add('const int ABI_TIMEOUT_MS = 5000;');
    Lines.Add('');
    Lines.Add('const int STATUS_OK = 0x00;');
    Lines.Add('const int STATUS_ERROR = 0xFF;');
    Lines.Add('');

    if HasAnyFunction then
    begin
      UsedApiNames.Clear;
      for i := 0 to High(Funcs) do
      begin
        F := Funcs[i];
        ApiName := MakeUniqueApiName(F.Name, UsedApiNames);
        EmitSyncFunction(Lines, ApiName, F);
        EmitAppCall_Future(Lines, ApiName, F);
        EmitAppCall_Async(Lines, ApiName, F);
        EmitAppCall_Sequenced(Lines, ApiName, F);
        EmitByUid_Future(Lines, ApiName, F);
        EmitByUid_Async(Lines, ApiName, F);
        EmitByUid_Sequenced(Lines, ApiName, F);
        EmitByP2PName_Future(Lines, ApiName, F);
        EmitByP2PName_Async(Lines, ApiName, F);
        EmitByP2PName_Sequenced(Lines, ApiName, F);
      end;
    end;

    if Length(Procs) > 0 then
    begin
      UsedApiNames.Clear;
      for i := 0 to High(Procs) do
      begin
        F := Procs[i];
        ApiName := MakeUniqueApiName(F.Name, UsedApiNames);
        EmitNotifyVariant(Lines, ApiName + 'Notify', ApiName, F, '', False, 'notify');
        EmitNotifyVariant(Lines, ApiName + 'SequencedNotify', ApiName, F, '', False, 'sequencedNotify');
        EmitNotifyVariant(Lines, ApiName + 'NotifyByUid', ApiName, F,
          'Uint8List uid', True, 'uidNotify');
        EmitNotifyVariant(Lines, ApiName + 'SequencedNotifyByUid', ApiName, F,
          'Uint8List uid', True, 'uidSequencedNotify');
        EmitNotifyVariant(Lines, ApiName + 'NotifyByP2PName', ApiName, F,
          'String p2pName', False, 'p2pnameNotify');
        EmitNotifyVariant(Lines, ApiName + 'SequencedNotifyByP2PName', ApiName, F,
          'String p2pName', False, 'p2pnameSequencedNotify');
      end;
    end;

    Result := Lines;
    Log(PFormat('Generated %d lines for Dart ABI call', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'dart',
    'xxx_abi_call.dart',
    gkCall,
    'Dart ABI call implementation',
    @GenerateABICallDartCode);

end.
