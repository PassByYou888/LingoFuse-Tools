unit zig_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallZigCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[zig_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[zig_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Zig_Param_Decl(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := '[]const u8'
  else
    Result := ABI_Type_To_Zig_Decl(T);
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

function MakeSafeZigIdent(const Name: TP_String; Index: integer): TP_String;
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
  if IsZigKeyword(Result) then
    Result := Result + '_';
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

function BuildTypedParams(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PType: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeZigIdent(Params[i].Name, i);
    PType := ABI_Type_To_Zig_Param_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName + ': ' + PType;
  end;
end;

function PrefixParams(const Prefix, TypedParams: TP_String): TP_String;
begin
  if Prefix = '' then
    Result := TypedParams
  else if TypedParams = '' then
    Result := Prefix
  else
    Result := Prefix + ', ' + TypedParams;
end;

procedure EmitParamWrites(Lines: TPascalStringList;
  const Params: TParamArray);
var
  i: integer;
  PName: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeZigIdent(Params[i].Name, i);
    if IsStringABIType(Params[i].PascalType) then
      Lines.Add('    try req.writeString(' + PName + ');')
    else
      Lines.Add('    try req.write(' + PName + ');');
  end;
end;

procedure EmitReadResponseFunction(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String; const F: TFunctionStructure);
var
  RetDecl, FnSig: TP_String;
begin
  RetDecl := ABI_Type_To_Zig_Decl(F.ReturnType);

  if IsStringABIType(F.ReturnType) then
    FnSig := 'fn read_' + ZigIdent + '_response(hnd: *lf.DataHandle, alloc: std.mem.Allocator) Error!' + RetDecl + ' {'
  else
    FnSig := 'fn read_' + ZigIdent + '_response(hnd: *lf.DataHandle) Error!' + RetDecl + ' {';

  Lines.Add(FnSig);
  Lines.Add('    const total = try hnd.size();');
  Lines.Add('    if (total <= 0) return error.CallFailed;');
  Lines.Add('    try hnd.setPosition(0);');
  Lines.Add('    var status: u8 = 0;');
  Lines.Add('    if (!try hnd.read(&status)) return error.ReadFailed;');
  Lines.Add('    if (status != STATUS_OK) return error.CallFailed;');
  if IsStringABIType(F.ReturnType) then
    Lines.Add('    return lf.io.readString(hnd, alloc);')
  else
  begin
    Lines.Add('    var v: ' + RetDecl + ' = undefined;');
    Lines.Add('    if (!try hnd.read(&v)) return error.ReadFailed;');
    Lines.Add('    return v;');
  end;
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFunctionResultType(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetDecl: TP_String;
begin
  RetDecl := ABI_Type_To_Zig_Decl(F.ReturnType);
  Lines.Add('pub const ' + ApiName + 'Result = union(enum) {');
  Lines.Add('    ok: ' + RetDecl + ',');
  Lines.Add('    err: lf.Error,');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('pub const ' + ApiName + 'AsyncHandler = *const fn (user_ctx: ?*anyopaque, result: ' + ApiName + 'Result) void;');
  Lines.Add('');
end;

procedure EmitAsyncContext(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
begin
  Lines.Add('const ' + ApiName + 'AsyncCtx = struct {');
  Lines.Add('    user_ctx: ?*anyopaque,');
  Lines.Add('    user_handler: ' + ApiName + 'AsyncHandler,');
  if IsStringABIType(F.ReturnType) then
    Lines.Add('    alloc: std.mem.Allocator,');
  Lines.Add('};');
  Lines.Add('');
end;

procedure EmitAsyncBridge(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String; const F: TFunctionStructure);
var
  ReadCall: TP_String;
begin
  Lines.Add('fn ' + ZigIdent + '_async_bridge(ctx: ?*anyopaque, ar: lf.async_call.AsyncResult) void {');
  Lines.Add('    const c: *' + ApiName + 'AsyncCtx = @ptrCast(@alignCast(ctx orelse return));');
  Lines.Add('    defer std.heap.page_allocator.destroy(c);');
  Lines.Add('    const result: ' + ApiName + 'Result = switch (ar) {');
  Lines.Add('        .ok => |h| blk: {');
  Lines.Add('            var hh = h;');
  if IsStringABIType(F.ReturnType) then
    ReadCall := 'read_' + ZigIdent + '_response(&hh, c.alloc)'
  else
    ReadCall := 'read_' + ZigIdent + '_response(&hh)';
  Lines.Add('            const v = ' + ReadCall + ' catch |e| break :blk .{ .err = e };');
  Lines.Add('            break :blk .{ .ok = v };');
  Lines.Add('        },');
  Lines.Add('        .err => |e| .{ .err = e },');
  Lines.Add('    };');
  Lines.Add('    c.user_handler(c.user_ctx, result);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSyncFunction(Lines: TPascalStringList;
  const ApiName, ZigIdent, FnSuffix: TP_String;
  const F: TFunctionStructure;
  const AddrPrefix, CallFn: TP_String;
  const AddrZigType, AddrName: TP_String);
var
  FnName, ExtraParam, ParamStr: TP_String;
  HasAlloc: boolean;
begin
  FnName := ZigIdent + FnSuffix;
  HasAlloc := IsStringABIType(F.ReturnType);

  ExtraParam := '';
  if AddrName <> '' then
    ExtraParam := AddrName + ': ' + AddrZigType;

  ParamStr := PrefixParams(ExtraParam, BuildTypedParams(F.Params));
  if HasAlloc then
    ParamStr := PrefixParams('alloc: std.mem.Allocator', ParamStr);

  Lines.Add('pub fn ' + FnName + '(' + ParamStr + ') Error!' +
    ABI_Type_To_Zig_Decl(F.ReturnType) + ' {');
  Lines.Add('    var req = try data.create(' + ZigStrLit(ApiName) + ');');
  Lines.Add('    defer req.deinit();');
  EmitParamWrites(Lines, F.Params);
  Lines.Add('    var resp = (try lf.framework.' + CallFn + '(' + AddrPrefix +
    ', &req, ABI_TIMEOUT)) orelse return error.CallFailed;');
  Lines.Add('    defer resp.deinit();');
  if HasAlloc then
    Lines.Add('    return read_' + ZigIdent + '_response(&resp, alloc);')
  else
    Lines.Add('    return read_' + ZigIdent + '_response(&resp);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAsyncFunction(Lines: TPascalStringList;
  const ApiName, ZigIdent, FnSuffix: TP_String;
  const F: TFunctionStructure;
  const AddrPrefix, CallFn: TP_String;
  const AddrZigType, AddrName: TP_String);
var
  FnName, ExtraParam, ParamStr: TP_String;
  HasAlloc: boolean;
begin
  FnName := ZigIdent + FnSuffix;
  HasAlloc := IsStringABIType(F.ReturnType);

  ExtraParam := '';
  if AddrName <> '' then
    ExtraParam := AddrName + ': ' + AddrZigType;

  ParamStr := PrefixParams(ExtraParam, BuildTypedParams(F.Params));
  if HasAlloc then
    ParamStr := PrefixParams('alloc: std.mem.Allocator', ParamStr);
  ParamStr := PrefixParams(ParamStr,
    'user_ctx: ?*anyopaque, user_handler: ' + ApiName + 'AsyncHandler');

  Lines.Add('pub fn ' + FnName + '(' + ParamStr + ') Error!void {');
  Lines.Add('    var req = try data.create(' + ZigStrLit(ApiName) + ');');
  Lines.Add('    defer req.deinit();');
  EmitParamWrites(Lines, F.Params);
  Lines.Add('    const ctx = std.heap.page_allocator.create(' + ApiName + 'AsyncCtx) catch return error.OutOfMemory;');
  if HasAlloc then
    Lines.Add('    ctx.* = .{ .user_ctx = user_ctx, .user_handler = user_handler, .alloc = alloc };')
  else
    Lines.Add('    ctx.* = .{ .user_ctx = user_ctx, .user_handler = user_handler };');
  Lines.Add('    lf.async_call.' + CallFn + '(' + AddrPrefix + ', &req, ctx, ' + ZigIdent + '_async_bridge) catch |err| {');
  Lines.Add('        if (err != lf.Error.CallFailed) std.heap.page_allocator.destroy(ctx);');
  Lines.Add('        return err;');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNotifyProcedure(Lines: TPascalStringList;
  const ApiName, ZigIdent, FnSuffix: TP_String;
  const F: TFunctionStructure;
  const AddrPrefix, NotifyFn: TP_String;
  const AddrZigType, AddrName: TP_String);
var
  FnName, ExtraParam, ParamStr: TP_String;
begin
  FnName := ZigIdent + FnSuffix;

  ExtraParam := '';
  if AddrName <> '' then
    ExtraParam := AddrName + ': ' + AddrZigType;

  ParamStr := PrefixParams(ExtraParam, BuildTypedParams(F.Params));

  Lines.Add('pub fn ' + FnName + '(' + ParamStr + ') Error!void {');
  Lines.Add('    var req = try data.create(' + ZigStrLit(ApiName) + ');');
  Lines.Add('    defer req.deinit();');
  EmitParamWrites(Lines, F.Params);
  Lines.Add('    try lf.framework.' + NotifyFn + '(' + AddrPrefix + ', &req);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFunctionVariants(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String; const F: TFunctionStructure);
begin
  EmitFunctionResultType(Lines, ApiName, F);
  EmitAsyncContext(Lines, ApiName, F);
  EmitReadResponseFunction(Lines, ApiName, ZigIdent, F);
  EmitAsyncBridge(Lines, ApiName, ZigIdent, F);

  EmitSyncFunction(Lines, ApiName, ZigIdent, '', F,
    'ABI_TARGET_APP', 'callOptional', '', '');
  EmitSyncFunction(Lines, ApiName, ZigIdent, '_uid', F,
    'uid', 'callOptionalByUid', 'lf.Uid', 'uid');
  EmitSyncFunction(Lines, ApiName, ZigIdent, '_p2p_name', F,
    'p2p_name', 'callOptionalByP2PName', '[:0]const u8', 'p2p_name');

  EmitAsyncFunction(Lines, ApiName, ZigIdent, '_async', F,
    'ABI_TARGET_APP', 'callAsync', '', '');
  EmitAsyncFunction(Lines, ApiName, ZigIdent, '_async_sequenced', F,
    'ABI_TARGET_APP', 'callAsyncSequenced', '', '');
  EmitAsyncFunction(Lines, ApiName, ZigIdent, '_uid_async', F,
    'uid', 'callAsyncByUid', 'lf.Uid', 'uid');
  EmitAsyncFunction(Lines, ApiName, ZigIdent, '_uid_async_sequenced', F,
    'uid', 'callAsyncByUidSequenced', 'lf.Uid', 'uid');
  EmitAsyncFunction(Lines, ApiName, ZigIdent, '_p2p_name_async', F,
    'p2p_name', 'callAsyncByP2PName', '[:0]const u8', 'p2p_name');
  EmitAsyncFunction(Lines, ApiName, ZigIdent, '_p2p_name_async_sequenced', F,
    'p2p_name', 'callAsyncByP2PNameSequenced', '[:0]const u8', 'p2p_name');
end;

procedure EmitProcedureVariants(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String; const F: TFunctionStructure);
begin
  EmitNotifyProcedure(Lines, ApiName, ZigIdent, '', F,
    'ABI_TARGET_APP', 'notify', '', '');
  EmitNotifyProcedure(Lines, ApiName, ZigIdent, '_sequenced_notify', F,
    'ABI_TARGET_APP', 'sequencedNotify', '', '');
  EmitNotifyProcedure(Lines, ApiName, ZigIdent, '_uid_notify', F,
    'uid', 'notifyByUid', 'lf.Uid', 'uid');
  EmitNotifyProcedure(Lines, ApiName, ZigIdent, '_uid_sequenced_notify', F,
    'uid', 'sequencedNotifyByUid', 'lf.Uid', 'uid');
  EmitNotifyProcedure(Lines, ApiName, ZigIdent, '_p2p_name_notify', F,
    'p2p_name', 'notifyByP2PName', '[:0]const u8', 'p2p_name');
  EmitNotifyProcedure(Lines, ApiName, ZigIdent, '_p2p_name_sequenced_notify', F,
    'p2p_name', 'sequencedNotifyByP2PName', '[:0]const u8', 'p2p_name');
end;

function GenerateABICallZigCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetApp: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, ZigIdent: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallZigCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallZigCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';

  Log(PFormat('Generating Zig ABI call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
    end;

    Lines.Add('const std = @import("std");');
    Lines.Add('const lf = @import("lingofuse");');
    Lines.Add('const data = lf.DataHandle;');
    Lines.Add('const Error = lf.Error;');
    Lines.Add('');
    Lines.Add('pub var ABI_TARGET_APP: [:0]const u8 = ' + ZigStrLit(TargetApp) + ';');
    Lines.Add('pub var ABI_TIMEOUT: u64 = 5000;');
    Lines.Add('');
    Lines.Add('const STATUS_OK: u8 = 0x00;');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := UsedApiNames[i];
      ZigIdent := ToSnakeCase(ApiName);
      if F.IsFunction then
        EmitFunctionVariants(Lines, ApiName, ZigIdent, F)
      else
        EmitProcedureVariants(Lines, ApiName, ZigIdent, F);
    end;

    Result := Lines;
    Log(PFormat('Generated %d lines for Zig ABI call.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'zig',
    'xxx_abi_call.zig',
    gkCall,
    'Zig ABI call implementation',
    @GenerateABICallZigCode);

end.
