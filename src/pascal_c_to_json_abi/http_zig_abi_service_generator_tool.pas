unit http_zig_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceZigCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_zig_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_zig_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Zig_Param(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := '[]const u8'
  else if ABI_Type_Is_Float(T) then Result := 'f64'
  else if ABI_Type_Is_Int(T) then Result := 'i64'
  else Result := 'void';
end;

function ABI_Type_To_Zig_Return(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := '[]const u8'
  else if ABI_Type_Is_Float(T) then Result := 'f64'
  else if ABI_Type_Is_Int(T) then Result := 'i64'
  else Result := 'void';
end;

function ABI_Type_To_Pascal_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') then Result := 'Integer'
  else if T.Same('int64') then Result := 'Int64'
  else if T.Same('cardinal') then Result := 'Cardinal'
  else if T.Same('longint') then Result := 'LongInt'
  else if T.Same('dword') then Result := 'DWord'
  else if T.Same('word') then Result := 'Word'
  else if T.Same('smallint') then Result := 'SmallInt'
  else if T.Same('byte') then Result := 'Byte'
  else if T.Same('uint64') then Result := 'UInt64'
  else if T.Same('longword') then Result := 'LongWord'
  else if T.Same('double') then Result := 'Double'
  else if T.Same('single') then Result := 'Single'
  else if T.Same('extended') then Result := 'Extended'
  else if T.Same('real') then Result := 'Real'
  else if ABI_Type_Is_String(T) then Result := 'string'
  else Result := '';
end;

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then Result := 'number'
  else Result := '';
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

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  if T.Len > 0 then
  begin
    if T[1] = '{' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;
  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then T := T.GetString(1, T.Len).TrimChar(#32#9)
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
  if Comment.Len = 0 then Exit;
  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do Inc(j);
    if j > i then
    begin
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);
      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        else
        begin
          if Line[1] = '*' then Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if Line.Len > 0 then
          begin
            Result := Line;
            if Result.Len > 200 then Result := Result.GetString(1, 201);
            Exit;
          end;
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
    T := ABI_Type_To_Zig_Param(Params[i].PascalType);
    if i > 0 then Result := Result + ', ';
    Result := Result + n + ': ' + T;
  end;
end;

function BuildZigCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeZigIdent(Params[i].Name, i);
    if i > 0 then Result := Result + ', ';
    Result := Result + '_' + n;
  end;
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeZigIdent(F.Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    if i > 0 then ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;
  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

function BuildZigStubSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  ParamDecl, RetPart: TP_String;
begin
  ParamDecl := BuildZigParamDecl(F.Params);
  if F.IsFunction then RetPart := ' ' + ABI_Type_To_Zig_Return(F.ReturnType)
  else RetPart := ' void';
  Result := 'pub fn internal_call_' + ApiName + '(' + ParamDecl + ')' + RetPart;
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
// ZIG SERVICE MODULE GENERATOR
// ============================================================================

procedure EmitZigServiceHeader(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('// Auto-generated by http_zig_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI service provider for Zig.');
  Lines.Add('');
  Lines.Add('const std = @import("std");');
  Lines.Add('const lf = @import("lingofuse");');
  Lines.Add('');
  Lines.Add('extern "c" fn getchar() c_int;');
  Lines.Add('');
end;

procedure EmitZigServiceConfig(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Configuration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub const APP_NAME: [:0]const u8 = ' + ZigStrLit(AppName).Text + ';');
  Lines.Add('pub const APP_DESC: [:0]const u8 = ' + ZigStrLit(AppDesc).Text + ';');
  Lines.Add('pub const ENDPOINT: [:0]const u8 = ' + ZigStrLit(Endpoint).Text + ';');
  Lines.Add('');
  Lines.Add('pub var DEBUG_LOG: bool = false;');
  Lines.Add('');
end;

procedure EmitZigServiceJsonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// JSON helpers');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('fn _lookupValue(root: std.json.Value, name: []const u8, index: usize) ?std.json.Value {');
  Lines.Add('    const obj = switch (root) {');
  Lines.Add('        .object => |o| o,');
  Lines.Add('        else => return null,');
  Lines.Add('    };');
  Lines.Add('    if (obj.get("args")) |args_v| {');
  Lines.Add('        if (args_v == .array) {');
  Lines.Add('            const arr = args_v.array;');
  Lines.Add('            if (index < arr.items.len) return arr.items[index];');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    return obj.get(name);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _jsonGetI64(root: std.json.Value, name: []const u8, index: usize, default: i64) i64 {');
  Lines.Add('    const v = _lookupValue(root, name, index) orelse return default;');
  Lines.Add('    return switch (v) {');
  Lines.Add('        .integer => |i| i,');
  Lines.Add('        .float => |f| @intFromFloat(f),');
  Lines.Add('        else => default,');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _jsonGetF64(root: std.json.Value, name: []const u8, index: usize, default: f64) f64 {');
  Lines.Add('    const v = _lookupValue(root, name, index) orelse return default;');
  Lines.Add('    return switch (v) {');
  Lines.Add('        .float => |f| f,');
  Lines.Add('        .integer => |i| @floatFromInt(i),');
  Lines.Add('        else => default,');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _jsonGetString(root: std.json.Value, name: []const u8, index: usize, default: []const u8) []const u8 {');
  Lines.Add('    const v = _lookupValue(root, name, index) orelse return default;');
  Lines.Add('    return switch (v) {');
  Lines.Add('        .string => |s| s,');
  Lines.Add('        else => default,');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// JSON response emission');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('const _HEX = "0123456789abcdef";');
  Lines.Add('');
  Lines.Add('fn _writeJsonString(output: *lf.DataHandle, s: []const u8) void {');
  Lines.Add('    lf.io.writeString(output, s) catch |e| {');
  Lines.Add('        std.log.err("[service] write response failed: {}", .{e});');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
  // v5: std.array_list.Managed(u8) - Zig 0.17's managed ArrayList.
  Lines.Add('fn _escapeAppend(buf: *std.array_list.Managed(u8), ch: u8) bool {');
  Lines.Add('    switch (ch) {');
  Lines.Add('        0x22 => buf.appendSlice("\\\"") catch return false,');
  Lines.Add('        0x5C => buf.appendSlice("\\\\") catch return false,');
  Lines.Add('        0x08 => buf.appendSlice("\\b") catch return false,');
  Lines.Add('        0x09 => buf.appendSlice("\\t") catch return false,');
  Lines.Add('        0x0A => buf.appendSlice("\\n") catch return false,');
  Lines.Add('        0x0C => buf.appendSlice("\\f") catch return false,');
  Lines.Add('        0x0D => buf.appendSlice("\\r") catch return false,');
  Lines.Add('        else => {');
  Lines.Add('            if (ch < 0x20) {');
  Lines.Add('                const esc = [_]u8{ 0x5C, 0x75, 0x30, 0x30, _HEX[(ch >> 4) & 0x0F], _HEX[ch & 0x0F] };');
  Lines.Add('                buf.appendSlice(&esc) catch return false;');
  Lines.Add('            } else {');
  Lines.Add('                buf.append(ch) catch return false;');
  Lines.Add('            }');
  Lines.Add('        },');
  Lines.Add('    }');
  Lines.Add('    return true;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _writeSuccessI64(output: *lf.DataHandle, v: i64) void {');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('    const s = std.fmt.allocPrint(alloc, "{{\"code\":0,\"result\":{d}}}", .{v}) catch return;');
  Lines.Add('    defer alloc.free(s);');
  Lines.Add('    _writeJsonString(output, s);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _writeSuccessF64(output: *lf.DataHandle, v: f64) void {');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('    const s = std.fmt.allocPrint(alloc, "{{\"code\":0,\"result\":{d}}}", .{v}) catch return;');
  Lines.Add('    defer alloc.free(s);');
  Lines.Add('    _writeJsonString(output, s);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _writeSuccessString(output: *lf.DataHandle, v: []const u8) void {');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('    var buf = std.array_list.Managed(u8).init(alloc);');
  Lines.Add('    defer buf.deinit();');
  Lines.Add('    buf.appendSlice("{\"code\":0,\"result\":\"") catch return;');
  Lines.Add('    for (v) |ch| {');
  Lines.Add('        if (!_escapeAppend(&buf, ch)) return;');
  Lines.Add('    }');
  Lines.Add('    buf.appendSlice("\"}") catch return;');
  Lines.Add('    _writeJsonString(output, buf.items);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _writeSuccessVoid(output: *lf.DataHandle) void {');
  Lines.Add('    _writeJsonString(output, "{\"code\":0}");');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _writeError(output: *lf.DataHandle, msg: []const u8) void {');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('    var buf = std.array_list.Managed(u8).init(alloc);');
  Lines.Add('    defer buf.deinit();');
  Lines.Add('    buf.appendSlice("{\"code\":-1,\"error\":\"") catch return;');
  Lines.Add('    for (msg) |ch| {');
  Lines.Add('        if (!_escapeAppend(&buf, ch)) return;');
  Lines.Add('    }');
  Lines.Add('    buf.appendSlice("\"}") catch return;');
  Lines.Add('    _writeJsonString(output, buf.items);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitZigServiceStub(Lines: TPascalStringList;
  const F: TFunctionStructure;
  const ApiName: TP_String);
var
  i: integer;
  ParamDecl, DefaultReturn, Description: TP_String;
  HasParams: boolean;
  PName: TP_String;
begin
  ParamDecl := BuildZigParamDecl(F.Params);
  HasParams := Length(F.Params) > 0;
  Description := GetFullDescription(F.Comment);
  if Description.Len = 0 then Description := 'HTTP/JSON API: ' + ApiName;
  if F.IsFunction then
  begin
    if ABI_Type_Is_String(F.ReturnType) then DefaultReturn := '""'
    else if ABI_Type_Is_Float(F.ReturnType) then DefaultReturn := '0.0'
    else DefaultReturn := '0';
  end
  else DefaultReturn := '';
  Lines.Add('/// ' + Description.Text);
  Lines.Add('///');
  Lines.Add('/// Pascal source: `' + BuildPascalDecl(F) + '`.');
  Lines.Add('///');
  Lines.Add('/// TODO: replace this body with the real implementation.');
  if F.IsFunction then
    Lines.Add('pub fn internal_call_' + ApiName.Text + '(' + ParamDecl.Text + ') ' + ABI_Type_To_Zig_Return(F.ReturnType).Text + ' {')
  else
    Lines.Add('pub fn internal_call_' + ApiName.Text + '(' + ParamDecl.Text + ') void {');
  if HasParams then
    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafeZigIdent(F.Params[i].Name, i);
      Lines.Add('    _ = ' + PName.Text + ';');
    end;
  Lines.Add('    // TODO: implement this stub.');
  if F.IsFunction then Lines.Add('    return ' + DefaultReturn.Text + ';');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitZigServiceHandler(Lines: TPascalStringList;
  const F: TFunctionStructure;
  const ApiName: TP_String);
var
  i: integer;
  PName, ArgList: TP_String;
  HasParams: boolean;
begin
  HasParams := Length(F.Params) > 0;
  ArgList := BuildZigCallArgList(F.Params);
  Lines.Add('/// Handler for the `' + ApiName.Text + '` API.');
  Lines.Add('fn cb_' + ApiName.Text + '(ctx: ?*anyopaque, input: *lf.DataHandle, output: *lf.DataHandle) lf.Error!void {');
  Lines.Add('    _ = ctx;');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('');
  Lines.Add('    var parsed = lf.io.readJson(input, alloc, std.json.Value) catch {');
  Lines.Add('        _writeError(output, "Invalid JSON request");');
  Lines.Add('        return;');
  Lines.Add('    };');
  Lines.Add('    defer parsed.deinit();');
  Lines.Add('');
  Lines.Add('    if (DEBUG_LOG) {');
  Lines.Add('        std.debug.print("[service] ' + ApiName.Text + ': request received\n", .{});');
  Lines.Add('    }');
  Lines.Add('');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeZigIdent(F.Params[i].Name, i);
    if ABI_Type_Is_String(F.Params[i].PascalType) then
      Lines.Add('    const _' + PName.Text + ' = _jsonGetString(parsed.value, ' + ZigStrLit(F.Params[i].Name).Text + ', ' + umlIntToStr(i).Text + ', "");')
    else if ABI_Type_Is_Float(F.Params[i].PascalType) then
      Lines.Add('    const _' + PName.Text + ' = _jsonGetF64(parsed.value, ' + ZigStrLit(F.Params[i].Name).Text + ', ' + umlIntToStr(i).Text + ', 0.0);')
    else
      Lines.Add('    const _' + PName.Text + ' = _jsonGetI64(parsed.value, ' + ZigStrLit(F.Params[i].Name).Text + ', ' + umlIntToStr(i).Text + ', 0);');
  end;
  if HasParams then Lines.Add('');
  if F.IsFunction then
  begin
    Lines.Add('    const _result = internal_call_' + ApiName.Text + '(' + ArgList.Text + ');');
    if ABI_Type_Is_String(F.ReturnType) then Lines.Add('    _writeSuccessString(output, _result);')
    else if ABI_Type_Is_Float(F.ReturnType) then Lines.Add('    _writeSuccessF64(output, _result);')
    else Lines.Add('    _writeSuccessI64(output, _result);');
  end
  else
  begin
    Lines.Add('    internal_call_' + ApiName.Text + '(' + ArgList.Text + ');');
    Lines.Add('    _writeSuccessVoid(output);');
  end;
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitZigServiceRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Description: TP_String;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Registration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub fn registerAllApis(app: *lf.AppHandle) lf.Error!void {');
  if Length(SupportedFuncs) = 0 then
    Lines.Add('    _ = app;')
  else
  begin
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then Description := 'HTTP/JSON API: ' + ApiName;
      Lines.Add('    try app.registerCall(');
      Lines.Add('        ' + ZigStrLit(ApiName).Text + ',');
      Lines.Add('        ' + ZigStrLit(Description).Text + ',');
      Lines.Add('        null,');
      Lines.Add('        cb_' + ApiName.Text + ',');
      Lines.Add('    );');
    end;
  end;
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitZigServiceEntry(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Entry point');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub fn runService() !void {');
  Lines.Add('    try lf.framework.init();');
  Lines.Add('    errdefer lf.framework.deinit();');
  Lines.Add('');
  Lines.Add('    lf.options.setWaitConnectionReadyOk(false) catch |e| {');
  Lines.Add('        std.log.warn("setWaitConnectionReadyOk failed: {}", .{e});');
  Lines.Add('    };');
  Lines.Add('    lf.options.setOverlapConnection(true) catch |e| {');
  Lines.Add('        std.log.warn("setOverlapConnection failed: {}", .{e});');
  Lines.Add('    };');
  Lines.Add('    lf.options.setQuiet(true) catch |e| {');
  Lines.Add('        std.log.warn("setQuiet failed: {}", .{e});');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    lf.framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('    var app = try lf.AppHandle.create(APP_NAME, APP_DESC);');
  Lines.Add('    errdefer app.deinit();');
  Lines.Add('');
  Lines.Add('    try registerAllApis(&app);');
  Lines.Add('    std.debug.print("[service] Registered APIs on app ''{s}''\n", .{APP_NAME});');
  Lines.Add('');
  Lines.Add('    _ = try lf.framework.prepareClient(ENDPOINT, &app);');
  Lines.Add('    std.debug.print("[service] Connecting to bridge at {s}...\n", .{ENDPOINT});');
  Lines.Add('');
  Lines.Add('    _ = lf.framework.prepareDone();');
  Lines.Add('');
  Lines.Add('    std.debug.print("[service] Ready. Press Enter to stop.\n", .{});');
  Lines.Add('    _ = getchar();');
  Lines.Add('');
  Lines.Add('    lf.framework.exitMainThread();');
  Lines.Add('    app.deinit();');
  Lines.Add('    lf.framework.shutdown();');
  Lines.Add('    lf.framework.deinit();');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('pub fn main() void {');
  Lines.Add('    runService() catch |e| {');
  Lines.Add('        std.debug.print("[FATAL] {}\n", .{e});');
  Lines.Add('        std.process.exit(1);');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceZigCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
begin
  Result := nil;
  if Model = nil then begin Log('Model is nil'); Exit end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then begin Log('UnitName is empty'); Exit end;
  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);
    EmitZigServiceHeader(Lines, UnitName);
    EmitZigServiceConfig(Lines, AppName, AppDesc, Endpoint);
    EmitZigServiceJsonHelpers(Lines);
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// User-editable API stubs');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
      EmitZigServiceStub(Lines, SupportedFuncs[i], ApiNames[i]);
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// LingoFuse callback wiring');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
      EmitZigServiceHandler(Lines, SupportedFuncs[i], ApiNames[i]);
    EmitZigServiceRegistration(Lines, SupportedFuncs, ApiNames);
    EmitZigServiceEntry(Lines);
    Result := Lines;
  finally
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry('zig', 'Zig HTTP/JSON service code',
    asService, akServiceCode, '_http_json_service_zig.zig', False,
    @GenerateHTTPServiceZigCode);
end.
