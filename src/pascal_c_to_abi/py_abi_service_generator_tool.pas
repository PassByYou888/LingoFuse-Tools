unit py_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServicePyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'str()'
  else if IsFloatABIType(T) or T.Same('single') then
    Result := '0.0'
  else
    Result := '0';
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

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('');
  Lines.Add('import ctypes');
  Lines.Add('import struct');
  Lines.Add('');
  Lines.Add('from lingofuse._lf_native import (');
  Lines.Add('    DataHnd,');
  Lines.Add('    AppHnd,');
  Lines.Add('    LFCallFunc,');
  Lines.Add('    LFNotifyFunc,');
  Lines.Add('    LF_CreateApp,');
  Lines.Add('    LF_FreeApp,');
  Lines.Add('    LF_RegisterCall,');
  Lines.Add('    LF_RegisterNotify,');
  Lines.Add('    LF_Register_P2P_Call,');
  Lines.Add('    LF_Register_P2P_Notify,');
  Lines.Add('    LF_ReadBuffer,');
  Lines.Add('    LF_WriteBuffer,');
  Lines.Add(')');
  Lines.Add('from lingofuse.lf_io import (');
  Lines.Add('    cstr,');
  Lines.Add('    read_string as _lf_read_string,');
  Lines.Add('    write_string as _lf_write_string,');
  Lines.Add(')');
  Lines.Add('from lingofuse.core import DataHandle');
  Lines.Add('');
end;

procedure EmitConstants(Lines: TPascalStringList; const AppName, AppDesc: TP_String; const ApiCount: integer);
begin
  Lines.Add('DEFAULT_APP_NAME = ' + PyStrLit(AppName));
  Lines.Add('DEFAULT_APP_DESC = ' + PyStrLit(AppDesc));
  Lines.Add('');
  Lines.Add('DEBUG_LOG = True');
  Lines.Add('');
  Lines.Add('STATUS_OK = 0x00');
  Lines.Add('STATUS_ERROR = 0xFF');
  Lines.Add('');
  Lines.Add('API_COUNT = ' + umlIntToStr(ApiCount).Text);
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

procedure EmitInternalCallStubs(Lines: TPascalStringList;
  const Funcs: TArryFunctionStructure; const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, RetAnnotation, DefaultExpr: TP_String;
begin
  for i := 0 to High(Funcs) do
  begin
    F := Funcs[i];
    ApiName := ApiNames[i];

    if F.IsFunction then
      RetAnnotation := ABI_Type_To_Py_Annotation(F.ReturnType)
    else
      RetAnnotation := 'None';

    ParamDecl := '_lf_uid, _lf_p2p_name';
    for j := 0 to High(F.Params) do
    begin
      ParamDecl := ParamDecl + ', ' + MakeSafePyParamName(F.Params[j].Name, j) +
        ': ' + ABI_Type_To_Py_Annotation(F.Params[j].PascalType);
    end;

    EmitCommentBlock(Lines, '', F.Comment);

    Lines.Add('def internal_call_' + ApiName + '(' + ParamDecl + ') -> ' + RetAnnotation + ':');
    if F.IsFunction then
    begin
      DefaultExpr := ABI_Type_Default(F.ReturnType);
      Lines.Add('    return ' + DefaultExpr);
    end
    else
    begin
      Lines.Add('    return None');
    end;
    Lines.Add('');
    Lines.Add('');
  end;
end;

procedure EmitCallbacks(Lines: TPascalStringList;
  const Funcs: TArryFunctionStructure; const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, ParamName, ReadFunc, WriteFunc, ArgList: TP_String;
begin
  for i := 0 to High(Funcs) do
  begin
    F := Funcs[i];
    ApiName := ApiNames[i];
    ArgList := BuildArgListWithPrefix('_lf_uid, _lf_p2p_name', F.Params);

    if F.IsFunction then
    begin
      Lines.Add('@LFCallFunc');
      Lines.Add('def Callback_' + ApiName + '(_Trigger, _In, _Out):');
      Lines.Add('    in_hnd = DataHandle._from_raw(_In, owned=False)');
      Lines.Add('    try:');
      Lines.Add('        _lf_uid = in_hnd.get_p2p_uid()');
      Lines.Add('        _lf_p2p_name = in_hnd.get_p2p_name()');
      Lines.Add('    except Exception:');
      Lines.Add('        _lf_uid = b"\x00" * 32');
      Lines.Add('        _lf_p2p_name = ""');
      Lines.Add('');
      Lines.Add('    try:');
      for j := 0 to High(F.Params) do
      begin
        ParamName := MakeSafePyParamName(F.Params[j].Name, j);
        ReadFunc := ABI_Type_To_Py_Read_Func(F.Params[j].PascalType);
        Lines.Add('        ' + ParamName + ' = ' + ReadFunc + '(_In)');
      end;
      Lines.Add('        _ret = internal_call_' + ApiName + '(' + ArgList + ')');
      Lines.Add('        _write_uint8(_Out, STATUS_OK)');
      WriteFunc := ABI_Type_To_Py_Write_Func(F.ReturnType);
      Lines.Add('        ' + WriteFunc + '(_Out, _ret)');
      Lines.Add('    except Exception as _e:');
      Lines.Add('        try:');
      Lines.Add('            _write_uint8(_Out, STATUS_ERROR)');
      Lines.Add('            _write_string(_Out, str(_e))');
      Lines.Add('        except Exception:');
      Lines.Add('            pass');
      Lines.Add('');
      Lines.Add('');
    end
    else
    begin
      Lines.Add('@LFNotifyFunc');
      Lines.Add('def Callback_' + ApiName + '(_Trigger, _In):');
      Lines.Add('    in_hnd = DataHandle._from_raw(_In, owned=False)');
      Lines.Add('    try:');
      Lines.Add('        _lf_uid = in_hnd.get_p2p_uid()');
      Lines.Add('        _lf_p2p_name = in_hnd.get_p2p_name()');
      Lines.Add('    except Exception:');
      Lines.Add('        _lf_uid = b"\x00" * 32');
      Lines.Add('        _lf_p2p_name = ""');
      Lines.Add('');
      Lines.Add('    try:');
      for j := 0 to High(F.Params) do
      begin
        ParamName := MakeSafePyParamName(F.Params[j].Name, j);
        ReadFunc := ABI_Type_To_Py_Read_Func(F.Params[j].PascalType);
        Lines.Add('        ' + ParamName + ' = ' + ReadFunc + '(_In)');
      end;
      Lines.Add('        internal_call_' + ApiName + '(' + ArgList + ')');
      Lines.Add('    except Exception:');
      Lines.Add('        pass');
      Lines.Add('');
      Lines.Add('');
    end;
  end;
end;

procedure EmitRegistration(Lines: TPascalStringList;
  const Funcs: TArryFunctionStructure; const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Desc, RegFunc, CbFunc: TP_String;
begin
  Lines.Add('def Register_All_ABI_APIs(app):');
  Lines.Add('    _failed = 0');
  for i := 0 to High(Funcs) do
  begin
    F := Funcs[i];
    ApiName := ApiNames[i];
    Desc := GetFullDescription(F.Comment);
    if Desc.Len = 0 then
      Desc := 'ABI api for ' + F.Name;
    if F.IsFunction then
      RegFunc := 'LF_RegisterCall'
    else
      RegFunc := 'LF_RegisterNotify';
    CbFunc := 'Callback_' + ApiName;
    Lines.Add('    if ' + RegFunc + '(app, cstr(' + PyStrLit(ApiName) + '), cstr(' +
      PyStrLit(Desc) + '), None, ' + CbFunc + ') != 1:');
    Lines.Add('        _failed += 1');
  end;
  Lines.Add('    return _failed');
  Lines.Add('');
  Lines.Add('');

  Lines.Add('def Register_All_P2P_ABI_APIs():');
  Lines.Add('    _failed = 0');
  for i := 0 to High(Funcs) do
  begin
    F := Funcs[i];
    ApiName := ApiNames[i];
    Desc := GetFullDescription(F.Comment);
    if Desc.Len = 0 then
      Desc := 'ABI api for ' + F.Name;
    if F.IsFunction then
      RegFunc := 'LF_Register_P2P_Call'
    else
      RegFunc := 'LF_Register_P2P_Notify';
    CbFunc := 'Callback_' + ApiName;
    Lines.Add('    if ' + RegFunc + '(cstr(' + PyStrLit(ApiName) + '), cstr(' +
      PyStrLit(Desc) + '), None, ' + CbFunc + ') != 1:');
    Lines.Add('        _failed += 1');
  end;
  Lines.Add('    return _failed');
  Lines.Add('');
  Lines.Add('');

  Lines.Add('def Create_And_Register_ABI_App():');
  Lines.Add('    app = LF_CreateApp(cstr(DEFAULT_APP_NAME), cstr(DEFAULT_APP_DESC))');
  Lines.Add('    if app:');
  Lines.Add('        Register_All_ABI_APIs(app)');
  Lines.Add('    return app');
  Lines.Add('');
end;

function GenerateABIServicePyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServicePyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServicePyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Python ABI service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines);
    EmitConstants(Lines, AppName, AppDesc, Length(SupportedFuncs));
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

    EmitInternalCallStubs(Lines, SupportedFuncs, UsedApiNames);
    EmitCallbacks(Lines, SupportedFuncs, UsedApiNames);
    EmitRegistration(Lines, SupportedFuncs, UsedApiNames);

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
    'xxx_abi_service.py',
    gkService,
    'Python ABI service module',
    @GenerateABIServicePyCode);

end.
