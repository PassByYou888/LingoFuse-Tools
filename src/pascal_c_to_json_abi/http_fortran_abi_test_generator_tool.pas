unit http_fortran_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine, Z.UReplace,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceFortranTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallFortranTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
  begin
    DoStatus('[http_fortran_abi_test_generator] %s', [Msg.Text]);
  end;
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
  begin
    DoStatus('[http_fortran_abi_test_generator] %s', [PFormat(Fmt, Args)]);
  end;
end;

// ---------------------------------------------------------------------------
// ABI type classification
// ---------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal') or
    T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

// ABI_Type_To_Fortran_Default - default test-argument literal.
function ABI_Type_To_Fortran_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := #39#39;    // '' empty string
  end
  else if ABI_Type_Is_Float(T) then
  begin
    Result := '0.0d0';
  end
  else if ABI_Type_Is_Int(T) then
  begin
    Result := '0_c_int64_t';
  end
  else
  begin
    Result := '0';
  end;
end;

// ABI_Type_To_Json_Literal - default JSON literal for the type.
function ABI_Type_To_Json_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := '""';
  end
  else
  begin
    Result := '0';
  end;
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
  else if ABI_Type_Is_String(T) then Result := 'string'
  else Result := '';
end;

// ABI_Type_To_Fortran_Module_Result_Decl - module-scope declaration for
// a typed result variable.
//
// IMPORTANT: must be a FIXED-length character, not "character(len=:),
// allocatable". Fortran 2008 does not allow a deferred-length
// allocatable variable to carry the SAVE attribute. This variable is
// assigned from <api>_read_async_result, which returns an allocatable;
// Fortran truncates or pads on assignment to a fixed-length target,
// which is exactly what we want here.
function ABI_Type_To_Fortran_Module_Result_Decl(const T: TP_String; const Ident: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := 'character(len=1024), save, public :: ' + Ident + ' = ' + #39#39;
  end
  else if ABI_Type_Is_Float(T) then
  begin
    Result := 'real(c_double), save, public :: ' + Ident + ' = 0.0d0';
  end
  else
  begin
    Result := 'integer(c_int64_t), save, public :: ' + Ident + ' = 0_c_int64_t';
  end;
end;

// ---------------------------------------------------------------------------
// Identifier helpers
// ---------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
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
    begin
      Result.Append(c);
    end
    else
    begin
      Result.Append('_');
    end;
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
  begin
    Result := '_' + Result;
  end;

  Result := Result.LowerText;
end;

function UniqueName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while Used.IndexOf(Base + '_' + umlIntToStr(i).Text) >= 0 do
  begin
    Inc(i);
  end;
  Result := Base + '_' + umlIntToStr(i).Text;
end;

function FStrLit(const S: TP_String): TP_String;
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
      Result.Append(#39);
      Result.Append(#39);
    end
    else
    begin
      Result.Append(c);
    end;
  end;
  Result.Append(#39);
end;

// ---------------------------------------------------------------------------
// Comment extraction
// ---------------------------------------------------------------------------

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);

  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
  begin
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;

  if T.Len > 0 then
  begin
    if T[1] = '{' then
    begin
      T := T.GetString(2, T.Len + 1).TrimChar(#32#9);
    end
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
    begin
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
    end;
  end;

  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then
    begin
      T := T.GetString(1, T.Len).TrimChar(#32#9);
    end
    else if (T.Len >= 2) and (T[T.Len - 1] = '*') and (T[T.Len] = ')') then
    begin
      T := T.GetString(1, T.Len - 1).TrimChar(#32#9);
    end;
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
    begin
      Inc(j);
    end;
    if j > i then
    begin
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);
      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
          // Doxygen tag; skip.
        end
        else
        begin
          if Line[1] = '*' then
          begin
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          end;
          if (Line.Len > 0) and (Line[1] = '*') then
          begin
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          end;
          if Line.Len > 0 then
          begin
            Result := Line;
            if Result.Len > 200 then
            begin
              Result := Result.GetString(1, 201);
            end;
            Exit;
          end;
        end;
      end;
    end;
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
    begin
      Inc(i);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Parameter list builders
// ---------------------------------------------------------------------------

function BuildFortranCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeFortranIdent(Params[i].Name, i);
    if i > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + n;
  end;
end;

function BuildDefaultTestArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ABI_Type_To_Fortran_Default(Params[i].PascalType);
  end;
end;

function BuildDefaultJsonArgsArray(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  if Length(Params) = 0 then
  begin
    Result := '{"args":[]}';
    Exit;
  end;
  Result := '{"args":[';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + ABI_Type_To_Json_Literal(Params[i].PascalType);
  end;
  Result := Result + ']}';
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeFortranIdent(F.Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    if i > 0 then
    begin
      ParamDecl := ParamDecl + '; ';
    end;
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
  begin
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';';
  end
  else
  begin
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
  end;
end;

// ---------------------------------------------------------------------------
// Supported-function filtering
// ---------------------------------------------------------------------------

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
    begin
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;
    end;

    if Supported and f.IsFunction and (not ABI_Type_Is_Supported(f.ReturnType)) then
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

// ---------------------------------------------------------------------------
// Emit: sleep_ms helper
// ---------------------------------------------------------------------------

procedure EmitSleepHelper(Lines: TPascalStringList);
begin
  Lines.Add('  ! sleep_ms - cross-platform millisecond sleep via system_clock.');
  Lines.Add('  subroutine sleep_ms(ms)');
  Lines.Add('    integer, intent(in) :: ms');
  Lines.Add('    integer(c_int64_t) :: t0, t1, rate, elapsed_ms');
  Lines.Add('');
  Lines.Add('    call system_clock(t0, rate)');
  Lines.Add('    if (rate <= 0_c_int64_t) then');
  Lines.Add('      rate = 1000_c_int64_t');
  Lines.Add('    end if');
  Lines.Add('    do');
  Lines.Add('      call system_clock(t1)');
  Lines.Add('      elapsed_ms = (t1 - t0) * 1000_c_int64_t / rate');
  Lines.Add('      if (elapsed_ms >= int(ms, c_int64_t)) then');
  Lines.Add('        exit');
  Lines.Add('      end if');
  Lines.Add('    end do');
  Lines.Add('  end subroutine sleep_ms');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Emit: read_response_code helper (self-contained)
// ---------------------------------------------------------------------------

procedure EmitReadResponseCode(Lines: TPascalStringList);
begin
  Lines.Add('  ! read_response_code - extract the top-level code from a JSON response.');
  Lines.Add('  ! Returns -1 when the code field is missing or unparseable.');
  Lines.Add('  function read_response_code(s) result(code)');
  Lines.Add('    character(len=*), intent(in) :: s');
  Lines.Add('    integer :: code');
  Lines.Add('    integer :: p, q, slen, ios');
  Lines.Add('    character(len=32) :: tmp');
  Lines.Add('');
  Lines.Add('    code = -1');
  Lines.Add('    slen = len(s)');
  Lines.Add('    p = index(s, ' + FStrLit('"code":') + ')');
  Lines.Add('    if (p <= 0) then');
  Lines.Add('      return');
  Lines.Add('    end if');
  Lines.Add('    p = p + 7');
  Lines.Add('    do while (p <= slen)');
  Lines.Add('      if (s(p:p) == ' + FStrLit(' ') + ') then');
  Lines.Add('        p = p + 1');
  Lines.Add('      else');
  Lines.Add('        exit');
  Lines.Add('      end if');
  Lines.Add('    end do');
  Lines.Add('    q = p');
  Lines.Add('    if (q <= slen) then');
  Lines.Add('      if (s(q:q) == ' + FStrLit('-') + ') then');
  Lines.Add('        q = q + 1');
  Lines.Add('      end if');
  Lines.Add('    end if');
  Lines.Add('    do while (q <= slen)');
  Lines.Add('      if (s(q:q) >= ' + FStrLit('0') + ') then');
  Lines.Add('        if (s(q:q) <= ' + FStrLit('9') + ') then');
  Lines.Add('          q = q + 1');
  Lines.Add('        else');
  Lines.Add('          exit');
  Lines.Add('        end if');
  Lines.Add('      else');
  Lines.Add('        exit');
  Lines.Add('      end if');
  Lines.Add('    end do');
  Lines.Add('    if (q > p) then');
  Lines.Add('      tmp = s(p:q-1)');
  Lines.Add('      read(tmp, *, iostat=ios) code');
  Lines.Add('      if (ios /= 0) then');
  Lines.Add('        code = -1');
  Lines.Add('      end if');
  Lines.Add('    end if');
  Lines.Add('  end function read_response_code');
  Lines.Add('');
end;

// ===========================================================================
// SERVICE-SIDE TEST PROGRAM
// ===========================================================================

function GenerateHTTPServiceFortranTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName, Endpoint, FileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, SafeName, AsyncFlag, CbName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  ArgsJson: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceFortranTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceFortranTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
  begin
    NormalizedUnit := '_' + NormalizedUnit;
  end;
  ModuleName := NormalizedUnit.LowerText + '_http_json_service_mod';
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  FileName := NormalizedUnit + '_http_json_service_main_test___.f90';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // -------------------------------------------------------------------------
    // Header
    // -------------------------------------------------------------------------
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('! ' + FileName.Text);
    Lines.Add('!');
    Lines.Add('! Auto-generated by http_fortran_abi_test_generator_tool.pas.');
    Lines.Add('! Source model unit: ' + UnitName.Text + '.');
    Lines.Add('! Do not edit by hand unless you know what you are doing.');
    Lines.Add('!');
    Lines.Add('! Service-side test program.');
    Lines.Add('!');
    Lines.Add('! Modes:');
    Lines.Add('!   (default)  Start the service and block until Enter.');
    Lines.Add('!   --smoke    Prepare LingoFuse, wait ~2s, then for each exposed API');
    Lines.Add('!              issue one sync self-call (code=0 check) and one async');
    Lines.Add('!              self-call (callback fire check). No bridge.py needed:');
    Lines.Add('!              self-calls use the local short-circuit.');
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Async state module (module-level bind(C) callbacks)
    // -------------------------------------------------------------------------
    Lines.Add('module ' + NormalizedUnit.LowerText + '_service_test_async_state');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  implicit none');
    Lines.Add('  private');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      SafeName := MakeSafeFortranIdent(ApiNames[i], i);
      AsyncFlag := 'done_' + SafeName;
      Lines.Add('  logical, save, public :: ' + AsyncFlag + ' = .false.');
    end;
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      SafeName := MakeSafeFortranIdent(ApiNames[i], i);
      CbName := 'cb_' + SafeName;
      Lines.Add('  public :: ' + CbName);
    end;
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      SafeName := MakeSafeFortranIdent(ApiNames[i], i);
      AsyncFlag := 'done_' + SafeName;
      CbName := 'cb_' + SafeName;
      Lines.Add('  subroutine ' + CbName + '(ud, handle) bind(C)');
      Lines.Add('    type(c_ptr), value :: ud');
      Lines.Add('    type(c_ptr), value :: handle');
      Lines.Add('    ! Service side does not import the call module; only assert fire.');
      Lines.Add('    ' + AsyncFlag + ' = .true.');
      Lines.Add('  end subroutine ' + CbName);
      Lines.Add('');
    end;

    Lines.Add('end module ' + NormalizedUnit.LowerText + '_service_test_async_state');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Main program
    // -------------------------------------------------------------------------
    Lines.Add('program ' + NormalizedUnit.Text + '_http_json_service_main_test___');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  use ' + ModuleName.Text);
    Lines.Add('  use ' + NormalizedUnit.LowerText + '_service_test_async_state');
    Lines.Add('  implicit none');
    Lines.Add('');
    Lines.Add('  logical :: smoke_mode');
    Lines.Add('  character(len=64) :: arg1');
    Lines.Add('  type(c_ptr) :: app');
    Lines.Add('  integer(c_int) :: rc, reg_rc');
    Lines.Add('  integer :: pass_count, fail_count, i');
    Lines.Add('');
    Lines.Add('  ! ---- Parse command line ----');
    Lines.Add('  smoke_mode = .false.');
    Lines.Add('  if (command_argument_count() >= 1) then');
    Lines.Add('    call get_command_argument(1, arg1)');
    Lines.Add('    if (trim(arg1) == ' + FStrLit('--smoke') + ') then');
    Lines.Add('      smoke_mode = .true.');
    Lines.Add('    end if');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('=== ' + AppName + ' Fortran HTTP/JSON service test ===') + '');
    Lines.Add('  write(*, ' + FStrLit('(A,A)') + ') ' + FStrLit('Endpoint : ') + ', ' +
      FStrLit(Endpoint) + '');
    Lines.Add('  write(*, ' + FStrLit('(A,A)') + ') ' + FStrLit('APIs     : ') + ', ' +
      FStrLit(umlIntToStr(Length(SupportedFuncs))) + '');
    Lines.Add('');
    Lines.Add('  ! ---- Prepare LingoFuse ----');
    Lines.Add('  call lf_reset_prepare()');
    Lines.Add('  call lf_set_opt_wait_ready_ok(.false.)');
    Lines.Add('  call lf_set_opt_overlap_connection(.true.)');
    Lines.Add('');
    Lines.Add('  rc = lf_prepare_service(' + FStrLit(Endpoint) + ', ' + FStrLit(Endpoint) + ')');
    Lines.Add('  if (rc < 0) then');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[FATAL] lf_prepare_service failed') + '');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  app = lf_app_create(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)');
    Lines.Add('  if (.not. c_associated(app)) then');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[FATAL] lf_app_create failed') + '');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  call register_all_http_json_apis(app, reg_rc)');
    Lines.Add('  if (reg_rc /= 0_c_int) then');
    Lines.Add('    write(*, ' + FStrLit('(A,I0,A)') + ') ' +
      FStrLit('[FATAL] ') + ', reg_rc, ' + FStrLit(' registration(s) failed') + '');
    Lines.Add('    call lf_app_destroy(app)');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  rc = lf_prepare_client(' + FStrLit(Endpoint) + ', app)');
    Lines.Add('  if (rc < 0) then');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[FATAL] lf_prepare_client failed') + '');
    Lines.Add('    call lf_app_destroy(app)');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  if (lf_prepare_done() /= 1_c_int) then');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[FATAL] lf_prepare_done failed') + '');
    Lines.Add('    call lf_app_destroy(app)');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  if (smoke_mode) then');
    Lines.Add('    call sleep_ms(2000)');
    Lines.Add('    pass_count = 0');
    Lines.Add('    fail_count = 0');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' + FStrLit('') + '');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[smoke] Running service self-calls.') + '');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[smoke] No bridge.py is required.') + '');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' + FStrLit('') + '');
    Lines.Add('');

    // Per-API sync + async blocks
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      SafeName := MakeSafeFortranIdent(ApiName, i);
      AsyncFlag := 'done_' + SafeName;
      CbName := 'cb_' + SafeName;
      ArgsJson := BuildDefaultJsonArgsArray(F.Params);

      // ---- sync block ----
      Lines.Add('    ! ---- ' + ApiName + ' [sync] ----');
      Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('  ' + ApiName + ' [sync] : ') + '');
      Lines.Add('    block');
      Lines.Add('      type(c_ptr) :: req, resp_h');
      Lines.Add('      character(len=:), allocatable :: resp_str');
      Lines.Add('      integer :: code_v');
      Lines.Add('      req = lf_data_create(' + FStrLit(ApiName) + ')');
      Lines.Add('      if (.not. c_associated(req)) then');
      Lines.Add('        write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (create)') + '');
      Lines.Add('        fail_count = fail_count + 1');
      Lines.Add('      else');
      Lines.Add('        if (lf_data_write_string(req, ' + FStrLit(ArgsJson) + ') /= 1_c_int) then');
      Lines.Add('          write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (write)') + '');
      Lines.Add('          fail_count = fail_count + 1');
      Lines.Add('          call lf_data_destroy(req)');
      Lines.Add('        else');
      Lines.Add('          resp_h = lf_call(HTTP_SERVICE_APP_NAME, req, 5000_c_int64_t)');
      Lines.Add('          call lf_data_destroy(req)');
      Lines.Add('          if (.not. c_associated(resp_h)) then');
      Lines.Add('            write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (nil)') + '');
      Lines.Add('            fail_count = fail_count + 1');
      Lines.Add('          else');
      Lines.Add('            if (lf_data_get_size(resp_h) <= 0_c_int64_t) then');
      Lines.Add('              write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (empty)') + '');
      Lines.Add('              fail_count = fail_count + 1');
      Lines.Add('              call lf_data_destroy(resp_h)');
      Lines.Add('            else');
      Lines.Add('              call lf_data_read_string(resp_h, resp_str)');
      Lines.Add('              call lf_data_destroy(resp_h)');
      Lines.Add('              code_v = read_response_code(resp_str)');
      Lines.Add('              if (code_v == 0) then');
      Lines.Add('                write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
      Lines.Add('                pass_count = pass_count + 1');
      Lines.Add('              else');
      Lines.Add('                write(*, ' + FStrLit('(A,I0,A)') + ') ' +
        FStrLit('FAILED (code=') + ', code_v, ' + FStrLit(')') + '');
      Lines.Add('                fail_count = fail_count + 1');
      Lines.Add('              end if');
      Lines.Add('            end if');
      Lines.Add('          end if');
      Lines.Add('        end if');
      Lines.Add('      end if');
      Lines.Add('    end block');
      Lines.Add('');

      // ---- async block ----
      Lines.Add('    ! ---- ' + ApiName + ' [async] ----');
      Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('  ' + ApiName + ' [async]: ') + '');
      Lines.Add('    block');
      Lines.Add('      type(c_ptr) :: req');
      Lines.Add('      integer(c_int) :: arc');
      Lines.Add('      ' + AsyncFlag + ' = .false.');
      Lines.Add('      req = lf_data_create(' + FStrLit(ApiName) + ')');
      Lines.Add('      if (.not. c_associated(req)) then');
      Lines.Add('        write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (create)') + '');
      Lines.Add('        fail_count = fail_count + 1');
      Lines.Add('      else');
      Lines.Add('        if (lf_data_write_string(req, ' + FStrLit(ArgsJson) + ') /= 1_c_int) then');
      Lines.Add('          write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (write)') + '');
      Lines.Add('          fail_count = fail_count + 1');
      Lines.Add('          call lf_data_destroy(req)');
      Lines.Add('        else');
      Lines.Add('          arc = lf_async_call(HTTP_SERVICE_APP_NAME, req, &');
      Lines.Add('                              c_funloc(' + CbName + '), c_null_ptr)');
      Lines.Add('          call lf_data_destroy(req)');
      Lines.Add('          if (arc /= 1_c_int) then');
      Lines.Add('            write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (submit)') + '');
      Lines.Add('            fail_count = fail_count + 1');
      Lines.Add('          else');
      Lines.Add('            do i = 1, 500');
      Lines.Add('              if (' + AsyncFlag + ') then');
      Lines.Add('                exit');
      Lines.Add('              end if');
      Lines.Add('              call sleep_ms(10)');
      Lines.Add('            end do');
      Lines.Add('            if (' + AsyncFlag + ') then');
      Lines.Add('              write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
      Lines.Add('              pass_count = pass_count + 1');
      Lines.Add('            else');
      Lines.Add('              write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('FAILED (timeout)') + '');
      Lines.Add('              fail_count = fail_count + 1');
      Lines.Add('            end if');
      Lines.Add('          end if');
      Lines.Add('        end if');
      Lines.Add('      end if');
      Lines.Add('    end block');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('  (no APIs to smoke-test)') + '');
      Lines.Add('');
    end;

    Lines.Add('    ! ---- Summary ----');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' + FStrLit('') + '');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('=== Smoke test summary ===') + '');
    Lines.Add('    write(*, ' + FStrLit('(A,I0)') + ') ' + FStrLit('Passed: ') + ', pass_count');
    Lines.Add('    write(*, ' + FStrLit('(A,I0)') + ') ' + FStrLit('Failed: ') + ', fail_count');
    Lines.Add('');
    Lines.Add('    call lf_exit_main_thread()');
    Lines.Add('    call lf_app_destroy(app)');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('');
    Lines.Add('    if (fail_count /= 0) then');
    Lines.Add('      stop 1');
    Lines.Add('    end if');
    Lines.Add('    stop 0');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  ! ---- Default mode: run until Enter ----');
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[OK] Service ready. Press Enter to stop.') + '');
    Lines.Add('  read (*, *)');
    Lines.Add('');
    Lines.Add('  call lf_exit_main_thread()');
    Lines.Add('  call lf_app_destroy(app)');
    Lines.Add('  call lf_shutdown()');
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[OK] Service stopped cleanly.') + '');
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');
    EmitSleepHelper(Lines);
    EmitReadResponseCode(Lines);
    Lines.Add('end program ' + NormalizedUnit.Text + '_http_json_service_main_test___');

    Result := Lines;
    Log(PFormat('Generated service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
    begin
      Lines.Free;
    end;
  end;
end;

// ===========================================================================
// CALL-SIDE TEST PROGRAM
// ===========================================================================

function GenerateHTTPCallFortranTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName, Endpoint, BaseUrl, FileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, SafeName, AsyncFlag, CbName, OKVar, ResultVar: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  HasParams: boolean;
  DefaultArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallFortranTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallFortranTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
  begin
    NormalizedUnit := '_' + NormalizedUnit;
  end;
  ModuleName := NormalizedUnit.LowerText + '_http_json_call_mod';
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  FileName := NormalizedUnit + '_http_json_call_main_test___.f90';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // -------------------------------------------------------------------------
    // Header
    // -------------------------------------------------------------------------
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('! ' + FileName.Text);
    Lines.Add('!');
    Lines.Add('! Auto-generated by http_fortran_abi_test_generator_tool.pas.');
    Lines.Add('! Source model unit: ' + UnitName.Text + '.');
    Lines.Add('! Do not edit by hand unless you know what you are doing.');
    Lines.Add('!');
    Lines.Add('! Call-side test program. For each exposed API:');
    Lines.Add('!   [sync]  <api>_call(args...)          (bridge.py required)');
    Lines.Add('!   [async] <api>_call_async(args..., cb)');
    Lines.Add('! Prints OK / FAILED per call, then a summary.');
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Async state module
    // -------------------------------------------------------------------------
    Lines.Add('module ' + NormalizedUnit.LowerText + '_call_test_async_state');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use ' + ModuleName.Text);
    Lines.Add('  implicit none');
    Lines.Add('  private');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      SafeName := MakeSafeFortranIdent(ApiNames[i], i);
      AsyncFlag := 'done_' + SafeName;
      OKVar := 'ok_' + SafeName;
      Lines.Add('  logical, save, public :: ' + AsyncFlag + ' = .false.');
      Lines.Add('  logical, save, public :: ' + OKVar + ' = .false.');
      if F.IsFunction then
      begin
        ResultVar := 'result_' + SafeName;
        Lines.Add('  ' + ABI_Type_To_Fortran_Module_Result_Decl(F.ReturnType, ResultVar));
      end;
    end;
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      SafeName := MakeSafeFortranIdent(ApiNames[i], i);
      CbName := 'cb_' + SafeName;
      Lines.Add('  public :: ' + CbName);
    end;
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      SafeName := MakeSafeFortranIdent(ApiNames[i], i);
      AsyncFlag := 'done_' + SafeName;
      CbName := 'cb_' + SafeName;
      OKVar := 'ok_' + SafeName;
      ResultVar := 'result_' + SafeName;
      Lines.Add('  subroutine ' + CbName + '(ud, handle) bind(C)');
      Lines.Add('    type(c_ptr), value :: ud');
      Lines.Add('    type(c_ptr), value :: handle');
      if F.IsFunction then
      begin
        Lines.Add('    logical :: local_ok');
        Lines.Add('    ' + ResultVar + ' = ' + SafeName + '_read_async_result(handle, local_ok)');
        Lines.Add('    ' + OKVar + ' = local_ok');
      end
      else
      begin
        Lines.Add('    ' + OKVar + ' = ' + SafeName + '_read_async_result(handle)');
      end;
      Lines.Add('    ' + AsyncFlag + ' = .true.');
      Lines.Add('  end subroutine ' + CbName);
      Lines.Add('');
    end;

    Lines.Add('end module ' + NormalizedUnit.LowerText + '_call_test_async_state');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Main program
    // -------------------------------------------------------------------------
    Lines.Add('program ' + NormalizedUnit.Text + '_http_json_call_main_test___');
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  use ' + ModuleName.Text);
    Lines.Add('  use ' + NormalizedUnit.LowerText + '_call_test_async_state');
    Lines.Add('  implicit none');
    Lines.Add('');
    Lines.Add('  integer :: pass_count, fail_count, i');
    Lines.Add('  character(len=512) :: base_url_arg');
    Lines.Add('  character(len=128) :: endpoint_arg');
    Lines.Add('');
    Lines.Add('  ! ---- Parse command line (optional) ----');
    Lines.Add('  if (command_argument_count() >= 1) then');
    Lines.Add('    call get_command_argument(1, base_url_arg)');
    Lines.Add('    HTTP_CALL_BASE_URL = trim(base_url_arg)');
    Lines.Add('  end if');
    Lines.Add('  if (command_argument_count() >= 2) then');
    Lines.Add('    call get_command_argument(2, endpoint_arg)');
    Lines.Add('  else');
    Lines.Add('    endpoint_arg = ' + FStrLit(Endpoint) + '');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('=== ' + UnitName + ' Fortran HTTP/JSON call test ===') + '');
    Lines.Add('  write(*, ' + FStrLit('(A,A)') + ') ' + FStrLit('Base URL : ') + ', trim(HTTP_CALL_BASE_URL)');
    Lines.Add('  write(*, ' + FStrLit('(A,A)') + ') ' + FStrLit('Endpoint : ') + ', trim(endpoint_arg)');
    Lines.Add('  write(*, ' + FStrLit('(A,A)') + ') ' + FStrLit('APIs     : ') + ', ' +
      FStrLit(umlIntToStr(Length(SupportedFuncs))) + '');
    Lines.Add('');
    Lines.Add('  call lf_reset_prepare()');
    Lines.Add('  call lf_set_opt_wait_ready_ok(.true.)');
    Lines.Add('  call lf_set_opt_overlap_connection(.true.)');
    Lines.Add('');
    Lines.Add('  if (lf_prepare_client(trim(endpoint_arg), c_null_ptr) < 0) then');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[FATAL] lf_prepare_client failed') + '');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  if (lf_prepare_done() /= 1_c_int) then');
    Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[FATAL] lf_prepare_done failed') + '');
    Lines.Add('    call lf_shutdown()');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('');
    Lines.Add('  call sleep_ms(2000)');
    Lines.Add('');
    Lines.Add('  pass_count = 0');
    Lines.Add('  fail_count = 0');
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' + FStrLit('') + '');
    Lines.Add('');

    // Per-API sync + async blocks
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      SafeName := MakeSafeFortranIdent(ApiName, i);
      AsyncFlag := 'done_' + SafeName;
      CbName := 'cb_' + SafeName;
      OKVar := 'ok_' + SafeName;
      HasParams := Length(F.Params) > 0;
      DefaultArgs := BuildDefaultTestArgList(F.Params);

      // ---- sync block ----
      Lines.Add('  ! ---- ' + ApiName + ' [sync] ----');
      Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('  ' + ApiName + ' [sync] : ') + '');
      if F.IsFunction then
      begin
        if ABI_Type_Is_String(F.ReturnType) then
        begin
          Lines.Add('  block');
          Lines.Add('    character(len=:), allocatable :: r');
          Lines.Add('    r = ' + SafeName + '_call(' + DefaultArgs + ')');
          Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
          Lines.Add('    pass_count = pass_count + 1');
          Lines.Add('  end block');
        end
        else if ABI_Type_Is_Float(F.ReturnType) then
        begin
          Lines.Add('  block');
          Lines.Add('    real(c_double) :: r');
          Lines.Add('    r = ' + SafeName + '_call(' + DefaultArgs + ')');
          Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
          Lines.Add('    pass_count = pass_count + 1');
          Lines.Add('  end block');
        end
        else
        begin
          Lines.Add('  block');
          Lines.Add('    integer(c_int64_t) :: r');
          Lines.Add('    r = ' + SafeName + '_call(' + DefaultArgs + ')');
          Lines.Add('    write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
          Lines.Add('    pass_count = pass_count + 1');
          Lines.Add('  end block');
        end;
      end
      else
      begin
        Lines.Add('  call ' + SafeName + '_call(' + DefaultArgs + ')');
        Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
        Lines.Add('  pass_count = pass_count + 1');
      end;
      Lines.Add('');

      // ---- async block ----
      Lines.Add('  ! ---- ' + ApiName + ' [async] ----');
      Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('  ' + ApiName + ' [async]: ') + '');
      Lines.Add('  block');
      Lines.Add('    ' + AsyncFlag + ' = .false.');
      Lines.Add('    ' + OKVar + ' = .false.');
      if HasParams then
      begin
        Lines.Add('    call ' + SafeName + '_call_async(' + DefaultArgs + ', &');
        Lines.Add('         c_funloc(' + CbName + '), c_null_ptr)');
      end
      else
      begin
        // ---- v4 fix ----
        // Emit an explicit continuation marker at the end of the
        // opening line. Without it, gfortran parses the "(" as an
        // already-closed empty argument list, then treats the
        // following "c_funloc(...)" line as an independent statement
        // and fails with "'c_funloc' at (1) is not a variable".
        Lines.Add('    call ' + SafeName + '_call_async( &');
        Lines.Add('         c_funloc(' + CbName + '), c_null_ptr)');
      end;
      Lines.Add('    do i = 1, 500');
      Lines.Add('      if (' + AsyncFlag + ') then');
      Lines.Add('        exit');
      Lines.Add('      end if');
      Lines.Add('      call sleep_ms(10)');
      Lines.Add('    end do');
      Lines.Add('    if (.not. ' + AsyncFlag + ') then');
      Lines.Add('      write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (timeout)') + '');
      Lines.Add('      fail_count = fail_count + 1');
      Lines.Add('    else if (.not. ' + OKVar + ') then');
      Lines.Add('      write(*, ' + FStrLit('(A)') + ') ' + FStrLit('FAILED (service code != 0)') + '');
      Lines.Add('      fail_count = fail_count + 1');
      Lines.Add('    else');
      Lines.Add('      write(*, ' + FStrLit('(A)') + ') ' + FStrLit('OK') + '');
      Lines.Add('      pass_count = pass_count + 1');
      Lines.Add('    end if');
      Lines.Add('  end block');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' + FStrLit('  (no APIs to test)') + '');
      Lines.Add('');
    end;

    // Summary
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' + FStrLit('') + '');
    Lines.Add('  write(*, ' + FStrLit('(A)') + ') ' + FStrLit('=== Summary ===') + '');
    Lines.Add('  write(*, ' + FStrLit('(A,I0)') + ') ' + FStrLit('Passed: ') + ', pass_count');
    Lines.Add('  write(*, ' + FStrLit('(A,I0)') + ') ' + FStrLit('Failed: ') + ', fail_count');
    Lines.Add('');
    Lines.Add('  call lf_exit_main_thread()');
    Lines.Add('  call lf_shutdown()');
    Lines.Add('');
    Lines.Add('  if (fail_count /= 0) then');
    Lines.Add('    stop 1');
    Lines.Add('  end if');
    Lines.Add('  stop 0');
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');
    EmitSleepHelper(Lines);
    Lines.Add('end program ' + NormalizedUnit.Text + '_http_json_call_main_test___');

    Result := Lines;
    Log(PFormat('Generated call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
    begin
      Lines.Free;
    end;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'fortran', 'Fortran HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.f90', False,
    @GenerateHTTPServiceFortranTestCode);
  RegisterCodeGenEntry(
    'fortran', 'Fortran HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.f90', False,
    @GenerateHTTPCallFortranTestCode);
end.
