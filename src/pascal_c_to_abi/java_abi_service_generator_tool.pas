unit java_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceJavaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or
    T.Same('pwidechar');
end;

function ABI_Type_To_Java_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'long'
  else if T.Same('word') then
    Result := 'int'
  else if T.Same('smallint') then
    Result := 'short'
  else if T.Same('byte') then
    Result := 'byte'
  else if T.Same('uint64') then
    Result := 'long'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'String'
  else
    Result := '';
end;

function ABI_Type_To_Java_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := '""'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else if T.Same('single') then
    Result := '0.0f'
  else if T.Same('int64') or T.Same('uint64') then
    Result := '0L'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := '0L'
  else if T.Same('smallint') then
    Result := '(short)0'
  else if T.Same('byte') then
    Result := '(byte)0'
  else
    Result := '0';
end;

function ABI_Type_To_Java_Read_Expr(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'in.readInt32()'
  else if T.Same('int64') then
    Result := 'in.readInt64()'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'in.readInt32() & 0xFFFFFFFFL'
  else if T.Same('word') then
    Result := 'in.readInt16() & 0xFFFF'
  else if T.Same('smallint') then
    Result := 'in.readInt16()'
  else if T.Same('byte') then
    Result := 'in.readInt8()'
  else if T.Same('uint64') then
    Result := 'in.readInt64()'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'in.readDouble()'
  else if T.Same('single') then
    Result := 'in.readSingle()'
  else if IsStringABIType(T) then
    Result := 'in.readString()'
  else
    Result := '';
end;

function ABI_Type_To_Java_ResultWriter(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'writeCallResult_Int32'
  else if T.Same('int64') then
    Result := 'writeCallResult_Int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'writeCallResult_UInt32'
  else if T.Same('word') then
    Result := 'writeCallResult_UInt16'
  else if T.Same('smallint') then
    Result := 'writeCallResult_Int16'
  else if T.Same('byte') then
    Result := 'writeCallResult_Int8'
  else if T.Same('uint64') then
    Result := 'writeCallResult_UInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'writeCallResult_Double'
  else if T.Same('single') then
    Result := 'writeCallResult_Single'
  else if IsStringABIType(T) then
    Result := 'writeCallResult_String'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Java_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsJavaKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('assert') or S.Same('boolean') or
    S.Same('break') or S.Same('byte') or S.Same('case') or
    S.Same('catch') or S.Same('char') or S.Same('class') or
    S.Same('const') or S.Same('continue') or S.Same('default') or
    S.Same('do') or S.Same('double') or S.Same('else') or
    S.Same('enum') or S.Same('extends') or S.Same('final') or
    S.Same('finally') or S.Same('float') or S.Same('for') or
    S.Same('goto') or S.Same('if') or S.Same('implements') or
    S.Same('import') or S.Same('instanceof') or S.Same('int') or
    S.Same('interface') or S.Same('long') or S.Same('native') or
    S.Same('new') or S.Same('package') or S.Same('private') or
    S.Same('protected') or S.Same('public') or S.Same('return') or
    S.Same('short') or S.Same('static') or S.Same('strictfp') or
    S.Same('super') or S.Same('switch') or S.Same('synchronized') or
    S.Same('this') or S.Same('throw') or S.Same('throws') or
    S.Same('transient') or S.Same('try') or S.Same('void') or
    S.Same('volatile') or S.Same('while') or S.Same('true') or
    S.Same('false') or S.Same('null') or S.Same('var') or
    S.Same('record') or S.Same('yield') or S.Same('sealed') or
    S.Same('permits');
end;

function IsReservedLocalName(const S: TP_String): boolean;
begin
  Result :=
    S.Same('in') or S.Same('out') or S.Same('req') or
    S.Same('resp') or S.Same('handler') or S.Same('ret') or
    S.Same('app') or S.Same('appName') or S.Same('group') or
    S.Same('uid') or S.Same('body') or S.Same('msg') or
    S.Same('err') or S.Same('status') or S.Same('t') or
    S.Same('value');
end;

function MakeSafeJavaParamName(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append(TP_Char('_'));
  end;
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := TP_String('_') + Result;
  if IsJavaKeyword(Result) then
    Result := Result + TP_String('_');
  if IsReservedLocalName(Result) then
    Result := Result + TP_String('_');
end;

function JavaStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Code: integer;
begin
  Result := TP_String('"');
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
      Result := Result + TP_String('\') + TP_String('"')
    else if c = '\' then
      Result := Result + TP_String('\') + TP_String('\')
    else if c = #10 then
      Result := Result + TP_String('\') + TP_String('n')
    else if c = #13 then
      Result := Result + TP_String('\') + TP_String('r')
    else if c = #9 then
      Result := Result + TP_String('\') + TP_String('t')
    else if (Ord(c) < 32) or (Ord(c) > 126) then
    begin
      Code := Ord(c);
      Result := Result + TP_String('\') + TP_String('u') +
        TP_String(IntToHex(Code, 4));
    end
    else
      Result.Append(c);
  end;
  Result := Result + TP_String('"');
end;

function JavaPackageName(const UnitName: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := TP_String('lingofuse.abi.');
  for i := 1 to UnitName.Len do
  begin
    c := UnitName[i];
    if (c >= 'A') and (c <= 'Z') then
      Result.Append(TP_Char(Ord(c) + 32))
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append(TP_Char('_'));
  end;
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
  Result := TP_String('');
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
    while (i <= Comment.Len) and
          ((Comment[i] = #10) or (Comment[i] = #13)) do
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
        Log(TP_String(PFormat(
          'Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text])));
        Break;
      end;
    if Supported and f.IsFunction and
       (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(TP_String(PFormat(
        'Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text])));
    end;
    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log(TP_String('Skipped: routine with empty Name'));
    end;
    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function BuildJavaParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := TP_String('');
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeJavaParamName(Params[i].Name, i);
    PTyp := ABI_Type_To_Java_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + TP_String(', ');
    Result := Result + PTyp + TP_String(' ') + PName;
  end;
end;

function BuildJavaArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := TP_String('');
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeJavaParamName(Params[i].Name, i);
    if i > 0 then
      Result := Result + TP_String(', ');
    Result := Result + PName;
  end;
end;

procedure EmitSafetyHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    private static void writeCallError(DataHandle out, Throwable t) {');
  Lines.Add('        try {');
  Lines.Add('            out.writeInt8(STATUS_ERROR);');
  Lines.Add('            String msg = (t == null || t.getMessage() == null) ? "unknown error" : t.getMessage();');
  Lines.Add('            out.writeString(msg);');
  Lines.Add('        } catch (Throwable ignored) {');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Int32(DataHandle out, int value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt32(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Int64(DataHandle out, long value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt64(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_UInt32(DataHandle out, long value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt32((int)(value & 0xFFFFFFFFL));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_UInt16(DataHandle out, int value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt16((short)(value & 0xFFFF));');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Int16(DataHandle out, short value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt16(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Int8(DataHandle out, byte value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt8(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_UInt64(DataHandle out, long value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeInt64(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Single(DataHandle out, float value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeSingle(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Double(DataHandle out, double value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeDouble(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_String(DataHandle out, String value) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('        out.writeString(value);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeCallResult_Void(DataHandle out) {');
  Lines.Add('        out.writeInt8(STATUS_OK);');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitBusinessHook(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetDecl, DefExpr: TP_String;
begin
  ParamDecl := BuildJavaParamDecl(F.Params);
  RetDecl := ABI_Type_To_Java_Decl(F.ReturnType);
  DefExpr := ABI_Type_To_Java_Default(F.ReturnType);

  if F.IsFunction then
    Lines.Add('    public static ' + RetDecl.Text + ' internal_call_' +
      ApiName.Text + '(' + ParamDecl.Text + ') {')
  else
    Lines.Add('    public static void internal_call_' +
      ApiName.Text + '(' + ParamDecl.Text + ') {');

  if F.IsFunction then
    Lines.Add('        return ' + DefExpr.Text + ';');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCallHandler(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, PTyp, ReadExpr, Writer, ArgList, RetDecl: TP_String;
begin
  Lines.Add('    private static void handle_' + ApiName.Text +
    '(DataHandle in, DataHandle out) {');
  Lines.Add('        try {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJavaParamName(F.Params[i].Name, i);
    PTyp := ABI_Type_To_Java_Decl(F.Params[i].PascalType);
    ReadExpr := ABI_Type_To_Java_Read_Expr(F.Params[i].PascalType);
    Lines.Add('            ' + PTyp.Text + ' ' + PName.Text + ' = ' +
      ReadExpr.Text + ';');
  end;
  ArgList := BuildJavaArgList(F.Params);
  if F.IsFunction then
  begin
    RetDecl := ABI_Type_To_Java_Decl(F.ReturnType);
    Writer := ABI_Type_To_Java_ResultWriter(F.ReturnType);
    Lines.Add('            ' + RetDecl.Text + ' ret = internal_call_' +
      ApiName.Text + '(' + ArgList.Text + ');');
    Lines.Add('            ' + Writer.Text + '(out, ret);');
  end
  else
  begin
    Lines.Add('            internal_call_' + ApiName.Text + '(' +
      ArgList.Text + ');');
    Lines.Add('            writeCallResult_Void(out);');
  end;
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            writeCallError(out, t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitNotifyHandler(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, PTyp, ReadExpr, ArgList: TP_String;
begin
  Lines.Add('    private static void handle_' + ApiName.Text +
    '(DataHandle in) {');
  Lines.Add('        try {');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJavaParamName(F.Params[i].Name, i);
    PTyp := ABI_Type_To_Java_Decl(F.Params[i].PascalType);
    ReadExpr := ABI_Type_To_Java_Read_Expr(F.Params[i].PascalType);
    Lines.Add('            ' + PTyp.Text + ' ' + PName.Text + ' = ' +
      ReadExpr.Text + ';');
  end;
  ArgList := BuildJavaArgList(F.Params);
  Lines.Add('            internal_call_' + ApiName.Text + '(' +
    ArgList.Text + ');');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            Framework.reportCallbackError(' +
    JavaStrLit(TP_String('handle_') + ApiName).Text + ', t);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

function GenerateABIServiceJavaCode(
  Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, PackageName, ClassName, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, Description: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log(TP_String('GenerateABIServiceJavaCode: Model is nil'));
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log(TP_String('GenerateABIServiceJavaCode: UnitName is empty'));
    Exit;
  end;

  PackageName := JavaPackageName(UnitName);
  ClassName := UnitName + TP_String('AbiService');
  AppName := MakeApiName(UnitName) + TP_String('_abi');
  AppDesc := TP_String('ABI service for ') + UnitName;

  Log(TP_String(PFormat('Generating Java ABI service for unit "%s"',
    [UnitName.Text])));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log(TP_String('No supported routines; generating an empty skeleton.'));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('package ' + PackageName.Text + ';');
    Lines.Add('');
    Lines.Add('import lingofuse.AppHandle;');
    Lines.Add('import lingofuse.DataHandle;');
    Lines.Add('import lingofuse.Framework;');
    Lines.Add('import lingofuse.P2PRegistry;');
    Lines.Add('');
    Lines.Add('public final class ' + ClassName.Text + ' {');
    Lines.Add('');
    Lines.Add('    public static final String DEFAULT_APP_NAME = ' +
      JavaStrLit(AppName).Text + ';');
    Lines.Add('    public static final String DEFAULT_APP_DESC = ' +
      JavaStrLit(AppDesc).Text + ';');
    Lines.Add('');
    Lines.Add('    public static final byte STATUS_OK    = 0x00;');
    Lines.Add('    public static final byte STATUS_ERROR = (byte) 0xFF;');
    Lines.Add('');
    Lines.Add('    private ' + ClassName.Text + '() {');
    Lines.Add('    }');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);
      EmitBusinessHook(Lines, ApiName, F);
    end;

    EmitSafetyHelpers(Lines);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);
      if F.IsFunction then
        EmitCallHandler(Lines, ApiName, F)
      else
        EmitNotifyHandler(Lines, ApiName, F);
    end;

    Lines.Add('    public static int registerAllAbiApis(AppHandle app) {');
    Lines.Add('        if (app == null) {');
    Lines.Add('            return -1;');
    Lines.Add('        }');
    Lines.Add('        int failed = 0;');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := TP_String('ABI api for ') + F.Name;
      if F.IsFunction then
        Lines.Add('        if (!app.registerCall(' + JavaStrLit(ApiName).Text +
          ', ' + JavaStrLit(Description).Text + ', ' + ClassName.Text +
          '::handle_' + ApiName.Text + ')) {')
      else
        Lines.Add('        if (!app.registerNotify(' + JavaStrLit(ApiName).Text +
          ', ' + JavaStrLit(Description).Text + ', ' + ClassName.Text +
          '::handle_' + ApiName.Text + ')) {');
      Lines.Add('            failed++;');
      Lines.Add('        }');
    end;
    Lines.Add('        return failed;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    public static int registerAllP2PAbiApis() {');
    Lines.Add('        int failed = 0;');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(
          ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text)) >= 0 do
          Inc(j);
        ApiName := ApiName + TP_String('_') + TP_String(umlIntToStr(j).Text);
      end;
      UsedApiNames.Add(ApiName);
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := TP_String('ABI api for ') + F.Name;
      Lines.Add('        try {');
      if F.IsFunction then
        Lines.Add('            P2PRegistry.registerCall(' +
          JavaStrLit(ApiName).Text + ', ' + JavaStrLit(Description).Text +
          ', ' + ClassName.Text + '::handle_' + ApiName.Text + ');')
      else
        Lines.Add('            P2PRegistry.registerNotify(' +
          JavaStrLit(ApiName).Text + ', ' + JavaStrLit(Description).Text +
          ', ' + ClassName.Text + '::handle_' + ApiName.Text + ');');
      Lines.Add('        } catch (Throwable t) {');
      Lines.Add('            failed++;');
      Lines.Add('        }');
    end;
    Lines.Add('        return failed;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    public static AppHandle createAndRegisterAbiApp() {');
    Lines.Add('        AppHandle app = new AppHandle(' +
      'DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    Lines.Add('        registerAllAbiApis(app);');
    Lines.Add('        return app;');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(TP_String(PFormat('Generated %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)])));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'java',
    'xxxAbiService.java',
    gkService,
    'Java ABI service',
    @GenerateABIServiceJavaCode);

end.
