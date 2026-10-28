unit julia_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestJuliaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Julia_TestValue(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then Result := '"test"'
  else if T.Same('single') then Result := 'Float32(3.14)'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'Float64(3.14)'
  else if T.Same('byte') then Result := 'UInt8(42)'
  else if T.Same('word') then Result := 'UInt16(42)'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'UInt32(42)'
  else if T.Same('uint64') then Result := 'UInt64(42)'
  else if T.Same('smallint') then Result := 'Int16(42)'
  else if T.Same('integer') or T.Same('longint') then Result := 'Int32(42)'
  else if T.Same('int64') then Result := 'Int64(42)'
  else Result := 'nothing';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('longint') or T.Same('int64') or
    T.Same('cardinal') or T.Same('dword') or T.Same('longword') or
    T.Same('word') or T.Same('smallint') or T.Same('byte') or
    T.Same('uint64') or T.Same('double') or T.Same('extended') or
    T.Same('real') or T.Same('single') or IsStringABIType(T);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function JuliaStrLit(const S: TP_String): TP_String;
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
        Log(PFormat('Skipped "%s": parameter "%s" unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" unsupported', [f.Name.Text, f.ReturnType.Text]));
    end;
    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: empty Name');
    end;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

procedure AssignUniqueApiNames(const Funcs: TArryFunctionStructure; Names: TPascalStringList);
var
  i, j: integer;
  N: TP_String;
begin
  Names.Clear;
  for i := 0 to High(Funcs) do
  begin
    N := MakeApiName(Funcs[i].Name);
    if Names.IndexOf(N) >= 0 then
    begin
      j := 1;
      while Names.IndexOf(N + '_' + IntToStr(j)) >= 0 do
        Inc(j);
      N := N + '_' + IntToStr(j);
    end;
    Names.Add(N);
  end;
end;

procedure EmitTestHarness(Lines: TPascalStringList);
begin
  Lines.Add('mutable struct TestContext');
  Lines.Add('    pass::Int');
  Lines.Add('    fail::Int');
  Lines.Add('    skip::Int');
  Lines.Add('    TestContext() = new(0, 0, 0)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function t_pass!(ctx::TestContext, label::String)');
  Lines.Add('    ctx.pass += 1');
  Lines.Add('    println("[PASS] ", label)');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function t_fail!(ctx::TestContext, label::String, reason::String)');
  Lines.Add('    ctx.fail += 1');
  Lines.Add('    println("[FAIL] ", label, " -- ", reason)');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function t_skip!(ctx::TestContext, label::String, reason::String)');
  Lines.Add('    ctx.skip += 1');
  Lines.Add('    println("[SKIP] ", label, " -- ", reason)');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function run_sync_test!(ctx::TestContext, label::String, thunk::Function)');
  Lines.Add('    try');
  Lines.Add('        thunk()');
  Lines.Add('        t_pass!(ctx, label)');
  Lines.Add('    catch e');
  Lines.Add('        t_fail!(ctx, label, string(e))');
  Lines.Add('    end');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function run_async_test!(ctx::TestContext, label::String, launcher::Function)');
  Lines.Add('    done = Base.Event()');
  Lines.Add('    completed = Ref(false)');
  Lines.Add('    err_ref = Ref{Any}(nothing)');
  Lines.Add('    try');
  Lines.Add('        launcher(function (r, e)');
  Lines.Add('            completed[] = true');
  Lines.Add('            err_ref[] = e');
  Lines.Add('            Base.notify(done)');
  Lines.Add('            return nothing');
  Lines.Add('        end)');
  Lines.Add('    catch e');
  Lines.Add('        t_fail!(ctx, label, string(e))');
  Lines.Add('        return nothing');
  Lines.Add('    end');
  Lines.Add('    timer = Timer(5.0) do _');
  Lines.Add('        Base.notify(done)');
  Lines.Add('    end');
  Lines.Add('    try');
  Lines.Add('        wait(done)');
  Lines.Add('    finally');
  Lines.Add('        close(timer)');
  Lines.Add('    end');
  Lines.Add('    if !completed[]');
  Lines.Add('        t_fail!(ctx, label, "timeout")');
  Lines.Add('    elseif err_ref[] !== nothing');
  Lines.Add('        t_fail!(ctx, label, string(err_ref[]))');
  Lines.Add('    else');
  Lines.Add('        t_pass!(ctx, label)');
  Lines.Add('    end');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _wait_until(pred::Function, timeout_sec::Float64)::Bool');
  Lines.Add('    deadline = time() + timeout_sec');
  Lines.Add('    while time() < deadline');
  Lines.Add('        if pred()');
  Lines.Add('            return true');
  Lines.Add('        end');
  Lines.Add('        sleep(0.5)');
  Lines.Add('    end');
  Lines.Add('    return false');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitMakeArgs(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  Args: TP_String;
begin
  Lines.Add('function make_args_' + ApiName.Text + '_for_call()::Tuple');
  Args := '';
  for i := 0 to High(F.Params) do
  begin
    if i > 0 then
      Args := Args + ', ';
    Args := Args + ABI_Type_Julia_TestValue(F.Params[i].PascalType).Text;
  end;
  if Length(F.Params) = 0 then
    Lines.Add('    return ()')
  else
    Lines.Add('    return (' + Args + ',)');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitFunctionTestBlock(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const NsCall: TP_String);
begin
  Lines.Add('function test_' + ApiName.Text + '!(ctx::TestContext, service_uid::Union{Nothing, NTuple{32, UInt8}})');
  Lines.Add('    args = make_args_' + ApiName.Text + '_for_call()');
  Lines.Add('');
  Lines.Add('    run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(app sync)').Text + ', () -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '(args...)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    run_async_test!(ctx, ' + JuliaStrLit(ApiName + '(app async)').Text + ', (cb) -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_Async(args..., cb)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    run_async_test!(ctx, ' + JuliaStrLit(ApiName + '(app asyncSeq)').Text + ', (cb) -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_AsyncSequenced(args..., cb)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    if service_uid === nothing');
  Lines.Add('        t_skip!(ctx, ' + JuliaStrLit(ApiName + '(uid sync)').Text + ', "no service UID: service-initiated identity probe did not complete")');
  Lines.Add('        t_skip!(ctx, ' + JuliaStrLit(ApiName + '(uid async)').Text + ', "no service UID: service-initiated identity probe did not complete")');
  Lines.Add('        t_skip!(ctx, ' + JuliaStrLit(ApiName + '(uid asyncSeq)').Text + ', "no service UID: service-initiated identity probe did not complete")');
  Lines.Add('    else');
  Lines.Add('        run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(uid sync)').Text + ', () -> begin');
  Lines.Add('            ' + NsCall.Text + '.' + ApiName.Text + '_UID_Call(service_uid, args...)');
  Lines.Add('            return nothing');
  Lines.Add('        end)');
  Lines.Add('        run_async_test!(ctx, ' + JuliaStrLit(ApiName + '(uid async)').Text + ', (cb) -> begin');
  Lines.Add('            ' + NsCall.Text + '.' + ApiName.Text + '_UID_Async(service_uid, args..., cb)');
  Lines.Add('            return nothing');
  Lines.Add('        end)');
  Lines.Add('        run_async_test!(ctx, ' + JuliaStrLit(ApiName + '(uid asyncSeq)').Text + ', (cb) -> begin');
  Lines.Add('            ' + NsCall.Text + '.' + ApiName.Text + '_UID_AsyncSequenced(service_uid, args..., cb)');
  Lines.Add('            return nothing');
  Lines.Add('        end)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(p2pname sync)').Text + ', () -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_P2PName_Call(P2P_NAME, args...)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    run_async_test!(ctx, ' + JuliaStrLit(ApiName + '(p2pname async)').Text + ', (cb) -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_P2PName_Async(P2P_NAME, args..., cb)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    run_async_test!(ctx, ' + JuliaStrLit(ApiName + '(p2pname asyncSeq)').Text + ', (cb) -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_P2PName_AsyncSequenced(P2P_NAME, args..., cb)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitProcedureTestBlock(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const NsCall: TP_String);
begin
  Lines.Add('function test_' + ApiName.Text + '!(ctx::TestContext, service_uid::Union{Nothing, NTuple{32, UInt8}})');
  Lines.Add('    args = make_args_' + ApiName.Text + '_for_call()');
  Lines.Add('');
  Lines.Add('    run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(app notify)').Text + ', () -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '(args...)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(app seq notify)').Text + ', () -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_SequencedNotify(args...)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    if service_uid === nothing');
  Lines.Add('        t_skip!(ctx, ' + JuliaStrLit(ApiName + '(uid notify)').Text + ', "no service UID: service-initiated identity probe did not complete")');
  Lines.Add('        t_skip!(ctx, ' + JuliaStrLit(ApiName + '(uid seq notify)').Text + ', "no service UID: service-initiated identity probe did not complete")');
  Lines.Add('    else');
  Lines.Add('        run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(uid notify)').Text + ', () -> begin');
  Lines.Add('            ' + NsCall.Text + '.' + ApiName.Text + '_UID_Notify(service_uid, args...)');
  Lines.Add('            return nothing');
  Lines.Add('        end)');
  Lines.Add('        run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(uid seq notify)').Text + ', () -> begin');
  Lines.Add('            ' + NsCall.Text + '.' + ApiName.Text + '_UID_SequencedNotify(service_uid, args...)');
  Lines.Add('            return nothing');
  Lines.Add('        end)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(p2pname notify)').Text + ', () -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_P2PName_Notify(P2P_NAME, args...)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('');
  Lines.Add('    run_sync_test!(ctx, ' + JuliaStrLit(ApiName + '(p2pname seq notify)').Text + ', () -> begin');
  Lines.Add('        ' + NsCall.Text + '.' + ApiName.Text + '_P2PName_SequencedNotify(P2P_NAME, args...)');
  Lines.Add('        return nothing');
  Lines.Add('    end)');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitTestSummary(Lines: TPascalStringList; const CtxVar: TP_String);
begin
  Lines.Add('        println()');
  Lines.Add('        println("=== Summary ===")');
  Lines.Add('        println("Pass : ", ' + CtxVar.Text + '.pass)');
  Lines.Add('        println("Fail : ", ' + CtxVar.Text + '.fail)');
  Lines.Add('        println("Skip : ", ' + CtxVar.Text + '.skip)');
  Lines.Add('        println("Total: ", ' + CtxVar.Text + '.pass + ' + CtxVar.Text + '.fail + ' + CtxVar.Text + '.skip)');
  Lines.Add('');
  Lines.Add('        if exit_code != 1');
  Lines.Add('            exit_code = (' + CtxVar.Text + '.fail == 0) ? 0 : 2');
  Lines.Add('        end');
end;

procedure EmitFinallyBlock(Lines: TPascalStringList);
begin
  Lines.Add('    finally');
  Lines.Add('        try');
  Lines.Add('            LF.exit_main_thread()');
  Lines.Add('        catch e');
  Lines.Add('            println("[WARN] exit_main_thread: ", e)');
  Lines.Add('        end');
  Lines.Add('        if app !== nothing');
  Lines.Add('            try');
  Lines.Add('                LF.dispose!(app)');
  Lines.Add('            catch e');
  Lines.Add('                println("[WARN] dispose!(app): ", e)');
  Lines.Add('            end');
  Lines.Add('        end');
  Lines.Add('        try');
  Lines.Add('            LF.stop_callback_consumer()');
  Lines.Add('        catch e');
  Lines.Add('            println("[WARN] stop_callback_consumer: ", e)');
  Lines.Add('        end');
  Lines.Add('        try');
  Lines.Add('            LF.shutdown()');
  Lines.Add('        catch e');
  Lines.Add('            println("[WARN] shutdown: ", e)');
  Lines.Add('        end');
  Lines.Add('    end');
  Lines.Add('    return exit_code');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('exit_code = main()');
  Lines.Add('flush(stdout)');
  Lines.Add('flush(stderr)');
  Lines.Add('ccall(:_exit, Cvoid, (Cint,), Cint(exit_code))');
end;

procedure EmitCallFinallyBlock(Lines: TPascalStringList);
begin
  Lines.Add('    finally');
  Lines.Add('        try');
  Lines.Add('            LF.exit_main_thread()');
  Lines.Add('        catch e');
  Lines.Add('            println("[WARN] exit_main_thread: ", e)');
  Lines.Add('        end');
  Lines.Add('        if client_app !== nothing');
  Lines.Add('            try');
  Lines.Add('                LF.dispose!(client_app)');
  Lines.Add('            catch e');
  Lines.Add('                println("[WARN] dispose!(client_app): ", e)');
  Lines.Add('            end');
  Lines.Add('        end');
  Lines.Add('        try');
  Lines.Add('            LF.stop_callback_consumer()');
  Lines.Add('        catch e');
  Lines.Add('            println("[WARN] stop_callback_consumer: ", e)');
  Lines.Add('        end');
  Lines.Add('        try');
  Lines.Add('            LF.shutdown()');
  Lines.Add('        catch e');
  Lines.Add('            println("[WARN] shutdown: ", e)');
  Lines.Add('        end');
  Lines.Add('    end');
  Lines.Add('    return exit_code');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('exit_code = main()');
  Lines.Add('flush(stdout)');
  Lines.Add('flush(stderr)');
  Lines.Add('ccall(:_exit, Cvoid, (Cint,), Cint(exit_code))');
end;

function GenerateABIServiceTestJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsService, NsCall, AppName, P2PName: TP_String;
  ApiNames: TPascalStringList;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestJuliaCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestJuliaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsService := NormalizedUnit + '_abi_service';
  NsCall := NormalizedUnit + '_abi_call';
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
  begin
    Log('GenerateABIServiceTestJuliaCode: no supported routines');
    Exit;
  end;

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    AssignUniqueApiNames(SupportedFuncs, ApiNames);

    Lines.Add('if Threads.nthreads() < 2');
    Lines.Add('    error("This test requires --threads=2 (got $(Threads.nthreads())).")');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('import LingoFuse');
    Lines.Add('const LF = LingoFuse');
    Lines.Add('');
    Lines.Add('include(' + JuliaStrLit(NormalizedUnit + '_abi_service.jl') + ')');
    Lines.Add('include(' + JuliaStrLit(NormalizedUnit + '_abi_call.jl') + ')');
    Lines.Add('');
    Lines.Add('const APP_NAME = ' + JuliaStrLit(AppName));
    Lines.Add('const P2P_NAME = ' + JuliaStrLit(P2PName));
    Lines.Add('const IPC_ENDPOINT = "ipc:" * APP_NAME');
    Lines.Add('const P2P_WAIT_SECONDS = 30.0');
    Lines.Add('');

    EmitTestHarness(Lines);

    for i := 0 to High(SupportedFuncs) do
      EmitMakeArgs(Lines, ApiNames[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        EmitFunctionTestBlock(Lines, ApiNames[i], F, NsCall)
      else
        EmitProcedureTestBlock(Lines, ApiNames[i], F, NsCall);
    end;

    Lines.Add('function main()::Int');
    Lines.Add('    serve_only = "--serve-only" in ARGS');
    Lines.Add('    println("=== ' + NormalizedUnit.Text + '_abi service test ===")');
    Lines.Add('    println("Mode     : ", serve_only ? "serve-only" : "self-loop")');
    Lines.Add('    println("Endpoint : ", IPC_ENDPOINT)');
    Lines.Add('    println("AppName  : ", APP_NAME)');
    Lines.Add('    println("P2PName  : ", P2P_NAME)');
    Lines.Add('    println()');
    Lines.Add('');
    Lines.Add('    if !LF.shim_available()');
    Lines.Add('        println("[FATAL] LingoFuse C shim not found.")');
    Lines.Add('        return 1');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    try');
    Lines.Add('        LF.start_callback_consumer()');
    Lines.Add('    catch e');
    Lines.Add('        println("[FATAL] start_callback_consumer failed: ", e)');
    Lines.Add('        return 1');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    app = nothing');
    Lines.Add('    exit_code = 1');
    Lines.Add('    try');
    Lines.Add('        LF.set_option("Quiet", "True")');
    Lines.Add('        LF.set_option("ConsoleOutput", "True")');
    Lines.Add('        LF.set_option("Overlap_Connection", "True")');
    Lines.Add('        LF.reset_prepare()');
    Lines.Add('');
    Lines.Add('        rc_svc = LF.prepare_service(IPC_ENDPOINT, IPC_ENDPOINT)');
    Lines.Add('        if rc_svc == -1');
    Lines.Add('            println("[FATAL] prepare_service returned -1")');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        app = ' + NsService.Text + '.create_and_register_abi_app()');
    Lines.Add('        if app === nothing');
    Lines.Add('            println("[FATAL] create_and_register_abi_app returned nothing")');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        LF.set_option("LF_P2P_name", P2P_NAME)');
    Lines.Add('        ' + NsService.Text + '.register_all_p2p_abi_apis!()');
    Lines.Add('');
    Lines.Add('        rc_cli = LF.prepare_client(IPC_ENDPOINT, app)');
    Lines.Add('        if rc_cli == -1');
    Lines.Add('            println("[FATAL] prepare_client returned -1")');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        rc_done = LF.prepare_done()');
    Lines.Add('        if rc_done != 1');
    Lines.Add('            println("[FATAL] prepare_done returned ", rc_done)');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        if serve_only');
    Lines.Add('            println("[READY] service online. Press Ctrl+C to stop.")');
    Lines.Add('            flush(stdout)');
    Lines.Add('            try');
    Lines.Add('                while true');
    Lines.Add('                    sleep(1)');
    Lines.Add('                end');
    Lines.Add('            catch e');
    Lines.Add('            end');
    Lines.Add('            exit_code = 0');
    Lines.Add('        else');
    Lines.Add('            println("[READY] service + client self-loop online.")');
    Lines.Add('');
    Lines.Add('            println("[INFO] waiting for P2P name visibility (max ", P2P_WAIT_SECONDS, "s)...")');
    Lines.Add('            p2p_ready = _wait_until(() -> LF.LF_Check_P2PNAME(P2P_NAME) != 0, P2P_WAIT_SECONDS)');
    Lines.Add('            if !p2p_ready');
    Lines.Add('                println("[WARN] P2P name not visible; p2pname tests may fail.")');
    Lines.Add('            else');
    Lines.Add('                println("[INFO] P2P name visible.")');
    Lines.Add('            end');
    Lines.Add('');
    Lines.Add('            service_uid = nothing');
    Lines.Add('            println("[INFO] UID tests will be skipped in self-loop mode: local short-circuit bypasses the C shim event queue, so task_local_storage is not populated with sender identity. Use --serve-only plus the cross-process call test to exercise UID routing.")');
    Lines.Add('');
    Lines.Add('            ctx = TestContext()');
    Lines.Add('            try');
    for i := 0 to High(SupportedFuncs) do
      Lines.Add('                test_' + ApiNames[i].Text + '!(ctx, service_uid)');
    Lines.Add('            catch e');
    Lines.Add('                println("[FATAL] test loop threw: ", e)');
    Lines.Add('                ctx.fail += 1');
    Lines.Add('                exit_code = 1');
    Lines.Add('            end');
    Lines.Add('');
    EmitTestSummary(Lines, 'ctx');
    Lines.Add('        end');
    Lines.Add('    catch e');
    Lines.Add('        println("[FATAL] ", e)');
    Lines.Add('        exit_code = 1');
    EmitFinallyBlock(Lines);

    Result := Lines;
    Lines := nil;
    Log(PFormat('Generated %d lines, %d routines, self-loop + serve-only test for %s',
      [Result.Count, Length(SupportedFuncs), AppName.Text]));
  finally
    ApiNames.Free;
    if Lines <> nil then
      Lines.Free;
  end;
end;

function GenerateABICallTestJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsCall, AppName, P2PName, FirstApiName: TP_String;
  ApiNames: TPascalStringList;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestJuliaCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestJuliaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsCall := NormalizedUnit + '_abi_call';
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
  begin
    Log('GenerateABICallTestJuliaCode: no supported routines');
    Exit;
  end;

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    AssignUniqueApiNames(SupportedFuncs, ApiNames);
    FirstApiName := ApiNames[0];

    Lines.Add('if Threads.nthreads() < 2');
    Lines.Add('    error("This test requires --threads=2 (got $(Threads.nthreads())).")');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('import LingoFuse');
    Lines.Add('const LF = LingoFuse');
    Lines.Add('');
    Lines.Add('include(' + JuliaStrLit(NormalizedUnit + '_abi_call.jl') + ')');
    Lines.Add('');
    Lines.Add('const APP_NAME = ' + JuliaStrLit(AppName));
    Lines.Add('const P2P_NAME = ' + JuliaStrLit(P2PName));
    Lines.Add('const IPC_ENDPOINT = "ipc:" * APP_NAME');
    Lines.Add('const SERVICE_WAIT_SECONDS = 30.0');
    Lines.Add('const UID_PROBE_TIMEOUT_SECONDS = 10.0');
    Lines.Add('');

    EmitTestHarness(Lines);

    for i := 0 to High(SupportedFuncs) do
      EmitMakeArgs(Lines, ApiNames[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        EmitFunctionTestBlock(Lines, ApiNames[i], F, NsCall)
      else
        EmitProcedureTestBlock(Lines, ApiNames[i], F, NsCall);
    end;

    Lines.Add('function main()::Int');
    Lines.Add('    println("=== ' + NormalizedUnit.Text + '_abi call test (cross-process) ===")');
    Lines.Add('    println("Endpoint : ", IPC_ENDPOINT)');
    Lines.Add('    println("AppName  : ", APP_NAME)');
    Lines.Add('    println("P2PName  : ", P2P_NAME)');
    Lines.Add('    println()');
    Lines.Add('');
    Lines.Add('    if !LF.shim_available()');
    Lines.Add('        println("[FATAL] LingoFuse C shim not found.")');
    Lines.Add('        return 1');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    try');
    Lines.Add('        LF.start_callback_consumer()');
    Lines.Add('    catch e');
    Lines.Add('        println("[FATAL] start_callback_consumer failed: ", e)');
    Lines.Add('        return 1');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    client_app = nothing');
    Lines.Add('    got_service_uid = Ref{Union{Nothing, NTuple{32, UInt8}}}(nothing)');
    Lines.Add('    got_service_p2p = Ref{Union{Nothing, String}}(nothing)');
    Lines.Add('    exit_code = 1');
    Lines.Add('    try');
    Lines.Add('        LF.set_option("Quiet", "True")');
    Lines.Add('        LF.set_option("ConsoleOutput", "True")');
    Lines.Add('        LF.reset_prepare()');
    Lines.Add('');
    Lines.Add('        ' + NsCall.Text + '.ABI_TargetApp[] = APP_NAME');
    Lines.Add('        ' + NsCall.Text + '.ABI_Timeout[] = 5000');
    Lines.Add('');
    Lines.Add('        client_app = LF.App("LF_TEST_CLIENT_SELF", "client test app")');
    Lines.Add('        LF.register_call!(client_app, "LF_TEST_REPORT_SERVICE_IDENTITY", "",');
    Lines.Add('            function (in_bytes)');
    Lines.Add('                got_service_uid[] = LF.current_input_uid()');
    Lines.Add('                got_service_p2p[] = LF.current_input_p2p_name()');
    Lines.Add('                return in_bytes');
    Lines.Add('            end; warmup=false)');
    Lines.Add('');
    Lines.Add('        rc_cli = LF.prepare_client(IPC_ENDPOINT, client_app)');
    Lines.Add('        if rc_cli == -1');
    Lines.Add('            println("[FATAL] prepare_client returned -1 (is the service running?)")');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        rc_done = LF.prepare_done()');
    Lines.Add('        if rc_done != 1');
    Lines.Add('            println("[FATAL] prepare_done returned ", rc_done)');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        println("[INFO] waiting for service API visibility (max ", SERVICE_WAIT_SECONDS, "s)...")');
    Lines.Add('        ready = _wait_until(() -> LF.check_api(APP_NAME, ' + JuliaStrLit(FirstApiName) + '), SERVICE_WAIT_SECONDS)');
    Lines.Add('        if !ready');
    Lines.Add('            println("[FATAL] service API not visible after ", SERVICE_WAIT_SECONDS, "s")');
    Lines.Add('            return 1');
    Lines.Add('        end');
    Lines.Add('        println("[READY] service is online.")');
    Lines.Add('');
    Lines.Add('        println("[INFO] probing service UID via service-initiated call...")');
    Lines.Add('        try');
    Lines.Add('            LF.notify(LF.app_target(APP_NAME), "LF_TEST_ASK_SERVICE_CALL_ME", nothing)');
    Lines.Add('        catch e');
    Lines.Add('            println("[WARN] LF_TEST_ASK_SERVICE_CALL_ME notify failed: ", e)');
    Lines.Add('        end');
    Lines.Add('        probe_deadline = time() + UID_PROBE_TIMEOUT_SECONDS');
    Lines.Add('        while time() < probe_deadline && got_service_uid[] === nothing');
    Lines.Add('            sleep(0.1)');
    Lines.Add('        end');
    Lines.Add('        service_uid = got_service_uid[]');
    Lines.Add('        if service_uid === nothing');
    Lines.Add('            println("[WARN] service-initiated identity probe timed out; UID tests will be skipped.")');
    Lines.Add('        else');
    Lines.Add('            println("[INFO] service UID acquired.")');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        ctx = TestContext()');
    Lines.Add('        try');
    for i := 0 to High(SupportedFuncs) do
      Lines.Add('            test_' + ApiNames[i].Text + '!(ctx, service_uid)');
    Lines.Add('        catch e');
    Lines.Add('            println("[FATAL] test loop threw: ", e)');
    Lines.Add('            ctx.fail += 1');
    Lines.Add('            exit_code = 1');
    Lines.Add('        end');
    Lines.Add('');
    EmitTestSummary(Lines, 'ctx');
    Lines.Add('    catch e');
    Lines.Add('        println("[FATAL] ", e)');
    Lines.Add('        exit_code = 1');
    EmitCallFinallyBlock(Lines);

    Result := Lines;
    Lines := nil;
    Log(PFormat('Generated %d lines, %d routines, cross-process test for %s',
      [Result.Count, Length(SupportedFuncs), AppName.Text]));
  finally
    ApiNames.Free;
    if Lines <> nil then
      Lines.Free;
  end;
end;

initialization

  RegisterGenerator(
    'julia',
    'xxx_abi_service_test.jl',
    gkTest,
    'Julia ABI service self-loop + serve-only test',
    @GenerateABIServiceTestJuliaCode);

  RegisterGenerator(
    'julia',
    'xxx_abi_call_test.jl',
    gkTest,
    'Julia ABI call cross-process test',
    @GenerateABICallTestJuliaCode);

end.
