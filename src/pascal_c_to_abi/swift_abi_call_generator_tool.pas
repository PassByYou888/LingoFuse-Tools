unit swift_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallSwiftCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[swift_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[swift_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Swift_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'Int32'
  else if T.Same('int64') then
    Result := 'Int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'UInt32'
  else if T.Same('word') then
    Result := 'UInt16'
  else if T.Same('smallint') then
    Result := 'Int16'
  else if T.Same('byte') then
    Result := 'UInt8'
  else if T.Same('uint64') then
    Result := 'UInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'Double'
  else if T.Same('single') then
    Result := 'Float'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Swift_ReadFunc(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'readInt32'
  else if T.Same('int64') then
    Result := 'readInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'readUInt32'
  else if T.Same('word') then
    Result := 'readUInt16'
  else if T.Same('smallint') then
    Result := 'readInt16'
  else if T.Same('byte') then
    Result := 'readUInt8'
  else if T.Same('uint64') then
    Result := 'readUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'readDouble'
  else if T.Same('single') then
    Result := 'readSingle'
  else if IsStringABIType(T) then
    Result := 'readString'
  else
    Result := '';
end;

function ABI_Type_To_Swift_WriteFunc(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'writeInt32'
  else if T.Same('int64') then
    Result := 'writeInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'writeUInt32'
  else if T.Same('word') then
    Result := 'writeUInt16'
  else if T.Same('smallint') then
    Result := 'writeInt16'
  else if T.Same('byte') then
    Result := 'writeUInt8'
  else if T.Same('uint64') then
    Result := 'writeUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'writeDouble'
  else if T.Same('single') then
    Result := 'writeSingle'
  else if IsStringABIType(T) then
    Result := 'writeString'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Swift_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsSwiftKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('associatedtype') or S.Same('class') or S.Same('deinit') or
    S.Same('enum') or S.Same('extension') or S.Same('fileprivate') or
    S.Same('func') or S.Same('import') or S.Same('init') or
    S.Same('inout') or S.Same('internal') or S.Same('let') or
    S.Same('open') or S.Same('operator') or S.Same('private') or
    S.Same('protocol') or S.Same('public') or S.Same('rethrows') or
    S.Same('static') or S.Same('struct') or S.Same('subscript') or
    S.Same('typealias') or S.Same('var') or
    S.Same('break') or S.Same('case') or S.Same('continue') or
    S.Same('default') or S.Same('defer') or S.Same('do') or
    S.Same('else') or S.Same('fallthrough') or S.Same('for') or
    S.Same('guard') or S.Same('if') or S.Same('in') or
    S.Same('repeat') or S.Same('return') or S.Same('switch') or
    S.Same('where') or S.Same('while') or
    S.Same('as') or S.Same('Any') or S.Same('catch') or
    S.Same('false') or S.Same('is') or S.Same('nil') or
    S.Same('super') or S.Same('self') or S.Same('Self') or S.Same('throw') or
    S.Same('throws') or S.Same('true') or S.Same('try');
end;

function MakeSafeSwiftIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsSwiftKeyword(Result) then
    Result := Result + '_';

  if Result.Same('uid') or Result.Same('p2pName') or Result.Same('input') or
     Result.Same('output') or Result.Same('status') or Result.Same('result') or
     Result.Same('error') or Result.Same('app') or Result.Same('resp') or
     Result.Same('param') or Result.Same('target') then
    Result := Result + '_param';
end;

function MakeSafeSwiftFuncName(const Name: TP_String): TP_String;
begin
  Result := Name;
  if (Result.Len > 0) and IsSwiftKeyword(Result) then
    Result := Result + '_';
end;

function SwiftStrLit(const S: TP_String): TP_String;
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

function BuildParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    PName := MakeSafeSwiftIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Swift_Decl(Params[i].PascalType);
    Result := Result + '_ ' + PName + ': ' + PTyp;
  end;
end;

function BuildParamDeclWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Tmp := BuildParamDecl(Params);
  if Tmp = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Tmp
  else
    Result := Prefix + ', ' + Tmp;
end;

function BuildArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    PName := MakeSafeSwiftIdent(Params[i].Name, i);
    Result := Result + PName;
  end;
end;

procedure EmitBuildParamHelper(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  ParamDecl, ArgList, PName, WriteFunc: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);
  ArgList := BuildArgList(F.Params);
  Lines.Add('    private static func buildParam_' + ApiName + '(' + ParamDecl + ') throws -> DataHandle {');
  Lines.Add('        let param = try DataHandle(apiName: ' + SwiftStrLit(ApiName) + ')');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeSwiftIdent(F.Params[i].Name, i);
    WriteFunc := ABI_Type_To_Swift_WriteFunc(F.Params[i].PascalType);
    Lines.Add('        try param.' + WriteFunc + '(' + PName + ')');
  end;
  Lines.Add('        param.position = 0');
  Lines.Add('        return param');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitReadResponseHelper(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ReadFunc, OpLine: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ReadFunc := ABI_Type_To_Swift_ReadFunc(F.ReturnType);

  OpLine := '                operation: ';
  OpLine.Append(SwiftStrLit('ABI call ' + ApiName.Text + ' failed: '));
  OpLine.Append(' + msg');
  OpLine.Append(',');

  Lines.Add('    private static func readResponse_' + ApiName + '(_ resp: DataHandle) throws -> ' + RetType + ' {');
  Lines.Add('        resp.position = 0');
  Lines.Add('        let status: UInt8 = try resp.readUInt8()');
  Lines.Add('        if status != statusOK {');
  Lines.Add('            let msg = (try? resp.readString()) ?? ""');
  Lines.Add('            throw LingoFuseError.callFailed(');
  Lines.Add(OpLine.Text);
  Lines.Add('                targetApp: targetAppName,');
  Lines.Add('                targetApi: ' + SwiftStrLit(ApiName) + ')');
  Lines.Add('        }');
  Lines.Add('        return try resp.' + ReadFunc + '()');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSyncAppCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList, OpLine: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDecl(F.Params);
  ArgList := BuildArgList(F.Params);

  OpLine := '                operation: ';
  OpLine.Append(SwiftStrLit('ABI call ' + ApiName.Text + ' returned nil'));
  OpLine.Append(',');

  Lines.Add('    public static func ' + ApiName + '(' + ParamDecl + ') throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        guard let resp = try AppTarget(targetAppName, defaultTimeoutMs: defaultTimeoutMs).tryCall(' + SwiftStrLit(ApiName) + ', param) else {');
  Lines.Add('            throw LingoFuseError.callFailed(');
  Lines.Add(OpLine.Text);
  Lines.Add('                targetApp: targetAppName,');
  Lines.Add('                targetApi: ' + SwiftStrLit(ApiName) + ')');
  Lines.Add('        }');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncAppCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDecl(F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_Async(' + ParamDecl + ') async throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        let resp = try await AppTarget(targetAppName, defaultTimeoutMs: defaultTimeoutMs).callAsync(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncSequencedAppCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDecl(F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_AsyncSequenced(' + ParamDecl + ') async throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        let resp = try await AppTarget(targetAppName, defaultTimeoutMs: defaultTimeoutMs).sequencedCallAsync(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSyncUidCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList, OpLine: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('_ uid: Uid', F.Params);
  ArgList := BuildArgList(F.Params);

  OpLine := '                operation: ';
  OpLine.Append(SwiftStrLit('ABI call ' + ApiName.Text + ' returned nil'));
  OpLine.Append(',');

  Lines.Add('    public static func ' + ApiName + '_UID_Call(' + ParamDecl + ') throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        guard let resp = try UidTarget(uid, defaultTimeoutMs: defaultTimeoutMs).tryCall(' + SwiftStrLit(ApiName) + ', param) else {');
  Lines.Add('            throw LingoFuseError.callFailed(');
  Lines.Add(OpLine.Text);
  Lines.Add('                targetApp: nil,');
  Lines.Add('                targetApi: ' + SwiftStrLit(ApiName) + ')');
  Lines.Add('        }');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncUidCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('_ uid: Uid', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_UID_Async(' + ParamDecl + ') async throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        let resp = try await UidTarget(uid, defaultTimeoutMs: defaultTimeoutMs).callAsync(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncSequencedUidCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('_ uid: Uid', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_UID_AsyncSequenced(' + ParamDecl + ') async throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        let resp = try await UidTarget(uid, defaultTimeoutMs: defaultTimeoutMs).sequencedCallAsync(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSyncP2PNameCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList, OpLine: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('_ p2pName: String', F.Params);
  ArgList := BuildArgList(F.Params);

  OpLine := '                operation: ';
  OpLine.Append(SwiftStrLit('ABI call ' + ApiName.Text + ' returned nil'));
  OpLine.Append(',');

  Lines.Add('    public static func ' + ApiName + '_P2PName_Call(' + ParamDecl + ') throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        guard let resp = try P2PNameTarget(p2pName, defaultTimeoutMs: defaultTimeoutMs).tryCall(' + SwiftStrLit(ApiName) + ', param) else {');
  Lines.Add('            throw LingoFuseError.callFailed(');
  Lines.Add(OpLine.Text);
  Lines.Add('                targetApp: nil,');
  Lines.Add('                targetApi: ' + SwiftStrLit(ApiName) + ')');
  Lines.Add('        }');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncP2PNameCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('_ p2pName: String', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_P2PName_Async(' + ParamDecl + ') async throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        let resp = try await P2PNameTarget(p2pName, defaultTimeoutMs: defaultTimeoutMs).callAsync(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAsyncSequencedP2PNameCall(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ParamDecl, ArgList: TP_String;
begin
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  ParamDecl := BuildParamDeclWithPrefix('_ p2pName: String', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_P2PName_AsyncSequenced(' + ParamDecl + ') async throws -> ' + RetType + ' {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        let resp = try await P2PNameTarget(p2pName, defaultTimeoutMs: defaultTimeoutMs).sequencedCallAsync(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('        defer { resp.dispose() }');
  Lines.Add('        return try readResponse_' + ApiName + '(resp)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAppNotify(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '(' + ParamDecl + ') throws {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        AppTarget(targetAppName, defaultTimeoutMs: defaultTimeoutMs).notify(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitAppSequencedNotify(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList: TP_String;
begin
  ParamDecl := BuildParamDecl(F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_SequencedNotify(' + ParamDecl + ') throws {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        AppTarget(targetAppName, defaultTimeoutMs: defaultTimeoutMs).sequencedNotify(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitUidNotify(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('_ uid: Uid', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_UID_Notify(' + ParamDecl + ') throws {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        UidTarget(uid, defaultTimeoutMs: defaultTimeoutMs).notify(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitUidSequencedNotify(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('_ uid: Uid', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_UID_SequencedNotify(' + ParamDecl + ') throws {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        UidTarget(uid, defaultTimeoutMs: defaultTimeoutMs).sequencedNotify(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitP2PNameNotify(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('_ p2pName: String', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_P2PName_Notify(' + ParamDecl + ') throws {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        P2PNameTarget(p2pName, defaultTimeoutMs: defaultTimeoutMs).notify(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitP2PNameSequencedNotify(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList: TP_String;
begin
  ParamDecl := BuildParamDeclWithPrefix('_ p2pName: String', F.Params);
  ArgList := BuildArgList(F.Params);

  Lines.Add('    public static func ' + ApiName + '_P2PName_SequencedNotify(' + ParamDecl + ') throws {');
  Lines.Add('        let param = try buildParam_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        defer { param.dispose() }');
  Lines.Add('        P2PNameTarget(p2pName, defaultTimeoutMs: defaultTimeoutMs).sequencedNotify(' + SwiftStrLit(ApiName) + ', param)');
  Lines.Add('    }');
  Lines.Add('');
end;

function GenerateABICallSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, EnumName, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallSwiftCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallSwiftCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  EnumName := NormalizedUnit + 'ABICall';
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating Swift ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('import Foundation');
    Lines.Add('import LingoFuse');
    Lines.Add('');
    Lines.Add('public enum ' + EnumName + ' {');
    Lines.Add('    public static var targetAppName: String = ' + SwiftStrLit(TargetAppName));
    Lines.Add('    public static var defaultTimeoutMs: UInt64 = 5000');
    Lines.Add('    public static let statusOK: UInt8 = 0x00');
    Lines.Add('    public static let statusError: UInt8 = 0xFF');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeSafeSwiftFuncName(MakeApiName(F.Name));
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      EmitBuildParamHelper(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if not F.IsFunction then
        Continue;
      ApiName := MakeSafeSwiftFuncName(MakeApiName(F.Name));
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      EmitReadResponseHelper(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if not F.IsFunction then
        Continue;
      ApiName := MakeSafeSwiftFuncName(MakeApiName(F.Name));
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitSyncAppCall(Lines, ApiName, F);
      EmitAsyncAppCall(Lines, ApiName, F);
      EmitAsyncSequencedAppCall(Lines, ApiName, F);
      EmitSyncUidCall(Lines, ApiName, F);
      EmitAsyncUidCall(Lines, ApiName, F);
      EmitAsyncSequencedUidCall(Lines, ApiName, F);
      EmitSyncP2PNameCall(Lines, ApiName, F);
      EmitAsyncP2PNameCall(Lines, ApiName, F);
      EmitAsyncSequencedP2PNameCall(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        Continue;
      ApiName := MakeSafeSwiftFuncName(MakeApiName(F.Name));
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitAppNotify(Lines, ApiName, F);
      EmitAppSequencedNotify(Lines, ApiName, F);
      EmitUidNotify(Lines, ApiName, F);
      EmitUidSequencedNotify(Lines, ApiName, F);
      EmitP2PNameNotify(Lines, ApiName, F);
      EmitP2PNameSequencedNotify(Lines, ApiName, F);
    end;

    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the Swift ABI call', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'swift',
    'xxx_abi_call.swift',
    gkCall,
    'Swift ABI call implementation',
    @GenerateABICallSwiftCode);

end.
