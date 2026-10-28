unit rust_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallRsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[rust_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[rust_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Rust_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'i32'
  else if T.Same('int64') then
    Result := 'i64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'u32'
  else if T.Same('word') then
    Result := 'u16'
  else if T.Same('smallint') then
    Result := 'i16'
  else if T.Same('byte') then
    Result := 'u8'
  else if T.Same('uint64') then
    Result := 'u64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'f64'
  else if T.Same('single') then
    Result := 'f32'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Rust_Param_Decl(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := '&' + #39 + 'static str'
  else
    Result := ABI_Type_To_Rust_Decl(T);
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Rust_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsRustKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('as') or S.Same('async') or S.Same('await') or S.Same('break') or
    S.Same('const') or S.Same('continue') or S.Same('crate') or S.Same('dyn') or
    S.Same('else') or S.Same('enum') or S.Same('extern') or S.Same('false') or
    S.Same('fn') or S.Same('for') or S.Same('if') or S.Same('impl') or
    S.Same('in') or S.Same('let') or S.Same('loop') or S.Same('match') or
    S.Same('mod') or S.Same('move') or S.Same('mut') or S.Same('pub') or
    S.Same('ref') or S.Same('return') or S.Same('self') or S.Same('Self') or
    S.Same('static') or S.Same('struct') or S.Same('super') or S.Same('trait') or
    S.Same('true') or S.Same('type') or S.Same('unsafe') or S.Same('use') or
    S.Same('where') or S.Same('while') or S.Same('try') or S.Same('do') or
    S.Same('abstract') or S.Same('become') or S.Same('box') or S.Same('final') or
    S.Same('macro') or S.Same('override') or S.Same('priv') or S.Same('typeof') or
    S.Same('unsized') or S.Same('virtual') or S.Same('yield');
end;

function MakeSafeRustIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsRustKeyword(Result) then
    Result := Result + '_';

  if Result.Same('uid') or Result.Same('p2p_name') or Result.Same('on_result') or
     Result.Same('param') or Result.Same('target') or Result.Same('resp') or
     Result.Same('raw') or Result.Same('lf_uid') or Result.Same('status') or
     Result.Same('msg') or Result.Same('handle') then
    Result := Result + '_param';
end;

function CStrLit(const S: TP_String): TP_String;
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

procedure EmitCommentLines(Lines: TPascalStringList; const Comment: TP_String);
var
  i, j: integer;
  Line: TP_String;
begin
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
      Line := StripCommentMarkers(Comment.GetString(i, j));
      if Line.Len > 0 then
      begin
        if Line[1] = '*' then
          Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
        if (Line.Len > 0) and (Line[1] = '*') then
          Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
        if Line.Len > 0 then
          Lines.Add('/// ' + Line.Text);
      end;
    end;
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
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

function BuildRustParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRustIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Rust_Param_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName + ': ' + PTyp;
  end;
end;

function BuildArgNames(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRustIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function BuildParamDeclWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Tmp := BuildRustParamDecl(Params);
  if Tmp = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Tmp
  else
    Result := Prefix + ', ' + Tmp;
end;

function BuildArgListWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Tmp := BuildArgNames(Params);
  if Tmp = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Tmp
  else
    Result := Prefix + ', ' + Tmp;
end;

procedure EmitWriteParamStatements(Lines: TPascalStringList; const Params: TParamArray);
var
  i: integer;
  PName: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRustIdent(Params[i].Name, i);
    if IsStringABIType(Params[i].PascalType) then
      Lines.Add('    param.write_string(' + PName + ')?;')
    else
      Lines.Add('    param.write(' + PName + ')?;');
  end;
end;

procedure EmitReadResponseFunction(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType: TP_String;
begin
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);

  Lines.Add('fn read_' + ApiName + '_response(mut handle: DataHandle) -> Result<' + RetType + ', Error> {');
  Lines.Add('    handle.set_position(0)?;');
  Lines.Add('    let status: u8 = handle.read()?;');
  Lines.Add('    if status != STATUS_OK {');
  Lines.Add('        let msg = handle.read_string().unwrap_or_default();');
  Lines.Add('        return Err(Error::new(');
  Lines.Add('            ErrorCode::CallFailed,');
  Lines.Add('            format!("ABI call ' + ApiName + ' failed: {}", msg),');
  Lines.Add('        ));');
  Lines.Add('    }');
  if IsStringABIType(F.ReturnType) then
    Lines.Add('    handle.read_string()')
  else
    Lines.Add('    handle.read()');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitParamBuild(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
begin
  Lines.Add('    let mut param = DataHandle::new(' + CStrLit(ApiName) + ')?;');
  EmitWriteParamStatements(Lines, F.Params);
  Lines.Add('    param.set_position(0)?;');
end;

procedure EmitSyncAppCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl: TP_String;
begin
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);
  ParamDecl := BuildRustParamDecl(F.Params);

  EmitCommentLines(Lines, F.Comment);
  Lines.Add('pub fn ' + ApiName + '(' + ParamDecl + ') -> Result<' + RetType + ', Error> {');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let target = ABI_TARGET_APP.read().unwrap().to_string();');
  Lines.Add('    let resp = _expect_response(');
  Lines.Add('        framework::try_call(&target, &param, ABI_TIMEOUT.load(Ordering::SeqCst))?,');
  Lines.Add('        ' + CStrLit(ApiName) + ',');
  Lines.Add('    )?;');
  Lines.Add('    read_' + ApiName + '_response(resp)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAsyncAppCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, FullDecl: TP_String;
begin
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);
  ParamDecl := BuildRustParamDecl(F.Params);
  if ParamDecl <> '' then
    FullDecl := ParamDecl + ', on_result: F'
  else
    FullDecl := 'on_result: F';

  Lines.Add('pub fn ' + ApiName + '_Async<F>(' + FullDecl + ') -> Result<(), Error>');
  Lines.Add('where');
  Lines.Add('    F: FnOnce(Result<' + RetType + ', Error>) + Send + ' + #39 + 'static,');
  Lines.Add('{');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let target = ABI_TARGET_APP.read().unwrap().to_string();');
  Lines.Add('    async_call::call_async(&target, &param, move |r| {');
  Lines.Add('        on_result(r.and_then(read_' + ApiName + '_response));');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn ' + ApiName + '_AsyncSequenced<F>(' + FullDecl + ') -> Result<(), Error>');
  Lines.Add('where');
  Lines.Add('    F: FnOnce(Result<' + RetType + ', Error>) + Send + ' + #39 + 'static,');
  Lines.Add('{');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let target = ABI_TARGET_APP.read().unwrap().to_string();');
  Lines.Add('    async_call::call_async_sequenced(&target, &param, move |r| {');
  Lines.Add('        on_result(r.and_then(read_' + ApiName + '_response));');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitUIDVariants(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, AsyncFullDecl: TP_String;
begin
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('uid: Uid', F.Params);
  AsyncFullDecl := ParamDecl + ', on_result: F';

  Lines.Add('pub fn ' + ApiName + '_UID_Call(' + ParamDecl + ') -> Result<' + RetType + ', Error> {');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let resp = _expect_response(');
  Lines.Add('        framework::try_call_by_uid(uid, &param, ABI_TIMEOUT.load(Ordering::SeqCst))?,');
  Lines.Add('        ' + CStrLit(ApiName) + ',');
  Lines.Add('    )?;');
  Lines.Add('    read_' + ApiName + '_response(resp)');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn ' + ApiName + '_UID_Async<F>(' + AsyncFullDecl + ') -> Result<(), Error>');
  Lines.Add('where');
  Lines.Add('    F: FnOnce(Result<' + RetType + ', Error>) + Send + ' + #39 + 'static,');
  Lines.Add('{');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    async_call::call_async_by_uid(uid, &param, move |r| {');
  Lines.Add('        on_result(r.and_then(read_' + ApiName + '_response));');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn ' + ApiName + '_UID_AsyncSequenced<F>(' + AsyncFullDecl + ') -> Result<(), Error>');
  Lines.Add('where');
  Lines.Add('    F: FnOnce(Result<' + RetType + ', Error>) + Send + ' + #39 + 'static,');
  Lines.Add('{');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let lf_uid = LfP2PUid { bytes: uid.to_bytes() };');
  Lines.Add('    let raw = param.raw().ok_or_else(|| {');
  Lines.Add('        Error::new(ErrorCode::NullHandle, "param is null")');
  Lines.Add('    })?;');
  Lines.Add('    _lf_async_impl::submit_uid_sequenced(lf_uid, raw, move |r| {');
  Lines.Add('        on_result(r.and_then(read_' + ApiName + '_response));');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitP2PNameVariants(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, AsyncFullDecl: TP_String;
begin
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('p2p_name: &' + #39 + 'static str', F.Params);
  AsyncFullDecl := ParamDecl + ', on_result: F';

  Lines.Add('pub fn ' + ApiName + '_P2PName_Call(' + ParamDecl + ') -> Result<' + RetType + ', Error> {');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let resp = _expect_response(');
  Lines.Add('        framework::try_call_by_p2p_name(p2p_name, &param, ABI_TIMEOUT.load(Ordering::SeqCst))?,');
  Lines.Add('        ' + CStrLit(ApiName) + ',');
  Lines.Add('    )?;');
  Lines.Add('    read_' + ApiName + '_response(resp)');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn ' + ApiName + '_P2PName_Async<F>(' + AsyncFullDecl + ') -> Result<(), Error>');
  Lines.Add('where');
  Lines.Add('    F: FnOnce(Result<' + RetType + ', Error>) + Send + ' + #39 + 'static,');
  Lines.Add('{');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    async_call::call_async_by_p2p_name(p2p_name, &param, move |r| {');
  Lines.Add('        on_result(r.and_then(read_' + ApiName + '_response));');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn ' + ApiName + '_P2PName_AsyncSequenced<F>(' + AsyncFullDecl + ') -> Result<(), Error>');
  Lines.Add('where');
  Lines.Add('    F: FnOnce(Result<' + RetType + ', Error>) + Send + ' + #39 + 'static,');
  Lines.Add('{');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let raw = param.raw().ok_or_else(|| {');
  Lines.Add('        Error::new(ErrorCode::NullHandle, "param is null")');
  Lines.Add('    })?;');
  Lines.Add('    _lf_async_impl::submit_p2pname_sequenced(p2p_name, raw, move |r| {');
  Lines.Add('        on_result(r.and_then(read_' + ApiName + '_response));');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFunctionVariants(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitReadResponseFunction(Lines, ApiName, F);
  EmitSyncAppCall(Lines, ApiName, F);
  EmitAsyncAppCall(Lines, ApiName, F);
  EmitUIDVariants(Lines, ApiName, F);
  EmitP2PNameVariants(Lines, ApiName, F);
end;

procedure EmitNotifyVariant(Lines: TPascalStringList;
  const ApiName, FuncName, ExtraDecl, ExtraArg, NotifyFn: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix(ExtraDecl, F.Params);
  Lines.Add('pub fn ' + FuncName + '(' + ParamDecl + ') -> Result<(), Error> {');
  EmitParamBuild(Lines, ApiName, F);
  if ExtraArg = '' then
    Lines.Add('    ' + NotifyFn + '(&param)')
  else
    Lines.Add('    ' + NotifyFn + '(' + ExtraArg + ', &param)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcedureVariants(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  EmitCommentLines(Lines, F.Comment);

  ParamDecl := BuildRustParamDecl(F.Params);

  Lines.Add('pub fn ' + ApiName + '(' + ParamDecl + ') -> Result<(), Error> {');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let target = ABI_TARGET_APP.read().unwrap().to_string();');
  Lines.Add('    framework::notify(&target, &param)');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn ' + ApiName + '_SequencedNotify(' + ParamDecl + ') -> Result<(), Error> {');
  EmitParamBuild(Lines, ApiName, F);
  Lines.Add('    let target = ABI_TARGET_APP.read().unwrap().to_string();');
  Lines.Add('    framework::sequenced_notify(&target, &param)');
  Lines.Add('}');
  Lines.Add('');

  EmitNotifyVariant(Lines, ApiName, ApiName + '_UID_Notify',
    'uid: Uid', 'uid', 'framework::notify_by_uid', F);
  EmitNotifyVariant(Lines, ApiName, ApiName + '_UID_SequencedNotify',
    'uid: Uid', 'uid', 'framework::sequenced_notify_by_uid', F);
  EmitNotifyVariant(Lines, ApiName, ApiName + '_P2PName_Notify',
    'p2p_name: &' + #39 + 'static str', 'p2p_name', 'framework::notify_by_p2p_name', F);
  EmitNotifyVariant(Lines, ApiName, ApiName + '_P2PName_SequencedNotify',
    'p2p_name: &' + #39 + 'static str', 'p2p_name', 'framework::sequenced_notify_by_p2p_name', F);
end;

procedure EmitAsyncSequencedModule(Lines: TPascalStringList);
begin
  Lines.Add('mod _lf_async_impl {');
  Lines.Add('    use std::ffi::{c_void, CString};');
  Lines.Add('    use lingofuse::data_handle::DataHandle;');
  Lines.Add('    use lingofuse::error::{Error, ErrorCode};');
  Lines.Add('    use lingofuse::sys::{get_library, DataHnd, LfAsyncCallOnResult, LfP2PUid};');
  Lines.Add('');
  Lines.Add('    pub struct AsyncHolder {');
  Lines.Add('        pub cb: Option<Box<dyn FnOnce(Result<DataHandle, Error>) + Send + ' + #39 + 'static>>,');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    pub unsafe extern "C" fn trampoline(data: *mut c_void, result: DataHnd) {');
  Lines.Add('        if data.is_null() {');
  Lines.Add('            return;');
  Lines.Add('        }');
  Lines.Add('        let mut holder: Box<AsyncHolder> =');
  Lines.Add('            unsafe { Box::from_raw(data as *mut AsyncHolder) };');
  Lines.Add('        if let Some(cb) = holder.cb.take() {');
  Lines.Add('            let h = DataHandle::from_raw(result, false);');
  Lines.Add('            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {');
  Lines.Add('                match h {');
  Lines.Add('                    Ok(handle) => cb(Ok(handle)),');
  Lines.Add('                    Err(e) => cb(Err(e)),');
  Lines.Add('                }');
  Lines.Add('            }));');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    pub fn submit_uid_sequenced<F>(');
  Lines.Add('        uid: LfP2PUid,');
  Lines.Add('        param: DataHnd,');
  Lines.Add('        cb: F,');
  Lines.Add('    ) -> Result<(), Error>');
  Lines.Add('    where');
  Lines.Add('        F: FnOnce(Result<DataHandle, Error>) + Send + ' + #39 + 'static,');
  Lines.Add('    {');
  Lines.Add('        let lib = get_library().map_err(Error::from)?;');
  Lines.Add('        let holder = Box::new(AsyncHolder { cb: Some(Box::new(cb)) });');
  Lines.Add('        let data = Box::into_raw(holder) as *mut c_void;');
  Lines.Add('        let ret = unsafe {');
  Lines.Add('            (lib.lf_uid_async_sequenced_call)(');
  Lines.Add('                uid,');
  Lines.Add('                param,');
  Lines.Add('                data,');
  Lines.Add('                trampoline as LfAsyncCallOnResult,');
  Lines.Add('            )');
  Lines.Add('        };');
  Lines.Add('        if ret != 1 {');
  Lines.Add('            unsafe {');
  Lines.Add('                drop(Box::from_raw(data as *mut AsyncHolder));');
  Lines.Add('            }');
  Lines.Add('            return Err(Error::new(');
  Lines.Add('                ErrorCode::CallFailed,');
  Lines.Add('                "async call was not dispatched",');
  Lines.Add('            ));');
  Lines.Add('        }');
  Lines.Add('        Ok(())');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    pub fn submit_p2pname_sequenced<F>(');
  Lines.Add('        p2p_name: &' + #39 + 'static str,');
  Lines.Add('        param: DataHnd,');
  Lines.Add('        cb: F,');
  Lines.Add('    ) -> Result<(), Error>');
  Lines.Add('    where');
  Lines.Add('        F: FnOnce(Result<DataHandle, Error>) + Send + ' + #39 + 'static,');
  Lines.Add('    {');
  Lines.Add('        let lib = get_library().map_err(Error::from)?;');
  Lines.Add('        let c_name = CString::new(p2p_name).map_err(|_| {');
  Lines.Add('            Error::new(');
  Lines.Add('                ErrorCode::InvalidArgument,');
  Lines.Add('                "p2p_name contains interior NUL",');
  Lines.Add('            )');
  Lines.Add('        })?;');
  Lines.Add('        let holder = Box::new(AsyncHolder { cb: Some(Box::new(cb)) });');
  Lines.Add('        let data = Box::into_raw(holder) as *mut c_void;');
  Lines.Add('        let ret = unsafe {');
  Lines.Add('            (lib.lf_p2pname_async_sequenced_call)(');
  Lines.Add('                c_name.as_ptr(),');
  Lines.Add('                param,');
  Lines.Add('                data,');
  Lines.Add('                trampoline as LfAsyncCallOnResult,');
  Lines.Add('            )');
  Lines.Add('        };');
  Lines.Add('        if ret != 1 {');
  Lines.Add('            unsafe {');
  Lines.Add('                drop(Box::from_raw(data as *mut AsyncHolder));');
  Lines.Add('            }');
  Lines.Add('            return Err(Error::new(');
  Lines.Add('                ErrorCode::CallFailed,');
  Lines.Add('                "async call was not dispatched",');
  Lines.Add('            ));');
  Lines.Add('        }');
  Lines.Add('        Ok(())');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallRsCode(Model: TPascal_Func_Model): TPascalStringList;
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
    Log('GenerateABICallRsCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallRsCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';

  Log(PFormat('Generating Rust ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#![allow(non_snake_case)]');
    Lines.Add('#![allow(dead_code)]');
    Lines.Add('#![allow(unused_mut)]');
    Lines.Add('');
    Lines.Add('use std::sync::RwLock;');
    Lines.Add('use std::sync::atomic::{AtomicU64, Ordering};');
    Lines.Add('');
    Lines.Add('use lingofuse::async_call;');
    Lines.Add('use lingofuse::data_handle::DataHandle;');
    Lines.Add('use lingofuse::error::{Error, ErrorCode};');
    Lines.Add('use lingofuse::framework;');
    Lines.Add('use lingofuse::sys::LfP2PUid;');
    Lines.Add('use lingofuse::uid::Uid;');
    Lines.Add('');
    Lines.Add('pub static ABI_TARGET_APP: RwLock<&' + #39 + 'static str> = RwLock::new(' + CStrLit(TargetApp) + ');');
    Lines.Add('pub static ABI_TIMEOUT: AtomicU64 = AtomicU64::new(5000);');
    Lines.Add('');
    Lines.Add('const STATUS_OK: u8 = 0x00;');
    Lines.Add('');
    Lines.Add('fn _expect_response(r: Option<DataHandle>, api_name: &' + #39 + 'static str) -> Result<DataHandle, Error> {');
    Lines.Add('    r.ok_or_else(|| Error::new(');
    Lines.Add('        ErrorCode::CallFailed,');
    Lines.Add('        format!("ABI call {} returned an empty response (timeout or target not found)", api_name),');
    Lines.Add('    ))');
    Lines.Add('}');
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

    EmitAsyncSequencedModule(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines for Rust ABI call', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'rust',
    'xxx_abi_call.rs',
    gkCall,
    'Rust ABI call implementation',
    @GenerateABICallRsCode);

end.
