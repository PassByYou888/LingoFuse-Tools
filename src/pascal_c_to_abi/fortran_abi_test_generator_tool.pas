unit fortran_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceTestFortranCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABICallTestFortranCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

type
  TArryFunctionStructure = array of TFunctionStructure;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[fortran_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[fortran_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Fortran_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'integer(c_int32_t)'
  else if T.Same('int64') then Result := 'integer(c_int64_t)'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'integer(c_int32_t)'
  else if T.Same('word') then Result := 'integer(c_int16_t)'
  else if T.Same('smallint') then Result := 'integer(c_int16_t)'
  else if T.Same('byte') then Result := 'integer(c_int8_t)'
  else if T.Same('uint64') then Result := 'integer(c_int64_t)'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'real(c_double)'
  else if T.Same('single') then Result := 'real(c_float)'
  else if IsStringABIType(T) then Result := 'character(len=:), allocatable'
  else Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Fortran_Decl(T) <> '';
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
    S.Same('uid') or S.Same('p2p_name') or S.Same('input') or S.Same('output') or
    S.Same('ret') or S.Same('rc') or S.Same('lf_rc') or S.Same('str_status') or
    S.Same('status_byte') or S.Same('app') or S.Same('req') or S.Same('resp') or
    S.Same('g_pass') or S.Same('g_fail') or S.Same('g_skip') or
    S.Same('g_running') or S.Same('g_uptime_ms') or
    S.Same('g_client_uid') or S.Same('g_service_uid') or
    S.Same('g_pending_callback') or S.Same('g_service_called_me') or
    S.Same('g_has_service_uid') or
    S.Same('pass') or S.Same('fail') or S.Same('local_rc') or
    S.Same('msg') or S.Same('uidPtr') or
    S.Same('s') or S.Same('hexch') or S.Same('j') or S.Same('v');
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

function PlaceholderValue(const ABIType: TP_String): TP_String;
begin
  if IsStringABIType(ABIType) then
    Result := FortranStrLit('test')
  else if ABIType.Same('double') or ABIType.Same('extended') or ABIType.Same('real') then
    Result := '3.14_c_double'
  else if ABIType.Same('single') then
    Result := '3.14_c_float'
  else if ABIType.Same('int64') or ABIType.Same('uint64') then
    Result := '42_c_int64_t'
  else if ABIType.Same('word') or ABIType.Same('smallint') then
    Result := '42_c_int16_t'
  else if ABIType.Same('byte') then
    Result := '42_c_int8_t'
  else
    Result := '42_c_int32_t';
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
        Break;
      end;
    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
      Supported := False;
    if Supported and (f.Name.Len = 0) then
      Supported := False;
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

function BuildPlaceholderArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Result <> '' then Result := Result + ', ';
    Result := Result + PlaceholderValue(Params[i].PascalType);
  end;
end;

procedure EmitArgsAndReturnVars(Lines: TPascalStringList; const F: TFunctionStructure);
var
  j: integer;
begin
  for j := 0 to High(F.Params) do
  begin
    if IsStringABIType(F.Params[j].PascalType) then
      Lines.Add('  character(len=:), allocatable :: p' + umlIntToStr(j).Text)
    else
      Lines.Add('  ' + ABI_Type_To_Fortran_Decl(F.Params[j].PascalType) +
        ' :: p' + umlIntToStr(j).Text);
  end;
  if F.IsFunction then
  begin
    if IsStringABIType(F.ReturnType) then
      Lines.Add('  character(len=:), allocatable :: ret')
    else
      Lines.Add('  ' + ABI_Type_To_Fortran_Decl(F.ReturnType) + ' :: ret');
  end;
end;

procedure EmitAssignPlaceholders(Lines: TPascalStringList; const F: TFunctionStructure);
var
  j: integer;
begin
  for j := 0 to High(F.Params) do
    Lines.Add('  p' + umlIntToStr(j).Text + ' = ' + PlaceholderValue(F.Params[j].PascalType));
end;

procedure EmitFunctionTestCall(Lines: TPascalStringList; const ApiName: TP_String);
begin
  Lines.Add('  call test_' + ApiName + '(g_pass, g_fail)');
end;

procedure EmitProcedureTestCall(Lines: TPascalStringList; const ApiName: TP_String);
begin
  Lines.Add('  call test_' + ApiName + '(g_pass, g_fail)');
end;

procedure EmitFunctionTestSub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  PlaceholderArgs, ArgNames: TP_String;
  j: integer;
begin
  PlaceholderArgs := BuildPlaceholderArgs(F.Params);
  ArgNames := '';
  for j := 0 to High(F.Params) do
  begin
    if ArgNames <> '' then ArgNames := ArgNames + ', ';
    ArgNames := ArgNames + 'p' + umlIntToStr(j).Text;
  end;

  Lines.Add('  subroutine test_' + ApiName + '(pass, fail)');
  Lines.Add('    integer(c_int), intent(inout) :: pass, fail');
  Lines.Add('    integer(c_int32_t) :: rc');
  EmitArgsAndReturnVars(Lines, F);
  if length(F.Params) > 0 then
    Lines.Add('');
  EmitAssignPlaceholders(Lines, F);
  Lines.Add('');
  Lines.Add('    rc = -1_c_int32_t');
  if PlaceholderArgs = '' then
    Lines.Add('    call ' + ApiName + '(DEFAULT_TARGET_APP, ret, rc)')
  else
    Lines.Add('    call ' + ApiName + '(DEFAULT_TARGET_APP, ' + ArgNames + ', ret, rc)');
  Lines.Add('    if (rc == 0_c_int32_t) then');
  Lines.Add('      pass = pass + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[PASS] ' + ApiName.Text + '(app)') + ', ' + FortranStrLit(''));
  Lines.Add('    else');
  Lines.Add('      fail = fail + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A,A,I0)') + ') ' +
    FortranStrLit('[FAIL] ' + ApiName.Text + '(app) -- rc=') + ', ' + FortranStrLit('') + ', rc');
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('    if (g_has_service_uid) then');
  Lines.Add('      rc = -1_c_int32_t');
  if PlaceholderArgs = '' then
    Lines.Add('      call ' + ApiName + '_UID_Call(g_service_uid, ret, rc)')
  else
    Lines.Add('      call ' + ApiName + '_UID_Call(g_service_uid, ' + ArgNames + ', ret, rc)');
  Lines.Add('      if (rc == 0_c_int32_t) then');
  Lines.Add('        pass = pass + 1_c_int');
  Lines.Add('        write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[PASS] ' + ApiName.Text + '(uid)') + ', ' + FortranStrLit(''));
  Lines.Add('      else');
  Lines.Add('        fail = fail + 1_c_int');
  Lines.Add('        write(*, ' + FortranStrLit('(A,A,A,I0)') + ') ' +
    FortranStrLit('[FAIL] ' + ApiName.Text + '(uid) -- rc=') + ', ' + FortranStrLit('') + ', rc');
  Lines.Add('      end if');
  Lines.Add('    else');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[SKIP] ' + ApiName.Text + '(uid)') + ', ' + FortranStrLit(' no service UID'));
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('    rc = -1_c_int32_t');
  if PlaceholderArgs = '' then
    Lines.Add('    call ' + ApiName + '_P2PName_Call(DEFAULT_TARGET_P2P_NAME, ret, rc)')
  else
    Lines.Add('    call ' + ApiName + '_P2PName_Call(DEFAULT_TARGET_P2P_NAME, ' + ArgNames + ', ret, rc)');
  Lines.Add('    if (rc == 0_c_int32_t) then');
  Lines.Add('      pass = pass + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[PASS] ' + ApiName.Text + '(p2pname)') + ', ' + FortranStrLit(''));
  Lines.Add('    else');
  Lines.Add('      fail = fail + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A,A,I0)') + ') ' +
    FortranStrLit('[FAIL] ' + ApiName.Text + '(p2pname) -- rc=') + ', ' + FortranStrLit('') + ', rc');
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('  end subroutine');
  Lines.Add('');
end;

procedure EmitProcedureTestSub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgNames: TP_String;
  j: integer;
begin
  ArgNames := '';
  for j := 0 to High(F.Params) do
  begin
    if ArgNames <> '' then ArgNames := ArgNames + ', ';
    ArgNames := ArgNames + 'p' + umlIntToStr(j).Text;
  end;

  Lines.Add('  subroutine test_' + ApiName + '(pass, fail)');
  Lines.Add('    integer(c_int), intent(inout) :: pass, fail');
  Lines.Add('    integer(c_int32_t) :: rc');
  EmitArgsAndReturnVars(Lines, F);
  if length(F.Params) > 0 then
    Lines.Add('');
  EmitAssignPlaceholders(Lines, F);
  Lines.Add('');
  Lines.Add('    rc = -1_c_int32_t');
  if ArgNames = '' then
    Lines.Add('    call ' + ApiName + '(DEFAULT_TARGET_APP, rc)')
  else
    Lines.Add('    call ' + ApiName + '(DEFAULT_TARGET_APP, ' + ArgNames + ', rc)');
  Lines.Add('    if (rc == 0_c_int32_t) then');
  Lines.Add('      pass = pass + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[PASS] ' + ApiName.Text + '(app)') + ', ' + FortranStrLit(''));
  Lines.Add('    else');
  Lines.Add('      fail = fail + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A,A,I0)') + ') ' +
    FortranStrLit('[FAIL] ' + ApiName.Text + '(app) -- rc=') + ', ' + FortranStrLit('') + ', rc');
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('    if (g_has_service_uid) then');
  Lines.Add('      rc = -1_c_int32_t');
  if ArgNames = '' then
    Lines.Add('      call ' + ApiName + '_UID_Notify(g_service_uid, rc)')
  else
    Lines.Add('      call ' + ApiName + '_UID_Notify(g_service_uid, ' + ArgNames + ', rc)');
  Lines.Add('      if (rc == 0_c_int32_t) then');
  Lines.Add('        pass = pass + 1_c_int');
  Lines.Add('        write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[PASS] ' + ApiName.Text + '(uid)') + ', ' + FortranStrLit(''));
  Lines.Add('      else');
  Lines.Add('        fail = fail + 1_c_int');
  Lines.Add('        write(*, ' + FortranStrLit('(A,A,A,I0)') + ') ' +
    FortranStrLit('[FAIL] ' + ApiName.Text + '(uid) -- rc=') + ', ' + FortranStrLit('') + ', rc');
  Lines.Add('      end if');
  Lines.Add('    else');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[SKIP] ' + ApiName.Text + '(uid)') + ', ' + FortranStrLit(' no service UID'));
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('    rc = -1_c_int32_t');
  if ArgNames = '' then
    Lines.Add('    call ' + ApiName + '_P2PName_Notify(DEFAULT_TARGET_P2P_NAME, rc)')
  else
    Lines.Add('    call ' + ApiName + '_P2PName_Notify(DEFAULT_TARGET_P2P_NAME, ' + ArgNames + ', rc)');
  Lines.Add('    if (rc == 0_c_int32_t) then');
  Lines.Add('      pass = pass + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A)') + ') ' +
    FortranStrLit('[PASS] ' + ApiName.Text + '(p2pname)') + ', ' + FortranStrLit(''));
  Lines.Add('    else');
  Lines.Add('      fail = fail + 1_c_int');
  Lines.Add('      write(*, ' + FortranStrLit('(A,A,A,I0)') + ') ' +
    FortranStrLit('[FAIL] ' + ApiName.Text + '(p2pname) -- rc=') + ', ' + FortranStrLit('') + ', rc');
  Lines.Add('    end if');
  Lines.Add('');
  Lines.Add('  end subroutine');
  Lines.Add('');
end;

function GenerateABIServiceTestFortranCode(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, AppName, P2PName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  Log(PFormat('Generating Fortran ABI service test program for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('program ' + NormalizedUnit.Text + '_abi_service_test');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  use ' + NormalizedUnit.Text + '_abi_service');
    Lines.Add('  implicit none');
    Lines.Add('');
    Lines.Add('  character(len=*), parameter :: SERVICE_ENDPOINT = ' + FortranStrLit('ipc:' + AppName.Text));
    Lines.Add('  character(len=*), parameter :: SERVICE_APP_NAME = ' + FortranStrLit(AppName.Text));
    Lines.Add('  character(len=*), parameter :: SERVICE_P2P_NAME = ' + FortranStrLit(P2PName.Text));
    Lines.Add('  character(len=*), parameter :: WHOAMI_API = ' + FortranStrLit('LF_TEST_WHOAMI'));
    Lines.Add('  character(len=*), parameter :: ASK_CALL_ME_API = ' + FortranStrLit('LF_TEST_ASK_SERVICE_CALL_ME'));
    Lines.Add('  character(len=*), parameter :: REPORT_IDENTITY_API = ' + FortranStrLit('LF_TEST_REPORT_SERVICE_IDENTITY'));
    Lines.Add('');
    Lines.Add('  interface');
    Lines.Add('    subroutine lf_sleep_ms(ms) bind(C, name=' + FortranStrLit('Sleep') + ')');
    Lines.Add('      import :: c_int32_t');
    Lines.Add('      integer(c_int32_t), value :: ms');
    Lines.Add('    end subroutine');
    Lines.Add('  end interface');
    Lines.Add('');
    Lines.Add('  character(len=512) :: g_sentinel_path = ' + FortranStrLit('LingoFuse_FortranServiceTest.exit'));
    Lines.Add('  integer(c_int64_t) :: g_timeout_ms = 30000_c_int64_t');
    Lines.Add('  logical :: g_quiet = .true.');
    Lines.Add('  logical :: g_help = .false.');
    Lines.Add('  logical :: g_running = .true.');
    Lines.Add('  integer(c_int64_t) :: g_uptime_ms = 0_c_int64_t');
    Lines.Add('  integer(c_int64_t) :: g_last_stats_ms = 0_c_int64_t');
    Lines.Add('  integer(c_int64_t) :: g_last_sentinel_ms = 0_c_int64_t');
    Lines.Add('  integer(c_int8_t) :: g_client_uid(LF_UID_BYTE_COUNT)');
    Lines.Add('  logical :: g_pending_callback = .false.');
    Lines.Add('  type(c_ptr) :: g_app = c_null_ptr');
    Lines.Add('  integer(c_int) :: lf_rc');
    Lines.Add('');
    Lines.Add('  call parse_args()');
    Lines.Add('  if (g_help) then');
    Lines.Add('    call print_help()');
    Lines.Add('    stop 0');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  if (lf_load_library() /= 1_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_load_library failed'));
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  call lf_set_opt_quiet(g_quiet)');
    Lines.Add('  call lf_set_opt_overlap_connection(.true.)');
    Lines.Add('  call lf_set_opt_p2p_name(SERVICE_P2P_NAME)');
    Lines.Add('');
    Lines.Add('  call lf_reset_prepare()');
    Lines.Add('  lf_rc = lf_prepare_service(SERVICE_ENDPOINT, SERVICE_ENDPOINT)');
    Lines.Add('  if (lf_rc < 0_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_prepare_service failed'));
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  g_app = lf_app_create(SERVICE_APP_NAME, ' + FortranStrLit('Fortran ABI service test') + ')');
    Lines.Add('  if (.not. c_associated(g_app)) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_app_create failed'));
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  lf_rc = register_all_abi_apis(g_app)');
    Lines.Add('  lf_rc = lf_app_register_call(g_app, WHOAMI_API, ' +
      FortranStrLit('service-side whoami helper') + ', c_funloc(cb_whoami))');
    Lines.Add('  lf_rc = lf_app_register_notify(g_app, ASK_CALL_ME_API, ' +
      FortranStrLit('ask service to call back client') + ', c_funloc(cb_ask_call_me))');
    Lines.Add('');
    Lines.Add('  lf_rc = register_all_p2p_abi_apis()');
    Lines.Add('  lf_rc = lf_register_p2p_call(WHOAMI_API, ' +
      FortranStrLit('service-side whoami helper') + ', c_funloc(cb_whoami))');
    Lines.Add('  lf_rc = lf_register_p2p_notify(ASK_CALL_ME_API, ' +
      FortranStrLit('ask service to call back client') + ', c_funloc(cb_ask_call_me))');
    Lines.Add('');
    Lines.Add('  lf_rc = lf_prepare_client(SERVICE_ENDPOINT, g_app)');
    Lines.Add('  if (lf_rc < 0_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_prepare_client failed'));
    Lines.Add('    call cleanup()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  lf_rc = lf_prepare_done()');
    Lines.Add('  if (lf_rc /= 1_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_prepare_done failed'));
    Lines.Add('    call cleanup()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  write(*, ' + FortranStrLit('(A,A)') + ') ' +
      FortranStrLit('[READY] ') + ', trim(SERVICE_ENDPOINT)');
    Lines.Add('');
    Lines.Add('  do while (g_running)');
    Lines.Add('    call lf_sleep_ms(20_c_int32_t)');
    Lines.Add('    g_uptime_ms = g_uptime_ms + 20_c_int64_t');
    Lines.Add('');
    Lines.Add('    if (g_uptime_ms - g_last_stats_ms >= 5000_c_int64_t) then');
    Lines.Add('      if (.not. g_quiet) then');
    Lines.Add('        write(*, ' + FortranStrLit('(A,I0)') + ') ' +
      FortranStrLit('[STATS] uptime_ms=') + ', g_uptime_ms');
    Lines.Add('      end if');
    Lines.Add('      g_last_stats_ms = g_uptime_ms');
    Lines.Add('    end if');
    Lines.Add('');
    Lines.Add('    if (g_uptime_ms - g_last_sentinel_ms >= 500_c_int64_t) then');
    Lines.Add('      if (file_exists(g_sentinel_path)) then');
    Lines.Add('        g_running = .false.');
    Lines.Add('      end if');
    Lines.Add('      g_last_sentinel_ms = g_uptime_ms');
    Lines.Add('    end if');
    Lines.Add('');
    Lines.Add('    if (g_pending_callback) then');
    Lines.Add('      g_pending_callback = .false.');
    Lines.Add('      call do_reverse_call()');
    Lines.Add('    end if');
    Lines.Add('');
    Lines.Add('    if (g_uptime_ms >= g_timeout_ms) then');
    Lines.Add('      g_running = .false.');
    Lines.Add('    end if');
    Lines.Add('  end do');
    Lines.Add('');
    Lines.Add('  call cleanup()');
    Lines.Add('  write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[SHUTDOWN]'));
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');
    Lines.Add('  subroutine parse_args()');
    Lines.Add('    integer :: na, i, arglen, ios, secs');
    Lines.Add('    character(len=512) :: arg');
    Lines.Add('    na = command_argument_count()');
    Lines.Add('    do i = 1, na');
    Lines.Add('      call get_command_argument(i, arg, arglen)');
    Lines.Add('      if (arglen <= 0) cycle');
    Lines.Add('      if (arg(1:arglen) == ' + FortranStrLit('--help') + ') then');
    Lines.Add('        g_help = .true.');
    Lines.Add('      else if (arg(1:arglen) == ' + FortranStrLit('--quiet') + ') then');
    Lines.Add('        g_quiet = .true.');
    Lines.Add('      else if (arglen >= 10 .and. arg(1:10) == ' + FortranStrLit('--seconds=') + ') then');
    Lines.Add('        read(arg(11:arglen), *, iostat=ios) secs');
    Lines.Add('        if (ios == 0 .and. secs > 0) g_timeout_ms = int(secs, c_int64_t) * 1000_c_int64_t');
    Lines.Add('      else if (arglen >= 11 .and. arg(1:11) == ' + FortranStrLit('--sentinel=') + ') then');
    Lines.Add('        g_sentinel_path = ' + FortranStrLit('') + '');
    Lines.Add('        g_sentinel_path = trim(arg(12:arglen))');
    Lines.Add('      end if');
    Lines.Add('    end do');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine print_help()');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('Usage: ' + NormalizedUnit.Text + '_abi_service_test.exe [options]'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --seconds=N       Service runtime in seconds (default: 30)'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --sentinel=PATH   Sentinel file path (default: LingoFuse_FortranServiceTest.exit)'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --quiet           Suppress periodic status output'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --help            Show this help and exit'));
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  logical function file_exists(path)');
    Lines.Add('    character(len=*), intent(in) :: path');
    Lines.Add('    inquire(file=trim(path), exist=file_exists)');
    Lines.Add('  end function');
    Lines.Add('');
    Lines.Add('  subroutine cleanup()');
    Lines.Add('    call lf_exit_main_thread()');
    Lines.Add('    if (c_associated(g_app)) then');
    Lines.Add('      call lf_app_destroy(g_app)');
    Lines.Add('      g_app = c_null_ptr');
    Lines.Add('    end if');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    call lf_free_library()');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine do_reverse_call()');
    Lines.Add('    type(c_ptr) :: req, resp');
    Lines.Add('    integer(c_int) :: local_rc');
    Lines.Add('    local_rc = -1_c_int');
    Lines.Add('    req = lf_data_create(REPORT_IDENTITY_API)');
    Lines.Add('    if (.not. c_associated(req)) then');
    Lines.Add('      write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[SERVICE] ask_call_me: lf_data_create failed'));
    Lines.Add('      return');
    Lines.Add('    end if');
    Lines.Add('    local_rc = lf_data_write_string(req, ' + FortranStrLit('service initiates call') + ')');
    Lines.Add('    resp = lf_call_uid(g_client_uid, req, 5000_c_int64_t)');
    Lines.Add('    call lf_data_destroy(req)');
    Lines.Add('    if (c_associated(resp)) then');
    Lines.Add('      write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[SERVICE] ask_call_me: client responded ok'));
    Lines.Add('      call lf_data_destroy(resp)');
    Lines.Add('    else');
    Lines.Add('      write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[SERVICE] ask_call_me: UID call returned nil (timeout)'));
    Lines.Add('    end if');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine cb_whoami(input, output) bind(C)');
    Lines.Add('    type(c_ptr), value :: input, output');
    Lines.Add('    integer(c_int8_t) :: uid(LF_UID_BYTE_COUNT)');
    Lines.Add('    character(len=:), allocatable :: p2p_name');
    Lines.Add('    integer(c_int) :: local_rc');
    Lines.Add('    local_rc = lf_data_get_p2p_uid(input, uid)');
    Lines.Add('    call lf_data_get_p2p_name(input, p2p_name)');
    Lines.Add('    local_rc = lf_data_write_uint8(output, int(z' +
      FortranStrLit('00') + ', c_int8_t))');
    Lines.Add('    local_rc = lf_data_write_uid(output, uid)');
    Lines.Add('    local_rc = lf_data_write_string(output, p2p_name)');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine cb_ask_call_me(input) bind(C)');
    Lines.Add('    type(c_ptr), value :: input');
    Lines.Add('    integer(c_int) :: local_rc');
    Lines.Add('    local_rc = lf_data_get_p2p_uid(input, g_client_uid)');
    Lines.Add('    if (local_rc == 1_c_int) then');
    Lines.Add('      g_pending_callback = .true.');
    Lines.Add('    end if');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('end program ' + NormalizedUnit.Text + '_abi_service_test');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Fortran ABI service test', [Lines.Count]));
  finally
  end;
end;

function GenerateABICallTestFortranCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, P2PName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  P2PName := NormalizedUnit + '_service_test_p2p';

  Log(PFormat('Generating Fortran ABI call test program for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := BuildUniqueApiNames(SupportedFuncs);

  Lines := TPascalStringList.Create;
  try
    Lines.Add('program ' + NormalizedUnit.Text + '_abi_call_test');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  use ' + NormalizedUnit.Text + '_abi_call');
    Lines.Add('  implicit none');
    Lines.Add('');
    Lines.Add('  character(len=*), parameter :: DEFAULT_ENDPOINT = ' + FortranStrLit('ipc:' + AppName.Text));
    Lines.Add('  character(len=*), parameter :: DEFAULT_TARGET_APP = ' + FortranStrLit(AppName.Text));
    Lines.Add('  character(len=*), parameter :: DEFAULT_TARGET_P2P_NAME = ' + FortranStrLit(P2PName.Text));
    Lines.Add('  character(len=*), parameter :: CLIENT_APP_NAME = ' + FortranStrLit('LF_TEST_CLIENT_SELF'));
    Lines.Add('  character(len=*), parameter :: REPORT_IDENTITY_API = ' + FortranStrLit('LF_TEST_REPORT_SERVICE_IDENTITY'));
    Lines.Add('  character(len=*), parameter :: WHOAMI_API = ' + FortranStrLit('LF_TEST_WHOAMI'));
    Lines.Add('  character(len=*), parameter :: ASK_CALL_ME_API = ' + FortranStrLit('LF_TEST_ASK_SERVICE_CALL_ME'));
    Lines.Add('');
    Lines.Add('  interface');
    Lines.Add('    subroutine lf_sleep_ms(ms) bind(C, name=' + FortranStrLit('Sleep') + ')');
    Lines.Add('      import :: c_int32_t');
    Lines.Add('      integer(c_int32_t), value :: ms');
    Lines.Add('    end subroutine');
    Lines.Add('  end interface');
    Lines.Add('');
    Lines.Add('  logical :: g_quiet = .true.');
    Lines.Add('  logical :: g_help = .false.');
    Lines.Add('  integer(c_int64_t) :: g_timeout_ms = 30000_c_int64_t');
    Lines.Add('  integer(c_int) :: g_pass = 0');
    Lines.Add('  integer(c_int) :: g_fail = 0');
    Lines.Add('  integer(c_int) :: g_skip = 0');
    Lines.Add('  integer(c_int8_t) :: g_service_uid(LF_UID_BYTE_COUNT)');
    Lines.Add('  logical :: g_has_service_uid = .false.');
    Lines.Add('  logical :: g_service_called_me = .false.');
    Lines.Add('  logical :: g_service_identity_seen = .false.');
    Lines.Add('  character(len=:), allocatable :: g_service_p2p_name');
    Lines.Add('  type(c_ptr) :: g_client_app = c_null_ptr');
    Lines.Add('  integer(c_int) :: lf_rc');
    Lines.Add('  integer(c_int64_t) :: wait_ms');
    Lines.Add('');
    Lines.Add('  call parse_args()');
    Lines.Add('  if (g_help) then');
    Lines.Add('    call print_help()');
    Lines.Add('    stop 0');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  if (lf_load_library() /= 1_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_load_library failed'));
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  call lf_set_opt_quiet(g_quiet)');
    Lines.Add('  call lf_set_opt_overlap_connection(.true.)');
    Lines.Add('');
    Lines.Add('  call lf_reset_prepare()');
    Lines.Add('');
    Lines.Add('  g_client_app = lf_app_create(CLIENT_APP_NAME, ' + FortranStrLit('client test app') + ')');
    Lines.Add('  if (.not. c_associated(g_client_app)) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_app_create failed'));
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  lf_rc = lf_app_register_call(g_client_app, REPORT_IDENTITY_API, ' +
      FortranStrLit('report service identity') + ', c_funloc(cb_report_identity))');
    Lines.Add('');
    Lines.Add('  lf_rc = lf_prepare_client(DEFAULT_ENDPOINT, g_client_app)');
    Lines.Add('  if (lf_rc < 0_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_prepare_client failed'));
    Lines.Add('    call cleanup()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  lf_rc = lf_prepare_done()');
    Lines.Add('  if (lf_rc /= 1_c_int) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[FATAL] lf_prepare_done failed'));
    Lines.Add('    call cleanup()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[READY] Client online'));
    Lines.Add('');
    Lines.Add('  block');
    Lines.Add('    logical :: app_ready');
    Lines.Add('    integer :: tries');
    Lines.Add('    app_ready = .false.');
    Lines.Add('    do tries = 1, 50');
    Lines.Add('      if (lf_check_app(DEFAULT_TARGET_APP)) then');
    Lines.Add('        app_ready = .true.');
    Lines.Add('        exit');
    Lines.Add('      end if');
    Lines.Add('      call lf_sleep_ms(200_c_int32_t)');
    Lines.Add('    end do');
    Lines.Add('    if (.not. app_ready) then');
    Lines.Add('      write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[WARN] Target service not detected, proceeding anyway'));
    Lines.Add('    end if');
    Lines.Add('  end block');
    Lines.Add('');
    Lines.Add('  call probe_service_identity()');
    Lines.Add('  if (g_has_service_uid) then');
    Lines.Add('    write(*, ' + FortranStrLit('(A,A)') + ') ' +
      FortranStrLit('[OK] service UID = ') + ', uid_to_hex(g_service_uid)');
    Lines.Add('    write(*, ' + FortranStrLit('(A,A)') + ') ' +
      FortranStrLit('[OK] service P2P = ') + ', trim(g_service_p2p_name)');
    Lines.Add('  else');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[WARN] whoami failed, UID tests will be skipped'));
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  call trigger_service_reverse_call()');
    Lines.Add('');
    Lines.Add('  if (g_service_called_me .and. g_has_service_uid) then');
    Lines.Add('    g_pass = g_pass + 1_c_int');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[PASS] service-initiated call'));
    Lines.Add('  else');
    Lines.Add('    g_fail = g_fail + 1_c_int');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('[FAIL] service-initiated call -- timeout or no UID'));
    Lines.Add('  end if');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      if SupportedFuncs[i].IsFunction then
        EmitFunctionTestCall(Lines, ApiNames[i])
      else
        EmitProcedureTestCall(Lines, ApiNames[i]);
    end;

    Lines.Add('');
    Lines.Add('  write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit(''));
    Lines.Add('  write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('=== Summary ==='));
    Lines.Add('  write(*, ' + FortranStrLit('(A,I0)') + ') ' + FortranStrLit('Pass: ') + ', g_pass');
    Lines.Add('  write(*, ' + FortranStrLit('(A,I0)') + ') ' + FortranStrLit('Fail: ') + ', g_fail');
    Lines.Add('  write(*, ' + FortranStrLit('(A,I0)') + ') ' + FortranStrLit('Skip: ') + ', g_skip');
    Lines.Add('');
    Lines.Add('  call cleanup()');
    Lines.Add('  write(*, ' + FortranStrLit('(A)') + ') ' + FortranStrLit('[SHUTDOWN] Client test complete'));
    Lines.Add('');
    Lines.Add('  if (g_fail == 0_c_int) then');
    Lines.Add('    stop 0');
    Lines.Add('  else');
    Lines.Add('    stop 2');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');
    Lines.Add('  subroutine parse_args()');
    Lines.Add('    integer :: na, i, arglen, ios, secs');
    Lines.Add('    character(len=512) :: arg');
    Lines.Add('    na = command_argument_count()');
    Lines.Add('    do i = 1, na');
    Lines.Add('      call get_command_argument(i, arg, arglen)');
    Lines.Add('      if (arglen <= 0) cycle');
    Lines.Add('      if (arg(1:arglen) == ' + FortranStrLit('--help') + ') then');
    Lines.Add('        g_help = .true.');
    Lines.Add('      else if (arg(1:arglen) == ' + FortranStrLit('--quiet') + ') then');
    Lines.Add('        g_quiet = .true.');
    Lines.Add('      else if (arglen >= 10 .and. arg(1:10) == ' + FortranStrLit('--seconds=') + ') then');
    Lines.Add('        read(arg(11:arglen), *, iostat=ios) secs');
    Lines.Add('        if (ios == 0 .and. secs > 0) g_timeout_ms = int(secs, c_int64_t) * 1000_c_int64_t');
    Lines.Add('      end if');
    Lines.Add('    end do');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine print_help()');
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('Usage: ' + NormalizedUnit.Text + '_abi_call_test.exe [options]'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --seconds=N   Overall test timeout in seconds (default: 30)'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --quiet       Suppress informational messages'));
    Lines.Add('    write(*, ' + FortranStrLit('(A)') + ') ' +
      FortranStrLit('  --help        Show this help and exit'));
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine cleanup()');
    Lines.Add('    call lf_exit_main_thread()');
    Lines.Add('    if (c_associated(g_client_app)) then');
    Lines.Add('      call lf_app_destroy(g_client_app)');
    Lines.Add('      g_client_app = c_null_ptr');
    Lines.Add('    end if');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    call lf_free_library()');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  function uid_to_hex(uid) result(s)');
    Lines.Add('    integer(c_int8_t), intent(in) :: uid(LF_UID_BYTE_COUNT)');
    Lines.Add('    character(len=64) :: s');
    Lines.Add('    character(len=16) :: hexch');
    Lines.Add('    integer :: j, v');
    Lines.Add('    hexch = ' + FortranStrLit('0123456789ABCDEF'));
    Lines.Add('    do j = 1, LF_UID_BYTE_COUNT');
    Lines.Add('      v = iand(int(uid(j)), 255)');
    Lines.Add('      s(j*2-1:j*2-1) = hexch(v/16+1:v/16+1)');
    Lines.Add('      s(j*2:j*2) = hexch(mod(v, 16)+1:mod(v, 16)+1)');
    Lines.Add('    end do');
    Lines.Add('  end function');
    Lines.Add('');
    Lines.Add('  subroutine probe_service_identity()');
    Lines.Add('    type(c_ptr) :: req, resp');
    Lines.Add('    integer(c_int) :: local_rc');
    Lines.Add('    integer(c_int64_t) :: str_status');
    Lines.Add('    integer(c_int8_t) :: status_byte');
    Lines.Add('    local_rc = -1_c_int');
    Lines.Add('    req = lf_data_create(WHOAMI_API)');
    Lines.Add('    if (.not. c_associated(req)) return');
    Lines.Add('    local_rc = lf_data_write_string(req, ' + FortranStrLit('') + ')');
    Lines.Add('    resp = lf_call(DEFAULT_TARGET_APP, req, 5000_c_int64_t)');
    Lines.Add('    call lf_data_destroy(req)');
    Lines.Add('    if (.not. c_associated(resp)) return');
    Lines.Add('    call lf_data_set_position(resp, 0_c_int64_t)');
    Lines.Add('    local_rc = lf_data_read_uint8(resp, status_byte)');
    Lines.Add('    if (local_rc == 1_c_int .and. status_byte == int(z' +
      FortranStrLit('00') + ', c_int8_t)) then');
    Lines.Add('      local_rc = lf_data_read_uid(resp, g_service_uid)');
    Lines.Add('      if (local_rc == 1_c_int) then');
    Lines.Add('        call lf_data_read_string(resp, g_service_p2p_name, str_status)');
    Lines.Add('        g_has_service_uid = .true.');
    Lines.Add('      end if');
    Lines.Add('    end if');
    Lines.Add('    call lf_data_destroy(resp)');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine trigger_service_reverse_call()');
    Lines.Add('    type(c_ptr) :: req');
    Lines.Add('    integer(c_int) :: local_rc');
    Lines.Add('    local_rc = -1_c_int');
    Lines.Add('    g_service_called_me = .false.');
    Lines.Add('    req = lf_data_create(ASK_CALL_ME_API)');
    Lines.Add('    if (.not. c_associated(req)) return');
    Lines.Add('    local_rc = lf_data_write_string(req, REPORT_IDENTITY_API)');
    Lines.Add('    call lf_notify(DEFAULT_TARGET_APP, req)');
    Lines.Add('    call lf_data_destroy(req)');
    Lines.Add('    wait_ms = 0_c_int64_t');
    Lines.Add('    do while (.not. g_service_called_me .and. wait_ms < 10000_c_int64_t)');
    Lines.Add('      call lf_sleep_ms(50_c_int32_t)');
    Lines.Add('      wait_ms = wait_ms + 50_c_int64_t');
    Lines.Add('    end do');
    Lines.Add('  end subroutine');
    Lines.Add('');
    Lines.Add('  subroutine cb_report_identity(input, output) bind(C)');
    Lines.Add('    type(c_ptr), value :: input, output');
    Lines.Add('    integer(c_int8_t) :: uid(LF_UID_BYTE_COUNT)');
    Lines.Add('    character(len=:), allocatable :: msg');
    Lines.Add('    integer(c_int) :: local_rc');
    Lines.Add('    integer(c_int64_t) :: str_status');
    Lines.Add('    local_rc = lf_data_get_p2p_uid(input, uid)');
    Lines.Add('    if (local_rc == 1_c_int) then');
    Lines.Add('      g_service_uid = uid');
    Lines.Add('      call lf_data_get_p2p_name(input, g_service_p2p_name)');
    Lines.Add('      g_has_service_uid = .true.');
    Lines.Add('    end if');
    Lines.Add('    call lf_data_read_string(input, msg, str_status)');
    Lines.Add('    g_service_called_me = .true.');
    Lines.Add('    local_rc = lf_data_write_uint8(output, int(z' +
      FortranStrLit('00') + ', c_int8_t))');
    Lines.Add('    local_rc = lf_data_write_string(output, ' +
      FortranStrLit('identity received') + ')');
    Lines.Add('  end subroutine');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      if SupportedFuncs[i].IsFunction then
        EmitFunctionTestSub(Lines, ApiNames[i], SupportedFuncs[i])
      else
        EmitProcedureTestSub(Lines, ApiNames[i], SupportedFuncs[i]);
    end;

    Lines.Add('end program ' + NormalizedUnit.Text + '_abi_call_test');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Fortran ABI call test', [Lines.Count]));
  finally
    ApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'fortran',
    'xxx_abi_service_test.f90',
    gkTest,
    'Fortran ABI service test program',
    @GenerateABIServiceTestFortranCode);

  RegisterGenerator(
    'fortran',
    'xxx_abi_call_test.f90',
    gkTest,
    'Fortran ABI call test program',
    @GenerateABICallTestFortranCode);

end.
