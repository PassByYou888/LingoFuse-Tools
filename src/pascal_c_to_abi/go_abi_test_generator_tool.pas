unit go_abi_test_generator_tool;

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

function GenerateABIServiceTestGoCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestGoCode(Model: TPascal_Func_Model): TPascalStringList;

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

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Go_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function MakeExportedGoName(const Name: TP_String): TP_String;
begin
  Result := Name;
  if Result.Len = 0 then Exit;
  if (Result[1] >= 'a') and (Result[1] <= 'z') then
    Result[1] := TP_Char(Ord(Result[1]) - 32);
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

function PlaceholderForType(const PascalType: TP_String): TP_String;
begin
  if IsStringABIType(PascalType) then
    Result := '"test"'
  else if PascalType.Same('double') or PascalType.Same('extended') or
    PascalType.Same('real') or PascalType.Same('single') then
    Result := '3.14'
  else
    Result := '42';
end;

function BuildPlaceholderArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PlaceholderForType(Params[i].PascalType);
  end;
end;

procedure EmitFunctionTest(
  Lines: TPascalStringList;
  const ExportedName: TP_String;
  const F: TFunctionStructure);
var
  RetType, Args: TP_String;
begin
  RetType := ABI_Type_To_Go_Decl(F.ReturnType);
  Args := BuildPlaceholderArgs(F.Params);

  Lines.Add('func test' + ExportedName + '() {');

  if Args <> '' then
    Lines.Add(#9 + 'v, err := abi.' + ExportedName + '(' + Args + ')')
  else
    Lines.Add(#9 + 'v, err := abi.' + ExportedName + '()');
  Lines.Add(#9 + 'if err != nil {');
  Lines.Add(#9 + #9 + 'reportFail("' + ExportedName + '(app)", err.Error())');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportPass(fmt.Sprintf("' + ExportedName + '(app) = %v", v))');
  Lines.Add(#9 + '}');
  Lines.Add('');

  Lines.Add(#9 + 'asyncScalar[' + RetType + ']("' + ExportedName + '(app_async)", func(cb func(' + RetType + ', error)) error {');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_Async(' + Args + ', cb)')
  else
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_Async(cb)');
  Lines.Add(#9 + '})');
  Lines.Add('');

  Lines.Add(#9 + 'asyncScalar[' + RetType + ']("' + ExportedName + '(app_asyncseq)", func(cb func(' + RetType + ', error)) error {');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_AsyncSequenced(' + Args + ', cb)')
  else
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_AsyncSequenced(cb)');
  Lines.Add(#9 + '})');
  Lines.Add('');

  Lines.Add(#9 + 'uid, hasUID := getServiceUID()');
  Lines.Add(#9 + 'if hasUID {');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'v, err := abi.' + ExportedName + '_UID_Call(uid, ' + Args + ')')
  else
    Lines.Add(#9 + #9 + 'v, err := abi.' + ExportedName + '_UID_Call(uid)');
  Lines.Add(#9 + #9 + 'if err != nil {');
  Lines.Add(#9 + #9 + #9 + 'reportFail("' + ExportedName + '(uid)", err.Error())');
  Lines.Add(#9 + #9 + '} else {');
  Lines.Add(#9 + #9 + #9 + 'reportPass(fmt.Sprintf("' + ExportedName + '(uid) = %v", v))');
  Lines.Add(#9 + #9 + '}');
  Lines.Add('');

  Lines.Add(#9 + #9 + 'asyncScalar[' + RetType + ']("' + ExportedName + '(uid_async)", func(cb func(' + RetType + ', error)) error {');
  if Args <> '' then
    Lines.Add(#9 + #9 + #9 + 'return abi.' + ExportedName + '_UID_Async(uid, ' + Args + ', cb)')
  else
    Lines.Add(#9 + #9 + #9 + 'return abi.' + ExportedName + '_UID_Async(uid, cb)');
  Lines.Add(#9 + #9 + '})');
  Lines.Add('');

  Lines.Add(#9 + #9 + 'asyncScalar[' + RetType + ']("' + ExportedName + '(uid_asyncseq)", func(cb func(' + RetType + ', error)) error {');
  if Args <> '' then
    Lines.Add(#9 + #9 + #9 + 'return abi.' + ExportedName + '_UID_AsyncSequenced(uid, ' + Args + ', cb)')
  else
    Lines.Add(#9 + #9 + #9 + 'return abi.' + ExportedName + '_UID_AsyncSequenced(uid, cb)');
  Lines.Add(#9 + #9 + '})');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportSkip("' + ExportedName + '(uid)", "no service UID")');
  Lines.Add(#9 + #9 + 'reportSkip("' + ExportedName + '(uid_async)", "no service UID")');
  Lines.Add(#9 + #9 + 'reportSkip("' + ExportedName + '(uid_asyncseq)", "no service UID")');
  Lines.Add(#9 + '}');
  Lines.Add('');

  if Args <> '' then
    Lines.Add(#9 + 'v2, err2 := abi.' + ExportedName + '_P2PName_Call(callP2PName, ' + Args + ')')
  else
    Lines.Add(#9 + 'v2, err2 := abi.' + ExportedName + '_P2PName_Call(callP2PName)');
  Lines.Add(#9 + 'if err2 != nil {');
  Lines.Add(#9 + #9 + 'reportFail("' + ExportedName + '(p2pname)", err2.Error())');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportPass(fmt.Sprintf("' + ExportedName + '(p2pname) = %v", v2))');
  Lines.Add(#9 + '}');
  Lines.Add('');

  Lines.Add(#9 + 'asyncScalar[' + RetType + ']("' + ExportedName + '(p2pname_async)", func(cb func(' + RetType + ', error)) error {');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_P2PName_Async(callP2PName, ' + Args + ', cb)')
  else
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_P2PName_Async(callP2PName, cb)');
  Lines.Add(#9 + '})');
  Lines.Add('');

  Lines.Add(#9 + 'asyncScalar[' + RetType + ']("' + ExportedName + '(p2pname_asyncseq)", func(cb func(' + RetType + ', error)) error {');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_P2PName_AsyncSequenced(callP2PName, ' + Args + ', cb)')
  else
    Lines.Add(#9 + #9 + 'return abi.' + ExportedName + '_P2PName_AsyncSequenced(callP2PName, cb)');
  Lines.Add(#9 + '})');
  Lines.Add('');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitProcedureTest(
  Lines: TPascalStringList;
  const ExportedName: TP_String;
  const F: TFunctionStructure);
var
  Args: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);

  Lines.Add('func test' + ExportedName + '() {');

  if Args <> '' then
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '(' + Args + '); err != nil {')
  else
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '(); err != nil {');
  Lines.Add(#9 + #9 + 'reportFail("' + ExportedName + '(app)", err.Error())');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportPass("' + ExportedName + '(app)")');
  Lines.Add(#9 + '}');
  Lines.Add('');

  if Args <> '' then
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '_SequencedNotify(' + Args + '); err != nil {')
  else
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '_SequencedNotify(); err != nil {');
  Lines.Add(#9 + #9 + 'reportFail("' + ExportedName + '(app_seqnotify)", err.Error())');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportPass("' + ExportedName + '(app_seqnotify)")');
  Lines.Add(#9 + '}');
  Lines.Add('');

  Lines.Add(#9 + 'uid, hasUID := getServiceUID()');
  Lines.Add(#9 + 'if hasUID {');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'if err := abi.' + ExportedName + '_UID_Notify(uid, ' + Args + '); err != nil {')
  else
    Lines.Add(#9 + #9 + 'if err := abi.' + ExportedName + '_UID_Notify(uid); err != nil {');
  Lines.Add(#9 + #9 + #9 + 'reportFail("' + ExportedName + '(uid)", err.Error())');
  Lines.Add(#9 + #9 + '} else {');
  Lines.Add(#9 + #9 + #9 + 'reportPass("' + ExportedName + '(uid)")');
  Lines.Add(#9 + #9 + '}');
  Lines.Add('');
  if Args <> '' then
    Lines.Add(#9 + #9 + 'if err := abi.' + ExportedName + '_UID_SequencedNotify(uid, ' + Args + '); err != nil {')
  else
    Lines.Add(#9 + #9 + 'if err := abi.' + ExportedName + '_UID_SequencedNotify(uid); err != nil {');
  Lines.Add(#9 + #9 + #9 + 'reportFail("' + ExportedName + '(uid_seqnotify)", err.Error())');
  Lines.Add(#9 + #9 + '} else {');
  Lines.Add(#9 + #9 + #9 + 'reportPass("' + ExportedName + '(uid_seqnotify)")');
  Lines.Add(#9 + #9 + '}');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportSkip("' + ExportedName + '(uid)", "no service UID")');
  Lines.Add(#9 + #9 + 'reportSkip("' + ExportedName + '(uid_seqnotify)", "no service UID")');
  Lines.Add(#9 + '}');
  Lines.Add('');

  if Args <> '' then
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '_P2PName_Notify(callP2PName, ' + Args + '); err != nil {')
  else
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '_P2PName_Notify(callP2PName); err != nil {');
  Lines.Add(#9 + #9 + 'reportFail("' + ExportedName + '(p2pname)", err.Error())');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportPass("' + ExportedName + '(p2pname)")');
  Lines.Add(#9 + '}');
  Lines.Add('');

  if Args <> '' then
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '_P2PName_SequencedNotify(callP2PName, ' + Args + '); err != nil {')
  else
    Lines.Add(#9 + 'if err := abi.' + ExportedName + '_P2PName_SequencedNotify(callP2PName); err != nil {');
  Lines.Add(#9 + #9 + 'reportFail("' + ExportedName + '(p2pname_seqnotify)", err.Error())');
  Lines.Add(#9 + '} else {');
  Lines.Add(#9 + #9 + 'reportPass("' + ExportedName + '(p2pname_seqnotify)")');
  Lines.Add(#9 + '}');
  Lines.Add('');

  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceTestGoCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, ServiceApp, ServiceP2P, ModulePath: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  ServiceApp := NormalizedUnit + '_abi';
  ServiceP2P := NormalizedUnit + '_service_test_p2p';
  ModulePath := 'local/' + ServiceApp;

  Lines := TPascalStringList.Create;
  try
    Lines.Add('package main');
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add(#9 + '"fmt"');
    Lines.Add(#9 + '"os"');
    Lines.Add('');
    Lines.Add(#9 + 'abi "' + ModulePath.Text + '"');
    Lines.Add('');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/lingofuse"');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/sys"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('const (');
    Lines.Add(#9 + 'serviceEndpoint = "ipc:' + ServiceApp.Text + '"');
    Lines.Add(#9 + 'serviceAppName  = "' + ServiceApp.Text + '"');
    Lines.Add(#9 + 'serviceP2PName  = "' + ServiceP2P.Text + '"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('func cbWhoami(inp, out *lingofuse.DataHandle) {');
    Lines.Add(#9 + 'uid, _ := inp.GetP2PUID()');
    Lines.Add(#9 + 'p2pName, _ := inp.GetP2PName()');
    Lines.Add(#9 + '_ = out.WriteUint8(0x00)');
    Lines.Add(#9 + '_ = out.WriteBytes(uid.Bytes[:])');
    Lines.Add(#9 + '_ = out.WriteString(p2pName)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func cbAskCallMe(inp *lingofuse.DataHandle) {');
    Lines.Add(#9 + 'uid, _ := inp.GetP2PUID()');
    Lines.Add(#9 + 'if sys.IsNullUID(uid) {');
    Lines.Add(#9 + #9 + 'fmt.Fprintln(os.Stderr, "[SERVICE] ask_call_me: no UID in input")');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'clientApi := "LF_TEST_REPORT_SERVICE_IDENTITY"');
    Lines.Add('');
    Lines.Add(#9 + 'req, err := lingofuse.NewDataHandle(clientApi)');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[SERVICE] ask_call_me: NewDataHandle: %v\n", err)');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'defer req.Close()');
    Lines.Add('');
    Lines.Add(#9 + 'if err := req.WriteString("service initiates call"); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[SERVICE] ask_call_me: WriteString: %v\n", err)');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'if err := req.SetPosition(0); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[SERVICE] ask_call_me: SetPosition: %v\n", err)');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'fmt.Printf("[SERVICE] ask_call_me: calling client API %q via UID\n", clientApi)');
    Lines.Add(#9 + 'if err := lingofuse.UID(uid).CallAsync(clientApi, req, func(r lingofuse.AsyncResult) {');
    Lines.Add(#9 + #9 + 'if r.Err != nil {');
    Lines.Add(#9 + #9 + #9 + 'fmt.Printf("[SERVICE] ask_call_me: client call failed: %v\n", r.Err)');
    Lines.Add(#9 + #9 + #9 + 'return');
    Lines.Add(#9 + #9 + '}');
    Lines.Add(#9 + #9 + 'fmt.Println("[SERVICE] ask_call_me: client responded ok")');
    Lines.Add(#9 + '}); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[SERVICE] ask_call_me: dispatch failed: %v\n", err)');
    Lines.Add(#9 + '}');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func cbReportIdentity(inp, out *lingofuse.DataHandle) {');
    Lines.Add(#9 + '_, _ = inp.GetP2PUID()');
    Lines.Add(#9 + '_ = out.WriteUint8(0x00)');
    Lines.Add(#9 + '_ = out.WriteString("identity received")');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func main() {');
    Lines.Add(#9 + 'fmt.Println("=== ' + UnitName.Text + ' ABI service test ===")');
    Lines.Add('');
    Lines.Add(#9 + 'if err := sys.LoadLibrary(); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + '_ = lingofuse.SetOption("Quiet", "True")');
    Lines.Add(#9 + '_ = lingofuse.SetOption("Overlap_Connection", "True")');
    Lines.Add(#9 + '_ = lingofuse.SetOption("Wait_Connection_ReadyOk", "False")');
    Lines.Add(#9 + '_ = lingofuse.ResetPrepare()');
    Lines.Add('');
    Lines.Add(#9 + 'if _, err := lingofuse.PrepareService(serviceEndpoint, serviceEndpoint); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] PrepareService: %v\n", err)');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'app, err := abi.CreateAndRegisterABIApp()');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] CreateAndRegisterABIApp: %v\n", err)');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + '_ = app.RegisterCall("LF_TEST_WHOAMI", "service-side whoami helper", cbWhoami)');
    Lines.Add(#9 + '_ = app.RegisterNotify("LF_TEST_ASK_SERVICE_CALL_ME", "ask service to call back client", cbAskCallMe)');
    Lines.Add(#9 + '_ = app.RegisterCall("LF_TEST_REPORT_SERVICE_IDENTITY", "report identity", cbReportIdentity)');
    Lines.Add('');
    Lines.Add(#9 + '_ = lingofuse.SetOption("LF_P2P_name", serviceP2PName)');
    Lines.Add(#9 + '_ = abi.RegisterAllP2PABIAPIs()');
    Lines.Add(#9 + '_ = lingofuse.RegisterP2PCall("LF_TEST_WHOAMI", "service-side whoami helper", cbWhoami)');
    Lines.Add(#9 + '_ = lingofuse.RegisterP2PNotify("LF_TEST_ASK_SERVICE_CALL_ME", "ask service to call back client", cbAskCallMe)');
    Lines.Add('');
    Lines.Add(#9 + 'if _, err := lingofuse.PrepareClient(serviceEndpoint, app); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] PrepareClient: %v\n", err)');
    Lines.Add(#9 + #9 + 'app.Close()');
    Lines.Add(#9 + #9 + '_ = lingofuse.Shutdown()');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'ok, err := lingofuse.PrepareDone()');
    Lines.Add(#9 + 'if err != nil || !ok {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] PrepareDone: ok=%v err=%v\n", ok, err)');
    Lines.Add(#9 + #9 + '_ = lingofuse.ExitMainThread()');
    Lines.Add(#9 + #9 + 'app.Close()');
    Lines.Add(#9 + #9 + '_ = lingofuse.Shutdown()');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'fmt.Printf("[OK] Service ready on %s\n", serviceEndpoint)');
    Lines.Add(#9 + 'fmt.Printf("[OK] App name : %s\n", serviceAppName)');
    Lines.Add(#9 + 'fmt.Printf("[OK] P2P name : %s\n", serviceP2PName)');
    Lines.Add(#9 + 'fmt.Println("[OK] Press Enter to shut down")');
    Lines.Add('');
    Lines.Add(#9 + 'var dummy string');
    Lines.Add(#9 + '_, _ = fmt.Scanln(&dummy)');
    Lines.Add('');
    Lines.Add(#9 + '_ = lingofuse.ExitMainThread()');
    Lines.Add(#9 + 'app.Close()');
    Lines.Add(#9 + '_ = lingofuse.Shutdown()');
    Lines.Add(#9 + 'fmt.Println("[OK] Shutdown complete")');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateABICallTestGoCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, CallApp, CallP2P, ModulePath: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  ExportedName: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  CallApp := NormalizedUnit + '_abi';
  CallP2P := NormalizedUnit + '_service_test_p2p';
  ModulePath := 'local/' + CallApp;

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := BuildUniqueApiNames(SupportedFuncs);

  Lines := TPascalStringList.Create;
  try
    Lines.Add('package main');
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add(#9 + '"fmt"');
    Lines.Add(#9 + '"os"');
    Lines.Add(#9 + '"sync"');
    Lines.Add(#9 + '"time"');
    Lines.Add('');
    Lines.Add(#9 + 'abi "' + ModulePath.Text + '"');
    Lines.Add('');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/lingofuse"');
    Lines.Add(#9 + '"github.com/PassByYou888/LingoFuse/go/sys"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('const (');
    Lines.Add(#9 + 'callEndpoint = "ipc:' + CallApp.Text + '"');
    Lines.Add(#9 + 'callAppName  = "' + CallApp.Text + '"');
    Lines.Add(#9 + 'callP2PName  = "' + CallP2P.Text + '"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('type callResult[T any] struct {');
    Lines.Add(#9 + 'value T');
    Lines.Add(#9 + 'err   error');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('var (');
    Lines.Add(#9 + 'pass, fail, skip int');
    Lines.Add(#9 + 'serviceUIDMu     sync.RWMutex');
    Lines.Add(#9 + 'serviceUID       sys.TP2P_UID');
    Lines.Add(#9 + 'hasServiceUID    bool');
    Lines.Add(#9 + 'reportCh         chan struct{}');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('func reportPass(label string) {');
    Lines.Add(#9 + 'pass++');
    Lines.Add(#9 + 'fmt.Printf("[PASS] %s\n", label)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func reportFail(label, reason string) {');
    Lines.Add(#9 + 'fail++');
    Lines.Add(#9 + 'fmt.Fprintf(os.Stderr, "[FAIL] %s -- %s\n", label, reason)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func reportSkip(label, reason string) {');
    Lines.Add(#9 + 'skip++');
    Lines.Add(#9 + 'fmt.Printf("[SKIP] %s -- %s\n", label, reason)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func setServiceUID(uid sys.TP2P_UID) {');
    Lines.Add(#9 + 'serviceUIDMu.Lock()');
    Lines.Add(#9 + 'serviceUID = uid');
    Lines.Add(#9 + 'hasServiceUID = !sys.IsNullUID(uid)');
    Lines.Add(#9 + 'serviceUIDMu.Unlock()');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func clearServiceUID() {');
    Lines.Add(#9 + 'serviceUIDMu.Lock()');
    Lines.Add(#9 + 'serviceUID = sys.NullUID');
    Lines.Add(#9 + 'hasServiceUID = false');
    Lines.Add(#9 + 'serviceUIDMu.Unlock()');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func getServiceUID() (sys.TP2P_UID, bool) {');
    Lines.Add(#9 + 'serviceUIDMu.RLock()');
    Lines.Add(#9 + 'defer serviceUIDMu.RUnlock()');
    Lines.Add(#9 + 'return serviceUID, hasServiceUID');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func asyncScalar[T any](label string, dispatch func(cb func(T, error)) error) {');
    Lines.Add(#9 + 'ch := make(chan callResult[T], 1)');
    Lines.Add(#9 + 'if err := dispatch(func(v T, e error) {');
    Lines.Add(#9 + #9 + 'ch <- callResult[T]{value: v, err: e}');
    Lines.Add(#9 + '}); err != nil {');
    Lines.Add(#9 + #9 + 'reportFail(label, err.Error())');
    Lines.Add(#9 + #9 + 'return');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'select {');
    Lines.Add(#9 + 'case r := <-ch:');
    Lines.Add(#9 + #9 + 'if r.err != nil {');
    Lines.Add(#9 + #9 + #9 + 'reportFail(label, r.err.Error())');
    Lines.Add(#9 + #9 + '} else {');
    Lines.Add(#9 + #9 + #9 + 'reportPass(fmt.Sprintf("%s = %v", label, r.value))');
    Lines.Add(#9 + #9 + '}');
    Lines.Add(#9 + 'case <-time.After(10 * time.Second):');
    Lines.Add(#9 + #9 + 'reportFail(label, "timeout")');
    Lines.Add(#9 + '}');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func cbReportIdentity(inp, out *lingofuse.DataHandle) {');
    Lines.Add(#9 + 'uid, _ := inp.GetP2PUID()');
    Lines.Add(#9 + 'if !sys.IsNullUID(uid) {');
    Lines.Add(#9 + #9 + 'setServiceUID(uid)');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + '_ = out.WriteUint8(0x00)');
    Lines.Add(#9 + '_ = out.WriteString("identity received")');
    Lines.Add(#9 + 'if reportCh != nil {');
    Lines.Add(#9 + #9 + 'select {');
    Lines.Add(#9 + #9 + 'case reportCh <- struct{}{}:');
    Lines.Add(#9 + #9 + 'default:');
    Lines.Add(#9 + #9 + '}');
    Lines.Add(#9 + '}');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func probeClientIdentity() bool {');
    Lines.Add(#9 + 'req, err := lingofuse.NewDataHandle("LF_TEST_WHOAMI")');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "probeClientIdentity: NewDataHandle: %v\n", err)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'defer req.Close()');
    Lines.Add('');
    Lines.Add(#9 + 'res, err := lingofuse.App(callAppName).Call("LF_TEST_WHOAMI", req, 5000)');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "probeClientIdentity: call: %v\n", err)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'defer res.Close()');
    Lines.Add('');
    Lines.Add(#9 + 'sz, _ := res.Size()');
    Lines.Add(#9 + 'if sz < 33 {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "probeClientIdentity: response too short (%d bytes)\n", sz)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + '_ = res.SetPosition(0)');
    Lines.Add('');
    Lines.Add(#9 + 'status, err := res.ReadUint8()');
    Lines.Add(#9 + 'if err != nil || status != 0x00 {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "probeClientIdentity: bad status (err=%v status=0x%02X)\n", err, status)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'data, err := res.ReadBytesExact(32)');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "probeClientIdentity: ReadBytesExact: %v\n", err)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'p2pName, _ := res.ReadString()');
    Lines.Add('');
    Lines.Add(#9 + 'var uid sys.TP2P_UID');
    Lines.Add(#9 + 'copy(uid.Bytes[:], data)');
    Lines.Add('');
    Lines.Add(#9 + 'nonZero := false');
    Lines.Add(#9 + 'for _, b := range uid.Bytes {');
    Lines.Add(#9 + #9 + 'if b != 0 {');
    Lines.Add(#9 + #9 + #9 + 'nonZero = true');
    Lines.Add(#9 + #9 + #9 + 'break');
    Lines.Add(#9 + #9 + '}');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'fmt.Printf("[INFO] client UID = %s\n", sys.FormatUIDHex(uid))');
    Lines.Add(#9 + 'fmt.Printf("[INFO] client P2P = %s\n", p2pName)');
    Lines.Add(#9 + 'return nonZero');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('func testServiceInitiatesCall() bool {');
    Lines.Add(#9 + 'clearServiceUID()');
    Lines.Add(#9 + 'reportCh = make(chan struct{}, 1)');
    Lines.Add('');
    Lines.Add(#9 + 'req, err := lingofuse.NewDataHandle("LF_TEST_ASK_SERVICE_CALL_ME")');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "testServiceInitiatesCall: NewDataHandle: %v\n", err)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'defer req.Close()');
    Lines.Add('');
    Lines.Add(#9 + '_ = req.WriteString("LF_TEST_REPORT_SERVICE_IDENTITY")');
    Lines.Add(#9 + '_ = req.SetPosition(0)');
    Lines.Add('');
    Lines.Add(#9 + 'if err := lingofuse.App(callAppName).Notify("LF_TEST_ASK_SERVICE_CALL_ME", req); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "testServiceInitiatesCall: notify: %v\n", err)');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'select {');
    Lines.Add(#9 + 'case <-reportCh:');
    Lines.Add(#9 + #9 + '_, has := getServiceUID()');
    Lines.Add(#9 + #9 + 'return has');
    Lines.Add(#9 + 'case <-time.After(10 * time.Second):');
    Lines.Add(#9 + #9 + 'return false');
    Lines.Add(#9 + '}');
    Lines.Add('}');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ExportedName := MakeExportedGoName(ApiNames[i]);
      if SupportedFuncs[i].IsFunction then
        EmitFunctionTest(Lines, ExportedName, SupportedFuncs[i])
      else
        EmitProcedureTest(Lines, ExportedName, SupportedFuncs[i]);
    end;

    Lines.Add('func main() {');
    Lines.Add(#9 + 'fmt.Println("=== ' + UnitName.Text + ' ABI client test ===")');
    Lines.Add(#9 + 'fmt.Printf("Endpoint: %s\n", callEndpoint)');
    Lines.Add(#9 + 'fmt.Printf("AppName : %s\n", callAppName)');
    Lines.Add(#9 + 'fmt.Printf("P2PName : %s\n", callP2PName)');
    Lines.Add(#9 + 'fmt.Println()');
    Lines.Add('');
    Lines.Add(#9 + 'if err := sys.LoadLibrary(); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + '_ = lingofuse.SetOption("Quiet", "True")');
    Lines.Add(#9 + '_ = lingofuse.SetOption("Overlap_Connection", "True")');
    Lines.Add(#9 + '_ = lingofuse.SetOption("Wait_Connection_ReadyOk", "False")');
    Lines.Add(#9 + '_ = lingofuse.ResetPrepare()');
    Lines.Add('');
    Lines.Add(#9 + 'clientApp, err := lingofuse.NewAppHandle("LF_TEST_CLIENT_SELF", "client test app")');
    Lines.Add(#9 + 'if err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] NewAppHandle: %v\n", err)');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + '_ = clientApp.RegisterCall("LF_TEST_REPORT_SERVICE_IDENTITY", "report identity", cbReportIdentity)');
    Lines.Add('');
    Lines.Add(#9 + 'if _, err := lingofuse.PrepareClient(callEndpoint, clientApp); err != nil {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] PrepareClient: %v\n", err)');
    Lines.Add(#9 + #9 + 'clientApp.Close()');
    Lines.Add(#9 + #9 + '_ = lingofuse.Shutdown()');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'ok, err := lingofuse.PrepareDone()');
    Lines.Add(#9 + 'if err != nil || !ok {');
    Lines.Add(#9 + #9 + 'fmt.Fprintf(os.Stderr, "[FATAL] PrepareDone: ok=%v err=%v\n", ok, err)');
    Lines.Add(#9 + #9 + '_ = lingofuse.ExitMainThread()');
    Lines.Add(#9 + #9 + 'clientApp.Close()');
    Lines.Add(#9 + #9 + '_ = lingofuse.Shutdown()');
    Lines.Add(#9 + #9 + 'os.Exit(1)');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'fmt.Println("[READY] Client online")');
    Lines.Add(#9 + 'fmt.Println()');
    Lines.Add('');
    Lines.Add(#9 + 'ready := false');
    Lines.Add(#9 + 'for i := 0; i < 30; i++ {');
    Lines.Add(#9 + #9 + 'if ok, _ := lingofuse.CheckApp(callAppName); ok {');
    Lines.Add(#9 + #9 + #9 + 'ready = true');
    Lines.Add(#9 + #9 + #9 + 'break');
    Lines.Add(#9 + #9 + '}');
    Lines.Add(#9 + #9 + 'time.Sleep(200 * time.Millisecond)');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'if !ready {');
    Lines.Add(#9 + #9 + 'fmt.Fprintln(os.Stderr, "[WARN] service not detected; proceeding anyway")');
    Lines.Add(#9 + '}');
    Lines.Add('');
    Lines.Add(#9 + 'if probeClientIdentity() {');
    Lines.Add(#9 + #9 + 'fmt.Println("[OK] client identity probe")');
    Lines.Add(#9 + '} else {');
    Lines.Add(#9 + #9 + 'fmt.Println("[WARN] whoami failed, UID tests will be skipped")');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'fmt.Println()');
    Lines.Add('');
    Lines.Add(#9 + 'if testServiceInitiatesCall() {');
    Lines.Add(#9 + #9 + 'fmt.Println("[OK] service-initiated call")');
    Lines.Add(#9 + '} else {');
    Lines.Add(#9 + #9 + 'fmt.Fprintln(os.Stderr, "[WARN] service-initiated call failed")');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'fmt.Println()');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ExportedName := MakeExportedGoName(ApiNames[i]);
      Lines.Add(#9 + 'test' + ExportedName + '()');
    end;

    Lines.Add('');
    Lines.Add(#9 + 'fmt.Println()');
    Lines.Add(#9 + 'fmt.Println("=== Summary ===")');
    Lines.Add(#9 + 'fmt.Printf("Pass: %d\n", pass)');
    Lines.Add(#9 + 'fmt.Printf("Fail: %d\n", fail)');
    Lines.Add(#9 + 'fmt.Printf("Skip: %d\n", skip)');
    Lines.Add('');
    Lines.Add(#9 + '_ = lingofuse.ExitMainThread()');
    Lines.Add(#9 + 'clientApp.Close()');
    Lines.Add(#9 + '_ = lingofuse.Shutdown()');
    Lines.Add(#9 + 'fmt.Println("[OK] Client test complete")');
    Lines.Add('');
    Lines.Add(#9 + 'if fail == 0 {');
    Lines.Add(#9 + #9 + 'os.Exit(0)');
    Lines.Add(#9 + '}');
    Lines.Add(#9 + 'os.Exit(2)');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'go',
    'xxx_abi_service_test.go',
    gkTest,
    'Go ABI service test program',
    @GenerateABIServiceTestGoCode);

  RegisterGenerator(
    'go',
    'xxx_abi_call_test.go',
    gkTest,
    'Go ABI call test program',
    @GenerateABICallTestGoCode);

end.
