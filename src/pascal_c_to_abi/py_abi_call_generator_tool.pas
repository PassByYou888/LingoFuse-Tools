unit py_abi_call_generator_tool;


// py_abi_call_generator_tool - LingoFuse ABI Call-Side Generator for
// Python.
//
// This unit is the Python counterpart of pas_abi_call_generator_tool.
// It consumes the same TPascal_Func_Model (Typ_Normalize_Func =
// tnf_ABI) and produces a standalone Python module that provides a
// typed free function for every supported routine, calling the
// matching ABI service over LingoFuse.
//
// The generated module:
//   - Declares a runtime-configurable target app name and timeout.
//   - Declares an EABIRemoteError exception class.
//   - Provides one free function per supported routine, mirroring the
//     signature of the original declaration. Each function:
//       1. Serialises its arguments into a DataHnd using the local
//          little-endian helpers.
//       2. Calls LF_Call and reads back the response.
//       3. Interprets the one-byte status prefix written by the
//          service:
//            0x00 -> success; reads and returns the payload.
//            0xFF -> raises EABIRemoteError with the UTF-8 message.
//
// Wire protocol (matches py_abi_service_generator_tool and
// pas_abi_service_generator_tool):
//   request  = [field1][field2]...[fieldN]
//   response = [status:UInt8][payload]
//     status = 0x00 -> success
//     status = 0xFF -> error followed by a NUL-terminated UTF-8
//                      message
//
// Deployment notes:
//   The generated module does NOT call LF_PrepareClient /
//   LF_PrepareDone / LF_Shutdown. The host program is responsible for
//   wiring up LingoFuse before calling any generated function. A
//   typical host program:
//
//       from lingofuse._lf_native import (
//           LF_ResetPrepare, LF_PrepareClient, LF_PrepareDone,
//           LF_ExitMainThread, LF_Shutdown,
//       )
//       from lingofuse.lf_io import cstr
//       import my_unit_abi_call_module
//
//       LF_ResetPrepare()
//       LF_PrepareClient(cstr('ipc:my_unit_abi'), None)
//       if LF_PrepareDone() != 1:
//           raise SystemExit(1)
//       try:
//           print(my_unit_abi_call_module.Add(3, 4))
//       finally:
//           LF_ExitMainThread()
//           LF_Shutdown()
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


  // GenerateABICallPyCode - main entry point.
  //
  // Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
  // list is owned by the caller and must be released with DisposeObject.

function GenerateABICallPyCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICallPyReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// call-side type mapping, and every exported Python function. The
// document is written so that both human readers and AI assistants can
// learn the call-side module's usage model from the README alone.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABICallPyReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[py_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;


// -----------------------------------------------------------------------------
// ABI type mapping (mirrors pas_abi_call_generator_tool)
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


// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// Wire API name: matches the naming scheme used by the two service
// generators, so that both the Pascal and the Python service sides
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

// Produce a valid, unique Python identifier. If `Preferred` is
// already valid and unused, it is returned unchanged. Otherwise a
// fresh name is derived from `FallbackPrefix` with a numeric suffix.
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
// Non-ASCII characters are emitted verbatim; the generated Python
// file carries a UTF-8 coding declaration, so Python 3 will decode
// them correctly.
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
// Parameter helpers
// -----------------------------------------------------------------------------

// Build a Python signature parameter list, e.g. "a: int, b: int".
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

procedure EmitHeader(Lines: TPascalStringList; const UnitName, TargetAppName: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('"""');
  Lines.Add('Auto-generated by py_abi_call_generator_tool.');
  Lines.Add('');
  Lines.Add('Source model unit: ' + UnitName.Text + '.');
  Lines.Add('');
  Lines.Add('LingoFuse ABI call-side client.');
  Lines.Add('');
  Lines.Add('Wire protocol (both directions):');
  Lines.Add('    request  = [field1][field2]...[fieldN]');
  Lines.Add('    response = [status:UInt8][payload]');
  Lines.Add('        status = 0x00 -> success; payload is the serialised result');
  Lines.Add('                         (functions) or empty (procedures).');
  Lines.Add('        status = 0xFF -> error; payload is a UTF-8 string message.');
  Lines.Add('');
  Lines.Add('This module does NOT call LF_PrepareClient / LF_PrepareDone /');
  Lines.Add('LF_Shutdown. The host program is responsible for wiring up');
  Lines.Add('LingoFuse before calling any function in this module. A typical');
  Lines.Add('host program:');
  Lines.Add('');
  Lines.Add('    from lingofuse._lf_native import (');
  Lines.Add('        LF_ResetPrepare, LF_PrepareClient, LF_PrepareDone,');
  Lines.Add('        LF_ExitMainThread, LF_Shutdown,');
  Lines.Add('    )');
  Lines.Add('    from lingofuse.lf_io import cstr');
  Lines.Add('    import this_module');
  Lines.Add('');
  Lines.Add('    LF_ResetPrepare()');
  Lines.Add('    LF_PrepareClient(cstr(''ipc:my_unit_abi''), None)');
  Lines.Add('    if LF_PrepareDone() != 1:');
  Lines.Add('        raise SystemExit(1)');
  Lines.Add('    try:');
  Lines.Add('        print(this_module.Add(3, 4))');
  Lines.Add('    finally:');
  Lines.Add('        LF_ExitMainThread()');
  Lines.Add('        LF_Shutdown()');
  Lines.Add('');
  Lines.Add('Both ABI_TARGET_APP and ABI_TIMEOUT are module-level variables');
  Lines.Add('and may be reassigned at runtime. The default target is:');
  Lines.Add('    ' + TargetAppName.Text);
  Lines.Add('"""');
  Lines.Add('');
  Lines.Add('import ctypes');
  Lines.Add('import struct');
  Lines.Add('');
  Lines.Add('from lingofuse._lf_native import (');
  Lines.Add('    DataHnd,');
  Lines.Add('    LF_CreateData,');
  Lines.Add('    LF_FreeData,');
  Lines.Add('    LF_Call,');
  Lines.Add('    LF_GetSize,');
  Lines.Add('    LF_SetPos,');
  Lines.Add('    LF_ReadBuffer,');
  Lines.Add('    LF_WriteBuffer,');
  Lines.Add(')');
  Lines.Add('from lingofuse.lf_io import (');
  Lines.Add('    cstr,');
  Lines.Add('    read_string as _lf_read_string,');
  Lines.Add('    write_string as _lf_write_string,');
  Lines.Add(')');
  Lines.Add('');
end;

procedure EmitConstants(Lines: TPascalStringList; const TargetAppName: TP_String);
begin
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Remote call target configuration');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('# LingoFuse application name of the ABI service. Must match');
  Lines.Add('# MY_APP_NAME on the service side.');
  Lines.Add('ABI_TARGET_APP = ' + PyStrLit(TargetAppName) + '');
  Lines.Add('');
  Lines.Add('# Per-call timeout in milliseconds.');
  Lines.Add('ABI_TIMEOUT = 5000');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Wire protocol constants');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('STATUS_OK = 0x00');
  Lines.Add('STATUS_ERROR = 0xFF');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Exception type');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('class EABIRemoteError(Exception):');
  Lines.Add('    """Raised when a remote ABI call fails.');
  Lines.Add('');
  Lines.Add('    The failure may be a timeout, an empty response, a truncated');
  Lines.Add('    response, or a 0xFF error status returned by the service.');
  Lines.Add('    """');
  Lines.Add('    pass');
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
// Emit one typed remote-call function.

// Parameters:
//   Lines       - destination list.
//   FuncName    - Python function name (already made unique and valid).
//   ApiName     - wire API name written into the MethodName field of
//                 the request DataHandle. Matches the name registered
//                 by the service side.
//   IsFunction  - True for functions, False for procedures.
//   Params      - parameter list of the original declaration.
//   ReturnType  - ABI-normalised return type (empty for procedures).
// -----------------------------------------------------------------------------

procedure EmitFunction(Lines: TPascalStringList; const FuncName, ApiName: TP_String; const IsFunction: boolean; const Params: TParamArray; const ReturnType: TP_String);
var
  i: integer;
  PyParamList: TP_String;
  ReadFunc, WriteFunc: TP_String;
  ParamName: TP_String;
  ReturnAnnotation: TP_String;
begin
  PyParamList := BuildPyParamList(Params);

  // Precompute the return annotation. FPC 3.2.2 does not support the
  // inline if-then-else expression form, so this must be a plain
  // statement.
  if IsFunction then
    ReturnAnnotation := ABI_Type_To_Py_Annotation(ReturnType)
  else
    ReturnAnnotation := 'None';

  Lines.Add('');
  Lines.Add('def ' + FuncName + '(' + PyParamList + ') -> ' + ReturnAnnotation + ':');

  // A short docstring identifying the remote API.
  Lines.Add('    """Typed remote call: ' + ApiName + '."""');

  Lines.Add('    _data = LF_CreateData(cstr(' + PyStrLit(ApiName) + '))');
  Lines.Add('    if not _data:');
  Lines.Add('        raise EABIRemoteError(');
  Lines.Add('            ''LF_CreateData returned nil for API "' + ApiName + '"''');
  Lines.Add('        )');
  Lines.Add('');
  Lines.Add('    try:');

  // Serialise parameters.
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      ParamName := 'p' + umlIntToStr(i)
    else
      ParamName := Params[i].Name;
    WriteFunc := ABI_Type_To_Py_Write_Func(Params[i].PascalType);
    Lines.Add('        ' + WriteFunc + '(_data, ' + ParamName + ')');
  end;

  Lines.Add('        _res = LF_Call(cstr(ABI_TARGET_APP), _data, ABI_TIMEOUT)');
  Lines.Add('        if not _res:');
  Lines.Add('            raise EABIRemoteError(');
  Lines.Add('                ''ABI call "' + ApiName + '" returned nil (timeout or target not found)''');
  Lines.Add('            )');
  Lines.Add('');
  Lines.Add('        try:');
  Lines.Add('            if LF_GetSize(_res) <= 0:');
  Lines.Add('                raise EABIRemoteError(');
  Lines.Add('                    ''ABI call "' + ApiName + '" returned empty response''');
  Lines.Add('                )');
  Lines.Add('');
  Lines.Add('            LF_SetPos(_res, 0)');
  Lines.Add('');
  Lines.Add('            try:');
  Lines.Add('                _status = _read_uint8(_res)');
  Lines.Add('            except Exception:');
  Lines.Add('                raise EABIRemoteError(');
  Lines.Add('                    ''ABI call "' + ApiName + '": response truncated (status byte)''');
  Lines.Add('                )');
  Lines.Add('');
  Lines.Add('            if _status != STATUS_OK:');
  Lines.Add('                try:');
  Lines.Add('                    _err_msg = _read_string(_res)');
  Lines.Add('                except Exception:');
  Lines.Add('                    _err_msg = ''''');
  Lines.Add('                raise EABIRemoteError(');
  Lines.Add('                    ''ABI call "' + ApiName + '" failed: %s'' % _err_msg');
  Lines.Add('                )');

  // Deserialise result for functions.
  if IsFunction then
  begin
    ReadFunc := ABI_Type_To_Py_Read_Func(ReturnType);
    Lines.Add('');
    Lines.Add('            try:');
    Lines.Add('                return ' + ReadFunc + '(_res)');
    Lines.Add('            except Exception:');
    Lines.Add('                raise EABIRemoteError(');
    Lines.Add('                    ''ABI call "' + ApiName + '": response truncated (result)''');
    Lines.Add('                )');
  end;

  Lines.Add('        finally:');
  Lines.Add('            LF_FreeData(_res)');
  Lines.Add('    finally:');
  Lines.Add('        LF_FreeData(_data)');
  Lines.Add('');
end;


// -----------------------------------------------------------------------------
// Main entry point
// -----------------------------------------------------------------------------

function GenerateABICallPyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;

  HeaderLines: TPascalStringList;
  ConstLines: TPascalStringList;
  SerializationLines: TPascalStringList;
  FunctionLines: TPascalStringList;
  ResultLines: TPascalStringList;
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

  HeaderLines := TPascalStringList.Create;
  ConstLines := TPascalStringList.Create;
  SerializationLines := TPascalStringList.Create;
  FunctionLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // -------------------------------------------------------------------------
    // 1. Header (docstring + imports)
    // -------------------------------------------------------------------------
    EmitHeader(HeaderLines, UnitName, TargetAppName);

    // -------------------------------------------------------------------------
    // 2. Constants + exception class
    // -------------------------------------------------------------------------
    EmitConstants(ConstLines, TargetAppName);

    // -------------------------------------------------------------------------
    // 3. Serialisation helpers
    // -------------------------------------------------------------------------
    EmitSerializationHelpers(SerializationLines);

    // -------------------------------------------------------------------------
    // 4. Typed remote call functions
    // -------------------------------------------------------------------------
    FunctionLines.Add('');
    FunctionLines.Add('# ----------------------------------------------------------------------');
    FunctionLines.Add('# Typed remote call functions');
    FunctionLines.Add('# ----------------------------------------------------------------------');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        ApiName := MakePyIdent(ApiName, 'api_' + umlIntToStr(i).Text, UsedApiNames);

        EmitFunction(
          FunctionLines,
          ApiName,
          ApiName,
          IsFunction,
          Params,
          ReturnType
          );
      end;
    end;

    // -------------------------------------------------------------------------
    // 5. Assemble
    // -------------------------------------------------------------------------
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(ConstLines);
    ResultLines.AddStrings(SerializationLines);
    ResultLines.AddStrings(FunctionLines);

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.', [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    ConstLines.Free;
    SerializationLines.Free;
    FunctionLines.Free;
    UsedApiNames.Free;
    // ResultLines is returned to the caller; not freed here.
  end;
end;

// =============================================================================
// SECTION 2 - README generator
// =============================================================================
//
// This section is self-contained. It depends only on the helpers already
// present in this unit (MakeApiName, MakePyIdent, ABI_Type_To_Py_Annotation,
// ABI_Type_To_Py_Read_Func, ABI_Type_To_Py_Write_Func, BuildPyParamList,
// BuildPyArgList, CollectSupportedFunctions, PyStrLit, Log) plus the
// standard Z-framework units already in scope.
//
// The README is organised into twelve sections:
//
//   §1  Overview
//   §2  Application scope
//   §3  Compatibility (Python version, platform, dependencies)
//   §4  Wire protocol
//   §5  Runtime architecture (call-side view)
//   §6  Type mapping
//   §7  Deployment
//   §8  Testing
//   §9  API reference
//   §10 Troubleshooting
//   §11 Self-assessment checklist
//   §12 Reference resources
//
// The document is written so that both human readers and AI assistants
// can learn the call-side module's usage model from the README alone.
// =============================================================================

// Returns the "wire size" column text for the ABI type table.
function PyCallReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '1 byte'
  else if ABI_Type.Same('word') or ABI_Type.Same('smallint') then
    Result := '2 bytes'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or
    ABI_Type.Same('longword') or ABI_Type.Same('integer') or
    ABI_Type.Same('longint') or ABI_Type.Same('single') then
    Result := '4 bytes'
  else if ABI_Type.Same('int64') or ABI_Type.Same('uint64') or
    ABI_Type.Same('double') or ABI_Type.Same('extended') or
    ABI_Type.Same('real') then
    Result := '8 bytes'
  else if ABI_Type.Same('string') or ABI_Type.Same('ansistring') or
    ABI_Type.Same('unicodestring') or ABI_Type.Same('tpascalstring') or
    ABI_Type.Same('tupascalstring') or ABI_Type.Same('tp_string') or
    ABI_Type.Same('pchar') or ABI_Type.Same('pansichar') or
    ABI_Type.Same('pwidechar') then
    Result := 'variable + NUL'
  else
    Result := 'unknown';
end;

// Returns the "struct format" column text for the ABI type table.
function PyCallReadmeStructFormat(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '`<B`'
  else if ABI_Type.Same('word') then
    Result := '`<H`'
  else if ABI_Type.Same('smallint') then
    Result := '`<h`'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or
    ABI_Type.Same('longword') then
    Result := '`<I`'
  else if ABI_Type.Same('integer') or ABI_Type.Same('longint') then
    Result := '`<i`'
  else if ABI_Type.Same('int64') then
    Result := '`<q`'
  else if ABI_Type.Same('uint64') then
    Result := '`<Q`'
  else if ABI_Type.Same('single') then
    Result := '`<f`'
  else if ABI_Type.Same('double') or ABI_Type.Same('extended') or
    ABI_Type.Same('real') then
    Result := '`<d`'
  else if ABI_Type.Same('string') or ABI_Type.Same('ansistring') or
    ABI_Type.Same('unicodestring') or ABI_Type.Same('tpascalstring') or
    ABI_Type.Same('tupascalstring') or ABI_Type.Same('tp_string') or
    ABI_Type.Same('pchar') or ABI_Type.Same('pansichar') or
    ABI_Type.Same('pwidechar') then
    Result := '`_lf_write_string`'
  else
    Result := '?';
end;

// Sanitise a description for use inside a Markdown table cell.
function PyCallReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// Sanitise a description for use as standalone paragraph text.
function PyCallReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

// -----------------------------------------------------------------------------
// Comment description extraction
//
// Operates on UTF-16 TP_String directly. Strips comment markers, Doxygen
// tag lines, and continuation '*' markers. Only the first non-empty,
// non-Doxygen line is returned, capped at 200 characters.
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
    // Locate end of the current logical line.
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
          // Strip leading '*' markers from block comment continuation.
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

    // Advance past CR/LF.
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
end;

// Build the README for a given model.
function GenerateABICallPyReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName: TP_String;

  // ---------------------------------------------------------------------------
  // §1. Header
  // ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - Python ABI Call Client');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `py_abi_call_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Call-side module**  : `' + UnitName + '_abi_call.py`');
    L.Add('> **Target App name**   : `' + TargetAppName + '`');
    L.Add('> **Exported functions**: ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> import, deploy, or call this module without reading the source.');
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
    L.Add('This document describes the **Python call-side client module** that');
    L.Add('was generated from the Pascal unit `' + UnitName + '`. The module is');
    L.Add('a strongly-typed wrapper around LingoFuse that talks to a matching');
    L.Add('ABI service over a compact binary wire protocol.');
    L.Add('');
    L.Add('### 1.1 What is a call-side client?');
    L.Add('');
    L.Add('A call-side client is a Python module that:');
    L.Add('');
    L.Add('- exports one **free function** per API of the matching service;');
    L.Add('- each free function mirrors the signature of the original routine;');
    L.Add('- serialises its arguments with little-endian `struct.pack`, sends');
    L.Add('  them through `LF_Call`, and decodes the response with');
    L.Add('  `struct.unpack`;');
    L.Add('- raises `EABIRemoteError` on timeout, empty response, or when the');
    L.Add('  service returns a `0xFF` error status.');
    L.Add('');
    L.Add('The module is a **client**: it never registers APIs of its own,');
    L.Add('never calls `LF_PrepareService`, and never touches the LingoFuse');
    L.Add('main-thread setup beyond what the host program provides.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Target resolution | Direct by App name (no discovery) |');
    L.Add('| Service dependency | Must be generated from the same model |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Implementation | Pure Python 3 + ctypes |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Install** the `lingofuse` Python package. See §3.3.');
    L.Add('2. **Start** the matching service process. See §5.');
    L.Add('3. **Call** the exported free functions. See §8 and §9.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + UnitName + '_abi_call.py` | The call-side module (import into your client program). |');
    L.Add('| `' + UnitName + '_abi_call_python.md` | This README. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use this call-side module');
    L.Add('');
    L.Add('Use this module when:');
    L.Add('');
    L.Add('- You need to call a **specific, known ABI service**.');
    L.Add('- The service''s signature is **stable** and known at build time.');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- A Python script calling a Python ABI service.');
    L.Add('- A Python front-end calling a compute engine written in Pascal or C++.');
    L.Add('- A data pipeline stage consuming a downstream ABI service.');
    L.Add('- A test harness exercising a native ABI service.');
    L.Add('');
    L.Add('### 2.2 When NOT to use this call-side module');
    L.Add('');
    L.Add('- You need to discover the API surface at runtime.');
    L.Add('- The target service''s signature changes without a rebuild.');
    L.Add('- Parameters include complex types (dicts, lists, custom objects).');
    L.Add('- You need a client that can target **arbitrary** third-party');
    L.Add('  services without prior generation.');
    L.Add('- You need to talk to a JSON-based service.');
    L.Add('');
    L.Add('### 2.3 Comparison with other RPC clients');
    L.Add('');
    L.Add('| Approach | Typed | Binary | Self-describing | Paired codegen |');
    L.Add('|----------|:-----:|:------:|:---------------:|:--------------:|');
    L.Add('| This ABI client | yes | yes | no | yes (required) |');
    L.Add('| gRPC client | yes | yes | yes (proto) | yes (generated) |');
    L.Add('| REST + JSON client | no | no | yes | no |');
    L.Add('| Raw TCP client | no | yes | no | yes |');
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
    L.Add('Every exported free function is thread-safe with respect to');
    L.Add('LingoFuse. Different threads may call different free functions in');
    L.Add('parallel. `LF_Call` performs its own internal synchronisation and');
    L.Add('blocks the calling thread until the response arrives or the');
    L.Add('timeout expires.');
    L.Add('');
    L.Add('**Do not call an exported free function from inside a LingoFuse');
    L.Add('callback.** Doing so deadlocks the calling worker thread. If you');
    L.Add('need to call a remote service from inside a callback, offload the');
    L.Add('call to a separate `threading.Thread`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The call-side module speaks the same wire format as the matching');
    L.Add('service.');
    L.Add('');
    L.Add('### 4.1 Request');
    L.Add('');
    L.Add('```');
    L.Add('request = [field1][field2]...[fieldN]');
    L.Add('```');
    L.Add('');
    L.Add('Fields are serialised in the **exact order** in which they appear');
    L.Add('in the original Pascal declaration. Each exported free function');
    L.Add('performs this serialisation automatically.');
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
    L.Add('The exported free functions decode this automatically:');
    L.Add('');
    L.Add('- `0x00` -> returns the deserialised result (or returns normally');
    L.Add('  for procedures).');
    L.Add('- `0xFF` -> raises `EABIRemoteError` with the decoded message.');
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
    L.Add('    participant C as Call-side module');
    L.Add('    participant S as Service');
    L.Add('    C->>C: _write_xxx(a), _write_xxx(b)');
    L.Add('    C->>S: LF_Call(payload)');
    L.Add('    S-->>C: [status][payload]');
    L.Add('    C->>C: _read_uint8 -> status');
    L.Add('    alt status == 0x00');
    L.Add('        C->>C: _read_xxx -> result');
    L.Add('    else status == 0xFF');
    L.Add('        C->>C: _read_string -> error');
    L.Add('        C->>C: raise EABIRemoteError');
    L.Add('    end');
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
    L.Add('The call-side module raises `EABIRemoteError` with the decoded');
    L.Add('message. Callers should wrap their calls in a `try-except` block.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §6. Runtime architecture (call-side view)
  // ---------------------------------------------------------------------------
  procedure EmitRuntimeArchitecture;
  begin
    L.Add('## 5. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph Client["Client process (this module)"]');
    L.Add('        C_PREP["LF_ResetPrepare()"]');
    L.Add('        C_CLI["LF_PrepareClient(cstr(&#39;ipc:&lt;unit&gt;_abi&#39;), None)"]');
    L.Add('        C_RUN["LF_PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;ApiName&gt;(args)"]');
    L.Add('        C_CATCH["try / except EABIRemoteError"]');
    L.Add('        C_OFF["LF_ExitMainThread() + LF_Shutdown()"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Service["Service process (external)"]');
    L.Add('        S_RUN["ABI service running<br/>App = &lt;unit&gt;_abi"]');
    L.Add('    end');
    L.Add('');
    L.Add('    C_PREP --> C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "LF_Call over IPC" .-> S_RUN');
    L.Add('    S_RUN -. "response" .-> C_CATCH');
    L.Add('    C_CATCH --> C_OFF');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (client)');
    L.Add('');
    L.Add('1. `LF_ResetPrepare()`');
    L.Add('2. `LF_PrepareClient(cstr(''ipc:<unit>_abi''), None)`');
    L.Add('   (pass `None` because the client does not expose any APIs)');
    L.Add('3. `LF_PrepareDone()`');
    L.Add('');
    L.Add('The service process must be running before step 3 completes.');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The caller invokes an exported free function, e.g.');
    L.Add('   `<ApiName>(a, b)`.');
    L.Add('2. The free function creates a `DataHnd` via `LF_CreateData`.');
    L.Add('3. It writes every argument with the matching `_write_xxx` helper.');
    L.Add('4. It calls `LF_Call(cstr(ABI_TARGET_APP), _data, ABI_TIMEOUT)`.');
    L.Add('5. LingoFuse routes the payload to the service and waits for the');
    L.Add('   response (blocking).');
    L.Add('6. On a null response: raises `EABIRemoteError`.');
    L.Add('7. On an empty response: raises `EABIRemoteError`.');
    L.Add('8. It reads the status byte.');
    L.Add('9. On `0xFF`: reads the UTF-8 message and raises `EABIRemoteError`.');
    L.Add('10. On `0x00`: reads the result with `_read_xxx` and returns it.');
    L.Add('');
    L.Add('### 5.3 Timeout');
    L.Add('');
    L.Add('The timeout is controlled by the module-level variable');
    L.Add('`ABI_TIMEOUT` (default `5000` ms). Change it before making calls:');
    L.Add('');
    L.Add('```python');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('abi.ABI_TIMEOUT = 30000  # 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('### 5.4 Target application name');
    L.Add('');
    L.Add('The target service is identified by the module-level variable');
    L.Add('`ABI_TARGET_APP` (default `' + TargetAppName + '`). Change it to');
    L.Add('point at a differently-named service:');
    L.Add('');
    L.Add('```python');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('abi.ABI_TARGET_APP = "my_other_service_abi"');
    L.Add('```');
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
    L.Add('The call-side module accepts the same type set as the matching');
    L.Add('service. Every exported free function''s parameters and return');
    L.Add('type are drawn from this table.');
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
    L.Add('Anything not in §6.1 cannot appear in an exported function''s');
    L.Add('signature. If the original routine used a complex type, the');
    L.Add('matching free function is **not generated at all**.');
    L.Add('');
    L.Add('Common examples of unsupported types:');
    L.Add('');
    L.Add('- `bool`');
    L.Add('- `dict`, `list`, `tuple`, `set`');
    L.Add('- Custom classes and dataclasses');
    L.Add('- `bytes`, `bytearray`');
    L.Add('- `datetime`, `decimal.Decimal`');
    L.Add('');
    L.Add('**Workaround**: serialise the complex value into a `str` first');
    L.Add('(JSON or a custom format) on the caller side, then call a');
    L.Add('string-typed overload of the service. On the service side,');
    L.Add('deserialise the string back into the rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The wire format is little-endian for all integers and floats. All');
    L.Add('supported platforms are little-endian, so the generated module');
    L.Add('never performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('The exported free functions use `lingofuse.lf_io.write_string` and');
    L.Add('`lingofuse.lf_io.read_string` for string parameters and return');
    L.Add('values. `write_string` always appends a single `\\x00` byte after');
    L.Add('the UTF-8 payload. `read_string` scans forward until it finds that');
    L.Add('byte.');
    L.Add('');
    L.Add('**Recommendation**: do not hand-roll string encoding. Always rely');
    L.Add('on the generated free functions.');
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
    L.Add('my_abi_client/');
    L.Add('  ' + UnitName + '_abi_call.py              <- generated (described here)');
    L.Add('  ' + UnitName + '_client.py                <- your client entry point');
    L.Add('  ZNetV2/');
    L.Add('    z_ipc_64.dll                              <- Windows');
    L.Add('    libz_ipc_64.so                            <- Linux');
    L.Add('  LingoFuse64.dll                             <- Windows');
    L.Add('  liblingofuse.so                             <- Linux');
    L.Add('  liblingofuse.dylib                          <- macOS');
    L.Add('```');
    L.Add('');
    L.Add('The `lingofuse` Python package must be importable (see §3.3). The');
    L.Add('matching service process must be running independently and must');
    L.Add('expose the App name `' + TargetAppName + '`.');
    L.Add('');
    L.Add('### 7.2 Installing the lingofuse package');
    L.Add('');
    L.Add('**Preferred:**');
    L.Add('');
    L.Add('```bash');
    L.Add('pip install py-lingofuse');
    L.Add('```');
    L.Add('');
    L.Add('**Fallback (v3-shipped copy):**');
    L.Add('');
    L.Add('**Windows (cmd):**');
    L.Add('');
    L.Add('```bat');
    L.Add('set PYTHONPATH=D:\\LingoFuse-pasAgent-v3\\src');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (PowerShell):**');
    L.Add('');
    L.Add('```powershell');
    L.Add('$env:PYTHONPATH = "D:\\LingoFuse-pasAgent-v3\\src"');
    L.Add('```');
    L.Add('');
    L.Add('**Linux / macOS:**');
    L.Add('');
    L.Add('```bash');
    L.Add('export PYTHONPATH=/path/to/LingoFuse-pasAgent-v3/src');
    L.Add('```');
    L.Add('');
    L.Add('### 7.3 Syntax check');
    L.Add('');
    L.Add('```bash');
    L.Add('python -m py_compile ' + UnitName + '_abi_call.py');
    L.Add('```');
    L.Add('');
    L.Add('### 7.4 Startup order');
    L.Add('');
    L.Add('The service must be running before the client calls');
    L.Add('`LF_PrepareDone`. If the client starts first, retry or poll:');
    L.Add('');
    L.Add('```python');
    L.Add('import time');
    L.Add('from lingofuse._lf_native import LF_CheckApp');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('');
    L.Add('while not LF_CheckApp(cstr("' + TargetAppName + '")):');
    L.Add('    time.sleep(0.1)');
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
    L.Add('The recommended shutdown sequence on the client side is:');
    L.Add('');
    L.Add('1. `LF_ExitMainThread()`');
    L.Add('2. `LF_Shutdown()`');
    L.Add('');
    L.Add('The client does not own an App handle, so there is nothing to');
    L.Add('release with `LF_FreeApp`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Testing
  // ---------------------------------------------------------------------------
  procedure EmitTesting;
  begin
    L.Add('## 8. Testing');
    L.Add('');
    L.Add('The program below is a complete, copy-paste-ready test client.');
    L.Add('Save it next to the generated module and run it with Python 3.8+.');
    L.Add('');
    L.Add('### 8.1 Client program (`' + UnitName + '_client.py`)');
    L.Add('');
    L.Add('```python');
    L.Add('# -*- coding: utf-8 -*-');
    L.Add('"""Minimal test client for the ' + UnitName + ' ABI service."""');
    L.Add('');
    L.Add('from lingofuse._lf_native import (');
    L.Add('    LF_ResetPrepare,');
    L.Add('    LF_PrepareClient,');
    L.Add('    LF_PrepareDone,');
    L.Add('    LF_ExitMainThread,');
    L.Add('    LF_Shutdown,');
    L.Add(')');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('');
    L.Add('');
    L.Add('def main() -> int:');
    L.Add('    print("=== ' + UnitName + ' ABI client ===")');
    L.Add('');
    L.Add('    LF_ResetPrepare()');
    L.Add('    LF_PrepareClient(cstr("ipc:' + TargetAppName + '"), None)');
    L.Add('');
    L.Add('    if LF_PrepareDone() != 1:');
    L.Add('        print("[FATAL] LF_PrepareDone failed")');
    L.Add('        return 1');
    L.Add('');
    L.Add('    try:');
    L.Add('        # Replace with actual calls to the generated functions.');
    L.Add('        # Example:');
    L.Add('        #     print("Add(3, 4) =", abi.Add(3, 4))');
    L.Add('        pass');
    L.Add('    except abi.EABIRemoteError as e:');
    L.Add('        print(f"[ERROR] {e}")');
    L.Add('');
    L.Add('    LF_ExitMainThread()');
    L.Add('    LF_Shutdown()');
    L.Add('    return 0');
    L.Add('');
    L.Add('');
    L.Add('if __name__ == "__main__":');
    L.Add('    raise SystemExit(main())');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Running the test');
    L.Add('');
    L.Add('Make sure the matching service process is running first. Then:');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_client.py');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path:');
    L.Add('');
    L.Add('1. Stop the service process.');
    L.Add('2. Run the client again.');
    L.Add('3. The free function raises `EABIRemoteError` with a timeout or');
    L.Add('   "target not found" message.');
    L.Add('');
    L.Add('### 8.4 Unit-level testing of the serialisation helpers');
    L.Add('');
    L.Add('The generated module exposes the low-level helpers');
    L.Add('`_write_int32`, `_write_string`, `_read_int32`, etc. These can be');
    L.Add('exercised directly without a running service:');
    L.Add('');
    L.Add('```python');
    L.Add('from lingofuse._lf_native import (');
    L.Add('    LF_CreateData, LF_FreeData, LF_SetPos,');
    L.Add(')');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('');
    L.Add('hnd = LF_CreateData(cstr("<ApiName>"))');
    L.Add('try:');
    L.Add('    abi._write_int32(hnd, 42)');
    L.Add('    abi._write_string(hnd, "hello")');
    L.Add('    LF_SetPos(hnd, 0)');
    L.Add('    assert abi._read_int32(hnd) == 42');
    L.Add('    assert abi._read_string(hnd) == "hello"');
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
    CallExpr: TP_String;
    PName: TP_String;
    RetDecl: TP_String;
    UsedNames: TPascalStringList;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this call-side module exports no functions.**');
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

    L.Add('Total exported functions: **' +
      umlIntToStr(Length(SupportedFuncs)).Text + '**.');
    L.Add('');
    L.Add('Every function is a **free function** declared at module level.');
    L.Add('Import the module and call them directly:');
    L.Add('');
    L.Add('```python');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('result = abi.<ApiName>(...)');
    L.Add('```');
    L.Add('');

    // Build the summary table.
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | Function | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');

    // We must reproduce the same unique-name logic as GenerateABICallPyCode
    // so the README lists the exact Python identifiers that the generated
    // module actually exports.
    UsedNames := TPascalStringList.Create;
    try
      for ii := 0 to High(SupportedFuncs) do
      begin
        Func := SupportedFuncs[ii];
        ApiNm := MakeApiName(Func.Name);
        ApiNm := MakePyIdent(ApiNm, 'api_' + umlIntToStr(ii).Text, UsedNames);

        ShortDesc := PyCallReadmeTableCell(GetFullDescription(Func.Comment));
        if ShortDesc.Len > 60 then
          ShortDesc := ShortDesc.GetString(1, 61) + '...';

        if Func.IsFunction then
          RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm +
            '` | function | ' + umlIntToStr(Length(Func.Params)).Text +
            ' | `' + ABI_Type_To_Py_Annotation(Func.ReturnType) + '` | ' +
            ShortDesc + ' |'
        else
          RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm +
            '` | procedure | ' + umlIntToStr(Length(Func.Params)).Text +
            ' | - | ' + ShortDesc + ' |';
        L.Add(RowStr);
      end;
    finally
      UsedNames.Free;
    end;

    L.Add('');

    // Per-API details.
    UsedNames := TPascalStringList.Create;
    try
      for ii := 0 to High(SupportedFuncs) do
      begin
        Func := SupportedFuncs[ii];
        ApiNm := MakeApiName(Func.Name);
        ApiNm := MakePyIdent(ApiNm, 'api_' + umlIntToStr(ii).Text, UsedNames);
        FuncDesc := PyCallReadmeParagraph(GetFullDescription(Func.Comment));

        // Reconstructed declaration.
        DeclLine := 'def ' + ApiNm + '(';
        for jj := 0 to High(Func.Params) do
        begin
          if jj > 0 then
            DeclLine := DeclLine + ', ';
          PName := Func.Params[jj].Name.Text;
          if PName = '' then
            PName := 'p' + umlIntToStr(jj).Text;
          DeclLine := DeclLine + PName + ': ' +
            ABI_Type_To_Py_Annotation(Func.Params[jj].PascalType);
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

        // Call expression for the example.
        CallExpr := ApiNm + '(';
        for jj := 0 to High(Func.Params) do
        begin
          if jj > 0 then
            CallExpr := CallExpr + ', ';
          if IsStringABIType(Func.Params[jj].PascalType) then
            CallExpr := CallExpr + '"hello"'
          else if IsFloatABIType(Func.Params[jj].PascalType) or
            Func.Params[jj].PascalType.Same('single') then
            CallExpr := CallExpr + '0.0'
          else
            CallExpr := CallExpr + '0';
        end;
        CallExpr := CallExpr + ')';

        L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
        L.Add('');
        L.Add('- **Declaration**: `' + DeclLine + '`');
        if Func.IsFunction then
          L.Add('- **Kind**: function; returns `' +
            ABI_Type_To_Py_Annotation(Func.ReturnType) + '`')
        else
          L.Add('- **Kind**: procedure');
        L.Add('- **Raises**: `EABIRemoteError` on timeout, empty response, or `0xFF` status');
        L.Add('');

        if FuncDesc.Len > 0 then
        begin
          L.Add('#### Description');
          L.Add('');
          L.Add(FuncDesc);
          L.Add('');
        end;

        // Parameters table.
        if Length(Func.Params) > 0 then
        begin
          L.Add('#### Parameters');
          L.Add('');
          L.Add('| # | Name | Python type | ABI type | Writer | Wire size |');
          L.Add('|---|------|-------------|----------|--------|-----------|');
          for jj := 0 to High(Func.Params) do
          begin
            PName := Func.Params[jj].Name.Text;
            if PName = '' then
              PName := 'p' + umlIntToStr(jj).Text;
            RowStr := '| ' + umlIntToStr(jj + 1).Text +
              ' | `' + PName + '`' +
              ' | `' + ABI_Type_To_Py_Annotation(Func.Params[jj].PascalType) + '`' +
              ' | `' + Func.Params[jj].PascalType + '`' +
              ' | `' + ABI_Type_To_Py_Write_Func(Func.Params[jj].PascalType) + '`' +
              ' | ' + PyCallReadmeWireSizeText(Func.Params[jj].PascalType) +
              ' |';
            L.Add(RowStr);
          end;
          L.Add('');
        end;

        // Call example.
        L.Add('#### Call example');
        L.Add('');
        L.Add('```python');
        L.Add('import ' + UnitName + '_abi_call as abi');
        L.Add('');
        L.Add('try:');
        if Func.IsFunction then
          L.Add('    result = abi.' + CallExpr)
        else
          L.Add('    abi.' + CallExpr);
        L.Add('except abi.EABIRemoteError as e:');
        L.Add('    print(f"Call failed: {e}")');
        L.Add('```');
        L.Add('');

        L.Add('---');
        L.Add('');
      end;
    finally
      UsedNames.Free;
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
    L.Add('| `LF_PrepareDone` returns 0 | Service not running | Start the service before the client, or poll `LF_CheckApp`. |');
    L.Add('| `EABIRemoteError: nil (timeout)` | App name mismatch | Check `ABI_TARGET_APP` and the service''s `DEFAULT_APP_NAME`. |');
    L.Add('| `EABIRemoteError: nil (timeout)` | Timeout too short | Increase `ABI_TIMEOUT`. |');
    L.Add('| `EABIRemoteError: "input truncated"` | Service rejected the request | Verify the client and service were generated from the same model. |');
    L.Add('| `EABIRemoteError: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| `EABIRemoteError` on every call | Service App not registered | Verify the service is running and registered. |');
    L.Add('| Deadlock inside a callback | Calling a free function inside a LingoFuse callback | Offload the call to a separate `threading.Thread`. |');
    L.Add('| `LF_CreateData returned nil` | Out of memory or LingoFuse not initialised | Verify `LF_PrepareDone` was called. |');
    L.Add('| Client hangs forever | Timeout set to 0 | Set `ABI_TIMEOUT` to a positive value. |');
    L.Add('');
    L.Add('### 10.2 Verifying the service is reachable');
    L.Add('');
    L.Add('Before making a call:');
    L.Add('');
    L.Add('```python');
    L.Add('from lingofuse._lf_native import LF_CheckMainThread, LF_CheckApp');
    L.Add('from lingofuse.lf_io import cstr');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('');
    L.Add('if LF_CheckMainThread() == 0:');
    L.Add('    print("Main thread is not running")');
    L.Add('if not LF_CheckApp(cstr(abi.ABI_TARGET_APP)):');
    L.Add('    print("Target service is not registered")');
    L.Add('```');
    L.Add('');
    L.Add('### 10.3 Inspecting the raw payload');
    L.Add('');
    L.Add('To dump the raw bytes of a `DataHnd` for debugging:');
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
    L.Add('### 10.4 Adjusting the timeout');
    L.Add('');
    L.Add('Increase `ABI_TIMEOUT` when calling a slow service:');
    L.Add('');
    L.Add('```python');
    L.Add('import ' + UnitName + '_abi_call as abi');
    L.Add('abi.ABI_TIMEOUT = 30000  # 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('A value of `0` disables the timeout, which means the call blocks');
    L.Add('indefinitely if the service never responds.');
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
    L.Add('| 1 | What does this call-side module export? | §1 |');
    L.Add('| 2 | When should I use this client instead of a JSON client? | §2 |');
    L.Add('| 3 | Which Python versions and platforms are supported? | §3 |');
    L.Add('| 4 | How do I install the `lingofuse` package? | §3.3 |');
    L.Add('| 5 | What is the wire format of a request and a response? | §4 |');
    L.Add('| 6 | What is the client startup sequence? | §5.1 |');
    L.Add('| 7 | How is the target App name configured? | §5.4 |');
    L.Add('| 8 | How is the timeout configured? | §5.3 |');
    L.Add('| 9 | Which Python types are accepted? | §6.1 |');
    L.Add('| 10 | Where do I place the DLLs at runtime? | §7.5 |');
    L.Add('| 11 | What is the shutdown order on the client side? | §7.6 |');
    L.Add('| 12 | How do I invoke a specific API? | §9 |');
    L.Add('| 13 | How do I handle a failed call? | §4.5, §9 |');
    L.Add('| 14 | What should I do if the client hangs forever? | §10.4 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('call-side module.');
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
    L.Add('| `py_abi_service_generator_tool.pas` | Paired Python service-side generator |');
    L.Add('| `cpp_abi_call_generator_tool.pas` | Paired C++ call-side generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `py_abi_call_generator_tool.pas`');
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
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('GenerateABICallPyReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABICallPyReadme: %d valid APIs',
    [Length(SupportedFuncs)]));

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

  Log(PFormat('GenerateABICallPyReadme: %d lines generated',
    [L.Count]));
end;

end.
