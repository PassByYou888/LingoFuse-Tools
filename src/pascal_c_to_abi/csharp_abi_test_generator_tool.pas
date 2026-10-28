unit csharp_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_CSharp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'int'
  else if T.Same('int64') then Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'uint'
  else if T.Same('word') then Result := 'ushort'
  else if T.Same('smallint') then Result := 'short'
  else if T.Same('byte') then Result := 'byte'
  else if T.Same('uint64') then Result := 'ulong'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'double'
  else if T.Same('single') then Result := 'float'
  else if IsStringABIType(T) then Result := 'string'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_CSharp_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function CSharpStrLit(const S: TP_String): TP_String;
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
    else if c = #0 then
    begin
      Result.Append('\');
      Result.Append('0');
    end
    else
      Result.Append(c);
  end;
  Result.Append('"');
end;

function PlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := '"test"'
  else if ABIType.Same('single') then
    Result := '0.0f'
  else if ABIType.Same('double') or ABIType.Same('extended') or ABIType.Same('real') then
    Result := '0.0'
  else
    Result := '0';
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

function BuildUniqueNames(const Funcs: TArryFunctionStructure): TPascalStringList;
var
  i, j: integer;
  N: TP_String;
begin
  Result := TPascalStringList.Create;
  for i := 0 to High(Funcs) do
  begin
    N := MakeApiName(Funcs[i].Name);
    if Result.IndexOf(N) >= 0 then
    begin
      j := 1;
      while Result.IndexOf(N + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      N := N + '_' + umlIntToStr(j).Text;
    end;
    Result.Add(N);
  end;
end;

function BuildArgs(const F: TFunctionStructure; const UseUid, UseP2P: boolean): TP_String;
var
  i: integer;
begin
  Result := '';
  if UseUid then
    Result := 'TestContext.ServiceUid';
  if UseP2P then
    Result := 'TargetP2PName';
  for i := 0 to High(F.Params) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + PlaceholderValue(F.Params[i].PascalType);
  end;
end;

function BuildCallExpr(const MethodName, Args: TP_String): TP_String;
begin
  if Args = '' then
    Result := MethodName + '()'
  else
    Result := MethodName + '(' + Args + ')';
end;

function GenerateABIServiceMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, NsName, AppName, P2PName: TP_String;
  SupportedFuncs: TArryFunctionStructure;
  Lines: TPascalStringList;
  ApiCountStr: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  Log(PFormat('Generating C# ABI service test program for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiCountStr := umlIntToStr(Length(SupportedFuncs));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('using System;');
    Lines.Add('using System.Threading;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName + ';');
    Lines.Add('');
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    private const string TestP2PName = "' + P2PName + '";');
    Lines.Add('    private const string WhoAmIApi = "LF_TEST_WHOAMI";');
    Lines.Add('    private const string AskCallMeApi = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('    private const string ReportIdentityApi = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('');
    Lines.Add('    private static int Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("=== ' + UnitName.Text + ' ABI service test ===");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        string endpoint = "ipc:" + AppInfo.Name;');
    Lines.Add('');
    Lines.Add('        Framework.ResetPrepare();');
    Lines.Add('        Framework.PrepareService(endpoint, endpoint);');
    Lines.Add('');
    Lines.Add('        AppHandle app = Service.CreateAndRegisterABIApp();');
    Lines.Add('        if (app == null)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] CreateAndRegisterABIApp returned null");');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        app.RegisterCall(WhoAmIApi, "whoami helper", Callback_TestWhoAmI);');
    Lines.Add('        app.RegisterNotify(AskCallMeApi, "ask service to call back client", Callback_TestAskServiceCallMe);');
    Lines.Add('');
    Lines.Add('        Framework.SetOption("LF_P2P_name", TestP2PName);');
    Lines.Add('        Service.RegisterAllP2PABIAPIs();');
    Lines.Add('        Framework.RegisterP2PCall(WhoAmIApi, "whoami helper", Callback_TestWhoAmI);');
    Lines.Add('        Framework.RegisterP2PNotify(AskCallMeApi, "ask service to call back client", Callback_TestAskServiceCallMe);');
    Lines.Add('');
    Lines.Add('        if (Framework.PrepareClient(endpoint, app) == -1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] PrepareClient failed");');
    Lines.Add('            app.Dispose();');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        if (Framework.PrepareDone() != 1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] PrepareDone failed");');
    Lines.Add('            Framework.ExitMainThread();');
    Lines.Add('            app.Dispose();');
    Lines.Add('            Framework.Shutdown();');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        Console.WriteLine("[OK] Service ready on " + endpoint);');
    Lines.Add('        Console.WriteLine("[OK] Registered ' + ApiCountStr + ' API(s) + 2 test helper(s) (App + P2P).");');
    Lines.Add('        Console.WriteLine("[OK] Press Enter to shut down.");');
    Lines.Add('');
    Lines.Add('        string line;');
    Lines.Add('        while ((line = Console.ReadLine()) != null)');
    Lines.Add('        {');
    Lines.Add('            if (line.Length == 0) break;');
    Lines.Add('            if (line.Trim().Equals("exit", StringComparison.OrdinalIgnoreCase)) break;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        Framework.ExitMainThread();');
    Lines.Add('        app.Dispose();');
    Lines.Add('        Framework.Shutdown();');
    Lines.Add('        Console.WriteLine("[OK] Shutdown complete.");');
    Lines.Add('        return 0;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static void Callback_TestWhoAmI(DataHandle inHandle, DataHandle outHandle)');
    Lines.Add('    {');
    Lines.Add('        P2PUid uid = P2PUid.Empty;');
    Lines.Add('        string p2p = string.Empty;');
    Lines.Add('        try');
    Lines.Add('        {');
    Lines.Add('            uid = inHandle.GetSenderUid();');
    Lines.Add('            p2p = inHandle.GetSenderP2PName();');
    Lines.Add('        }');
    Lines.Add('        catch { }');
    Lines.Add('');
    Lines.Add('        Console.WriteLine("[SERVICE] whoami: p2p=" + p2p);');
    Lines.Add('        outHandle.WriteUInt8(0x00);');
    Lines.Add('        outHandle.WriteBytes(uid.ToByteArray());');
    Lines.Add('        outHandle.WriteString(p2p);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static void Callback_TestAskServiceCallMe(DataHandle inHandle)');
    Lines.Add('    {');
    Lines.Add('        P2PUid clientUid = P2PUid.Empty;');
    Lines.Add('        try { clientUid = inHandle.GetSenderUid(); }');
    Lines.Add('        catch { }');
    Lines.Add('');
    Lines.Add('        if (clientUid.IsEmpty)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[SERVICE] ask_call_me: no UID in input");');
    Lines.Add('            return;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        using (var req = new DataHandle(ReportIdentityApi))');
    Lines.Add('        {');
    Lines.Add('            req.WriteString("service initiates call");');
    Lines.Add('            Console.WriteLine("[SERVICE] ask_call_me: calling client via UID");');
    Lines.Add('            try');
    Lines.Add('            {');
    Lines.Add('                using (var res = Framework.CallByUid(clientUid, req, 10000))');
    Lines.Add('                {');
    Lines.Add('                    if (res.IsValid && res.Size > 0)');
    Lines.Add('                        Console.WriteLine("[SERVICE] ask_call_me: client responded ok");');
    Lines.Add('                    else');
    Lines.Add('                        Console.WriteLine("[SERVICE] ask_call_me: UID call returned empty");');
    Lines.Add('                }');
    Lines.Add('            }');
    Lines.Add('            catch (Exception ex)');
    Lines.Add('            {');
    Lines.Add('                Console.Error.WriteLine("[SERVICE] ask_call_me failed: " + ex.Message);');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service test program.', [Lines.Count]));
  finally
  end;
end;

procedure EmitFunctionTest(Lines: TPascalStringList; const MethodName, ApiName: TP_String;
  const F: TFunctionStructure);
var
  Args: TP_String;
  CallExpr: TP_String;
begin
  Lines.Add('    private static async System.Threading.Tasks.Task Test_' + MethodName + '()');
  Lines.Add('    {');

  Args := BuildArgs(F, False, False);
  CallExpr := BuildCallExpr('ABI.' + MethodName, Args);
  Lines.Add('        await System.Threading.Tasks.Task.Delay(20);');
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            var r = ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(app call)", r.ToString());');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(app call)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_Async', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            var r = await ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(app async)", r.ToString());');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(app async)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_AsyncSequenced', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            var r = await ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(app asyncSeq)", r.ToString());');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(app asyncSeq)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  Args := BuildArgs(F, True, False);
  CallExpr := BuildCallExpr('ABI.' + MethodName + '_UID_Call', Args);
  Lines.Add('        if (TestContext.HasServiceUid)');
  Lines.Add('        {');
  Lines.Add('            await System.Threading.Tasks.Task.Delay(20);');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                var r = ' + CallExpr + ';');
  Lines.Add('                LogPass("' + ApiName + '(uid call)", r.ToString());');
  Lines.Add('            }');
  Lines.Add('            catch (Exception ex)');
  Lines.Add('            {');
  Lines.Add('                LogFail("' + ApiName + '(uid call)", ex.Message);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        else');
  Lines.Add('        {');
  Lines.Add('            LogSkip("' + ApiName + '(uid call)", "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_UID_Async', Args);
  Lines.Add('        if (TestContext.HasServiceUid)');
  Lines.Add('        {');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                var r = await ' + CallExpr + ';');
  Lines.Add('                LogPass("' + ApiName + '(uid async)", r.ToString());');
  Lines.Add('            }');
  Lines.Add('            catch (Exception ex)');
  Lines.Add('            {');
  Lines.Add('                LogFail("' + ApiName + '(uid async)", ex.Message);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        else');
  Lines.Add('        {');
  Lines.Add('            LogSkip("' + ApiName + '(uid async)", "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_UID_AsyncSequenced', Args);
  Lines.Add('        if (TestContext.HasServiceUid)');
  Lines.Add('        {');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                var r = await ' + CallExpr + ';');
  Lines.Add('                LogPass("' + ApiName + '(uid asyncSeq)", r.ToString());');
  Lines.Add('            }');
  Lines.Add('            catch (Exception ex)');
  Lines.Add('            {');
  Lines.Add('                LogFail("' + ApiName + '(uid asyncSeq)", ex.Message);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        else');
  Lines.Add('        {');
  Lines.Add('            LogSkip("' + ApiName + '(uid asyncSeq)", "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  Args := BuildArgs(F, False, True);
  CallExpr := BuildCallExpr('ABI.' + MethodName + '_P2PName_Call', Args);
  Lines.Add('        await System.Threading.Tasks.Task.Delay(20);');
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            var r = ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(p2pname call)", r.ToString());');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(p2pname call)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_P2PName_Async', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            var r = await ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(p2pname async)", r.ToString());');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(p2pname async)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_P2PName_AsyncSequenced', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            var r = await ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(p2pname asyncSeq)", r.ToString());');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(p2pname asyncSeq)", ex.Message);');
  Lines.Add('        }');

  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitProcedureTest(Lines: TPascalStringList; const MethodName, ApiName: TP_String;
  const F: TFunctionStructure);
var
  Args: TP_String;
  CallExpr: TP_String;
begin
  Lines.Add('    private static void Test_' + MethodName + '()');
  Lines.Add('    {');

  Args := BuildArgs(F, False, False);
  CallExpr := BuildCallExpr('ABI.' + MethodName, Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(app notify)");');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(app notify)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_SequencedNotify', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(app seq notify)");');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(app seq notify)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  Args := BuildArgs(F, True, False);
  CallExpr := BuildCallExpr('ABI.' + MethodName + '_UID_Notify', Args);
  Lines.Add('        if (TestContext.HasServiceUid)');
  Lines.Add('        {');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                ' + CallExpr + ';');
  Lines.Add('                LogPass("' + ApiName + '(uid notify)");');
  Lines.Add('            }');
  Lines.Add('            catch (Exception ex)');
  Lines.Add('            {');
  Lines.Add('                LogFail("' + ApiName + '(uid notify)", ex.Message);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        else');
  Lines.Add('        {');
  Lines.Add('            LogSkip("' + ApiName + '(uid notify)", "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_UID_SequencedNotify', Args);
  Lines.Add('        if (TestContext.HasServiceUid)');
  Lines.Add('        {');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                ' + CallExpr + ';');
  Lines.Add('                LogPass("' + ApiName + '(uid seq notify)");');
  Lines.Add('            }');
  Lines.Add('            catch (Exception ex)');
  Lines.Add('            {');
  Lines.Add('                LogFail("' + ApiName + '(uid seq notify)", ex.Message);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        else');
  Lines.Add('        {');
  Lines.Add('            LogSkip("' + ApiName + '(uid seq notify)", "no service UID");');
  Lines.Add('        }');
  Lines.Add('');

  Args := BuildArgs(F, False, True);
  CallExpr := BuildCallExpr('ABI.' + MethodName + '_P2PName_Notify', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(p2pname notify)");');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(p2pname notify)", ex.Message);');
  Lines.Add('        }');
  Lines.Add('');

  CallExpr := BuildCallExpr('ABI.' + MethodName + '_P2PName_SequencedNotify', Args);
  Lines.Add('        try');
  Lines.Add('        {');
  Lines.Add('            ' + CallExpr + ';');
  Lines.Add('            LogPass("' + ApiName + '(p2pname seq notify)");');
  Lines.Add('        }');
  Lines.Add('        catch (Exception ex)');
  Lines.Add('        {');
  Lines.Add('            LogFail("' + ApiName + '(p2pname seq notify)", ex.Message);');
  Lines.Add('        }');

  Lines.Add('    }');
  Lines.Add('');
end;

function GenerateABICallMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, P2PName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
  FuncCount, ProcCount: integer;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi_call';
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  SupportedFuncs := CollectSupportedFunctions(Model);

  FuncCount := 0;
  ProcCount := 0;
  for i := 0 to High(SupportedFuncs) do
    if SupportedFuncs[i].IsFunction then
      Inc(FuncCount)
    else
      Inc(ProcCount);

  Log(PFormat('Generating C# ABI call test program for unit "%s" (%d functions, %d procedures)',
    [UnitName.Text, FuncCount, ProcCount]));

  UsedApiNames := BuildUniqueNames(SupportedFuncs);
  Lines := TPascalStringList.Create;
  try
    Lines.Add('using System;');
    Lines.Add('using System.Threading.Tasks;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName + ';');
    Lines.Add('');
    Lines.Add('internal sealed class TestStats');
    Lines.Add('{');
    Lines.Add('    public int Pass;');
    Lines.Add('    public int Fail;');
    Lines.Add('    public int Skip;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('internal static class TestContext');
    Lines.Add('{');
    Lines.Add('    public static P2PUid ServiceUid = P2PUid.Empty;');
    Lines.Add('    public static string ServiceP2PName = string.Empty;');
    Lines.Add('    public static bool HasServiceUid = false;');
    Lines.Add('    public static bool ServiceCalledMe = false;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    private const string TestClientApp = "LF_TEST_CLIENT_SELF";');
    Lines.Add('    private const string ReportIdentityApi = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('    private const string AskCallMeApi = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('    private const string WhoAmIApi = "LF_TEST_WHOAMI";');
    Lines.Add('    private const string TargetP2PName = "' + P2PName + '";');
    Lines.Add('');
    Lines.Add('    private static readonly TestStats Stats = new TestStats();');
    Lines.Add('');
    Lines.Add('    private static void LogPass(string label, string value = "")');
    Lines.Add('    {');
    Lines.Add('        Stats.Pass++;');
    Lines.Add('        if (!string.IsNullOrEmpty(value))');
    Lines.Add('            Console.WriteLine("[PASS] " + label + " = " + value);');
    Lines.Add('        else');
    Lines.Add('            Console.WriteLine("[PASS] " + label);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static void LogFail(string label, string msg)');
    Lines.Add('    {');
    Lines.Add('        Stats.Fail++;');
    Lines.Add('        Console.Error.WriteLine("[FAIL] " + label + " -- " + msg);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static void LogSkip(string label, string reason)');
    Lines.Add('    {');
    Lines.Add('        Stats.Skip++;');
    Lines.Add('        Console.WriteLine("[SKIP] " + label + " -- " + reason);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static async Task<int> Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("=== ' + UnitName.Text + ' ABI client test ===");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        ABI.Timeout = 10000;');
    Lines.Add('        string endpoint = "ipc:" + ABI.TargetApp;');
    Lines.Add('');
    Lines.Add('        Framework.ResetPrepare();');
    Lines.Add('');
    Lines.Add('        using (var clientApp = new AppHandle(TestClientApp, "client test app"))');
    Lines.Add('        {');
    Lines.Add('            clientApp.RegisterCall(ReportIdentityApi, "report service identity", Callback_TestReportServiceIdentity);');
    Lines.Add('');
    Lines.Add('            if (Framework.PrepareClient(endpoint, clientApp) == -1)');
    Lines.Add('            {');
    Lines.Add('                Console.Error.WriteLine("[FATAL] PrepareClient failed");');
    Lines.Add('                return 1;');
    Lines.Add('            }');
    Lines.Add('');
    Lines.Add('            if (Framework.PrepareDone() != 1)');
    Lines.Add('            {');
    Lines.Add('                Console.Error.WriteLine("[FATAL] PrepareDone failed");');
    Lines.Add('                Framework.ExitMainThread();');
    Lines.Add('                Framework.Shutdown();');
    Lines.Add('                return 1;');
    Lines.Add('            }');
    Lines.Add('');
    Lines.Add('            Console.WriteLine("[OK] Client online.");');
    Lines.Add('            Console.WriteLine();');
    Lines.Add('');
    Lines.Add('            if (ProbeClientIdentity())');
    Lines.Add('                Console.WriteLine("[OK] client identity probe");');
    Lines.Add('            else');
    Lines.Add('                Console.WriteLine("[WARN] whoami failed; UID variants will be skipped.");');
    Lines.Add('');
    Lines.Add('            if (await TestServiceInitiatesCall())');
    Lines.Add('            {');
    Lines.Add('                Console.WriteLine("[OK] service-initiated call");');
    Lines.Add('                Console.WriteLine("[INFO] service UID    = " + TestContext.ServiceUid.ToHexString());');
    Lines.Add('                Console.WriteLine("[INFO] service P2PName = " + TestContext.ServiceP2PName);');
    Lines.Add('            }');
    Lines.Add('            else');
    Lines.Add('            {');
    Lines.Add('                LogFail("service-initiated call", "timeout or no UID");');
    Lines.Add('            }');
    Lines.Add('');
    Lines.Add('            Console.WriteLine();');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UsedApiNames[i];
      if SupportedFuncs[i].IsFunction then
        Lines.Add('            await Test_' + ApiName + '();')
      else
        Lines.Add('            Test_' + ApiName + '();');
    end;

    Lines.Add('');
    Lines.Add('            Console.WriteLine();');
    Lines.Add('            Console.WriteLine("=== Summary ===");');
    Lines.Add('            Console.WriteLine("Pass: " + Stats.Pass);');
    Lines.Add('            Console.WriteLine("Fail: " + Stats.Fail);');
    Lines.Add('            Console.WriteLine("Skip: " + Stats.Skip);');
    Lines.Add('');
    Lines.Add('            Framework.ExitMainThread();');
    Lines.Add('            Framework.Shutdown();');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        Console.WriteLine("[OK] Client test complete.");');
    Lines.Add('        return Stats.Fail == 0 ? 0 : 2;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static bool ProbeClientIdentity()');
    Lines.Add('    {');
    Lines.Add('        using (var req = new DataHandle(WhoAmIApi))');
    Lines.Add('        {');
    Lines.Add('            try');
    Lines.Add('            {');
    Lines.Add('                using (var res = Framework.Call(ABI.TargetApp, req, 10000))');
    Lines.Add('                {');
    Lines.Add('                    if (!res.IsValid || res.Size < 34) return false;');
    Lines.Add('                    res.Position = 0;');
    Lines.Add('                    byte status = res.ReadUInt8();');
    Lines.Add('                    if (status != 0x00) return false;');
    Lines.Add('                    byte[] uidBytes = res.ReadBytesExact(32);');
    Lines.Add('                    P2PUid clientUid = P2PUid.FromBytes(uidBytes);');
    Lines.Add('                    string clientP2P = res.ReadString();');
    Lines.Add('                    bool hasUid = !clientUid.IsEmpty;');
    Lines.Add('                    Console.WriteLine("[INFO] client UID    = " + clientUid.ToHexString());');
    Lines.Add('                    Console.WriteLine("[INFO] client P2PName = " + clientP2P);');
    Lines.Add('                    return hasUid;');
    Lines.Add('                }');
    Lines.Add('            }');
    Lines.Add('            catch (Exception ex)');
    Lines.Add('            {');
    Lines.Add('                Console.Error.WriteLine("[WARN] whoami failed: " + ex.Message);');
    Lines.Add('                return false;');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static async Task<bool> TestServiceInitiatesCall()');
    Lines.Add('    {');
    Lines.Add('        TestContext.ServiceCalledMe = false;');
    Lines.Add('        TestContext.HasServiceUid = false;');
    Lines.Add('        TestContext.ServiceUid = P2PUid.Empty;');
    Lines.Add('        TestContext.ServiceP2PName = string.Empty;');
    Lines.Add('');
    Lines.Add('        using (var req = new DataHandle(AskCallMeApi))');
    Lines.Add('        {');
    Lines.Add('            req.WriteString("service initiates call");');
    Lines.Add('            Framework.Notify(ABI.TargetApp, req);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        var deadline = DateTime.UtcNow.AddSeconds(10);');
    Lines.Add('        while (DateTime.UtcNow < deadline)');
    Lines.Add('        {');
    Lines.Add('            if (TestContext.ServiceCalledMe) break;');
    Lines.Add('            await Task.Delay(10);');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        return TestContext.ServiceCalledMe && TestContext.HasServiceUid;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static void Callback_TestReportServiceIdentity(DataHandle inHandle, DataHandle outHandle)');
    Lines.Add('    {');
    Lines.Add('        try');
    Lines.Add('        {');
    Lines.Add('            TestContext.ServiceUid = inHandle.GetSenderUid();');
    Lines.Add('            TestContext.ServiceP2PName = inHandle.GetSenderP2PName();');
    Lines.Add('            TestContext.HasServiceUid = !TestContext.ServiceUid.IsEmpty;');
    Lines.Add('            TestContext.ServiceCalledMe = true;');
    Lines.Add('');
    Lines.Add('            string msg = string.Empty;');
    Lines.Add('            try { msg = inHandle.ReadString(); } catch { }');
    Lines.Add('            Console.WriteLine("[CLIENT] service called me: msg=" + msg);');
    Lines.Add('');
    Lines.Add('            outHandle.WriteUInt8(0x00);');
    Lines.Add('            outHandle.WriteString("identity received");');
    Lines.Add('        }');
    Lines.Add('        catch (Exception ex)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[CLIENT] report_identity failed: " + ex.Message);');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      if SupportedFuncs[i].IsFunction then
        EmitFunctionTest(Lines, UsedApiNames[i], UsedApiNames[i], SupportedFuncs[i])
      else
        EmitProcedureTest(Lines, UsedApiNames[i], UsedApiNames[i], SupportedFuncs[i]);
    end;

    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test program.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'csharp',
    'xxx_abi_service_test___.cs',
    gkTest,
    'C# ABI service test program',
    @GenerateABIServiceMainTestCsharpCode);

  RegisterGenerator(
    'csharp',
    'xxx_abi_call_test___.cs',
    gkTest,
    'C# ABI call test program',
    @GenerateABICallMainTestCsharpCode);

end.
