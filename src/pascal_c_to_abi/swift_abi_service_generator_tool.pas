unit swift_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceSwiftCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[swift_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[swift_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Swift_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := '""'
  else if T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else
    Result := '0';
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
     Result.Same('param') then
    Result := Result + '_param';
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
  if Comment.Len = 0 then
    Exit;

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

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := 'uid: Uid, p2pName: String';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeSwiftIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Swift_Decl(Params[i].PascalType);
    Result := Result + ', _ ' + PName + ': ' + PTyp;
  end;
end;

function BuildArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeSwiftIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function JoinArgs(const Prefix, Args: TP_String): TP_String;
begin
  if Args = '' then
    Result := Prefix
  else if Prefix = '' then
    Result := Args
  else
    Result := Prefix + ', ' + Args;
end;

procedure EmitInternalStub(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetType, RetDefault: TP_String;
  i: integer;
  PName: TP_String;
begin
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  RetType := ABI_Type_To_Swift_Decl(F.ReturnType);
  RetDefault := ABI_Type_To_Swift_Default(F.ReturnType);

  if F.IsFunction then
    Lines.Add('    public static func internalCall_' + ApiName + '(' + ParamDecl + ') -> ' + RetType + ' {')
  else
    Lines.Add('    public static func internalNotify_' + ApiName + '(' + ParamDecl + ') {');

  Lines.Add('        _ = uid');
  Lines.Add('        _ = p2pName');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeSwiftIdent(F.Params[i].Name, i);
    Lines.Add('        _ = ' + PName);
  end;

  if F.IsFunction then
    Lines.Add('        return ' + RetDefault);
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCallbackImpl(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  WriteFunc, ArgList, Head: TP_String;
  i: integer;
  PName, PTyp, ReadFunc: TP_String;
  HasParams: Boolean;
  NeedTryBlock: Boolean;
begin
  HasParams := Length(F.Params) > 0;
  NeedTryBlock := F.IsFunction or HasParams;

  if F.IsFunction then
    Lines.Add('    private static func callback_' + ApiName + '(input: DataHandle, output: DataHandle) {')
  else
    Lines.Add('    private static func callback_' + ApiName + '(input: DataHandle) {');

  Lines.Add('        let uid = input.p2pUid()');
  Lines.Add('        let p2pName = input.p2pName()');

  if NeedTryBlock then
    Lines.Add('        do {');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeSwiftIdent(F.Params[i].Name, i);
    PTyp := ABI_Type_To_Swift_Decl(F.Params[i].PascalType);
    ReadFunc := ABI_Type_To_Swift_ReadFunc(F.Params[i].PascalType);
    Lines.Add('            let ' + PName + ': ' + PTyp + ' = try input.' + ReadFunc + '()');
  end;

  ArgList := BuildArgList(F.Params);
  Head := JoinArgs('uid: uid, p2pName: p2pName', ArgList);

  if F.IsFunction then
  begin
    Lines.Add('            let result = internalCall_' + ApiName + '(' + Head + ')');
    Lines.Add('            try output.writeUInt8(statusOK)');
    WriteFunc := ABI_Type_To_Swift_WriteFunc(F.ReturnType);
    Lines.Add('            try output.' + WriteFunc + '(result)');
  end
  else
    Lines.Add('            internalNotify_' + ApiName + '(' + Head + ')');

  if NeedTryBlock then
  begin
    Lines.Add('        } catch {');
    if F.IsFunction then
    begin
      Lines.Add('            try? output.writeUInt8(statusError)');
      Lines.Add('            try? output.writeString("\(error)")');
    end;
    Lines.Add('        }');
  end;
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitRegisterAll(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Description: TP_String;
begin
  Lines.Add('    public static func registerAllABIAPIs(app: AppHandle) throws {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'ABI api for ' + F.Name;

    if F.IsFunction then
      Lines.Add('        try app.registerCall(' + SwiftStrLit(ApiName) + ', ' + SwiftStrLit(Description) +
        ', callback_' + ApiName + ')')
    else
      Lines.Add('        try app.registerNotify(' + SwiftStrLit(ApiName) + ', ' + SwiftStrLit(Description) +
        ', callback_' + ApiName + ')');
  end;
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    public static func registerAllP2PABIAPIs() throws {');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'ABI api for ' + F.Name;

    if F.IsFunction then
      Lines.Add('        try P2P.registerCall(' + SwiftStrLit(ApiName) + ', description: ' + SwiftStrLit(Description) +
        ', handler: callback_' + ApiName + ')')
    else
      Lines.Add('        try P2P.registerNotify(' + SwiftStrLit(ApiName) + ', description: ' + SwiftStrLit(Description) +
        ', handler: callback_' + ApiName + ')');
  end;
  Lines.Add('    }');
  Lines.Add('');

  Lines.Add('    public static func createAndRegisterABIApp() throws -> AppHandle {');
  Lines.Add('        let app = try AppHandle(name: defaultAppName, description: defaultAppDesc)');
  Lines.Add('        try registerAllABIAPIs(app: app)');
  Lines.Add('        return app');
  Lines.Add('    }');
end;

function GenerateABIServiceSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, EnumName, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceSwiftCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceSwiftCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  EnumName := NormalizedUnit + 'ABIService';
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Swift ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('import Foundation');
    Lines.Add('import LingoFuse');
    Lines.Add('');
    Lines.Add('public enum ' + EnumName + ' {');
    Lines.Add('    public static let defaultAppName: String = ' + SwiftStrLit(AppName));
    Lines.Add('    public static let defaultAppDesc: String = ' + SwiftStrLit(AppDesc));
    Lines.Add('    public static let statusOK: UInt8 = 0x00');
    Lines.Add('    public static let statusError: UInt8 = 0xFF');
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
      EmitInternalStub(Lines, ApiName, F);
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
      EmitCallbackImpl(Lines, ApiName, F);
    end;

    EmitRegisterAll(Lines, SupportedFuncs, UsedApiNames);

    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the Swift ABI service', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'swift',
    'xxx_abi_service.swift',
    gkService,
    'Swift ABI service implementation',
    @GenerateABIServiceSwiftCode);

end.
