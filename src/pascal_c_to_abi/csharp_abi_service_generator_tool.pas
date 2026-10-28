unit csharp_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_CSharp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'uint'
  else if T.Same('word') then
    Result := 'ushort'
  else if T.Same('smallint') then
    Result := 'short'
  else if T.Same('byte') then
    Result := 'byte'
  else if T.Same('uint64') then
    Result := 'ulong'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'string'
  else
    Result := '';
end;

function ABI_Type_To_CSharp_Reader_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'ReadInt32'
  else if T.Same('int64') then Result := 'ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'ReadUInt32'
  else if T.Same('word') then Result := 'ReadUInt16'
  else if T.Same('smallint') then Result := 'ReadInt16'
  else if T.Same('byte') then Result := 'ReadUInt8'
  else if T.Same('uint64') then Result := 'ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'ReadDouble'
  else if T.Same('single') then Result := 'ReadSingle'
  else if IsStringABIType(T) then Result := 'ReadString'
  else Result := '';
end;

function ABI_Type_To_CSharp_Writer_Method(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'WriteInt32'
  else if T.Same('int64') then Result := 'WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'WriteUInt32'
  else if T.Same('word') then Result := 'WriteUInt16'
  else if T.Same('smallint') then Result := 'WriteInt16'
  else if T.Same('byte') then Result := 'WriteUInt8'
  else if T.Same('uint64') then Result := 'WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'WriteDouble'
  else if T.Same('single') then Result := 'WriteSingle'
  else if IsStringABIType(T) then Result := 'WriteString'
  else Result := '';
end;

function ABI_Type_To_CSharp_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'string.Empty'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else if T.Same('single') then
    Result := '0.0f'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_CSharp_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsCSharpKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('base') or S.Same('bool') or
    S.Same('break') or S.Same('byte') or S.Same('case') or S.Same('catch') or
    S.Same('char') or S.Same('checked') or S.Same('class') or S.Same('const') or
    S.Same('continue') or S.Same('decimal') or S.Same('default') or S.Same('delegate') or
    S.Same('do') or S.Same('double') or S.Same('else') or S.Same('enum') or
    S.Same('event') or S.Same('explicit') or S.Same('extern') or S.Same('false') or
    S.Same('finally') or S.Same('fixed') or S.Same('float') or S.Same('for') or
    S.Same('foreach') or S.Same('goto') or S.Same('if') or S.Same('implicit') or
    S.Same('in') or S.Same('int') or S.Same('interface') or S.Same('internal') or
    S.Same('is') or S.Same('lock') or S.Same('long') or S.Same('namespace') or
    S.Same('new') or S.Same('null') or S.Same('object') or S.Same('operator') or
    S.Same('out') or S.Same('override') or S.Same('params') or S.Same('private') or
    S.Same('protected') or S.Same('public') or S.Same('readonly') or S.Same('ref') or
    S.Same('return') or S.Same('sbyte') or S.Same('sealed') or S.Same('short') or
    S.Same('sizeof') or S.Same('stackalloc') or S.Same('static') or S.Same('string') or
    S.Same('struct') or S.Same('switch') or S.Same('this') or S.Same('throw') or
    S.Same('true') or S.Same('try') or S.Same('typeof') or S.Same('uint') or
    S.Same('ulong') or S.Same('unchecked') or S.Same('unsafe') or S.Same('ushort') or
    S.Same('using') or S.Same('virtual') or S.Same('void') or S.Same('volatile') or
    S.Same('while');
end;

function IsReservedInternalName(const S: TP_String): boolean;
begin
  Result := S.Same('lfUid') or S.Same('lfP2PName') or
    S.Same('inHandle') or S.Same('outHandle') or
    S.Same('ex') or S.Same('ret');
end;

function MakeSafeCSharpParamName(const Name: TP_String; Index: integer): TP_String;
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

  if IsCSharpKeyword(Result) then
    Result := Result + '_';

  if IsReservedInternalName(Result) then
    Result := Result + '_';
end;

function CSharpStrLit(const S: TP_String): TP_String;
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
    else if c = #0 then
    begin
      Result.Append('\');
      Result.Append('0');
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

procedure EmitCommentLines(Lines: TPascalStringList; const Indent, Comment: TP_String);
var
  i, j: integer;
  Line: TP_String;
begin
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
        if Line[1] = '*' then
          Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
        if (Line.Len > 0) and (Line[1] = '*') then
          Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
        if Line.Len > 0 then
          Lines.Add(Indent + '// ' + Line.Text);
      end;
    end;
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
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

function GenerateABIServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, ParamDecl, RetType, ArgList: TP_String;
  Description: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  PName, PTyp, ReaderMethod, WriterMethod: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating C# ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('using System;');
    Lines.Add('using LingoFuse;');
    Lines.Add('');
    Lines.Add('namespace ' + NsName);
    Lines.Add('{');

    Lines.Add('    public static class AppInfo');
    Lines.Add('    {');
    Lines.Add('        public const string Name = ' + CSharpStrLit(AppName) + ';');
    Lines.Add('        public const string Desc = ' + CSharpStrLit(AppDesc) + ';');
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    internal static class WireStatus');
    Lines.Add('    {');
    Lines.Add('        public const byte Ok = 0x00;');
    Lines.Add('        public const byte Error = 0xFF;');
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    public static class InternalCalls');
    Lines.Add('    {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := MakeApiName(f.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      if i > 0 then
        Lines.Add('');

      EmitCommentLines(Lines, '        ', f.Comment);

      ParamDecl := 'P2PUid lfUid, string lfP2PName';
      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        PTyp := ABI_Type_To_CSharp_Decl(f.Params[j].PascalType);
        ParamDecl := ParamDecl + ', ' + PTyp + ' ' + PName;
      end;

      if f.IsFunction then
        Lines.Add('        public static ' + ABI_Type_To_CSharp_Decl(f.ReturnType) + ' InternalCall_' + ApiName + '(' + ParamDecl + ')')
      else
        Lines.Add('        public static void InternalCall_' + ApiName + '(' + ParamDecl + ')');
      Lines.Add('        {');
      if f.IsFunction then
        Lines.Add('            return ' + ABI_Type_To_CSharp_Default(f.ReturnType) + ';');
      Lines.Add('        }');
    end;
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    internal static class Callbacks');
    Lines.Add('    {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := MakeApiName(f.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      if i > 0 then
        Lines.Add('');

      if f.IsFunction then
      begin
        Lines.Add('        public static void Callback_' + ApiName + '(DataHandle inHandle, DataHandle outHandle)');
        Lines.Add('        {');
        Lines.Add('            P2PUid lfUid = P2PUid.Empty;');
        Lines.Add('            string lfP2PName = string.Empty;');
        Lines.Add('            try');
        Lines.Add('            {');
        Lines.Add('                lfUid = inHandle.GetSenderUid();');
        Lines.Add('                lfP2PName = inHandle.GetSenderP2PName();');
        Lines.Add('            }');
        Lines.Add('            catch { }');
        Lines.Add('');
        Lines.Add('            try');
        Lines.Add('            {');
        ArgList := 'lfUid, lfP2PName';
        for j := 0 to High(f.Params) do
        begin
          PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
          PTyp := ABI_Type_To_CSharp_Decl(f.Params[j].PascalType);
          ReaderMethod := ABI_Type_To_CSharp_Reader_Method(f.Params[j].PascalType);
          Lines.Add('                ' + PTyp + ' ' + PName + ' = inHandle.' + ReaderMethod + '();');
          ArgList := ArgList + ', ' + PName;
        end;
        RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);
        WriterMethod := ABI_Type_To_CSharp_Writer_Method(f.ReturnType);
        Lines.Add('                ' + RetType + ' ret = InternalCalls.InternalCall_' + ApiName + '(' + ArgList + ');');
        Lines.Add('                outHandle.WriteUInt8(WireStatus.Ok);');
        Lines.Add('                outHandle.' + WriterMethod + '(ret);');
        Lines.Add('            }');
        Lines.Add('            catch (Exception ex)');
        Lines.Add('            {');
        Lines.Add('                outHandle.WriteUInt8(WireStatus.Error);');
        Lines.Add('                outHandle.WriteString(ex.Message);');
        Lines.Add('            }');
        Lines.Add('        }');
      end
      else
      begin
        Lines.Add('        public static void Callback_' + ApiName + '(DataHandle inHandle)');
        Lines.Add('        {');
        Lines.Add('            P2PUid lfUid = P2PUid.Empty;');
        Lines.Add('            string lfP2PName = string.Empty;');
        Lines.Add('            try');
        Lines.Add('            {');
        Lines.Add('                lfUid = inHandle.GetSenderUid();');
        Lines.Add('                lfP2PName = inHandle.GetSenderP2PName();');
        Lines.Add('            }');
        Lines.Add('            catch { }');
        Lines.Add('');
        Lines.Add('            try');
        Lines.Add('            {');
        ArgList := 'lfUid, lfP2PName';
        for j := 0 to High(f.Params) do
        begin
          PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
          PTyp := ABI_Type_To_CSharp_Decl(f.Params[j].PascalType);
          ReaderMethod := ABI_Type_To_CSharp_Reader_Method(f.Params[j].PascalType);
          Lines.Add('                ' + PTyp + ' ' + PName + ' = inHandle.' + ReaderMethod + '();');
          ArgList := ArgList + ', ' + PName;
        end;
        Lines.Add('                InternalCalls.InternalCall_' + ApiName + '(' + ArgList + ');');
        Lines.Add('            }');
        Lines.Add('            catch { }');
        Lines.Add('        }');
      end;
    end;
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    public static class Service');
    Lines.Add('    {');
    Lines.Add('        public static void RegisterAllABIAPIs(AppHandle app)');
    Lines.Add('        {');
    Lines.Add('            if (app == null) throw new ArgumentNullException(nameof(app));');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := MakeApiName(f.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      Description := GetFullDescription(f.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + f.Name;

      if f.IsFunction then
        Lines.Add('            app.RegisterCall(' + CSharpStrLit(ApiName) + ', ' + CSharpStrLit(Description) + ', Callbacks.Callback_' + ApiName + ');')
      else
        Lines.Add('            app.RegisterNotify(' + CSharpStrLit(ApiName) + ', ' + CSharpStrLit(Description) + ', Callbacks.Callback_' + ApiName + ');');
    end;
    Lines.Add('        }');
    Lines.Add('');

    Lines.Add('        public static void RegisterAllP2PABIAPIs()');
    Lines.Add('        {');
    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := MakeApiName(f.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      Description := GetFullDescription(f.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + f.Name;

      if f.IsFunction then
        Lines.Add('            Framework.RegisterP2PCall(' + CSharpStrLit(ApiName) + ', ' + CSharpStrLit(Description) + ', Callbacks.Callback_' + ApiName + ');')
      else
        Lines.Add('            Framework.RegisterP2PNotify(' + CSharpStrLit(ApiName) + ', ' + CSharpStrLit(Description) + ', Callbacks.Callback_' + ApiName + ');');
    end;
    Lines.Add('        }');
    Lines.Add('');

    Lines.Add('        public static AppHandle CreateAndRegisterABIApp()');
    Lines.Add('        {');
    Lines.Add('            var app = new AppHandle(AppInfo.Name, AppInfo.Desc);');
    Lines.Add('            RegisterAllABIAPIs(app);');
    Lines.Add('            return app;');
    Lines.Add('        }');
    Lines.Add('    }');

    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the C# service module.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'csharp',
    'xxx_abi_service.cs',
    gkService,
    'C# ABI service library',
    @GenerateABIServiceCsharpCode);

end.
