unit fortran_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallFortranCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

type
  TArryFunctionStructure = array of TFunctionStructure;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[fortran_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[fortran_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Read_Func(const T: TP_String): TP_String;
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

function ABI_Type_To_Write_Func(const T: TP_String): TP_String;
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
  if Result.Len > 0 then
  begin
    if not (((Result[1] >= 'a') and (Result[1] <= 'z')) or
            ((Result[1] >= 'A') and (Result[1] <= 'Z'))) then
      Result := 'abi_' + Result;
  end;
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
    S.Same('req') or S.Same('resp') or S.Same('ret') or S.Same('rc') or
    S.Same('lf_rc') or S.Same('status_byte') or S.Same('str_status') or
    S.Same('app') or S.Same('uid') or S.Same('p2p_name') or
    S.Same('abi_targetapp') or S.Same('abi_timeout') or S.Same('abi_lasterror') or
    S.Same('abi_status_ok') or S.Same('abi_status_error');
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

function BuildParamDeclLines(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeFortranIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Fortran_Decl(Params[i].PascalType);
    if Result <> '' then Result.Append(sLineBreak);
    Result.Append('    ' + PTyp + ', intent(in) :: ' + PName);
  end;
end;

function BuildSignatureParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeFortranIdent(Params[i].Name, i);
    if Result <> '' then Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function BuildSignatureParamListWithPrefix(const Prefix: TP_String; const Params: TParamArray): TP_String;
var
  Inner: TP_String;
begin
  Inner := BuildSignatureParamList(Params);
  if Inner = '' then
    Result := Prefix
  else
    Result := Prefix + ', ' + Inner;
end;

procedure EmitWriteParams(Lines: TPascalStringList; const Params: TParamArray;
  const FailRc: Integer);
var
  i: integer;
  PName, WriteFn: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeFortranIdent(Params[i].Name, i);
    WriteFn := ABI_Type_To_Write_Func(Params[i].PascalType);
    Lines.Add('    lf_rc = ' + WriteFn + '(req, ' + PName + ')');
    Lines.Add('    if (lf_rc /= 1) then');
    Lines.Add('      rc = ' + umlIntToStr(FailRc) + '_c_int32_t');
    Lines.Add('      call lf_data_destroy(req)');
    Lines.Add('      return');
    Lines.Add('    end if');
  end;
end;

procedure EmitReadRetAndCleanup(Lines: TPascalStringList; const RetType: TP_String);
begin
  if IsStringABIType(RetType) then
  begin
    Lines.Add('    call lf_data_read_string(resp, ret, str_status)');
    Lines.Add('    call lf_data_destroy(resp)');
    Lines.Add('    if (str_status < 0_c_int64_t) then');
    Lines.Add('      rc = 6_c_int32_t');
    Lines.Add('      return');
    Lines.Add('    end if');
  end
  else
  begin
    Lines.Add('    lf_rc = ' + ABI_Type_To_Read_Func(RetType) + '(resp, ret)');
    Lines.Add('    call lf_data_destroy(resp)');
    Lines.Add('    if (lf_rc /= 1) then');
    Lines.Add('      rc = 6_c_int32_t');
    Lines.Add('      return');
    Lines.Add('    end if');
  end;
end;

procedure EmitFunctionSubroutine(Lines: TPascalStringList;
  const ApiName, SubName, AddrParamDecl, AddrParamName, CallFn: TP_String;
  const F: TFunctionStructure);
var
  ParamDeclLines, ParamSig, RetDecl, RetInit: TP_String;
begin
  ParamDeclLines := BuildParamDeclLines(F.Params);
  ParamSig := BuildSignatureParamListWithPrefix(AddrParamName, F.Params);

  if IsStringABIType(F.ReturnType) then
  begin
    RetDecl := '    character(len=:), allocatable, intent(out) :: ret';
    RetInit := '    ret = ' + FortranStrLit('');
  end
  else
  begin
    RetDecl := '    ' + ABI_Type_To_Fortran_Decl(F.ReturnType) + ', intent(out) :: ret';
    RetInit := '    ret = ' + ABI_Type_Zero_Value(F.ReturnType);
  end;

  Lines.Add('  subroutine ' + SubName + '(' + ParamSig + ', ret, rc)');
  Lines.Add('    ' + AddrParamDecl);
  if ParamDeclLines <> '' then
    Lines.Add(ParamDeclLines);
  Lines.Add(RetDecl);
  Lines.Add('    integer(c_int32_t), intent(out) :: rc');
  Lines.Add('    type(c_ptr) :: req');
  Lines.Add('    type(c_ptr) :: resp');
  Lines.Add('    integer(c_int) :: lf_rc');
  Lines.Add('    integer(c_int8_t) :: status_byte');
  Lines.Add('    integer(c_int64_t) :: str_status');
  Lines.Add('');
  Lines.Add('    rc = -1_c_int32_t');
  Lines.Add(RetInit);
  Lines.Add('    req = lf_data_create(' + FortranStrLit(ApiName) + ')');
  Lines.Add('    if (.not. c_associated(req)) then');
  Lines.Add('      rc = 1_c_int32_t');
  Lines.Add('      return');
  Lines.Add('    end if');
  Lines.Add('');

  EmitWriteParams(Lines, F.Params, 2);

  Lines.Add('');
  Lines.Add('    resp = ' + CallFn + '(' + AddrParamName + ', req, ABI_Timeout)');
  Lines.Add('    call lf_data_destroy(req)');
  Lines.Add('    if (.not. c_associated(resp)) then');
  Lines.Add('      rc = 3_c_int32_t');
  Lines.Add('      return');
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('    call lf_data_set_position(resp, 0_c_int64_t)');
  Lines.Add('    lf_rc = lf_data_read_uint8(resp, status_byte)');
  Lines.Add('    if (lf_rc /= 1) then');
  Lines.Add('      call lf_data_destroy(resp)');
  Lines.Add('      rc = 4_c_int32_t');
  Lines.Add('      return');
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('    if (status_byte /= ABI_STATUS_OK) then');
  Lines.Add('      call lf_data_read_string(resp, ABI_LastError, str_status)');
  Lines.Add('      call lf_data_destroy(resp)');
  Lines.Add('      rc = 5_c_int32_t');
  Lines.Add('      return');
  Lines.Add('    end if');
  Lines.Add('');

  EmitReadRetAndCleanup(Lines, F.ReturnType);

  Lines.Add('');
  Lines.Add('    rc = 0_c_int32_t');
  Lines.Add('  end subroutine');
  Lines.Add('');
end;

procedure EmitProcedureSubroutine(Lines: TPascalStringList;
  const ApiName, SubName, AddrParamDecl, AddrParamName, CallFn: TP_String;
  const F: TFunctionStructure);
var
  ParamDeclLines, ParamSig: TP_String;
begin
  ParamDeclLines := BuildParamDeclLines(F.Params);
  ParamSig := BuildSignatureParamListWithPrefix(AddrParamName, F.Params);

  Lines.Add('  subroutine ' + SubName + '(' + ParamSig + ', rc)');
  Lines.Add('    ' + AddrParamDecl);
  if ParamDeclLines <> '' then
    Lines.Add(ParamDeclLines);
  Lines.Add('    integer(c_int32_t), intent(out) :: rc');
  Lines.Add('    type(c_ptr) :: req');
  Lines.Add('    integer(c_int) :: lf_rc');
  Lines.Add('');
  Lines.Add('    rc = -1_c_int32_t');
  Lines.Add('    req = lf_data_create(' + FortranStrLit(ApiName) + ')');
  Lines.Add('    if (.not. c_associated(req)) then');
  Lines.Add('      rc = 1_c_int32_t');
  Lines.Add('      return');
  Lines.Add('    end if');
  Lines.Add('');

  EmitWriteParams(Lines, F.Params, 2);

  Lines.Add('');
  Lines.Add('    call ' + CallFn + '(' + AddrParamName + ', req)');
  Lines.Add('    call lf_data_destroy(req)');
  Lines.Add('    rc = 0_c_int32_t');
  Lines.Add('  end subroutine');
  Lines.Add('');
end;

procedure EmitAllVariantsForFunction(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitFunctionSubroutine(Lines, ApiName, ApiName,
    'character(len=*), intent(in) :: app', 'app', 'lf_call', F);

  EmitFunctionSubroutine(Lines, ApiName, ApiName + '_UID_Call',
    'integer(c_int8_t), intent(in) :: uid(LF_UID_BYTE_COUNT)', 'uid', 'lf_call_uid', F);

  EmitFunctionSubroutine(Lines, ApiName, ApiName + '_P2PName_Call',
    'character(len=*), intent(in) :: p2p_name', 'p2p_name', 'lf_call_p2pname', F);
end;

procedure EmitAllVariantsForProcedure(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitProcedureSubroutine(Lines, ApiName, ApiName,
    'character(len=*), intent(in) :: app', 'app', 'lf_notify', F);

  EmitProcedureSubroutine(Lines, ApiName, ApiName + '_UID_Notify',
    'integer(c_int8_t), intent(in) :: uid(LF_UID_BYTE_COUNT)', 'uid', 'lf_notify_uid', F);

  EmitProcedureSubroutine(Lines, ApiName, ApiName + '_P2PName_Notify',
    'character(len=*), intent(in) :: p2p_name', 'p2p_name', 'lf_notify_p2pname', F);
end;

function GenerateABICallFortranCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetApp: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallFortranCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallFortranCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetApp := NormalizedUnit + '_abi';

  Log(PFormat('Generating Fortran ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Call covers %d ABI APIs', [Length(SupportedFuncs)]));

  ApiNames := BuildUniqueApiNames(SupportedFuncs);
  Lines := TPascalStringList.Create;
  try
    Lines.Add('module ' + NormalizedUnit.Text + '_abi_call');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  implicit none');
    Lines.Add('  private');
    Lines.Add('  public :: ABI_TargetApp, ABI_Timeout, ABI_LastError');
    for i := 0 to High(SupportedFuncs) do
    begin
      if SupportedFuncs[i].IsFunction then
      begin
        Lines.Add('  public :: ' + ApiNames[i]);
        Lines.Add('  public :: ' + ApiNames[i] + '_UID_Call');
        Lines.Add('  public :: ' + ApiNames[i] + '_P2PName_Call');
      end
      else
      begin
        Lines.Add('  public :: ' + ApiNames[i]);
        Lines.Add('  public :: ' + ApiNames[i] + '_UID_Notify');
        Lines.Add('  public :: ' + ApiNames[i] + '_P2PName_Notify');
      end;
    end;
    Lines.Add('');
    Lines.Add('  character(len=64), save :: ABI_TargetApp = ' + FortranStrLit(TargetApp));
    Lines.Add('  integer(c_int64_t), save :: ABI_Timeout = 5000_c_int64_t');
    Lines.Add('  character(len=:), allocatable, save :: ABI_LastError');
    Lines.Add('  integer(c_int8_t), parameter :: ABI_STATUS_OK = int(z''00'', c_int8_t)');
    Lines.Add('  integer(c_int8_t), parameter :: ABI_STATUS_ERROR = int(z''FF'', c_int8_t)');
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      if SupportedFuncs[i].IsFunction then
        EmitAllVariantsForFunction(Lines, ApiNames[i], SupportedFuncs[i])
      else
        EmitAllVariantsForProcedure(Lines, ApiNames[i], SupportedFuncs[i]);

    Lines.Add('end module ' + NormalizedUnit.Text + '_abi_call');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Fortran ABI call', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'fortran',
    'xxx_abi_call.f90',
    gkCall,
    'Fortran ABI call module',
    @GenerateABICallFortranCode);

end.
