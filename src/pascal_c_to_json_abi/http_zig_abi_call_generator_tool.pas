unit http_zig_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallZigCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then DoStatus('[http_zig_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then DoStatus('[http_zig_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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
  if ABI_Type_Is_String(T) then Result := '[]u8'
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
var i: integer; c: TP_Char;
begin
  if Name.Len = 0 then begin Result := 'p' + umlIntToStr(Index); Exit end;
  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
      ((i > 1) and (c >= '0') and (c <= '9')) then Result.Append(c)
    else Result.Append('_');
  end;
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then Result := '_' + Result;
  if IsZigReservedWord(Result) then Result := Result + '_';
end;

function ZigStrLit(const S: TP_String): TP_String;
const HEXDIG = '0123456789abcdef';
var i, code: integer; c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i]; code := Ord(c);
    case c of
      '"': Result.Append('\"');
      '\': Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9: Result.Append('\t');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\x');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
        end
        else Result.Append(c);
    end;
  end;
  Result.Append('"');
end;

function MdCellEscape(const S: TP_String): TP_String;
var i: integer; c: TP_Char;
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
begin Result := umlIntToStr(V); end;

function StripCommentMarkers(const Line: TP_String): TP_String;
var T: TP_String;
begin
  T := Line.TrimChar(#32#9);
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  if T.Len > 0 then
  begin
    if T[1] = '{' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;
  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then T := T.GetString(1, T.Len).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
  end;
  Result := T;
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var i, j: integer; Line: TP_String;
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
var i: integer; n, T: TP_String;
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
var i: integer; n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeZigIdent(Params[i].Name, i);
    if i > 0 then Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var i: integer; ParamDecl, n, decl: TP_String;
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

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var i, j: integer; F: TFunctionStructure; Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    F := Model.Funcs[i]; Supported := True;
    for j := 0 to High(F.Params) do
      if not ABI_Type_Is_Supported(F.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" unsupported ABI type "%s"',
          [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]));
        Break;
      end;
    if Supported and F.IsFunction and (not ABI_Type_Is_Supported(F.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" unsupported', [F.Name.Text, F.ReturnType.Text]));
    end;
    if Supported and (F.Name.Len = 0) then Supported := False;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := F;
    end;
  end;
end;

procedure BuildDisambiguatedApiNames(const SupportedFuncs: TArryFunctionStructure; ApiNames: TPascalStringList);
var i, j: integer; ApiName: TP_String;
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
// ZIG CALL MODULE GENERATOR (v14)
// ============================================================================

procedure EmitZigHeader(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('// Auto-generated by http_zig_abi_call_generator_tool.pas (v14).');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('//');
  Lines.Add('// LingoFuse-mesh HTTP/JSON call module for Zig.');
  Lines.Add('//');
  Lines.Add('// The generated code reaches the service THROUGH the LingoFuse mesh,');
  Lines.Add('// using bridge.py as the LingoFuse-to-HTTP bridge:');
  Lines.Add('//');
  Lines.Add('//   Zig caller  --LF-->  bridge.py  --HTTP-->  remote service');
  Lines.Add('//');
  Lines.Add('// The caller MUST call lf.framework.init() before the first remote');
  Lines.Add('// call, and lf.framework.deinit() on exit.');
  Lines.Add('//');
  Lines.Add('// Every supported routine has TWO functions:');
  Lines.Add('//   * `pub fn <ApiName>(...)`        - synchronous (blocking)');
  Lines.Add('//   * `pub fn <ApiName>_async(...)`  - asynchronous, dispatched');
  Lines.Add('//                                       through lf.async_call');
  Lines.Add('//');
  Lines.Add('// Wire protocol:');
  Lines.Add('//   outer envelope  = { "url": "...", "method": "POST",');
  Lines.Add('//                       "body": { "args": [v1,v2,...] },');
  Lines.Add('//                       "timeout": N }');
  Lines.Add('//   bridge response = { "status_code": 200, "body":');
  Lines.Add('//                       { "code": 0, "result": ... } }');
  Lines.Add('');
  Lines.Add('const std = @import("std");');
  Lines.Add('const lf = @import("lingofuse");');
  Lines.Add('');
end;

procedure EmitZigConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Configuration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('// Default base URL of the HTTP bridge. The full URL for API "X"');
  Lines.Add('// is: HTTP_CALL_BASE_URL + "/" + "X".');
  Lines.Add('//');
  Lines.Add('// This default assumes bridge.py runs on localhost:8081 and the');
  Lines.Add('// target app name matches the source unit. If either is wrong,');
  Lines.Add('// overwrite this variable before calling any generated function.');
  Lines.Add('pub const DEFAULT_BASE_URL: []const u8 = ' + ZigStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('pub var HTTP_CALL_BASE_URL: []const u8 = DEFAULT_BASE_URL;');
  Lines.Add('');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Bridge identity');
  Lines.Add('//');
  Lines.Add('// These defaults MUST match bridge.py\''s own defaults AND the');
  Lines.Add('// Pascal-side lf_http_bridge_client.pas defaults:');
  Lines.Add('//');
  Lines.Add('//     source                       bridge app             bridge api');
  Lines.Add('//     --------------------------   -------------------    -------------------');
  Lines.Add('//     bridge.py (DEFAULT_BRIDGE_*) __lf_http_bridge__      __lf_outbound_post__');
  Lines.Add('//     lf_http_bridge_client.pas    __lf_http_bridge__      __lf_outbound_post__');
  Lines.Add('//     this module                  __lf_http_bridge__      __lf_outbound_post__');
  Lines.Add('//');
  Lines.Add('// If the bridge was started with --bridge-app / --bridge-api');
  Lines.Add('// overrides, change the two variables below BEFORE calling any');
  Lines.Add('// generated function:');
  Lines.Add('//');
  Lines.Add('//     call.BRIDGE_APP_NAME = "<your-bridge-app>";');
  Lines.Add('//     call.BRIDGE_API_NAME = "<your-bridge-api>";');
  Lines.Add('//');
  Lines.Add('// They are `pub var` so a caller can overwrite them at runtime.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub var BRIDGE_APP_NAME: [:0]const u8 = "__lf_http_bridge__";');
  Lines.Add('pub var BRIDGE_API_NAME: [:0]const u8 = "__lf_outbound_post__";');
  Lines.Add('pub var BRIDGE_REPAIR_API_NAME: [:0]const u8 = "__lf_repair_json__";');
  Lines.Add('');
  Lines.Add('// LingoFuse call timeout, in milliseconds. MUST be larger than');
  Lines.Add('// DEFAULT_HTTP_TIMEOUT_SEC * 1000 by a comfortable margin.');
  Lines.Add('pub var BRIDGE_TIMEOUT_MS: u64 = 35_000;');
  Lines.Add('');
  Lines.Add('// HTTP timeout passed to bridge.py, in seconds. bridge.py');
  Lines.Add('// forwards this to its outbound HTTP client (requests).');
  Lines.Add('pub var DEFAULT_HTTP_TIMEOUT_SEC: u32 = 30;');
  Lines.Add('');
  Lines.Add('// Set to True to log every request and response to stderr.');
  Lines.Add('pub var DEBUG_LOG: bool = false;');
  Lines.Add('');
end;

procedure EmitZigBridgeDiag(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Bridge diagnostics');
  Lines.Add('//');
  Lines.Add('// checkApp / checkApi consult the locally cached view of the mesh.');
  Lines.Add('// A freshly started bridge may not appear for 3-5 seconds. Poll');
  Lines.Add('// checkBridgeApi() until it returns true, or give up after a');
  Lines.Add('// timeout.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub fn checkBridgeApp() bool {');
  Lines.Add('    return lf.framework.checkApp(BRIDGE_APP_NAME);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('pub fn checkBridgeApi() bool {');
  Lines.Add('    return lf.framework.checkApi(BRIDGE_APP_NAME, BRIDGE_API_NAME);');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitZigErrorModel(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Error model');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub const ErrorKind = enum {');
  Lines.Add('    lf_transport,');
  Lines.Add('    empty_response,');
  Lines.Add('    invalid_envelope,');
  Lines.Add('    missing_body,');
  Lines.Add('    missing_code,');
  Lines.Add('    remote,');
  Lines.Add('    invalid_result_type,');
  Lines.Add('    missing_result,');
  Lines.Add('    other,');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('pub const ErrorInfo = struct {');
  Lines.Add('    kind: ErrorKind = .other,');
  Lines.Add('    code: i32 = 0,');
  Lines.Add('    http_status: u16 = 0,');
  Lines.Add('    message_buf: [512]u8 = undefined,');
  Lines.Add('    message_len: usize = 0,');
  Lines.Add('');
  Lines.Add('    pub fn message(self: *const @This()) []const u8 {');
  Lines.Add('        return self.message_buf[0..self.message_len];');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    fn set(self: *@This(), kind_: ErrorKind, code_: i32, http_: u16, msg: []const u8) void {');
  Lines.Add('        self.kind = kind_;');
  Lines.Add('        self.code = code_;');
  Lines.Add('        self.http_status = http_;');
  Lines.Add('        const n = @min(msg.len, self.message_buf.len);');
  Lines.Add('        @memcpy(self.message_buf[0..n], msg[0..n]);');
  Lines.Add('        self.message_len = n;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    fn clear(self: *@This()) void { self.* = .{}; }');
  Lines.Add('};');
  Lines.Add('');
  Lines.Add('threadlocal var _last_error: ErrorInfo = .{};');
  Lines.Add('');
  Lines.Add('pub fn lastError() *const ErrorInfo { return &_last_error; }');
  Lines.Add('');
  Lines.Add('pub const HttpCallError = error{');
  Lines.Add('    OutOfMemory,');
  Lines.Add('    LfTransportFailed,');
  Lines.Add('    EmptyResponse,');
  Lines.Add('    InvalidEnvelope,');
  Lines.Add('    MissingBody,');
  Lines.Add('    MissingCode,');
  Lines.Add('    RemoteCallFailed,');
  Lines.Add('    InvalidResultType,');
  Lines.Add('    MissingResult,');
  Lines.Add('};');
  Lines.Add('');
end;

procedure EmitZigTransport(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Transport (LingoFuse -> bridge.py -> HTTP)');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('fn _buildArgsArray(');
  Lines.Add('    alloc: std.mem.Allocator,');
  Lines.Add('    args: []const std.json.Value,');
  Lines.Add(') HttpCallError![]u8 {');
  Lines.Add('    var buf = std.array_list.Managed(u8).init(alloc);');
  Lines.Add('    defer buf.deinit();');
  Lines.Add('    buf.append(' + #39 + '[' + #39 + ') catch return HttpCallError.OutOfMemory;');
  Lines.Add('    for (args, 0..) |arg, i| {');
  Lines.Add('        if (i > 0) buf.append(' + #39 + ',' + #39 + ') catch return HttpCallError.OutOfMemory;');
  Lines.Add('        switch (arg) {');
  Lines.Add('            .string => |s| {');
  Lines.Add('                buf.append(' + #39 + '"' + #39 + ') catch return HttpCallError.OutOfMemory;');
  Lines.Add('                for (s) |ch| {');
  Lines.Add('                    switch (ch) {');
  Lines.Add('                        ' + #39 + '"' + #39 + ' => buf.appendSlice("\\\"") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        ' + #39 + '\\' + #39 + ' => buf.appendSlice("\\\\") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        0x08 => buf.appendSlice("\\b") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        0x09 => buf.appendSlice("\\t") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        0x0A => buf.appendSlice("\\n") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        0x0C => buf.appendSlice("\\f") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        0x0D => buf.appendSlice("\\r") catch return HttpCallError.OutOfMemory,');
  Lines.Add('                        else => {');
  Lines.Add('                            if (ch < 0x20) {');
  Lines.Add('                                const hex = "0123456789abcdef";');
  Lines.Add('                                const esc = [_]u8{ ' + #39 + '\\' + #39 + ', ' + #39 + 'u' + #39 + ', ' + #39 + '0' + #39 + ', ' + #39 + '0' + #39 + ', hex[(ch >> 4) & 0xF], hex[ch & 0xF] };');
  Lines.Add('                                buf.appendSlice(&esc) catch return HttpCallError.OutOfMemory;');
  Lines.Add('                            } else buf.append(ch) catch return HttpCallError.OutOfMemory;');
  Lines.Add('                        },');
  Lines.Add('                    }');
  Lines.Add('                }');
  Lines.Add('                buf.append(' + #39 + '"' + #39 + ') catch return HttpCallError.OutOfMemory;');
  Lines.Add('            },');
  Lines.Add('            .integer => |v| {');
  Lines.Add('                var tmp: [32]u8 = undefined;');
  Lines.Add('                const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return HttpCallError.OutOfMemory;');
  Lines.Add('                buf.appendSlice(s) catch return HttpCallError.OutOfMemory;');
  Lines.Add('            },');
  Lines.Add('            .float => |v| {');
  Lines.Add('                var tmp: [64]u8 = undefined;');
  Lines.Add('                const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return HttpCallError.OutOfMemory;');
  Lines.Add('                buf.appendSlice(s) catch return HttpCallError.OutOfMemory;');
  Lines.Add('            },');
  Lines.Add('            else => return HttpCallError.InvalidResultType,');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    buf.append(' + #39 + ']' + #39 + ') catch return HttpCallError.OutOfMemory;');
  Lines.Add('    return alloc.dupe(u8, buf.items) catch return HttpCallError.OutOfMemory;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _buildOuterEnvelope(');
  Lines.Add('    alloc: std.mem.Allocator,');
  Lines.Add('    url: []const u8,');
  Lines.Add('    innerArgsArrayJson: []const u8,');
  Lines.Add('    timeoutSec: u32,');
  Lines.Add(') HttpCallError![]u8 {');
  Lines.Add('    return std.fmt.allocPrint(');
  Lines.Add('        alloc,');
  Lines.Add('        "{{\"url\":\"{s}\",\"method\":\"POST\",\"body\":{{\"args\":{s}}},\"timeout\":{d}}}",');
  Lines.Add('        .{ url, innerArgsArrayJson, timeoutSec },');
  Lines.Add('    ) catch return HttpCallError.OutOfMemory;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _postSync(');
  Lines.Add('    alloc: std.mem.Allocator,');
  Lines.Add('    url: []const u8,');
  Lines.Add('    innerArgsArrayJson: []const u8,');
  Lines.Add(') HttpCallError!std.json.Parsed(std.json.Value) {');
  Lines.Add('    _last_error.clear();');
  Lines.Add('');
  Lines.Add('    const envelope = try _buildOuterEnvelope(alloc, url, innerArgsArrayJson, DEFAULT_HTTP_TIMEOUT_SEC);');
  Lines.Add('    defer alloc.free(envelope);');
  Lines.Add('');
  Lines.Add('    if (DEBUG_LOG) {');
  Lines.Add('        std.debug.print("[zig-json-call] POST {s} envelope={s}\n", .{ url, envelope });');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    var data = lf.DataHandle.create(BRIDGE_API_NAME) catch {');
  Lines.Add('        _last_error.set(.lf_transport, -1, 0, "lf.DataHandle.create failed");');
  Lines.Add('        return HttpCallError.LfTransportFailed;');
  Lines.Add('    };');
  Lines.Add('    defer data.deinit();');
  Lines.Add('');
  Lines.Add('    lf.io.writeString(&data, envelope) catch {');
  Lines.Add('        _last_error.set(.lf_transport, -1, 0, "lf.io.writeString failed");');
  Lines.Add('        return HttpCallError.LfTransportFailed;');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    var resp = lf.framework.call(BRIDGE_APP_NAME, &data, BRIDGE_TIMEOUT_MS) catch |e| {');
  Lines.Add('        _last_error.set(.lf_transport, -1, 0, @errorName(e));');
  Lines.Add('        return HttpCallError.LfTransportFailed;');
  Lines.Add('    };');
  Lines.Add('    defer resp.deinit();');
  Lines.Add('');
  Lines.Add('    resp.setPosition(0) catch {};');
  Lines.Add('');
  Lines.Add('    const respJson = lf.io.readString(&resp, alloc) catch {');
  Lines.Add('        _last_error.set(.lf_transport, -1, 0, "lf.io.readString failed");');
  Lines.Add('        return HttpCallError.EmptyResponse;');
  Lines.Add('    };');
  Lines.Add('    defer alloc.free(respJson);');
  Lines.Add('');
  Lines.Add('    if (DEBUG_LOG) {');
  Lines.Add('        std.debug.print("[zig-json-call] response = {s}\n", .{respJson});');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (respJson.len == 0) {');
  Lines.Add('        _last_error.set(.empty_response, -1, 0, "bridge returned empty response");');
  Lines.Add('        return HttpCallError.EmptyResponse;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    const outer = std.json.parseFromSlice(');
  Lines.Add('        std.json.Value, alloc, respJson,');
  Lines.Add('        .{ .allocate = .alloc_always },');
  Lines.Add('    ) catch |e| {');
  Lines.Add('        _last_error.set(.invalid_envelope, -1, 0, @errorName(e));');
  Lines.Add('        return HttpCallError.InvalidEnvelope;');
  Lines.Add('    };');
  Lines.Add('    errdefer outer.deinit();');
  Lines.Add('');
  Lines.Add('    if (outer.value != .object) {');
  Lines.Add('        _last_error.set(.invalid_envelope, -1, 0, "outer envelope is not an object");');
  Lines.Add('        return HttpCallError.InvalidEnvelope;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (outer.value.object.get("body")) |body_v| {');
  Lines.Add('        if (body_v != .object) {');
  Lines.Add('            _last_error.set(.invalid_envelope, -1, 0, "body is not an object");');
  Lines.Add('            return HttpCallError.InvalidEnvelope;');
  Lines.Add('        }');
  Lines.Add('    } else {');
  Lines.Add('        _last_error.set(.missing_body, -1, 0, "envelope has no body field");');
  Lines.Add('        return HttpCallError.MissingBody;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    return outer;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _checkServiceCode(body_v: std.json.Value) HttpCallError!void {');
  Lines.Add('    if (body_v != .object) return HttpCallError.InvalidEnvelope;');
  Lines.Add('    const code_v = body_v.object.get("code") orelse {');
  Lines.Add('        _last_error.set(.missing_code, -1, 0, "body has no code field");');
  Lines.Add('        return HttpCallError.MissingCode;');
  Lines.Add('    };');
  Lines.Add('    const code: i32 = switch (code_v) {');
  Lines.Add('        .integer => |i| @intCast(i),');
  Lines.Add('        else => {');
  Lines.Add('            _last_error.set(.missing_code, -1, 0, "code is not an integer");');
  Lines.Add('            return HttpCallError.MissingCode;');
  Lines.Add('        },');
  Lines.Add('    };');
  Lines.Add('    if (code != 0) {');
  Lines.Add('        const msg: []const u8 = if (body_v.object.get("error")) |e| switch (e) {');
  Lines.Add('            .string => |s| s,');
  Lines.Add('            else => "unknown remote error",');
  Lines.Add('        } else "unknown remote error";');
  Lines.Add('        _last_error.set(.remote, code, 200, msg);');
  Lines.Add('        return HttpCallError.RemoteCallFailed;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _extractI64(body_v: std.json.Value) HttpCallError!i64 {');
  Lines.Add('    if (body_v != .object) return HttpCallError.InvalidResultType;');
  Lines.Add('    const v = body_v.object.get("result") orelse return HttpCallError.MissingResult;');
  Lines.Add('    return switch (v) {');
  Lines.Add('        .integer => |i| i,');
  Lines.Add('        .float => |f| @intFromFloat(f),');
  Lines.Add('        .number_string => |s| std.fmt.parseInt(i64, s, 10) catch return HttpCallError.InvalidResultType,');
  Lines.Add('        else => return HttpCallError.InvalidResultType,');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _extractF64(body_v: std.json.Value) HttpCallError!f64 {');
  Lines.Add('    if (body_v != .object) return HttpCallError.InvalidResultType;');
  Lines.Add('    const v = body_v.object.get("result") orelse return HttpCallError.MissingResult;');
  Lines.Add('    return switch (v) {');
  Lines.Add('        .float => |f| f,');
  Lines.Add('        .integer => |i| @floatFromInt(i),');
  Lines.Add('        .number_string => |s| std.fmt.parseFloat(f64, s) catch return HttpCallError.InvalidResultType,');
  Lines.Add('        else => return HttpCallError.InvalidResultType,');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn _extractString(alloc: std.mem.Allocator, body_v: std.json.Value) HttpCallError![]u8 {');
  Lines.Add('    if (body_v != .object) return HttpCallError.InvalidResultType;');
  Lines.Add('    const v = body_v.object.get("result") orelse return HttpCallError.MissingResult;');
  Lines.Add('    return switch (v) {');
  Lines.Add('        .string => |s| alloc.dupe(u8, s) catch return HttpCallError.OutOfMemory,');
  Lines.Add('        else => return HttpCallError.InvalidResultType,');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitZigFunction(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl, ArgCallList: TP_String;
  Description, ReturnPart, FieldKind: TP_String;
  HasParams, IsStringReturn: boolean;
  i: integer;
  PName: TP_String;
begin
  ParamDecl := BuildZigParamDecl(F.Params);
  ArgCallList := BuildZigCallArgList(F.Params);
  HasParams := Length(F.Params) > 0;
  if F.IsFunction then
  begin
    ReturnPart := ABI_Type_To_Zig_Return(F.ReturnType);
    IsStringReturn := ABI_Type_Is_String(F.ReturnType);
  end
  else
  begin
    ReturnPart := 'void';
    IsStringReturn := False;
  end;
  Description := GetFullDescription(F.Comment);
  if Description.Len = 0 then Description := 'HTTP/JSON API: ' + ApiName;

  // ---- Sync ----
  Lines.Add('/// ' + Description.Text);
  Lines.Add('///');
  Lines.Add('/// HTTP route: `POST /' + ApiName.Text + '` (through bridge.py).');
  if HasParams then
    Lines.Add('pub fn ' + ApiName.Text + '(' + ParamDecl.Text + ') HttpCallError!' + ReturnPart.Text + ' {')
  else
    Lines.Add('pub fn ' + ApiName.Text + '() HttpCallError!' + ReturnPart.Text + ' {');
  Lines.Add('    const __lf_alloc = std.heap.page_allocator;');
  if HasParams then
  begin
    Lines.Add('    const __lf_args = [_]std.json.Value{');
    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafeZigIdent(F.Params[i].Name, i);
      if ABI_Type_Is_String(F.Params[i].PascalType) then FieldKind := 'string'
      else if ABI_Type_Is_Float(F.Params[i].PascalType) then FieldKind := 'float'
      else FieldKind := 'integer';
      Lines.Add('        .{ .' + FieldKind.Text + ' = ' + PName.Text + ' },');
    end;
    Lines.Add('    };');
    Lines.Add('    const __lf_inner = try _buildArgsArray(__lf_alloc, &__lf_args);');
    Lines.Add('    defer __lf_alloc.free(__lf_inner);');
  end
  else
  begin
    Lines.Add('    const __lf_inner = try __lf_alloc.dupe(u8, "[]");');
    Lines.Add('    defer __lf_alloc.free(__lf_inner);');
  end;
  Lines.Add('    const __lf_url = std.fmt.allocPrint(__lf_alloc, "{s}/' + ApiName.Text + '", .{HTTP_CALL_BASE_URL}) catch return HttpCallError.OutOfMemory;');
  Lines.Add('    defer __lf_alloc.free(__lf_url);');
  Lines.Add('    const __lf_outer = try _postSync(__lf_alloc, __lf_url, __lf_inner);');
  Lines.Add('    defer __lf_outer.deinit();');
  Lines.Add('    const __lf_body = __lf_outer.value.object.get("body") orelse return HttpCallError.MissingBody;');
  Lines.Add('    try _checkServiceCode(__lf_body);');
  if not F.IsFunction then
    Lines.Add('    // void API')
  else if IsStringReturn then
    Lines.Add('    return _extractString(__lf_alloc, __lf_body);')
  else if ABI_Type_Is_Float(F.ReturnType) then
    Lines.Add('    return _extractF64(__lf_body);')
  else
    Lines.Add('    return _extractI64(__lf_body);');
  Lines.Add('}');
  Lines.Add('');

  // ---- Result union ----
  Lines.Add('pub const ' + ApiName.Text + '_Result = union(enum) {');
  if F.IsFunction then Lines.Add('    ok: ' + ReturnPart.Text + ',') else Lines.Add('    ok: void,');
  Lines.Add('    err: HttpCallError,');
  Lines.Add('};');
  Lines.Add('');

  // ---- Async context ----
  Lines.Add('const _' + ApiName.Text + 'AsyncCtx = struct {');
  Lines.Add('    user_ctx: ?*anyopaque,');
  Lines.Add('    handler: *const fn (?*anyopaque, ' + ApiName.Text + '_Result) void,');
  Lines.Add('};');
  Lines.Add('');

  // ---- Async trampoline ----
  Lines.Add('fn _' + ApiName.Text + 'AsyncTrampoline(__lf_ctx: ?*anyopaque, __lf_result: lf.async_call.AsyncResult) void {');
  Lines.Add('    const __lf_c: *_' + ApiName.Text + 'AsyncCtx = @ptrCast(@alignCast(__lf_ctx orelse return));');
  Lines.Add('    const __lf_user_ctx = __lf_c.user_ctx;');
  Lines.Add('    const __lf_handler = __lf_c.handler;');
  Lines.Add('    const __lf_alloc = std.heap.page_allocator;');
  Lines.Add('    __lf_alloc.destroy(__lf_c);');
  Lines.Add('');
  Lines.Add('    switch (__lf_result) {');
  Lines.Add('        .ok => |h| {');
  Lines.Add('            var __lf_handle = h;');
  Lines.Add('            __lf_handle.setPosition(0) catch {};');
  Lines.Add('            const __lf_resp_json = lf.io.readString(&__lf_handle, __lf_alloc) catch {');
  Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = HttpCallError.EmptyResponse });');
  Lines.Add('                return;');
  Lines.Add('            };');
  Lines.Add('            defer __lf_alloc.free(__lf_resp_json);');
  Lines.Add('');
  Lines.Add('            if (__lf_resp_json.len == 0) {');
  Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = HttpCallError.EmptyResponse });');
  Lines.Add('                return;');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            const __lf_outer = std.json.parseFromSlice(std.json.Value, __lf_alloc, __lf_resp_json, .{ .allocate = .alloc_always }) catch {');
  Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = HttpCallError.InvalidEnvelope });');
  Lines.Add('                return;');
  Lines.Add('            };');
  Lines.Add('            defer __lf_outer.deinit();');
  Lines.Add('');
  Lines.Add('            if (__lf_outer.value != .object) {');
  Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = HttpCallError.InvalidEnvelope });');
  Lines.Add('                return;');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            const __lf_body = __lf_outer.value.object.get("body") orelse {');
  Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = HttpCallError.MissingBody });');
  Lines.Add('                return;');
  Lines.Add('            };');
  Lines.Add('');
  Lines.Add('            _checkServiceCode(__lf_body) catch |e| {');
  Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = e });');
  Lines.Add('                return;');
  Lines.Add('            };');
  Lines.Add('');
  if not F.IsFunction then
    Lines.Add('            __lf_handler(__lf_user_ctx, .{ .ok = {} });')
  else if IsStringReturn then
  begin
    Lines.Add('            const __lf_v = _extractString(__lf_alloc, __lf_body) catch |e| {');
    Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = e });');
    Lines.Add('                return;');
    Lines.Add('            };');
    Lines.Add('            __lf_handler(__lf_user_ctx, .{ .ok = __lf_v });');
    Lines.Add('            __lf_alloc.free(__lf_v);');
  end
  else if ABI_Type_Is_Float(F.ReturnType) then
  begin
    Lines.Add('            const __lf_v = _extractF64(__lf_body) catch |e| {');
    Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = e });');
    Lines.Add('                return;');
    Lines.Add('            };');
    Lines.Add('            __lf_handler(__lf_user_ctx, .{ .ok = __lf_v });');
  end
  else
  begin
    Lines.Add('            const __lf_v = _extractI64(__lf_body) catch |e| {');
    Lines.Add('                __lf_handler(__lf_user_ctx, .{ .err = e });');
    Lines.Add('                return;');
    Lines.Add('            };');
    Lines.Add('            __lf_handler(__lf_user_ctx, .{ .ok = __lf_v });');
  end;
  Lines.Add('        },');
  Lines.Add('        .err => |e| {');
  Lines.Add('            _last_error.set(.lf_transport, -1, 0, @errorName(e));');
  Lines.Add('            __lf_handler(__lf_user_ctx, .{ .err = HttpCallError.LfTransportFailed });');
  Lines.Add('        },');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');

  // ---- Public async ----
  Lines.Add('/// ' + Description.Text + ' (asynchronous)');
  Lines.Add('/// The handler runs on the LingoFuse async worker thread.');
  if IsStringReturn then
    Lines.Add('/// The ok payload is freed automatically after the handler returns.');
  if HasParams then
    Lines.Add('pub fn ' + ApiName.Text + '_async(' + ParamDecl.Text +
      ', user_ctx: ?*anyopaque, handler: *const fn (?*anyopaque, ' +
      ApiName.Text + '_Result) void) HttpCallError!void {')
  else
    Lines.Add('pub fn ' + ApiName.Text + '_async(user_ctx: ?*anyopaque, handler: *const fn (?*anyopaque, ' +
      ApiName.Text + '_Result) void) HttpCallError!void {');
  Lines.Add('    const __lf_alloc = std.heap.page_allocator;');
  if HasParams then
  begin
    Lines.Add('    const __lf_args = [_]std.json.Value{');
    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafeZigIdent(F.Params[i].Name, i);
      if ABI_Type_Is_String(F.Params[i].PascalType) then FieldKind := 'string'
      else if ABI_Type_Is_Float(F.Params[i].PascalType) then FieldKind := 'float'
      else FieldKind := 'integer';
      Lines.Add('        .{ .' + FieldKind.Text + ' = ' + PName.Text + ' },');
    end;
    Lines.Add('    };');
    Lines.Add('    const __lf_inner = _buildArgsArray(__lf_alloc, &__lf_args) catch return HttpCallError.OutOfMemory;');
    Lines.Add('    defer __lf_alloc.free(__lf_inner);');
  end
  else
  begin
    Lines.Add('    const __lf_inner = __lf_alloc.dupe(u8, "[]") catch return HttpCallError.OutOfMemory;');
    Lines.Add('    defer __lf_alloc.free(__lf_inner);');
  end;
  Lines.Add('    const __lf_url = std.fmt.allocPrint(__lf_alloc, "{s}/' + ApiName.Text + '", .{HTTP_CALL_BASE_URL}) catch return HttpCallError.OutOfMemory;');
  Lines.Add('    defer __lf_alloc.free(__lf_url);');
  Lines.Add('    const __lf_envelope = _buildOuterEnvelope(__lf_alloc, __lf_url, __lf_inner, DEFAULT_HTTP_TIMEOUT_SEC) catch return HttpCallError.OutOfMemory;');
  Lines.Add('    defer __lf_alloc.free(__lf_envelope);');
  Lines.Add('');
  Lines.Add('    const __lf_ctx = __lf_alloc.create(_' + ApiName.Text + 'AsyncCtx) catch return HttpCallError.OutOfMemory;');
  Lines.Add('    __lf_ctx.* = .{ .user_ctx = user_ctx, .handler = handler };');
  Lines.Add('');
  Lines.Add('    var __lf_data = lf.DataHandle.create(BRIDGE_API_NAME) catch {');
  Lines.Add('        __lf_alloc.destroy(__lf_ctx);');
  Lines.Add('        return HttpCallError.LfTransportFailed;');
  Lines.Add('    };');
  Lines.Add('    defer __lf_data.deinit();');
  Lines.Add('');
  Lines.Add('    lf.io.writeString(&__lf_data, __lf_envelope) catch {');
  Lines.Add('        __lf_alloc.destroy(__lf_ctx);');
  Lines.Add('        return HttpCallError.LfTransportFailed;');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    lf.async_call.callAsync(BRIDGE_APP_NAME, &__lf_data, @ptrCast(__lf_ctx), _' + ApiName.Text + 'AsyncTrampoline) catch {');
  Lines.Add('        return HttpCallError.LfTransportFailed;');
  Lines.Add('    };');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPCallZigCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
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
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);
    EmitZigHeader(Lines, UnitName);
    EmitZigConfig(Lines, BaseUrl);
    EmitZigBridgeDiag(Lines);
    EmitZigErrorModel(Lines);
    EmitZigTransport(Lines);
    for i := 0 to High(SupportedFuncs) do EmitZigFunction(Lines, SupportedFuncs[i], ApiNames[i]);
    Result := Lines;
    Log(PFormat('Generated %d lines, %d routines.', [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry('zig', 'Zig HTTP/JSON call code',
    asCall, akCallCode, '_http_json_call_zig.zig', False, @GenerateHTTPCallZigCode);
end.
