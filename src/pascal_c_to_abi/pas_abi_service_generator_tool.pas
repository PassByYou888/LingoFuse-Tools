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

function ABI_Type_Is_LF_Binary_Data(const T: TP_String): boolean;
begin
  Result := T.Same('tbytes') or T.Same('array of byte') or T.Same('cbytes');
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring')
    or T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar')
    or T.Same('pwidechar');
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
  else if IsStringABIType(T) then Result := 'string'
  else if ABI_Type_Is_LF_Binary_Data(T) then Result := 'PLF_Binary_Data'
  else Result := '';
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
  else if ABI_Type_Is_LF_Binary_Data(T) then Result := 'LF_Read_LF_Binary_Data'
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
  else if ABI_Type_Is_LF_Binary_Data(T) then Result := 'LF_Write_LF_Binary_Data'
  else Result := '';
end;

function ABI_Type_Default_Expr(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_LF_Binary_Data(T) then
    Result := 'nil'
  else if IsStringABIType(T) then
    Result := #39#39
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

function IsPascalReservedWord(const S: TP_String): Boolean;
begin
  Result :=
    S.Same('and') or S.Same('array') or S.Same('as') or S.Same('asm') or
    S.Same('begin') or S.Same('case') or S.Same('class') or S.Same('const') or
    S.Same('constructor') or S.Same('destructor') or S.Same('div') or S.Same('do') or
    S.Same('downto') or S.Same('else') or S.Same('end') or S.Same('except') or
    S.Same('exports') or S.Same('file') or S.Same('finalization') or S.Same('finally') or
    S.Same('for') or S.Same('function') or S.Same('goto') or S.Same('if') or
    S.Same('implementation') or S.Same('in') or S.Same('inherited') or S.Same('initialization') or
    S.Same('inline') or S.Same('interface') or S.Same('is') or S.Same('label') or
    S.Same('library') or S.Same('mod') or S.Same('nil') or S.Same('not') or
    S.Same('object') or S.Same('of') or S.Same('or') or S.Same('out') or
    S.Same('packed') or S.Same('procedure') or S.Same('program') or S.Same('property') or
    S.Same('raise') or S.Same('record') or S.Same('repeat') or S.Same('resourcestring') or
    S.Same('set') or S.Same('shl') or S.Same('shr') or S.Same('string') or
    S.Same('then') or S.Same('threadvar') or S.Same('to') or S.Same('try') or
    S.Same('type') or S.Same('unit') or S.Same('until') or S.Same('uses') or
    S.Same('var') or S.Same('while') or S.Same('with') or S.Same('xor') or
    S.Same('result');
end;

function MakeSafePascalParamName(const Name: TP_String; Index: Integer): TP_String;
var
  i: Integer;
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
  if IsPascalReservedWord(Result) then
    Result := Result + '_';
end;

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePascalParamName(Params[i].Name, i);
    if i > 0 then Result := Result + '; ';
    Result := Result + n + ': ' + ABI_Type_To_Pascal_Decl(Params[i].PascalType);
  end;
end;

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
begin
  Result := 'UID___: TP2P_UID___; p2pName___: string';
  if Length(Params) > 0 then
    Result := Result + '; ' + BuildTypedParamDecl(Params);
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

procedure EmitInternalCallStub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetDecl: TP_String;
begin
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  RetDecl := ABI_Type_To_Pascal_Decl(F.ReturnType);

  if F.IsFunction then
    Lines.Add('function internal_call_' + ApiName + '(' + ParamDecl + '): ' + RetDecl + ';')
  else
    Lines.Add('procedure internal_call_' + ApiName + '(' + ParamDecl + ');');

  Lines.Add('begin');
  if F.IsFunction then
    Lines.Add('  Result := ' + ABI_Type_Default_Expr(F.ReturnType) + ';');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitCallbackCallProc(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, ReadFn, ArgList, WriteFn, RetDecl: TP_String;
begin
  RetDecl := ABI_Type_To_Pascal_Decl(F.ReturnType);

  Lines.Add('procedure Callback_' + ApiName + '(' +
    '_Trigger: Pointer; _In_, _Out_: TDataHnd___); cdecl;');
  Lines.Add('var');
  Lines.Add('  _uidPtr: PP2P_UID___;');
  Lines.Add('  _uid_: TP2P_UID___;');
  Lines.Add('  _p2p_: string;');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    Lines.Add('  _' + PName + ': ' + ABI_Type_To_Pascal_Decl(F.Params[i].PascalType) + ';');
  end;
  Lines.Add('  _ret: ' + RetDecl + ';');
  Lines.Add('begin');
  Lines.Add('  FillChar(_uid_, SizeOf(_uid_), 0);');
  Lines.Add('  _uidPtr := LF_Get_P2P_UID(_In_);');
  Lines.Add('  if _uidPtr <> nil then');
  Lines.Add('    _uid_ := _uidPtr^;');
  Lines.Add('  _p2p_ := LF_Get_P2P_NameEx(_In_);');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    if ABI_Type_Is_LF_Binary_Data(F.Params[i].PascalType) then
      Lines.Add('  _' + PName + ' := nil;')
    else if IsStringABIType(F.Params[i].PascalType) then
      Lines.Add('  _' + PName + ' := ' + #39#39 + ';')
    else if F.Params[i].PascalType.Same('double') or
            F.Params[i].PascalType.Same('single') or
            F.Params[i].PascalType.Same('extended') or
            F.Params[i].PascalType.Same('real') then
      Lines.Add('  _' + PName + ' := 0.0;')
    else
      Lines.Add('  _' + PName + ' := 0;');
  end;
  if ABI_Type_Is_LF_Binary_Data(F.ReturnType) then
    Lines.Add('  _ret := nil;')
  else if IsStringABIType(F.ReturnType) then
    Lines.Add('  _ret := ' + #39#39 + ';')
  else if F.ReturnType.Same('double') or F.ReturnType.Same('single') or
          F.ReturnType.Same('extended') or F.ReturnType.Same('real') then
    Lines.Add('  _ret := 0.0;')
  else
    Lines.Add('  _ret := 0;');
  Lines.Add('  try');
  Lines.Add('    try');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    ReadFn := ABI_Type_To_Read_Func(F.Params[i].PascalType);
    Lines.Add('      if not ' + ReadFn + '(_In_, _' + PName + ') then');
    Lines.Add('      begin');
    Lines.Add('        if LF_WriteUInt8(_Out_, $FF) then');
    Lines.Add('          LF_WriteString(_Out_, ' + PascalStrLit('input truncated: ' + PName.Text) + ');');
    Lines.Add('        Exit;');
    Lines.Add('      end;');
  end;
  ArgList := '_uid_, _p2p_';
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    ArgList := ArgList + ', _' + PName;
  end;
  Lines.Add('      _ret := internal_call_' + ApiName + '(' + ArgList + ');');
  Lines.Add('    except');
  Lines.Add('      on E: Exception do');
  Lines.Add('      begin');
  Lines.Add('        if LF_WriteUInt8(_Out_, $FF) then');
  Lines.Add('          LF_WriteString(_Out_, E.Message);');
  Lines.Add('        Exit;');
  Lines.Add('      end;');
  Lines.Add('    end;');
  WriteFn := ABI_Type_To_Write_Func(F.ReturnType);
  Lines.Add('    if LF_WriteUInt8(_Out_, $00) then');
  Lines.Add('      ' + WriteFn + '(_Out_, _ret);');
  Lines.Add('  finally');
  for i := 0 to High(F.Params) do
    if ABI_Type_Is_LF_Binary_Data(F.Params[i].PascalType) then
    begin
      PName := MakeSafePascalParamName(F.Params[i].Name, i);
      Lines.Add('    if _' + PName + ' <> nil then FreeLF_Binary_Data(_' + PName + ');');
    end;
  if ABI_Type_Is_LF_Binary_Data(F.ReturnType) then
    Lines.Add('    if _ret <> nil then FreeLF_Binary_Data(_ret);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitCallbackNotifyProc(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
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
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    Lines.Add('  _' + PName + ': ' + ABI_Type_To_Pascal_Decl(F.Params[i].PascalType) + ';');
  end;
  Lines.Add('begin');
  Lines.Add('  FillChar(_uid_, SizeOf(_uid_), 0);');
  Lines.Add('  _uidPtr := LF_Get_P2P_UID(_In_);');
  Lines.Add('  if _uidPtr <> nil then');
  Lines.Add('    _uid_ := _uidPtr^;');
  Lines.Add('  _p2p_ := LF_Get_P2P_NameEx(_In_);');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    if ABI_Type_Is_LF_Binary_Data(F.Params[i].PascalType) then
      Lines.Add('  _' + PName + ' := nil;')
    else if IsStringABIType(F.Params[i].PascalType) then
      Lines.Add('  _' + PName + ' := ' + #39#39 + ';')
    else if F.Params[i].PascalType.Same('double') or
            F.Params[i].PascalType.Same('single') or
            F.Params[i].PascalType.Same('extended') or
            F.Params[i].PascalType.Same('real') then
      Lines.Add('  _' + PName + ' := 0.0;')
    else
      Lines.Add('  _' + PName + ' := 0;');
  end;
  Lines.Add('  try');
  Lines.Add('    try');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    ReadFn := ABI_Type_To_Read_Func(F.Params[i].PascalType);
    Lines.Add('      if not ' + ReadFn + '(_In_, _' + PName + ') then');
    Lines.Add('        Exit;');
  end;
  ArgList := '_uid_, _p2p_';
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafePascalParamName(F.Params[i].Name, i);
    ArgList := ArgList + ', _' + PName;
  end;
  Lines.Add('      internal_call_' + ApiName + '(' + ArgList + ');');
  Lines.Add('    except');
  Lines.Add('    end;');
  Lines.Add('  finally');
  for i := 0 to High(F.Params) do
    if ABI_Type_Is_LF_Binary_Data(F.Params[i].PascalType) then
    begin
      PName := MakeSafePascalParamName(F.Params[i].Name, i);
      Lines.Add('    if _' + PName + ' <> nil then FreeLF_Binary_Data(_' + PName + ');');
    end;
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
  ApiName, ParamDecl, Description: TP_String;
  F: TFunctionStructure;
  HeaderLines, InterfaceDeclLines, ImplStubLines,
    ImplCallbackLines, ImplRegistrationLines: TPascalStringList;
  ResultLines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating ABI service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceDeclLines := TPascalStringList.Create;
  ImplStubLines := TPascalStringList.Create;
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
    HeaderLines.Add('  lingofuse_import,');
    HeaderLines.Add('  abi_wire_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('const');
    HeaderLines.Add('  DEFAULT_APP_NAME: string = ' + PascalStrLit(AppName) + ';');
    HeaderLines.Add('  DEFAULT_APP_DESC: string = ' + PascalStrLit(AppDesc) + ';');
    HeaderLines.Add('');
    HeaderLines.Add('function Register_All_ABI_APIs(App: TAppHnd___): Integer;');
    HeaderLines.Add('function Register_All_P2P_ABI_APIs: Integer;');
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
      EmitInternalCallStub(ImplStubLines, ApiName, F);
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

    ImplRegistrationLines.Add('function Register_All_ABI_APIs(App: TAppHnd___): Integer;');
    ImplRegistrationLines.Add('begin');
    ImplRegistrationLines.Add('  Result := 0;');
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

      Description := 'ABI api for ' + F.Name;

      if F.IsFunction then
        ImplRegistrationLines.Add('  if LF_RegisterCallEx(App, ' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ') <> 1 then Inc(Result);')
      else
        ImplRegistrationLines.Add('  if LF_RegisterNotifyEx(App, ' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ') <> 1 then Inc(Result);');
    end;
    ImplRegistrationLines.Add('end;');
    ImplRegistrationLines.Add('');

    ImplRegistrationLines.Add('function Register_All_P2P_ABI_APIs: Integer;');
    ImplRegistrationLines.Add('begin');
    ImplRegistrationLines.Add('  Result := 0;');
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

      Description := 'ABI api for ' + F.Name;

      if F.IsFunction then
        ImplRegistrationLines.Add('  if LF_Register_P2P_CallEx(' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ') <> 1 then Inc(Result);')
      else
        ImplRegistrationLines.Add('  if LF_Register_P2P_NotifyEx(' +
          PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) +
          ', nil, @Callback_' + ApiName + ') <> 1 then Inc(Result);');
    end;
    ImplRegistrationLines.Add('end;');
    ImplRegistrationLines.Add('');

    ImplRegistrationLines.Add('function Create_And_Register_ABI_App: TAppHnd___;');
    ImplRegistrationLines.Add('var');
    ImplRegistrationLines.Add('  _f: Integer;');
    ImplRegistrationLines.Add('begin');
    ImplRegistrationLines.Add('  Result := LF_CreateAppEx(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    ImplRegistrationLines.Add('  if Result <> nil then');
    ImplRegistrationLines.Add('  begin');
    ImplRegistrationLines.Add('    _f := Register_All_ABI_APIs(Result);');
    ImplRegistrationLines.Add('    if _f > 0 then');
    ImplRegistrationLines.Add('      try');
    ImplRegistrationLines.Add('        WriteLn(' + #39 + '[WARN] ' + #39 + ', _f, ' + #39 + ' ABI API(s) failed to register' + #39 + ');');
    ImplRegistrationLines.Add('      except');
    ImplRegistrationLines.Add('      end;');
    ImplRegistrationLines.Add('  end;');
    ImplRegistrationLines.Add('end;');
    ImplRegistrationLines.Add('');

    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(InterfaceDeclLines);
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(ImplStubLines);
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
    ImplStubLines.Free;
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
