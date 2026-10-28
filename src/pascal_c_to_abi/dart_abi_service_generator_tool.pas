unit dart_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceDartCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Dart_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'int'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'int'
  else if T.Same('word') then
    Result := 'int'
  else if T.Same('smallint') then
    Result := 'int'
  else if T.Same('byte') then
    Result := 'int'
  else if T.Same('uint64') then
    Result := 'int'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'double'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Writer_Method(const T: TP_String): TP_String;
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

function ABI_Type_To_Reader_Method(const T: TP_String): TP_String;
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

function ABI_Type_Default_Literal(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := #39#39
  else if T.Same('double') or T.Same('single') or
    T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Dart_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsDartKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('assert') or S.Same('async') or
    S.Same('await') or S.Same('break') or S.Same('case') or S.Same('catch') or
    S.Same('class') or S.Same('const') or S.Same('continue') or S.Same('covariant') or
    S.Same('default') or S.Same('deferred') or S.Same('do') or S.Same('dynamic') or
    S.Same('else') or S.Same('enum') or S.Same('export') or S.Same('extends') or
    S.Same('extension') or S.Same('external') or S.Same('factory') or S.Same('false') or
    S.Same('final') or S.Same('finally') or S.Same('for') or S.Same('Function') or
    S.Same('get') or S.Same('hide') or S.Same('if') or S.Same('implements') or
    S.Same('import') or S.Same('in') or S.Same('interface') or S.Same('is') or
    S.Same('late') or S.Same('library') or S.Same('mixin') or S.Same('new') or
    S.Same('null') or S.Same('on') or S.Same('operator') or S.Same('part') or
    S.Same('required') or S.Same('rethrow') or S.Same('return') or S.Same('set') or
    S.Same('show') or S.Same('static') or S.Same('super') or S.Same('switch') or
    S.Same('sync') or S.Same('this') or S.Same('throw') or S.Same('true') or
    S.Same('try') or S.Same('typedef') or S.Same('var') or S.Same('void') or
    S.Same('while') or S.Same('with') or S.Same('yield');
end;

function IsDartReservedLocal(const S: TP_String): boolean;
begin
  Result :=
    S.Same('ctx') or S.Same('uid') or S.Same('onResult') or
    S.Same('param') or S.Same('target') or S.Same('p2pName') or
    S.Same('name') or S.Same('abi') or S.Same('_lfCallStats');
end;

function MakeSafeDartIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsDartKeyword(Result) then
    Result := Result + '_';

  if IsDartReservedLocal(Result) then
    Result := Result + '_param';

  if Result.ComparePos(1, '_lf_') or Result.ComparePos(1, '_u_') then
    Result := '_u_' + Result;
end;

function DartStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
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
      Result.Append(c);
  end;
  Result.Append(#39);
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
      Line := StripCommentMarkers(Comment.GetString(i, j));
      if Line.Len > 0 then
      begin
        if Line[1] <> '@' then
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

function BuildDartParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeDartIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Dart_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PTyp + ' ' + PName;
  end;
end;

function BuildDartArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeDartIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

procedure EmitReadStatements(Lines: TPascalStringList; const Params: TParamArray; const Indent: string);
var
  i: integer;
  PName, ReadFn: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeDartIdent(Params[i].Name, i);
    ReadFn := ABI_Type_To_Reader_Method(Params[i].PascalType);
    Lines.Add(Indent + 'final ' + PName + ' = _lf_r.' + ReadFn + '();');
  end;
end;

procedure EmitInternalCallStub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetType, DefaultLit, KeyLit: TP_String;
begin
  ParamDecl := BuildDartParamDecl(F.Params);
  RetType := ABI_Type_To_Dart_Decl(F.ReturnType);
  KeyLit := DartStrLit(ApiName);
  if F.IsFunction then
  begin
    DefaultLit := ABI_Type_Default_Literal(F.ReturnType);
    Lines.Add(RetType + ' internal_call_' + ApiName + '(' + ParamDecl + ') {');
    Lines.Add('  _lfCallStats[' + KeyLit + '] = (_lfCallStats[' + KeyLit + '] ?? 0) + 1;');
    Lines.Add('  return ' + DefaultLit + ';');
    Lines.Add('}');
  end
  else
  begin
    Lines.Add('void internal_call_' + ApiName + '(' + ParamDecl + ') {');
    Lines.Add('  _lfCallStats[' + KeyLit + '] = (_lfCallStats[' + KeyLit + '] ?? 0) + 1;');
    Lines.Add('}');
  end;
  Lines.Add('');
end;

procedure EmitCallbackCall(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgList, WriteFn: TP_String;
begin
  ArgList := BuildDartArgList(F.Params);
  WriteFn := ABI_Type_To_Writer_Method(F.ReturnType);

  Lines.Add('Uint8List callback_' + ApiName + '(CallContext ctx) {');
  Lines.Add('  final _lf_w = AbiWriter();');
  Lines.Add('  try {');
  Lines.Add('    final _lf_r = AbiReader(ctx.payload);');
  EmitReadStatements(Lines, F.Params, '    ');
  if ArgList = '' then
    Lines.Add('    final _lf_ret = internal_call_' + ApiName + '();')
  else
    Lines.Add('    final _lf_ret = internal_call_' + ApiName + '(' + ArgList + ');');
  Lines.Add('    _lf_w.writeUInt8(STATUS_OK);');
  Lines.Add('    _lf_w.' + WriteFn + '(_lf_ret);');
  Lines.Add('  } catch (_lf_e) {');
  Lines.Add('    final _lf_ew = AbiWriter();');
  Lines.Add('    _lf_ew.writeUInt8(STATUS_ERROR);');
  Lines.Add('    _lf_ew.writeString(_lf_e.toString());');
  Lines.Add('    return _lf_ew.takeBytes();');
  Lines.Add('  }');
  Lines.Add('  return _lf_w.takeBytes();');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackNotify(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgList: TP_String;
begin
  ArgList := BuildDartArgList(F.Params);

  Lines.Add('void callback_' + ApiName + '(CallContext ctx) {');
  Lines.Add('  final _lf_r = AbiReader(ctx.payload);');
  EmitReadStatements(Lines, F.Params, '  ');
  if ArgList = '' then
    Lines.Add('  internal_call_' + ApiName + '();')
  else
    Lines.Add('  internal_call_' + ApiName + '(' + ArgList + ');');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRegisterAppCall(Lines: TPascalStringList;
  const ApiName, Description: TP_String);
begin
  Lines.Add('  app.registerCall(' + DartStrLit(ApiName) + ', ' +
    DartStrLit(Description) + ', callback_' + ApiName + ');');
end;

procedure EmitRegisterAppNotify(Lines: TPascalStringList;
  const ApiName, Description: TP_String);
begin
  Lines.Add('  app.registerNotify(' + DartStrLit(ApiName) + ', ' +
    DartStrLit(Description) + ', callback_' + ApiName + ');');
end;

procedure EmitRegisterP2PCall(Lines: TPascalStringList;
  const ApiName, Description: TP_String);
begin
  Lines.Add('  BridgeHost.instance.registerP2PCall(' + DartStrLit(ApiName) + ', ' +
    DartStrLit(Description) + ', callback_' + ApiName + ');');
end;

procedure EmitRegisterP2PNotify(Lines: TPascalStringList;
  const ApiName, Description: TP_String);
begin
  Lines.Add('  BridgeHost.instance.registerP2PNotify(' + DartStrLit(ApiName) + ', ' +
    DartStrLit(Description) + ', callback_' + ApiName + ');');
end;

function MakeUniqueApiName(const Source: TP_String; Used: TPascalStringList): TP_String;
var
  j: integer;
begin
  Result := MakeApiName(Source);
  if Used.IndexOf(Result) >= 0 then
  begin
    j := 1;
    while Used.IndexOf(Result + '_' + umlIntToStr(j).Text) >= 0 do
      Inc(j);
    Result := Result + '_' + umlIntToStr(j).Text;
  end;
  Used.Add(Result);
end;

function GenerateABIServiceDartCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, Description: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceDartCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceDartCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Dart ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('// ignore_for_file: non_constant_identifier_names, unused_local_variable, unnecessary_statements');
    Lines.Add('');
    Lines.Add('import ' + DartStrLit('dart:typed_data') + ';');
    Lines.Add('');
    Lines.Add('import ' + DartStrLit('package:lingofuse/lingofuse.dart') + ';');
    Lines.Add('');
    Lines.Add('const String DEFAULT_APP_NAME = ' + DartStrLit(AppName) + ';');
    Lines.Add('const String DEFAULT_APP_DESC = ' + DartStrLit(AppDesc) + ';');
    Lines.Add('');
    Lines.Add('const int STATUS_OK = 0x00;');
    Lines.Add('const int STATUS_ERROR = 0xFF;');
    Lines.Add('');
    Lines.Add('final Map<String, int> _lfCallStats = <String, int>{};');
    Lines.Add('');
    Lines.Add('Map<String, int> lf_get_call_stats() => Map<String, int>.from(_lfCallStats);');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeUniqueApiName(SupportedFuncs[i].Name, UsedApiNames);
      EmitInternalCallStub(Lines, ApiName, SupportedFuncs[i]);
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeUniqueApiName(F.Name, UsedApiNames);
      if F.IsFunction then
        EmitCallbackCall(Lines, ApiName, F)
      else
        EmitCallbackNotify(Lines, ApiName, F);
    end;

    Lines.Add('void register_all_abi_apis(AppHandle app) {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeUniqueApiName(F.Name, UsedApiNames);
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;
      if F.IsFunction then
        EmitRegisterAppCall(Lines, ApiName, Description)
      else
        EmitRegisterAppNotify(Lines, ApiName, Description);
    end;
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('void register_all_p2p_abi_apis() {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeUniqueApiName(F.Name, UsedApiNames);
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;
      if F.IsFunction then
        EmitRegisterP2PCall(Lines, ApiName, Description)
      else
        EmitRegisterP2PNotify(Lines, ApiName, Description);
    end;
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('AppHandle create_and_register_abi_app() {');
    Lines.Add('  final app = AppHandle(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    Lines.Add('  register_all_abi_apis(app);');
    Lines.Add('  return app;');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Dart ABI service', [Lines.Count]));
  finally
  end;
end;

initialization

  RegisterGenerator(
    'dart',
    'xxx_abi_service.dart',
    gkService,
    'Dart ABI service implementation',
    @GenerateABIServiceDartCode);

end.
