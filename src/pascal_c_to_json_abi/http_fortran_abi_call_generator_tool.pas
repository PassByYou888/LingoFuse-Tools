unit http_fortran_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallFortranCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_fortran_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_fortran_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Fortran_Param_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := 'character(len=*), intent(in)';
  end
  else if ABI_Type_Is_Float(T) then
  begin
    Result := 'real(c_double), intent(in)';
  end
  else if ABI_Type_Is_Int(T) then
  begin
    Result := 'integer(c_int64_t), intent(in)';
  end
  else
  begin
    Result := '';
  end;
end;

function ABI_Type_To_Fortran_Return_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := 'character(len=:), allocatable';
  end
  else if ABI_Type_Is_Float(T) then
  begin
    Result := 'real(c_double)';
  end
  else if ABI_Type_Is_Int(T) then
  begin
    Result := 'integer(c_int64_t)';
  end
  else
  begin
    Result := '';
  end;
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

function ABI_Type_To_Fortran_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := FStrLit('');
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

function ABI_Type_To_Json_Body_Fragment(const VarName, T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := 'json_escape_string(' + VarName + ')';
  end
  else if ABI_Type_Is_Float(T) then
  begin
    Result := 'ftoa_d(' + VarName + ')';
  end
  else
  begin
    Result := 'itoa_i64(' + VarName + ')';
  end;
end;

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
  begin
    Result := 'string';
  end
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
  begin
    Result := 'number';
  end
  else
  begin
    Result := '';
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

function BuildFortranParamDecl(const Params: TParamArray): TP_String;
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
// JSON helper emission
// ---------------------------------------------------------------------------

procedure EmitJsonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('  ! ======================================================================');
  Lines.Add('  ! Minimal inlined JSON helpers.');
  Lines.Add('  ! The module stays self-contained: iso_c_binding + lf_fortran_mod only.');
  Lines.Add('  ! ======================================================================');
  Lines.Add('');
  Lines.Add('  ! itoa_i64 - format a signed 64-bit integer.');
  Lines.Add('  function itoa_i64(v) result(s)');
  Lines.Add('    integer(c_int64_t), intent(in) :: v');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    character(len=32) :: tmp');
  Lines.Add('    write(tmp, ' + FStrLit('(I0)') + ') v');
  Lines.Add('    s = trim(tmp)');
  Lines.Add('  end function itoa_i64');
  Lines.Add('');
  Lines.Add('  ! ftoa_d - format a double in a JSON-compatible way.');
  Lines.Add('  function ftoa_d(v) result(s)');
  Lines.Add('    real(c_double), intent(in) :: v');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    character(len=64) :: tmp');
  Lines.Add('    write(tmp, ' + FStrLit('(G0)') + ') v');
  Lines.Add('    s = trim(tmp)');
  Lines.Add('  end function ftoa_d');
  Lines.Add('');
  Lines.Add('  ! json_escape_string - wrap a string in double quotes.');
  Lines.Add('  function json_escape_string(s) result(v)');
  Lines.Add('    character(len=*), intent(in) :: s');
  Lines.Add('    character(len=:), allocatable :: v, tmp');
  Lines.Add('    integer :: i');
  Lines.Add('    tmp = ' + FStrLit('') + '');
  Lines.Add('    do i = 1, len(s)');
  Lines.Add('      select case (s(i:i))');
  Lines.Add('        case (' + FStrLit('"') + ')');
  Lines.Add('          tmp = tmp // ' + FStrLit('\"') + '');
  Lines.Add('        case (' + FStrLit('\') + ')');
  Lines.Add('          tmp = tmp // ' + FStrLit('\\') + '');
  Lines.Add('        case (char(10))');
  Lines.Add('          tmp = tmp // ' + FStrLit('\n') + '');
  Lines.Add('        case (char(13))');
  Lines.Add('          tmp = tmp // ' + FStrLit('\r') + '');
  Lines.Add('        case (char(9))');
  Lines.Add('          tmp = tmp // ' + FStrLit('\t') + '');
  Lines.Add('        case default');
  Lines.Add('          tmp = tmp // s(i:i)');
  Lines.Add('      end select');
  Lines.Add('    end do');
  Lines.Add('    v = ' + FStrLit('"') + ' // tmp // ' + FStrLit('"') + '');
  Lines.Add('  end function json_escape_string');
  Lines.Add('');
  Lines.Add('  ! build_outer_envelope - build the bridge request envelope.');
  Lines.Add('  function build_outer_envelope(url, body_json, timeout_sec) result(env)');
  Lines.Add('    character(len=*), intent(in) :: url, body_json');
  Lines.Add('    real(c_double), intent(in) :: timeout_sec');
  Lines.Add('    character(len=:), allocatable :: env');
  Lines.Add('    character(len=32) :: tstr');
  Lines.Add('    integer :: it');
  Lines.Add('    it = nint(timeout_sec)');
  Lines.Add('    write(tstr, ' + FStrLit('(I0)') + ') it');
  Lines.Add('    env = ' + FStrLit('{"url":"') + ' // trim(url) // ' +
    FStrLit('","method":"POST","body":') + ' // trim(body_json) // ' +
    FStrLit(',"timeout":') + ' // trim(tstr) // ' + FStrLit('}') + '');
  Lines.Add('  end function build_outer_envelope');
  Lines.Add('');
  Lines.Add('  ! find_key_int - find the first integer value after "<key>": in s.');
  Lines.Add('  function find_key_int(s, key, def) result(v)');
  Lines.Add('    character(len=*), intent(in) :: s, key');
  Lines.Add('    integer, intent(in) :: def');
  Lines.Add('    integer :: v');
  Lines.Add('    integer :: p, q, slen, ios');
  Lines.Add('    character(len=:), allocatable :: tmp');
  Lines.Add('    v = def');
  Lines.Add('    slen = len(s)');
  Lines.Add('    p = index(s, ' + FStrLit('"') + ' // key // ' + FStrLit('":') + ')');
  Lines.Add('    if (p <= 0) return');
  Lines.Add('    p = p + len(key) + 3');
  Lines.Add('    do while (p <= slen .and. s(p:p) == ' + FStrLit(' ') + ')');
  Lines.Add('      p = p + 1');
  Lines.Add('    end do');
  Lines.Add('    q = p');
  Lines.Add('    do while (q <= slen)');
  Lines.Add('      if (s(q:q) == ' + FStrLit('-') + ') then');
  Lines.Add('        q = q + 1');
  Lines.Add('      else if (s(q:q) >= ' + FStrLit('0') + ' .and. ' + 's(q:q) <= ' + FStrLit('9') + ') then');
  Lines.Add('        q = q + 1');
  Lines.Add('      else');
  Lines.Add('        exit');
  Lines.Add('      end if');
  Lines.Add('    end do');
  Lines.Add('    if (q > p) then');
  Lines.Add('      tmp = s(p:q-1)');
  Lines.Add('      read(tmp, *, iostat=ios) v');
  Lines.Add('      if (ios /= 0) v = def');
  Lines.Add('    end if');
  Lines.Add('  end function find_key_int');
  Lines.Add('');
  Lines.Add('  ! read_response_code - extract the service code.');
  Lines.Add('  function read_response_code(resp_json) result(code)');
  Lines.Add('    character(len=*), intent(in) :: resp_json');
  Lines.Add('    integer :: code');
  Lines.Add('    if (index(resp_json, ' + FStrLit('"error"') + ') > 0) then');
  Lines.Add('      if (index(resp_json, ' + FStrLit('"body"') + ') <= 0) then');
  Lines.Add('        code = -1');
  Lines.Add('        return');
  Lines.Add('      end if');
  Lines.Add('    end if');
  Lines.Add('    code = find_key_int(resp_json, ' + FStrLit('code') + ', -1)');
  Lines.Add('  end function read_response_code');
  Lines.Add('');
  Lines.Add('  ! read_response_result_i64 - extract the integer result.');
  Lines.Add('  function read_response_result_i64(resp_json, default) result(v)');
  Lines.Add('    character(len=*), intent(in) :: resp_json');
  Lines.Add('    integer(c_int64_t), intent(in) :: default');
  Lines.Add('    integer(c_int64_t) :: v');
  Lines.Add('    integer :: iv');
  Lines.Add('    iv = find_key_int(resp_json, ' + FStrLit('result') + ', int(default))');
  Lines.Add('    v = int(iv, c_int64_t)');
  Lines.Add('  end function read_response_result_i64');
  Lines.Add('');
  Lines.Add('  ! read_response_result_double - extract the floating-point result.');
  Lines.Add('  function read_response_result_double(resp_json, default) result(v)');
  Lines.Add('    character(len=*), intent(in) :: resp_json');
  Lines.Add('    real(c_double), intent(in) :: default');
  Lines.Add('    real(c_double) :: v');
  Lines.Add('    integer :: p, q, slen, ios');
  Lines.Add('    character(len=:), allocatable :: tmp');
  Lines.Add('    v = default');
  Lines.Add('    slen = len(resp_json)');
  Lines.Add('    p = index(resp_json, ' + FStrLit('"result":') + ')');
  Lines.Add('    if (p <= 0) return');
  Lines.Add('    p = p + 9');
  Lines.Add('    do while (p <= slen .and. resp_json(p:p) == ' + FStrLit(' ') + ')');
  Lines.Add('      p = p + 1');
  Lines.Add('    end do');
  Lines.Add('    q = p');
  Lines.Add('    do while (q <= slen)');
  Lines.Add('      if (resp_json(q:q) == ' + FStrLit(',') + ') exit');
  Lines.Add('      if (resp_json(q:q) == ' + FStrLit('}') + ') exit');
  Lines.Add('      if (resp_json(q:q) == ' + FStrLit(']') + ') exit');
  Lines.Add('      q = q + 1');
  Lines.Add('    end do');
  Lines.Add('    if (q > p) then');
  Lines.Add('      tmp = resp_json(p:q-1)');
  Lines.Add('      read(tmp, *, iostat=ios) v');
  Lines.Add('      if (ios /= 0) v = default');
  Lines.Add('    end if');
  Lines.Add('  end function read_response_result_double');
  Lines.Add('');
  Lines.Add('  ! read_response_result_string - extract the string result.');
  Lines.Add('  function read_response_result_string(resp_json) result(v)');
  Lines.Add('    character(len=*), intent(in) :: resp_json');
  Lines.Add('    character(len=:), allocatable :: v');
  Lines.Add('    integer :: p, q, slen');
  Lines.Add('    v = ' + FStrLit('') + '');
  Lines.Add('    slen = len(resp_json)');
  Lines.Add('    p = index(resp_json, ' + FStrLit('"result":"') + ')');
  Lines.Add('    if (p <= 0) return');
  Lines.Add('    p = p + 10');
  Lines.Add('    q = p');
  Lines.Add('    do while (q <= slen)');
  Lines.Add('      if (resp_json(q:q) == ' + FStrLit('"') + ') then');
  Lines.Add('        if (q > p) then');
  Lines.Add('          if (resp_json(q-1:q-1) == ' + FStrLit('\') + ') then');
  Lines.Add('            q = q + 1');
  Lines.Add('            cycle');
  Lines.Add('          end if');
  Lines.Add('        end if');
  Lines.Add('        exit');
  Lines.Add('      end if');
  Lines.Add('      q = q + 1');
  Lines.Add('    end do');
  Lines.Add('    if (q > p) v = resp_json(p:q-1)');
  Lines.Add('  end function read_response_result_string');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Init routine
// ---------------------------------------------------------------------------

procedure EmitInitRoutine(Lines: TPascalStringList);
begin
  Lines.Add('  ! ======================================================================');
  Lines.Add('  ! Configuration.');
  Lines.Add('  ! ======================================================================');
  Lines.Add('');
  Lines.Add('  subroutine http_call_init(base_url, bridge_app, bridge_api, &');
  Lines.Add('                           call_timeout_ms, http_timeout_sec)');
  Lines.Add('    character(len=*), intent(in), optional :: base_url');
  Lines.Add('    character(len=*), intent(in), optional :: bridge_app');
  Lines.Add('    character(len=*), intent(in), optional :: bridge_api');
  Lines.Add('    integer(c_int64_t), intent(in), optional :: call_timeout_ms');
  Lines.Add('    real(c_double), intent(in), optional :: http_timeout_sec');
  Lines.Add('');
  Lines.Add('    if (present(base_url)) HTTP_CALL_BASE_URL = base_url');
  Lines.Add('    if (present(bridge_app)) HTTP_BRIDGE_APP_NAME = bridge_app');
  Lines.Add('    if (present(bridge_api)) HTTP_BRIDGE_API_NAME = bridge_api');
  Lines.Add('    if (present(call_timeout_ms)) HTTP_CALL_TIMEOUT_MS = call_timeout_ms');
  Lines.Add('    if (present(http_timeout_sec)) HTTP_CALL_DEFAULT_TIMEOUT_S = http_timeout_sec');
  Lines.Add('  end subroutine http_call_init');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Timeout helpers
// ---------------------------------------------------------------------------

procedure EmitTimeoutHelpers(Lines: TPascalStringList);
begin
  Lines.Add('  ! effective_call_timeout_ms - the LF_Call timeout.');
  Lines.Add('  function effective_call_timeout_ms() result(v)');
  Lines.Add('    integer(c_int64_t) :: v');
  Lines.Add('    if (HTTP_CALL_TIMEOUT_MS > 0_c_int64_t) then');
  Lines.Add('      v = HTTP_CALL_TIMEOUT_MS');
  Lines.Add('    else');
  Lines.Add('      v = 60000_c_int64_t');
  Lines.Add('    end if');
  Lines.Add('  end function effective_call_timeout_ms');
  Lines.Add('');
  Lines.Add('  ! effective_http_timeout_sec - the HTTP timeout.');
  Lines.Add('  function effective_http_timeout_sec() result(v)');
  Lines.Add('    real(c_double) :: v');
  Lines.Add('    if (HTTP_CALL_DEFAULT_TIMEOUT_S > 0.0d0) then');
  Lines.Add('      v = HTTP_CALL_DEFAULT_TIMEOUT_S');
  Lines.Add('    else');
  Lines.Add('      v = 25.0d0');
  Lines.Add('    end if');
  Lines.Add('  end function effective_http_timeout_sec');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Main call-module generator
// ---------------------------------------------------------------------------

function GenerateHTTPCallFortranCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName, DefaultBaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, SyncName, AsyncName, ReadName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  RetDecl: TP_String;
  HasParams: boolean;
  Description: TP_String;
  BodyFragment, ArgName: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallFortranCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallFortranCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
  begin
    NormalizedUnit := '_' + NormalizedUnit;
  end;
  ModuleName := NormalizedUnit.LowerText + '_http_json_call_mod';
  AppName := NormalizedUnit;
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

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
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('! ' + ModuleName.Text + '.f90');
    Lines.Add('!');
    Lines.Add('! Auto-generated by http_fortran_abi_call_generator_tool.pas.');
    Lines.Add('! Source model unit: ' + UnitName.Text + '.');
    Lines.Add('! Do not edit by hand unless you know what you are doing.');
    Lines.Add('!');
    Lines.Add('! This module is the CALL side of the Fortran HTTP/JSON binding.');
    Lines.Add('! It routes requests to the LingoFuse HTTP bridge (bridge.py) and');
    Lines.Add('! parses the response. It does NOT speak HTTP directly.');
    Lines.Add('!');
    Lines.Add('! Dependencies: iso_c_binding, lf_fortran_mod.');
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('module ' + ModuleName.Text);
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  implicit none');
    Lines.Add('  private');
    Lines.Add('');
    Lines.Add('  character(len=512), save, public :: HTTP_CALL_BASE_URL = ' +
      FStrLit(DefaultBaseUrl) + '');
    Lines.Add('  character(len=128), save, public :: HTTP_BRIDGE_APP_NAME = ' +
      FStrLit('__lf_http_bridge__') + '');
    Lines.Add('  character(len=128), save, public :: HTTP_BRIDGE_API_NAME = ' +
      FStrLit('__lf_outbound_post__') + '');
    Lines.Add('  integer(c_int64_t), save, public :: HTTP_CALL_TIMEOUT_MS = 0_c_int64_t');
    Lines.Add('  real(c_double), save, public :: HTTP_CALL_DEFAULT_TIMEOUT_S = 0.0d0');
    Lines.Add('');
    Lines.Add('  public :: http_call_init');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      SyncName := MakeSafeFortranIdent(ApiNames[i], i) + '_call';
      AsyncName := MakeSafeFortranIdent(ApiNames[i], i) + '_call_async';
      ReadName := MakeSafeFortranIdent(ApiNames[i], i) + '_read_async_result';
      Lines.Add('  public :: ' + SyncName.Text);
      Lines.Add('  public :: ' + AsyncName.Text);
      Lines.Add('  public :: ' + ReadName.Text);
    end;
    Lines.Add('');
    Lines.Add('  abstract interface');
    Lines.Add('    subroutine HTTP_CALL_ASYNC_CALLBACK(user_data, result_handle) bind(C)');
    Lines.Add('      import :: c_ptr');
    Lines.Add('      type(c_ptr), value :: user_data');
    Lines.Add('      type(c_ptr), value :: result_handle');
    Lines.Add('    end subroutine HTTP_CALL_ASYNC_CALLBACK');
    Lines.Add('  end interface');
    Lines.Add('');
    Lines.Add('  public :: HTTP_CALL_ASYNC_CALLBACK');
    Lines.Add('');
    Lines.Add('contains');
    Lines.Add('');

    EmitJsonHelpers(Lines);
    EmitTimeoutHelpers(Lines);
    EmitInitRoutine(Lines);

    // -------------------------------------------------------------------------
    // Sync functions
    // -------------------------------------------------------------------------
    Lines.Add('  ! ======================================================================');
    Lines.Add('  ! Synchronous call functions.');
    Lines.Add('  ! ======================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      SyncName := MakeSafeFortranIdent(ApiName, i) + '_call';
      HasParams := Length(F.Params) > 0;

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
      begin
        Description := 'HTTP/JSON api for ' + F.Name;
      end;

      Lines.Add('  ! ' + Description.Text);
      Lines.Add('  ! HTTP route: POST /' + AppName.Text + '/' + ApiName.Text);

      if F.IsFunction then
      begin
        RetDecl := ABI_Type_To_Fortran_Return_Decl(F.ReturnType);
        Lines.Add('  function ' + SyncName.Text + '(' + BuildFortranParamDecl(F.Params) +
          ') result(r)');
        if HasParams then
        begin
          for j := 0 to High(F.Params) do
          begin
            Lines.Add('    ' + ABI_Type_To_Fortran_Param_Decl(F.Params[j].PascalType) +
              ' :: ' + MakeSafeFortranIdent(F.Params[j].Name, j));
          end;
        end;
        Lines.Add('    ' + RetDecl.Text + ' :: r');
        Lines.Add('    type(c_ptr) :: req, res_h');
        Lines.Add('    character(len=:), allocatable :: body, outer, resp_json');
        Lines.Add('    integer(c_int64_t) :: resp_size');
        Lines.Add('');
        Lines.Add('    body = ' + FStrLit('{"args":[') + '');
        for j := 0 to High(F.Params) do
        begin
          ArgName := MakeSafeFortranIdent(F.Params[j].Name, j);
          BodyFragment := ABI_Type_To_Json_Body_Fragment(ArgName, F.Params[j].PascalType);
          if j = 0 then
          begin
            Lines.Add('    body = body // ' + BodyFragment);
          end
          else
          begin
            Lines.Add('    body = body // ' + FStrLit(',') + ' // ' + BodyFragment);
          end;
        end;
        Lines.Add('    body = body // ' + FStrLit(']}') + '');
        Lines.Add('');
        Lines.Add('    outer = build_outer_envelope(&');
        Lines.Add('      trim(HTTP_CALL_BASE_URL) // ' + FStrLit('/') + ' // ' +
          FStrLit(ApiName) + ', &');
        Lines.Add('      body, effective_http_timeout_sec())');
        Lines.Add('');
        Lines.Add('    req = lf_data_create(trim(HTTP_BRIDGE_API_NAME))');
        Lines.Add('    if (.not. c_associated(req)) then');
        Lines.Add('      r = ' + ABI_Type_To_Fortran_Default(F.ReturnType) + '');
        Lines.Add('      return');
        Lines.Add('    end if');
        Lines.Add('    if (lf_data_write_string(req, outer) /= 1_c_int) then');
        Lines.Add('      call lf_data_destroy(req)');
        Lines.Add('      r = ' + ABI_Type_To_Fortran_Default(F.ReturnType) + '');
        Lines.Add('      return');
        Lines.Add('    end if');
        Lines.Add('    res_h = lf_call(trim(HTTP_BRIDGE_APP_NAME), req, &');
        Lines.Add('                    effective_call_timeout_ms())');
        Lines.Add('    call lf_data_destroy(req)');
        Lines.Add('    if (.not. c_associated(res_h)) then');
        Lines.Add('      r = ' + ABI_Type_To_Fortran_Default(F.ReturnType) + '');
        Lines.Add('      return');
        Lines.Add('    end if');
        Lines.Add('    resp_size = lf_data_get_size(res_h)');
        Lines.Add('    if (resp_size <= 0_c_int64_t) then');
        Lines.Add('      call lf_data_destroy(res_h)');
        Lines.Add('      r = ' + ABI_Type_To_Fortran_Default(F.ReturnType) + '');
        Lines.Add('      return');
        Lines.Add('    end if');
        Lines.Add('    call lf_data_read_string(res_h, resp_json)');
        Lines.Add('    call lf_data_destroy(res_h)');
        Lines.Add('');
        if ABI_Type_Is_String(F.ReturnType) then
        begin
          Lines.Add('    r = read_response_result_string(resp_json)');
        end
        else if ABI_Type_Is_Float(F.ReturnType) then
        begin
          Lines.Add('    r = read_response_result_double(resp_json, 0.0d0)');
        end
        else
        begin
          Lines.Add('    r = read_response_result_i64(resp_json, 0_c_int64_t)');
        end;
        Lines.Add('  end function ' + SyncName.Text);
      end
      else
      begin
        Lines.Add('  subroutine ' + SyncName.Text + '(' + BuildFortranParamDecl(F.Params) + ')');
        if HasParams then
        begin
          for j := 0 to High(F.Params) do
          begin
            Lines.Add('    ' + ABI_Type_To_Fortran_Param_Decl(F.Params[j].PascalType) +
              ' :: ' + MakeSafeFortranIdent(F.Params[j].Name, j));
          end;
        end;
        Lines.Add('    type(c_ptr) :: req, res_h');
        Lines.Add('    character(len=:), allocatable :: body, outer');
        Lines.Add('');
        Lines.Add('    body = ' + FStrLit('{"args":[') + '');
        for j := 0 to High(F.Params) do
        begin
          ArgName := MakeSafeFortranIdent(F.Params[j].Name, j);
          BodyFragment := ABI_Type_To_Json_Body_Fragment(ArgName, F.Params[j].PascalType);
          if j = 0 then
          begin
            Lines.Add('    body = body // ' + BodyFragment);
          end
          else
          begin
            Lines.Add('    body = body // ' + FStrLit(',') + ' // ' + BodyFragment);
          end;
        end;
        Lines.Add('    body = body // ' + FStrLit(']}') + '');
        Lines.Add('');
        Lines.Add('    outer = build_outer_envelope(&');
        Lines.Add('      trim(HTTP_CALL_BASE_URL) // ' + FStrLit('/') + ' // ' +
          FStrLit(ApiName) + ', &');
        Lines.Add('      body, effective_http_timeout_sec())');
        Lines.Add('    req = lf_data_create(trim(HTTP_BRIDGE_API_NAME))');
        Lines.Add('    if (.not. c_associated(req)) return');
        Lines.Add('    if (lf_data_write_string(req, outer) /= 1_c_int) then');
        Lines.Add('      call lf_data_destroy(req)');
        Lines.Add('      return');
        Lines.Add('    end if');
        Lines.Add('    res_h = lf_call(trim(HTTP_BRIDGE_APP_NAME), req, &');
        Lines.Add('                    effective_call_timeout_ms())');
        Lines.Add('    call lf_data_destroy(req)');
        Lines.Add('    if (c_associated(res_h)) call lf_data_destroy(res_h)');
        Lines.Add('  end subroutine ' + SyncName.Text);
      end;
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // Async subroutines
    // -------------------------------------------------------------------------
    Lines.Add('  ! ======================================================================');
    Lines.Add('  ! Asynchronous submit routines.');
    Lines.Add('  ! ======================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      AsyncName := MakeSafeFortranIdent(ApiName, i) + '_call_async';
      HasParams := Length(F.Params) > 0;

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
      begin
        Description := 'HTTP/JSON api for ' + F.Name;
      end;

      Lines.Add('  ! ' + Description.Text);
      Lines.Add('  ! HTTP route: POST /' + AppName.Text + '/' + ApiName.Text);
      Lines.Add('  subroutine ' + AsyncName.Text + '(' + BuildFortranParamDecl(F.Params) +
        if_(HasParams, ', ', '') + 'callback, user_data)');
      if HasParams then
      begin
        for j := 0 to High(F.Params) do
        begin
          Lines.Add('    ' + ABI_Type_To_Fortran_Param_Decl(F.Params[j].PascalType) +
            ' :: ' + MakeSafeFortranIdent(F.Params[j].Name, j));
        end;
      end;
      Lines.Add('    type(c_funptr), value :: callback');
      Lines.Add('    type(c_ptr), value :: user_data');
      Lines.Add('    type(c_ptr) :: req');
      Lines.Add('    character(len=:), allocatable :: body, outer');
      Lines.Add('    integer(c_int) :: rc');
      Lines.Add('');
      Lines.Add('    body = ' + FStrLit('{"args":[') + '');
      for j := 0 to High(F.Params) do
      begin
        ArgName := MakeSafeFortranIdent(F.Params[j].Name, j);
        BodyFragment := ABI_Type_To_Json_Body_Fragment(ArgName, F.Params[j].PascalType);
        if j = 0 then
        begin
          Lines.Add('    body = body // ' + BodyFragment);
        end
        else
        begin
          Lines.Add('    body = body // ' + FStrLit(',') + ' // ' + BodyFragment);
        end;
      end;
      Lines.Add('    body = body // ' + FStrLit(']}') + '');
      Lines.Add('');
      Lines.Add('    outer = build_outer_envelope(&');
      Lines.Add('      trim(HTTP_CALL_BASE_URL) // ' + FStrLit('/') + ' // ' +
        FStrLit(ApiName) + ', &');
      Lines.Add('      body, effective_http_timeout_sec())');
      Lines.Add('');
      Lines.Add('    req = lf_data_create(trim(HTTP_BRIDGE_API_NAME))');
      Lines.Add('    if (.not. c_associated(req)) return');
      Lines.Add('    if (lf_data_write_string(req, outer) /= 1_c_int) then');
      Lines.Add('      call lf_data_destroy(req)');
      Lines.Add('      return');
      Lines.Add('    end if');
      Lines.Add('    rc = lf_async_call(trim(HTTP_BRIDGE_APP_NAME), req, &');
      Lines.Add('                       callback, user_data)');
      Lines.Add('    call lf_data_destroy(req)');
      Lines.Add('');
      Lines.Add('    ! NOTE: on dispatch failure (rc /= 1), the underlying C++');
      Lines.Add('    ! bridge has ALREADY invoked the user callback synchronously');
      Lines.Add('    ! on this thread with a NULL handle. Fortran cannot invoke a');
      Lines.Add('    ! c_funptr directly, so we let the C layer handle it.');
      Lines.Add('  end subroutine ' + AsyncName.Text);
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // Async result readers
    // -------------------------------------------------------------------------
    Lines.Add('  ! ======================================================================');
    Lines.Add('  ! Async result readers.');
    Lines.Add('  ! ======================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ReadName := MakeSafeFortranIdent(ApiName, i) + '_read_async_result';

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
      begin
        Description := 'HTTP/JSON api for ' + F.Name;
      end;

      Lines.Add('  ! ' + Description.Text);
      if F.IsFunction then
      begin
        RetDecl := ABI_Type_To_Fortran_Return_Decl(F.ReturnType);
        Lines.Add('  function ' + ReadName.Text + '(handle, ok) result(r)');
        Lines.Add('    type(c_ptr), value :: handle');
        Lines.Add('    logical, intent(out) :: ok');
        Lines.Add('    ' + RetDecl.Text + ' :: r');
        Lines.Add('    character(len=:), allocatable :: resp_json');
        Lines.Add('    integer :: code');
        Lines.Add('');
        Lines.Add('    r = ' + ABI_Type_To_Fortran_Default(F.ReturnType) + '');
        Lines.Add('    ok = .false.');
        Lines.Add('    if (.not. c_associated(handle)) return');
        Lines.Add('    if (lf_data_get_size(handle) <= 0_c_int64_t) return');
        Lines.Add('    call lf_data_read_string(handle, resp_json)');
        Lines.Add('    code = read_response_code(resp_json)');
        Lines.Add('    if (code /= 0) return');
        if ABI_Type_Is_String(F.ReturnType) then
        begin
          Lines.Add('    r = read_response_result_string(resp_json)');
        end
        else if ABI_Type_Is_Float(F.ReturnType) then
        begin
          Lines.Add('    r = read_response_result_double(resp_json, 0.0d0)');
        end
        else
        begin
          Lines.Add('    r = read_response_result_i64(resp_json, 0_c_int64_t)');
        end;
        Lines.Add('    ok = .true.');
        Lines.Add('  end function ' + ReadName.Text);
      end
      else
      begin
        Lines.Add('  function ' + ReadName.Text + '(handle) result(ok)');
        Lines.Add('    type(c_ptr), value :: handle');
        Lines.Add('    logical :: ok');
        Lines.Add('    character(len=:), allocatable :: resp_json');
        Lines.Add('    integer :: code');
        Lines.Add('');
        Lines.Add('    ok = .false.');
        Lines.Add('    if (.not. c_associated(handle)) return');
        Lines.Add('    if (lf_data_get_size(handle) <= 0_c_int64_t) return');
        Lines.Add('    call lf_data_read_string(handle, resp_json)');
        Lines.Add('    code = read_response_code(resp_json)');
        Lines.Add('    if (code == 0) ok = .true.');
        Lines.Add('  end function ' + ReadName.Text);
      end;
      Lines.Add('');
    end;

    Lines.Add('end module ' + ModuleName.Text);

    Result := Lines;
    Log(PFormat('Generated Fortran call module: %d lines, %d routines.',
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
    'fortran', 'Fortran HTTP/JSON call module',
    asCall, akCallCode,
    '_http_json_call_mod.f90', False,
    @GenerateHTTPCallFortranCode);
end.
