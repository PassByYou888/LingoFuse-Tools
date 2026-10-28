unit http_zig_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceZigTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallZigTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_zig_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_zig_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal') or
    T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsZigReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('addrspace') or S.Same('align') or S.Same('allowzero') or S.Same('and') or
    S.Same('anyframe') or S.Same('anytype') or S.Same('asm') or S.Same('async') or
    S.Same('await') or S.Same('break') or S.Same('callconv') or S.Same('catch') or
    S.Same('comptime') or S.Same('const') or S.Same('continue') or S.Same('defer') or
    S.Same('else') or S.Same('enum') or S.Same('errdefer') or S.Same('error') or
    S.Same('export') or S.Same('extern') or S.Same('fn') or S.Same('for') or
    S.Same('if') or S.Same('inline') or S.Same('linksection') or S.Same('noalias') or
    S.Same('noinline') or S.Same('nosuspend') or S.Same('opaque') or S.Same('or') or
    S.Same('orelse') or S.Same('packed') or S.Same('pub') or S.Same('resume') or
    S.Same('return') or S.Same('struct') or S.Same('suspend') or S.Same('switch') or
    S.Same('test') or S.Same('threadlocal') or S.Same('try') or S.Same('union') or
    S.Same('unreachable') or S.Same('usingnamespace') or S.Same('var') or
    S.Same('volatile') or S.Same('while');
end;

function MakeSafeZigIdent(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then begin Result := 'p' + umlIntToStr(Index); Exit end;
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
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then Result := '_' + Result;
  if IsZigReservedWord(Result) then Result := Result + '_';
end;

function ZigStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      '"':  Result.Append('\"');
      '\':  Result.Append('\\');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\x');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
        end
        else
          Result.Append(c);
    end;
  end;
  Result.Append('"');
end;

function MdCellEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '|' then Result.Append('\|')
    else if c = #10 then Result.Append(' ')
    else if c = #13 then
    else Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var
  i, j: integer;
  Line, T: TP_String;
begin
  Result := '';
  if Comment.Len = 0 then Exit;
  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do Inc(j);
    if j > i then
    begin
      Line := Comment.GetString(i, j);
      T := Line.TrimChar(#32#9);
      if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
        T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
      if T.Len > 0 then
        if T[1] = '{' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
        else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
          T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
      if T.Len > 0 then
        if T[T.Len] = '}' then T := T.GetString(1, T.Len).TrimChar(#32#9)
        else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then
          T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
      if (T.Len > 0) and (T[1] <> '@') then
      begin
        if T[1] = '*' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9);
        if T.Len > 0 then
        begin
          Result := T;
          if Result.Len > 200 then Result := Result.GetString(1, 201);
          Exit;
        end;
      end;
    end;
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do Inc(i);
  end;
end;

function BuildZigParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeZigIdent(Params[i].Name, i);
    if ABI_Type_Is_String(Params[i].PascalType) then T := '[]const u8'
    else if ABI_Type_Is_Float(Params[i].PascalType) then T := 'f64'
    else T := 'i64';
    if i > 0 then Result := Result + ', ';
    Result := Result + n + ': ' + T;
  end;
end;

function BuildZigDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then d := '""'
    else if ABI_Type_Is_Float(Params[i].PascalType) then d := '0.0'
    else d := '0';
    if i > 0 then Result := Result + ', ';
    Result := Result + d;
  end;
end;

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  F: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    F := Model.Funcs[i];
    Supported := True;
    for j := 0 to High(F.Params) do
      if not ABI_Type_Is_Supported(F.Params[j].PascalType) then
      begin
        Supported := False;
        Break;
      end;
    if Supported and F.IsFunction and (not ABI_Type_Is_Supported(F.ReturnType)) then
      Supported := False;
    if Supported and (F.Name.Len = 0) then
      Supported := False;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := F;
    end;
  end;
end;

procedure BuildDisambiguatedApiNames(
  const SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList);
var
  i, j: integer;
  ApiName: TP_String;
begin
  ApiNames.Clear;
  for i := 0 to High(SupportedFuncs) do
  begin
    ApiName := MakeApiName(SupportedFuncs[i].Name);
    if ApiNames.IndexOf(ApiName) >= 0 then
    begin
      j := 1;
      while ApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do Inc(j);
      ApiName := ApiName + '_' + umlIntToStr(j).Text;
    end;
    ApiNames.Add(ApiName);
  end;
end;

// ============================================================================
// SERVICE HOST PROGRAM (v5, unchanged)
// ============================================================================

function GenerateHTTPServiceZigTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceFileName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then begin Log('Model is nil'); Exit end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then begin Log('UnitName is empty'); Exit end;
  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceFileName := NormalizedUnit + '_http_json_service_zig.zig';
  SupportedFuncs := CollectSupportedFunctions(Model);

  Lines := TPascalStringList.Create;
  try
    Lines.Add('// Auto-generated by http_zig_abi_test_generator_tool.pas (v9).');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service host for the generated Zig LingoFuse service.');
    Lines.Add('//');
    Lines.Add('// Lifecycle:');
    Lines.Add('//   1. Load native library and configure options.');
    Lines.Add('//   2. Create the App and register every API.');
    Lines.Add('//   3. prepareService(ENDPOINT) - become the listener.');
    Lines.Add('//   4. prepareClient(ENDPOINT) - also connect as a client.');
    Lines.Add('//   5. prepareDone() - start the framework.');
    Lines.Add('//   6. Block on getchar() so the process stays online.');
    Lines.Add('//   7. Clean shutdown on Enter.');
    Lines.Add('');
    Lines.Add('const std = @import("std");');
    Lines.Add('const lf = @import("lingofuse");');
    Lines.Add('const service = @import("' + ServiceFileName.Text + '");');
    Lines.Add('');
    Lines.Add('extern "c" fn getchar() c_int;');
    Lines.Add('');
    Lines.Add('pub fn main() void {');
    Lines.Add('    lf.framework.init() catch |e| {');
    Lines.Add('        std.debug.print("[FATAL] framework.init failed: {}\n", .{e});');
    Lines.Add('        std.process.exit(1);');
    Lines.Add('    };');
    Lines.Add('    defer lf.framework.deinit();');
    Lines.Add('');
    Lines.Add('    lf.options.setWaitConnectionReadyOk(false) catch {};');
    Lines.Add('    lf.options.setOverlapConnection(true) catch {};');
    Lines.Add('    lf.options.setQuiet(true) catch {};');
    Lines.Add('');
    Lines.Add('    lf.framework.resetPrepare();');
    Lines.Add('');
    Lines.Add('    var app = lf.AppHandle.create(service.APP_NAME, service.APP_DESC) catch |e| {');
    Lines.Add('        std.debug.print("[FATAL] AppHandle.create failed: {}\n", .{e});');
    Lines.Add('        std.process.exit(1);');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    service.registerAllApis(&app) catch |e| {');
    Lines.Add('        std.debug.print("[FATAL] registerAllApis failed: {}\n", .{e});');
    Lines.Add('        app.deinit();');
    Lines.Add('        std.process.exit(1);');
    Lines.Add('    };');
    Lines.Add('    std.debug.print("[service] Registered ' + umlIntToStr(Length(SupportedFuncs)).Text +
      ' APIs on app ''{s}''\n", .{service.APP_NAME});');
    Lines.Add('');
    Lines.Add('    _ = lf.framework.prepareService(service.ENDPOINT, service.ENDPOINT) catch |e| {');
    Lines.Add('        std.debug.print("[FATAL] prepareService failed: {}\n", .{e});');
    Lines.Add('        app.deinit();');
    Lines.Add('        std.process.exit(1);');
    Lines.Add('    };');
    Lines.Add('    _ = lf.framework.prepareClient(service.ENDPOINT, &app) catch |e| {');
    Lines.Add('        std.debug.print("[FATAL] prepareClient failed: {}\n", .{e});');
    Lines.Add('        app.deinit();');
    Lines.Add('        std.process.exit(1);');
    Lines.Add('    };');
    Lines.Add('    _ = lf.framework.prepareDone();');
    Lines.Add('');
    Lines.Add('    std.debug.print("[service] Online on endpoint {s}\n", .{service.ENDPOINT});');
    Lines.Add('    std.debug.print("[service] Press Enter to stop.\n", .{});');
    Lines.Add('    _ = getchar();');
    Lines.Add('');
    Lines.Add('    lf.framework.exitMainThread();');
    Lines.Add('    app.deinit();');
    Lines.Add('    lf.framework.shutdown();');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
  finally
    if Result <> Lines then Lines.Free;
  end;
end;

// ============================================================================
// CALL TEST PROGRAM (v9 -- fixes \n, otherwise same as v8)
// ============================================================================

function GenerateHTTPCallZigTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, CallFileName, Endpoint, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, DefaultArgs, ArgSep: TP_String;
begin
  Result := nil;
  if Model = nil then begin Log('Model is nil'); Exit end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then begin Log('UnitName is empty'); Exit end;
  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  CallFileName := NormalizedUnit + '_http_json_call_zig.zig';
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// Auto-generated by http_zig_abi_test_generator_tool.pas (v9).');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('//');
    Lines.Add('// Call-side end-to-end test for the generated Zig HTTP/JSON client.');
    Lines.Add('//');
    Lines.Add('// The generated client speaks LingoFuse-mesh to bridge.py:');
    Lines.Add('//');
    Lines.Add('//     Zig caller  --LF-->  bridge.py  --HTTP-->  remote service');
    Lines.Add('//');
    Lines.Add('// Therefore this test must:');
    Lines.Add('//   1. Init the LingoFuse framework.');
    Lines.Add('//   2. Connect as a client on the SAME endpoint as bridge.py.');
    Lines.Add('//   3. Wait for the bridge App to appear in the local cache.');
    Lines.Add('//   4. Call each API (sync + async).');
    Lines.Add('//   5. Shut down cleanly so the C worker threads never outlive');
    Lines.Add('//      their IPC handle.');
    Lines.Add('');
    Lines.Add('const std = @import("std");');
    Lines.Add('const lf = @import("lingofuse");');
    Lines.Add('const call = @import("' + CallFileName.Text + '");');
    Lines.Add('');
    Lines.Add('extern "c" fn getchar() c_int;');
    Lines.Add('extern "c" fn Sleep(dwMilliseconds: u32) void;');
    Lines.Add('');
    Lines.Add('fn sleepMs(ms: u32) void { Sleep(ms); }');
    Lines.Add('');
    Lines.Add('const Log = struct {');
    Lines.Add('    fn line(msg: []const u8) void {');
    Lines.Add('        std.debug.print("{s}\n", .{msg});');
    Lines.Add('    }');
    Lines.Add('    fn fmt(comptime f: []const u8, args: anytype) void {');
    Lines.Add('        std.debug.print(f ++ "\n", args);');
    Lines.Add('    }');
    Lines.Add('};');
    Lines.Add('');
    Lines.Add('// Every fatal exit MUST stop the LingoFuse main thread first.');
    Lines.Add('// std.process.exit() bypasses LingoFuse cleanup, and the C-side');
    Lines.Add('// worker threads crash on a half-torn-down IPC handle.');
    Lines.Add('fn fatal(comptime fmt: []const u8, args: anytype) noreturn {');
    Lines.Add('    lf.framework.exitMainThread();');
    Lines.Add('    lf.framework.shutdown();');
    Lines.Add('    lf.framework.deinit();');
    Lines.Add('    std.debug.print(fmt, args);');
    Lines.Add('    std.process.exit(1);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('const Waiter = struct {');
    Lines.Add('    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),');
    Lines.Add('    success: bool = false,');
    Lines.Add('    err_buf: [128]u8 = undefined,');
    Lines.Add('    err_len: usize = 0,');
    Lines.Add('    fn wait(self: *Waiter, timeout_ms: u32) bool {');
    Lines.Add('        var elapsed: u32 = 0;');
    Lines.Add('        while (elapsed < timeout_ms) : (elapsed += 10) {');
    Lines.Add('            if (self.done.load(.acquire)) return true;');
    Lines.Add('            sleepMs(10);');
    Lines.Add('        }');
    Lines.Add('        return false;');
    Lines.Add('    }');
    Lines.Add('    fn errMsg(self: *const Waiter) []const u8 {');
    Lines.Add('        return self.err_buf[0..self.err_len];');
    Lines.Add('    }');
    Lines.Add('};');
    Lines.Add('');

    // ---- Per-API async handlers ---------------------------------------------
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Lines.Add('fn ' + ApiName.Text + '_handler(user_ctx: ?*anyopaque, result: call.' + ApiName.Text + '_Result) void {');
      Lines.Add('    const raw = user_ctx orelse return;');
      Lines.Add('    const w: *Waiter = @ptrCast(@alignCast(raw));');
      Lines.Add('    switch (result) {');
      Lines.Add('        .ok => { w.success = true; w.done.store(true, .release); },');
      Lines.Add('        .err => |e| {');
      Lines.Add('            const n = @errorName(e);');
      Lines.Add('            const m = @min(n.len, w.err_buf.len);');
      Lines.Add('            @memcpy(w.err_buf[0..m], n[0..m]);');
      Lines.Add('            w.err_len = m;');
      Lines.Add('            w.done.store(true, .release);');
      Lines.Add('        },');
      Lines.Add('    }');
      Lines.Add('}');
      Lines.Add('');
    end;

    // ---- main --------------------------------------------------------------
    Lines.Add('pub fn main() void {');
    Lines.Add('    lf.framework.init() catch |e| {');
    Lines.Add('        std.debug.print("[FATAL] framework.init failed: {}\n", .{e});');
    Lines.Add('        std.process.exit(1);');
    Lines.Add('    };');
    Lines.Add('');
    Lines.Add('    lf.options.setWaitConnectionReadyOk(false) catch {};');
    Lines.Add('    lf.options.setOverlapConnection(true) catch {};');
    Lines.Add('    lf.options.setQuiet(true) catch {};');
    Lines.Add('');
    Lines.Add('    // Bridge names: v14 call module already defaults to');
    Lines.Add('    // __lf_http_bridge__ / __lf_outbound_post__, which match');
    Lines.Add('    // bridge.py and lf_http_bridge_client.pas. No override needed.');
    Lines.Add('    call.HTTP_CALL_BASE_URL = ' + ZigStrLit(BaseUrl).Text + ';');
    Lines.Add('');
    Lines.Add('    lf.framework.resetPrepare();');
    Lines.Add('    _ = lf.framework.prepareClient(' + ZigStrLit(Endpoint).Text + ', null) catch |e| {');
    Lines.Add('        fatal("[FATAL] prepareClient failed: {}\n", .{e});');
    Lines.Add('    };');
    Lines.Add('    _ = lf.framework.prepareDone();');
    Lines.Add('');
    Lines.Add('    // Wait for the bridge App to appear in the local broadcast cache.');
    Lines.Add('    // 10 s is generous; typical latency is ~3 s.');
    Lines.Add('    var waited: u32 = 0;');
    Lines.Add('    while (waited < 10_000) : (waited += 200) {');
    Lines.Add('        if (call.checkBridgeApi()) break;');
    Lines.Add('        sleepMs(200);');
    Lines.Add('    }');
    Lines.Add('    if (!call.checkBridgeApp()) {');
    Lines.Add('        fatal(');
    Lines.Add('            "[FATAL] bridge app ''{s}'' not found in mesh\n" ++');
    Lines.Add('            "[hint]  start bridge.py with:\n" ++');
    Lines.Add('            "          python bridge.py --endpoint ' + Endpoint.Text + ' --port 8081\n",');
    Lines.Add('            .{call.BRIDGE_APP_NAME},');
    Lines.Add('        );');
    Lines.Add('    }');
    Lines.Add('    if (!call.checkBridgeApi()) {');
    Lines.Add('        fatal(');
    Lines.Add('            "[FATAL] bridge app ''{s}'' found, but API ''{s}'' is missing\n",');
    Lines.Add('            .{ call.BRIDGE_APP_NAME, call.BRIDGE_API_NAME },');
    Lines.Add('        );');
    Lines.Add('    }');
    Lines.Add('    std.debug.print("[diag] bridge reachable: {s}.{s}\n", .{');
    Lines.Add('        call.BRIDGE_APP_NAME, call.BRIDGE_API_NAME,');
    Lines.Add('    });');
    Lines.Add('');
    Lines.Add('    Log.line("================================================================");');
    Lines.Add('    Log.line("  LingoFuse Zig HTTP/JSON call test (via LingoFuse mesh + bridge)");');
    Lines.Add('    Log.fmt("  Endpoint   : ' + Endpoint.Text + '", .{});');
    Lines.Add('    Log.fmt("  Bridge App : {s}", .{call.BRIDGE_APP_NAME});');
    Lines.Add('    Log.fmt("  Bridge Api : {s}", .{call.BRIDGE_API_NAME});');
    Lines.Add('    Log.fmt("  Base URL   : {s}", .{call.HTTP_CALL_BASE_URL});');
    Lines.Add('    Log.line("================================================================");');
    Lines.Add('');
    Lines.Add('    var passed: i32 = 0;');
    Lines.Add('    var failed: i32 = 0;');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildZigDefaultArgList(F.Params);
      if Length(F.Params) > 0 then ArgSep := ', ' else ArgSep := '';

      // ---- sync ----
      Lines.Add('    // ---- ' + ApiName.Text + ' [sync] ----');
      Lines.Add('    if (call.' + ApiName.Text + '(' + DefaultArgs.Text + ')) |_| {');
      Lines.Add('        Log.fmt("[OK  ] {s} [sync]", .{' + ZigStrLit(ApiName).Text + '});');
      Lines.Add('        passed += 1;');
      Lines.Add('    } else |e| {');
      Lines.Add('        const info = call.lastError();');
      Lines.Add('        Log.fmt("[FAIL] {s} [sync]: {s} (code={d}, msg={s})", .{');
      Lines.Add('            ' + ZigStrLit(ApiName).Text + ', @errorName(e), info.code, info.message() });');
      Lines.Add('        failed += 1;');
      Lines.Add('    }');
      Lines.Add('');

      // ---- async ----
      Lines.Add('    // ---- ' + ApiName.Text + ' [async] ----');
      Lines.Add('    {');
      Lines.Add('        var waiter = Waiter{};');
      Lines.Add('        var spawn_ok = true;');
      Lines.Add('        call.' + ApiName.Text + '_async(' + DefaultArgs.Text + ArgSep.Text + '&waiter, ' + ApiName.Text + '_handler) catch |e| {');
      Lines.Add('            Log.fmt("[FAIL] {s} [async]: spawn failed: {s}", .{ ' + ZigStrLit(ApiName).Text + ', @errorName(e) });');
      Lines.Add('            failed += 1;');
      Lines.Add('            spawn_ok = false;');
      Lines.Add('        };');
      Lines.Add('        if (spawn_ok) {');
      Lines.Add('            if (!waiter.wait(10_000)) {');
      Lines.Add('                Log.fmt("[FAIL] {s} [async]: timeout", .{' + ZigStrLit(ApiName).Text + '});');
      Lines.Add('                failed += 1;');
      Lines.Add('            } else if (waiter.success) {');
      Lines.Add('                Log.fmt("[OK  ] {s} [async]", .{' + ZigStrLit(ApiName).Text + '});');
      Lines.Add('                passed += 1;');
      Lines.Add('            } else {');
      Lines.Add('                Log.fmt("[FAIL] {s} [async]: {s}", .{ ' + ZigStrLit(ApiName).Text + ', waiter.errMsg() });');
      Lines.Add('                failed += 1;');
      Lines.Add('            }');
      Lines.Add('        }');
      Lines.Add('    }');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('    Log.line("[skip] no supported routines to test");');

    Lines.Add('    Log.line("");');
    Lines.Add('    Log.line("================================================================");');
    Lines.Add('    Log.fmt("  Results: {d} passed, {d} failed", .{ passed, failed });');
    Lines.Add('    Log.line("================================================================");');
    Lines.Add('');
    Lines.Add('    Log.line("Press Enter to exit.");');
    Lines.Add('    _ = getchar();');
    Lines.Add('');
    Lines.Add('    lf.framework.exitMainThread();');
    Lines.Add('    lf.framework.shutdown();');
    Lines.Add('    lf.framework.deinit();');
    Lines.Add('');
    Lines.Add('    if (failed != 0) std.process.exit(1);');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
  finally
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry('zig', 'Zig HTTP/JSON service host program',
    asBoth, akTestCode, '_http_json_service_main_test___.zig', False,
    @GenerateHTTPServiceZigTestCode);
  RegisterCodeGenEntry('zig', 'Zig HTTP/JSON call test program',
    asBoth, akTestCode, '_http_json_call_main_test___.zig', False,
    @GenerateHTTPCallZigTestCode);
end.
