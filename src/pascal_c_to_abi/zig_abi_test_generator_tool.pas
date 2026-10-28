unit zig_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestZigCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestZigCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[zig_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[zig_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Zig_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'i32'
  else if T.Same('int64') then Result := 'i64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'u32'
  else if T.Same('word') then Result := 'u16'
  else if T.Same('smallint') then Result := 'i16'
  else if T.Same('byte') then Result := 'u8'
  else if T.Same('uint64') then Result := 'u64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'f64'
  else if T.Same('single') then Result := 'f32'
  else if IsStringABIType(T) then Result := '[]u8'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Zig_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsZigKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('addrspace') or S.Same('align') or S.Same('allowzero') or
    S.Same('and') or S.Same('anyframe') or S.Same('anytype') or
    S.Same('asm') or S.Same('async') or S.Same('await') or
    S.Same('break') or S.Same('callconv') or S.Same('catch') or
    S.Same('comptime') or S.Same('const') or S.Same('continue') or
    S.Same('defer') or S.Same('else') or S.Same('enum') or
    S.Same('errdefer') or S.Same('error') or S.Same('export') or
    S.Same('extern') or S.Same('fn') or S.Same('for') or
    S.Same('if') or S.Same('inline') or S.Same('noalias') or
    S.Same('noinline') or S.Same('nosuspend') or S.Same('opaque') or
    S.Same('or') or S.Same('orelse') or S.Same('packed') or
    S.Same('pub') or S.Same('resume') or S.Same('return') or
    S.Same('linksection') or S.Same('struct') or S.Same('suspend') or
    S.Same('switch') or S.Same('test') or S.Same('threadlocal') or
    S.Same('try') or S.Same('union') or S.Same('unreachable') or
    S.Same('usingnamespace') or S.Same('var') or S.Same('volatile') or
    S.Same('while');
end;

function ToSnakeCase(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  PrevWasUpper: boolean;
  Lowered: TP_Char;
begin
  Result := '';
  PrevWasUpper := False;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if (c >= 'A') and (c <= 'Z') then
    begin
      if (i > 1) and (not PrevWasUpper) and (Result.Len > 0)
         and (Result[Result.Len] <> '_') then
        Result.Append('_');
      Lowered := TP_Char(Ord(c) + 32);
      Result.Append(Lowered);
      PrevWasUpper := True;
    end
    else
    begin
      Result.Append(c);
      PrevWasUpper := False;
    end;
  end;
  if Result.Len = 0 then
    Result := 'anon';
  if IsZigKeyword(Result) then
    Result := Result + '_';
end;

const
  HexDigits: array[0..15] of AnsiChar = '0123456789ABCDEF';

function Hex2(v: integer): string;
begin
  Result := HexDigits[(v shr 4) and 15] + HexDigits[v and 15];
end;

function ZigStrLit(const S: TP_String): TP_String;
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
      Result.Append('\'); Result.Append('"');
    end
    else if c = '\' then
    begin
      Result.Append('\'); Result.Append('\');
    end
    else if c = #10 then
    begin
      Result.Append('\'); Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append('\'); Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append('\'); Result.Append('t');
    end
    else if (Ord(c) < 32) or (Ord(c) > 126) then
    begin
      Result.Append('\'); Result.Append('x'); Result.Append(Hex2(Ord(c) and 255));
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

function PlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := '"test"'
  else if ABIType.Same('integer') or ABIType.Same('longint') then
    Result := '@as(i32, 1)'
  else if ABIType.Same('int64') then
    Result := '@as(i64, 1)'
  else if ABIType.Same('cardinal') or ABIType.Same('dword') or ABIType.Same('longword') then
    Result := '@as(u32, 1)'
  else if ABIType.Same('word') then
    Result := '@as(u16, 1)'
  else if ABIType.Same('smallint') then
    Result := '@as(i16, 1)'
  else if ABIType.Same('byte') then
    Result := '@as(u8, 1)'
  else if ABIType.Same('uint64') then
    Result := '@as(u64, 1)'
  else if ABIType.Same('single') then
    Result := '@as(f32, 1.0)'
  else if ABIType.Same('double') or ABIType.Same('extended') or ABIType.Same('real') then
    Result := '@as(f64, 1.0)'
  else
    Result := '0';
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
    Result := Result + PlaceholderValue(Params[i].PascalType);
  end;
end;

function JoinComma(const A, B: TP_String): TP_String;
begin
  if A = '' then
    Result := B
  else if B = '' then
    Result := A
  else
    Result := A + ', ' + B;
end;

function GenerateABIServiceTestZigCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, P2PName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceTestZigCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceTestZigCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  Log(PFormat('Generating Zig ABI service test for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('const std = @import("std");');
    Lines.Add('const lf = @import("lingofuse");');
    Lines.Add('const data = lf.DataHandle;');
    Lines.Add('');
    Lines.Add('const svc = @import("' + NormalizedUnit + '_abi_service");');
    Lines.Add('');
    Lines.Add('extern "c" fn Sleep(ms: u32) void;');
    Lines.Add('extern "c" fn exit(code: c_int) noreturn;');
    Lines.Add('');
    Lines.Add('const TEST_ENDPOINT: [:0]const u8 = ' + ZigStrLit('ipc:' + AppName) + ';');
    Lines.Add('const TEST_APP_NAME: [:0]const u8 = ' + ZigStrLit(AppName) + ';');
    Lines.Add('const TEST_P2P_NAME: [:0]const u8 = ' + ZigStrLit(P2PName) + ';');
    Lines.Add('const TEST_WHOAMI_API: [:0]const u8 = "LF_TEST_WHOAMI";');
    Lines.Add('const TEST_ASK_CALL_ME_API: [:0]const u8 = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('const TEST_REPORT_IDENTITY_API: [:0]const u8 = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('const TEST_AUTO_EXIT_SECONDS: u32 = 120;');
    Lines.Add('');
    Lines.Add('const STATUS_OK: u8 = 0x00;');
    Lines.Add('const STATUS_ERROR: u8 = 0xFF;');
    Lines.Add('');
    Lines.Add('fn cbWhoami(_ctx: ?*anyopaque, in_: *lf.DataHandle, out_: *lf.DataHandle) lf.Error!void {');
    Lines.Add('    _ = _ctx;');
    Lines.Add('    const uid = in_.p2pUid() catch lf.Uid.NULL;');
    Lines.Add('    const alloc = std.heap.page_allocator;');
    Lines.Add('    const p2p_z = in_.p2pName(alloc) catch |e| return e;');
    Lines.Add('    defer alloc.free(p2p_z);');
    Lines.Add('');
    Lines.Add('    std.debug.print("[SERVICE] whoami: p2p={s}\\n", .{p2p_z});');
    Lines.Add('');
    Lines.Add('    try out_.writeBytes(&[_]u8{STATUS_OK});');
    Lines.Add('    const uid_bytes = uid.toBytes();');
    Lines.Add('    try out_.writeBytes(&uid_bytes);');
    Lines.Add('    try out_.writeString(p2p_z);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn cbAskCallMe(_ctx: ?*anyopaque, in_: *lf.DataHandle) lf.Error!void {');
    Lines.Add('    _ = _ctx;');
    Lines.Add('    const uid = in_.p2pUid() catch {');
    Lines.Add('        std.debug.print("[SERVICE] ask_call_me: no uid\\n", .{});');
    Lines.Add('        return;');
    Lines.Add('    };');
    Lines.Add('    if (uid.isNull()) {');
    Lines.Add('        std.debug.print("[SERVICE] ask_call_me: null uid\\n", .{});');
    Lines.Add('        return;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std.debug.print("[SERVICE] ask_call_me: invoking client via uid\\n", .{});');
    Lines.Add('');
    Lines.Add('    var req = try data.create(TEST_REPORT_IDENTITY_API);');
    Lines.Add('    defer req.deinit();');
    Lines.Add('    try req.writeString("service initiates call");');
    Lines.Add('');
    Lines.Add('    const resp_opt = lf.framework.callOptionalByUid(uid, &req, 5000) catch {');
    Lines.Add('        std.debug.print("[SERVICE] ask_call_me: call failed\\n", .{});');
    Lines.Add('        return;');
    Lines.Add('    };');
    Lines.Add('    if (resp_opt) |resp_in| {');
    Lines.Add('        var resp = resp_in;');
    Lines.Add('        defer resp.deinit();');
    Lines.Add('        std.debug.print("[SERVICE] ask_call_me: client responded\\n", .{});');
    Lines.Add('    } else {');
    Lines.Add('        std.debug.print("[SERVICE] ask_call_me: no response (timeout)\\n", .{});');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('pub fn main() void {');
    Lines.Add('    std.debug.print("=== ' + UnitName.Text + ' ABI service test ===\\n", .{});');
    Lines.Add('');
    Lines.Add('    lf.framework.init() catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] init: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('    defer lf.framework.deinit();');
    Lines.Add('');
    Lines.Add('    lf.options.setQuiet(true) catch {};');
    Lines.Add('    lf.options.setConsoleOutput(true) catch {};');
    Lines.Add('    lf.options.setOverlapConnection(true) catch {};');
    Lines.Add('    lf.options.setWaitConnectionReadyOk(false) catch {};');
    Lines.Add('    lf.options.setWaitConnectionTimeout(10000) catch {};');
    Lines.Add('    lf.options.setP2PName(TEST_P2P_NAME) catch {};');
    Lines.Add('');
    Lines.Add('    lf.framework.resetPrepare();');
    Lines.Add('');
    Lines.Add('    _ = lf.framework.prepareService(TEST_ENDPOINT, TEST_ENDPOINT) catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] prepareService: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    var app = lf.AppHandle.create(TEST_APP_NAME, TEST_APP_NAME) catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] createApp: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    svc.registerAllAbiApis(&app) catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] registerAllAbiApis: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('    app.registerCall(TEST_WHOAMI_API, "service whoami", null, cbWhoami) catch {};');
    Lines.Add('    app.registerNotify(TEST_ASK_CALL_ME_API, "ask service to call client", null, cbAskCallMe) catch {};');
    Lines.Add('');
    Lines.Add('    svc.registerAllP2pAbiApis() catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] registerAllP2pAbiApis: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('    lf.p2p.registerP2PCall(TEST_WHOAMI_API, "service whoami", null, cbWhoami) catch {};');
    Lines.Add('    lf.p2p.registerP2PNotify(TEST_ASK_CALL_ME_API, "ask service to call client", null, cbAskCallMe) catch {};');
    Lines.Add('');
    Lines.Add('    _ = lf.framework.prepareClient(TEST_ENDPOINT, &app) catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] prepareClient: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    if (!lf.framework.prepareDone()) {');
    Lines.Add('        std.debug.print("[FATAL] prepareDone returned false\\n", .{});');
    Lines.Add('        exit(1);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    var i: usize = 0;');
    Lines.Add('    var ready: bool = false;');
    Lines.Add('    while (i < 50) : (i += 1) {');
    Lines.Add('        if (lf.framework.checkApi(TEST_APP_NAME, TEST_WHOAMI_API)) {');
    Lines.Add('            ready = true;');
    Lines.Add('            break;');
    Lines.Add('        }');
    Lines.Add('        Sleep(200);');
    Lines.Add('    }');
    Lines.Add('    if (!ready) {');
    Lines.Add('        std.debug.print("[WARN] whoami not visible within 10s\\n", .{});');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std.debug.print("[OK] Service ready on {s}\\n", .{TEST_ENDPOINT});');
    Lines.Add('    std.debug.print("[OK] App: {s}\\n", .{TEST_APP_NAME});');
    Lines.Add('    std.debug.print("[OK] P2P: {s}\\n", .{TEST_P2P_NAME});');
    Lines.Add('    std.debug.print("[OK] Auto-exit after {} seconds (Ctrl+C to exit sooner)\\n", .{TEST_AUTO_EXIT_SECONDS});');
    Lines.Add('');
    Lines.Add('    var elapsed: u32 = 0;');
    Lines.Add('    while (elapsed < TEST_AUTO_EXIT_SECONDS) : (elapsed += 1) {');
    Lines.Add('        Sleep(1000);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std.debug.print("[OK] Shutting down...\\n", .{});');
    Lines.Add('    lf.framework.exitMainThread();');
    Lines.Add('    app.deinit();');
    Lines.Add('    lf.framework.shutdown();');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Zig service test', [Lines.Count]));
  finally
  end;
end;

procedure EmitCallTestWaiter(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String;
  const F: TFunctionStructure);
begin
  Lines.Add('const ' + ZigIdent + 'Waiter = struct {');
  Lines.Add('    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),');
  Lines.Add('    ok: bool = false,');
  Lines.Add('    alloc: std.mem.Allocator,');
  Lines.Add('');
  Lines.Add('    fn onResult(ctx: ?*anyopaque, r: call.' + ApiName + 'Result) void {');
  Lines.Add('        const self: *@This() = @ptrCast(@alignCast(ctx orelse return));');
  Lines.Add('        switch (r) {');
  Lines.Add('            .ok => |v| {');
  if IsStringABIType(F.ReturnType) then
  begin
    Lines.Add('                defer self.alloc.free(v);');
    Lines.Add('                reportString(' + ZigStrLit(ApiName + '(async)') + ', v);');
  end
  else
  begin
    Lines.Add('                var buf: [64]u8 = undefined;');
    Lines.Add('                const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "";');
    Lines.Add('                reportPass(' + ZigStrLit(ApiName + '(async)') + ', s);');
  end;
  Lines.Add('                self.ok = true;');
  Lines.Add('            },');
  Lines.Add('            .err => |e| {');
  Lines.Add('                reportFail(' + ZigStrLit(ApiName + '(async)') + ', @errorName(e));');
  Lines.Add('                self.ok = false;');
  Lines.Add('            },');
  Lines.Add('        }');
  Lines.Add('        self.done.store(true, .release);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    fn wait(self: *@This(), timeout_ms: u64) bool {');
  Lines.Add('        const start = nowMs();');
  Lines.Add('        while (nowMs() - start < timeout_ms) {');
  Lines.Add('            if (self.done.load(.acquire)) return true;');
  Lines.Add('            sleepMs(1);');
  Lines.Add('        }');
  Lines.Add('        return self.done.load(.acquire);');
  Lines.Add('    }');
  Lines.Add('};');
  Lines.Add('');
end;

procedure EmitSyncCallBlock(Lines: TPascalStringList;
  const Label_, CallExpr: TP_String;
  const F: TFunctionStructure);
begin
  if IsStringABIType(F.ReturnType) then
  begin
    Lines.Add('    {');
    Lines.Add('        if (' + CallExpr + ') |result| {');
    Lines.Add('            defer alloc.free(result);');
    Lines.Add('            reportString(' + ZigStrLit(Label_) + ', result);');
    Lines.Add('        } else |err| {');
    Lines.Add('            reportFail(' + ZigStrLit(Label_) + ', @errorName(err));');
    Lines.Add('        }');
    Lines.Add('    }');
  end
  else
  begin
    Lines.Add('    {');
    Lines.Add('        if (' + CallExpr + ') |result| {');
    Lines.Add('            var buf: [64]u8 = undefined;');
    Lines.Add('            const s = std.fmt.bufPrint(&buf, "{d}", .{result}) catch "";');
    Lines.Add('            reportPass(' + ZigStrLit(Label_) + ', s);');
    Lines.Add('        } else |err| {');
    Lines.Add('            reportFail(' + ZigStrLit(Label_) + ', @errorName(err));');
    Lines.Add('        }');
    Lines.Add('    }');
  end;
end;

procedure EmitSkipBlock(Lines: TPascalStringList;
  const Label_, CallExpr: TP_String;
  const F: TFunctionStructure;
  const SkipLabel: TP_String);
begin
  Lines.Add('    if (g_has_service_uid.load(.acquire)) {');
  if IsStringABIType(F.ReturnType) then
  begin
    Lines.Add('        if (' + CallExpr + ') |result| {');
    Lines.Add('            defer alloc.free(result);');
    Lines.Add('            reportString(' + ZigStrLit(Label_) + ', result);');
    Lines.Add('        } else |err| {');
    Lines.Add('            reportFail(' + ZigStrLit(Label_) + ', @errorName(err));');
    Lines.Add('        }');
  end
  else
  begin
    Lines.Add('        if (' + CallExpr + ') |result| {');
    Lines.Add('            var buf: [64]u8 = undefined;');
    Lines.Add('            const s = std.fmt.bufPrint(&buf, "{d}", .{result}) catch "";');
    Lines.Add('            reportPass(' + ZigStrLit(Label_) + ', s);');
    Lines.Add('        } else |err| {');
    Lines.Add('            reportFail(' + ZigStrLit(Label_) + ', @errorName(err));');
    Lines.Add('        }');
  end;
  Lines.Add('    } else {');
  Lines.Add('        reportSkip(' + ZigStrLit(SkipLabel) + ', "no service uid");');
  Lines.Add('    }');
end;

procedure EmitAsyncTestBlock(Lines: TPascalStringList;
  const Label_, CallExpr, ZigIdent: TP_String);
begin
  Lines.Add('    {');
  Lines.Add('        var w = ' + ZigIdent + 'Waiter{ .alloc = alloc };');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            if (!w.wait(5000)) {');
  Lines.Add('                reportFail(' + ZigStrLit(Label_) + ', "timeout");');
  Lines.Add('            }');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(Label_) + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    }');
end;

procedure EmitAsyncUidBlock(Lines: TPascalStringList;
  const Label_, CallExpr, ZigIdent, SkipLabel: TP_String);
begin
  Lines.Add('    if (g_has_service_uid.load(.acquire)) {');
  Lines.Add('        var w = ' + ZigIdent + 'Waiter{ .alloc = alloc };');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            if (!w.wait(5000)) {');
  Lines.Add('                reportFail(' + ZigStrLit(Label_) + ', "timeout");');
  Lines.Add('            }');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(Label_) + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    } else {');
  Lines.Add('        reportSkip(' + ZigStrLit(SkipLabel) + ', "no service uid");');
  Lines.Add('    }');
end;

procedure EmitCallTestFunction(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String;
  const F: TFunctionStructure);
var
  Args, FullArgs, CallExpr: TP_String;
  HasAlloc: boolean;
begin
  Args := BuildPlaceholderArgs(F.Params);
  HasAlloc := IsStringABIType(F.ReturnType);

  EmitCallTestWaiter(Lines, ApiName, ZigIdent, F);

  Lines.Add('fn test_' + ZigIdent + '() void {');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('');

  if HasAlloc then
    FullArgs := JoinComma('alloc', Args)
  else
    FullArgs := Args;

  CallExpr := 'call.' + ZigIdent + '(' + FullArgs + ')';
  EmitSyncCallBlock(Lines, ApiName + '(app call)', CallExpr, F);
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_async(' + JoinComma(FullArgs, '&w, ' + ZigIdent + 'Waiter.onResult') + ')';
  EmitAsyncTestBlock(Lines, ApiName + '(app async)', CallExpr, ZigIdent);
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_async_sequenced(' + JoinComma(FullArgs, '&w, ' + ZigIdent + 'Waiter.onResult') + ')';
  EmitAsyncTestBlock(Lines, ApiName + '(app asyncSeq)', CallExpr, ZigIdent);
  Lines.Add('');

  if HasAlloc then
    CallExpr := 'call.' + ZigIdent + '_uid(' + JoinComma(JoinComma('alloc', 'g_service_uid'), Args) + ')'
  else
    CallExpr := 'call.' + ZigIdent + '_uid(' + JoinComma('g_service_uid', Args) + ')';
  EmitSkipBlock(Lines, ApiName + '(uid call)', CallExpr, F, ApiName + '(uid call)');
  Lines.Add('');

  if HasAlloc then
    CallExpr := 'call.' + ZigIdent + '_uid_async(' + JoinComma(JoinComma('alloc', 'g_service_uid'), JoinComma(Args, '&w, ' + ZigIdent + 'Waiter.onResult')) + ')'
  else
    CallExpr := 'call.' + ZigIdent + '_uid_async(' + JoinComma(JoinComma('g_service_uid', Args), '&w, ' + ZigIdent + 'Waiter.onResult') + ')';
  EmitAsyncUidBlock(Lines, ApiName + '(uid async)', CallExpr, ZigIdent, ApiName + '(uid async)');
  Lines.Add('');

  if HasAlloc then
    CallExpr := 'call.' + ZigIdent + '_uid_async_sequenced(' + JoinComma(JoinComma('alloc', 'g_service_uid'), JoinComma(Args, '&w, ' + ZigIdent + 'Waiter.onResult')) + ')'
  else
    CallExpr := 'call.' + ZigIdent + '_uid_async_sequenced(' + JoinComma(JoinComma('g_service_uid', Args), '&w, ' + ZigIdent + 'Waiter.onResult') + ')';
  EmitAsyncUidBlock(Lines, ApiName + '(uid asyncSeq)', CallExpr, ZigIdent, ApiName + '(uid asyncSeq)');
  Lines.Add('');

  if HasAlloc then
    CallExpr := 'call.' + ZigIdent + '_p2p_name(' + JoinComma(JoinComma('alloc', 'TEST_P2P_NAME'), Args) + ')'
  else
    CallExpr := 'call.' + ZigIdent + '_p2p_name(' + JoinComma('TEST_P2P_NAME', Args) + ')';
  EmitSyncCallBlock(Lines, ApiName + '(p2pname call)', CallExpr, F);
  Lines.Add('');

  if HasAlloc then
    CallExpr := 'call.' + ZigIdent + '_p2p_name_async(' + JoinComma(JoinComma('alloc', 'TEST_P2P_NAME'), JoinComma(Args, '&w, ' + ZigIdent + 'Waiter.onResult')) + ')'
  else
    CallExpr := 'call.' + ZigIdent + '_p2p_name_async(' + JoinComma(JoinComma('TEST_P2P_NAME', Args), '&w, ' + ZigIdent + 'Waiter.onResult') + ')';
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname async)', CallExpr, ZigIdent);
  Lines.Add('');

  if HasAlloc then
    CallExpr := 'call.' + ZigIdent + '_p2p_name_async_sequenced(' + JoinComma(JoinComma('alloc', 'TEST_P2P_NAME'), JoinComma(Args, '&w, ' + ZigIdent + 'Waiter.onResult')) + ')'
  else
    CallExpr := 'call.' + ZigIdent + '_p2p_name_async_sequenced(' + JoinComma(JoinComma('TEST_P2P_NAME', Args), '&w, ' + ZigIdent + 'Waiter.onResult') + ')';
  EmitAsyncTestBlock(Lines, ApiName + '(p2pname asyncSeq)', CallExpr, ZigIdent);
  Lines.Add('');

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallTestProcedure(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String;
  const F: TFunctionStructure);
var
  Args, CallExpr: TP_String;
begin
  Args := BuildPlaceholderArgs(F.Params);

  Lines.Add('fn test_' + ZigIdent + '() void {');
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '(' + Args + ')';
  Lines.Add('    {');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            reportPass(' + ZigStrLit(ApiName + '(app notify)') + ', null);');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(ApiName + '(app notify)') + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_sequenced_notify(' + Args + ')';
  Lines.Add('    {');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            reportPass(' + ZigStrLit(ApiName + '(app seq notify)') + ', null);');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(ApiName + '(app seq notify)') + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_uid_notify(' + JoinComma('g_service_uid', Args) + ')';
  Lines.Add('    if (g_has_service_uid.load(.acquire)) {');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            reportPass(' + ZigStrLit(ApiName + '(uid notify)') + ', null);');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(ApiName + '(uid notify)') + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    } else {');
  Lines.Add('        reportSkip(' + ZigStrLit(ApiName + '(uid notify)') + ', "no service uid");');
  Lines.Add('    }');
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_uid_sequenced_notify(' + JoinComma('g_service_uid', Args) + ')';
  Lines.Add('    if (g_has_service_uid.load(.acquire)) {');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            reportPass(' + ZigStrLit(ApiName + '(uid seq notify)') + ', null);');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(ApiName + '(uid seq notify)') + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    } else {');
  Lines.Add('        reportSkip(' + ZigStrLit(ApiName + '(uid seq notify)') + ', "no service uid");');
  Lines.Add('    }');
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_p2p_name_notify(' + JoinComma('TEST_P2P_NAME', Args) + ')';
  Lines.Add('    {');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            reportPass(' + ZigStrLit(ApiName + '(p2pname notify)') + ', null);');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(ApiName + '(p2pname notify)') + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');

  CallExpr := 'call.' + ZigIdent + '_p2p_name_sequenced_notify(' + JoinComma('TEST_P2P_NAME', Args) + ')';
  Lines.Add('    {');
  Lines.Add('        if (' + CallExpr + ') |_| {');
  Lines.Add('            reportPass(' + ZigStrLit(ApiName + '(p2pname seq notify)') + ', null);');
  Lines.Add('        } else |err| {');
  Lines.Add('            reportFail(' + ZigStrLit(ApiName + '(p2pname seq notify)') + ', @errorName(err));');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallTestZigCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, P2PName, ClientP2PName: TP_String;
  ApiNames, ZigIdents: TPascalStringList;
  ApiName, ZigIdent: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallTestZigCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallTestZigCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';
  ClientP2PName := NormalizedUnit + '_client_test_p2p';

  Log(PFormat('Generating Zig ABI call test for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call test exercises %d ABI APIs', [Length(SupportedFuncs)]));

  ApiNames := TPascalStringList.Create;
  ZigIdents := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if ApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while ApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      ApiNames.Add(ApiName);

      ZigIdent := ToSnakeCase(ApiName);
      if ZigIdents.IndexOf(ZigIdent) >= 0 then
      begin
        j := 1;
        while ZigIdents.IndexOf(ZigIdent + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ZigIdent := ZigIdent + '_' + umlIntToStr(j).Text;
      end;
      ZigIdents.Add(ZigIdent);
    end;

    Lines.Add('const std = @import("std");');
    Lines.Add('const lf = @import("lingofuse");');
    Lines.Add('const data = lf.DataHandle;');
    Lines.Add('const call = @import("' + NormalizedUnit + '_abi_call");');
    Lines.Add('');
    Lines.Add('extern "c" fn Sleep(ms: u32) void;');
    Lines.Add('extern "c" fn GetTickCount64() u64;');
    Lines.Add('extern "c" fn exit(code: c_int) noreturn;');
    Lines.Add('');
    Lines.Add('fn nowMs() u64 { return GetTickCount64(); }');
    Lines.Add('fn sleepMs(ms: u32) void { Sleep(ms); }');
    Lines.Add('');
    Lines.Add('const TEST_ENDPOINT: [:0]const u8 = ' + ZigStrLit('ipc:' + AppName) + ';');
    Lines.Add('const TEST_APP_NAME: [:0]const u8 = ' + ZigStrLit(AppName) + ';');
    Lines.Add('const TEST_P2P_NAME: [:0]const u8 = ' + ZigStrLit(P2PName) + ';');
    Lines.Add('const CLIENT_APP_NAME: [:0]const u8 = "LF_TEST_CLIENT_SELF";');
    Lines.Add('const CLIENT_P2P_NAME: [:0]const u8 = ' + ZigStrLit(ClientP2PName) + ';');
    Lines.Add('const TEST_WHOAMI_API: [:0]const u8 = "LF_TEST_WHOAMI";');
    Lines.Add('const TEST_ASK_CALL_ME_API: [:0]const u8 = "LF_TEST_ASK_SERVICE_CALL_ME";');
    Lines.Add('const TEST_REPORT_IDENTITY_API: [:0]const u8 = "LF_TEST_REPORT_SERVICE_IDENTITY";');
    Lines.Add('');
    Lines.Add('const STATUS_OK: u8 = 0x00;');
    Lines.Add('const STATUS_ERROR: u8 = 0xFF;');
    Lines.Add('');
    Lines.Add('var g_pass: usize = 0;');
    Lines.Add('var g_fail: usize = 0;');
    Lines.Add('var g_skip: usize = 0;');
    Lines.Add('var g_service_uid: lf.Uid = lf.Uid.NULL;');
    Lines.Add('var g_has_service_uid: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);');
    Lines.Add('var g_service_called_me: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);');
    Lines.Add('');
    Lines.Add('fn reportPass(label: []const u8, value: ?[]const u8) void {');
    Lines.Add('    g_pass += 1;');
    Lines.Add('    if (value) |v| {');
    Lines.Add('        std.debug.print("[PASS] {s} = {s}\\n", .{label, v});');
    Lines.Add('    } else {');
    Lines.Add('        std.debug.print("[PASS] {s}\\n", .{label});');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn reportString(label: []const u8, value: []const u8) void {');
    Lines.Add('    g_pass += 1;');
    Lines.Add('    std.debug.print("[PASS] {s} = {s}\\n", .{label, value});');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn reportFail(label: []const u8, reason: []const u8) void {');
    Lines.Add('    g_fail += 1;');
    Lines.Add('    std.debug.print("[FAIL] {s} -- {s}\\n", .{label, reason});');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn reportSkip(label: []const u8, reason: []const u8) void {');
    Lines.Add('    g_skip += 1;');
    Lines.Add('    std.debug.print("[SKIP] {s} -- {s}\\n", .{label, reason});');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn cbReportIdentity(_ctx: ?*anyopaque, in_: *lf.DataHandle, out_: *lf.DataHandle) lf.Error!void {');
    Lines.Add('    _ = _ctx;');
    Lines.Add('    const uid = in_.p2pUid() catch lf.Uid.NULL;');
    Lines.Add('    const alloc = std.heap.page_allocator;');
    Lines.Add('    const p2p_z = in_.p2pName(alloc) catch |e| return e;');
    Lines.Add('    defer alloc.free(p2p_z);');
    Lines.Add('');
    Lines.Add('    g_service_uid = uid;');
    Lines.Add('    g_has_service_uid.store(!uid.isNull(), .release);');
    Lines.Add('    g_service_called_me.store(true, .release);');
    Lines.Add('');
    Lines.Add('    std.debug.print("[CLIENT] service called me: p2p={s}\\n", .{p2p_z});');
    Lines.Add('');
    Lines.Add('    try out_.writeBytes(&[_]u8{STATUS_OK});');
    Lines.Add('    try out_.writeString("identity received");');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn probeClientIdentity(out_uid: *lf.Uid, out_p2p: *[]u8) !void {');
    Lines.Add('    const alloc = std.heap.page_allocator;');
    Lines.Add('    var req = try data.create(TEST_WHOAMI_API);');
    Lines.Add('    defer req.deinit();');
    Lines.Add('');
    Lines.Add('    var resp = (try lf.framework.callOptional(TEST_APP_NAME, &req, 5000)) orelse return error.CallFailed;');
    Lines.Add('    defer resp.deinit();');
    Lines.Add('');
    Lines.Add('    try resp.setPosition(0);');
    Lines.Add('    var status: u8 = 0;');
    Lines.Add('    if (!try resp.read(&status)) return error.ReadFailed;');
    Lines.Add('    if (status != 0x00) return error.CallFailed;');
    Lines.Add('');
    Lines.Add('    var uid_bytes: [32]u8 = undefined;');
    Lines.Add('    const got = try resp.readBytes(&uid_bytes);');
    Lines.Add('    if (got != 32) return error.ReadFailed;');
    Lines.Add('    out_uid.* = lf.Uid.fromBytes(uid_bytes);');
    Lines.Add('    out_p2p.* = try lf.io.readString(&resp, alloc);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('fn waitServiceUid(timeout_ms: u64) bool {');
    Lines.Add('    g_service_called_me.store(false, .release);');
    Lines.Add('    g_has_service_uid.store(false, .release);');
    Lines.Add('');
    Lines.Add('    var req = data.create(TEST_ASK_CALL_ME_API) catch return false;');
    Lines.Add('    defer req.deinit();');
    Lines.Add('');
    Lines.Add('    lf.framework.notify(TEST_APP_NAME, &req) catch return false;');
    Lines.Add('');
    Lines.Add('    const start = nowMs();');
    Lines.Add('    while (nowMs() - start < timeout_ms) {');
    Lines.Add('        if (g_service_called_me.load(.acquire) and g_has_service_uid.load(.acquire)) return true;');
    Lines.Add('        sleepMs(10);');
    Lines.Add('    }');
    Lines.Add('    return false;');
    Lines.Add('}');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ZigIdent := ZigIdents[i];
      if F.IsFunction then
        EmitCallTestFunction(Lines, ApiName, ZigIdent, F)
      else
        EmitCallTestProcedure(Lines, ApiName, ZigIdent, F);
    end;

    Lines.Add('fn run() !void {');
    Lines.Add('    try lf.options.setQuiet(true);');
    Lines.Add('    try lf.options.setConsoleOutput(true);');
    Lines.Add('    try lf.options.setOverlapConnection(true);');
    Lines.Add('    try lf.options.setWaitConnectionReadyOk(true);');
    Lines.Add('    try lf.options.setWaitConnectionTimeout(15000);');
    Lines.Add('    try lf.options.setP2PName(CLIENT_P2P_NAME);');
    Lines.Add('');
    Lines.Add('    lf.framework.resetPrepare();');
    Lines.Add('');
    Lines.Add('    var app = try lf.AppHandle.create(CLIENT_APP_NAME, "client test app");');
    Lines.Add('    errdefer app.deinit();');
    Lines.Add('    try app.registerCall(TEST_REPORT_IDENTITY_API, "report identity", null, cbReportIdentity);');
    Lines.Add('');
    Lines.Add('    _ = try lf.framework.prepareClient(TEST_ENDPOINT, &app);');
    Lines.Add('');
    Lines.Add('    if (!lf.framework.prepareDone()) {');
    Lines.Add('        std.debug.print("[FATAL] prepareDone returned false\\n", .{});');
    Lines.Add('        return error.PrepareFailed;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    var i: usize = 0;');
    Lines.Add('    var ready: bool = false;');
    Lines.Add('    while (i < 50) : (i += 1) {');
    Lines.Add('        if (lf.framework.checkApi(TEST_APP_NAME, TEST_WHOAMI_API)) {');
    Lines.Add('            ready = true;');
    Lines.Add('            break;');
    Lines.Add('        }');
    Lines.Add('        sleepMs(200);');
    Lines.Add('    }');
    Lines.Add('    if (!ready) {');
    Lines.Add('        std.debug.print("[WARN] service_test not visible after 10s\\n", .{});');
    Lines.Add('        std.debug.print("[WARN] start service_test first, then run this program\\n", .{});');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    std.debug.print("[READY] Client online\\n", .{});');
    Lines.Add('');
    Lines.Add('    const alloc = std.heap.page_allocator;');
    Lines.Add('    var my_uid: lf.Uid = lf.Uid.NULL;');
    Lines.Add('    var my_p2p: []u8 = try alloc.alloc(u8, 0);');
    Lines.Add('    defer alloc.free(my_p2p);');
    Lines.Add('    if (probeClientIdentity(&my_uid, &my_p2p)) |_| {');
    Lines.Add('        var hex: [64]u8 = undefined;');
    Lines.Add('        my_uid.toHexBuf(&hex);');
    Lines.Add('        std.debug.print("[INFO] client uid = {s}\\n", .{&hex});');
    Lines.Add('        std.debug.print("[INFO] client p2p = {s}\\n", .{my_p2p});');
    Lines.Add('    } else |err| {');
    Lines.Add('        std.debug.print("[WARN] whoami failed: {} -- uid tests will be skipped\\n", .{err});');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (waitServiceUid(10000)) {');
    Lines.Add('        var svc_hex: [64]u8 = undefined;');
    Lines.Add('        g_service_uid.toHexBuf(&svc_hex);');
    Lines.Add('        std.debug.print("[INFO] service uid = {s}\\n", .{&svc_hex});');
    Lines.Add('    } else {');
    Lines.Add('        std.debug.print("[WARN] service-initiated call timed out\\n", .{});');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    const overall_start = nowMs();');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      Lines.Add('    test_' + ZigIdents[i] + '();');

    Lines.Add('');
    Lines.Add('    const elapsed = nowMs() - overall_start;');
    Lines.Add('');
    Lines.Add('    std.debug.print("\\n=== Summary ===\\n", .{});');
    Lines.Add('    std.debug.print("Pass: {d}\\n", .{g_pass});');
    Lines.Add('    std.debug.print("Fail: {d}\\n", .{g_fail});');
    Lines.Add('    std.debug.print("Skip: {d}\\n", .{g_skip});');
    Lines.Add('    std.debug.print("Elapsed: {d} ms\\n", .{elapsed});');
    Lines.Add('');
    Lines.Add('    lf.framework.exitMainThread();');
    Lines.Add('    app.deinit();');
    Lines.Add('    lf.framework.shutdown();');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('pub fn main() void {');
    Lines.Add('    std.debug.print("=== ' + UnitName.Text + ' ABI client test ===\\n", .{});');
    Lines.Add('');
    Lines.Add('    lf.framework.init() catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] init: {}\\n", .{err});');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('    defer lf.framework.deinit();');
    Lines.Add('');
    Lines.Add('    run() catch |err| {');
    Lines.Add('        std.debug.print("[FATAL] run: {}\\n", .{err});');
    Lines.Add('        lf.framework.shutdown();');
    Lines.Add('        exit(1);');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    if (g_fail > 0) exit(2);');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Zig call test', [Lines.Count]));
  finally
    ApiNames.Free;
    ZigIdents.Free;
  end;
end;

initialization

  RegisterGenerator(
    'zig',
    'xxx_abi_service_test.zig',
    gkTest,
    'Zig ABI service test program',
    @GenerateABIServiceTestZigCode);

  RegisterGenerator(
    'zig',
    'xxx_abi_call_test.zig',
    gkTest,
    'Zig ABI call test program',
    @GenerateABICallTestZigCode);

end.
