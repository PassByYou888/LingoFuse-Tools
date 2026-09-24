unit py_abi_service_generator_tool;


// py_abi_service_generator_tool - LingoFuse ABI Service Provider
// Generator for Python.
//
// This unit is the Python counterpart of pas_abi_service_generator_tool.
// It consumes the same TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI)
// and produces a standalone Python module that exposes the same wire
// protocol as the Pascal service provider.
//
// The generated module exposes:
//   MY_APP_NAME, MY_APP_DESC
//   RegisterAllABIAPIs(app)
//   CreateAndRegisterABIApp()
//   (a __main__ block that runs the service when the module is executed)
//
// Wire protocol (both directions):
//   request  = [field1][field2]...[fieldN]
//   response = [status:UInt8][payload]
//     status = 0x00 -> success; payload is the serialised result
//                      (functions) or empty (procedures).
//     status = 0xFF -> error; payload is a UTF-8 string message.
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> _read_int32  / _write_int32
//   int64                         -> _read_int64  / _write_int64
//   cardinal / dword / longword   -> _read_uint32 / _write_uint32
//   word                          -> _read_uint16 / _write_uint16
//   smallint                      -> _read_int16  / _write_int16
//   byte                          -> _read_uint8  / _write_uint8
//   uint64                        -> _read_uint64 / _write_uint64
//   double / extended / real      -> _read_double / _write_double
//   single                        -> _read_single / _write_single
//   string / PChar family         -> _read_string / _write_string
//
// The generated module uses little-endian struct packing, matching the
// Pascal LF_WriteXxx / LF_ReadXxx ABI. For strings it delegates to
// lingofuse.lf_io, which guarantees UTF-8 + NUL framing identical to
// Pascal's LF_WriteString / LF_ReadString.
//
// The user is expected to:
//   1. Fill in each internal_call_<api> stub with a call to the real
//      Python function.
//   2. Run the module directly (python <file>.py) or import it and
//      follow the standard LingoFuse service setup.
//
// Author: LingoFuse-pasAgent project


{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;


  // GenerateABIServicePyCode - main entry point.
  //
  // Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
  // list is owned by the caller and must be released with DisposeObject.

function GenerateABIServicePyCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABIServicePyReadme - generate the user-facing README.

// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// ABI type mapping, and every exposed API of the generated Python
// service module. The document is written so that both human readers
// and AI assistants can learn the service's usage model from the
// README alone.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABIServicePyReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation


// -----------------------------------------------------------------------------
// Logging helpers
// -----------------------------------------------------------------------------

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


// -----------------------------------------------------------------------------
// ABI type mapping (mirrors pas_abi_service_generator_tool)
// -----------------------------------------------------------------------------

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
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
  Result := IsStringABIType(T) or IsInt32ABIType(T) or IsUInt32ABIType(T) or IsFloatABIType(T) or T.Same('int64') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('single');
end;

function ABI_Type_To_Py_Annotation(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'str'
  else if IsFloatABIType(T) or T.Same('single') then
    Result := 'float'
  else if T.Same('integer') or T.Same('longint') or T.Same('int64') or T.Same('cardinal') or T.Same('dword') or T.Same('longword') or
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
    Result := ''''''
  else if IsFloatABIType(T) or T.Same('single') then
    Result := '0.0'
  else
    Result := '0';
end;


// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// Wire API name: matches the naming scheme used by
// pas_abi_service_generator_tool, so that the two service sides
// register identical API names.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

// Python keyword list. Used to avoid generating bare identifier
// collisions with reserved words.
function IsPythonKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('False') or S.Same('None') or S.Same('True') or S.Same('and') or S.Same('as') or S.Same('assert') or S.Same('async') or
    S.Same('await') or S.Same('break') or S.Same('class') or S.Same('continue') or S.Same('def') or S.Same('del') or S.Same('elif') or
    S.Same('else') or S.Same('except') or S.Same('finally') or S.Same('for') or S.Same('from') or S.Same('global') or S.Same('if') or
    S.Same('import') or S.Same('in') or S.Same('is') or S.Same('lambda') or S.Same('nonlocal') or S.Same('not') or S.Same('or') or
    S.Same('pass') or S.Same('raise') or S.Same('return') or S.Same('try') or S.Same('while') or S.Same('with') or S.Same('yield');
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
  if S.Len = 0 then
    Exit;
  if IsPythonKeyword(S) then
    Exit;
  if not IsPyIdentStart(S[1]) then
    Exit;
  for i := 2 to S.Len do
    if not IsPyIdentChar(S[i]) then
      Exit;
  Result := True;
end;

// Produce a valid, unique Python identifier. If `Preferred` is already
// valid and unused, it is returned unchanged. Otherwise a fresh name
// is derived from `FallbackPrefix` with a numeric suffix.
function MakePyIdent(const Preferred, FallbackPrefix: TP_String; Used: TPascalStringList): TP_String;
var
  j: integer;
begin
  if IsValidPyIdentifier(Preferred) and (Used.IndexOf(Preferred) < 0) then
  begin
    Used.Add(Preferred);
    Exit(Preferred);
  end;

  j := 0;
  while True do
  begin
    Result := FallbackPrefix + '_' + umlIntToStr(j).Text;
    if IsValidPyIdentifier(Result) and (Used.IndexOf(Result) < 0) then
    begin
      Used.Add(Result);
      Exit;
    end;
    Inc(j);
  end;
end;


// -----------------------------------------------------------------------------
// Python string literal helper

// Emits a single-quoted Python string literal with backslash escapes.
// Non-ASCII characters are emitted verbatim; the generated Python file
// carries a UTF-8 coding declaration, so Python 3 will decode them
// correctly.
// -----------------------------------------------------------------------------

function PyStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '''';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '''' then
    begin
      Result.Append('\');
      Result.Append('''');
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
  Result.Append('''');
end;


// -----------------------------------------------------------------------------
// Comment description extraction (mirrors the Pascal sibling)

// Operates on UTF-16 TP_String directly. Strips comment markers,
// Doxygen tag lines, and continuation '*' markers. Only the first
// non-empty, non-Doxygen line is returned, capped at 200 characters.
// -----------------------------------------------------------------------------

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);

  // Strip "//" prefix.
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);

  // Strip leading "{" or "(*".
  if T.Len > 0 then
  begin
    if T[1] = '{' then
      T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;

  // Strip trailing "}" or "*)".
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
      Line := Comment.GetString(i, j);
      Line := StripCommentMarkers(Line);

      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
          // Skip Doxygen tag lines.
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


// -----------------------------------------------------------------------------
// Parameter helpers
// -----------------------------------------------------------------------------

// Build a Python signature parameter list, e.g.
//   "a: int, b: int"
// When a parameter name is empty, a synthetic name pN is used.
function BuildPyParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    T := ABI_Type_To_Py_Annotation(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + ': ' + T;
  end;
end;

// Build a Python comma-separated argument list, e.g. "a, b".
function BuildPyArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;


// -----------------------------------------------------------------------------
// Supported-function filtering
// -----------------------------------------------------------------------------

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
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"', [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type', [f.Name.Text, f.ReturnType.Text]));
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


// -----------------------------------------------------------------------------
// Static scaffolding blocks
// -----------------------------------------------------------------------------

procedure EmitHeader(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('"""');
  Lines.Add('Auto-generated by py_abi_service_generator_tool.');
  Lines.Add('');
  Lines.Add('Source model unit: ' + UnitName.Text + '.');
  Lines.Add('');
  Lines.Add('LingoFuse ABI service provider.');
  Lines.Add('');
  Lines.Add('Wire protocol (both directions):');
  Lines.Add('    request  = [field1][field2]...[fieldN]');
  Lines.Add('    response = [status:UInt8][payload]');
  Lines.Add('        status = 0x00 -> success; payload is the serialised result');
  Lines.Add('                         (functions) or empty (procedures).');
  Lines.Add('        status = 0xFF -> error; payload is a UTF-8 string message.');
  Lines.Add('');
  Lines.Add('This module can be run directly to start the service:');
  Lines.Add('    python ' + UnitName.Text + '_abi_service.py');
  Lines.Add('');
  Lines.Add('It can also be imported and wired up manually by a host program.');
  Lines.Add('The user is expected to:');
  Lines.Add('    1. Fill in each internal_call_<api> stub with a call to the');
  Lines.Add('       real Python function.');
  Lines.Add('    2. Either run the module directly, or follow the standard');
  Lines.Add('       LingoFuse service setup shown below:');
  Lines.Add('');
  Lines.Add('           from lingofuse._lf_native import (');
  Lines.Add('               LF_ResetPrepare, LF_PrepareService,');
  Lines.Add('               LF_PrepareClient, LF_PrepareDone,');
  Lines.Add('               LF_ExitMainThread, LF_FreeApp, LF_Shutdown,');
  Lines.Add('           )');
  Lines.Add('           from lingofuse.lf_io import cstr');
  Lines.Add('           import this_module');
  Lines.Add('');
  Lines.Add('           LF_ResetPrepare()');
  Lines.Add('           LF_PrepareService(cstr("ipc:my_unit_abi"),');
  Lines.Add('                             cstr("ipc:my_unit_abi"))');
  Lines.Add('           app = this_module.CreateAndRegisterABIApp()');
  Lines.Add('           LF_PrepareClient(cstr("ipc:my_unit_abi"), app)');
  Lines.Add('           if LF_PrepareDone() != 1:');
  Lines.Add('               raise SystemExit(1)');
  Lines.Add('           try:');
  Lines.Add('               ...  # run the service');
  Lines.Add('           finally:');
  Lines.Add('               LF_ExitMainThread()');
  Lines.Add('               LF_FreeApp(app)');
  Lines.Add('               LF_Shutdown()');
  Lines.Add('"""');
  Lines.Add('');
  Lines.Add('import ctypes');
  Lines.Add('import struct');
  Lines.Add('');
  Lines.Add('from lingofuse._lf_native import (');
  Lines.Add('    AppHnd,');
  Lines.Add('    DataHnd,');
  Lines.Add('    LFCallFunc,');
  Lines.Add('    LF_CreateApp,');
  Lines.Add('    LF_FreeApp,');
  Lines.Add('    LF_RegisterCall,');
  Lines.Add('    LF_ReadBuffer,');
  Lines.Add('    LF_WriteBuffer,');
  Lines.Add('    LF_ResetPrepare,');
  Lines.Add('    LF_PrepareService,');
  Lines.Add('    LF_PrepareClient,');
  Lines.Add('    LF_PrepareDone,');
  Lines.Add('    LF_ExitMainThread,');
  Lines.Add('    LF_Shutdown,');
  Lines.Add(')');
  Lines.Add('from lingofuse.lf_io import (');
  Lines.Add('    cstr,');
  Lines.Add('    read_string as _lf_read_string,');
  Lines.Add('    write_string as _lf_write_string,');
  Lines.Add(')');
  Lines.Add('');
end;

procedure EmitConstants(Lines: TPascalStringList; const AppName, AppDesc: TP_String);
begin
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Application metadata');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('DEFAULT_APP_NAME = ' + PyStrLit(AppName) + '');
  Lines.Add('DEFAULT_APP_DESC = ' + PyStrLit(AppDesc) + '');
  Lines.Add('');
  Lines.Add('DEBUG_LOG = True');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Wire protocol constants');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('STATUS_OK = 0x00');
  Lines.Add('STATUS_ERROR = 0xFF');
  Lines.Add('');
end;

procedure EmitSerializationHelpers(Lines: TPascalStringList);
begin
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Serialisation helpers (little-endian, matching Pascal LF_WriteXxx)');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _read_exact(hnd, size):');
  Lines.Add('    """Read exactly `size` bytes from the handle."""');
  Lines.Add('    if size <= 0:');
  Lines.Add('        return b""');
  Lines.Add('    buf = (ctypes.c_byte * size)()');
  Lines.Add('    n = LF_ReadBuffer(hnd, buf, size)');
  Lines.Add('    if n != size:');
  Lines.Add('        raise IOError(');
  Lines.Add('            "input truncated: expected %d bytes, got %d" % (size, n)');
  Lines.Add('        )');
  Lines.Add('    return bytes(buf)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_exact(hnd, data):');
  Lines.Add('    """Write all bytes to the handle, raising on a short write."""');
  Lines.Add('    if not data:');
  Lines.Add('        return');
  Lines.Add('    n = LF_WriteBuffer(hnd, data, len(data))');
  Lines.Add('    if n != len(data):');
  Lines.Add('        raise IOError(');
  Lines.Add('            "output truncated: expected %d bytes, got %d"');
  Lines.Add('            % (len(data), n)');
  Lines.Add('        )');
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
  Lines.Add('    """Read a NUL-terminated UTF-8 string."""');
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
  Lines.Add('    """Write a UTF-8 string with a NUL terminator."""');
  Lines.Add('    _lf_write_string(hnd, v)');
  Lines.Add('');
end;

// -----------------------------------------------------------------------------
// Main block: makes the generated module runnable as a program.

// This block is emitted only once, at the very end of the module. It
// mirrors the standard LingoFuse service setup described in the module
// docstring and in the README.
//
// The README promises that the module is runnable as a program, so
// this block is what makes that promise true.
// -----------------------------------------------------------------------------

procedure EmitMainBlock(Lines: TPascalStringList);
begin
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Main entry point');
  Lines.Add('#');
  Lines.Add('# Running this module directly starts the service:');
  Lines.Add('#     python <this_file>.py');
  Lines.Add('#');
  Lines.Add('# The service stays alive until the user types "exit" and presses');
  Lines.Add('# Enter, or sends Ctrl+C / Ctrl+D.');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('if __name__ == "__main__":');
  Lines.Add('    import sys');
  Lines.Add('');
  Lines.Add('    print(f"=== {DEFAULT_APP_NAME} service ===")');
  Lines.Add('');
  Lines.Add('    _ep = cstr("ipc:" + DEFAULT_APP_NAME)');
  Lines.Add('');
  Lines.Add('    LF_ResetPrepare()');
  Lines.Add('    LF_PrepareService(_ep, _ep)');
  Lines.Add('');
  Lines.Add('    _app = CreateAndRegisterABIApp()');
  Lines.Add('    if not _app:');
  Lines.Add('        print("[FATAL] CreateAndRegisterABIApp failed")');
  Lines.Add('        sys.exit(1)');
  Lines.Add('');
  Lines.Add('    if LF_PrepareClient(_ep, _app) == -1:');
  Lines.Add('        print("[FATAL] LF_PrepareClient failed")');
  Lines.Add('        LF_FreeApp(_app)');
  Lines.Add('        sys.exit(1)');
  Lines.Add('');
  Lines.Add('    if LF_PrepareDone() != 1:');
  Lines.Add('        print("[FATAL] LF_PrepareDone failed")');
  Lines.Add('        LF_ExitMainThread()');
  Lines.Add('        LF_FreeApp(_app)');
  Lines.Add('        LF_Shutdown()');
  Lines.Add('        sys.exit(1)');
  Lines.Add('');
  Lines.Add('    print("[OK] Service ready. Type ''exit'' and press Enter to quit.")');
  Lines.Add('    try:');
  Lines.Add('        while True:');
  Lines.Add('            _line = input()');
  Lines.Add('            if _line.strip().lower() == "exit":');
  Lines.Add('                break');
  Lines.Add('    except (KeyboardInterrupt, EOFError):');
  Lines.Add('        pass');
  Lines.Add('');
  Lines.Add('    LF_ExitMainThread()');
  Lines.Add('    LF_FreeApp(_app)');
  Lines.Add('    LF_Shutdown()');
  Lines.Add('    print("[OK] Shutdown complete.")');
  Lines.Add('');
end;


// -----------------------------------------------------------------------------
// Main entry point
// -----------------------------------------------------------------------------

function GenerateABIServicePyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  Description: TP_String;
  PyParamList, PyArgList: TP_String;

  HeaderLines: TPascalStringList;
  ConstLines: TPascalStringList;
  SerializationLines: TPascalStringList;
  InternalCallLines: TPascalStringList;
  CallbackLines: TPascalStringList;
  RegistrationLines: TPascalStringList;
  ResultLines: TPascalStringList;
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

  Log(PFormat('Generating Python ABI service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  ConstLines := TPascalStringList.Create;
  SerializationLines := TPascalStringList.Create;
  InternalCallLines := TPascalStringList.Create;
  CallbackLines := TPascalStringList.Create;
  RegistrationLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // -------------------------------------------------------------------------
    // 1. Header (docstring + imports)
    // -------------------------------------------------------------------------
    EmitHeader(HeaderLines, UnitName);

    // -------------------------------------------------------------------------
    // 2. Application constants
    // -------------------------------------------------------------------------
    EmitConstants(ConstLines, AppName,
      'ABI service for ' + UnitName.Text);

    // -------------------------------------------------------------------------
    // 3. Serialisation helpers
    // -------------------------------------------------------------------------
    EmitSerializationHelpers(SerializationLines);

    // -------------------------------------------------------------------------
    // 4. internal_call_<api> stubs
    // -------------------------------------------------------------------------
    InternalCallLines.Add('');
    InternalCallLines.Add('# ----------------------------------------------------------------------');
    InternalCallLines.Add('# Internal call stubs. Each stub mirrors one original routine.');
    InternalCallLines.Add('# Replace the body with a call to the real Python function.');
    InternalCallLines.Add('# ----------------------------------------------------------------------');
    InternalCallLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        ApiName := MakePyIdent(ApiName, 'api_' + umlIntToStr(i), UsedApiNames);

        InternalCallName := 'internal_call_' + ApiName;
        PyParamList := BuildPyParamList(Params);
        PyArgList := BuildPyArgList(Params);

        if IsFunction then
          InternalCallLines.Add('def ' + InternalCallName + '(' + PyParamList + ') -> ' + ABI_Type_To_Py_Annotation(ReturnType) + ':')
        else
          InternalCallLines.Add('def ' + InternalCallName + '(' + PyParamList + ') -> None:');

        InternalCallLines.Add('    # TODO: call the real function, for example:');
        if IsFunction then
          InternalCallLines.Add('    #     return ' + Name.Text + '(' + PyArgList + ')')
        else
          InternalCallLines.Add('    #     ' + Name.Text + '(' + PyArgList + ')');
        if IsFunction then
          InternalCallLines.Add('    return ' + ABI_Type_Default(ReturnType))
        else
          InternalCallLines.Add('    return None');
        InternalCallLines.Add('');
        InternalCallLines.Add('');
      end;
    end;

    // -------------------------------------------------------------------------
    // 5. cdecl callbacks
    // -------------------------------------------------------------------------
    CallbackLines.Add('');
    CallbackLines.Add('# ----------------------------------------------------------------------');
    CallbackLines.Add('# cdecl callbacks (registered with LF_RegisterCall).');
    CallbackLines.Add('#');
    CallbackLines.Add('# Wire format:');
    CallbackLines.Add('#   request  = [field1][field2]...[fieldN]');
    CallbackLines.Add('#   response = [status:UInt8][payload]');
    CallbackLines.Add('#     status = 0x00 success; 0xFF error followed by a UTF-8');
    CallbackLines.Add('#     string written with NUL framing.');
    CallbackLines.Add('# ----------------------------------------------------------------------');
    CallbackLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        ApiName := MakePyIdent(ApiName, 'api_' + umlIntToStr(i), UsedApiNames);

        CallbackName := 'Callback_' + ApiName;
        InternalCallName := 'internal_call_' + ApiName;
        PyArgList := BuildPyArgList(Params);

        CallbackLines.Add('@LFCallFunc');
        CallbackLines.Add('def ' + CallbackName + '(_Trigger, _In, _Out):');

        // ---- The callback body. ----------------------------------------
        // Every line below uses 4-space indent for the "try:" statement
        // and 8-space indent for its body. There must be no draft
        // fragment before the "try:" line: Python requires that the
        // entire function body has a single, consistent indent level.

        CallbackLines.Add('    try:');

        // Deserialise parameters.
        for j := 0 to High(Params) do
        begin
          if Params[j].Name.Len = 0 then
            CallbackLines.Add('        p' + umlIntToStr(j).Text + ' = ' + ABI_Type_To_Py_Read_Func(Params[j].PascalType) + '(_In)')
          else
            CallbackLines.Add('        ' + Params[j].Name.Text + ' = ' + ABI_Type_To_Py_Read_Func(Params[j].PascalType) + '(_In)');
        end;

        // Invoke the internal stub.
        if IsFunction then
          CallbackLines.Add('        _ret = ' + InternalCallName + '(' + PyArgList + ')')
        else
          CallbackLines.Add('        ' + InternalCallName + '(' + PyArgList + ')');

        // Error path.
        CallbackLines.Add('    except Exception as _e:');
        CallbackLines.Add('        try:');
        CallbackLines.Add('            _write_uint8(_Out, STATUS_ERROR)');
        CallbackLines.Add('            _write_string(_Out, str(_e))');
        CallbackLines.Add('        except Exception:');
        CallbackLines.Add('            # Nothing more we can do.');
        CallbackLines.Add('            pass');
        CallbackLines.Add('        return');
        CallbackLines.Add('');

        // Success path.
        CallbackLines.Add('    try:');
        CallbackLines.Add('        _write_uint8(_Out, STATUS_OK)');
        if IsFunction then
          CallbackLines.Add('        ' + ABI_Type_To_Py_Write_Func(ReturnType) + '(_Out, _ret)');
        CallbackLines.Add('    except Exception:');
        CallbackLines.Add('        # Swallow the exception to avoid it escaping into the C stack.');
        CallbackLines.Add('        pass');
        CallbackLines.Add('');
        CallbackLines.Add('');
      end;
    end;

    // -------------------------------------------------------------------------
    // 6. Registration
    // -------------------------------------------------------------------------
    RegistrationLines.Add('');
    RegistrationLines.Add('# ----------------------------------------------------------------------');
    RegistrationLines.Add('# Registration');
    RegistrationLines.Add('# ----------------------------------------------------------------------');
    RegistrationLines.Add('');
    RegistrationLines.Add('def RegisterAllABIAPIs(app: AppHnd) -> None:');
    RegistrationLines.Add('    """Register every generated Call API on the given app."""');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        ApiName := MakePyIdent(ApiName, 'api_' + umlIntToStr(i), UsedApiNames);

        CallbackName := 'Callback_' + ApiName;
        Description := GetFullDescription(Comment);
        if Description.Len = 0 then
          Description := 'ABI api for ' + Name;

        RegistrationLines.Add('    LF_RegisterCall(');
        RegistrationLines.Add('        app,');
        RegistrationLines.Add('        cstr(' + PyStrLit(ApiName) + '),');
        RegistrationLines.Add('        cstr(' + PyStrLit(Description) + '),');
        RegistrationLines.Add('        None,');
        RegistrationLines.Add('        ' + CallbackName + ',');
        RegistrationLines.Add('    )');
      end;
    end;

    RegistrationLines.Add('');
    RegistrationLines.Add('');
    RegistrationLines.Add('def CreateAndRegisterABIApp() -> AppHnd:');
    RegistrationLines.Add('    """Create a new LingoFuse App and register every generated API.');
    RegistrationLines.Add('');
    RegistrationLines.Add('    The caller owns the returned handle and must call LF_FreeApp');
    RegistrationLines.Add('    on it before shutting the library down.');
    RegistrationLines.Add('    """');
    RegistrationLines.Add('    app = LF_CreateApp(cstr(DEFAULT_APP_NAME), cstr(DEFAULT_APP_DESC))');
    RegistrationLines.Add('    if app:');
    RegistrationLines.Add('        RegisterAllABIAPIs(app)');
    RegistrationLines.Add('    return app');
    RegistrationLines.Add('');

    // -------------------------------------------------------------------------
    // 7. Assemble
    //
    // The module is emitted as:
    //   [header]  [constants]  [serialisation helpers]
    //   [internal_call_ stubs] [callbacks] [registration]
    //   [__main__ block]
    //
    // The __main__ block is what makes the README's "runnable as a
    // program" promise true.
    // -------------------------------------------------------------------------
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(ConstLines);
    ResultLines.AddStrings(SerializationLines);
    ResultLines.AddStrings(InternalCallLines);
    ResultLines.AddStrings(CallbackLines);
    ResultLines.AddStrings(RegistrationLines);
    EmitMainBlock(ResultLines);

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.', [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    ConstLines.Free;
    SerializationLines.Free;
    InternalCallLines.Free;
    CallbackLines.Free;
    RegistrationLines.Free;
    UsedApiNames.Free;
    // ResultLines is returned to the caller; not freed here.
  end;
end;

// =============================================================================
// SECTION 2 - README generator
// =============================================================================
//
// This section is self-contained. It depends only on the helpers already
// present in this unit (MakeApiName, ABI_Type_To_Py_Annotation,
// ABI_Type_To_Py_Read_Func, ABI_Type_To_Py_Write_Func,
// CollectSupportedFunctions, GetFullDescription, PyStrLit) plus the
// standard Z-framework units already in scope.
//
// The README is organised into twelve sections:
//
//   §1  Overview
//   §2  Application scope
//   §3  Compatibility (Python version, platform, dependencies)
//   §4  Wire protocol
//   §5  Runtime architecture
//   §6  Type mapping
//   §7  Deployment
//   §8  Testing
//   §9  API reference
//   §10 Troubleshooting
//   §11 Self-assessment checklist
//   §12 Reference resources
//
// The document is written so that both human readers and AI assistants
// can learn the Python service module's usage model from the README
// alone.
// =============================================================================

// Returns the "wire size" column text for the ABI type table.
function PyReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '1 byte'
  else if ABI_Type.Same('word') or ABI_Type.Same('smallint') then
    Result := '2 bytes'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or ABI_Type.Same('longword') or ABI_Type.Same('integer') or
    ABI_Type.Same('longint') or ABI_Type.Same('single') then
    Result := '4 bytes'
  else if ABI_Type.Same('int64') or ABI_Type.Same('uint64') or ABI_Type.Same('double') or ABI_Type.Same('extended') or ABI_Type.Same('real') then
    Result := '8 bytes'
  else if ABI_Type.Same('string') or ABI_Type.Same('ansistring') or ABI_Type.Same('unicodestring') or ABI_Type.Same('tpascalstring') or
    ABI_Type.Same('tupascalstring') or ABI_Type.Same('tp_string') or ABI_Type.Same('pchar') or ABI_Type.Same('pansichar') or ABI_Type.Same('pwidechar') then
    Result := 'variable + NUL'
  else
    Result := 'unknown';
end;

// Returns the "struct format" column text for the ABI type table.
function PyReadmeStructFormat(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '`<B`'
  else if ABI_Type.Same('word') then
    Result := '`<H`'
  else if ABI_Type.Same('smallint') then
    Result := '`<h`'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or ABI_Type.Same('longword') then
    Result := '`<I`'
  else if ABI_Type.Same('integer') or ABI_Type.Same('longint') then
    Result := '`<i`'
  else if ABI_Type.Same('int64') then
    Result := '`<q`'
  else if ABI_Type.Same('uint64') then
    Result := '`<Q`'
  else if ABI_Type.Same('single') then
    Result := '`<f`'
  else if ABI_Type.Same('double') or ABI_Type.Same('extended') or ABI_Type.Same('real') then
    Result := '`<d`'
  else if ABI_Type.Same('string') or ABI_Type.Same('ansistring') or ABI_Type.Same('unicodestring') or ABI_Type.Same('tpascalstring') or
    ABI_Type.Same('tupascalstring') or ABI_Type.Same('tp_string') or ABI_Type.Same('pchar') or ABI_Type.Same('pansichar') or ABI_Type.Same('pwidechar') then
    Result := '`_lf_write_string`'
  else
    Result := '?';
end;

// Sanitise a description for use inside a Markdown table cell.
function PyReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// Sanitise a description for use as standalone paragraph text.
function PyReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

// Build the README for a given model.
function GenerateABIServicePyReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;

// ---------------------------------------------------------------------------
// §1. Header
// ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - Python ABI Service Provider');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `py_abi_service_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Service module**    : `' + UnitName + '_abi_service.py`');
    L.Add('> **Default App name**  : `' + AppName + '`');
    L.Add('> **Exposed APIs**      : ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> deploy, test, or call this service without reading the source.');
    L.Add('');
    L.Add('---');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §2. Overview
  // ---------------------------------------------------------------------------
  procedure EmitOverview;
  begin
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('This document describes the **Python ABI service module** that was');
    L.Add('generated from the Pascal unit `' + UnitName + '`. The module is a');
    L.Add('strongly-typed, binary-wire RPC endpoint built on top of LingoFuse,');
    L.Add('written in pure Python 3 and calling the LingoFuse C ABI through');
    L.Add('`ctypes`.');
    L.Add('');
    L.Add('### 1.1 What is an ABI service?');
    L.Add('');
    L.Add('An ABI service is a LingoFuse endpoint that:');
    L.Add('');
    L.Add('- exposes one or more routines as remotely callable APIs;');
    L.Add('- uses a **compact binary wire protocol** in both directions;');
    L.Add('- binds every API to a **fixed, statically-typed signature**;');
    L.Add('- requires a **matching call-side client** to invoke. The call-side');
    L.Add('  client can be generated by the paired Pascal, Python, or C++');
    L.Add('  generator from the same model.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Discovery | Direct by App name on LingoFuse |');
    L.Add('| Client | Must be paired (generated from the same model) |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Implementation | Pure Python 3 + ctypes |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Install** the `lingofuse` Python package. See §3.3.');
    L.Add('2. **Implement** each `internal_call_*` stub. See §7.1.');
    L.Add('3. **Run** the module as a program. See §8.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + UnitName + '_abi_service.py` | The service module (runnable as-is). |');
    L.Add('| `' + UnitName + '_abi_service_python.md` | This README. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use a Python ABI service');
    L.Add('');
    L.Add('Use this generator when:');
    L.Add('');
    L.Add('- You have a **fixed set of Python functions** with stable signatures.');
    L.Add('- Your callers are **known in advance** (you control both sides).');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- Real-time data pipelines written in Python.');
    L.Add('- Local IPC between a Python service and a Pascal / C++ client.');
    L.Add('- Internal micro-services in a controlled deployment.');
    L.Add('- Python glue code calling into a native engine through LingoFuse.');
    L.Add('');
    L.Add('### 2.2 When NOT to use a Python ABI service');
    L.Add('');
    L.Add('- The API surface changes frequently: regenerate the whole chain.');
    L.Add('- Callers need to discover the API surface dynamically at runtime.');
    L.Add('- Parameters include complex types (dicts, lists, custom objects).');
    L.Add('- The service must be reachable by arbitrary third-party clients.');
    L.Add('- The service must support multiple versions of a signature at once.');
    L.Add('');
    L.Add('### 2.3 Comparison with other RPC approaches');
    L.Add('');
    L.Add('| Approach | Typed | Binary | Self-describing | Paired client |');
    L.Add('|----------|:-----:|:------:|:---------------:|:-------------:|');
    L.Add('| This ABI service | yes | yes | no | yes (required) |');
    L.Add('| gRPC | yes | yes | yes (proto) | yes (generated) |');
    L.Add('| REST + JSON | no | no | yes | no |');
    L.Add('| Raw TCP sockets | no | yes | no | yes |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §4. Compatibility
  // ---------------------------------------------------------------------------
  procedure EmitCompatibility;
  begin
    L.Add('## 3. Compatibility');
    L.Add('');
    L.Add('### 3.1 Python version support');
    L.Add('');
    L.Add('| Python | Status |');
    L.Add('|--------|--------|');
    L.Add('| 3.8 | Minimum supported |');
    L.Add('| 3.9 | Supported |');
    L.Add('| 3.10 | Supported |');
    L.Add('| 3.11 | Recommended |');
    L.Add('| 3.12 | Supported |');
    L.Add('');
    L.Add('Python 2 is **not supported**. The generated module uses f-strings,');
    L.Add('type annotations, and other features that require Python 3.8+.');
    L.Add('');
    L.Add('### 3.2 Platform support');
    L.Add('');
    L.Add('The generated module is pure Python; platform support is');
    L.Add('determined by the LingoFuse runtime and the `lingofuse` Python');
    L.Add('package.');
    L.Add('');
    L.Add('| Platform | Architecture | Status |');
    L.Add('|----------|-------------|--------|');
    L.Add('| Windows | x86_64 | Primary target |');
    L.Add('| Linux | x86_64 | Supported |');
    L.Add('| Linux | aarch64 | Supported |');
    L.Add('| macOS | x86_64 | Supported |');
    L.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    L.Add('');
    L.Add('**Byte order note**: the ABI wire format is little-endian. Every');
    L.Add('platform listed above is little-endian, so the generated module');
    L.Add('never performs byte swapping. Big-endian platforms are **not');
    L.Add('supported**.');
    L.Add('');
    L.Add('### 3.3 Python package dependencies');
    L.Add('');
    L.Add('The generated module imports from `lingofuse._lf_native` and');
    L.Add('`lingofuse.lf_io`. Two sources for that package are supported, in');
    L.Add('order of preference:');
    L.Add('');
    L.Add('| # | Source | When to use | How to get it |');
    L.Add('|---|--------|-------------|---------------|');
    L.Add('| **1** | Standalone `py-lingofuse` repository or PyPI package | If one exists for your deployment | `pip install py-lingofuse` |');
    L.Add('| **2** | `lingofuse/` directory shipped inside LingoFuse-pasAgent-v3 | Fallback | Point `PYTHONPATH` at `<v3>/src` |');
    L.Add('');
    L.Add('### 3.4 Runtime dependencies');
    L.Add('');
    L.Add('| Dependency | Where to get it |');
    L.Add('|------------|----------------|');
    L.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    L.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | ZNetV2 binary distribution |');
    L.Add('| `lingofuse` Python package | See §3.3 |');
    L.Add('');
    L.Add('### 3.5 Character encoding');
    L.Add('');
    L.Add('- **Source files**: UTF-8, no BOM required. The first line is');
    L.Add('  `# -*- coding: utf-8 -*-`.');
    L.Add('- **String payloads**: UTF-8 followed by a single `\\x00` terminator.');
    L.Add('- All strings are `str` (Python 3 Unicode); no manual encoding is');
    L.Add('  required in user code.');
    L.Add('');
    L.Add('### 3.6 Threading model');
    L.Add('');
    L.Add('Callbacks are invoked from a LingoFuse worker thread, not the');
    L.Add('Python main thread. The GIL serialises execution, so Python code');
    L.Add('inside a callback runs on one thread at a time. Long-running');
    L.Add('callbacks block other callbacks; keep them short or offload work');
    L.Add('to a `threading.Thread`.');
    L.Add('');
    L.Add('**Do not call any blocking LingoFuse function inside a callback.**');
    L.Add('Doing so deadlocks the calling worker thread.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The ABI service uses a minimal, fixed binary wire format on both');
    L.Add('directions.');
    L.Add('');
    L.Add('### 4.1 Request');
    L.Add('');
    L.Add('```');
    L.Add('request = [field1][field2]...[fieldN]');
    L.Add('```');
    L.Add('');
    L.Add('Fields are serialised in the **exact order** in which they appear');
    L.Add('in the original Pascal declaration. There is no header, no length');
    L.Add('prefix, and no field tag: the receiver must know the signature to');
    L.Add('parse the payload.');
    L.Add('');
    L.Add('### 4.2 Response');
    L.Add('');
    L.Add('```');
    L.Add('response = [status:UInt8][payload]');
    L.Add('```');
    L.Add('');
    L.Add('The first byte is a status code:');
    L.Add('');
    L.Add('| Status | Meaning | Payload |');
    L.Add('|--------|---------|---------|');
    L.Add('| `0x00` | Success | Serialised result (functions) or empty (procedures). |');
    L.Add('| `0xFF` | Error   | UTF-8 message, terminated by `\\x00`. |');
    L.Add('');
    L.Add('### 4.3 Encoding rules');
    L.Add('');
    L.Add('| Rule | Value |');
    L.Add('|------|-------|');
    L.Add('| Byte order | Little-endian |');
    L.Add('| Integer | `struct.pack("<i", v)` etc. |');
    L.Add('| Float | `struct.pack("<d", v)` etc. |');
    L.Add('| String | UTF-8 bytes terminated by a single `\\x00` |');
    L.Add('| Boolean | Not supported |');
    L.Add('| dict / list | Not supported |');
    L.Add('');
    L.Add('### 4.4 Call sequence');
    L.Add('');
    L.Add('```mermaid');
    L.Add('sequenceDiagram');
    L.Add('    participant C as Client');
    L.Add('    participant S as Python service');
    L.Add('    C->>C: pack fields (little-endian)');
    L.Add('    C->>S: LF_CallEx(payload)');
    L.Add('    S->>S: _read_int32 / _read_string / ...');
    L.Add('    S->>S: internal_call_xxx(a, b)');
    L.Add('    S->>S: _write_uint8(0x00)');
    L.Add('    S->>S: _write_xxx(result)');
    L.Add('    S-->>C: response');
    L.Add('    C->>C: unpack status + result');
    L.Add('```');
    L.Add('');
    L.Add('### 4.5 Error response example');
    L.Add('');
    L.Add('Bytes on the wire:');
    L.Add('');
    L.Add('```');
    L.Add('FF                                  <- status = 0xFF');
    L.Add('72 65 61 64 20 66 61 69 6C 65 64    <- "read failed" (UTF-8)');
    L.Add('00                                  <- NUL terminator');
    L.Add('```');
    L.Add('');
    L.Add('The call side raises the corresponding exception and inspects the');
    L.Add('decoded message.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §6. Runtime architecture
  // ---------------------------------------------------------------------------
  procedure EmitRuntimeArchitecture;
  begin
    L.Add('## 5. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph PyService["Python service process"]');
    L.Add('        P_INIT["import ' + UnitName + '_abi_service"]');
    L.Add('        P_APP["CreateAndRegisterABIApp()<br/>creates the App and registers every API"]');
    L.Add('        P_SVC["LF_PrepareService(&#39;ipc:&lt;unit&gt;_abi&#39;)"]');
    L.Add('        P_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, app)"]');
    L.Add('        P_RUN["LF_PrepareDone()"]');
    L.Add('        P_CBK["@LFCallFunc callbacks"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["Client process (external)"]');
    L.Add('        C_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, nil)"]');
    L.Add('        C_RUN["LF_PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;ApiName&gt;(args)"]');
    L.Add('    end');
    L.Add('');
    L.Add('    P_INIT --> P_APP --> P_SVC --> P_CLI --> P_RUN');
    L.Add('    P_RUN --> P_CBK');
    L.Add('    C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "LF_CallEx over IPC" .-> P_CBK');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (Python service)');
    L.Add('');
    L.Add('1. `import ' + UnitName + '_abi_service` (or run the module as a');
    L.Add('   program; see §8).');
    L.Add('2. `LF_ResetPrepare()`');
    L.Add('3. `LF_PrepareService(cstr(ep), cstr(ep))` where `ep = ''ipc:' + AppName + '''`');
    L.Add('4. `app = CreateAndRegisterABIApp()`');
    L.Add('5. `LF_PrepareClient(cstr(ep), app)`');
    L.Add('6. `LF_PrepareDone()`');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The client serialises the parameters and calls `LF_CallEx`.');
    L.Add('2. LingoFuse routes the payload to the Python callback decorated');
    L.Add('   with `@LFCallFunc`.');
    L.Add('3. The callback deserialises the parameters with `_read_xxx`.');
    L.Add('4. It calls the internal `internal_call_<Api>` stub.');
    L.Add('5. The stub runs the real Python body.');
    L.Add('6. The callback writes `0x00` followed by the serialised result.');
    L.Add('7. On any exception, the callback writes `0xFF` followed by the');
    L.Add('   UTF-8 error message.');
    L.Add('');
    L.Add('### 5.3 Threading notes');
    L.Add('');
    L.Add('- Callbacks execute on a LingoFuse worker thread.');
    L.Add('- The Python GIL serialises Python code, so callbacks effectively');
    L.Add('  run one at a time.');
    L.Add('- Long-running callbacks block other callbacks: keep them short.');
    L.Add('- Do not call `LF_Call` / `LF_Notify` from inside a callback.');
    L.Add('- Do not touch the main thread''s UI or event loop directly.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §7. Type mapping
  // ---------------------------------------------------------------------------
  procedure EmitTypeMapping;
  begin
    L.Add('## 6. Type Mapping');
    L.Add('');
    L.Add('### 6.1 Supported types');
    L.Add('');
    L.Add('Every parameter and return type of every exposed API must be in');
    L.Add('this table. Any other type causes the **entire routine** to be');
    L.Add('silently dropped during generation.');
    L.Add('');
    L.Add('| ABI type | Python type | struct format | Wire size |');
    L.Add('|----------|-------------|---------------|-----------|');
    L.Add('| `integer` | `int` | `<i` | 4 bytes |');
    L.Add('| `longint` | `int` | `<i` | 4 bytes |');
    L.Add('| `int64` | `int` | `<q` | 8 bytes |');
    L.Add('| `cardinal` | `int` | `<I` | 4 bytes |');
    L.Add('| `dword` | `int` | `<I` | 4 bytes |');
    L.Add('| `longword` | `int` | `<I` | 4 bytes |');
    L.Add('| `word` | `int` | `<H` | 2 bytes |');
    L.Add('| `smallint` | `int` | `<h` | 2 bytes |');
    L.Add('| `byte` | `int` | `<B` | 1 byte |');
    L.Add('| `uint64` | `int` | `<Q` | 8 bytes |');
    L.Add('| `double` | `float` | `<d` | 8 bytes |');
    L.Add('| `single` | `float` | `<f` | 4 bytes |');
    L.Add('| `extended` | `float` | `<d` | 8 bytes |');
    L.Add('| `real` | `float` | `<d` | 8 bytes |');
    L.Add('| `string` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `ansistring` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `unicodestring` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `tpascalstring` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `tupascalstring` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `tp_string` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `pchar` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `pansichar` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('| `pwidechar` | `str` | `_lf_write_string` | variable + NUL |');
    L.Add('');
    L.Add('### 6.2 Unsupported types');
    L.Add('');
    L.Add('Anything not in §6.1 causes the **entire routine** to be silently');
    L.Add('dropped during generation. Common examples:');
    L.Add('');
    L.Add('- `bool`');
    L.Add('- `dict`, `list`, `tuple`, `set`');
    L.Add('- Custom classes and dataclasses');
    L.Add('- `bytes`, `bytearray`');
    L.Add('- `datetime`, `decimal.Decimal`');
    L.Add('');
    L.Add('**Workaround**: serialise complex values into a `str` first');
    L.Add('(JSON or a custom format), then pass the string across the ABI');
    L.Add('boundary. On the call side, deserialise the string back into the');
    L.Add('rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The ABI wire format uses little-endian for all integers and');
    L.Add('floats. Every platform listed in §3.2 is little-endian, so the');
    L.Add('generated module never performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('The generated module uses `lingofuse.lf_io.write_string` and');
    L.Add('`lingofuse.lf_io.read_string` for string parameters and return');
    L.Add('values. `write_string` always appends a single `\\x00` byte after');
    L.Add('the UTF-8 payload. `read_string` scans forward until it finds that');
    L.Add('byte. A mismatch (missing NUL) causes the reader to consume the');
    L.Add('rest of the payload.');
    L.Add('');
    L.Add('**Recommendation**: always use the provided helpers. Do not');
    L.Add('hand-roll the string encoding.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §8. Deployment
  // ---------------------------------------------------------------------------
  procedure EmitDeployment;
  begin
    L.Add('## 7. Deployment');
    L.Add('');
    L.Add('### 7.1 Directory layout');
    L.Add('');
    L.Add('```');
    L.Add('my_abi_service/');
    L.Add('  ' + UnitName + '_abi_service.py            <- generated (described here)');
    L.Add('  ' + UnitName + '_abi_call_unit.pas         <- generated by pas_abi_call_generator_tool (optional)');
    L.Add('  ' + UnitName + '_client.py                 <- your Python client entry point (optional)');
    L.Add('  ZNetV2/');
    L.Add('    z_ipc_64.dll                              <- Windows');
    L.Add('    libz_ipc_64.so                            <- Linux');
    L.Add('  LingoFuse64.dll                             <- Windows');
    L.Add('  liblingofuse.so                             <- Linux');
    L.Add('  liblingofuse.dylib                          <- macOS');
    L.Add('```');
    L.Add('');
    L.Add('The `lingofuse` Python package must be importable (see §3.3).');
    L.Add('');
    L.Add('### 7.2 Implementing the internal_call_* stubs');
    L.Add('');
    L.Add('Every exposed API has a matching stub in the generated module:');
    L.Add('');
    L.Add('```python');
    L.Add('def internal_call_<Api>(<params>) -> <ret>:');
    L.Add('    # TODO: call the real function, for example:');
    L.Add('    #     return my_engine.<real_func>(<args>)');
    L.Add('    return <default>');
    L.Add('```');
    L.Add('');
    L.Add('Replace the placeholder body with a call to the real function.');
    L.Add('The signature is already correct: keep the parameter names and the');
    L.Add('return type annotation.');
    L.Add('');
    L.Add('### 7.3 Python build');
    L.Add('');
    L.Add('Syntax check:');
    L.Add('');
    L.Add('```bash');
    L.Add('python -m py_compile ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('Run as a program (see §8):');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('### 7.4 Setting PYTHONPATH for the fallback lingofuse package');
    L.Add('');
    L.Add('**Windows (cmd):**');
    L.Add('');
    L.Add('```bat');
    L.Add('set PYTHONPATH=D:\\LingoFuse-pasAgent-v3\\src');
    L.Add('python ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (PowerShell):**');
    L.Add('');
    L.Add('```powershell');
    L.Add('$env:PYTHONPATH = "D:\\LingoFuse-pasAgent-v3\\src"');
    L.Add('python ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('**Linux / macOS:**');
    L.Add('');
    L.Add('```bash');
    L.Add('export PYTHONPATH=/path/to/LingoFuse-pasAgent-v3/src');
    L.Add('python ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('### 7.5 Runtime files');
    L.Add('');
    L.Add('At runtime the following files must be reachable from the process:');
    L.Add('');
    L.Add('| File | Where to place it |');
    L.Add('|------|-------------------|');
    L.Add('| `LingoFuse64.dll` / `liblingofuse.so` | Same directory as the Python script, or on `PATH` / `LD_LIBRARY_PATH`. |');
    L.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | Same as above. |');
    L.Add('');
    L.Add('### 7.6 Shutdown');
    L.Add('');
    L.Add('The recommended shutdown sequence is:');
    L.Add('');
    L.Add('1. `LF_ExitMainThread()`');
    L.Add('2. `LF_FreeApp(app)`');
    L.Add('3. `LF_Shutdown()`');
    L.Add('');
    L.Add('The generated `__main__` block performs this sequence automatically');
    L.Add('(see §8.1).');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Testing
  // ---------------------------------------------------------------------------
  procedure EmitTesting;
  begin
    L.Add('## 8. Testing');
    L.Add('');
    L.Add('The generated module is **already runnable as a program**: it');
    L.Add('contains a full `if __name__ == "__main__":` block that starts the');
    L.Add('service and keeps it alive until the user types `exit`.');
    L.Add('');
    L.Add('### 8.1 Running the built-in test');
    L.Add('');
    L.Add('Open a terminal:');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName + ' service ===');
    L.Add('[OK] Service ready. Type ''exit'' and press Enter to quit.');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Writing a Python client');
    L.Add('');
    L.Add('The matching Python call-side module can be generated by');
    L.Add('`py_abi_call_generator_tool`. It exposes one free function per API');
    L.Add('with the same signature, and uses `LF_Call` internally.');
    L.Add('');
    L.Add('A minimal client looks like:');
    L.Add('');
    L.Add('```python');
    L.Add('from lingofuse._lf_native import (');
    L.Add('    LF_ResetPrepare, LF_PrepareClient, LF_PrepareDone,');
    L.Add('    LF_ExitMainThread, LF_Shutdown,');
    L.Add(')');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('import ' + UnitName + '_abi_call');
    L.Add('');
    L.Add('LF_ResetPrepare()');
    L.Add('LF_PrepareClient(cstr(''ipc:' + AppName + '''), None)');
    L.Add('if LF_PrepareDone() != 1:');
    L.Add('    raise SystemExit(1)');
    L.Add('try:');
    L.Add('    print(' + UnitName + '_abi_call.<ApiName>(...))');
    L.Add('finally:');
    L.Add('    LF_ExitMainThread()');
    L.Add('    LF_Shutdown()');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Running the pair of programs');
    L.Add('');
    L.Add('Open two terminals.');
    L.Add('');
    L.Add('**Terminal 1 (service):**');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_abi_service.py');
    L.Add('```');
    L.Add('');
    L.Add('Wait for `[OK] Service ready.`');
    L.Add('');
    L.Add('**Terminal 2 (client):**');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_client.py');
    L.Add('```');
    L.Add('');
    L.Add('### 8.4 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path, make a call with a deliberately');
    L.Add('truncated payload (for example, pass an empty string where a');
    L.Add('non-empty value is expected). The service returns `0xFF` and the');
    L.Add('client raises the corresponding exception.');
    L.Add('');
    L.Add('### 8.5 Unit-level testing');
    L.Add('');
    L.Add('To test the serialisation helpers without a LingoFuse deployment,');
    L.Add('import the internal helpers and call them directly:');
    L.Add('');
    L.Add('```python');
    L.Add('from lingofuse._lf_native import LF_CreateData, LF_FreeData');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('import ' + UnitName + '_abi_service as svc');
    L.Add('');
    L.Add('hnd = LF_CreateData(cstr(''<ApiName>''))');
    L.Add('try:');
    L.Add('    svc._write_int32(hnd, 42)');
    L.Add('    svc._write_string(hnd, "hello")');
    L.Add('    # Now inspect the raw bytes with LF_GetBuffer + ctypes');
    L.Add('finally:');
    L.Add('    LF_FreeData(hnd)');
    L.Add('```');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §10. API reference
  // ---------------------------------------------------------------------------
  procedure EmitApiReference;
  var
    ii, jj: integer;
    Func: TFunctionStructure;
    FuncDesc: TP_String;
    ShortDesc: TP_String;
    ApiNm: TP_String;
    RowStr: TP_String;
    DeclLine: TP_String;
    PName: TP_String;
    RetDecl: TP_String;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this service exposes no APIs.**');
      L.Add('>');
      L.Add('> Possible reasons:');
      L.Add('>');
      L.Add('> 1. The source unit has no top-level routines.');
      L.Add('> 2. Every routine failed the ABI type check.');
      L.Add('>');
      L.Add('> Supported types are listed in §6.1.');
      L.Add('');
      Exit;
    end;

    L.Add('Total APIs: **' + umlIntToStr(Length(SupportedFuncs)).Text + '**.');
    L.Add('');
    L.Add('Every API is exposed as a LingoFuse Call API with the same name.');
    L.Add('The `@LFCallFunc`-decorated callback is registered automatically by');
    L.Add('`RegisterAllABIAPIs`.');
    L.Add('');

    // ---- Summary table ---------------------------------------------------
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');

    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      ShortDesc := PyReadmeTableCell(GetFullDescription(Func.Comment));
      if ShortDesc.Len > 60 then
        ShortDesc := ShortDesc.GetString(1, 61) + '...';

      if Func.IsFunction then
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | function | ' + umlIntToStr(Length(Func.Params)).Text +
          ' | `' + ABI_Type_To_Py_Annotation(Func.ReturnType) + '` | ' + ShortDesc + ' |'
      else
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | procedure | ' + umlIntToStr(Length(Func.Params)).Text + ' | - | ' + ShortDesc + ' |';
      L.Add(RowStr);
    end;

    L.Add('');

    // ---- Per-API details -------------------------------------------------
    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      FuncDesc := PyReadmeParagraph(GetFullDescription(Func.Comment));

      // Build the reconstructed stub declaration.
      DeclLine := 'def internal_call_' + ApiNm + '(';
      for jj := 0 to High(Func.Params) do
      begin
        if jj > 0 then
          DeclLine := DeclLine + ', ';
        PName := Func.Params[jj].Name.Text;
        if PName = '' then
          PName := 'p' + umlIntToStr(jj).Text;
        DeclLine := DeclLine + PName + ': ' + ABI_Type_To_Py_Annotation(Func.Params[jj].PascalType);
      end;
      DeclLine := DeclLine + ')';
      if Func.IsFunction then
      begin
        RetDecl := ABI_Type_To_Py_Annotation(Func.ReturnType);
        DeclLine := DeclLine + ' -> ' + RetDecl;
      end
      else
        DeclLine := DeclLine + ' -> None';
      DeclLine := DeclLine + ':';

      L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
      L.Add('');
      L.Add('- **Registered API name**: `' + ApiNm + '`');
      L.Add('- **Python stub**: `' + DeclLine + '`');
      if Func.IsFunction then
        L.Add('- **Kind**: function; returns `' + ABI_Type_To_Py_Annotation(Func.ReturnType) + '`')
      else
        L.Add('- **Kind**: procedure');
      L.Add('');

      if FuncDesc.Len > 0 then
      begin
        L.Add('#### Description');
        L.Add('');
        L.Add(FuncDesc);
        L.Add('');
      end;

      // Parameters table
      if Length(Func.Params) > 0 then
      begin
        L.Add('#### Parameters');
        L.Add('');
        L.Add('| # | Name | Python type | ABI type | Reader | Wire size |');
        L.Add('|---|------|-------------|----------|--------|-----------|');
        for jj := 0 to High(Func.Params) do
        begin
          PName := Func.Params[jj].Name.Text;
          if PName = '' then
            PName := 'p' + umlIntToStr(jj).Text;
          RowStr := '| ' + umlIntToStr(jj + 1).Text + ' | `' + PName + '`' + ' | `' + ABI_Type_To_Py_Annotation(Func.Params[jj].PascalType) +
            '`' + ' | `' + Func.Params[jj].PascalType + '`' + ' | `' + ABI_Type_To_Py_Read_Func(Func.Params[jj].PascalType) +
            '`' + ' | ' + PyReadmeWireSizeText(Func.Params[jj].PascalType) + ' |';
          L.Add(RowStr);
        end;
        L.Add('');
      end;

      // Request layout
      L.Add('#### Request layout');
      L.Add('');
      L.Add('```');
      if Length(Func.Params) = 0 then
        L.Add('(empty payload)')
      else
      begin
        RowStr := '';
        for jj := 0 to High(Func.Params) do
        begin
          PName := Func.Params[jj].Name.Text;
          if PName = '' then
            PName := 'p' + umlIntToStr(jj).Text;
          if RowStr <> '' then
            RowStr := RowStr + ' ';
          RowStr := RowStr + '[' + PName + ': ' + Func.Params[jj].PascalType + ']';
        end;
        L.Add(RowStr);
      end;
      L.Add('```');
      L.Add('');

      // Success response layout
      L.Add('#### Success response layout');
      L.Add('');
      L.Add('```');
      if Func.IsFunction then
        L.Add('[0x00] [result: ' + ABI_Type_To_Py_Annotation(Func.ReturnType) + ']')
      else
        L.Add('[0x00]');
      L.Add('```');
      L.Add('');

      // Error response
      L.Add('#### Error response');
      L.Add('');
      L.Add('`0xFF` followed by a UTF-8 message terminated by `\\x00`. The');
      L.Add('call side raises the corresponding exception with the decoded');
      L.Add('message.');
      L.Add('');

      L.Add('---');
      L.Add('');
    end;
  end;

  // ---------------------------------------------------------------------------
  // §11. Troubleshooting
  // ---------------------------------------------------------------------------
  procedure EmitTroubleshooting;
  begin
    L.Add('## 10. Troubleshooting');
    L.Add('');
    L.Add('### 10.1 Symptom, cause, fix');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `ModuleNotFoundError: lingofuse` | Package not installed | See §3.3. |');
    L.Add('| `ModuleNotFoundError: lingofuse._lf_native` | Partial install | Reinstall, or point `PYTHONPATH` at `<v3>/src`. |');
    L.Add('| `OSError: cannot load library LingoFuse64.dll` | Native library not on `PATH` | Copy `z_ipc_*.dll` / `LingoFuse*.dll` next to your script. |');
    L.Add('| `LF_PrepareDone` returns 0 | Service already running in this process | Reuse the existing runtime, or call `LF_Shutdown` first. |');
    L.Add('| Client `LF_PrepareDone` returns 0 | Python service not running | Start the Python service first. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | App name mismatch | Check the client target and `DEFAULT_APP_NAME`. |');
    L.Add('| `EABI_RemoteError: "input truncated"` | Fewer fields than expected | Verify the client writes every parameter. |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| String parameters read as empty | Missing NUL terminator | Use `_lf_write_string` on the writer side. |');
    L.Add('| Callback never fires | `internal_call_*` stub not filled | Search for `TODO` in the service module. |');
    L.Add('| Callback raises an exception | User code raised | The callback swallows it and returns `0xFF` with the message. |');
    L.Add('| UI update crashes the service | Worker thread touching UI | Offload UI updates to the main thread. |');
    L.Add('');
    L.Add('### 10.2 Verifying a running service');
    L.Add('');
    L.Add('From the client process, before making a call:');
    L.Add('');
    L.Add('```python');
    L.Add('from lingofuse._lf_native import LF_CheckMainThread, LF_CheckApp');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('');
    L.Add('if LF_CheckMainThread() == 0:');
    L.Add('    print("Main thread is not running")');
    L.Add('if not LF_CheckApp(cstr("' + AppName + '")):');
    L.Add('    print("Service App not registered")');
    L.Add('```');
    L.Add('');
    L.Add('### 10.3 Inspecting the raw payload');
    L.Add('');
    L.Add('To print the raw bytes of a `DataHnd` for debugging:');
    L.Add('');
    L.Add('```python');
    L.Add('import ctypes');
    L.Add('from lingofuse._lf_native import LF_GetSize, LF_GetBuffer');
    L.Add('');
    L.Add('sz = LF_GetSize(res)');
    L.Add('buf = LF_GetBuffer(res)');
    L.Add('arr = ctypes.cast(buf, ctypes.POINTER(ctypes.c_ubyte * sz)).contents');
    L.Add('print(" ".join(f"{b:02X}" for b in arr))');
    L.Add('```');
    L.Add('');
    L.Add('### 10.4 Enabling verbose logging');
    L.Add('');
    L.Add('In the service module, set:');
    L.Add('');
    L.Add('```python');
    L.Add('DEBUG_LOG = True');
    L.Add('```');
    L.Add('');
    L.Add('The callback wrappers then print the request status, the');
    L.Add('deserialised parameters, and the result to standard output.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §12. Self-assessment checklist
  // ---------------------------------------------------------------------------
  procedure EmitSelfAssessment;
  begin
    L.Add('## 11. Self-Assessment Checklist');
    L.Add('');
    L.Add('After reading this document you should be able to answer the');
    L.Add('following questions without consulting the source code. If any');
    L.Add('answer is unclear, re-read the corresponding section.');
    L.Add('');
    L.Add('| # | Question | Section |');
    L.Add('|---|----------|---------|');
    L.Add('| 1 | What does the Python ABI service expose? | §1 |');
    L.Add('| 2 | When should I choose ABI instead of a JSON-based RPC? | §2 |');
    L.Add('| 3 | Which Python versions and platforms are supported? | §3 |');
    L.Add('| 4 | How do I install the `lingofuse` package? | §3.3 |');
    L.Add('| 5 | What are the two bytes that frame every response? | §4.2 |');
    L.Add('| 6 | Which function creates the App? | §5.1 |');
    L.Add('| 7 | What happens if a parameter type is not in the whitelist? | §6.2 |');
    L.Add('| 8 | Where do I place the DLLs at runtime? | §7.5 |');
    L.Add('| 9 | How do I run the built-in test? | §8.1 |');
    L.Add('| 10 | How do I invoke a specific API from the client? | §9 |');
    L.Add('| 11 | How do I enable verbose logging? | §10.4 |');
    L.Add('| 12 | What is the shutdown order? | §7.6 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('Python ABI service.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §13. Resources
  // ---------------------------------------------------------------------------
  procedure EmitResources;
  begin
    L.Add('## 12. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| Standalone `py-lingofuse` (if available) | Preferred source of the Python runtime bindings |');
    L.Add('| LingoFuse-pasAgent-v3 repository | Fallback source of `lingofuse/`, plus reference tools |');
    L.Add('| `lingofuse/_lf_native.py` | Low-level ctypes bindings |');
    L.Add('| `lingofuse/lf_io.py` | NUL-terminated framing helpers |');
    L.Add('| `pas_abi_service_generator_tool.pas` | Paired Pascal service-side generator |');
    L.Add('| `pas_abi_call_generator_tool.pas` | Paired Pascal call-side generator |');
    L.Add('| `py_abi_call_generator_tool.pas` | Paired Python call-side generator |');
    L.Add('| `cpp_abi_call_generator_tool.pas` | Paired C++ call-side generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `py_abi_service_generator_tool.pas`');
    L.Add('');
  end;

  // =============================================================================
  // Main body
  // =============================================================================
begin
  Result := TPascalStringList.Create;

  if Model = nil then
  begin
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: supplied TPascal_Func_Model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: Model.UnitName is empty.');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('GenerateABIServicePyReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABIServicePyReadme: %d valid APIs', [Length(SupportedFuncs)]));

  L := Result;
  try
    EmitHeader;
    EmitOverview;
    EmitApplicationScope;
    EmitCompatibility;
    EmitWireProtocol;
    EmitRuntimeArchitecture;
    EmitTypeMapping;
    EmitDeployment;
    EmitTesting;
    EmitApiReference;
    EmitTroubleshooting;
    EmitSelfAssessment;
    EmitResources;
  finally
    // Result already owns L; nothing to free here.
  end;

  Log(PFormat('GenerateABIServicePyReadme: %d lines generated', [L.Count]));
end;

end.
