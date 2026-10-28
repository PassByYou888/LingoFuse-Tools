unit ts_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Ts_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'number'
  else if T.Same('int64') then Result := 'bigint'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'number'
  else if T.Same('word') then Result := 'number'
  else if T.Same('smallint') then Result := 'number'
  else if T.Same('byte') then Result := 'number'
  else if T.Same('uint64') then Result := 'bigint'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'number'
  else if T.Same('single') then Result := 'number'
  else if IsStringABIType(T) then Result := 'string'
  else Result := '';
end;

function ABI_Type_To_Ts_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then Result := '""'
  else if T.Same('int64') or T.Same('uint64') then Result := '0n'
  else if T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real') then Result := '0.0'
  else Result := '0';
end;

function ABI_Type_To_Ts_Write_Fn(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'writeInt32'
  else if T.Same('int64') then Result := 'writeInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'writeUInt32'
  else if T.Same('word') then Result := 'writeUInt16'
  else if T.Same('smallint') then Result := 'writeInt16'
  else if T.Same('byte') then Result := 'writeUInt8'
  else if T.Same('uint64') then Result := 'writeUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'writeDouble'
  else if T.Same('single') then Result := 'writeSingle'
  else if IsStringABIType(T) then Result := 'writeString'
  else Result := '';
end;

function ABI_Type_To_Ts_Read_Fn(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'readInt32'
  else if T.Same('int64') then Result := 'readInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'readUInt32'
  else if T.Same('word') then Result := 'readUInt16'
  else if T.Same('smallint') then Result := 'readInt16'
  else if T.Same('byte') then Result := 'readUInt8'
  else if T.Same('uint64') then Result := 'readUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'readDouble'
  else if T.Same('single') then Result := 'readSingle'
  else if IsStringABIType(T) then Result := 'readString'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Ts_Write_Fn(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function MakeTsParamName(const Name: TP_String; Index: integer): TP_String;
begin
  if Name.Len = 0 then
    Result := '_arg' + umlIntToStr(Index).Text
  else
    Result := '_arg_' + Name.Text;
end;

function TsStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
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
    begin
      Code := Ord(c);
      if Code < 32 then
      begin
        Result.Append('\');
        Result.Append('x');
        if Code < 16 then
        begin
          Result.Append('0');
          Result.Append(TP_String(IntToHex(Code, 1)));
        end
        else
          Result.Append(TP_String(IntToHex(Code, 2)));
      end
      else
        Result.Append(c);
    end;
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
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);
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

function BuildTsInternalCallParamList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + MakeTsParamName(Params[i].Name, i) + ': ' + ABI_Type_To_Ts_Decl(Params[i].PascalType);
  end;
end;

function BuildTsInternalCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + MakeTsParamName(Params[i].Name, i);
  end;
end;

procedure EmitInternalCallStub(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
begin
  if F.IsFunction then
  begin
    Lines.Add('export function internal_call_' + ApiName + '(' +
      BuildTsInternalCallParamList(F.Params) + '): ' +
      ABI_Type_To_Ts_Decl(F.ReturnType) + ' {');
    Lines.Add('    return ' + ABI_Type_To_Ts_Default(F.ReturnType) + ';');
    Lines.Add('}');
  end
  else
  begin
    Lines.Add('export function internal_call_' + ApiName + '(' +
      BuildTsInternalCallParamList(F.Params) + '): void {');
    Lines.Add('}');
  end;
  Lines.Add('');
end;

procedure EmitCallbackFunction(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn, WriteFn: TP_String;
begin
  Lines.Add('export function Cb_' + ApiName + '(_trigger: unknown, input: unknown, output: unknown): void {');
  Lines.Add('    const _inH = lf.DataHandle.fromRaw(input, false);');
  Lines.Add('    const _outH = lf.DataHandle.fromRaw(output, false);');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeTsParamName(F.Params[i].Name, i);
    Lines.Add('    let ' + PName + ': ' + ABI_Type_To_Ts_Decl(F.Params[i].PascalType) + ';');
  end;
  Lines.Add('    try {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeTsParamName(F.Params[i].Name, i);
    ReadFn := ABI_Type_To_Ts_Read_Fn(F.Params[i].PascalType);
    Lines.Add('        ' + PName + ' = _inH.' + ReadFn + '();');
  end;
  Lines.Add('    } catch (_e) {');
  Lines.Add('        _safeWriteError(_outH, "input truncated: ' + ApiName.Text + '");');
  Lines.Add('        return;');
  Lines.Add('    }');
  Lines.Add('    let _ret: ' + ABI_Type_To_Ts_Decl(F.ReturnType) + ';');
  Lines.Add('    try {');
  Lines.Add('        _ret = internal_call_' + ApiName + '(' + BuildTsInternalCallArgList(F.Params) + ');');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        _safeWriteError(_outH, (_e instanceof Error) ? _e.message : String(_e));');
  Lines.Add('        return;');
  Lines.Add('    }');
  WriteFn := ABI_Type_To_Ts_Write_Fn(F.ReturnType);
  Lines.Add('    try {');
  Lines.Add('        _outH.writeUInt8(STATUS_OK);');
  Lines.Add('        _outH.' + WriteFn + '(_ret);');
  Lines.Add('    } catch (_e) {');
  Lines.Add('        _safeWriteError(_outH, (_e instanceof Error) ? _e.message : String(_e));');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackProcedure(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn: TP_String;
begin
  Lines.Add('export function Cb_' + ApiName + '(_trigger: unknown, input: unknown): void {');
  Lines.Add('    const _inH = lf.DataHandle.fromRaw(input, false);');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeTsParamName(F.Params[i].Name, i);
    Lines.Add('    let ' + PName + ': ' + ABI_Type_To_Ts_Decl(F.Params[i].PascalType) + ';');
  end;
  Lines.Add('    try {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeTsParamName(F.Params[i].Name, i);
    ReadFn := ABI_Type_To_Ts_Read_Fn(F.Params[i].PascalType);
    Lines.Add('        ' + PName + ' = _inH.' + ReadFn + '();');
  end;
  Lines.Add('    } catch (_e) {');
  Lines.Add('        return;');
  Lines.Add('    }');
  Lines.Add('    try {');
  Lines.Add('        internal_call_' + ApiName + '(' + BuildTsInternalCallArgList(F.Params) + ');');
  Lines.Add('    } catch (_e) {');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, Desc: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  Log(PFormat('Generating TypeScript ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('import * as lf from "lingofuse-ts";');
    Lines.Add('import { getBinding } from "lingofuse-ts";');
    Lines.Add('');
    Lines.Add('const _binding = (lf as any)._binding;');
    Lines.Add('const koffi = _binding.koffi;');
    Lines.Add('const LfCallFuncPtr = _binding.LfCallFuncPtr;');
    Lines.Add('const LfNotifyFuncPtr = _binding.LfNotifyFuncPtr;');
    Lines.Add('const funcs = getBinding().funcs;');
    Lines.Add('');
    Lines.Add('const STATUS_OK = 0x00;');
    Lines.Add('const STATUS_ERROR = 0xFF;');
    Lines.Add('');
    Lines.Add('function _safeWriteError(outH: lf.DataHandle, msg: string): void {');
    Lines.Add('    try {');
    Lines.Add('        outH.size = 0;');
    Lines.Add('        outH.position = 0;');
    Lines.Add('        outH.writeUInt8(STATUS_ERROR);');
    Lines.Add('        outH.writeString(msg);');
    Lines.Add('    } catch (_) {');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    UsedApiNames.Clear;
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
      EmitInternalCallStub(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
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

      if F.IsFunction then
        EmitCallbackFunction(Lines, ApiName, F)
      else
        EmitCallbackProcedure(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
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

      if F.IsFunction then
        Lines.Add('export const cb_' + ApiName + ' = koffi.register(Cb_' + ApiName + ', LfCallFuncPtr);')
      else
        Lines.Add('export const cb_' + ApiName + ' = koffi.register(Cb_' + ApiName + ', LfNotifyFuncPtr);');
    end;
    Lines.Add('');

    Lines.Add('export function registerAll(app: unknown): number {');
    Lines.Add('    if (app === null || app === undefined) return -1;');
    Lines.Add('    let _failed = 0;');
    UsedApiNames.Clear;
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

      Desc := GetFullDescription(F.Comment);
      if Desc.Len = 0 then
        Desc := 'ABI api for ' + F.Name;

      if F.IsFunction then
        Lines.Add('    if (funcs.LF_RegisterCall(app, ' + TsStrLit(ApiName) +
          ', ' + TsStrLit(Desc) + ', null, cb_' + ApiName + ') !== 1) ++_failed;')
      else
        Lines.Add('    if (funcs.LF_RegisterNotify(app, ' + TsStrLit(ApiName) +
          ', ' + TsStrLit(Desc) + ', null, cb_' + ApiName + ') !== 1) ++_failed;');
    end;
    Lines.Add('    return _failed;');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('export function registerAllP2P(): number {');
    Lines.Add('    let _failed = 0;');
    UsedApiNames.Clear;
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

      Desc := GetFullDescription(F.Comment);
      if Desc.Len = 0 then
        Desc := 'ABI api for ' + F.Name;

      if F.IsFunction then
        Lines.Add('    if (funcs.LF_Register_P2P_Call(' + TsStrLit(ApiName) +
          ', ' + TsStrLit(Desc) + ', null, cb_' + ApiName + ') !== 1) ++_failed;')
      else
        Lines.Add('    if (funcs.LF_Register_P2P_Notify(' + TsStrLit(ApiName) +
          ', ' + TsStrLit(Desc) + ', null, cb_' + ApiName + ') !== 1) ++_failed;');
    end;
    Lines.Add('    return _failed;');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the TypeScript service implementation.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'http_ts',
    'xxx_abi_service.ts',
    gkService,
    'TypeScript ABI service implementation',
    @GenerateABIServiceTypeScriptCode);

end.
