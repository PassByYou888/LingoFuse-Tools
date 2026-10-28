unit nodejs_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallNodejsCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[nodejs_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[nodejs_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Js_Write_Fn(const T: TP_String): TP_String;
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

function ABI_Type_To_Js_Read_Fn(const T: TP_String): TP_String;
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
  Result := ABI_Type_To_Js_Write_Fn(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function MakeJsParamName(const Name: TP_String; Index: integer): TP_String;
begin
  if Name.Len = 0 then
    Result := '_arg' + umlIntToStr(Index).Text
  else
    Result := '_arg_' + Name.Text;
end;

function JsStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append('\');
      Result.Append(#39);
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
  Result.Append(#39);
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

function BuildCallParamList(const LeadParams: TP_String; const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := LeadParams;
  for i := 0 to High(Params) do
  begin
    if Result.Len > 0 then Result := Result + ', ';
    Result := Result + MakeJsParamName(Params[i].Name, i);
  end;
end;

procedure EmitWriteParams(Lines: TPascalStringList; const Params: TParamArray);
var
  i: integer;
  PName, WriteFn: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeJsParamName(Params[i].Name, i);
    WriteFn := ABI_Type_To_Js_Write_Fn(Params[i].PascalType);
    Lines.Add('        param.' + WriteFn + '(' + PName + ');');
  end;
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
  ParamDecl, ArgLine, ReadFn: TP_String;
begin
  if UidFirst then
    ParamDecl := BuildCallParamList('uid', F.Params)
  else if P2PFirst then
    ParamDecl := BuildCallParamList('p2pName', F.Params)
  else
    ParamDecl := BuildCallParamList('', F.Params);

  Lines.Add('function ' + FuncName + '(' + ParamDecl + ') {');
  Lines.Add('    const param = new DataHandle(' + JsStrLit(ApiName) + ');');
  Lines.Add('    try {');
  EmitWriteParams(Lines, F.Params);

  if UidFirst then
    Lines.Add('        const uidArg = _wrapUid(uid);');

  if UidFirst then
    ArgLine := 'uidArg, param.raw, BigInt(ABI_Timeout)'
  else if P2PFirst then
    ArgLine := 'p2pName, param.raw, BigInt(ABI_Timeout)'
  else
    ArgLine := 'ABI_TargetApp, param.raw, BigInt(ABI_Timeout)';

  Lines.Add('        const raw = funcs.' + CallFnName + '(' + ArgLine + ');');
  Lines.Add('        if (raw === null || raw === undefined) {');
  Lines.Add('            throw new Error(' + JsStrLit('LF ' + CallFnName + ' returned null handle') + ');');
  Lines.Add('        }');
  Lines.Add('        const res = DataHandle.fromRaw(raw, true);');
  Lines.Add('        try {');
  ReadFn := ABI_Type_To_Js_Read_Fn(F.ReturnType);
  Lines.Add('            return _readSyncReply(' + JsStrLit(ApiName) + ', res, (r) => r.' + ReadFn + '());');
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
  ParamDecl, ReadFn, CallArg: TP_String;
begin
  if UidFirst then
    ParamDecl := BuildCallParamList('uid', F.Params)
  else if P2PFirst then
    ParamDecl := BuildCallParamList('p2pName', F.Params)
  else
    ParamDecl := BuildCallParamList('', F.Params);

  Lines.Add('function ' + FuncName + '(' + ParamDecl + ') {');
  Lines.Add('    const param = new DataHandle(' + JsStrLit(ApiName) + ');');
  Lines.Add('    let promise;');
  Lines.Add('    try {');
  EmitWriteParams(Lines, F.Params);

  if UidFirst then
    Lines.Add('        const uidArg = _wrapUid(uid);');

  Lines.Add('        promise = runAsyncWithPromise(');

  if UidFirst then
    CallArg := 'uidArg, param.raw, op.dataPtr, cb'
  else if P2PFirst then
    CallArg := 'p2pName, param.raw, op.dataPtr, cb'
  else
    CallArg := 'ABI_TargetApp, param.raw, op.dataPtr, cb';

  Lines.Add('            (cb, op) => funcs.' + CallFnName + '(' + CallArg + '),');

  ReadFn := ABI_Type_To_Js_Read_Fn(F.ReturnType);
  Lines.Add('            (rawResult) => _readAsyncReply(' + JsStrLit(ApiName) + ', rawResult, (r) => r.' + ReadFn + '()),');
  Lines.Add('            ABI_Timeout');
  Lines.Add('        );');
  Lines.Add('    } catch (err) {');
  Lines.Add('        try { param.dispose(); } catch (_) {}');
  Lines.Add('        throw err;');
  Lines.Add('    }');
  Lines.Add('    promise.then(');
  Lines.Add('        () => { try { param.dispose(); } catch (_) {} },');
  Lines.Add('        () => { try { param.dispose(); } catch (_) {} }');
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
  ParamDecl, ArgLine: TP_String;
begin
  if UidFirst then
    ParamDecl := BuildCallParamList('uid', F.Params)
  else if P2PFirst then
    ParamDecl := BuildCallParamList('p2pName', F.Params)
  else
    ParamDecl := BuildCallParamList('', F.Params);

  Lines.Add('function ' + FuncName + '(' + ParamDecl + ') {');
  Lines.Add('    const param = new DataHandle(' + JsStrLit(ApiName) + ');');
  Lines.Add('    try {');
  EmitWriteParams(Lines, F.Params);

  if UidFirst then
    Lines.Add('        const uidArg = _wrapUid(uid);');

  if UidFirst then
    ArgLine := 'uidArg, param.raw'
  else if P2PFirst then
    ArgLine := 'p2pName, param.raw'
  else
    ArgLine := 'ABI_TargetApp, param.raw';

  Lines.Add('        funcs.' + CallFnName + '(' + ArgLine + ');');
  Lines.Add('    } finally {');
  Lines.Add('        param.dispose();');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABICallNodejsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  FuncNames: TPascalStringList;
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

  Log(PFormat('Generating Node.js ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  FuncNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add(#39 + 'use strict' + #39 + ';');
    Lines.Add('');
    Lines.Add('const lf = require(' + JsStrLit('lingofuse-js') + ');');
    Lines.Add('const { DataHandle } = lf;');
    Lines.Add('const { runAsyncWithPromise } = require(' + JsStrLit('lingofuse-js/async-support') + ');');
    Lines.Add('const _binding = lf._binding;');
    Lines.Add('const funcs = _binding.getBinding().funcs;');
    Lines.Add('');
    Lines.Add('const STATUS_OK = 0x00;');
    Lines.Add('const STATUS_ERROR = 0xFF;');
    Lines.Add('');
    Lines.Add('let ABI_TargetApp = ' + JsStrLit(MakeApiName(UnitName) + '_abi') + ';');
    Lines.Add('let ABI_Timeout = 5000;');
    Lines.Add('');
    Lines.Add('function _wrapUid(uid) {');
    Lines.Add('    if (uid !== null && typeof uid === ' + JsStrLit('object') + ' && uid.bytes instanceof Uint8Array) {');
    Lines.Add('        if (uid.bytes.length !== 32) {');
    Lines.Add('            throw new RangeError(' + JsStrLit('UID must be exactly 32 bytes, got ') + ' + uid.bytes.length);');
    Lines.Add('        }');
    Lines.Add('        return uid;');
    Lines.Add('    }');
    Lines.Add('    if (uid instanceof Uint8Array) {');
    Lines.Add('        if (uid.length !== 32) {');
    Lines.Add('            throw new RangeError(' + JsStrLit('UID must be exactly 32 bytes, got ') + ' + uid.length);');
    Lines.Add('        }');
    Lines.Add('        return { bytes: new Uint8Array(uid) };');
    Lines.Add('    }');
    Lines.Add('    if (typeof uid === ' + JsStrLit('string') + ') {');
    Lines.Add('        const hex = uid.trim();');
    Lines.Add('        if (hex.length !== 64) {');
    Lines.Add('            throw new RangeError(' + JsStrLit('UID hex string must be exactly 64 characters, got ') + ' + hex.length);');
    Lines.Add('        }');
    Lines.Add('        if (!/^[0-9a-fA-F]+$/.test(hex)) {');
    Lines.Add('            throw new RangeError(' + JsStrLit('UID hex string contains non-hex characters') + ');');
    Lines.Add('        }');
    Lines.Add('        const bytes = new Uint8Array(32);');
    Lines.Add('        for (let i = 0; i < 32; i++) {');
    Lines.Add('            bytes[i] = parseInt(hex.substr(i * 2, 2), 16);');
    Lines.Add('        }');
    Lines.Add('        return { bytes };');
    Lines.Add('    }');
    Lines.Add('    throw new TypeError(' + JsStrLit('UID must be a Uint8Array(32), a 64-char hex string, or a { bytes: Uint8Array(32) } object') + ');');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('function _readSyncReply(apiName, res, readResultFn) {');
    Lines.Add('    if (res.size === 0) {');
    Lines.Add('        throw new Error(' + JsStrLit('ABI call ') + ' + JSON.stringify(apiName) + ' + JsStrLit(' returned empty response (timeout or target not found)') + ');');
    Lines.Add('    }');
    Lines.Add('    res.position = 0;');
    Lines.Add('    const status = res.readUInt8();');
    Lines.Add('    if (status !== STATUS_OK) {');
    Lines.Add('        let errMsg = ' + #39 + #39 + ';');
    Lines.Add('        try { errMsg = res.readString(); } catch (_) {}');
    Lines.Add('        throw new Error(' + JsStrLit('ABI call ') + ' + JSON.stringify(apiName) + ' + JsStrLit(' failed: ') + ' + errMsg);');
    Lines.Add('    }');
    Lines.Add('    return readResultFn(res);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('function _readAsyncReply(apiName, rawResult, readResultFn) {');
    Lines.Add('    if (rawResult === null || rawResult === undefined) {');
    Lines.Add('        throw new Error(' + JsStrLit('ABI call ') + ' + JSON.stringify(apiName) + ' + JsStrLit(' returned null response') + ');');
    Lines.Add('    }');
    Lines.Add('    const res = DataHandle.fromRaw(rawResult, false);');
    Lines.Add('    try {');
    Lines.Add('        if (res.size === 0) {');
    Lines.Add('            throw new Error(' + JsStrLit('ABI call ') + ' + JSON.stringify(apiName) + ' + JsStrLit(' returned empty response') + ');');
    Lines.Add('        }');
    Lines.Add('        res.position = 0;');
    Lines.Add('        const status = res.readUInt8();');
    Lines.Add('        if (status !== STATUS_OK) {');
    Lines.Add('            let errMsg = ' + #39 + #39 + ';');
    Lines.Add('            try { errMsg = res.readString(); } catch (_) {}');
    Lines.Add('            throw new Error(' + JsStrLit('ABI call ') + ' + JSON.stringify(apiName) + ' + JsStrLit(' failed: ') + ' + errMsg);');
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
        FuncNames.Add(ApiName);

        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'Async', False, False, 'LF_Async_Call');
        FuncNames.Add(ApiName + 'Async');

        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'Sequenced', False, False, 'LF_Async_Sequenced_Call');
        FuncNames.Add(ApiName + 'Sequenced');

        EmitSyncCallFunction(Lines, ApiName, F, ApiName + 'ByUid', True, False, 'LF_UID_Call');
        FuncNames.Add(ApiName + 'ByUid');

        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByUidAsync', True, False, 'LF_UID_Async_Call');
        FuncNames.Add(ApiName + 'ByUidAsync');

        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByUidSequenced', True, False, 'LF_UID_Async_Sequenced_Call');
        FuncNames.Add(ApiName + 'ByUidSequenced');

        EmitSyncCallFunction(Lines, ApiName, F, ApiName + 'ByP2PName', False, True, 'LF_P2PNAME_Call');
        FuncNames.Add(ApiName + 'ByP2PName');

        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByP2PNameAsync', False, True, 'LF_P2PNAME_Async_Call');
        FuncNames.Add(ApiName + 'ByP2PNameAsync');

        EmitAsyncCallFunction(Lines, ApiName, F, ApiName + 'ByP2PNameSequenced', False, True, 'LF_P2PNAME_Async_Sequenced_Call');
        FuncNames.Add(ApiName + 'ByP2PNameSequenced');
      end
      else
      begin
        EmitNotifyFunction(Lines, ApiName, F, ApiName, False, False, 'LF_Notify');
        FuncNames.Add(ApiName);

        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'Sequenced', False, False, 'LF_Sequenced_Notify');
        FuncNames.Add(ApiName + 'Sequenced');

        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByUid', True, False, 'LF_UID_Notify');
        FuncNames.Add(ApiName + 'ByUid');

        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByUidSequenced', True, False, 'LF_UID_Sequenced_Notify');
        FuncNames.Add(ApiName + 'ByUidSequenced');

        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByP2PName', False, True, 'LF_P2PNAME_Notify');
        FuncNames.Add(ApiName + 'ByP2PName');

        EmitNotifyFunction(Lines, ApiName, F, ApiName + 'ByP2PNameSequenced', False, True, 'LF_P2PNAME_Sequenced_Notify');
        FuncNames.Add(ApiName + 'ByP2PNameSequenced');
      end;
    end;

    Lines.Add('module.exports = {');
    Lines.Add('    get ABI_TargetApp() { return ABI_TargetApp; },');
    Lines.Add('    set ABI_TargetApp(v) { ABI_TargetApp = String(v); },');
    Lines.Add('    get ABI_Timeout() { return ABI_Timeout; },');
    Lines.Add('    set ABI_Timeout(v) { ABI_Timeout = Number(v); },');
    for i := 0 to FuncNames.Count - 1 do
      Lines.Add('    ' + JsStrLit(FuncNames[i]) + ': ' + FuncNames[i].Text + ',');
    Lines.Add('};');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call implementation.', [Lines.Count]));
  finally
    UsedApiNames.Free;
    FuncNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'nodejs',
    'xxx_abi_call.js',
    gkCall,
    'Node.js ABI call client',
    @GenerateABICallNodejsCode);

end.
