unit go_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib,
  Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceGoCode(Model: TPascal_Func_Model): TPascalStringList;

implementation

type
  TArryFunctionStructure = array of TFunctionStructure;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Go_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'int32'
  else if T.Same('int64') then Result := 'int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'uint32'
  else if T.Same('word') then Result := 'uint16'
  else if T.Same('smallint') then Result := 'int16'
  else if T.Same('shortint') or T.Same('int8') then Result := 'int8'
  else if T.Same('byte') then Result := 'uint8'
  else if T.Same('uint64') then Result := 'uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'float64'
  else if T.Same('single') then Result := 'float32'
  else if IsStringABIType(T) then Result := 'string'
  else Result := '';
end;

function ABI_Type_To_Go_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'ReadInt32'
  else if T.Same('int64') then Result := 'ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'ReadUint32'
  else if T.Same('word') then Result := 'ReadUint16'
  else if T.Same('smallint') then Result := 'ReadInt16'
  else if T.Same('shortint') or T.Same('int8') then Result := 'ReadInt8'
  else if T.Same('byte') then Result := 'ReadUint8'
  else if T.Same('uint64') then Result := 'ReadUint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'ReadDouble'
  else if T.Same('single') then Result := 'ReadSingle'
  else if IsStringABIType(T) then Result := 'ReadString'
  else Result := '';
end;

function ABI_Type_To_Go_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'WriteInt32'
  else if T.Same('int64') then Result := 'WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'WriteUint32'
  else if T.Same('word') then Result := 'WriteUint16'
  else if T.Same('smallint') then Result := 'WriteInt16'
  else if T.Same('shortint') or T.Same('int8') then Result := 'WriteInt8'
  else if T.Same('byte') then Result := 'WriteUint8'
  else if T.Same('uint64') then Result := 'WriteUint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'WriteDouble'
  else if T.Same('single') then Result := 'WriteSingle'
  else if IsStringABIType(T) then Result := 'WriteString'
  else Result := '';
end;

function ABI_Type_To_Go_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then Result := '""'
  else Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Go_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsGoKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('break') or S.Same('case') or S.Same('chan') or S.Same('const') or
    S.Same('continue') or S.Same('default') or S.Same('defer') or S.Same('else') or
    S.Same('fallthrough') or S.Same('for') or S.Same('func') or S.Same('go') or
    S.Same('goto') or S.Same('if') or S.Same('import') or S.Same('interface') or
    S.Same('map') or S.Same('package') or S.Same('range') or S.Same('return') or
    S.Same('select') or S.Same('struct') or S.Same('switch') or S.Same('type') or
    S.Same('var');
end;

function MakeSafeGoIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsGoKeyword(Result) then
    Result := Result + '_';

  if Result.Same('err') or Result.Same('ret') or Result.Same('callErr') or
     Result.Same('uid') or Result.Same('p2pName') or Result.Same('r') or
     Result.Same('inp') or Result.Same('out') then
    Result := Result + '_p';
end;

function GoStrLit(const S: TP_String): TP_String;
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
        if Line[1] <> '@' then
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
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
      Supported := False;

    if Supported and (f.Name.Len = 0) then
      Supported := False;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function BuildUniqueApiNames(const Funcs: TArryFunctionStructure): TPascalStringList;
var
  i, j: integer;
  ApiName: TP_String;
begin
  Result := TPascalStringList.Create;
  for i := 0 to High(Funcs) do
  begin
    ApiName := MakeApiName(Funcs[i].Name);
    if Result.IndexOf(ApiName) >= 0 then
    begin
      j := 1;
      while Result.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      ApiName := ApiName + '_' + umlIntToStr(j).Text;
    end;
    Result.Add(ApiName);
  end;
end;

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := 'uid sys.TP2P_UID, p2pName string';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeGoIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Go_Decl(Params[i].PascalType);
    Result := Result + ', ' + PName + ' ' + PTyp;
  end;
end;

function BuildInternalCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := 'uid, p2pName';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeGoIdent(Params[i].Name, i);
    Result := Result + ', ' + PName;
  end;
end;

procedure EmitInternalCallStub(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  ParamDecl, RetType, RetDefault, PName: TP_String;
begin
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  RetType := ABI_Type_To_Go_Decl(F.ReturnType);
  RetDefault := ABI_Type_To_Go_Default(F.ReturnType);

  if F.IsFunction then
    Lines.Add('func internalCall' + ApiName + '(' + ParamDecl + ') (' + RetType + ', error) {')
  else
    Lines.Add('func internalCall' + ApiName + '(' + ParamDecl + ') error {');

  Lines.Add(#9 + '_, _ = uid, p2pName');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    Lines.Add(#9 + '_ = ' + PName);
  end;

  if F.IsFunction then
    Lines.Add(#9 + 'return ' + RetDefault + ', nil')
  else
    Lines.Add(#9 + 'return nil');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackImplementation(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFunc, ArgList, RetType, WriteFunc: TP_String;
begin
  if F.IsFunction then
    Lines.Add('func callback' + ApiName + '(inp, out *lingofuse.DataHandle) {')
  else
    Lines.Add('func callback' + ApiName + '(inp *lingofuse.DataHandle) {');

  Lines.Add(#9 + 'uid, _ := inp.GetP2PUID()');
  Lines.Add(#9 + 'p2pName, _ := inp.GetP2PName()');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    ReadFunc := ABI_Type_To_Go_Read_Func(F.Params[i].PascalType);
    Lines.Add(#9 + PName + ', err := inp.' + ReadFunc + '()');
    Lines.Add(#9 + 'if err != nil {');
    if F.IsFunction then
      Lines.Add(#9 + #9 + 'writeCallbackError(out, ' + GoStrLit('input truncated: ' + PName) + ')');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
  end;

  Lines.Add('');

  ArgList := BuildInternalCallArgList(F.Params);

  if F.IsFunction then
  begin
    RetType := ABI_Type_To_Go_Decl(F.ReturnType);
    WriteFunc := ABI_Type_To_Go_Write_Func(F.ReturnType);

    Lines.Add(#9 + 'var ret ' + RetType);
    Lines.Add(#9 + 'var callErr error');
    Lines.Add(#9 + 'func() {');
    Lines.Add(#9 + #9 + 'defer func() {');
    Lines.Add(#9 + #9 + #9 + 'if r := recover(); r != nil {');
    Lines.Add(#9 + #9 + #9 + #9 + 'callErr = panicToError(' + GoStrLit(ApiName) + ', r)');
    Lines.Add(#9 + #9 + #9 + '}');
    Lines.Add(#9 + #9 + '}()');
    Lines.Add(#9 + #9 + 'ret, callErr = internalCall' + ApiName + '(' + ArgList + ')');
    Lines.Add(#9 + '}()');
    Lines.Add(#9 + 'if callErr != nil {');
    Lines.Add(#9 + #9 + 'writeCallbackError(out, callErr.Error())');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'writeCallbackOK(out)');
    Lines.Add(#9 + '_ = out.' + WriteFunc + '(ret)');
  end
  else
  begin
    Lines.Add(#9 + 'func() {');
    Lines.Add(#9 + #9 + 'defer func() {');
    Lines.Add(#9 + #9 + #9 + '_ = recover()');
    Lines.Add(#9 + #9 + '}()');
    Lines.Add(#9 + #9 + '_ = internalCall' + ApiName + '(' + ArgList + ')');
    Lines.Add(#9 + '}()');
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
  ApiName, Description, RegFunc: TP_String;
begin
  Lines.Add('func RegisterAllABIAPIs(app *lingofuse.AppHandle) error {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'ABI api for ' + F.Name;

    if F.IsFunction then
      RegFunc := 'RegisterCall'
    else
      RegFunc := 'RegisterNotify';

    Lines.Add(#9 + 'if err := app.' + RegFunc + '(' + GoStrLit(ApiName) + ', ' + GoStrLit(Description) + ', callback' + ApiName + '); err != nil {');
    Lines.Add(#9 + #9 + 'return err');
    Lines.Add(#9 + '}');
  end;
  Lines.Add(#9 + 'return nil');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('func RegisterAllP2PABIAPIs() error {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'ABI api for ' + F.Name;

    if F.IsFunction then
      RegFunc := 'RegisterP2PCall'
    else
      RegFunc := 'RegisterP2PNotify';

    Lines.Add(#9 + 'if err := lingofuse.' + RegFunc + '(' + GoStrLit(ApiName) + ', ' + GoStrLit(Description) + ', callback' + ApiName + '); err != nil {');
    Lines.Add(#9 + #9 + 'return err');
    Lines.Add(#9 + '}');
  end;
  Lines.Add(#9 + 'return nil');
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('func CreateAndRegisterABIApp() (*lingofuse.AppHandle, error) {');
  Lines.Add(#9 + 'app, err := lingofuse.NewAppHandle(DefaultAppName, DefaultAppDesc)');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'return nil, err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'if err := RegisterAllABIAPIs(app); err != nil {');
  Lines.Add(#9 + #9 + 'app.Close()');
  Lines.Add(#9 + #9 + 'return nil, err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'return app, nil');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceGoCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := BuildUniqueApiNames(SupportedFuncs);

  Lines := TPascalStringList.Create;
  try
    Lines.Add('package ' + NormalizedUnit.Text + '_abi');
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add(#9 + '"fmt"');
    Lines.Add('');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/lingofuse"');
    if Length(SupportedFuncs) > 0 then
      Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/sys"');
    Lines.Add(')');
    Lines.Add('');

    Lines.Add('const DefaultAppName = ' + GoStrLit(AppName));
    Lines.Add('');
    Lines.Add('const DefaultAppDesc = ' + GoStrLit(AppDesc));
    Lines.Add('');

    Lines.Add('func writeCallbackOK(out *lingofuse.DataHandle) {');
    Lines.Add(#9 + '_ = out.WriteUint8(0x00)');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('func writeCallbackError(out *lingofuse.DataHandle, msg string) {');
    Lines.Add(#9 + '_ = out.WriteUint8(0xFF)');
    Lines.Add(#9 + '_ = out.WriteString(msg)');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('func panicToError(apiName string, r any) error {');
    Lines.Add(#9 + 'return fmt.Errorf("internalCall for API %q panicked: %v", apiName, r)');
    Lines.Add('}');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      EmitInternalCallStub(Lines, ApiNames[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
      EmitCallbackImplementation(Lines, ApiNames[i], SupportedFuncs[i]);

    EmitRegisterAll(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'go',
    'xxx_abi_service.go',
    gkService,
    'Go ABI service implementation',
    @GenerateABIServiceGoCode);

end.
