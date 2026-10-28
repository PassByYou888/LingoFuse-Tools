unit rust_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceRsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[rust_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[rust_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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
    Result := '&str'
  else
    Result := ABI_Type_To_Rust_Decl(T);
end;

function ABI_Type_To_Rust_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'String::new()'
  else if T.Same('double') or T.Same('extended') or T.Same('real') or T.Same('single') then
    Result := '0.0'
  else
    Result := '0';
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

  if Result.Same('uid') or Result.Same('p2p_name') then
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
        begin
        end
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

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Result := 'uid: Uid, p2p_name: &str';
  Tmp := BuildRustParamDecl(Params);
  if Tmp <> '' then
    Result := Result + ', ' + Tmp;
end;

function BuildInternalCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := 'uid, &p2p_name';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRustIdent(Params[i].Name, i);
    Result := Result + ', ';
    if IsStringABIType(Params[i].PascalType) then
      Result := Result + '&' + PName
    else
      Result := Result + PName;
  end;
end;

procedure EmitInternalCallStub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  ParamDecl, RetType, RetDefault, PName: TP_String;
begin
  EmitCommentLines(Lines, F.Comment);
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  RetType := ABI_Type_To_Rust_Decl(F.ReturnType);

  if F.IsFunction then
    Lines.Add('pub fn internal_call_' + ApiName + '(' + ParamDecl + ') -> ' + RetType + ' {')
  else
    Lines.Add('pub fn internal_call_' + ApiName + '(' + ParamDecl + ') {');

  Lines.Add('    let _ = (uid, p2p_name);');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeRustIdent(F.Params[i].Name, i);
    Lines.Add('    let _ = ' + PName + ';');
  end;

  if F.IsFunction then
  begin
    RetDefault := ABI_Type_To_Rust_Default(F.ReturnType);
    Lines.Add('    ' + RetDefault);
  end;
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackReadParam(Lines: TPascalStringList; const PName, PascalType: TP_String; HasOutput: boolean);
var
  RustType: TP_String;
begin
  if IsStringABIType(PascalType) then
  begin
    Lines.Add('    let ' + PName + ': String = match input.read_string() {');
    Lines.Add('        Ok(v) => v,');
    if HasOutput then
    begin
      Lines.Add('        Err(_) => {');
      Lines.Add('            let mut buf: Vec<u8> = vec![STATUS_ERROR];');
      Lines.Add('            buf.extend_from_slice(b"truncated input: ' + PName + '\x00");');
      Lines.Add('            let _ = output.write_bytes(&buf);');
      Lines.Add('            return;');
      Lines.Add('        }');
    end
    else
      Lines.Add('        Err(_) => return,');
    Lines.Add('    };');
  end
  else
  begin
    RustType := ABI_Type_To_Rust_Decl(PascalType);
    Lines.Add('    let ' + PName + ': ' + RustType + ' = match input.read() {');
    Lines.Add('        Ok(v) => v,');
    if HasOutput then
    begin
      Lines.Add('        Err(_) => {');
      Lines.Add('            let mut buf: Vec<u8> = vec![STATUS_ERROR];');
      Lines.Add('            buf.extend_from_slice(b"truncated input: ' + PName + '\x00");');
      Lines.Add('            let _ = output.write_bytes(&buf);');
      Lines.Add('            return;');
      Lines.Add('        }');
    end
    else
      Lines.Add('        Err(_) => return,');
    Lines.Add('    };');
  end;
end;

procedure EmitCallbackImplementation(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ArgList: TP_String;
  i: integer;
  PName, PascalType: TP_String;
begin
  if F.IsFunction then
    Lines.Add('fn callback_' + ApiName + '(input: &mut DataHandle, output: &mut DataHandle) {')
  else
    Lines.Add('fn callback_' + ApiName + '(input: &mut DataHandle) {');

  Lines.Add('    let uid = input.p2p_uid().unwrap_or_default();');
  Lines.Add('    let p2p_name = input.p2p_name().unwrap_or_default();');
  Lines.Add('');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeRustIdent(F.Params[i].Name, i);
    PascalType := F.Params[i].PascalType;
    EmitCallbackReadParam(Lines, PName, PascalType, F.IsFunction);
  end;

  Lines.Add('');
  ArgList := BuildInternalCallArgList(F.Params);

  if F.IsFunction then
  begin
    RetType := ABI_Type_To_Rust_Decl(F.ReturnType);

    Lines.Add('    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {');
    Lines.Add('        internal_call_' + ApiName + '(' + ArgList + ')');
    Lines.Add('    }));');
    Lines.Add('');
    Lines.Add('    match result {');

    if IsStringABIType(F.ReturnType) then
    begin
      Lines.Add('        Ok(v) => {');
      Lines.Add('            let mut buf: Vec<u8> = Vec::with_capacity(1 + v.len() + 1);');
      Lines.Add('            buf.push(STATUS_OK);');
      Lines.Add('            buf.extend_from_slice(v.as_bytes());');
      Lines.Add('            buf.push(0);');
      Lines.Add('            let _ = output.write_bytes(&buf);');
      Lines.Add('        }');
    end
    else
    begin
      Lines.Add('        Ok(v) => {');
      Lines.Add('            let mut buf: Vec<u8> = Vec::with_capacity(1 + std::mem::size_of::<' + RetType + '>());');
      Lines.Add('            buf.push(STATUS_OK);');
      Lines.Add('            buf.extend_from_slice(&v.to_le_bytes());');
      Lines.Add('            let _ = output.write_bytes(&buf);');
      Lines.Add('        }');
    end;

    Lines.Add('        Err(_) => {');
    Lines.Add('            let mut buf: Vec<u8> = vec![STATUS_ERROR];');
    Lines.Add('            buf.extend_from_slice(b"internal_call_' + ApiName + ' panicked\x00");');
    Lines.Add('            let _ = output.write_bytes(&buf);');
    Lines.Add('        }');
    Lines.Add('    }');
  end
  else
  begin
    Lines.Add('    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {');
    Lines.Add('        internal_call_' + ApiName + '(' + ArgList + ');');
    Lines.Add('    }));');
  end;

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRegisterAll(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Description: TP_String;
begin
  Lines.Add('pub fn register_all_abi_apis(app: &AppHandle) -> Result<(), Error> {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'ABI api for ' + F.Name;

    if F.IsFunction then
      Lines.Add('    app.register_call(' + CStrLit(ApiName) + ', ' + CStrLit(Description) +
        ', callback_' + ApiName + ')?;')
    else
      Lines.Add('    app.register_notify(' + CStrLit(ApiName) + ', ' + CStrLit(Description) +
        ', callback_' + ApiName + ')?;');
  end;
  Lines.Add('    Ok(())');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn register_all_p2p_abi_apis() -> Result<(), Error> {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'ABI api for ' + F.Name;

    if F.IsFunction then
      Lines.Add('    p2p::register_p2p_call(' + CStrLit(ApiName) + ', ' + CStrLit(Description) +
        ', callback_' + ApiName + ')?;')
    else
      Lines.Add('    p2p::register_p2p_notify(' + CStrLit(ApiName) + ', ' + CStrLit(Description) +
        ', callback_' + ApiName + ')?;');
  end;
  Lines.Add('    Ok(())');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn create_and_register_abi_app() -> Result<AppHandle, Error> {');
  Lines.Add('    let app = AppHandle::new(DEFAULT_APP_NAME, DEFAULT_APP_DESC)?;');
  Lines.Add('    register_all_abi_apis(&app)?;');
  Lines.Add('    Ok(app)');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceRsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceRsCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceRsCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Rust ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#![allow(non_snake_case)]');
    Lines.Add('#![allow(dead_code)]');
    Lines.Add('');
    Lines.Add('use lingofuse::app_handle::AppHandle;');
    Lines.Add('use lingofuse::data_handle::DataHandle;');
    Lines.Add('use lingofuse::error::Error;');
    Lines.Add('use lingofuse::p2p;');
    Lines.Add('use lingofuse::uid::Uid;');
    Lines.Add('');
    Lines.Add('pub const DEFAULT_APP_NAME: &str = ' + CStrLit(AppName) + ';');
    Lines.Add('pub const DEFAULT_APP_DESC: &str = ' + CStrLit(AppDesc) + ';');
    Lines.Add('');
    Lines.Add('pub const STATUS_OK: u8 = 0x00;');
    Lines.Add('pub const STATUS_ERROR: u8 = 0xFF;');
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

      EmitInternalCallStub(Lines, ApiName, F);
    end;

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

      EmitCallbackImplementation(Lines, ApiName, F);
    end;

    EmitRegisterAll(Lines, SupportedFuncs, UsedApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines for Rust ABI service', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'rust',
    'xxx_abi_service.rs',
    gkService,
    'Rust ABI service implementation',
    @GenerateABIServiceRsCode);

end.
