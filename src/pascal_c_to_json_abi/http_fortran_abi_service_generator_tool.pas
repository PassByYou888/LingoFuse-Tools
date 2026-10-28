unit http_fortran_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceFortranCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_fortran_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_fortran_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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
    Result := 'character(len=*), intent(in)'
  else if ABI_Type_Is_Float(T) then
    Result := 'real(c_double), intent(in)'
  else if ABI_Type_Is_Int(T) then
    Result := 'integer(c_int64_t), intent(in)'
  else
    Result := '';
end;

function ABI_Type_To_Fortran_Return_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'character(len=:), allocatable'
  else if ABI_Type_Is_Float(T) then
    Result := 'real(c_double)'
  else if ABI_Type_Is_Int(T) then
    Result := 'integer(c_int64_t)'
  else
    Result := '';
end;

function ABI_Type_To_Fortran_Local_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'character(len=:), allocatable'
  else if ABI_Type_Is_Float(T) then
    Result := 'real(c_double)'
  else if ABI_Type_Is_Int(T) then
    Result := 'integer(c_int64_t)'
  else
    Result := '';
end;

function ABI_Type_To_Json_Extractor_Suffix(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) then
    Result := 'double'
  else
    Result := 'int64';
end;

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
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
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

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
    Inc(i);
  Result := Base + '_' + umlIntToStr(i).Text;
end;

// FStrLit - produce a Fortran single-quoted string literal.
// Uses #39 for both surrounding quotes and internal escape.
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
      Result.Append(c);
  end;
  Result.Append(#39);
end;

// ---------------------------------------------------------------------------
// Comment / description extraction
// ---------------------------------------------------------------------------

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
          // Doxygen tag; skip.
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
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

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
      Result := Result + ', ';
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
      ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
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
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
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
// JSON helper emission (inlined into each generated .f90 module)
// ---------------------------------------------------------------------------

procedure EmitJsonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('  ! ======================================================================');
  Lines.Add('  ! Minimal inlined JSON helpers.');
  Lines.Add('  ! These handle the request shape {"args":[...]} and the response');
  Lines.Add('  ! shapes {"code":0,"result":...} / {"code":-1,"error":"..."} .');
  Lines.Add('  ! For anything more elaborate, extend this block or replace it with');
  Lines.Add('  ! a full JSON library.');
  Lines.Add('  ! ======================================================================');
  Lines.Add('');
  Lines.Add('contains');
  Lines.Add('');
  Lines.Add('  ! json_extract_arg_raw - return the raw text of the idx-th element');
  Lines.Add('  ! of the "args" array inside s . Returns an empty string on miss.');
  Lines.Add('  function json_extract_arg_raw(s, idx) result(raw)');
  Lines.Add('    character(len=*), intent(in) :: s');
  Lines.Add('    integer, intent(in) :: idx');
  Lines.Add('    character(len=:), allocatable :: raw');
  Lines.Add('    integer :: p, q, depth, arg_i, slen');
  Lines.Add('    logical :: in_str');
  Lines.Add('    character :: c');
  Lines.Add('');
  Lines.Add('    raw = ' + FStrLit('') + '');
  Lines.Add('    slen = len(s)');
  Lines.Add('    p = index(s, ' + FStrLit('"args"') + ')');
  Lines.Add('    if (p <= 0) return');
  Lines.Add('    p = p + 6');
  Lines.Add('    do while (p <= slen .and. (s(p:p) == ' + FStrLit(' ') + ' .or. s(p:p) == ' + FStrLit(':') + '))');
  Lines.Add('      p = p + 1');
  Lines.Add('    end do');
  Lines.Add('    if (p > slen .or. s(p:p) /= ' + FStrLit('[') + ') return');
  Lines.Add('    p = p + 1');
  Lines.Add('    q = p');
  Lines.Add('    depth = 0');
  Lines.Add('    arg_i = 0');
  Lines.Add('    in_str = .false.');
  Lines.Add('');
  Lines.Add('    do while (p <= slen)');
  Lines.Add('      c = s(p:p)');
  Lines.Add('      if (in_str) then');
  Lines.Add('        if (c == ' + FStrLit('\') + ' .and. p < slen) then');
  Lines.Add('          p = p + 2');
  Lines.Add('          cycle');
  Lines.Add('        else if (c == ' + FStrLit('"') + ') then');
  Lines.Add('          in_str = .false.');
  Lines.Add('        end if');
  Lines.Add('      else');
  Lines.Add('        if (c == ' + FStrLit('"') + ') then');
  Lines.Add('          in_str = .true.');
  Lines.Add('        else if (c == ' + FStrLit('[') + ' .or. c == ' + FStrLit('{') + ') then');
  Lines.Add('          depth = depth + 1');
  Lines.Add('        else if (c == ' + FStrLit(']') + ' .or. c == ' + FStrLit('}') + ') then');
  Lines.Add('          if (depth == 0 .and. c == ' + FStrLit(']') + ') then');
  Lines.Add('            if (arg_i == idx .and. p > q) then');
  Lines.Add('              raw = trim(adjustl(s(q:p-1)))');
  Lines.Add('            end if');
  Lines.Add('            return');
  Lines.Add('          end if');
  Lines.Add('          depth = depth - 1');
  Lines.Add('        else if (c == ' + FStrLit(',') + ' .and. depth == 0) then');
  Lines.Add('          if (arg_i == idx) then');
  Lines.Add('            if (p > q) then');
  Lines.Add('              raw = trim(adjustl(s(q:p-1)))');
  Lines.Add('            end if');
  Lines.Add('            return');
  Lines.Add('          end if');
  Lines.Add('          arg_i = arg_i + 1');
  Lines.Add('          q = p + 1');
  Lines.Add('        end if');
  Lines.Add('      end if');
  Lines.Add('      p = p + 1');
  Lines.Add('    end do');
  Lines.Add('  end function json_extract_arg_raw');
  Lines.Add('');
  Lines.Add('  ! json_arg_to_int64 - convert a raw JSON number (possibly quoted) to int64.');
  Lines.Add('  function json_arg_to_int64(raw, default) result(v)');
  Lines.Add('    character(len=*), intent(in) :: raw');
  Lines.Add('    integer(c_int64_t), intent(in) :: default');
  Lines.Add('    integer(c_int64_t) :: v');
  Lines.Add('    integer :: ios');
  Lines.Add('    character(len=:), allocatable :: tmp');
  Lines.Add('');
  Lines.Add('    v = default');
  Lines.Add('    tmp = trim(adjustl(raw))');
  Lines.Add('    if (len(tmp) == 0) return');
  Lines.Add('    if (tmp(1:1) == ' + FStrLit('"') + ' .and. len(tmp) >= 2 .and. tmp(len(tmp):len(tmp)) == ' + FStrLit('"') + ') then');
  Lines.Add('      tmp = tmp(2:len(tmp)-1)');
  Lines.Add('    end if');
  Lines.Add('    if (len(tmp) == 0) return');
  Lines.Add('    read(tmp, *, iostat=ios) v');
  Lines.Add('    if (ios /= 0) v = default');
  Lines.Add('  end function json_arg_to_int64');
  Lines.Add('');
  Lines.Add('  ! json_arg_to_double - convert a raw JSON number to double.');
  Lines.Add('  function json_arg_to_double(raw, default) result(v)');
  Lines.Add('    character(len=*), intent(in) :: raw');
  Lines.Add('    real(c_double), intent(in) :: default');
  Lines.Add('    real(c_double) :: v');
  Lines.Add('    integer :: ios');
  Lines.Add('    character(len=:), allocatable :: tmp');
  Lines.Add('');
  Lines.Add('    v = default');
  Lines.Add('    tmp = trim(adjustl(raw))');
  Lines.Add('    if (len(tmp) == 0) return');
  Lines.Add('    if (tmp(1:1) == ' + FStrLit('"') + ' .and. len(tmp) >= 2 .and. tmp(len(tmp):len(tmp)) == ' + FStrLit('"') + ') then');
  Lines.Add('      tmp = tmp(2:len(tmp)-1)');
  Lines.Add('    end if');
  Lines.Add('    if (len(tmp) == 0) return');
  Lines.Add('    read(tmp, *, iostat=ios) v');
  Lines.Add('    if (ios /= 0) v = default');
  Lines.Add('  end function json_arg_to_double');
  Lines.Add('');
  Lines.Add('  ! json_arg_to_string - convert a raw JSON string literal to a Fortran string.');
  Lines.Add('  function json_arg_to_string(raw) result(v)');
  Lines.Add('    character(len=*), intent(in) :: raw');
  Lines.Add('    character(len=:), allocatable :: v');
  Lines.Add('    character(len=:), allocatable :: tmp');
  Lines.Add('');
  Lines.Add('    v = ' + FStrLit('') + '');
  Lines.Add('    tmp = trim(adjustl(raw))');
  Lines.Add('    if (len(tmp) == 0) return');
  Lines.Add('    if (tmp(1:1) == ' + FStrLit('"') + ' .and. len(tmp) >= 2 .and. tmp(len(tmp):len(tmp)) == ' + FStrLit('"') + ') then');
  Lines.Add('      v = tmp(2:len(tmp)-1)');
  Lines.Add('    else');
  Lines.Add('      v = tmp');
  Lines.Add('    end if');
  Lines.Add('  end function json_arg_to_string');
  Lines.Add('');
  Lines.Add('  ! json_make_success_i64 - build {"code":0,"result":<value>}.');
  Lines.Add('  function json_make_success_i64(value) result(s)');
  Lines.Add('    integer(c_int64_t), intent(in) :: value');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    character(len=32) :: tmp');
  Lines.Add('    write(tmp, ' + FStrLit('(I0)') + ') value');
  Lines.Add('    s = ' + FStrLit('{"code":0,"result":') + ' // trim(tmp) // ' + FStrLit('}') + '');
  Lines.Add('  end function json_make_success_i64');
  Lines.Add('');
  Lines.Add('  ! json_make_success_double - build {"code":0,"result":<value>}.');
  Lines.Add('  function json_make_success_double(value) result(s)');
  Lines.Add('    real(c_double), intent(in) :: value');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    character(len=64) :: tmp');
  Lines.Add('    write(tmp, ' + FStrLit('(G0)') + ') value');
  Lines.Add('    s = ' + FStrLit('{"code":0,"result":') + ' // trim(tmp) // ' + FStrLit('}') + '');
  Lines.Add('  end function json_make_success_double');
  Lines.Add('');
  Lines.Add('  ! json_make_success_string - build {"code":0,"result":"<value>"}.');
  Lines.Add('  ! NOTE: no escaping; caller must ensure no " or \ in value.');
  Lines.Add('  function json_make_success_string(value) result(s)');
  Lines.Add('    character(len=*), intent(in) :: value');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    s = ' + FStrLit('{"code":0,"result":"') + ' // trim(value) // ' + FStrLit('"}') + '');
  Lines.Add('  end function json_make_success_string');
  Lines.Add('');
  Lines.Add('  ! json_make_success_void - build {"code":0}.');
  Lines.Add('  function json_make_success_void() result(s)');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    s = ' + FStrLit('{"code":0}') + '');
  Lines.Add('  end function json_make_success_void');
  Lines.Add('');
  Lines.Add('  ! json_make_error - build {"code":-1,"error":"<msg>"}.');
  Lines.Add('  ! NOTE: no escaping; caller must ensure no " or \ in msg.');
  Lines.Add('  function json_make_error(msg) result(s)');
  Lines.Add('    character(len=*), intent(in) :: msg');
  Lines.Add('    character(len=:), allocatable :: s');
  Lines.Add('    s = ' + FStrLit('{"code":-1,"error":"') + ' // trim(msg) // ' + FStrLit('"}') + '');
  Lines.Add('  end function json_make_error');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Main service module generator
// ---------------------------------------------------------------------------

function GenerateHTTPServiceFortranCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, CallbackName, StubName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  RetDecl: TP_String;
  HasParams: boolean;
  Description: TP_String;
  ArgName, ExtractCall: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceFortranCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceFortranCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := NormalizedUnit.LowerText + '_http_json_service_mod';
  AppName := NormalizedUnit;

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
    Lines.Add('! ' + NormalizedUnit.Text + '_http_json_service_mod.f90');
    Lines.Add('!');
    Lines.Add('! Auto-generated by http_fortran_abi_service_generator_tool.pas.');
    Lines.Add('! Source model unit: ' + UnitName.Text + '.');
    Lines.Add('! Do not edit by hand unless you know what you are doing.');
    Lines.Add('!');
    Lines.Add('! This module is the SERVICE side of the Fortran HTTP/JSON binding.');
    Lines.Add('! It registers every supported routine as a LingoFuse Call API on the');
    Lines.Add('! given App handle, and exposes one internal_call_<api> stub per');
    Lines.Add('! routine that the user fills in with the real implementation.');
    Lines.Add('!');
    Lines.Add('! The module does NOT listen on any HTTP port. It joins the LingoFuse');
    Lines.Add('! mesh with lf_prepare_client. The actual HTTP listener is bridge.py,');
    Lines.Add('! which is a separate process (see the README).');
    Lines.Add('!');
    Lines.Add('! Dependencies:');
    Lines.Add('!   - iso_c_binding');
    Lines.Add('!   - lf_fortran_mod');
    Lines.Add('!');
    Lines.Add('! Compile with any Fortran 2008 compiler (gfortran, ifort, flang).');
    Lines.Add('! ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('module ' + ModuleName.Text);
    Lines.Add('  use iso_c_binding');
    Lines.Add('  use lf_fortran_mod');
    Lines.Add('  implicit none');
    Lines.Add('  private');
    Lines.Add('');
    Lines.Add('  ! ---- Public API -------------------------------------------------------');
    Lines.Add('');
    Lines.Add('  ! The App name used by this service.');
    Lines.Add('  character(len=*), parameter, public :: HTTP_SERVICE_APP_NAME = ' +
      FStrLit(AppName) + '');
    Lines.Add('');
    Lines.Add('  ! Human-readable description of the service.');
    Lines.Add('  character(len=*), parameter, public :: HTTP_SERVICE_APP_DESC = ' +
      FStrLit('HTTP/JSON service for ' + UnitName) + '');
    Lines.Add('');
    Lines.Add('  ! Enable per-call debug tracing on stderr.');
    Lines.Add('  logical, save, public :: DEBUG_LOG = .false.');
    Lines.Add('');
    Lines.Add('  ! register_all_http_json_apis - register every supported routine');
    Lines.Add('  ! on app. rc is 0 on success, or the number of failed');
    Lines.Add('  ! registrations.');
    Lines.Add('  public :: register_all_http_json_apis');
    Lines.Add('');
    Lines.Add('  ! ---- Per-API stubs (user implements these) ---------------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      StubName := 'internal_call_' + MakeSafeFortranIdent(ApiName, i);
      Lines.Add('  public :: ' + StubName.Text);
    end;
    Lines.Add('');
    Lines.Add('  ! ---- Per-API callbacks (registered automatically) --------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      CallbackName := 'callback_' + MakeSafeFortranIdent(ApiName, i);
      Lines.Add('  public :: ' + CallbackName.Text);
    end;
    Lines.Add('');

    // -------------------------------------------------------------------------
    // JSON helpers
    // -------------------------------------------------------------------------
    EmitJsonHelpers(Lines);

    // -------------------------------------------------------------------------
    // User-implemented stubs
    // -------------------------------------------------------------------------
    Lines.Add('  ! ======================================================================');
    Lines.Add('  ! internal_call stubs - the user fills these in.');
    Lines.Add('  !');
    Lines.Add('  ! Each stub receives already-extracted, typed arguments and returns');
    Lines.Add('  ! the typed result.');
    Lines.Add('  ! ======================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      StubName := 'internal_call_' + MakeSafeFortranIdent(ApiName, i);
      HasParams := Length(F.Params) > 0;

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON api for ' + F.Name;

      Lines.Add('  ! ' + Description.Text);
      if F.IsFunction then
      begin
        RetDecl := ABI_Type_To_Fortran_Return_Decl(F.ReturnType);
        Lines.Add('  function ' + StubName.Text + '(' +
          BuildFortranParamDecl(F.Params) + ') result(res)');
        if HasParams then
        begin
          for j := 0 to High(F.Params) do
            Lines.Add('    ' + ABI_Type_To_Fortran_Param_Decl(F.Params[j].PascalType) +
              ' :: ' + MakeSafeFortranIdent(F.Params[j].Name, j));
        end;
        Lines.Add('    ' + RetDecl.Text + ' :: res');
        Lines.Add('');
        Lines.Add('    ! TODO: replace the body below with a call to the real implementation.');
        if HasParams then
          Lines.Add('    ! Example: res = ' + F.Name + '(' +
            BuildFortranCallArgList(F.Params) + ')')
        else
          Lines.Add('    ! Example: res = ' + F.Name + '()');
        if ABI_Type_Is_String(F.ReturnType) then
          Lines.Add('    res = ' + FStrLit('') + '')
        else if ABI_Type_Is_Float(F.ReturnType) then
          Lines.Add('    res = 0.0d0')
        else
          Lines.Add('    res = 0_c_int64_t');
        Lines.Add('  end function ' + StubName.Text);
      end
      else
      begin
        Lines.Add('  subroutine ' + StubName.Text + '(' +
          BuildFortranParamDecl(F.Params) + ')');
        if HasParams then
        begin
          for j := 0 to High(F.Params) do
            Lines.Add('    ' + ABI_Type_To_Fortran_Param_Decl(F.Params[j].PascalType) +
              ' :: ' + MakeSafeFortranIdent(F.Params[j].Name, j));
        end;
        Lines.Add('');
        Lines.Add('    ! TODO: replace the body below with a call to the real implementation.');
        if HasParams then
          Lines.Add('    ! Example: call ' + F.Name + '(' +
            BuildFortranCallArgList(F.Params) + ')')
        else
          Lines.Add('    ! Example: call ' + F.Name + '()');
        // Reference every parameter so gfortran -Wall does not warn.
        if HasParams then
        begin
          Lines.Add('    if (.false.) then');
          for j := 0 to High(F.Params) do
          begin
            if ABI_Type_Is_String(F.Params[j].PascalType) then
              Lines.Add('      if (len_trim(' +
                MakeSafeFortranIdent(F.Params[j].Name, j) + ') < 0) then')
            else if ABI_Type_Is_Float(F.Params[j].PascalType) then
              Lines.Add('      if (' +
                MakeSafeFortranIdent(F.Params[j].Name, j) + ' < -1.0d300) then')
            else
              Lines.Add('      if (' +
                MakeSafeFortranIdent(F.Params[j].Name, j) + ' < -1_c_int64_t) then');
            Lines.Add('        continue');
            Lines.Add('      end if');
          end;
          Lines.Add('    end if');
        end;
        Lines.Add('  end subroutine ' + StubName.Text);
      end;
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // cdecl callbacks
    // -------------------------------------------------------------------------
    Lines.Add('  ! ======================================================================');
    Lines.Add('  ! callbacks - bind(C) wrappers that translate JSON to typed arguments,');
    Lines.Add('  ! call the internal stub, and write the JSON response back.');
    Lines.Add('  ! ======================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      CallbackName := 'callback_' + MakeSafeFortranIdent(ApiName, i);
      StubName := 'internal_call_' + MakeSafeFortranIdent(ApiName, i);
      HasParams := Length(F.Params) > 0;

      Lines.Add('  subroutine ' + CallbackName.Text + '(input, output) bind(C)');
      Lines.Add('    type(c_ptr), value :: input');
      Lines.Add('    type(c_ptr), value :: output');
      Lines.Add('    character(len=:), allocatable :: req_json, resp_json, raw');
      Lines.Add('    integer(c_int) :: wrc');
      if HasParams then
      begin
        for j := 0 to High(F.Params) do
          Lines.Add('    ' + ABI_Type_To_Fortran_Local_Decl(F.Params[j].PascalType) +
            ' :: ' + MakeSafeFortranIdent(F.Params[j].Name, j));
      end;
      if F.IsFunction then
        Lines.Add('    ' + ABI_Type_To_Fortran_Return_Decl(F.ReturnType) + ' :: res');
      Lines.Add('');
      Lines.Add('    ! Read the UTF-8 JSON request.');
      Lines.Add('    call lf_data_read_string(input, req_json)');
      Lines.Add('');
      Lines.Add('    if (DEBUG_LOG) then');
      Lines.Add('      write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('[' + ApiName + '] request: ') + ' // trim(req_json)');
      Lines.Add('    end if');
      Lines.Add('');

      // Extract each parameter.
      for j := 0 to High(F.Params) do
      begin
        ArgName := MakeSafeFortranIdent(F.Params[j].Name, j);
        ExtractCall := 'json_arg_to_' + ABI_Type_To_Json_Extractor_Suffix(F.Params[j].PascalType);
        Lines.Add('    raw = json_extract_arg_raw(req_json, ' + umlIntToStr(j) + ')');
        if ABI_Type_Is_String(F.Params[j].PascalType) then
          Lines.Add('    ' + ArgName.Text + ' = ' + ExtractCall.Text + '(raw)')
        else if ABI_Type_Is_Float(F.Params[j].PascalType) then
          Lines.Add('    ' + ArgName.Text + ' = ' + ExtractCall.Text + '(raw, 0.0d0)')
        else
          Lines.Add('    ' + ArgName.Text + ' = ' + ExtractCall.Text + '(raw, 0_c_int64_t)');
        Lines.Add('');
      end;

      // Call the internal stub.
      Lines.Add('    ! Invoke the user-implemented stub.');
      if F.IsFunction then
        Lines.Add('    res = ' + StubName.Text + '(' +
          BuildFortranCallArgList(F.Params) + ')')
      else
        Lines.Add('    call ' + StubName.Text + '(' +
          BuildFortranCallArgList(F.Params) + ')');
      Lines.Add('');

      // Build the response.
      if F.IsFunction then
      begin
        if ABI_Type_Is_String(F.ReturnType) then
          Lines.Add('    resp_json = json_make_success_string(res)')
        else if ABI_Type_Is_Float(F.ReturnType) then
          Lines.Add('    resp_json = json_make_success_double(res)')
        else
          Lines.Add('    resp_json = json_make_success_i64(res)');
      end
      else
        Lines.Add('    resp_json = json_make_success_void()');

      Lines.Add('');
      Lines.Add('    if (DEBUG_LOG) then');
      Lines.Add('      write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('[' + ApiName + '] response: ') + ' // trim(resp_json)');
      Lines.Add('    end if');
      Lines.Add('');
      Lines.Add('    wrc = lf_data_write_string(output, resp_json)');
      Lines.Add('  end subroutine ' + CallbackName.Text);
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------
    Lines.Add('  ! ======================================================================');
    Lines.Add('  ! Registration entry point.');
    Lines.Add('  !');
    Lines.Add('  ! Call this once, on the main thread, AFTER the App has been created');
    Lines.Add('  ! but BEFORE lf_prepare_client. rc is 0 on success, or the number of');
    Lines.Add('  ! failed registrations.');
    Lines.Add('  ! ======================================================================');
    Lines.Add('');
    Lines.Add('  subroutine register_all_http_json_apis(app, rc)');
    Lines.Add('    type(c_ptr), value :: app');
    Lines.Add('    integer(c_int), intent(out) :: rc');
    Lines.Add('    integer(c_int) :: tmp');
    Lines.Add('');
    Lines.Add('    rc = 0_c_int');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      CallbackName := 'callback_' + MakeSafeFortranIdent(ApiName, i);
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON api for ' + F.Name;

      Lines.Add('    tmp = lf_app_register_call(app, ' +
        FStrLit(ApiName) + ', ' + FStrLit(Description) + ', &');
      Lines.Add('                               c_funloc(' + CallbackName.Text + '))');
      Lines.Add('    if (tmp /= 1_c_int) then');
      Lines.Add('      if (DEBUG_LOG) write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('register ' + ApiName + ' failed') + '');
      Lines.Add('      rc = rc + 1_c_int');
      Lines.Add('    else');
      Lines.Add('      if (DEBUG_LOG) write(*, ' + FStrLit('(A)') + ') ' +
        FStrLit('[register] ' + ApiName + ' OK') + '');
      Lines.Add('    end if');
      Lines.Add('');
    end;

    Lines.Add('    if (DEBUG_LOG) write(*, ' + FStrLit('(A)') + ') ' +
      FStrLit('[register] total APIs: ' + umlIntToStr(Length(SupportedFuncs))) + '');
    Lines.Add('  end subroutine register_all_http_json_apis');
    Lines.Add('');
    Lines.Add('end module ' + ModuleName.Text);

    Result := Lines;
    Log(PFormat('Generated Fortran service module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'fortran', 'Fortran HTTP/JSON service module',
    asService, akServiceCode,
    '_http_json_service_mod.f90', False,
    @GenerateHTTPServiceFortranCode);
end.
