unit zig_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceZigCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[zig_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[zig_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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
  else if IsStringABIType(T) then Result := '[]const u8'
  else Result := '';
end;

function ABI_Type_Default_Expr(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := '""'
  else if T.Same('single') or T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else
    Result := '0';
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
  if Comment.Len = 0 then Exit;
  i := 1;
  while i <= Comment.Len do
  begin
    j := i;
    while (j <= Comment.Len) and (Comment[j] <> #10) and (Comment[j] <> #13) do
      Inc(j);
    if j > i then
    begin
      Line := StripCommentMarkers(Comment.GetString(i, j));
      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
        end
        else
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

procedure EmitErrorHelpers(Lines: TPascalStringList);
begin
  Lines.Add('fn w_err(out_: *lf.DataHandle, msg: []const u8) void {');
  Lines.Add('    out_.writeBytes(&[_]u8{STATUS_ERROR}) catch return;');
  Lines.Add('    out_.writeString(msg) catch return;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitInternalCallStub(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String; const F: TFunctionStructure);
var
  i: integer;
  ParamParts, IgnoreBody: TP_String;
  ParamName, TypeDecl: TP_String;
begin
  ParamParts := '_uid: lf.Uid, _p2p_name: []const u8';
  IgnoreBody := '    _ = _uid;' + #13#10 + '    _ = _p2p_name;';
  for i := 0 to High(F.Params) do
  begin
    ParamName := MakeSafeZigIdent(F.Params[i].Name, i);
    TypeDecl := ABI_Type_To_Zig_Decl(F.Params[i].PascalType);
    ParamParts := ParamParts + ', ' + ParamName + ': ' + TypeDecl;
    IgnoreBody := IgnoreBody + #13#10 + '    _ = ' + ParamName + ';';
  end;

  if F.IsFunction then
  begin
    Lines.Add('pub fn internal_call_' + ZigIdent + '(' + ParamParts + ') !' +
      ABI_Type_To_Zig_Decl(F.ReturnType) + ' {');
    Lines.Add(IgnoreBody);
    Lines.Add('    return ' + ABI_Type_Default_Expr(F.ReturnType) + ';');
    Lines.Add('}');
  end
  else
  begin
    Lines.Add('pub fn internal_call_' + ZigIdent + '(' + ParamParts + ') !void {');
    Lines.Add(IgnoreBody);
    Lines.Add('}');
  end;
  Lines.Add('');
end;

procedure EmitReadParamLines(Lines: TPascalStringList;
  const ParamName, PascalType: TP_String; HasOut: boolean);
var
  TypeDecl: TP_String;
begin
  TypeDecl := ABI_Type_To_Zig_Decl(PascalType);
  if IsStringABIType(PascalType) then
  begin
    Lines.Add('    const ' + ParamName + ' = lf.io.readString(in_, alloc) catch |e| {');
    if HasOut then
    begin
      Lines.Add('        w_err(out_, ' + ZigStrLit('input truncated: ' + ParamName) + ');');
      Lines.Add('        return e;');
    end
    else
      Lines.Add('        return e;');
    Lines.Add('    };');
    Lines.Add('    defer alloc.free(' + ParamName + ');');
    Exit;
  end;

  Lines.Add('    var ' + ParamName + ': ' + TypeDecl + ' = ' +
    ABI_Type_Default_Expr(PascalType) + ';');
  Lines.Add('    if (!try in_.read(&' + ParamName + ')) {');
  if HasOut then
  begin
    Lines.Add('        w_err(out_, ' + ZigStrLit('input truncated: ' + ParamName) + ');');
    Lines.Add('        return error.ReadFailed;');
  end
  else
    Lines.Add('        return error.ReadFailed;');
  Lines.Add('    }');
end;

procedure EmitWriteResultLines(Lines: TPascalStringList;
  const VarName, PascalType: TP_String);
begin
  Lines.Add('    try out_.writeBytes(&[_]u8{STATUS_OK});');
  if IsStringABIType(PascalType) then
    Lines.Add('    try out_.writeString(' + VarName + ');')
  else
    Lines.Add('    try out_.write(' + VarName + ');');
end;

procedure EmitCallbackImplementation(Lines: TPascalStringList;
  const ApiName, ZigIdent: TP_String; const F: TFunctionStructure);
var
  i: integer;
  IsCall: boolean;
  ParamName, ArgList: TP_String;
begin
  IsCall := F.IsFunction;

  if IsCall then
    Lines.Add('fn callback_' + ZigIdent +
      '(_ctx: ?*anyopaque, in_: *lf.DataHandle, out_: *lf.DataHandle) lf.Error!void {')
  else
    Lines.Add('fn callback_' + ZigIdent +
      '(_ctx: ?*anyopaque, in_: *lf.DataHandle) lf.Error!void {');

  Lines.Add('    _ = _ctx;');
  Lines.Add('    const uid = in_.p2pUid() catch lf.Uid.NULL;');
  Lines.Add('    const alloc = std.heap.page_allocator;');
  Lines.Add('    const p2p_z = in_.p2pName(alloc) catch |e| return e;');
  Lines.Add('    defer alloc.free(p2p_z);');
  Lines.Add('');

  for i := 0 to High(F.Params) do
  begin
    ParamName := MakeSafeZigIdent(F.Params[i].Name, i);
    EmitReadParamLines(Lines, ParamName, F.Params[i].PascalType, IsCall);
  end;

  ArgList := 'uid, p2p_z';
  for i := 0 to High(F.Params) do
  begin
    ParamName := MakeSafeZigIdent(F.Params[i].Name, i);
    ArgList := ArgList + ', ' + ParamName;
  end;

  if IsCall then
  begin
    Lines.Add('');
    Lines.Add('    const result = internal_call_' + ZigIdent + '(' + ArgList +
      ') catch |e| {');
    Lines.Add('        w_err(out_, @errorName(e));');
    Lines.Add('        return e;');
    Lines.Add('    };');
    Lines.Add('');
    EmitWriteResultLines(Lines, 'result', F.ReturnType);
  end
  else
  begin
    Lines.Add('');
    Lines.Add('    internal_call_' + ZigIdent + '(' + ArgList + ') catch |e| return e;');
  end;

  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRegisterAll(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames, ZigIdents: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  Desc, ApiName, ZigIdent: TP_String;
  RegFn: TP_String;
begin
  Lines.Add('pub fn registerAllAbiApis(app: *lf.AppHandle) !void {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ZigIdent := ZigIdents[i];
    Desc := GetFullDescription(F.Comment);
    if Desc.Len = 0 then
      Desc := 'ABI api for ' + F.Name;
    if F.IsFunction then RegFn := 'registerCall' else RegFn := 'registerNotify';
    Lines.Add('    try app.' + RegFn + '(' + ZigStrLit(ApiName) + ', ' +
      ZigStrLit(Desc) + ', null, callback_' + ZigIdent + ');');
  end;
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn registerAllP2pAbiApis() !void {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ZigIdent := ZigIdents[i];
    Desc := GetFullDescription(F.Comment);
    if Desc.Len = 0 then
      Desc := 'ABI api for ' + F.Name;
    if F.IsFunction then RegFn := 'registerP2PCall' else RegFn := 'registerP2PNotify';
    Lines.Add('    try lf.p2p.' + RegFn + '(' + ZigStrLit(ApiName) + ', ' +
      ZigStrLit(Desc) + ', null, callback_' + ZigIdent + ');');
  end;
  Lines.Add('}');
  Lines.Add('');

  Lines.Add('pub fn createAndRegisterAbiApp() !lf.AppHandle {');
  Lines.Add('    var app = try lf.AppHandle.create(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
  Lines.Add('    errdefer app.deinit();');
  Lines.Add('    try registerAllAbiApis(&app);');
  Lines.Add('    return app;');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceZigCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames, UsedZigIdents: TPascalStringList;
  ApiName, ZigIdent: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceZigCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceZigCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Zig ABI service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  UsedZigIdents := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      ZigIdent := ApiName;
      if UsedZigIdents.IndexOf(ZigIdent) >= 0 then
      begin
        j := 1;
        while UsedZigIdents.IndexOf(ZigIdent + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ZigIdent := ZigIdent + '_' + umlIntToStr(j).Text;
      end;
      UsedZigIdents.Add(ZigIdent);
    end;

    Lines.Add('const std = @import("std");');
    Lines.Add('const lf = @import("lingofuse");');
    Lines.Add('const data = lf.DataHandle;');
    Lines.Add('');
    Lines.Add('pub const DEFAULT_APP_NAME: [:0]const u8 = ' + ZigStrLit(AppName) + ';');
    Lines.Add('pub const DEFAULT_APP_DESC: [:0]const u8 = ' + ZigStrLit(AppDesc) + ';');
    Lines.Add('');
    Lines.Add('const STATUS_OK: u8 = 0x00;');
    Lines.Add('const STATUS_ERROR: u8 = 0xFF;');
    Lines.Add('');
    EmitErrorHelpers(Lines);

    for i := 0 to High(SupportedFuncs) do
      EmitInternalCallStub(Lines, UsedApiNames[i], UsedZigIdents[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
      EmitCallbackImplementation(Lines, UsedApiNames[i], UsedZigIdents[i], SupportedFuncs[i]);

    EmitRegisterAll(Lines, SupportedFuncs, UsedApiNames, UsedZigIdents);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    UsedZigIdents.Free;
  end;
end;

initialization

  RegisterGenerator(
    'zig',
    'xxx_abi_service.zig',
    gkService,
    'Zig ABI service implementation',
    @GenerateABIServiceZigCode);

end.
