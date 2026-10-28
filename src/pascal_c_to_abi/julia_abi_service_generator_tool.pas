unit julia_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceJuliaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Julia_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'Int32'
  else if T.Same('int64') then Result := 'Int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'UInt32'
  else if T.Same('word') then Result := 'UInt16'
  else if T.Same('smallint') then Result := 'Int16'
  else if T.Same('byte') then Result := 'UInt8'
  else if T.Same('uint64') then Result := 'UInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'Float64'
  else if T.Same('single') then Result := 'Float32'
  else if IsStringABIType(T) then Result := 'String'
  else Result := '';
end;

function ABI_Type_To_Julia_Reader(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := '_read_int32_le!'
  else if T.Same('int64') then Result := '_read_int64_le!'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := '_read_uint32_le!'
  else if T.Same('word') then Result := '_read_uint16_le!'
  else if T.Same('smallint') then Result := '_read_int16_le!'
  else if T.Same('byte') then Result := '_read_uint8_le!'
  else if T.Same('uint64') then Result := '_read_uint64_le!'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := '_read_float64_le!'
  else if T.Same('single') then Result := '_read_float32_le!'
  else if IsStringABIType(T) then Result := '_read_string_nul!'
  else Result := '';
end;

function ABI_Type_To_Julia_Writer(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := '_write_int32_le!'
  else if T.Same('int64') then Result := '_write_int64_le!'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := '_write_uint32_le!'
  else if T.Same('word') then Result := '_write_uint16_le!'
  else if T.Same('smallint') then Result := '_write_int16_le!'
  else if T.Same('byte') then Result := '_write_uint8_le!'
  else if T.Same('uint64') then Result := '_write_uint64_le!'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := '_write_float64_le!'
  else if T.Same('single') then Result := '_write_float32_le!'
  else if IsStringABIType(T) then Result := '_write_string_nul!'
  else Result := '';
end;

function ABI_Type_Julia_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then Result := '""'
  else if T.Same('single') then Result := 'Float32(0.0)'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'Float64(0.0)'
  else if T.Same('byte') then Result := 'UInt8(0)'
  else if T.Same('word') then Result := 'UInt16(0)'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'UInt32(0)'
  else if T.Same('uint64') then Result := 'UInt64(0)'
  else if T.Same('smallint') then Result := 'Int16(0)'
  else if T.Same('integer') or T.Same('longint') then Result := 'Int32(0)'
  else if T.Same('int64') then Result := 'Int64(0)'
  else Result := 'nothing';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Julia_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function JuliaStrLit(const S: TP_String): TP_String;
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
    else
      Result.Append(c);
  end;
  Result.Append('"');
end;

function IsJuliaKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('baremodule') or S.Same('begin') or S.Same('break') or
    S.Same('catch') or S.Same('const') or S.Same('continue') or
    S.Same('do') or S.Same('else') or S.Same('elseif') or S.Same('end') or
    S.Same('export') or S.Same('false') or S.Same('finally') or S.Same('for') or
    S.Same('function') or S.Same('global') or S.Same('if') or S.Same('import') or
    S.Same('in') or S.Same('let') or S.Same('local') or S.Same('macro') or
    S.Same('module') or S.Same('quote') or S.Same('return') or S.Same('struct') or
    S.Same('true') or S.Same('try') or S.Same('using') or S.Same('while') or
    S.Same('mutable') or S.Same('primitive') or S.Same('abstract') or
    S.Same('type') or S.Same('where') or S.Same('isa') or S.Same('outer');
end;

function MakeSafeJuliaParamName(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'p' + IntToStr(Index);
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

  if IsJuliaKeyword(Result) then
    Result := Result + '_';
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
      Line := StripCommentMarkers(Comment.GetString(i, j));
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

procedure AssignUniqueApiNames(const Funcs: TArryFunctionStructure; Names: TPascalStringList);
var
  i, j: integer;
  N: TP_String;
begin
  Names.Clear;
  for i := 0 to High(Funcs) do
  begin
    N := MakeApiName(Funcs[i].Name);
    if Names.IndexOf(N) >= 0 then
    begin
      j := 1;
      while Names.IndexOf(N + '_' + IntToStr(j)) >= 0 do
        Inc(j);
      N := N + '_' + IntToStr(j);
    end;
    Names.Add(N);
  end;
end;

function BuildParamDeclTyped(const Params: TParamArray): TP_String;
var
  i: integer;
  n, t: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaParamName(Params[i].Name, i);
    t := ABI_Type_To_Julia_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + '::' + t;
  end;
end;

function BuildArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaParamName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildParamDeclTypedWithIdentity(const Params: TParamArray): TP_String;
var
  UserParams: TP_String;
begin
  UserParams := BuildParamDeclTyped(Params);
  if UserParams = '' then
    Result := '_lf_uid::NTuple{32, UInt8}, _lf_p2p_name::String'
  else
    Result := '_lf_uid::NTuple{32, UInt8}, _lf_p2p_name::String, ' + UserParams;
end;

function BuildArgListWithIdentity(const Params: TParamArray): TP_String;
var
  UserArgs: TP_String;
begin
  UserArgs := BuildArgList(Params);
  if UserArgs = '' then
    Result := '_lf_uid, _lf_p2p_name'
  else
    Result := '_lf_uid, _lf_p2p_name, ' + UserArgs;
end;

procedure EmitReadWriteHelpers(Lines: TPascalStringList);
begin
  Lines.Add('mutable struct _ParamReader');
  Lines.Add('    buf::Vector{UInt8}');
  Lines.Add('    pos::Int');
  Lines.Add('    _ParamReader(buf::Vector{UInt8}) = new(buf, 1)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _pr_ensure!(r::_ParamReader, n::Int)');
  Lines.Add('    if r.pos + n - 1 > length(r.buf)');
  Lines.Add('        throw(ArgumentError("truncated input: need $n bytes at pos $(r.pos)"))');
  Lines.Add('    end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_uint8_le!(r::_ParamReader)::UInt8');
  Lines.Add('    _pr_ensure!(r, 1)');
  Lines.Add('    v = @inbounds r.buf[r.pos]');
  Lines.Add('    r.pos += 1');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_uint16_le!(r::_ParamReader)::UInt16');
  Lines.Add('    _pr_ensure!(r, 2)');
  Lines.Add('    v = UInt16(@inbounds r.buf[r.pos]) | (UInt16(@inbounds r.buf[r.pos + 1]) << 8)');
  Lines.Add('    r.pos += 2');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_int16_le!(r::_ParamReader)::Int16');
  Lines.Add('    return reinterpret(Int16, _read_uint16_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_uint32_le!(r::_ParamReader)::UInt32');
  Lines.Add('    _pr_ensure!(r, 4)');
  Lines.Add('    v = UInt32(@inbounds r.buf[r.pos]) |');
  Lines.Add('        (UInt32(@inbounds r.buf[r.pos + 1]) << 8) |');
  Lines.Add('        (UInt32(@inbounds r.buf[r.pos + 2]) << 16) |');
  Lines.Add('        (UInt32(@inbounds r.buf[r.pos + 3]) << 24)');
  Lines.Add('    r.pos += 4');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_int32_le!(r::_ParamReader)::Int32');
  Lines.Add('    return reinterpret(Int32, _read_uint32_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_uint64_le!(r::_ParamReader)::UInt64');
  Lines.Add('    _pr_ensure!(r, 8)');
  Lines.Add('    v = UInt64(0)');
  Lines.Add('    @inbounds for i in 0:7');
  Lines.Add('        v |= UInt64(r.buf[r.pos + i]) << (8 * i)');
  Lines.Add('    end');
  Lines.Add('    r.pos += 8');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_int64_le!(r::_ParamReader)::Int64');
  Lines.Add('    return reinterpret(Int64, _read_uint64_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_float32_le!(r::_ParamReader)::Float32');
  Lines.Add('    return reinterpret(Float32, _read_uint32_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _read_float64_le!(r::_ParamReader)::Float64');
  Lines.Add('    return reinterpret(Float64, _read_uint64_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_string_nul!(r::_ParamReader)::String');
  Lines.Add('    start = r.pos');
  Lines.Add('    @inbounds while r.pos <= length(r.buf) && r.buf[r.pos] != UInt8(0x00)');
  Lines.Add('        r.pos += 1');
  Lines.Add('    end');
  Lines.Add('    if r.pos > length(r.buf)');
  Lines.Add('        throw(ArgumentError("truncated string: no NUL terminator"))');
  Lines.Add('    end');
  Lines.Add('    s = String(r.buf[start:r.pos - 1])');
  Lines.Add('    r.pos += 1');
  Lines.Add('    return s');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_uint8_le!(io::IOBuffer, v::UInt8)');
  Lines.Add('    write(io, v)');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_uint16_le!(io::IOBuffer, v::UInt16)');
  Lines.Add('    write(io, UInt8(v & 0xFF))');
  Lines.Add('    write(io, UInt8((v >> 8) & 0xFF))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_int16_le!(io::IOBuffer, v::Int16)');
  Lines.Add('    _write_uint16_le!(io, reinterpret(UInt16, v))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_uint32_le!(io::IOBuffer, v::UInt32)');
  Lines.Add('    write(io, UInt8(v & 0xFF))');
  Lines.Add('    write(io, UInt8((v >> 8) & 0xFF))');
  Lines.Add('    write(io, UInt8((v >> 16) & 0xFF))');
  Lines.Add('    write(io, UInt8((v >> 24) & 0xFF))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_int32_le!(io::IOBuffer, v::Int32)');
  Lines.Add('    _write_uint32_le!(io, reinterpret(UInt32, v))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_uint64_le!(io::IOBuffer, v::UInt64)');
  Lines.Add('    @inbounds for i in 0:7');
  Lines.Add('        write(io, UInt8((v >> (8 * i)) & 0xFF))');
  Lines.Add('    end');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_int64_le!(io::IOBuffer, v::Int64)');
  Lines.Add('    _write_uint64_le!(io, reinterpret(UInt64, v))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_float32_le!(io::IOBuffer, v::Float32)');
  Lines.Add('    _write_uint32_le!(io, reinterpret(UInt32, v))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('@inline function _write_float64_le!(io::IOBuffer, v::Float64)');
  Lines.Add('    _write_uint64_le!(io, reinterpret(UInt64, v))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _write_string_nul!(io::IOBuffer, v::String)');
  Lines.Add('    write(io, codeunits(v))');
  Lines.Add('    write(io, UInt8(0x00))');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _format_exception(e)::String');
  Lines.Add('    if e isa ArgumentError');
  Lines.Add('        return e.msg');
  Lines.Add('    elseif e isa ErrorException');
  Lines.Add('        return e.msg');
  Lines.Add('    else');
  Lines.Add('        return string(e)');
  Lines.Add('    end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_current_uid()::NTuple{32, UInt8}');
  Lines.Add('    v = LF.current_input_uid()');
  Lines.Add('    if v === nothing');
  Lines.Add('        return LF.zero_uid()');
  Lines.Add('    end');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_current_p2p()::String');
  Lines.Add('    v = LF.current_input_p2p_name()');
  Lines.Add('    if v === nothing');
  Lines.Add('        return ""');
  Lines.Add('    end');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitUserStub(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, ArgList, RetDecl, DefaultExpr: TP_String;
begin
  ParamDecl := BuildParamDeclTypedWithIdentity(F.Params);
  ArgList := BuildArgListWithIdentity(F.Params);

  if F.IsFunction then
  begin
    RetDecl := ABI_Type_To_Julia_Decl(F.ReturnType);
    DefaultExpr := ABI_Type_Julia_Default(F.ReturnType);
    Lines.Add('function _internal_call_' + ApiName + '_default(' + ParamDecl + ')::' + RetDecl);
    Lines.Add('    return ' + DefaultExpr);
    Lines.Add('end');
    Lines.Add('const internal_call_' + ApiName + '_impl = Ref{Function}(_internal_call_' + ApiName + '_default)');
    Lines.Add('');
    Lines.Add('function internal_call_' + ApiName + '(' + ParamDecl + ')::' + RetDecl);
    Lines.Add('    return internal_call_' + ApiName + '_impl[](' + ArgList + ')');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('function set_internal_call_' + ApiName + '!(f::Function)');
    Lines.Add('    internal_call_' + ApiName + '_impl[] = f');
    Lines.Add('    return nothing');
    Lines.Add('end');
  end
  else
  begin
    Lines.Add('function _internal_call_' + ApiName + '_default(' + ParamDecl + ')::Nothing');
    Lines.Add('    return nothing');
    Lines.Add('end');
    Lines.Add('const internal_call_' + ApiName + '_impl = Ref{Function}(_internal_call_' + ApiName + '_default)');
    Lines.Add('');
    Lines.Add('function internal_call_' + ApiName + '(' + ParamDecl + ')::Nothing');
    Lines.Add('    return internal_call_' + ApiName + '_impl[](' + ArgList + ')');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('function set_internal_call_' + ApiName + '!(f::Function)');
    Lines.Add('    internal_call_' + ApiName + '_impl[] = f');
    Lines.Add('    return nothing');
    Lines.Add('end');
  end;

  Lines.Add('');
end;

procedure EmitCallbackImpl(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, Reader, Writer, ArgList: TP_String;
begin
  Lines.Add('function callback_' + ApiName + '(in_bytes::Vector{UInt8})::Vector{UInt8}');
  Lines.Add('    out = IOBuffer()');
  Lines.Add('    try');
  Lines.Add('        r = _ParamReader(in_bytes)');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJuliaParamName(F.Params[i].Name, i);
    Reader := ABI_Type_To_Julia_Reader(F.Params[i].PascalType);
    Lines.Add('        ' + PName + ' = ' + Reader + '(r)');
  end;
  Lines.Add('        _lf_uid = _read_current_uid()');
  Lines.Add('        _lf_p2p_name = _read_current_p2p()');
  ArgList := BuildArgListWithIdentity(F.Params);
  Lines.Add('        _ret = internal_call_' + ApiName + '(' + ArgList + ')');
  Lines.Add('        write(out, STATUS_OK)');
  Writer := ABI_Type_To_Julia_Writer(F.ReturnType);
  Lines.Add('        ' + Writer + '(out, _ret)');
  Lines.Add('    catch e');
  Lines.Add('        empty!(out)');
  Lines.Add('        write(out, STATUS_ERROR)');
  Lines.Add('        _write_string_nul!(out, _format_exception(e))');
  Lines.Add('    end');
  Lines.Add('    return take!(out)');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitNotifyCallbackImpl(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  i: integer;
  PName, Reader, ArgList: TP_String;
begin
  Lines.Add('function callback_' + ApiName + '(in_bytes::Vector{UInt8})::Nothing');
  Lines.Add('    try');
  Lines.Add('        r = _ParamReader(in_bytes)');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeJuliaParamName(F.Params[i].Name, i);
    Reader := ABI_Type_To_Julia_Reader(F.Params[i].PascalType);
    Lines.Add('        ' + PName + ' = ' + Reader + '(r)');
  end;
  Lines.Add('        _lf_uid = _read_current_uid()');
  Lines.Add('        _lf_p2p_name = _read_current_p2p()');
  ArgList := BuildArgListWithIdentity(F.Params);
  Lines.Add('        internal_call_' + ApiName + '(' + ArgList + ')');
  Lines.Add('    catch e');
  Lines.Add('        @warn "notify ' + ApiName + ' handler failed" exception=e');
  Lines.Add('    end');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitTestHelperCallbacks(Lines: TPascalStringList);
begin
  Lines.Add('function callback___lf_whoami(in_bytes::Vector{UInt8})::Vector{UInt8}');
  Lines.Add('    out = IOBuffer()');
  Lines.Add('    try');
  Lines.Add('        _lf_uid = _read_current_uid()');
  Lines.Add('        _lf_p2p = _read_current_p2p()');
  Lines.Add('        write(out, STATUS_OK)');
  Lines.Add('        write(out, collect(UInt8, _lf_uid))');
  Lines.Add('        _write_string_nul!(out, _lf_p2p)');
  Lines.Add('    catch e');
  Lines.Add('        empty!(out)');
  Lines.Add('        write(out, STATUS_ERROR)');
  Lines.Add('        _write_string_nul!(out, _format_exception(e))');
  Lines.Add('    end');
  Lines.Add('    return take!(out)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function callback__LF_TEST_WHOAMI(in_bytes::Vector{UInt8})::Vector{UInt8}');
  Lines.Add('    return callback___lf_whoami(in_bytes)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function callback__LF_TEST_ASK_SERVICE_CALL_ME(in_bytes::Vector{UInt8})::Nothing');
  Lines.Add('    try');
  Lines.Add('        client_uid = _read_current_uid()');
  Lines.Add('        if client_uid == LF.zero_uid()');
  Lines.Add('            println("[WARN] LF_TEST_ASK_SERVICE_CALL_ME: no sender UID; skipping service-initiated call")');
  Lines.Add('            return nothing');
  Lines.Add('        end');
  Lines.Add('        Threads.@spawn begin');
  Lines.Add('            try');
  Lines.Add('                LF.call(LF.uid_target(client_uid; timeout_ms = 5000),');
  Lines.Add('                        "LF_TEST_REPORT_SERVICE_IDENTITY",');
  Lines.Add('                        (dh) -> LF.write_string!(dh, "service initiates call"))');
  Lines.Add('            catch e');
  Lines.Add('                println("[WARN] service-initiated call to client failed: ", e)');
  Lines.Add('            end');
  Lines.Add('        end');
  Lines.Add('    catch e');
  Lines.Add('        @warn "LF_TEST_ASK_SERVICE_CALL_ME handler failed" exception=e');
  Lines.Add('    end');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
end;

function GenerateABIServiceJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc: TP_String;
  ApiNames: TPascalStringList;
  Description: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceJuliaCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceJuliaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi_service';
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Julia ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty module.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    AssignUniqueApiNames(SupportedFuncs, ApiNames);

    Lines.Add('module ' + NsName);
    Lines.Add('');
    Lines.Add('import LingoFuse');
    Lines.Add('const LF = LingoFuse');
    Lines.Add('');
    Lines.Add('const STATUS_OK    = UInt8(0x00)');
    Lines.Add('const STATUS_ERROR = UInt8(0xFF)');
    Lines.Add('');
    Lines.Add('const DEFAULT_APP_NAME = ' + JuliaStrLit(AppName));
    Lines.Add('const DEFAULT_APP_DESC = ' + JuliaStrLit(AppDesc));
    Lines.Add('');

    EmitReadWriteHelpers(Lines);

    for i := 0 to High(SupportedFuncs) do
      EmitUserStub(Lines, ApiNames[i], SupportedFuncs[i]);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        EmitCallbackImpl(Lines, ApiNames[i], F)
      else
        EmitNotifyCallbackImpl(Lines, ApiNames[i], F);
    end;

    EmitTestHelperCallbacks(Lines);

    Lines.Add('function register_all_abi_apis!(app::LF.App)');
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;
      if F.IsFunction then
        Lines.Add('    LF.register_call!(app, ' + JuliaStrLit(ApiNames[i]) + ', ' +
          JuliaStrLit(Description) + ', callback_' + ApiNames[i].Text + '; warmup=false)')
      else
        Lines.Add('    LF.register_notify!(app, ' + JuliaStrLit(ApiNames[i]) + ', ' +
          JuliaStrLit(Description) + ', callback_' + ApiNames[i].Text + '; warmup=false)');
    end;
    Lines.Add('    LF.register_call!(app, "__lf_whoami", "Internal: probe caller identity", callback___lf_whoami; warmup=false)');
    Lines.Add('    LF.register_call!(app, "LF_TEST_WHOAMI", "service-side whoami helper", callback__LF_TEST_WHOAMI; warmup=false)');
    Lines.Add('    LF.register_notify!(app, "LF_TEST_ASK_SERVICE_CALL_ME", "ask service to call back client", callback__LF_TEST_ASK_SERVICE_CALL_ME; warmup=false)');
    Lines.Add('    return nothing');
    Lines.Add('end');
    Lines.Add('');

    Lines.Add('function register_all_p2p_abi_apis!()');
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;
      if F.IsFunction then
        Lines.Add('    LF.register_p2p_call!(' + JuliaStrLit(ApiNames[i]) + ', ' +
          JuliaStrLit(Description) + ', callback_' + ApiNames[i].Text + '; warmup=false)')
      else
        Lines.Add('    LF.register_p2p_notify!(' + JuliaStrLit(ApiNames[i]) + ', ' +
          JuliaStrLit(Description) + ', callback_' + ApiNames[i].Text + '; warmup=false)');
    end;
    Lines.Add('    return nothing');
    Lines.Add('end');
    Lines.Add('');

    Lines.Add('function create_and_register_abi_app()::LF.App');
    Lines.Add('    app = LF.App(DEFAULT_APP_NAME, DEFAULT_APP_DESC)');
    Lines.Add('    register_all_abi_apis!(app)');
    Lines.Add('    return app');
    Lines.Add('end');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      Lines.Add('export set_internal_call_' + ApiNames[i] + '!');
      Lines.Add('export internal_call_' + ApiNames[i]);
    end;
    Lines.Add('export register_all_abi_apis!');
    Lines.Add('export register_all_p2p_abi_apis!');
    Lines.Add('export create_and_register_abi_app');
    Lines.Add('export DEFAULT_APP_NAME');
    Lines.Add('export DEFAULT_APP_DESC');
    Lines.Add('');
    Lines.Add('end');
    Lines.Add('');

    Result := Lines;
    Lines := nil;
    Log(PFormat('Generated %d lines, %d routines.', [Result.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Lines <> nil then
      Lines.Free;
  end;
end;

initialization

  RegisterGenerator(
    'julia',
    'xxx_abi_service.jl',
    gkService,
    'Julia ABI service module',
    @GenerateABIServiceJuliaCode);

end.
