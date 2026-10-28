unit pas_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function PascalStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  Current: TP_String;
  NeedBreak: Boolean;
begin
  Result := '';
  Current := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    NeedBreak := (c < #32) or (c = #39) or (Ord(c) > 126);
    if NeedBreak then
    begin
      if Current.Len > 0 then
      begin
        if Result.Len > 0 then Result.Append(' + ');
        Result.Append(#39 + Current + #39);
        Current := '';
      end;
      if Result.Len > 0 then Result.Append(' + ');
      if c = #39 then
        Result.Append(#39 + #39)
      else
        Result.Append('#' + umlIntToStr(Ord(c)));
    end
    else
      Current.Append(c);
  end;
  if Current.Len > 0 then
  begin
    if Result.Len > 0 then Result.Append(' + ');
    Result.Append(#39 + Current + #39);
  end;
  if Result.Len = 0 then
    Result.Append(#39 + #39);
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
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar') then
    Result := 'string'
  else
    Result := '';
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
end;

function ABI_Type_To_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_ReadInt32'
  else if T.Same('int64') then Result := 'LF_ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'LF_ReadUInt32'
  else if T.Same('word') then Result := 'LF_ReadUInt16'
  else if T.Same('smallint') then Result := 'LF_ReadInt16'
  else if T.Same('byte') then Result := 'LF_ReadUInt8'
  else if T.Same('uint64') then Result := 'LF_ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'LF_ReadDouble'
  else if T.Same('single') then Result := 'LF_ReadSingle'
  else if IsStringABIType(T) then Result := 'LF_ReadString'
  else Result := '';
end;

function ABI_Type_To_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_WriteInt32'
  else if T.Same('int64') then Result := 'LF_WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'LF_WriteUInt32'
  else if T.Same('word') then Result := 'LF_WriteUInt16'
  else if T.Same('smallint') then Result := 'LF_WriteInt16'
  else if T.Same('byte') then Result := 'LF_WriteUInt8'
  else if T.Same('uint64') then Result := 'LF_WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'LF_WriteDouble'
  else if T.Same('single') then Result := 'LF_WriteSingle'
  else if IsStringABIType(T) then Result := 'LF_WriteString'
  else Result := '';
end;

function ABI_Type_Default_Expr(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := #39 + #39
  else if T.Same('double') or T.Same('single') or T.Same('extended')
    or T.Same('real') then
    Result := '0.0'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Pascal_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    if i > 0 then
      Result := Result + '; ';
    Result := Result + n + ': ' + ABI_Type_To_Pascal_Decl(Params[i].PascalType);
  end;
end;

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
begin
  Result := 'UID___: TP2P_UID___; p2pName___: string';
  if Length(Params) > 0 then
    Result := Result + '; ' + BuildTypedParamDecl(Params);
end;

function BuildArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildInternalCallArgList(const Params: TParamArray): TP_String;
begin
  Result := '_uid_, _p2p_';
  if Length(Params) > 0 then
    Result := Result + ', ' + BuildArgList(Params);
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

procedure EmitInternalCallImpl(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  if F.IsFunction then
    Lines.Add('function internal_call_' + ApiName + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';')
  else
    Lines.Add('procedure internal_call_' + ApiName + '(' + ParamDecl + ');');
  Lines.Add('begin');
  if F.IsFunction then
    Lines.Add('  Result := ' + ABI_Type_Default_Expr(F.ReturnType) + ';');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitCallbackCallProc(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn, ArgList: TP_String;
  NeedVar: boolean;
begin
  NeedVar := True;
  Lines.Add('procedure Callback_' + ApiName + '(' +
    '_Trigger: Pointer; _In_, _Out_: TDataHnd___); cdecl;');
  if NeedVar then
    Lines.Add('var');
  Lines.Add('  _uidPtr: PP2P_UID___;');
  Lines.Add('  _uid_: TP2P_UID___;');
  Lines.Add('  _p2p_: string;');
  for i := 0 to High(F.Params) do
  begin
    if F.Params[i].Name.Len = 0 then
      PName := 'p' + umlIntToStr(i)
    else
      PName := F.Params[i].Name;
    Lines.Add('  ' + PName + ': ' +
      ABI_Type_To_Pascal_Decl(F.Params[i].PascalType) + ';');
  end;
  if F.IsFunction then
    Lines.Add('  ret: ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';');
  Lines.Add('begin');
  Lines.Add('  FillChar(_uid_, SizeOf(_uid_), 0);');
  Lines.Add('  _uidPtr := LF_Get_P2P_UID(_In_);');
  Lines.Add('  if _uidPtr <> nil then');
  Lines.Add('    _uid_ := _uidPtr^;');
  Lines.Add('  _p2p_ := LF_Get_P2P_NameEx(_In_);');
  Lines.Add('  try');
  for i := 0 to High(F.Params) do
  begin
    if F.Params[i].Name.Len = 0 then
      PName := 'p' + umlIntToStr(i)
    else
      PName := F.Params[i].Name;
    ReadFn := ABI_Type_To_Read_Func(F.Params[i].PascalType);
    Lines.Add('    if not ' + ReadFn + '(_In_, ' + PName + ') then');
    Lines.Add('    begin');
    Lines.Add('      LF_WriteUInt8(_Out_, $FF);');
    Lines.Add('      LF_WriteString(_Out_, ' +
      PascalStrLit('input truncated: ' + PName) + ');');
    Lines.Add('      Exit;');
    Lines.Add('    end;');
  end;
  ArgList := BuildInternalCallArgList(F.Params);
  if F.IsFunction then
    Lines.Add('    ret := internal_call_' + ApiName + '(' + ArgList + ');')
  else
    Lines.Add('    internal_call_' + ApiName + '(' + ArgList + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do');
  Lines.Add('    begin');
  Lines.Add('      LF_WriteUInt8(_Out_, $FF);');
  Lines.Add('      LF_WriteString(_Out_, E.Message);');
  Lines.Add('      Exit;');
  Lines.Add('    end;');
  Lines.Add('  end;');
  Lines.Add('  LF_WriteUInt8(_Out_, $00);');
  if F.IsFunction then
    Lines.Add('  ' + ABI_Type_To_Write_Func(F.ReturnType) + '(_Out_, ret);');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitCallbackNotifyProc(
  Lines: TPascalStringList;
  const ApiName: TP_String;
  const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn, ArgList: TP_String;
begin
  Lines.Add('procedure Callback_' + ApiName + '(' +
    '_Trigger: Pointer; _In_: TDataHnd___); cdecl;');
  Lines.Add('var');
  Lines.Add('  _uidPtr: PP2P_UID___;');
  Lines.Add('  _uid_: TP2P_UID___;');
  Lines.Add('  _p2p_: string;');
  for i := 0 to High(F.Params) do
  begin
    if F.Params[i].Name.Len = 0 then
      PName := 'p' + umlIntToStr(i)
    else
      PName := F.Params[i].Name;
    Lines.Add('  ' + PName + ': ' +
      ABI_Type_To_Pascal_Decl(F.Params[i].PascalType) + ';');
  end;
  Lines.Add('begin');
  Lines.Add('  FillChar(_uid_, SizeOf(_uid_), 0);');
  Lines.Add('  _uidPtr := LF_Get_P2P_UID(_In_);');
  Lines.Add('  if _uidPtr <> nil then');
  Lines.Add('    _uid_ := _uidPtr^;');
  Lines.Add('  _p2p_ := LF_Get_P2P_NameEx(_In_);');
  Lines.Add('  try');
  for i := 0 to High(F.Params) do
  begin
    if F.Params[i].Name.Len = 0 then
      PName := 'p' + umlIntToStr(i)
    else
      PName := F.Params[i].Name;
    ReadFn := ABI_Type_To_Read_Func(F.Params[i].PascalType);
    Lines.Add('    if not ' + ReadFn + '(_In_, ' + PName + ') then');
    Lines.Add('      Exit;');
  end;
  ArgList := BuildInternalCallArgList(F.Params);
  Lines.Add('    internal_call_' + ApiName + '(' + ArgList + ');');
  Lines.Add('  except');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

function GenerateABIServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  ParamDecl, Description: TP_String;

  HeaderLines, InterfaceDeclLines, ImplInternalLines,
    ImplCallbackLines, ImplRegistrationLines: TPascalStringList;
  ResultLines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServicePascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServicePascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating ABI service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceDeclLines := TPascalStringList.Create;
  ImplInternalLines := TPascalStringList.Create;
  ImplCallbackLines := TPascalStringList.Create;
  ImplRegistrationLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    HeaderLines.Add('unit ' + NormalizedUnit + '_abi_service_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('{$ifdef FPC}');
    HeaderLines.Add('  {$mode delphi}{$H+}');
    HeaderLines.Add('  {$MODESWITCH NestedProcVars}');
    HeaderLines.Add('  {$modeswitch advancedrecords}');
    HeaderLines.Add('  {$CODEPAGE UTF8}');
    HeaderLines.Add('{$endif}');
    HeaderLines.Add('{$R-}{$I-}{$Q-}{$B-}');
    HeaderLines.Add('');
    HeaderLines.Add('interface');
    HeaderLines.Add('');
    HeaderLines.Add('uses');
    HeaderLines.Add('  SysUtils, Classes,');
    HeaderLines.Add('  lingofuse_import;');
    HeaderLines.Add('');
    HeaderLines.Add('const');
    HeaderLines.Add('  DEFAULT_APP_NAME: string = ' + PascalStrLit(AppName) + ';');
    HeaderLines.Add('  DEFAULT_APP_DESC: string = ' + PascalStrLit(AppDesc) + ';');
    HeaderLines.Add('');
    HeaderLines.Add('var');
    HeaderLines.Add('  DEBUG_LOG: boolean = True;');
    HeaderLines.Add('');
    HeaderLines.Add('procedure Register_All_ABI_APIs(App: TAppHnd___);');
    HeaderLines.Add('procedure Register_All_P2P_ABI_APIs();');
    HeaderLines.Add('function Create_And_Register_ABI_App: TAppHnd___;');
    HeaderLines.Add('');

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

      EmitCommentLines(InterfaceDeclLines, '', F.Comment);

      ParamDecl := BuildInternalCallParamDecl(F.Params);
      if F.IsFunction then
        InterfaceDeclLines.Add('function internal_call_' + ApiName + '(' +
          ParamDecl + '): ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';')
      else
        InterfaceDeclLines.Add('procedure internal_call_' + ApiName + '(' +
          ParamDecl + ');');
    end;
    InterfaceDeclLines.Add('');

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
      EmitInternalCallImpl(ImplInternalLines, ApiName, F);
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
        EmitCallbackCallProc(ImplCallbackLines, ApiName, F)
      else
        EmitCallbackNotifyProc(ImplCallbackLines, ApiName, F);
    end;

    ImplRegistrationLines.Add('procedure Register_All_ABI_APIs(App: TAppHnd___);');
    ImplRegistrationLines.Add('begin');
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

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;

      if F.IsFunction then
        ImplRegistrationLines.Add('  LF_RegisterCallEx(App, ' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ');')
      else
        ImplRegistrationLines.Add('  LF_RegisterNotifyEx(App, ' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ');');
    end;
    ImplRegistrationLines.Add('end;');
    ImplRegistrationLines.Add('');

    ImplRegistrationLines.Add('procedure Register_All_P2P_ABI_APIs();');
    ImplRegistrationLines.Add('begin');
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

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;

      if F.IsFunction then
        ImplRegistrationLines.Add('  LF_Register_P2P_CallEx(' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ');')
      else
        ImplRegistrationLines.Add('  LF_Register_P2P_NotifyEx(' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ');');
    end;
    ImplRegistrationLines.Add('end;');
    ImplRegistrationLines.Add('');

    ImplRegistrationLines.Add('function Create_And_Register_ABI_App: TAppHnd___;');
    ImplRegistrationLines.Add('begin');
    ImplRegistrationLines.Add('  Result := LF_CreateAppEx(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    ImplRegistrationLines.Add('  if Result <> nil then');
    ImplRegistrationLines.Add('    Register_All_ABI_APIs(Result);');
    ImplRegistrationLines.Add('end;');
    ImplRegistrationLines.Add('');

    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(InterfaceDeclLines);
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(ImplInternalLines);
    ResultLines.Add('');
    ResultLines.AddStrings(ImplCallbackLines);
    ResultLines.Add('');
    ResultLines.AddStrings(ImplRegistrationLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    InterfaceDeclLines.Free;
    ImplInternalLines.Free;
    ImplCallbackLines.Free;
    ImplRegistrationLines.Free;
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'pascal',
    'xxx_abi_service_unit.pas',
    gkService,
    'Pascal ABI service unit',
    @GenerateABIServicePascalCode);

end.
