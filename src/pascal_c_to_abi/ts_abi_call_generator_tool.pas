unit ts_abi_call_generator_tool;

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

function GenerateABICallTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function IsInt64ABIType(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
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

function BuildTsParamDecl(const LeadType, LeadName: TP_String; const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  if LeadType <> '' then
    Result := LeadName + ': ' + LeadType;
  for i := 0 to High(Params) do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + MakeTsParamName(Params[i].Name, i) + ': ' +
      ABI_Type_To_Ts_Decl(Params[i].PascalType);
  end;
end;

procedure EmitWriteParams(Lines: TPascalStringList; const Params: TParamArray; const Indent: string);
var
  i: integer;
begin
  for i := 0 to High(Params) do
    Lines.Add(Indent + 'param.' + ABI_Type_To_Ts_Write_Fn(Params[i].PascalType) + '(' +
      MakeTsParamName(Params[i].Name, i) + ');');
end;

procedure EmitSyncCallFunction(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const FuncName: TP_String;
  const UidFirst: boolean;
  const P2PFirst: boolean;
  const CallFnName: TP_String);
var
  ParamDecl, RawArgExpr, RetType: TP_String;
begin
  if UidFirst then
    ParamDecl := BuildTsParamDecl('Uint8Array | string', 'uid', F.Params)
  else if P2PFirst then
    ParamDecl := BuildTsParamDecl('string', 'p2pName', F.Params)
  else
    ParamDecl := BuildTsParamDecl('', '', F.Params);

  RetType := ABI_Type_To_Ts_Decl(F.ReturnType);

  Lines.Add('export function ' + FuncName + '(' + ParamDecl + '): ' + RetType + ' {');
  Lines.Add('    const param = new DataHandle(' + TsStrLit(ApiName) + ');');
  Lines.Add('    try {');
  EmitWriteParams(Lines, F.Params, '        ');

  if UidFirst then
    Lines.Add('        const uidArg = _wrapUid(uid);');

  if UidFirst then
    RawArgExpr := 'funcs.' + CallFnName + '(uidArg, param.raw, BigInt(_abiTimeout))'
  else if P2PFirst then
    RawArgExpr := 'funcs.' + CallFnName + '(p2pName, param.raw, BigInt(_abiTimeout))'
  else
    RawArgExpr := 'funcs.' + CallFnName + '(_abiTargetApp, param.raw, BigInt(_abiTimeout))';

  Lines.Add('        const raw = ' + RawArgExpr + ';');
  Lines.Add('        if (raw === null || raw === undefined) {');
  Lines.Add('            throw new Error(' + TsStrLit(CallFnName + ' returned null handle') + ');');
  Lines.Add('        }');
  Lines.Add('        const res = DataHandle.fromRaw(raw, true);');
  Lines.Add('        try {');
  Lines.Add('            return _readSyncReply<' + RetType + '>(' + TsStrLit(ApiName) +
    ', res, (r) => r.' + ABI_Type_To_Ts_Read_Fn(F.ReturnType) + '());');
  Lines.Add('        } finally {');
  Lines.Add('            res.dispose();');
  Lines.Add('        }');
  Lines.Add('    } finally {');
  Lines.Add('        param.dispose();');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitAsyncCallFunction(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const FuncName: TP_String;
  const UidFirst: boolean;
  const P2PFirst: boolean;
  const CallFnName: TP_String);
var
  ParamDecl, IssueExpr, RetType: TP_String;
begin
  if UidFirst then
    ParamDecl := BuildTsParamDecl('Uint8Array | string', 'uid', F.Params)
  else if P2PFirst then
    ParamDecl := BuildTsParamDecl('string', 'p2pName', F.Params)
  else
    ParamDecl := BuildTsParamDecl('', '', F.Params);

  RetType := ABI_Type_To_Ts_Decl(F.ReturnType);

  Lines.Add('export function ' + FuncName + '(' + ParamDecl + '): CallPromise<' + RetType + '> {');
  Lines.Add('    const param = new DataHandle(' + TsStrLit(ApiName) + ');');
  Lines.Add('    let promise: CallPromise<' + RetType + '>;');
  Lines.Add('    try {');
  EmitWriteParams(Lines, F.Params, '        ');

  if UidFirst then
    Lines.Add('        const uidArg = _wrapUid(uid);');

  if UidFirst then
    IssueExpr := 'funcs.' + CallFnName + '(uidArg, param.raw, op.dataPtr, cb)'
  else if P2PFirst then
    IssueExpr := 'funcs.' + CallFnName + '(p2pName, param.raw, op.dataPtr, cb)'
  else
    IssueExpr := 'funcs.' + CallFnName + '(_abiTargetApp, param.raw, op.dataPtr, cb)';

  Lines.Add('        promise = runAsyncWithPromise<' + RetType + '>(');
  Lines.Add('            (cb, op) => ' + IssueExpr + ',');
  Lines.Add('            (rawResult) => _readAsyncReply<' + RetType + '>(' +
    TsStrLit(ApiName) + ', rawResult, (r) => r.' +
    ABI_Type_To_Ts_Read_Fn(F.ReturnType) + '()),');
  Lines.Add('            _abiTimeout');
  Lines.Add('        );');
  Lines.Add('    } catch (err) {');
  Lines.Add('        try { param.dispose(); } catch (_e) { }');
  Lines.Add('        throw err;');
  Lines.Add('    }');
  Lines.Add('    promise.then(');
  Lines.Add('        () => { try { param.dispose(); } catch (_e) { } },');
  Lines.Add('        () => { try { param.dispose(); } catch (_e) { } }');
  Lines.Add('    );');
  Lines.Add('    return promise;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNotifyFunction(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure;
  const FuncName: TP_String;
  const UidFirst: boolean;
  const P2PFirst: boolean;
  const CallFnName: TP_String);
var
  ParamDecl, CallExpr: TP_String;
begin
  if UidFirst then
    ParamDecl := BuildTsParamDecl('Uint8Array | string', 'uid', F.Params)
  else if P2PFirst then
    ParamDecl := BuildTsParamDecl('string', 'p2pName', F.Params)
  else
    ParamDecl := BuildTsParamDecl('', '', F.Params);

  Lines.Add('export function ' + FuncName + '(' + ParamDecl + '): void {');
  Lines.Add('    const param = new DataHandle(' + TsStrLit(ApiName) + ');');
  Lines.Add('    try {');
  EmitWriteParams(Lines, F.Params, '        ');

  if UidFirst then
  begin
    Lines.Add('        const uidArg = _wrapUid(uid);');
    CallExpr := 'funcs.' + CallFnName + '(uidArg, param.raw)';
  end
  else if P2PFirst then
    CallExpr := 'funcs.' + CallFnName + '(p2pName, param.raw)'
  else
    CallExpr := 'funcs.' + CallFnName + '(_abiTargetApp, param.raw)';

  Lines.Add('        ' + CallExpr + ';');
  Lines.Add('    } finally {');
  Lines.Add('        param.dispose();');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallTypeScriptCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, DefaultTargetApp: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
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

  NormalizedUnit := MakeApiName(UnitName);
  DefaultTargetApp := NormalizedUnit + '_abi';

  Log(PFormat('Generating TypeScript ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('import * as lf from "lingofuse-ts";');
    Lines.Add('');
    Lines.Add('const DataHandle = lf.DataHandle;');
    Lines.Add('const funcs = lf.getBinding().funcs;');
    Lines.Add('const runAsyncWithPromise = lf.async.runAsyncWithPromise;');
    Lines.Add('type CallPromise<T> = lf.async.CallPromise<T>;');
    Lines.Add('');
    Lines.Add('const STATUS_OK = 0x00;');
    Lines.Add('const STATUS_ERROR = 0xFF;');
    Lines.Add('');
    Lines.Add('let _abiTargetApp = ' + TsStrLit(DefaultTargetApp) + ';');
    Lines.Add('let _abiTimeout = 5000;');
    Lines.Add('');
    Lines.Add('export const ABI = {');
    Lines.Add('    get TargetApp(): string { return _abiTargetApp; },');
    Lines.Add('    set TargetApp(v: string) { _abiTargetApp = v; },');
    Lines.Add('    get Timeout(): number { return _abiTimeout; },');
    Lines.Add('    set Timeout(v: number) { _abiTimeout = v; },');
    Lines.Add('};');
    Lines.Add('');
    Lines.Add('function _wrapUid(uid: Uint8Array | string): { bytes: Uint8Array } {');
    Lines.Add('    if (uid instanceof Uint8Array) {');
    Lines.Add('        if (uid.length !== 32) {');
    Lines.Add('            throw new RangeError("UID must be exactly 32 bytes, got " + uid.length);');
    Lines.Add('        }');
    Lines.Add('        return { bytes: new Uint8Array(uid) };');
    Lines.Add('    }');
    Lines.Add('    if (typeof uid === "string") {');
    Lines.Add('        const hex = uid.trim();');
    Lines.Add('        if (hex.length !== 64) {');
    Lines.Add('            throw new RangeError("UID hex string must be exactly 64 characters, got " + hex.length);');
    Lines.Add('        }');
    Lines.Add('        if (!/^[0-9a-fA-F]+$/.test(hex)) {');
    Lines.Add('            throw new RangeError("UID hex string contains non-hex characters");');
    Lines.Add('        }');
    Lines.Add('        const bytes = new Uint8Array(32);');
    Lines.Add('        for (let i = 0; i < 32; i++) {');
    Lines.Add('            bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);');
    Lines.Add('        }');
    Lines.Add('        return { bytes };');
    Lines.Add('    }');
    Lines.Add('    throw new TypeError("UID must be a Uint8Array(32) or a 64-char hex string");');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('function _readSyncReply<T>(apiName: string, res: lf.DataHandle, readResultFn: (r: lf.DataHandle) => T): T {');
    Lines.Add('    if (res.size === 0) {');
    Lines.Add('        throw new Error("ABI call " + JSON.stringify(apiName) + " returned empty response (timeout or target not found)");');
    Lines.Add('    }');
    Lines.Add('    res.position = 0;');
    Lines.Add('    const status = res.readUInt8();');
    Lines.Add('    if (status !== STATUS_OK) {');
    Lines.Add('        let errMsg = "";');
    Lines.Add('        try { errMsg = res.readString(); } catch (_e) { }');
    Lines.Add('        throw new Error("ABI call " + JSON.stringify(apiName) + " failed: " + errMsg);');
    Lines.Add('    }');
    Lines.Add('    return readResultFn(res);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('function _readAsyncReply<T>(apiName: string, rawResult: unknown, readResultFn: (r: lf.DataHandle) => T): T {');
    Lines.Add('    if (rawResult === null || rawResult === undefined) {');
    Lines.Add('        throw new Error("ABI call " + JSON.stringify(apiName) + " returned null response");');
    Lines.Add('    }');
    Lines.Add('    const res = lf.DataHandle.fromRaw(rawResult, false);');
    Lines.Add('    try {');
    Lines.Add('        if (res.size === 0) {');
    Lines.Add('            throw new Error("ABI call " + JSON.stringify(apiName) + " returned empty response");');
    Lines.Add('        }');
    Lines.Add('        res.position = 0;');
    Lines.Add('        const status = res.readUInt8();');
    Lines.Add('        if (status !== STATUS_OK) {');
    Lines.Add('            let errMsg = "";');
    Lines.Add('            try { errMsg = res.readString(); } catch (_e) { }');
    Lines.Add('            throw new Error("ABI call " + JSON.stringify(apiName) + " failed: " + errMsg);');
    Lines.Add('        }');
    Lines.Add('        return readResultFn(res);');
    Lines.Add('    } finally {');
    Lines.Add('        res.dispose();');
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

      if F.IsFunction then
      begin
        EmitSyncCallFunction(Lines, ApiName, F, ApiName, False, False, 'LF_Call');
        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'Async', False, False, 'LF_Async_Call');
        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'Sequenced', False, False, 'LF_Async_Sequenced_Call');
        EmitSyncCallFunction(Lines, ApiName, F, ApiName + 'ByUid', True, False, 'LF_UID_Call');
        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByUidAsync', True, False, 'LF_UID_Async_Call');
        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByUidSequenced', True, False, 'LF_UID_Async_Sequenced_Call');
        EmitSyncCallFunction(Lines, ApiName, F, ApiName + 'ByP2PName', False, True, 'LF_P2PNAME_Call');
        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByP2PNameAsync', False, True, 'LF_P2PNAME_Async_Call');
        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByP2PNameSequenced', False, True, 'LF_P2PNAME_Async_Sequenced_Call');
      end
      else
      begin
        EmitNotifyFunction(Lines, ApiName, F, ApiName, False, False, 'LF_Notify');
        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'Sequenced', False, False, 'LF_Sequenced_Notify');
        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByUid', True, False, 'LF_UID_Notify');
        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByUidSequenced', True, False, 'LF_UID_Sequenced_Notify');
        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByP2PName', False, True, 'LF_P2PNAME_Notify');
        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByP2PNameSequenced', False, True, 'LF_P2PNAME_Sequenced_Notify');
      end;
    end;

    Result := Lines;
    Log(PFormat('Generated %d lines for the TypeScript call implementation.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'http_ts',
    'xxx_abi_call.ts',
    gkCall,
    'TypeScript ABI call client',
    @GenerateABICallTypeScriptCode);

end.
