unit julia_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallJuliaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Julia_Param_Type(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'AbstractString'
  else if T.Same('double') or T.Same('extended') or T.Same('real') or T.Same('single') then
    Result := 'Real'
  else if T.Same('integer') or T.Same('longint') or T.Same('int64') or
          T.Same('cardinal') or T.Same('dword') or T.Same('longword') or
          T.Same('word') or T.Same('smallint') or T.Same('byte') or
          T.Same('uint64') then
    Result := 'Integer'
  else
    Result := '';
end;

function ABI_Type_To_Julia_Convert_Expr(const T: TP_String; const VarExpr: TP_String): TP_String;
begin
  if IsStringABIType(T) then Result := 'String(' + VarExpr + ')'
  else if T.Same('integer') or T.Same('longint') then Result := 'Int32(' + VarExpr + ')'
  else if T.Same('int64') then Result := 'Int64(' + VarExpr + ')'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'UInt32(' + VarExpr + ')'
  else if T.Same('word') then Result := 'UInt16(' + VarExpr + ')'
  else if T.Same('smallint') then Result := 'Int16(' + VarExpr + ')'
  else if T.Same('byte') then Result := 'UInt8(' + VarExpr + ')'
  else if T.Same('uint64') then Result := 'UInt64(' + VarExpr + ')'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'Float64(' + VarExpr + ')'
  else if T.Same('single') then Result := 'Float32(' + VarExpr + ')'
  else Result := VarExpr;
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

function ABI_Type_To_Julia_Write_Fn(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'write_int32!'
  else if T.Same('int64') then Result := 'write_int64!'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'write_uint32!'
  else if T.Same('word') then Result := 'write_uint16!'
  else if T.Same('smallint') then Result := 'write_int16!'
  else if T.Same('byte') then Result := 'write_uint8!'
  else if T.Same('uint64') then Result := 'write_uint64!'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'write_double!'
  else if T.Same('single') then Result := 'write_single!'
  else if IsStringABIType(T) then Result := 'write_string!'
  else Result := '';
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

function _join_params(const Leading, Params: TP_String): TP_String;
begin
  if Leading = '' then
    Result := Params
  else if Params = '' then
    Result := Leading
  else
    Result := Leading + ', ' + Params;
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
        Log(PFormat('Skipped "%s": parameter "%s" unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" unsupported', [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: empty Name');
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
    t := ABI_Type_To_Julia_Param_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + '::' + t;
  end;
end;

function BuildPayloadClosure(const Params: TParamArray): TP_String;
var
  i: integer;
  n, w, conv: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := 'nothing';
    Exit;
  end;

  Result := '(dh) -> begin';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaParamName(Params[i].Name, i);
    w := ABI_Type_To_Julia_Write_Fn(Params[i].PascalType);
    conv := ABI_Type_To_Julia_Convert_Expr(Params[i].PascalType, n);
    Result := Result + ' LF.' + w.Text + '(dh, ' + conv.Text + ');';
  end;
  Result := Result + ' end';
end;

procedure EmitExceptionType(Lines: TPascalStringList);
begin
  Lines.Add('struct EABI_RemoteError <: Exception');
  Lines.Add('    msg::String');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('Base.showerror(io::IO, e::EABI_RemoteError) = print(io, "EABI_RemoteError: ", e.msg)');
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
end;

procedure EmitReaders(Lines: TPascalStringList);
begin
  Lines.Add('mutable struct _ParamReader');
  Lines.Add('    buf::Vector{UInt8}');
  Lines.Add('    pos::Int');
  Lines.Add('    _ParamReader(buf::Vector{UInt8}) = new(buf, 1)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _pr_ensure!(r::_ParamReader, n::Int)');
  Lines.Add('    if r.pos + n - 1 > length(r.buf)');
  Lines.Add('        throw(ArgumentError(string("truncated input: need ", n, " bytes at pos ", r.pos)))');
  Lines.Add('    end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_uint8_le!(r::_ParamReader)::UInt8');
  Lines.Add('    _pr_ensure!(r, 1)');
  Lines.Add('    v = r.buf[r.pos]');
  Lines.Add('    r.pos += 1');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_uint16_le!(r::_ParamReader)::UInt16');
  Lines.Add('    _pr_ensure!(r, 2)');
  Lines.Add('    v = UInt16(r.buf[r.pos]) | (UInt16(r.buf[r.pos + 1]) << 8)');
  Lines.Add('    r.pos += 2');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_int16_le!(r::_ParamReader)::Int16');
  Lines.Add('    return reinterpret(Int16, _read_uint16_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_uint32_le!(r::_ParamReader)::UInt32');
  Lines.Add('    _pr_ensure!(r, 4)');
  Lines.Add('    v = UInt32(r.buf[r.pos]) |');
  Lines.Add('        (UInt32(r.buf[r.pos + 1]) << 8) |');
  Lines.Add('        (UInt32(r.buf[r.pos + 2]) << 16) |');
  Lines.Add('        (UInt32(r.buf[r.pos + 3]) << 24)');
  Lines.Add('    r.pos += 4');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_int32_le!(r::_ParamReader)::Int32');
  Lines.Add('    return reinterpret(Int32, _read_uint32_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_uint64_le!(r::_ParamReader)::UInt64');
  Lines.Add('    _pr_ensure!(r, 8)');
  Lines.Add('    v = UInt64(0)');
  Lines.Add('    for i in 0:7');
  Lines.Add('        v |= UInt64(r.buf[r.pos + i]) << (8 * i)');
  Lines.Add('    end');
  Lines.Add('    r.pos += 8');
  Lines.Add('    return v');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_int64_le!(r::_ParamReader)::Int64');
  Lines.Add('    return reinterpret(Int64, _read_uint64_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_float32_le!(r::_ParamReader)::Float32');
  Lines.Add('    return reinterpret(Float32, _read_uint32_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_float64_le!(r::_ParamReader)::Float64');
  Lines.Add('    return reinterpret(Float64, _read_uint64_le!(r))');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _read_string_nul!(r::_ParamReader)::String');
  Lines.Add('    start = r.pos');
  Lines.Add('    while r.pos <= length(r.buf) && r.buf[r.pos] != UInt8(0x00)');
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
end;

procedure EmitCheckResponse(Lines: TPascalStringList);
begin
  Lines.Add('function _check_response(res::Vector{UInt8}, api_name::String)::_ParamReader');
  Lines.Add('    if isempty(res)');
  Lines.Add('        throw(EABI_RemoteError(string("ABI call ", api_name, " returned empty response")))');
  Lines.Add('    end');
  Lines.Add('    status = res[1]');
  Lines.Add('    if status != UInt8(0x00)');
  Lines.Add('        start = 2');
  Lines.Add('        stop = start');
  Lines.Add('        while stop <= length(res) && res[stop] != UInt8(0x00)');
  Lines.Add('            stop += 1');
  Lines.Add('        end');
  Lines.Add('        local err::String');
  Lines.Add('        if stop - 1 >= start');
  Lines.Add('            err = String(res[start:stop - 1])');
  Lines.Add('        else');
  Lines.Add('            err = ""');
  Lines.Add('        end');
  Lines.Add('        throw(EABI_RemoteError(string("ABI call ", api_name, " failed: ", err)))');
  Lines.Add('    end');
  Lines.Add('    r = _ParamReader(res)');
  Lines.Add('    r.pos = 2');
  Lines.Add('    return r');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitSyncWrapper(Lines: TPascalStringList;
  const FuncName, FullParams, TargetExpr, ApiName: TP_String;
  const F: TFunctionStructure; const Payload: TP_String);
var
  ReadFn, RetType: TP_String;
begin
  RetType := ABI_Type_To_Julia_Decl(F.ReturnType);
  ReadFn := ABI_Type_To_Julia_Reader(F.ReturnType);

  Lines.Add('function ' + FuncName.Text + '(' + FullParams.Text + ')::' + RetType.Text);
  Lines.Add('    local raw');
  Lines.Add('    try');
  Lines.Add('        raw = LF.call(' + TargetExpr.Text + ', ' + JuliaStrLit(ApiName).Text + ', ' + Payload.Text + ')');
  Lines.Add('    catch e');
  Lines.Add('        if e isa LF.LingoFuseTimeoutError');
  Lines.Add('            throw(EABI_RemoteError(string("ABI call ", ' + JuliaStrLit(ApiName).Text + ', " timed out: ", string(e))))');
  Lines.Add('        else');
  Lines.Add('            throw(EABI_RemoteError(string("ABI call ", ' + JuliaStrLit(ApiName).Text + ', " dispatch failed: ", _format_exception(e))))');
  Lines.Add('        end');
  Lines.Add('    end');
  Lines.Add('    r = _check_response(raw, ' + JuliaStrLit(ApiName).Text + ')');
  Lines.Add('    return ' + ReadFn.Text + '(r)');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitAsyncInnerCB(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Indent: string);
var
  ReadFn: TP_String;
begin
  ReadFn := ABI_Type_To_Julia_Reader(F.ReturnType);
  Lines.Add(Indent + '__lf_inner_cb = function (res_bytes, err)');
  Lines.Add(Indent + '    if err !== nothing');
  Lines.Add(Indent + '        local __lf_eabierr');
  Lines.Add(Indent + '        if err isa LF.LingoFuseTimeoutError');
  Lines.Add(Indent + '            __lf_eabierr = EABI_RemoteError(string("ABI call ", ' + JuliaStrLit(ApiName).Text + ', " timed out: ", string(err)))');
  Lines.Add(Indent + '        else');
  Lines.Add(Indent + '            __lf_eabierr = EABI_RemoteError(string("ABI call ", ' + JuliaStrLit(ApiName).Text + ', " async failed: ", _format_exception(err)))');
  Lines.Add(Indent + '        end');
  Lines.Add(Indent + '        try __lf_cb(nothing, __lf_eabierr) catch; end');
  Lines.Add(Indent + '        return');
  Lines.Add(Indent + '    end');
  Lines.Add(Indent + '    try');
  Lines.Add(Indent + '        r = _check_response(res_bytes, ' + JuliaStrLit(ApiName).Text + ')');
  Lines.Add(Indent + '        parsed = ' + ReadFn.Text + '(r)');
  Lines.Add(Indent + '        try __lf_cb(parsed, nothing) catch; end');
  Lines.Add(Indent + '    catch e');
  Lines.Add(Indent + '        try __lf_cb(nothing, e) catch; end');
  Lines.Add(Indent + '    end');
  Lines.Add(Indent + 'end');
end;

procedure EmitAsyncWrapper(Lines: TPascalStringList;
  const FuncName, FullParams, AsyncCallFn, TargetExpr, ApiName: TP_String;
  const F: TFunctionStructure; const Payload: TP_String);
begin
  Lines.Add('function ' + FuncName.Text + '(' + FullParams.Text + ')::LF.Future');
  EmitAsyncInnerCB(Lines, ApiName, F, '    ');
  Lines.Add('    return LF.' + AsyncCallFn.Text + '(__lf_inner_cb, ' + TargetExpr.Text + ', ' + JuliaStrLit(ApiName).Text + ', ' + Payload.Text + ')');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitNotifyWrapper(Lines: TPascalStringList;
  const FuncName, FullParams, NotifyFn, TargetExpr, ApiName: TP_String;
  const F: TFunctionStructure; const Payload: TP_String);
begin
  Lines.Add('function ' + FuncName.Text + '(' + FullParams.Text + ')::Nothing');
  Lines.Add('    LF.' + NotifyFn.Text + '(' + TargetExpr.Text + ', ' + JuliaStrLit(ApiName).Text + ', ' + Payload.Text + ')');
  Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
end;

procedure EmitFunctionWrappers(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, Payload, CBParam, UIDParam, P2PParam, UIDAndParams: TP_String;
begin
  ParamDecl := BuildParamDeclTyped(F.Params);
  Payload := BuildPayloadClosure(F.Params);
  CBParam := '__lf_cb::Function';
  UIDParam := '__lf_uid::LF.LFShimUID';
  P2PParam := '__lf_p2p::AbstractString';
  UIDAndParams := _join_params(UIDParam, ParamDecl);

  EmitSyncWrapper(Lines, ApiName, ParamDecl,
    'LF.app_target(ABI_TargetApp[]; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitAsyncWrapper(Lines, ApiName + '_Async', _join_params(ParamDecl, CBParam),
    'async_call', 'LF.app_target(ABI_TargetApp[]; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitAsyncWrapper(Lines, ApiName + '_AsyncSequenced', _join_params(ParamDecl, CBParam),
    'async_sequenced_call', 'LF.app_target(ABI_TargetApp[]; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitSyncWrapper(Lines, ApiName + '_UID_Call', UIDAndParams,
    'LF.uid_target(__lf_uid; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitAsyncWrapper(Lines, ApiName + '_UID_Async', _join_params(UIDAndParams, CBParam),
    'async_call', 'LF.uid_target(__lf_uid; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitAsyncWrapper(Lines, ApiName + '_UID_AsyncSequenced', _join_params(UIDAndParams, CBParam),
    'async_sequenced_call', 'LF.uid_target(__lf_uid; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitSyncWrapper(Lines, ApiName + '_P2PName_Call', _join_params(P2PParam, ParamDecl),
    'LF.p2pname_target(__lf_p2p; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitAsyncWrapper(Lines, ApiName + '_P2PName_Async', _join_params(_join_params(P2PParam, ParamDecl), CBParam),
    'async_call', 'LF.p2pname_target(__lf_p2p; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);

  EmitAsyncWrapper(Lines, ApiName + '_P2PName_AsyncSequenced', _join_params(_join_params(P2PParam, ParamDecl), CBParam),
    'async_sequenced_call', 'LF.p2pname_target(__lf_p2p; timeout_ms = ABI_Timeout[])', ApiName, F, Payload);
end;

procedure EmitProcedureWrappers(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, Payload, UIDParam, P2PParam, UIDAndParams: TP_String;
begin
  ParamDecl := BuildParamDeclTyped(F.Params);
  Payload := BuildPayloadClosure(F.Params);
  UIDParam := '__lf_uid::LF.LFShimUID';
  P2PParam := '__lf_p2p::AbstractString';
  UIDAndParams := _join_params(UIDParam, ParamDecl);

  EmitNotifyWrapper(Lines, ApiName, ParamDecl,
    'notify', 'LF.app_target(ABI_TargetApp[])', ApiName, F, Payload);

  EmitNotifyWrapper(Lines, ApiName + '_SequencedNotify', ParamDecl,
    'sequenced_notify', 'LF.app_target(ABI_TargetApp[])', ApiName, F, Payload);

  EmitNotifyWrapper(Lines, ApiName + '_UID_Notify', UIDAndParams,
    'notify', 'LF.uid_target(__lf_uid)', ApiName, F, Payload);

  EmitNotifyWrapper(Lines, ApiName + '_UID_SequencedNotify', UIDAndParams,
    'sequenced_notify', 'LF.uid_target(__lf_uid)', ApiName, F, Payload);

  EmitNotifyWrapper(Lines, ApiName + '_P2PName_Notify', _join_params(P2PParam, ParamDecl),
    'notify', 'LF.p2pname_target(__lf_p2p)', ApiName, F, Payload);

  EmitNotifyWrapper(Lines, ApiName + '_P2PName_SequencedNotify', _join_params(P2PParam, ParamDecl),
    'sequenced_notify', 'LF.p2pname_target(__lf_p2p)', ApiName, F, Payload);
end;

function GenerateABICallJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName: TP_String;
  ApiNames: TPascalStringList;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallJuliaCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallJuliaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi_call';
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating Julia ABI call for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty module.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    AssignUniqueApiNames(SupportedFuncs, ApiNames);

    Lines.Add('module ' + NsName.Text);
    Lines.Add('');
    Lines.Add('import LingoFuse');
    Lines.Add('const LF = LingoFuse');
    Lines.Add('');
    Lines.Add('const ABI_TargetApp = Ref{String}(' + JuliaStrLit(AppName).Text + ')');
    Lines.Add('const ABI_Timeout   = Ref{Int}(5000)');
    Lines.Add('');

    EmitExceptionType(Lines);
    EmitReaders(Lines);
    EmitCheckResponse(Lines);

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
        EmitFunctionWrappers(Lines, ApiNames[i], F)
      else
        EmitProcedureWrappers(Lines, ApiNames[i], F);
    end;

    Lines.Add('export EABI_RemoteError');
    Lines.Add('export ABI_TargetApp');
    Lines.Add('export ABI_Timeout');
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      if F.IsFunction then
      begin
        Lines.Add('export ' + ApiNames[i].Text);
        Lines.Add('export ' + ApiNames[i].Text + '_Async');
        Lines.Add('export ' + ApiNames[i].Text + '_AsyncSequenced');
        Lines.Add('export ' + ApiNames[i].Text + '_UID_Call');
        Lines.Add('export ' + ApiNames[i].Text + '_UID_Async');
        Lines.Add('export ' + ApiNames[i].Text + '_UID_AsyncSequenced');
        Lines.Add('export ' + ApiNames[i].Text + '_P2PName_Call');
        Lines.Add('export ' + ApiNames[i].Text + '_P2PName_Async');
        Lines.Add('export ' + ApiNames[i].Text + '_P2PName_AsyncSequenced');
      end
      else
      begin
        Lines.Add('export ' + ApiNames[i].Text);
        Lines.Add('export ' + ApiNames[i].Text + '_SequencedNotify');
        Lines.Add('export ' + ApiNames[i].Text + '_UID_Notify');
        Lines.Add('export ' + ApiNames[i].Text + '_UID_SequencedNotify');
        Lines.Add('export ' + ApiNames[i].Text + '_P2PName_Notify');
        Lines.Add('export ' + ApiNames[i].Text + '_P2PName_SequencedNotify');
      end;
    end;
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
    'xxx_abi_call.jl',
    gkCall,
    'Julia ABI call module',
    @GenerateABICallJuliaCode);

end.
