unit py_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABICallPyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function IsInt32ABIType(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('longint');
end;

function IsUInt32ABIType(const T: TP_String): boolean;
begin
  Result := T.Same('cardinal') or T.Same('dword') or T.Same('longword');
end;

function IsFloatABIType(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('extended') or T.Same('real');
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := IsStringABIType(T) or IsInt32ABIType(T) or IsUInt32ABIType(T) or IsFloatABIType(T) or
    T.Same('int64') or T.Same('word') or T.Same('smallint') or T.Same('byte') or
    T.Same('uint64') or T.Same('single');
end;

function ABI_Type_To_Py_Annotation(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'str'
  else if IsFloatABIType(T) or T.Same('single') then
    Result := 'float'
  else if IsInt32ABIType(T) or T.Same('int64') or IsUInt32ABIType(T) or
    T.Same('word') or T.Same('smallint') or T.Same('byte') or T.Same('uint64') then
    Result := 'int'
  else
    Result := '';
end;

function ABI_Type_To_Py_Read_Func(const T: TP_String): TP_String;
begin
  if IsInt32ABIType(T) then Result := '_read_int32'
  else if T.Same('int64') then Result := '_read_int64'
  else if IsUInt32ABIType(T) then Result := '_read_uint32'
  else if T.Same('word') then Result := '_read_uint16'
  else if T.Same('smallint') then Result := '_read_int16'
  else if T.Same('byte') then Result := '_read_uint8'
  else if T.Same('uint64') then Result := '_read_uint64'
  else if IsFloatABIType(T) then Result := '_read_double'
  else if T.Same('single') then Result := '_read_single'
  else if IsStringABIType(T) then Result := '_read_string'
  else
    Result := '';
end;

function ABI_Type_To_Py_Write_Func(const T: TP_String): TP_String;
begin
  if IsInt32ABIType(T) then Result := '_write_int32'
  else if T.Same('int64') then Result := '_write_int64'
  else if IsUInt32ABIType(T) then Result := '_write_uint32'
  else if T.Same('word') then Result := '_write_uint16'
  else if T.Same('smallint') then Result := '_write_int16'
  else if T.Same('byte') then Result := '_write_uint8'
  else if T.Same('uint64') then Result := '_write_uint64'
  else if IsFloatABIType(T) then Result := '_write_double'
  else if T.Same('single') then Result := '_write_single'
  else if IsStringABIType(T) then Result := '_write_string'
  else
    Result := '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsPythonKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('False') or S.Same('None') or S.Same('True') or S.Same('and') or S.Same('as') or
    S.Same('assert') or S.Same('async') or S.Same('await') or S.Same('break') or S.Same('class') or
    S.Same('continue') or S.Same('def') or S.Same('del') or S.Same('elif') or S.Same('else') or
    S.Same('except') or S.Same('finally') or S.Same('for') or S.Same('from') or S.Same('global') or
    S.Same('if') or S.Same('import') or S.Same('in') or S.Same('is') or S.Same('lambda') or
    S.Same('nonlocal') or S.Same('not') or S.Same('or') or S.Same('pass') or S.Same('raise') or
    S.Same('return') or S.Same('try') or S.Same('while') or S.Same('with') or S.Same('yield');
end;

function IsPyIdentStart(c: TP_Char): boolean;
begin
  Result := (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'));
end;

function IsPyIdentChar(c: TP_Char): boolean;
begin
  Result := IsPyIdentStart(c) or ((c >= '0') and (c <= '9'));
end;

function IsValidPyIdentifier(const S: TP_String): boolean;
var
  i: integer;
begin
  Result := False;
  if S.Len = 0 then Exit;
  if IsPythonKeyword(S) then Exit;
  if not IsPyIdentStart(S[1]) then Exit;
  for i := 2 to S.Len do
    if not IsPyIdentChar(S[i]) then Exit;
  Result := True;
end;

function IsReservedInternalName(const S: TP_String): boolean;
begin
  Result := S.Same('on_result') or S.Same('user_data') or
    S.Same('_data') or S.Same('_res') or S.Same('_status') or
    S.Same('_err') or S.Same('_e') or S.Same('_ret') or
    S.Same('_fut') or S.Same('_r') or S.Same('_on_done') or
    S.Same('_issue') or S.Same('_cb') or S.Same('_uid_bytes') or
    S.Same('_uid_arr') or S.Same('_lf_uid') or S.Same('_lf_p2p_name') or
    S.Same('_f');
end;

function MakeSafePyParamName(const Name: TP_String; Index: integer): TP_String;
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

  if IsPythonKeyword(Result) then
    Result := Result + '_';

  if IsReservedInternalName(Result) then
    Result := Result + '_';
end;

function PyStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
      Result.Append('\' + #39)
    else if c = #92 then
      Result.Append('\\')
    else if c = #10 then
      Result.Append('\n')
    else if c = #13 then
      Result.Append('\r')
    else if c = #9 then
      Result.Append('\t')
    else
      Result.Append(c);
  end;
  Result.Append(#39);
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

procedure EmitCommentBlock(Lines: TPascalStringList;
  const Indent, Comment: TP_String);
var
  StartPos, EndPos: Integer;
  Line: TP_String;
begin
  if Comment.Len = 0 then Exit;
  StartPos := 1;
  while StartPos <= Comment.Len do
  begin
    EndPos := StartPos;
    while (EndPos <= Comment.Len) and (Comment[EndPos] <> #10)
      and (Comment[EndPos] <> #13) do
      Inc(EndPos);
    if EndPos > StartPos then
    begin
      Line := Comment.GetString(StartPos, EndPos);
      Line := StripCommentMarkers(Line);
      if Line.Len > 0 then
        Lines.Add(Indent + '# ' + Line.Text);
    end;
    StartPos := EndPos;
    while (StartPos <= Comment.Len) and ((Comment[StartPos] = #10)
      or (Comment[StartPos] = #13)) do
      Inc(StartPos);
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

function BuildTypedParams(const Params: TParamArray; const ExtraPrefix: TP_String): TP_String;
var
  i: integer;
  n, t: TP_String;
begin
  Result := ExtraPrefix;
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyParamName(Params[i].Name, i);
    t := ABI_Type_To_Py_Annotation(Params[i].PascalType);
    if Result <> '' then
      Result := Result + ', ';
    if t <> '' then
      Result := Result + n + ': ' + t
    else
      Result := Result + n;
  end;
end;

function BuildArgListWithPrefix(const Leading_: TP_String; const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := Leading_;
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyParamName(Params[i].Name, i);
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

procedure EmitWriteStatements(Lines: TPascalStringList; const Params: TParamArray; const Indent: string);
var
  i: integer;
  n, fn: TP_String;
begin
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyParamName(Params[i].Name, i);
    fn := ABI_Type_To_Py_Write_Func(Params[i].PascalType);
    Lines.Add(Indent + fn + '(_data, ' + n + ')');
  end;
end;

procedure EmitHeader(Lines: TPascalStringList; const TargetAppName: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('');
  Lines.Add('import ctypes');
  Lines.Add('import struct');
  Lines.Add('');
  Lines.Add('from lingofuse._lf_native import (');
  Lines.Add('    DataHnd,');
  Lines.Add('    LF_CreateData,');
  Lines.Add('    LF_FreeData,');
  Lines.Add('    LF_GetSize,');
  Lines.Add('    LF_SetPos,');
  Lines.Add('    LF_ReadBuffer,');
  Lines.Add('    LF_WriteBuffer,');
  Lines.Add('    LF_Call,');
  Lines.Add('    LF_Notify,');
  Lines.Add('    LF_Sequenced_Notify,');
  Lines.Add('    LF_Async_Call,');
  Lines.Add('    LF_Async_Sequenced_Call,');
  Lines.Add('    LF_UID_Call,');
  Lines.Add('    LF_UID_Notify,');
  Lines.Add('    LF_UID_Sequenced_Notify,');
  Lines.Add('    LF_UID_Async_Call,');
  Lines.Add('    LF_UID_Async_Sequenced_Call,');
  Lines.Add('    LF_P2PNAME_Call,');
  Lines.Add('    LF_P2PNAME_Notify,');
  Lines.Add('    LF_P2PNAME_Sequenced_Notify,');
  Lines.Add('    LF_P2PNAME_Async_Call,');
  Lines.Add('    LF_P2PNAME_Async_Sequenced_Call,');
  Lines.Add(')');
  Lines.Add('from lingofuse.lf_io import (');
  Lines.Add('    cstr,');
  Lines.Add('    read_string as _lf_read_string,');
  Lines.Add('    write_string as _lf_write_string,');
  Lines.Add(')');
  Lines.Add('from lingofuse.address import normalize_uid, to_tp2p_uid');
  Lines.Add('from lingofuse.async_support import (');
  Lines.Add('    CallFuture,');
  Lines.Add('    await_future,');
  Lines.Add('    run_async_with_future,');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('ABI_TARGET_APP = ' + PyStrLit(TargetAppName));
  Lines.Add('ABI_TIMEOUT = 5000');
  Lines.Add('STATUS_OK = 0x00');
  Lines.Add('STATUS_ERROR = 0xFF');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('class EABIRemoteError(Exception):');
  Lines.Add('    pass');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitSerializationHelpers(Lines: TPascalStringList);
begin
  Lines.Add('def _read_exact(hnd, size):');
  Lines.Add('    if size <= 0:');
  Lines.Add('        return b""');
  Lines.Add('    buf = (ctypes.c_byte * size)()');
  Lines.Add('    n = LF_ReadBuffer(hnd, buf, size)');
  Lines.Add('    if n != size:');
  Lines.Add('        raise IOError("input truncated: expected %d bytes, got %d" % (size, n))');
  Lines.Add('    return bytes(buf)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_exact(hnd, data):');
  Lines.Add('    if not data:');
  Lines.Add('        return');
  Lines.Add('    n = LF_WriteBuffer(hnd, data, len(data))');
  Lines.Add('    if n != len(data):');
  Lines.Add('        raise IOError("output truncated: expected %d bytes, got %d" % (len(data), n))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_uint8(hnd):');
  Lines.Add('    return struct.unpack("<B", _read_exact(hnd, 1))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_int8(hnd):');
  Lines.Add('    return struct.unpack("<b", _read_exact(hnd, 1))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_uint16(hnd):');
  Lines.Add('    return struct.unpack("<H", _read_exact(hnd, 2))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_int16(hnd):');
  Lines.Add('    return struct.unpack("<h", _read_exact(hnd, 2))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_uint32(hnd):');
  Lines.Add('    return struct.unpack("<I", _read_exact(hnd, 4))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_int32(hnd):');
  Lines.Add('    return struct.unpack("<i", _read_exact(hnd, 4))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_uint64(hnd):');
  Lines.Add('    return struct.unpack("<Q", _read_exact(hnd, 8))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_int64(hnd):');
  Lines.Add('    return struct.unpack("<q", _read_exact(hnd, 8))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_single(hnd):');
  Lines.Add('    return struct.unpack("<f", _read_exact(hnd, 4))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_double(hnd):');
  Lines.Add('    return struct.unpack("<d", _read_exact(hnd, 8))[0]');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_string(hnd):');
  Lines.Add('    return _lf_read_string(hnd)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_uint8(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<B", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_int8(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<b", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_uint16(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<H", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_int16(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<h", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_uint32(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<I", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_int32(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<i", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_uint64(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<Q", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_int64(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<q", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_single(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<f", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_double(hnd, v):');
  Lines.Add('    _write_exact(hnd, struct.pack("<d", v))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_string(hnd, v):');
  Lines.Add('    _lf_write_string(hnd, v)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitResponseReaders(Lines: TPascalStringList;
  const Funcs: TArryFunctionStructure; const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ReadFunc: TP_String;
begin
  for i := 0 to High(Funcs) do
  begin
    F := Funcs[i];
    if not F.IsFunction then Continue;
    ApiName := ApiNames[i];
    ReadFunc := ABI_Type_To_Py_Read_Func(F.ReturnType);
    Lines.Add('def _read_' + ApiName + '_response(_res):');
    Lines.Add('    if not _res:');
    Lines.Add('        raise EABIRemoteError("nil response (timeout or target not found)")');
    Lines.Add('    if LF_GetSize(_res) <= 0:');
    Lines.Add('        raise EABIRemoteError("empty response")');
    Lines.Add('    LF_SetPos(_res, 0)');
    Lines.Add('    _status = _read_uint8(_res)');
    Lines.Add('    if _status != STATUS_OK:');
    Lines.Add('        _err = ""');
    Lines.Add('        try:');
    Lines.Add('            _err = _read_string(_res)');
    Lines.Add('        except Exception:');
    Lines.Add('            pass');
    Lines.Add('        raise EABIRemoteError(_err)');
    Lines.Add('    return ' + ReadFunc + '(_res)');
    Lines.Add('');
    Lines.Add('');
  end;
end;

procedure EmitFunctionSyncApp(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetAnnotation, ParamDecl: TP_String;
begin
  RetAnnotation := ABI_Type_To_Py_Annotation(F.ReturnType);
  ParamDecl := BuildTypedParams(F.Params, '');
  Lines.Add('def ' + ApiName + '(' + ParamDecl + ') -> ' + RetAnnotation + ':');
  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError("LF_CreateData returned nil for API ' +
    PyStrLit(ApiName) + '")');
  Lines.Add('    try:');
  EmitWriteStatements(Lines, F.Params, '        ');
  Lines.Add('        _res = LF_Call(cstr(ABI_TARGET_APP), _data, ABI_TIMEOUT)');
  Lines.Add('        try:');
  Lines.Add('            return _read_' + ApiName + '_response(_res)');
  Lines.Add('        finally:');
  Lines.Add('            if _res:');
  Lines.Add('                LF_FreeData(_res)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitFunctionSyncUID(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetAnnotation, ParamDecl: TP_String;
begin
  RetAnnotation := ABI_Type_To_Py_Annotation(F.ReturnType);
  ParamDecl := BuildTypedParams(F.Params, 'uid');
  Lines.Add('def ' + ApiName + '_UID_Call(' + ParamDecl + ') -> ' + RetAnnotation + ':');
  Lines.Add('    _uid_bytes = normalize_uid(uid)');
  Lines.Add('    _uid_arr = to_tp2p_uid(_uid_bytes)');
  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError("LF_CreateData returned nil for API ' +
    PyStrLit(ApiName) + '")');
  Lines.Add('    try:');
  EmitWriteStatements(Lines, F.Params, '        ');
  Lines.Add('        _res = LF_UID_Call(_uid_arr, _data, ABI_TIMEOUT)');
  Lines.Add('        try:');
  Lines.Add('            return _read_' + ApiName + '_response(_res)');
  Lines.Add('        finally:');
  Lines.Add('            if _res:');
  Lines.Add('                LF_FreeData(_res)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitFunctionSyncP2P(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
var
  RetAnnotation, ParamDecl: TP_String;
begin
  RetAnnotation := ABI_Type_To_Py_Annotation(F.ReturnType);
  ParamDecl := BuildTypedParams(F.Params, 'p2p_name');
  Lines.Add('def ' + ApiName + '_P2PName_Call(' + ParamDecl + ') -> ' + RetAnnotation + ':');
  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError("LF_CreateData returned nil for API ' +
    PyStrLit(ApiName) + '")');
  Lines.Add('    try:');
  EmitWriteStatements(Lines, F.Params, '        ');
  Lines.Add('        _res = LF_P2PNAME_Call(cstr(p2p_name), _data, ABI_TIMEOUT)');
  Lines.Add('        try:');
  Lines.Add('            return _read_' + ApiName + '_response(_res)');
  Lines.Add('        finally:');
  Lines.Add('            if _res:');
  Lines.Add('                LF_FreeData(_res)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitAsyncDispatchCore(Lines: TPascalStringList;
  const ApiName, AsyncCallFunc, FirstArg: TP_String; const F: TFunctionStructure);
begin
  Lines.Add('    def _issue(_cb):');
  Lines.Add('        _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('        if not _data:');
  Lines.Add('            return 0');
  Lines.Add('        try:');
  EmitWriteStatements(Lines, F.Params, '            ');
  if FirstArg = '' then
    Lines.Add('            return ' + AsyncCallFunc + '(cstr(ABI_TARGET_APP), _data, None, _cb)')
  else if FirstArg = '_uid_arr' then
    Lines.Add('            return ' + AsyncCallFunc + '(_uid_arr, _data, None, _cb)')
  else
    Lines.Add('            return ' + AsyncCallFunc + '(cstr(p2p_name), _data, None, _cb)');
  Lines.Add('        finally:');
  Lines.Add('            LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('    _fut = run_async_with_future(');
  Lines.Add('        issue_fn=_issue,');
  Lines.Add('        deserialize=_read_' + ApiName + '_response,');
  Lines.Add('        timeout_ms=ABI_TIMEOUT,');
  Lines.Add('    )');
  Lines.Add('    if on_result is None:');
  Lines.Add('        return _fut');
  Lines.Add('');
  Lines.Add('    def _on_done(_f):');
  Lines.Add('        try:');
  Lines.Add('            _r = _f.result()');
  Lines.Add('            on_result(_r, None, user_data)');
  Lines.Add('        except Exception as _e:');
  Lines.Add('            on_result(None, _e, user_data)');
  Lines.Add('');
  Lines.Add('    _fut.add_done_callback(_on_done)');
  Lines.Add('    return None');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitFunctionAsyncApp(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, AsyncFunc, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, '');
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + '*, on_result=None, user_data=None';
  if Sequenced then
  begin
    AsyncFunc := 'LF_Async_Sequenced_Call';
    Suffix := '_AsyncSequenced';
  end
  else
  begin
    AsyncFunc := 'LF_Async_Call';
    Suffix := '_Async';
  end;
  Lines.Add('def ' + ApiName + Suffix + '(' + ParamDecl + '):');
  EmitAsyncDispatchCore(Lines, ApiName, AsyncFunc, '', F);
end;

procedure EmitFunctionAsyncUID(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, AsyncFunc, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, 'uid');
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + '*, on_result=None, user_data=None';
  if Sequenced then
  begin
    AsyncFunc := 'LF_UID_Async_Sequenced_Call';
    Suffix := '_UID_AsyncSequenced';
  end
  else
  begin
    AsyncFunc := 'LF_UID_Async_Call';
    Suffix := '_UID_Async';
  end;
  Lines.Add('def ' + ApiName + Suffix + '(' + ParamDecl + '):');
  Lines.Add('    _uid_bytes = normalize_uid(uid)');
  Lines.Add('    _uid_arr = to_tp2p_uid(_uid_bytes)');
  EmitAsyncDispatchCore(Lines, ApiName, AsyncFunc, '_uid_arr', F);
end;

procedure EmitFunctionAsyncP2P(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, AsyncFunc, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, 'p2p_name');
  if ParamDecl <> '' then
    ParamDecl := ParamDecl + ', ';
  ParamDecl := ParamDecl + '*, on_result=None, user_data=None';
  if Sequenced then
  begin
    AsyncFunc := 'LF_P2PNAME_Async_Sequenced_Call';
    Suffix := '_P2PName_AsyncSequenced';
  end
  else
  begin
    AsyncFunc := 'LF_P2PNAME_Async_Call';
    Suffix := '_P2PName_Async';
  end;
  Lines.Add('def ' + ApiName + Suffix + '(' + ParamDecl + '):');
  EmitAsyncDispatchCore(Lines, ApiName, AsyncFunc, 'p2p_name', F);
end;

procedure EmitFunctionAioApp(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, CallExpr, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, '');
  if Sequenced then
  begin
    CallExpr := ApiName + '_AsyncSequenced(' + BuildArgListWithPrefix('', F.Params) + ')';
    Suffix := '_Sequenced_Aio';
  end
  else
  begin
    CallExpr := ApiName + '_Async(' + BuildArgListWithPrefix('', F.Params) + ')';
    Suffix := '_Aio';
  end;
  Lines.Add('async def ' + ApiName + Suffix + '(' + ParamDecl + '):');
  Lines.Add('    _fut = ' + CallExpr);
  Lines.Add('    return await await_future(_fut)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitFunctionAioUID(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, CallExpr, Suffix, ArgList: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, 'uid');
  ArgList := BuildArgListWithPrefix('uid', F.Params);
  if Sequenced then
  begin
    CallExpr := ApiName + '_UID_AsyncSequenced(' + ArgList + ')';
    Suffix := '_UID_Sequenced_Aio';
  end
  else
  begin
    CallExpr := ApiName + '_UID_Async(' + ArgList + ')';
    Suffix := '_UID_Aio';
  end;
  Lines.Add('async def ' + ApiName + Suffix + '(' + ParamDecl + '):');
  Lines.Add('    _fut = ' + CallExpr);
  Lines.Add('    return await await_future(_fut)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitFunctionAioP2P(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, CallExpr, Suffix, ArgList: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, 'p2p_name');
  ArgList := BuildArgListWithPrefix('p2p_name', F.Params);
  if Sequenced then
  begin
    CallExpr := ApiName + '_P2PName_AsyncSequenced(' + ArgList + ')';
    Suffix := '_P2PName_Sequenced_Aio';
  end
  else
  begin
    CallExpr := ApiName + '_P2PName_Async(' + ArgList + ')';
    Suffix := '_P2PName_Aio';
  end;
  Lines.Add('async def ' + ApiName + Suffix + '(' + ParamDecl + '):');
  Lines.Add('    _fut = ' + CallExpr);
  Lines.Add('    return await await_future(_fut)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitProcedureNotifyApp(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, NotifyFunc, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, '');
  if Sequenced then
  begin
    NotifyFunc := 'LF_Sequenced_Notify';
    Suffix := '_SequencedNotify';
  end
  else
  begin
    NotifyFunc := 'LF_Notify';
    Suffix := '';
  end;
  Lines.Add('def ' + ApiName + Suffix + '(' + ParamDecl + ') -> None:');
  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError("LF_CreateData returned nil for API ' +
    PyStrLit(ApiName) + '")');
  Lines.Add('    try:');
  EmitWriteStatements(Lines, F.Params, '        ');
  Lines.Add('        ' + NotifyFunc + '(cstr(ABI_TARGET_APP), _data)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitProcedureNotifyUID(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, NotifyFunc, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, 'uid');
  if Sequenced then
  begin
    NotifyFunc := 'LF_UID_Sequenced_Notify';
    Suffix := '_UID_SequencedNotify';
  end
  else
  begin
    NotifyFunc := 'LF_UID_Notify';
    Suffix := '_UID_Notify';
  end;
  Lines.Add('def ' + ApiName + Suffix + '(' + ParamDecl + ') -> None:');
  Lines.Add('    _uid_bytes = normalize_uid(uid)');
  Lines.Add('    _uid_arr = to_tp2p_uid(_uid_bytes)');
  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError("LF_CreateData returned nil for API ' +
    PyStrLit(ApiName) + '")');
  Lines.Add('    try:');
  EmitWriteStatements(Lines, F.Params, '        ');
  Lines.Add('        ' + NotifyFunc + '(_uid_arr, _data)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitProcedureNotifyP2P(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure; const Sequenced: boolean);
var
  ParamDecl, NotifyFunc, Suffix: TP_String;
begin
  ParamDecl := BuildTypedParams(F.Params, 'p2p_name');
  if Sequenced then
  begin
    NotifyFunc := 'LF_P2PNAME_Sequenced_Notify';
    Suffix := '_P2PName_SequencedNotify';
  end
  else
  begin
    NotifyFunc := 'LF_P2PNAME_Notify';
    Suffix := '_P2PName_Notify';
  end;
  Lines.Add('def ' + ApiName + Suffix + '(' + ParamDecl + ') -> None:');
  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError("LF_CreateData returned nil for API ' +
    PyStrLit(ApiName) + '")');
  Lines.Add('    try:');
  EmitWriteStatements(Lines, F.Params, '        ');
  Lines.Add('        ' + NotifyFunc + '(cstr(p2p_name), _data)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitFunctionVariants(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitFunctionSyncApp(Lines, ApiName, F);
  EmitFunctionSyncUID(Lines, ApiName, F);
  EmitFunctionSyncP2P(Lines, ApiName, F);
  EmitFunctionAsyncApp(Lines, ApiName, F, False);
  EmitFunctionAsyncApp(Lines, ApiName, F, True);
  EmitFunctionAioApp(Lines, ApiName, F, False);
  EmitFunctionAioApp(Lines, ApiName, F, True);
  EmitFunctionAsyncUID(Lines, ApiName, F, False);
  EmitFunctionAsyncUID(Lines, ApiName, F, True);
  EmitFunctionAioUID(Lines, ApiName, F, False);
  EmitFunctionAioUID(Lines, ApiName, F, True);
  EmitFunctionAsyncP2P(Lines, ApiName, F, False);
  EmitFunctionAsyncP2P(Lines, ApiName, F, True);
  EmitFunctionAioP2P(Lines, ApiName, F, False);
  EmitFunctionAioP2P(Lines, ApiName, F, True);
end;

procedure EmitProcedureVariants(Lines: TPascalStringList;
  const ApiName: TP_String; const F: TFunctionStructure);
begin
  EmitProcedureNotifyApp(Lines, ApiName, F, False);
  EmitProcedureNotifyApp(Lines, ApiName, F, True);
  EmitProcedureNotifyUID(Lines, ApiName, F, False);
  EmitProcedureNotifyUID(Lines, ApiName, F, True);
  EmitProcedureNotifyP2P(Lines, ApiName, F, False);
  EmitProcedureNotifyP2P(Lines, ApiName, F, True);
end;

function GenerateABICallPyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallPyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallPyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating Python ABI call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines, TargetAppName);
    EmitSerializationHelpers(Lines);

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
    end;

    EmitResponseReaders(Lines, SupportedFuncs, UsedApiNames);

    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UsedApiNames[i];
      EmitCommentBlock(Lines, '', SupportedFuncs[i].Comment);
      if SupportedFuncs[i].IsFunction then
        EmitFunctionVariants(Lines, ApiName, SupportedFuncs[i])
      else
        EmitProcedureVariants(Lines, ApiName, SupportedFuncs[i]);
    end;

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    if Result = nil then
      Lines.Free;
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'python',
    'xxx_abi_call.py',
    gkCall,
    'Python ABI call module',
    @GenerateABICallPyCode);

end.
