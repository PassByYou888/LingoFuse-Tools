unit fortran_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceFortranCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

type
  TArryFunctionStructure = array of TFunctionStructure;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[fortran_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[fortran_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Fortran_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'integer(c_int32_t)'
  else if T.Same('int64') then
    Result := 'integer(c_int64_t)'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'integer(c_int32_t)'
  else if T.Same('word') then
    Result := 'integer(c_int16_t)'
  else if T.Same('smallint') then
    Result := 'integer(c_int16_t)'
  else if T.Same('byte') then
    Result := 'integer(c_int8_t)'
  else if T.Same('uint64') then
    Result := 'integer(c_int64_t)'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'real(c_double)'
  else if T.Same('single') then
    Result := 'real(c_float)'
  else if IsStringABIType(T) then
    Result := 'character(len=:), allocatable'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Fortran_Decl(T) <> '';
end;

function ABI_Type_To_Read_Call(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'lf_data_read_int32'
  else if T.Same('int64') then Result := 'lf_data_read_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'lf_data_read_uint32'
  else if T.Same('word') then Result := 'lf_data_read_uint16'
  else if T.Same('smallint') then Result := 'lf_data_read_int16'
  else if T.Same('byte') then Result := 'lf_data_read_uint8'
  else if T.Same('uint64') then Result := 'lf_data_read_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'lf_data_read_float64'
  else if T.Same('single') then Result := 'lf_data_read_float32'
  else Result := '';
end;

function ABI_Type_To_Write_Call(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'lf_data_write_int32'
  else if T.Same('int64') then Result := 'lf_data_write_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'lf_data_write_uint32'
  else if T.Same('word') then Result := 'lf_data_write_uint16'
  else if T.Same('smallint') then Result := 'lf_data_write_int16'
  else if T.Same('byte') then Result := 'lf_data_write_uint8'
  else if T.Same('uint64') then Result := 'lf_data_write_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'lf_data_write_float64'
  else if T.Same('single') then Result := 'lf_data_write_float32'
  else if IsStringABIType(T) then Result := 'lf_data_write_string'
  else Result := '';
end;

function ABI_Type_Zero_Value(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') or T.Same('cardinal')
    or T.Same('dword') or T.Same('longword') then
    Result := '0_c_int32_t'
  else if T.Same('int64') or T.Same('uint64') then
    Result := '0_c_int64_t'
  else if T.Same('word') or T.Same('smallint') then
    Result := '0_c_int16_t'
  else if T.Same('byte') then
    Result := '0_c_int8_t'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := '0.0_c_double'
  else if T.Same('single') then
    Result := '0.0_c_float'
  else
    Result := '0';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function FortranStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  Result.Append(#39);
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append(#39);
      Result.Append(#39);
    end
    else
      Result.Append(c);
  end;
  Result.Append(#39);
end;

function IsFortranReservedIdent(const S: TP_String): boolean;
begin
  Result :=
    S.Same('uid') or S.Same('p2p_name') or
    S.Same('input') or S.Same('output') or
    S.Same('ret') or S.Same('istat') or
    S.Same('rc') or S.Same('lf_rc') or
    S.Same('str_status') or S.Same('app') or
    S.Same('failed_count') or S.Same('dummy_rc');
end;

function MakeSafeFortranIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsFortranReservedIdent(Result) then
    Result := Result + '_p';
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

function BuildUniqueApiNames(const Funcs: TArryFunctionStructure): TPascalStringList;
var
  i, j: integer;
  ApiName: TP_String;
begin
  Result := TPascalStringList.Create;
  for i := 0 to High(Funcs) do
  begin
    ApiName := MakeApiName(Funcs[i].Name);
    if Result.IndexOf(ApiName) >= 0 then
    begin
      j := 1;
      while Result.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      ApiName := ApiName + '_' + umlIntToStr(j).Text;
    end;
    Result.Add(ApiName);
  end;
end;

procedure EmitInternalCallStub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  j: integer;
  ParamDecl, SigArgs: TP_String;
begin
  ParamDecl := '';
  for j := 0 to High(F.Params) do
  begin
    if ParamDecl <> '' then ParamDecl := ParamDecl + ', ';
    ParamDecl := ParamDecl + MakeSafeFortranIdent(F.Params[j].Name, j);
  end;

  if ParamDecl <> '' then
    SigArgs := 'uid, p2p_name, ' + ParamDecl
  else
    SigArgs := 'uid, p2p_name';

  if F.IsFunction then
  begin
    Lines.Add('  function internal_call_' + ApiName + '(' + SigArgs + ') result(ret)');
    Lines.Add('    integer(c_int8_t), intent(in) :: uid(LF_UID_BYTE_COUNT)');
    Lines.Add('    character(len=*), intent(in) :: p2p_name');
    for j := 0 to High(F.Params) do
    begin
      Lines.Add('    ' + ABI_Type_To_Fortran_Decl(F.Params[j].PascalType) + ', intent(in) :: ' +
        MakeSafeFortranIdent(F.Params[j].Name, j));
    end;
    if IsStringABIType(F.ReturnType) then
    begin
      Lines.Add('    character(len=:), allocatable :: ret');
      Lines.Add('    allocate(character(len=0) :: ret)');
    end
    else
    begin
      Lines.Add('    ' + ABI_Type_To_Fortran_Decl(F.ReturnType) + ' :: ret');
      Lines.Add('    ret = ' + ABI_Type_Zero_Value(F.ReturnType));
    end;
    Lines.Add('  end function');
    Lines.Add('');
  end
  else
  begin
    Lines.Add('  subroutine internal_call_' + ApiName + '(' + SigArgs + ')');
    Lines.Add('    integer(c_int8_t), intent(in) :: uid(LF_UID_BYTE_COUNT)');
    Lines.Add('    character(len=*), intent(in) :: p2p_name');
    for j := 0 to High(F.Params) do
    begin
      Lines.Add('    ' + ABI_Type_To_Fortran_Decl(F.Params[j].PascalType) + ', intent(in) :: ' +
        MakeSafeFortranIdent(F.Params[j].Name, j));
    end;
    Lines.Add('  end subroutine');
    Lines.Add('');
  end;
end;

procedure EmitCallback(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  j: integer;
  ParamName, ParamType, CallArgs: TP_String;
begin
  if F.IsFunction then
  begin
    Lines.Add('  subroutine ' + ApiName + '_callback(input, output) bind(C)');
    Lines.Add('    type(c_ptr), value :: input');
    Lines.Add('    type(c_ptr), value :: output');
  end
  else
  begin
    Lines.Add('  subroutine ' + ApiName + '_callback(input) bind(C)');
    Lines.Add('    type(c_ptr), value :: input');
  end;

  Lines.Add('    integer(c_int8_t) :: uid(LF_UID_BYTE_COUNT)');
  Lines.Add('    character(len=:), allocatable :: p2p_name');
  Lines.Add('    integer(c_int) :: lf_rc');
  Lines.Add('    integer(c_int64_t) :: str_status');

  for j := 0 to High(F.Params) do
  begin
    ParamName := MakeSafeFortranIdent(F.Params[j].Name, j);
    ParamType := F.Params[j].PascalType;
    if IsStringABIType(ParamType) then
      Lines.Add('    character(len=:), allocatable :: ' + ParamName)
    else
      Lines.Add('    ' + ABI_Type_To_Fortran_Decl(ParamType) + ' :: ' + ParamName);
  end;

  if F.IsFunction then
  begin
    if IsStringABIType(F.ReturnType) then
      Lines.Add('    character(len=:), allocatable :: ret')
    else
      Lines.Add('    ' + ABI_Type_To_Fortran_Decl(F.ReturnType) + ' :: ret');
  end;

  Lines.Add('');
  Lines.Add('    uid = int(z''00'', c_int8_t)');
  Lines.Add('    lf_rc = lf_data_get_p2p_uid(input, uid)');
  Lines.Add('    call lf_data_get_p2p_name(input, p2p_name)');
  Lines.Add('');

  for j := 0 to High(F.Params) do
  begin
    ParamName := MakeSafeFortranIdent(F.Params[j].Name, j);
    ParamType := F.Params[j].PascalType;
    if IsStringABIType(ParamType) then
    begin
      Lines.Add('    call lf_data_read_string(input, ' + ParamName + ', str_status)');
      Lines.Add('    if (str_status < 0_c_int64_t) then');
      if F.IsFunction then
      begin
        Lines.Add('      lf_rc = lf_data_write_uint8(output, ABI_STATUS_ERROR)');
        Lines.Add('      lf_rc = lf_data_write_string(output, ' +
          FortranStrLit('truncated input: ' + ParamName) + ')');
      end;
      Lines.Add('      return');
      Lines.Add('    end if');
    end
    else
    begin
      Lines.Add('    lf_rc = ' + ABI_Type_To_Read_Call(ParamType) + '(input, ' + ParamName + ')');
      Lines.Add('    if (lf_rc /= 1) then');
      if F.IsFunction then
      begin
        Lines.Add('      lf_rc = lf_data_write_uint8(output, ABI_STATUS_ERROR)');
        Lines.Add('      lf_rc = lf_data_write_string(output, ' +
          FortranStrLit('truncated input: ' + ParamName) + ')');
      end;
      Lines.Add('      return');
      Lines.Add('    end if');
    end;
  end;

  Lines.Add('');

  CallArgs := '';
  for j := 0 to High(F.Params) do
  begin
    CallArgs := CallArgs + ', ' + MakeSafeFortranIdent(F.Params[j].Name, j);
  end;

  if F.IsFunction then
  begin
    Lines.Add('    ret = internal_call_' + ApiName + '(uid, p2p_name' + CallArgs + ')');
    Lines.Add('    lf_rc = lf_data_write_uint8(output, ABI_STATUS_OK)');
    Lines.Add('    lf_rc = ' + ABI_Type_To_Write_Call(F.ReturnType) + '(output, ret)');
  end
  else
  begin
    Lines.Add('    call internal_call_' + ApiName + '(uid, p2p_name' + CallArgs + ')');
  end;

  Lines.Add('  end subroutine');
  Lines.Add('');
end;

procedure EmitRegisterFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Desc, RegFunc: TP_String;
begin
  Lines.Add('  function register_all_abi_apis(app) result(failed_count)');
  Lines.Add('    type(c_ptr), value :: app');
  Lines.Add('    integer(c_int) :: failed_count');
  Lines.Add('    failed_count = 0_c_int');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Desc := GetFullDescription(F.Comment);
    if Desc.Len = 0 then
      Desc := 'ABI api for ' + F.Name;

    if F.IsFunction then
      RegFunc := 'lf_app_register_call'
    else
      RegFunc := 'lf_app_register_notify';

    Lines.Add('    if (' + RegFunc + '(app, ' + FortranStrLit(ApiName) + ', ' +
      FortranStrLit(Desc) + ', c_funloc(' + ApiName + '_callback)) /= 1_c_int) then');
    Lines.Add('      failed_count = failed_count + 1_c_int');
    Lines.Add('    end if');
  end;

  Lines.Add('  end function');
  Lines.Add('');

  Lines.Add('  function register_all_p2p_abi_apis() result(failed_count)');
  Lines.Add('    integer(c_int) :: failed_count');
  Lines.Add('    failed_count = 0_c_int');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Desc := GetFullDescription(F.Comment);
    if Desc.Len = 0 then
      Desc := 'ABI api for ' + F.Name;

    if F.IsFunction then
      RegFunc := 'lf_register_p2p_call'
    else
      RegFunc := 'lf_register_p2p_notify';

    Lines.Add('    if (' + RegFunc + '(' + FortranStrLit(ApiName) + ', ' +
      FortranStrLit(Desc) + ', c_funloc(' + ApiName + '_callback)) /= 1_c_int) then');
    Lines.Add('      failed_count = failed_count + 1_c_int');
    Lines.Add('    end if');
  end;

  Lines.Add('  end function');
  Lines.Add('');
end;

function GenerateABIServiceFortranCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceFortranCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceFortranCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Fortran ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service covers %d ABI APIs', [Length(SupportedFuncs)]));

  ApiNames := BuildUniqueApiNames(SupportedFuncs);
  Lines := TPascalStringList.Create;
  try
    Lines.Add('module ' + NormalizedUnit.Text + '_abi_service');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  implicit none');
    Lines.Add('  private');
    Lines.Add('  public :: DEFAULT_APP_NAME, DEFAULT_APP_DESC');
    Lines.Add('  public :: create_and_register_abi_app');
    Lines.Add('  public :: register_all_abi_apis, register_all_p2p_abi_apis');
    Lines.Add('');
    Lines.Add('  character(len=*), parameter :: DEFAULT_APP_NAME = ' + FortranStrLit(AppName));
    Lines.Add('  character(len=*), parameter :: DEFAULT_APP_DESC = ' + FortranStrLit(AppDesc));
    Lines.Add('  integer(c_int8_t), parameter :: ABI_STATUS_OK = int(z''00'', c_int8_t)');
    Lines.Add('  integer(c_int8_t), parameter :: ABI_STATUS_ERROR = int(z''FF'', c_int8_t)');
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      EmitInternalCallStub(Lines, ApiNames[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
      EmitCallback(Lines, ApiNames[i], SupportedFuncs[i]);

    EmitRegisterFunctions(Lines, SupportedFuncs, ApiNames);

    Lines.Add('  function create_and_register_abi_app() result(app)');
    Lines.Add('    type(c_ptr) :: app');
    Lines.Add('    integer(c_int) :: dummy_rc');
    Lines.Add('    app = lf_app_create(DEFAULT_APP_NAME, DEFAULT_APP_DESC)');
    Lines.Add('    if (c_associated(app)) then');
    Lines.Add('      dummy_rc = register_all_abi_apis(app)');
    Lines.Add('    end if');
    Lines.Add('  end function');
    Lines.Add('');

    Lines.Add('end module ' + NormalizedUnit.Text + '_abi_service');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Fortran ABI service', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'fortran',
    'xxx_abi_service.f90',
    gkService,
    'Fortran ABI service module',
    @GenerateABIServiceFortranCode);

end.
