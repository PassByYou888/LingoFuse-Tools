unit go_abi_call_generator_tool;

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

function GenerateABICallGoCode(Model: TPascal_Func_Model): TPascalStringList;

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

function MakeExportedGoName(const Name: TP_String): TP_String;
begin
  Result := Name;
  if Result.Len = 0 then Exit;
  if (Result[1] >= 'a') and (Result[1] <= 'z') then
    Result[1] := TP_Char(Ord(Result[1]) - 32);
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

  if Result.Same('param') or Result.Same('res') or Result.Same('err') or
     Result.Same('target') or Result.Same('out') or Result.Same('r') or
     Result.Same('uid') or Result.Same('p2pName') or Result.Same('onResult') or
     Result.Same('timeoutMs') or Result.Same('apiName') then
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

function BuildGoParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeGoIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Go_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName + ' ' + PTyp;
  end;
end;

function BuildParamDeclWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Inner: TP_String;
begin
  Inner := BuildGoParamDecl(Params);
  if (Prefix = '') and (Inner = '') then
    Result := ''
  else if Prefix = '' then
    Result := Inner
  else if Inner = '' then
    Result := Prefix
  else
    Result := Prefix + ', ' + Inner;
end;

procedure EmitWriteParamStatements(
  Lines: TPascalStringList;
  const F: TFunctionStructure;
  const Indent: TP_String);
var
  i: integer;
  PName, WriteFunc: TP_String;
begin
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    WriteFunc := ABI_Type_To_Go_Write_Func(F.Params[i].PascalType);
    Lines.Add(Indent + 'if err := param.' + WriteFunc + '(' + PName + '); err != nil {');
    Lines.Add(Indent + #9 + 'return ' + #39 + 'returnzero' + #39 + ', err');
    Lines.Add(Indent + '}');
  end;
end;

procedure EmitWriteParamStatementsNoRet(
  Lines: TPascalStringList;
  const F: TFunctionStructure;
  const Indent: TP_String);
var
  i: integer;
  PName, WriteFunc: TP_String;
begin
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    WriteFunc := ABI_Type_To_Go_Write_Func(F.Params[i].PascalType);
    Lines.Add(Indent + 'if err := param.' + WriteFunc + '(' + PName + '); err != nil {');
    Lines.Add(Indent + #9 + 'return err');
    Lines.Add(Indent + '}');
  end;
end;

procedure EmitSyncCall(
  Lines: TPascalStringList;
  const F: TFunctionStructure;
  const ApiName, FuncName, ExtraParamPrefix, TargetExpr, MethodName: TP_String);
var
  RetType, ParamDecl, ReturnZero, ReadFunc: TP_String;
  i: integer;
  PName, WriteFunc: TP_String;
begin
  RetType := ABI_Type_To_Go_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix(ExtraParamPrefix, F.Params);
  ReturnZero := ABI_Type_To_Go_Default(F.ReturnType);
  ReadFunc := ABI_Type_To_Go_Read_Func(F.ReturnType);

  Lines.Add('func ' + FuncName + '(' + ParamDecl + ') (' + RetType + ', error) {');
  Lines.Add(#9 + 'param, err := lingofuse.NewDataHandle(' + GoStrLit(ApiName) + ')');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'return ' + ReturnZero + ', err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'defer param.Close()');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    WriteFunc := ABI_Type_To_Go_Write_Func(F.Params[i].PascalType);
    Lines.Add(#9 + 'if err := param.' + WriteFunc + '(' + PName + '); err != nil {');
    Lines.Add(#9 + #9 + 'return ' + ReturnZero + ', err');
    Lines.Add(#9 + '}');
  end;

  Lines.Add(#9 + 'if err := param.SetPosition(0); err != nil {');
  Lines.Add(#9 + #9 + 'return ' + ReturnZero + ', err');
  Lines.Add(#9 + '}');

  Lines.Add(#9 + 'res, err := ' + TargetExpr + '.' + MethodName + '(' + GoStrLit(ApiName) + ', param, uint64(ABI_Timeout / time.Millisecond))');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'return ' + ReturnZero + ', err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'defer res.Close()');

  Lines.Add(#9 + 'if err := checkResponseStatus(res, ' + GoStrLit(ApiName) + '); err != nil {');
  Lines.Add(#9 + #9 + 'return ' + ReturnZero + ', err');
  Lines.Add(#9 + '}');

  Lines.Add(#9 + 'out, err := res.' + ReadFunc + '()');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'return ' + ReturnZero + ', err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'return out, nil');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAsyncCall(
  Lines: TPascalStringList;
  const F: TFunctionStructure;
  const ApiName, FuncName, ExtraParamPrefix, TargetExpr, MethodName: TP_String);
var
  RetType, ParamDecl, ReturnZero, ReadFunc: TP_String;
  i: integer;
  PName, WriteFunc: TP_String;
begin
  RetType := ABI_Type_To_Go_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix(ExtraParamPrefix, F.Params);
  ReturnZero := ABI_Type_To_Go_Default(F.ReturnType);
  ReadFunc := ABI_Type_To_Go_Read_Func(F.ReturnType);

  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', onResult func(' + RetType + ', error)'
  else
    ParamDecl := 'onResult func(' + RetType + ', error)';

  Lines.Add('func ' + FuncName + '(' + ParamDecl + ') error {');
  Lines.Add(#9 + 'param, err := lingofuse.NewDataHandle(' + GoStrLit(ApiName) + ')');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'return err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'defer param.Close()');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    WriteFunc := ABI_Type_To_Go_Write_Func(F.Params[i].PascalType);
    Lines.Add(#9 + 'if err := param.' + WriteFunc + '(' + PName + '); err != nil {');
    Lines.Add(#9 + #9 + 'return err');
    Lines.Add(#9 + '}');
  end;

  Lines.Add(#9 + 'if err := param.SetPosition(0); err != nil {');
  Lines.Add(#9 + #9 + 'return err');
  Lines.Add(#9 + '}');

  Lines.Add(#9 + 'return ' + TargetExpr + '.' + MethodName + '(' + GoStrLit(ApiName) + ', param, func(r lingofuse.AsyncResult) {');
  Lines.Add(#9 + #9 + 'if r.Err != nil {');
  Lines.Add(#9 + #9 + #9 + 'onResult(' + ReturnZero + ', r.Err)');
  Lines.Add(#9 + #9 + #9 + 'return');
  Lines.Add(#9 + #9 + '}');
  Lines.Add(#9 + #9 + 'if err := checkResponseStatus(r.Value, ' + GoStrLit(ApiName) + '); err != nil {');
  Lines.Add(#9 + #9 + #9 + 'onResult(' + ReturnZero + ', err)');
  Lines.Add(#9 + #9 + #9 + 'return');
  Lines.Add(#9 + #9 + '}');
  Lines.Add(#9 + #9 + 'out, err := r.Value.' + ReadFunc + '()');
  Lines.Add(#9 + #9 + 'if err != nil {');
  Lines.Add(#9 + #9 + #9 + 'onResult(' + ReturnZero + ', err)');
  Lines.Add(#9 + #9 + #9 + 'return');
  Lines.Add(#9 + #9 + '}');
  Lines.Add(#9 + #9 + 'onResult(out, nil)');
  Lines.Add(#9 + '})');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNotify(
  Lines: TPascalStringList;
  const F: TFunctionStructure;
  const ApiName, FuncName, ExtraParamPrefix, TargetExpr, MethodName: TP_String);
var
  ParamDecl: TP_String;
  i: integer;
  PName, WriteFunc: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix(ExtraParamPrefix, F.Params);

  Lines.Add('func ' + FuncName + '(' + ParamDecl + ') error {');
  Lines.Add(#9 + 'param, err := lingofuse.NewDataHandle(' + GoStrLit(ApiName) + ')');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'return err');
  Lines.Add(#9 + '}');
  Lines.Add(#9 + 'defer param.Close()');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeGoIdent(F.Params[i].Name, i);
    WriteFunc := ABI_Type_To_Go_Write_Func(F.Params[i].PascalType);
    Lines.Add(#9 + 'if err := param.' + WriteFunc + '(' + PName + '); err != nil {');
    Lines.Add(#9 + #9 + 'return err');
    Lines.Add(#9 + '}');
  end;

  Lines.Add(#9 + 'if err := param.SetPosition(0); err != nil {');
  Lines.Add(#9 + #9 + 'return err');
  Lines.Add(#9 + '}');

  Lines.Add(#9 + 'return ' + TargetExpr + '.' + MethodName + '(' + GoStrLit(ApiName) + ', param)');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallGoCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetApp: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, ExportedName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('package ' + NormalizedUnit.Text + '_abi');
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add(#9 + '"errors"');
    Lines.Add(#9 + '"time"');
    Lines.Add('');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/lingofuse"');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/sys"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('var ABI_TargetApp = ' + GoStrLit(TargetApp));
    Lines.Add('');
    Lines.Add('var ABI_Timeout = 5000 * time.Millisecond');
    Lines.Add('');
    Lines.Add('const statusOK uint8 = 0x00');
    Lines.Add('');
    Lines.Add('const statusError uint8 = 0xFF');
    Lines.Add('');
    Lines.Add('func newRemoteError(msg string) error {');
    Lines.Add(#9 + 'return errors.New(msg)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func checkResponseStatus(res *lingofuse.DataHandle, apiName string) error {');
    Lines.Add(#9 + 'sz, err := res.Size()');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'return err');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'if sz == 0 {');
    Lines.Add(#9 + #9 + 'return newRemoteError("ABI call [" + apiName + "] returned nil (timeout or target not found)")');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'if err := res.SetPosition(0); err != nil {');
    Lines.Add(#9 + #9 + 'return err');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'status, err := res.ReadUint8()');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'return newRemoteError("ABI call [" + apiName + "]: response truncated (status)")');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'if status != statusOK {');
    Lines.Add(#9 + #9 + 'msg, _ := res.ReadString()');
    Lines.Add(#9 + #9 + 'return newRemoteError("ABI call [" + apiName + "] failed: " + msg)');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'return nil');
    Lines.Add('}');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if not F.IsFunction then Continue;

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      ExportedName := MakeExportedGoName(ApiName);

      EmitSyncCall(Lines, F, ApiName, ExportedName,
        '', 'lingofuse.App(ABI_TargetApp)', 'Call');
      EmitAsyncCall(Lines, F, ApiName, ExportedName + '_Async',
        '', 'lingofuse.App(ABI_TargetApp)', 'CallAsync');
      EmitAsyncCall(Lines, F, ApiName, ExportedName + '_AsyncSequenced',
        '', 'lingofuse.App(ABI_TargetApp)', 'SequencedCallAsync');

      EmitSyncCall(Lines, F, ApiName, ExportedName + '_UID_Call',
        'uid sys.TP2P_UID', 'lingofuse.UID(uid)', 'Call');
      EmitAsyncCall(Lines, F, ApiName, ExportedName + '_UID_Async',
        'uid sys.TP2P_UID', 'lingofuse.UID(uid)', 'CallAsync');
      EmitAsyncCall(Lines, F, ApiName, ExportedName + '_UID_AsyncSequenced',
        'uid sys.TP2P_UID', 'lingofuse.UID(uid)', 'SequencedCallAsync');

      EmitSyncCall(Lines, F, ApiName, ExportedName + '_P2PName_Call',
        'p2pName string', 'lingofuse.P2P(p2pName)', 'Call');
      EmitAsyncCall(Lines, F, ApiName, ExportedName + '_P2PName_Async',
        'p2pName string', 'lingofuse.P2P(p2pName)', 'CallAsync');
      EmitAsyncCall(Lines, F, ApiName, ExportedName + '_P2PName_AsyncSequenced',
        'p2pName string', 'lingofuse.P2P(p2pName)', 'SequencedCallAsync');
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then Continue;

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      ExportedName := MakeExportedGoName(ApiName);

      EmitNotify(Lines, F, ApiName, ExportedName,
        '', 'lingofuse.App(ABI_TargetApp)', 'Notify');
      EmitNotify(Lines, F, ApiName, ExportedName + '_SequencedNotify',
        '', 'lingofuse.App(ABI_TargetApp)', 'SequencedNotify');

      EmitNotify(Lines, F, ApiName, ExportedName + '_UID_Notify',
        'uid sys.TP2P_UID', 'lingofuse.UID(uid)', 'Notify');
      EmitNotify(Lines, F, ApiName, ExportedName + '_UID_SequencedNotify',
        'uid sys.TP2P_UID', 'lingofuse.UID(uid)', 'SequencedNotify');

      EmitNotify(Lines, F, ApiName, ExportedName + '_P2PName_Notify',
        'p2pName string', 'lingofuse.P2P(p2pName)', 'Notify');
      EmitNotify(Lines, F, ApiName, ExportedName + '_P2PName_SequencedNotify',
        'p2pName string', 'lingofuse.P2P(p2pName)', 'SequencedNotify');
    end;

    Result := Lines;
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'go',
    'xxx_abi_call.go',
    gkCall,
    'Go ABI call implementation',
    @GenerateABICallGoCode);

end.
