unit py_mcp_generator_tool;

{*******************************************************************************
 * py_mcp_generator_tool - LingoFuse Python Tool Provider Code & Doc Generator
 *
 * Python analogue of pas_mcp_generator_tool. Consumes one TPascal_Func_Model
 * and produces two artifacts:
 *
 *   1. GeneratePythonCode()   -> <unit>_tool_provider.py
 *      A complete, runnable Python module that registers every supported
 *      top-level function as a LingoFuse Call API and advertises each API as
 *      an MCP tool through the beacon.
 *
 *   2. GeneratePythonReadme() -> <unit>_tool_provider_python.md
 *      An English Markdown user guide that documents:
 *        - runtime architecture
 *        - a complete, runnable test script (the generated .py itself)
 *        - a step-by-step build & test procedure
 *        - every exposed tool with JSON input/output examples
 *        - Python environment portability notes
 *        - debugging and troubleshooting
 *
 * =============================================================================
 * PYTHON PACKAGE SOURCING POLICY
 * =============================================================================
 * The generated Python module imports from `lingofuse._lf_native`. Two ways
 * to provide that package:
 *
 *   Preferred: an independent `py-lingofuse` repository / PyPI package.
 *   Fallback : the `lingofuse/` directory shipped inside the
 *              LingoFuse-pasAgent-v3 repository (`<v3>/src/lingofuse/`).
 *
 * The README explains both paths and tells the user to prefer the standalone
 * repository if one exists, and to use the v3 copy otherwise.
 *
 * =============================================================================
 * NOTES
 * =============================================================================
 *   - Fixed beacon application name: 'agent_main_app'
 *   - Fixed IPC endpoint          : 'ipc:agent'
 *   - Nested routines (NestLevel <> 0) are skipped by the model itself.
 *   - Python string literals iterate with TP_Char (UTF-16) so non-ASCII
 *     content survives code generation (see MakePythonIdentifier and
 *     PyStrLit).
 *   - All README content is generated in English.
 * ****************************************************************************}

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

{$IFDEF FPC}
  {$CODEPAGE UTF8}
{$ENDIF FPC}

interface

uses
  SysUtils, Classes,
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

{* Generate the Python tool provider module. Caller owns the returned list. *}
function GeneratePythonCode(Model: TPascal_Func_Model): TPascalStringList;

{* Generate the English Markdown README. Caller owns the returned list. *}
function GeneratePythonReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  { Enable verbose generation logging (DoStatus). }
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[py_mcp_generator] %s', [Msg.Text]);
end;

// -----------------------------------------------------------------------------
// Type helpers
// -----------------------------------------------------------------------------

function IsSupportedType(const Typ: TP_String): boolean;
begin
  Result := Typ.Same('int64', 'double', 'string');
end;

function PascalTypeToPythonType(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := 'int'
  else if Typ.Same('double') then Result := 'float'
  else if Typ.Same('string') then Result := 'str'
  else Result := 'Any';
end;

function PascalTypeToJsonSchemaType(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := 'integer'
  else if Typ.Same('double') then Result := 'number'
  else if Typ.Same('string') then Result := 'string'
  else Result := 'string';
end;

function PascalTypeDefaultValue(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := '0'
  else if Typ.Same('double') then Result := '0.0'
  else if Typ.Same('string') then Result := '""'
  else Result := 'None';
end;

function PascalTypeToJsonLiteral(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := '0'
  else if Typ.Same('double') then Result := '0.0'
  else if Typ.Same('string') then Result := '""'
  else Result := 'null';
end;

// -----------------------------------------------------------------------------
// Python string literal escaping
//
// Iterates with TP_Char (UTF-16) so non-ASCII code points survive. Using
// SystemChar (AnsiChar) would truncate every multi-byte character.
// -----------------------------------------------------------------------------

function PyStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then Result := Result + '\"'
    else if c = #92 then Result := Result + '\\'
    else if c = #10 then Result := Result + '\n'
    else if c = #13 then Result := Result + '\r'
    else if c = #9 then Result := Result + '\t'
    else Result := Result + c;
  end;
  Result := Result + '"';
end;

// -----------------------------------------------------------------------------
// Python identifier maker
// -----------------------------------------------------------------------------

function IsPythonIdentChar(c: TP_Char): boolean;
begin
  Result := ((c >= 'a') and (c <= 'z'))
    or ((c >= 'A') and (c <= 'Z'))
    or ((c >= '0') and (c <= '9'))
    or (c = '_');
end;

function MakePythonIdentifier(const Name: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if IsPythonIdentChar(c) then
      Result := Result + c
    else
      Result := Result + '_';
  end;
  if Result.Len = 0 then
    Result := 'unnamed';
  if (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

// -----------------------------------------------------------------------------
// Comment description extraction (Doxygen-aware)
//
// Operates directly on the UTF-16 TP_String without going through
// TPascalStringList / SystemString. The TPascalStringList path silently
// drops every non-ASCII character.
// -----------------------------------------------------------------------------

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
      Line := Line.TrimChar(#32#9);

      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
          // Skip Doxygen tag line.
        end
        else
        begin
          if Line[1] = '*' then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);

          if Line.Len > 0 then
          begin
            if Result.Len > 0 then Result := Result + ' ';
            Result := Result + Line;
          end;
        end;
      end;
    end;

    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
end;

function GetTableCellText(const Comment: TP_String): TP_String;
begin
  Result := GetFullDescription(Comment);
  Result := Result.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// -----------------------------------------------------------------------------
// Shared function filtering
// -----------------------------------------------------------------------------

type
  TValidFuncArray = array of TFunctionStructure;

function CollectValidFunctions(Model: TPascal_Func_Model): TValidFuncArray;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  if Model = nil then Exit;

  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(f.Params) do
      if not IsSupportedType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": param "%s" has unsupported type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and not IsSupportedType(f.ReturnType) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" unsupported',
        [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function UniqueApiName(const BaseName: TP_String;
  UsedList: TPascalStringList): TP_String;
var
  Counter: integer;
  Candidate: TP_String;
begin
  Result := BaseName;
  if UsedList.IndexOf(Result) < 0 then Exit;

  Counter := 1;
  while True do
  begin
    Candidate := BaseName.Text + '_' + umlIntToStr(Counter).Text;
    if UsedList.IndexOf(Candidate) < 0 then
    begin
      Result := Candidate;
      Exit;
    end;
    Inc(Counter);
  end;
end;

function MakeAppNameFromUnit(const UnitName: TP_String): TP_String;
var
  tmp: TP_String;
begin
  tmp := UnitName;
  if umlMultipleMatch('*.pas', tmp) then
    tmp := umlChangeFileExt(tmp.Text, '').Text;
  Result := tmp.ReplaceChar('.', '_').ReplaceChar('-', '_');
end;

// =============================================================================
// SECTION 1 - Python code generator
// =============================================================================

function GeneratePythonCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TValidFuncArray;
  UnitName, AppName, BeaconApp, RegisterApi, AgentLogApi, IpcEndpoint: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  Description, ParamName, ParamExtract, CallArgs, ParamDeclPython: TP_String;
  RetTypePy: TP_String;
  PropJson, RequiredList: TP_String;
  TotalFuncCount: integer;

  HeaderLines, HelperLines, InternalCallLines: TPascalStringList;
  LoggingLines, CallbackLines, RegisterToolLines: TPascalStringList;
  RegisterToolsLines, RegisterAPIsLines, ExecuteLines: TPascalStringList;
  ResultLines: TPascalStringList;

  function BuildParamDeclPython(const Params: TParamArray): TP_String;
  var k: integer;
  begin
    Result := '';
    for k := 0 to High(Params) do
    begin
      if k > 0 then Result := Result + ', ';
      Result := Result + MakePythonIdentifier(Params[k].Name) + ': ' +
        PascalTypeToPythonType(Params[k].PascalType);
    end;
  end;

  function BuildArgListPython(const Params: TParamArray): TP_String;
  var k: integer;
  begin
    Result := '';
    for k := 0 to High(Params) do
    begin
      if k > 0 then Result := Result + ', ';
      Result := Result + MakePythonIdentifier(Params[k].Name);
    end;
  end;

begin
  Result := nil;
  if Model = nil then begin Log('GeneratePythonCode: model is nil.'); Exit; end;

  UnitName := Model.UnitName;
  if UnitName = '' then begin Log('GeneratePythonCode: UnitName is empty.'); Exit; end;

  AppName := MakeAppNameFromUnit(UnitName);

  BeaconApp := 'agent_main_app';
  RegisterApi := 'register_agent';
  AgentLogApi := 'agent_log';
  IpcEndpoint := 'ipc:agent';

  Log(PFormat('Generating Python code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectValidFunctions(Model);
  TotalFuncCount := Length(SupportedFuncs);
  if TotalFuncCount = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  HelperLines := TPascalStringList.Create;
  InternalCallLines := TPascalStringList.Create;
  LoggingLines := TPascalStringList.Create;
  CallbackLines := TPascalStringList.Create;
  RegisterToolLines := TPascalStringList.Create;
  RegisterToolsLines := TPascalStringList.Create;
  RegisterAPIsLines := TPascalStringList.Create;
  ExecuteLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // =========================================================================
    // 1. Header and imports
    // =========================================================================
    HeaderLines.Add('# -*- coding: utf-8 -*-');
    HeaderLines.Add('"""');
    HeaderLines.Add(UnitName + ' - Auto-generated LingoFuse Python tool provider');
    HeaderLines.Add('');
    HeaderLines.Add('This module was auto-generated from a Pascal source model.');
    HeaderLines.Add('It exposes the following public entry points:');
    HeaderLines.Add('    RegisterAPIs()          -> create the LingoFuse application handle');
    HeaderLines.Add('    RegisterTools()         -> advertise all APIs to the beacon');
    HeaderLines.Add('    Execute_And_Reg_all()   -> full startup sequence (recommended)');
    HeaderLines.Add('');
    HeaderLines.Add('Run this file directly to start the provider:');
    HeaderLines.Add('    python ' + UnitName + '_tool_provider.py');
    HeaderLines.Add('"""');
    HeaderLines.Add('');
    HeaderLines.Add('import sys');
    HeaderLines.Add('import json');
    HeaderLines.Add('import ctypes');
    HeaderLines.Add('import threading');
    HeaderLines.Add('from typing import Any, Optional');
    HeaderLines.Add('');
    HeaderLines.Add('try:');
    HeaderLines.Add('    from lingofuse._lf_native import (');
    HeaderLines.Add('        DataHnd, AppHnd,');
    HeaderLines.Add('        LF_CreateData,');
    HeaderLines.Add('        LF_FreeData,');
    HeaderLines.Add('        LF_CreateApp,');
    HeaderLines.Add('        LF_FreeApp,');
    HeaderLines.Add('        LF_RegisterCall,');
    HeaderLines.Add('        LF_WriteBuffer,');
    HeaderLines.Add('        LF_ReadBuffer,');
    HeaderLines.Add('        LF_GetPos,');
    HeaderLines.Add('        LF_SetPos,');
    HeaderLines.Add('        LF_GetSize,');
    HeaderLines.Add('        LF_GetBuffer,');
    HeaderLines.Add('        LF_PrepareClient,');
    HeaderLines.Add('        LF_ResetPrepare,');
    HeaderLines.Add('        LF_PrepareDone,');
    HeaderLines.Add('        LF_ExitMainThread,');
    HeaderLines.Add('        LF_Shutdown,');
    HeaderLines.Add('        LF_Call,');
    HeaderLines.Add('        LF_SetOption,');
    HeaderLines.Add('        LF_CheckMainThread,');
    HeaderLines.Add('        LFCallFunc,');
    HeaderLines.Add('    )');
    HeaderLines.Add('except ImportError as _imp_err:');
    HeaderLines.Add('    print(f"[FATAL] lingofuse package is not available: {_imp_err}", file=sys.stderr)');
    HeaderLines.Add('    sys.exit(1)');
    HeaderLines.Add('');
    HeaderLines.Add('');
    HeaderLines.Add('# ==== Application metadata ====');
    HeaderLines.Add('MY_APP_NAME = ' + PyStrLit(AppName));
    HeaderLines.Add('MY_APP_DESC = ' + PyStrLit('Tool provider for unit ' + UnitName));
    HeaderLines.Add('IPC_ENDPOINT = ' + PyStrLit(IpcEndpoint));
    HeaderLines.Add('BEACON_APP = ' + PyStrLit(BeaconApp));
    HeaderLines.Add('REGISTER_API = ' + PyStrLit(RegisterApi));
    HeaderLines.Add('AGENT_LOG_API = ' + PyStrLit(AgentLogApi));
    HeaderLines.Add('DEBUG_LOG = True');
    HeaderLines.Add('');
    HeaderLines.Add('');

    // =========================================================================
    // 2. Low-level string helpers
    // =========================================================================
    HelperLines.Add('# ==== Low-level string helpers ====');
    HelperLines.Add('');
    HelperLines.Add('def _write_string(hnd, s):');
    HelperLines.Add('    """Write a UTF-8 string with a null terminator to a DataHandle."""');
    HelperLines.Add('    if isinstance(s, str):');
    HelperLines.Add('        s = s.encode("utf-8")');
    HelperLines.Add('    if len(s) > 0:');
    HelperLines.Add('        LF_WriteBuffer(hnd, s, len(s))');
    HelperLines.Add('    LF_WriteBuffer(hnd, b"\\x00", 1)');
    HelperLines.Add('');
    HelperLines.Add('');
    HelperLines.Add('def _read_string_bytes(hnd) -> bytes:');
    HelperLines.Add('    """Read a null-terminated UTF-8 string from a DataHandle.');
    HelperLines.Add('');
    HelperLines.Add('    If no null terminator is found, return the entire remaining buffer.');
    HelperLines.Add('    This mirrors LF_ReadString behavior in lingofuse_import.pas.');
    HelperLines.Add('    """');
    HelperLines.Add('    pos = LF_GetPos(hnd)');
    HelperLines.Add('    size = LF_GetSize(hnd)');
    HelperLines.Add('    if pos >= size:');
    HelperLines.Add('        return b""');
    HelperLines.Add('    ptr = LF_GetBuffer(hnd)');
    HelperLines.Add('    if not ptr:');
    HelperLines.Add('        return b""');
    HelperLines.Add('    cptr = ctypes.cast(ptr, ctypes.POINTER(ctypes.c_byte))');
    HelperLines.Add('    end = pos');
    HelperLines.Add('    while end < size and cptr[end] != 0:');
    HelperLines.Add('        end += 1');
    HelperLines.Add('    if end < size:');
    HelperLines.Add('        data_len = end - pos');
    HelperLines.Add('        if data_len == 0:');
    HelperLines.Add('            LF_SetPos(hnd, end + 1)');
    HelperLines.Add('            return b""');
    HelperLines.Add('        raw = (ctypes.c_byte * data_len)()');
    HelperLines.Add('        LF_ReadBuffer(hnd, raw, data_len)');
    HelperLines.Add('        LF_SetPos(hnd, end + 1)');
    HelperLines.Add('        return bytes(raw)');
    HelperLines.Add('    else:');
    HelperLines.Add('        data_len = size - pos');
    HelperLines.Add('        if data_len == 0:');
    HelperLines.Add('            return b""');
    HelperLines.Add('        raw = (ctypes.c_byte * data_len)()');
    HelperLines.Add('        LF_ReadBuffer(hnd, raw, data_len)');
    HelperLines.Add('        LF_SetPos(hnd, size)');
    HelperLines.Add('        return bytes(raw)');
    HelperLines.Add('');
    HelperLines.Add('');
    HelperLines.Add('def _ret2str(v) -> str:');
    HelperLines.Add('    """Convert a return value to a printable string for logging."""');
    HelperLines.Add('    if v is None:');
    HelperLines.Add('        return "None"');
    HelperLines.Add('    return str(v)');
    HelperLines.Add('');
    HelperLines.Add('');

    // =========================================================================
    // 3. Internal call stubs
    // =========================================================================
    InternalCallLines.Add('# ==== Internal call stubs ====');
    InternalCallLines.Add('#');
    InternalCallLines.Add('# Each stub corresponds to an original Pascal routine and has the');
    InternalCallLines.Add('# correct signature with Python type annotations.');
    InternalCallLines.Add('# Replace the placeholder body with the actual implementation.');
    InternalCallLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakePythonIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);

        InternalCallName := 'internal_call_' + ApiName;

        ParamDeclPython := BuildParamDeclPython(Params);
        CallArgs := BuildArgListPython(Params);

        if IsFunction then
        begin
          RetTypePy := PascalTypeToPythonType(ReturnType);
          InternalCallLines.Add('def ' + InternalCallName + '(' + ParamDeclPython + ') -> ' + RetTypePy + ':');
        end
        else
        begin
          RetTypePy := 'None';
          InternalCallLines.Add('def ' + InternalCallName + '(' + ParamDeclPython + '):');
        end;

        InternalCallLines.Add('    """Wrapper for the original routine ' + PyStrLit(Name) + '.');
        InternalCallLines.Add('    TODO: replace this placeholder with the actual implementation.');
        InternalCallLines.Add('    """');
        InternalCallLines.Add('    if DEBUG_LOG:');
        InternalCallLines.Add('        print(f"[internal_call_' + ApiName + '] called")');
        if IsFunction then
        begin
          InternalCallLines.Add('    # Default return value; replace with actual logic.');
          InternalCallLines.Add('    return ' + PascalTypeDefaultValue(ReturnType));
        end
        else
          InternalCallLines.Add('    pass  # TODO: implement the routine body');
        InternalCallLines.Add('');
      end;
    end;
    InternalCallLines.Add('');

    // =========================================================================
    // 4. Asynchronous logging
    // =========================================================================
    LoggingLines.Add('# ==== Asynchronous logging to the beacon ====');
    LoggingLines.Add('');
    LoggingLines.Add('def _send_log_async(msg: str):');
    LoggingLines.Add('    """Fire-and-forget log to the beacon''s agent_log API."""');
    LoggingLines.Add('    def _worker():');
    LoggingLines.Add('        try:');
    LoggingLines.Add('            data = LF_CreateData(AGENT_LOG_API.encode("utf-8"))');
    LoggingLines.Add('            if not data:');
    LoggingLines.Add('                return');
    LoggingLines.Add('            try:');
    LoggingLines.Add('                payload = json.dumps({"message": msg}, ensure_ascii=False).encode("utf-8")');
    LoggingLines.Add('                _write_string(data, payload)');
    LoggingLines.Add('                result = LF_Call(BEACON_APP.encode("utf-8"), data, 3000)');
    LoggingLines.Add('                if result:');
    LoggingLines.Add('                    LF_FreeData(result)');
    LoggingLines.Add('            finally:');
    LoggingLines.Add('                LF_FreeData(data)');
    LoggingLines.Add('        except Exception:');
    LoggingLines.Add('            pass');
    LoggingLines.Add('    threading.Thread(target=_worker, daemon=True).start()');
    LoggingLines.Add('');
    LoggingLines.Add('');

    // =========================================================================
    // 5. API callbacks
    // =========================================================================
    CallbackLines.Add('# ==== API callbacks ====');
    CallbackLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakePythonIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);

        CallbackName := 'callback_' + ApiName;
        InternalCallName := 'internal_call_' + ApiName;

        ParamExtract := '';
        CallArgs := '';
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := MakePythonIdentifier(Params[j].Name);
          if CallArgs <> '' then
            CallArgs := CallArgs + ', ';
          CallArgs := CallArgs + ParamName;

          ParamExtract := ParamExtract + '        ' + ParamName + ' = data.get(' + PyStrLit(Params[j].Name) + ')';
          if Params[j].PascalType.Same('int64') then
            ParamExtract := ParamExtract + ' or 0'
          else if Params[j].PascalType.Same('double') then
            ParamExtract := ParamExtract + ' or 0.0'
          else if Params[j].PascalType.Same('string') then
            ParamExtract := ParamExtract + ' or ""';
          ParamExtract := ParamExtract + sLineBreak;
        end;

        CallbackLines.Add('@LFCallFunc');
        CallbackLines.Add('def ' + CallbackName + '(_Trigger, _In, _Out):');
        CallbackLines.Add('    """Auto-generated callback for API ' + PyStrLit(Name) + '."""');
        CallbackLines.Add('    try:');
        CallbackLines.Add('        json_bytes = _read_string_bytes(_In)');
        CallbackLines.Add('        if DEBUG_LOG:');
        CallbackLines.Add('            print(f"[' + Name + '] Input JSON: {json_bytes!r}")');
        CallbackLines.Add('');
        CallbackLines.Add('        if not json_bytes:');
        CallbackLines.Add('            _write_string(_Out, json.dumps({"error": "Empty input"}).encode("utf-8"))');
        CallbackLines.Add('            if DEBUG_LOG:');
        CallbackLines.Add('                print(f"[' + Name + '] Error: Empty input")');
        CallbackLines.Add('                _send_log_async(f"[' + Name + '] Error: Empty input")');
        CallbackLines.Add('            return');
        CallbackLines.Add('');
        CallbackLines.Add('        try:');
        CallbackLines.Add('            data = json.loads(json_bytes.decode("utf-8"))');
        CallbackLines.Add('        except Exception as _parse_err:');
        CallbackLines.Add('            _write_string(_Out, json.dumps({"error": f"Invalid JSON: {_parse_err}"}).encode("utf-8"))');
        CallbackLines.Add('            if DEBUG_LOG:');
        CallbackLines.Add('                print(f"[' + Name + '] Invalid JSON: {_parse_err}")');
        CallbackLines.Add('                _send_log_async(f"[' + Name + '] Invalid JSON: {_parse_err}")');
        CallbackLines.Add('            return');
        CallbackLines.Add('');

        if ParamExtract <> '' then
          CallbackLines.Add(ParamExtract);

        if IsFunction then
        begin
          CallbackLines.Add('        ret = ' + InternalCallName + '(' + CallArgs + ')');
          CallbackLines.Add('        _write_string(_Out, json.dumps({"result": ret}, ensure_ascii=False).encode("utf-8"))');
          CallbackLines.Add('        if DEBUG_LOG:');
          CallbackLines.Add('            print(f"[' + Name + '] Called -> {_ret2str(ret)}")');
          CallbackLines.Add('            _send_log_async(f"[' + Name + '] Called -> {_ret2str(ret)}")');
        end
        else
        begin
          CallbackLines.Add('        ' + InternalCallName + '(' + CallArgs + ')');
          CallbackLines.Add('        _write_string(_Out, json.dumps({"status": "ok"}).encode("utf-8"))');
          CallbackLines.Add('        if DEBUG_LOG:');
          CallbackLines.Add('            print(f"[' + Name + '] OK")');
          CallbackLines.Add('            _send_log_async(f"[' + Name + '] OK")');
        end;

        CallbackLines.Add('    except Exception as _err:');
        CallbackLines.Add('        try:');
        CallbackLines.Add('            _write_string(_Out, json.dumps({"error": str(_err)}).encode("utf-8"))');
        CallbackLines.Add('        except Exception:');
        CallbackLines.Add('            pass');
        CallbackLines.Add('        if DEBUG_LOG:');
        CallbackLines.Add('            print(f"[' + Name + '] Exception: {_err}")');
        CallbackLines.Add('            _send_log_async(f"[' + Name + '] Exception: {_err}")');
        CallbackLines.Add('');
        CallbackLines.Add('');
      end;
    end;

    // =========================================================================
    // 6. Tool registration helper
    // =========================================================================
    RegisterToolLines.Add('# ==== Tool registration with the beacon ====');
    RegisterToolLines.Add('');
    RegisterToolLines.Add('def _register_tool(tool_def: dict) -> bool:');
    RegisterToolLines.Add('    """Register a single tool with the beacon via the register_agent API."""');
    RegisterToolLines.Add('    tool_name = tool_def.get("name", "?")');
    RegisterToolLines.Add('    target_app = tool_def.get("target_app", "?")');
    RegisterToolLines.Add('    target_api = tool_def.get("target_api", "?")');
    RegisterToolLines.Add('    if DEBUG_LOG:');
    RegisterToolLines.Add('        print(f"[_register_tool] Registering {tool_name} -> {target_app}.{target_api}")');
    RegisterToolLines.Add('');
    RegisterToolLines.Add('    data = LF_CreateData(REGISTER_API.encode("utf-8"))');
    RegisterToolLines.Add('    if not data:');
    RegisterToolLines.Add('        if DEBUG_LOG:');
    RegisterToolLines.Add('            print(f"[_register_tool] Failed to create data handle")');
    RegisterToolLines.Add('        return False');
    RegisterToolLines.Add('    try:');
    RegisterToolLines.Add('        payload = json.dumps(tool_def, ensure_ascii=False).encode("utf-8")');
    RegisterToolLines.Add('        _write_string(data, payload)');
    RegisterToolLines.Add('        result = LF_Call(BEACON_APP.encode("utf-8"), data, 5000)');
    RegisterToolLines.Add('        if not result:');
    RegisterToolLines.Add('            if DEBUG_LOG:');
    RegisterToolLines.Add('                print(f"[_register_tool] No response from beacon")');
    RegisterToolLines.Add('            return False');
    RegisterToolLines.Add('        try:');
    RegisterToolLines.Add('            resp_bytes = _read_string_bytes(result)');
    RegisterToolLines.Add('            if not resp_bytes:');
    RegisterToolLines.Add('                if DEBUG_LOG:');
    RegisterToolLines.Add('                    print(f"[_register_tool] Empty response")');
    RegisterToolLines.Add('                return False');
    RegisterToolLines.Add('            resp = json.loads(resp_bytes.decode("utf-8"))');
    RegisterToolLines.Add('            if resp.get("status") == "ok":');
    RegisterToolLines.Add('                if DEBUG_LOG:');
    RegisterToolLines.Add('                    print(f"[_register_tool] OK: {tool_name}")');
    RegisterToolLines.Add('                return True');
    RegisterToolLines.Add('            if DEBUG_LOG:');
    RegisterToolLines.Add('                print(f"[_register_tool] Error: {resp.get(''message'', ''?'')}")');
    RegisterToolLines.Add('            return False');
    RegisterToolLines.Add('        finally:');
    RegisterToolLines.Add('            LF_FreeData(result)');
    RegisterToolLines.Add('    finally:');
    RegisterToolLines.Add('        LF_FreeData(data)');
    RegisterToolLines.Add('');
    RegisterToolLines.Add('');

    // =========================================================================
    // 7. RegisterTools()
    // =========================================================================
    RegisterToolsLines.Add('# ==== RegisterTools ====');
    RegisterToolsLines.Add('');
    RegisterToolsLines.Add('def RegisterTools() -> bool:');
    RegisterToolsLines.Add('    """Register all supported routines as tools with the beacon."""');
    RegisterToolsLines.Add('    total_count = ' + umlIntToStr(TotalFuncCount));
    RegisterToolsLines.Add('    reg_count = 0');
    RegisterToolsLines.Add('    if DEBUG_LOG:');
    RegisterToolsLines.Add('        print(f"[RegisterTools] Starting registration of {total_count} tools...")');
    RegisterToolsLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakePythonIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);

        Description := GetFullDescription(Comment);
        if Description = '' then
          Description := 'Auto-generated tool for ' + Name;

        RegisterToolsLines.Add('    tool_def = {');
        RegisterToolsLines.Add('        "name": ' + PyStrLit(ApiName) + ',');
        RegisterToolsLines.Add('        "description": ' + PyStrLit(Description) + ',');
        RegisterToolsLines.Add('        "target_app": MY_APP_NAME,');
        RegisterToolsLines.Add('        "target_api": ' + PyStrLit(ApiName) + ',');
        RegisterToolsLines.Add('        "parameters": {');
        RegisterToolsLines.Add('            "type": "object",');
        RegisterToolsLines.Add('            "properties": {');

        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;

          PropJson := '                ' + PyStrLit(ParamName) + ': {"type": ' +
            PyStrLit(PascalTypeToJsonSchemaType(Params[j].PascalType));
          if Params[j].Description <> '' then
            PropJson := PropJson + ', "description": ' + PyStrLit(Params[j].Description)
          else
            PropJson := PropJson + ', "description": ' + PyStrLit(ParamName + ' parameter');
          PropJson := PropJson + '},';
          RegisterToolsLines.Add(PropJson);
        end;

        RegisterToolsLines.Add('            },');

        RequiredList := '';
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;
          if RequiredList <> '' then
            RequiredList := RequiredList + ', ';
          RequiredList := RequiredList + PyStrLit(ParamName);
        end;
        if RequiredList <> '' then
          RegisterToolsLines.Add('            "required": [' + RequiredList + '],')
        else
          RegisterToolsLines.Add('            "required": [],');

        RegisterToolsLines.Add('        },');
        RegisterToolsLines.Add('    }');
        RegisterToolsLines.Add('    if _register_tool(tool_def):');
        RegisterToolsLines.Add('        reg_count += 1');
        RegisterToolsLines.Add('');
      end;
    end;

    RegisterToolsLines.Add('    if DEBUG_LOG:');
    RegisterToolsLines.Add('        print(f"[RegisterTools] Registered {reg_count} / {total_count}")');
    RegisterToolsLines.Add('    return reg_count == total_count');
    RegisterToolsLines.Add('');
    RegisterToolsLines.Add('');

    // =========================================================================
    // 8. RegisterAPIs()
    // =========================================================================
    RegisterAPIsLines.Add('# ==== RegisterAPIs ====');
    RegisterAPIsLines.Add('');
    RegisterAPIsLines.Add('def RegisterAPIs() -> Optional[Any]:');
    RegisterAPIsLines.Add('    """Create the LingoFuse app and register all API callbacks."""');
    RegisterAPIsLines.Add('    app = LF_CreateApp(MY_APP_NAME.encode("utf-8"), MY_APP_DESC.encode("utf-8"))');
    RegisterAPIsLines.Add('    if not app:');
    RegisterAPIsLines.Add('        if DEBUG_LOG:');
    RegisterAPIsLines.Add('            print(f"[RegisterAPIs] Failed to create app")');
    RegisterAPIsLines.Add('        return None');
    RegisterAPIsLines.Add('');
    RegisterAPIsLines.Add('    if DEBUG_LOG:');
    RegisterAPIsLines.Add('        print(f"[RegisterAPIs] Application ''{MY_APP_NAME}'' created")');
    RegisterAPIsLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakePythonIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);
        CallbackName := 'callback_' + ApiName;
        Description := GetFullDescription(Comment);
        if Description = '' then
          Description := 'Auto-generated API for ' + Name;

        RegisterAPIsLines.Add('    LF_RegisterCall(');
        RegisterAPIsLines.Add('        app,');
        RegisterAPIsLines.Add('        ' + PyStrLit(ApiName) + '.encode("utf-8"),');
        RegisterAPIsLines.Add('        ' + PyStrLit(Description) + '.encode("utf-8"),');
        RegisterAPIsLines.Add('        None,');
        RegisterAPIsLines.Add('        ' + CallbackName + ',');
        RegisterAPIsLines.Add('    )');
      end;
    end;

    RegisterAPIsLines.Add('');
    RegisterAPIsLines.Add('    if DEBUG_LOG:');
    RegisterAPIsLines.Add('        print(f"[RegisterAPIs] Registered ' + umlIntToStr(TotalFuncCount) + ' APIs")');
    RegisterAPIsLines.Add('');
    RegisterAPIsLines.Add('    return app');
    RegisterAPIsLines.Add('');
    RegisterAPIsLines.Add('');

    // =========================================================================
    // 9. Execute_And_Reg_all + __main__
    // =========================================================================
    ExecuteLines.Add('# ==== One-click startup ====');
    ExecuteLines.Add('');
    ExecuteLines.Add('def Execute_And_Reg_all() -> bool:');
    ExecuteLines.Add('    """');
    ExecuteLines.Add('    Full startup sequence:');
    ExecuteLines.Add('        1. RegisterAPIs         - create app and register callbacks.');
    ExecuteLines.Add('        2. LF_PrepareClient     - connect to the beacon via IPC_ENDPOINT.');
    ExecuteLines.Add('        3. LF_PrepareDone       - wait until the connection is ready.');
    ExecuteLines.Add('        4. RegisterTools        - advertise all APIs as tools.');
    ExecuteLines.Add('    """');
    ExecuteLines.Add('    app = RegisterAPIs()');
    ExecuteLines.Add('    if app is None:');
    ExecuteLines.Add('        if DEBUG_LOG:');
    ExecuteLines.Add('            print(f"[Execute_And_Reg_all] RegisterAPIs failed")');
    ExecuteLines.Add('        return False');
    ExecuteLines.Add('');
    ExecuteLines.Add('    LF_ResetPrepare()');
    ExecuteLines.Add('    LF_PrepareClient(IPC_ENDPOINT.encode("utf-8"), app)');
    ExecuteLines.Add('    if LF_PrepareDone() > 0:');
    ExecuteLines.Add('        return RegisterTools()');
    ExecuteLines.Add('    if DEBUG_LOG:');
    ExecuteLines.Add('        print(f"[Execute_And_Reg_all] LF_PrepareDone failed")');
    ExecuteLines.Add('    return False');
    ExecuteLines.Add('');
    ExecuteLines.Add('');
    ExecuteLines.Add('# ==== Main entry point ====');
    ExecuteLines.Add('');
    ExecuteLines.Add('if __name__ == "__main__":');
    ExecuteLines.Add('    print(f"=== {MY_APP_NAME} tool provider ===")');
    ExecuteLines.Add('    if not Execute_And_Reg_all():');
    ExecuteLines.Add('        print("Startup failed.")');
    ExecuteLines.Add('        sys.exit(1)');
    ExecuteLines.Add('    print("Ready. Type ''exit'' and press Enter to quit.")');
    ExecuteLines.Add('    try:');
    ExecuteLines.Add('        while True:');
    ExecuteLines.Add('            line = input()');
    ExecuteLines.Add('            if line.strip().lower() == "exit":');
    ExecuteLines.Add('                break');
    ExecuteLines.Add('    except (KeyboardInterrupt, EOFError):');
    ExecuteLines.Add('        pass');
    ExecuteLines.Add('    LF_ExitMainThread()');
    ExecuteLines.Add('    LF_Shutdown()');
    ExecuteLines.Add('    print("Shutdown complete.")');
    ExecuteLines.Add('');

    // =========================================================================
    // 10. Assemble the final output
    // =========================================================================
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.Add('');
    ResultLines.Add('');
    ResultLines.AddStrings(HelperLines);
    ResultLines.AddStrings(InternalCallLines);
    ResultLines.AddStrings(LoggingLines);
    ResultLines.AddStrings(CallbackLines);
    ResultLines.AddStrings(RegisterToolLines);
    ResultLines.AddStrings(RegisterToolsLines);
    ResultLines.AddStrings(RegisterAPIsLines);
    ResultLines.AddStrings(ExecuteLines);

    Result := ResultLines;
    Log(PFormat('Generated %d lines of Python code for %d supported routines.',
      [ResultLines.Count, TotalFuncCount]));

  finally
    HeaderLines.Free;
    HelperLines.Free;
    InternalCallLines.Free;
    LoggingLines.Free;
    CallbackLines.Free;
    RegisterToolLines.Free;
    RegisterToolsLines.Free;
    RegisterAPIsLines.Free;
    ExecuteLines.Free;
    UsedApiNames.Free;
  end;
end;

// =============================================================================
// SECTION 2 - Python README generator (English Markdown)
// =============================================================================

function GeneratePythonReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  ValidFuncs: TValidFuncArray;
  UnitName, AppName: TP_String;
  i, j: integer;
  f: TFunctionStructure;
  desc, shortDesc, row: TP_String;

  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - Python Tool Provider');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `py_mcp_generator_tool.pas`;');
    L.Add('> stays in sync with the code file.');
    L.Add('>');
    L.Add('> **Source unit**   : `' + UnitName + '`');
    L.Add('> **Provider file** : `' + UnitName + '_tool_provider.py`');
    L.Add('> **Exposed APIs**  : ' + umlIntToStr(Length(ValidFuncs)).Text);
    L.Add('');
    L.Add('---');
    L.Add('');
  end;

  procedure EmitOverview;
  begin
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('This README explains how to install, run, and test the auto-generated');
    L.Add('Python tool provider `' + UnitName + '_tool_provider.py`.');
    L.Add('');
    L.Add('The module registers every top-level function of `' + UnitName + '` as');
    L.Add('a LingoFuse Call API and advertises them as MCP tools through the');
    L.Add('beacon. An LLM client discovers these tools through the beacon and');
    L.Add('invokes them over IPC.');
    L.Add('');
    L.Add('### 1.1 Python package sourcing policy');
    L.Add('');
    L.Add('The generated module imports from `lingofuse._lf_native`. Two sources');
    L.Add('for that package are supported, in order of preference:');
    L.Add('');
    L.Add('| # | Source | When to use it | How to get it |');
    L.Add('|---|--------|----------------|---------------|');
    L.Add('| **1** | **Standalone `py-lingofuse` repository or PyPI package** | If one exists for your deployment | `pip install py-lingofuse` or `git clone <py-lingofuse-repo-url>` |');
    L.Add('| **2** | **`lingofuse/` directory shipped inside LingoFuse-pasAgent-v3** | Fallback when no standalone Python repository is available | `<v3-repo-url>` -> `<v3>/src/lingofuse/` |');
    L.Add('');
    L.Add('> **Placeholder note**: the URLs above are literal placeholders.');
    L.Add('> Replace them with the actual clone URLs before distributing this');
    L.Add('> README. If no standalone Python repository exists at the time of');
    L.Add('> reading, use the v3 copy - it is functionally equivalent for the');
    L.Add('> subset of `_lf_native` that the generated provider uses.');
    L.Add('');
    L.Add('### 1.2 Required external program');
    L.Add('');
    L.Add('The provider is a client of the LingoFuse beacon. The beacon binary');
    L.Add('ships with the Pascal runtime, not with any Python repository:');
    L.Add('');
    L.Add('| Dependency | Purpose | How to obtain |');
    L.Add('|------------|---------|---------------|');
    L.Add('| `pascal_agent_service.exe` | Beacon server that routes tool calls | Built from `<v3>/src/pascal_agent_service.lpr` |');
    L.Add('| `mcp_api_tool.py` | MCP gateway that exposes tools to LLM clients | Ships with v3 at `<v3>/src/mcp_api_tool.py` |');
    L.Add('| `generate_agent_json.py` | Produces MCP client config files | Ships with v3 at `<v3>/src/generate_agent_json.py` |');
    L.Add('');
    L.Add('### 1.3 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + UnitName + '_tool_provider.py` | Main provider module (runnable as-is) |');
    L.Add('| `' + UnitName + '_tool_provider_python.md` | This README |');
    L.Add('');
  end;

  procedure EmitArchitecture;
  begin
    L.Add('## 2. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph Runtime["LingoFuse Runtime"]');
    L.Add('        BEACON["pascal_agent_service.exe<br/>(agent_main_app)"]');
    L.Add('        IPC["ipc:agent"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Provider["Generated Python Provider"]');
    L.Add('        REG_APIS["RegisterAPIs()<br/>create App + register Call APIs"]');
    L.Add('        PREPARE["LF_PrepareClient + LF_PrepareDone"]');
    L.Add('        REG_TOOLS["RegisterTools()<br/>advertise tools to beacon"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Tools["Exposed APIs"]');
    L.Add('        T_API["Call APIs from ' + UnitName + '"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["LLM / MCP Client"]');
    L.Add('        LLM["mcp_api_tool.py<br/>LM Studio / Claude / ..."]');
    L.Add('    end');
    L.Add('');
    L.Add('    BEACON <--> IPC');
    L.Add('    REG_APIS --> PREPARE');
    L.Add('    PREPARE --> IPC');
    L.Add('    REG_TOOLS --> BEACON');
    L.Add('    LLM -->|discover| BEACON');
    L.Add('    LLM -->|invoke| IPC');
    L.Add('    IPC --> T_API');
    L.Add('');
    L.Add('    style Runtime fill:#e3f2fd,stroke:#1565c0');
    L.Add('    style Provider fill:#fff3e0,stroke:#e65100');
    L.Add('    style Tools fill:#e8f5e9,stroke:#2e7d32');
    L.Add('    style Client fill:#f3e5f5,stroke:#6a1b9a');
    L.Add('```');
    L.Add('');
    L.Add('**Call chain**');
    L.Add('');
    L.Add('1. Start `pascal_agent_service.exe` (the beacon); it listens on');
    L.Add('   `ipc:agent`.');
    L.Add('2. Start the provider with `python ' + UnitName + '_tool_provider.py`.');
    L.Add('3. `RegisterAPIs` creates a LingoFuse App and registers every top-level');
    L.Add('   function of `' + UnitName + '` as a Call API.');
    L.Add('4. `LF_PrepareClient` connects to `ipc:agent`; `LF_PrepareDone` waits');
    L.Add('   for readiness.');
    L.Add('5. `RegisterTools` pushes the JSON schema of every API to the beacon.');
    L.Add('6. An MCP client (`mcp_api_tool.py` + LM Studio / Claude) discovers');
    L.Add('   the tools and invokes them over IPC.');
    L.Add('');
  end;

  procedure EmitTestScript;
  begin
    L.Add('## 3. Test Provider Script');
    L.Add('');
    L.Add('The generated `' + UnitName + '_tool_provider.py` is **already runnable');
    L.Add('as-is**: it contains a full `if __name__ == "__main__"` block that');
    L.Add('starts the provider and keeps it alive until the user types `exit`.');
    L.Add('There is no separate test script to write.');
    L.Add('');
    L.Add('The sections below show:');
    L.Add('');
    L.Add('1. The minimal invocation (once the environment is set up).');
    L.Add('2. The two ways to provide the `lingofuse` package.');
    L.Add('');
    L.Add('### 3.1 Minimal invocation');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName + ' tool provider ===');
    L.Add('[RegisterAPIs] Application ''' + AppName + ''' created');
    L.Add('[RegisterAPIs] Registered N APIs');
    L.Add('[_register_tool] Registering <name> -> ' + AppName + '.<api>');
    L.Add('[_register_tool] OK: <name>');
    L.Add('...');
    L.Add('[RegisterTools] Registered N / N');
    L.Add('Ready. Type ''exit'' and press Enter to quit.');
    L.Add('```');
    L.Add('');
    L.Add('### 3.2 Path A - install a standalone Python package (preferred)');
    L.Add('');
    L.Add('If your deployment provides a standalone `py-lingofuse` package:');
    L.Add('');
    L.Add('```bash');
    L.Add('pip install py-lingofuse');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('No environment variable changes are needed; `import lingofuse` will');
    L.Add('resolve to the installed package automatically.');
    L.Add('');
    L.Add('### 3.3 Path B - use the v3-shipped `lingofuse/` directory (fallback)');
    L.Add('');
    L.Add('If no standalone Python repository exists, point `PYTHONPATH` at the');
    L.Add('v3 `src/` directory. The `lingofuse/` subdirectory inside it is a');
    L.Add('complete, working Python package for the subset of `_lf_native` that');
    L.Add('this provider uses.');
    L.Add('');
    L.Add('**Windows (cmd.exe)**:');
    L.Add('');
    L.Add('```bat');
    L.Add('set PYTHONPATH=D:\\LingoFuse-pasAgent-v3\\src');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (PowerShell)**:');
    L.Add('');
    L.Add('```powershell');
    L.Add('$env:PYTHONPATH = "D:\\LingoFuse-pasAgent-v3\\src"');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('**Linux / macOS**:');
    L.Add('');
    L.Add('```bash');
    L.Add('export PYTHONPATH=/path/to/LingoFuse-pasAgent-v3/src');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('### 3.4 Environment variable reference');
    L.Add('');
    L.Add('| Variable | Required | Purpose |');
    L.Add('|----------|----------|---------|');
    L.Add('| `PYTHONPATH` | Only if using Path B | Adds v3 `src/` to the import path so `import lingofuse` resolves |');
    L.Add('| `PATH` | Recommended | Locate the native `z_ipc_*.dll` / `libz_ipc_*` runtime library at process start |');
    L.Add('');
  end;

  procedure EmitBuildTestProcedure;
  begin
    L.Add('## 4. Build & Test Procedure');
    L.Add('');
    L.Add('Follow the steps in order. Each step is independent and can be');
    L.Add('verified before moving on.');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    S1["1. Prepare env<br/>(PYTHONPATH / pip install)"]');
    L.Add('    S2["2. Verify import<br/>(python -c ''''''import lingofuse'''''')"]');
    L.Add('    S3["3. Start beacon<br/>(pascal_agent_service.exe)"]');
    L.Add('    S4["4. Start provider<br/>(python provider.py)"]');
    L.Add('    S5["5. Start mcp_api_tool<br/>+ generate client config"]');
    L.Add('    S6["6. Start agent<br/>(LM Studio / Claude / ...)"]');
    L.Add('    S7["7. Test API<br/>(invoke tool from agent)"]');
    L.Add('');
    L.Add('    S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7');
    L.Add('');
    L.Add('    style S1 fill:#e3f2fd');
    L.Add('    style S2 fill:#e3f2fd');
    L.Add('    style S3 fill:#e8f5e9');
    L.Add('    style S4 fill:#fff3e0');
    L.Add('    style S5 fill:#f3e5f5');
    L.Add('    style S6 fill:#fce4ec');
    L.Add('    style S7 fill:#e0f7fa');
    L.Add('```');
    L.Add('');

    L.Add('### Step 1 - Prepare the Python environment');
    L.Add('');
    L.Add('Make sure `python` on your `PATH` is 3.8 or newer:');
    L.Add('');
    L.Add('```bash');
    L.Add('python --version');
    L.Add('```');
    L.Add('');
    L.Add('Then choose one of the two package paths from §3:');
    L.Add('');
    L.Add('- **Path A** (standalone package): `pip install py-lingofuse`');
    L.Add('- **Path B** (v3 fallback): set `PYTHONPATH` to `<v3>/src`');
    L.Add('');

    L.Add('### Step 2 - Verify the lingofuse package is importable');
    L.Add('');
    L.Add('Run this one-liner. It must print the native library path and no');
    L.Add('ImportError:');
    L.Add('');
    L.Add('```bash');
    L.Add('python -c "import lingofuse._lf_native as m; print(''OK'', m.__file__)"');
    L.Add('```');
    L.Add('');
    L.Add('If this fails:');
    L.Add('');
    L.Add('- Path A: re-check `pip show py-lingofuse`.');
    L.Add('- Path B: re-check `PYTHONPATH` (see §3.3 for the exact syntax for');
    L.Add('  your shell).');
    L.Add('');

    L.Add('### Step 3 - Start the beacon');
    L.Add('');
    L.Add('Open a new terminal and run:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('./pascal_agent_service.exe');
    L.Add('```');
    L.Add('');
    L.Add('The beacon listens on `ipc:agent`. Leave this terminal running.');
    L.Add('');

    L.Add('### Step 4 - Start the provider');
    L.Add('');
    L.Add('Open a second terminal and run:');
    L.Add('');
    L.Add('```bash');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('Expected output (identical to §3.1):');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName + ' tool provider ===');
    L.Add('[RegisterTools] Registered N / N');
    L.Add('Ready. Type ''exit'' and press Enter to quit.');
    L.Add('```');
    L.Add('');

    L.Add('### Step 5 - Start mcp_api_tool and generate the client config');
    L.Add('');
    L.Add('Open a third terminal:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('python mcp_api_tool.py --generate-configs --output-dir ./mcp_configs');
    L.Add('```');
    L.Add('');
    L.Add('This produces per-client JSON config files for LM Studio, Claude');
    L.Add('Desktop, Continue.dev, Jan, DeepSeek, and a generic MCP client. Pick');
    L.Add('the one matching your agent.');
    L.Add('');
    L.Add('Then start the MCP gateway:');
    L.Add('');
    L.Add('```bash');
    L.Add('python mcp_api_tool.py --transport stdio');
    L.Add('```');
    L.Add('');
    L.Add('(Or `--transport http --port 8000` for streamable HTTP.)');
    L.Add('');

    L.Add('### Step 6 - Start the agent (LLM client)');
    L.Add('');
    L.Add('Depending on the agent:');
    L.Add('');
    L.Add('- **LM Studio**: Settings -> MCP Servers -> paste the content of');
    L.Add('  `lmstudio_stdio.json` (or `lmstudio_http.json`). Restart.');
    L.Add('- **Claude Desktop**: edit `claude_desktop_config.json` and merge the');
    L.Add('  `mcpServers` section from `claude_stdio.json`. Restart.');
    L.Add('- **Continue.dev / Jan / DeepSeek**: merge the corresponding JSON and');
    L.Add('  restart.');
    L.Add('');
    L.Add('Once restarted, the agent will list your tools alongside its own.');
    L.Add('');

    L.Add('### Step 7 - Test the API');
    L.Add('');
    L.Add('In the agent, ask it to call one of the registered tools. For example,');
    L.Add('if the source unit registered `add(a: Int64, b: Int64): Int64`:');
    L.Add('');
    L.Add('```');
    L.Add('Please call the "add" tool with a=5 and b=7.');
    L.Add('```');
    L.Add('');
    L.Add('The agent will:');
    L.Add('');
    L.Add('1. Discover the `add` tool through the beacon.');
    L.Add('2. Build the JSON arguments `{"a": 5, "b": 7}`.');
    L.Add('3. Call through `mcp_api_tool` to your provider.');
    L.Add('4. Receive `{"result": 12}` and present it.');
    L.Add('');
    L.Add('The provider terminal prints the following (with `DEBUG_LOG = True`):');
    L.Add('');
    L.Add('```');
    L.Add('[add] Input JSON: b''{"a": 5, "b": 7}''');
    L.Add('[add] Called -> 12');
    L.Add('```');
    L.Add('');
  end;

  procedure EmitToolReference;
  var
    ii, jj: integer;
  begin
    L.Add('## 5. Tool Reference');
    L.Add('');
    L.Add('This section lists every API exposed by the generated provider. Each');
    L.Add('API corresponds to one top-level function of `' + UnitName + '`.');
    L.Add('');

    if Length(ValidFuncs) = 0 then
    begin
      L.Add('> **WARNING: this provider exposes no APIs.**');
      L.Add('>');
      L.Add('> Possible reasons:');
      L.Add('> 1. The source unit has no top-level functions');
      L.Add('>    (nested routines in `class` / `record` are skipped).');
      L.Add('> 2. Every function failed the type check.');
      L.Add('>');
      L.Add('> Supported types: `Int64`, `Double`, `string` only.');
      L.Add('');
      Exit;
    end;

    L.Add('Total APIs: **' + umlIntToStr(Length(ValidFuncs)).Text + '**.');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');
    for ii := 0 to High(ValidFuncs) do
    begin
      f := ValidFuncs[ii];
      shortDesc := GetTableCellText(f.Comment);
      if shortDesc.Len > 60 then
        shortDesc := shortDesc.GetString(1, 61) + '...';
      if f.IsFunction then
        row := '| ' + umlIntToStr(ii + 1).Text + ' | `' + MakePythonIdentifier(f.Name) + '` | function | ' +
          umlIntToStr(Length(f.Params)).Text + ' | `' + f.ReturnType + '` | ' + shortDesc + ' |'
      else
        row := '| ' + umlIntToStr(ii + 1).Text + ' | `' + MakePythonIdentifier(f.Name) + '` | procedure | ' +
          umlIntToStr(Length(f.Params)).Text + ' | - | ' + shortDesc + ' |';
      L.Add(row);
    end;
    L.Add('');

    for ii := 0 to High(ValidFuncs) do
    begin
      f := ValidFuncs[ii];
      desc := GetFullDescription(f.Comment);

      L.Add('### 5.' + umlIntToStr(ii + 1).Text + ' `' + MakePythonIdentifier(f.Name) + '`');
      L.Add('');
      L.Add('- Original Pascal function: `' + f.Name + '`');
      L.Add('- Exposed API name: `' + MakePythonIdentifier(f.Name) + '`');
      if f.IsFunction then
        L.Add('- Kind: `function`, returns `' + f.ReturnType + '`')
      else
        L.Add('- Kind: `procedure`');
      if desc.Len > 0 then
        L.Add('- Description: ' + desc);
      L.Add('');

      if Length(f.Params) > 0 then
      begin
        L.Add('**Parameters**');
        L.Add('');
        L.Add('| Name | Pascal type | JSON type | Description |');
        L.Add('|------|-------------|-----------|-------------|');
        for jj := 0 to High(f.Params) do
        begin
          L.Add('| `' + f.Params[jj].Name + '` | `' + f.Params[jj].PascalType + '` | `' +
            PascalTypeToJsonSchemaType(f.Params[jj].PascalType) + '` | ' +
            GetTableCellText(f.Params[jj].Description) + ' |');
        end;
        L.Add('');
      end;

      L.Add('**Input JSON example**');
      L.Add('');
      L.Add('```json');
      if Length(f.Params) = 0 then
        L.Add('{}')
      else
      begin
        L.Add('{');
        for jj := 0 to High(f.Params) do
        begin
          row := '  "' + f.Params[jj].Name + '": ' + PascalTypeToJsonLiteral(f.Params[jj].PascalType);
          if jj < High(f.Params) then row := row + ',';
          L.Add(row);
        end;
        L.Add('}');
      end;
      L.Add('```');
      L.Add('');

      L.Add('**Output JSON example**');
      L.Add('');
      L.Add('```json');
      if f.IsFunction then
        L.Add('{ "result": ' + PascalTypeToJsonLiteral(f.ReturnType) + ' }')
      else
        L.Add('{ "status": "ok" }');
      L.Add('```');
      L.Add('');
    end;
  end;

  procedure EmitJsonSchemaSpec;
  begin
    L.Add('## 6. JSON Schema Specification');
    L.Add('');
    L.Add('For each tool the provider sends a JSON Schema to the beacon through');
    L.Add('the `register_agent` API. The type whitelist is fixed by the');
    L.Add('normalized `TPascal_Func_Model` output.');
    L.Add('');
    L.Add('| Pascal normalized type | JSON Schema type | Python type | Example value |');
    L.Add('|------------------------|------------------|-------------|---------------|');
    L.Add('| `int64` | `integer` | `int` | `42` |');
    L.Add('| `double` | `number` | `float` | `3.14` |');
    L.Add('| `string` | `string` | `str` | `"hello"` |');
    L.Add('');
    L.Add('**Every other type** (for example `Boolean`, arrays, records, objects,');
    L.Add('enums, interfaces, function pointers) is **NOT supported**. Functions');
    L.Add('that use them are silently dropped. If you need to pass a complex');
    L.Add('value, serialize it into a `string` first.');
    L.Add('');
  end;

  procedure EmitTroubleshooting;
  begin
    L.Add('## 7. Debugging & Troubleshooting');
    L.Add('');
    L.Add('### 7.1 Global configuration variables');
    L.Add('');
    L.Add('The generated module exposes the following top-level constants. Edit');
    L.Add('them before running, or override them after import.');
    L.Add('');
    L.Add('| Name | Default | Purpose |');
    L.Add('|------|---------|---------|');
    L.Add('| `MY_APP_NAME` | `' + AppName + '` | LingoFuse application name |');
    L.Add('| `MY_APP_DESC` | (auto) | Application description |');
    L.Add('| `IPC_ENDPOINT` | `ipc:agent` | IPC endpoint |');
    L.Add('| `BEACON_APP` | `agent_main_app` | Beacon application name |');
    L.Add('| `REGISTER_API` | `register_agent` | Tool-registration API name |');
    L.Add('| `AGENT_LOG_API` | `agent_log` | Log API name |');
    L.Add('| `DEBUG_LOG` | `True` | Verbose logging toggle |');
    L.Add('');
    L.Add('### 7.2 Common problems');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `ModuleNotFoundError: No module named ''lingofuse''` | Package not installed and `PYTHONPATH` not set | See §3.2 / §3.3 |');
    L.Add('| `ModuleNotFoundError: No module named ''lingofuse._lf_native''` | Partial install | Reinstall, or point `PYTHONPATH` at `<v3>/src` |');
    L.Add('| `OSError: cannot load library LingoFuse64.dll` | Native library not on `PATH` | Copy `z_ipc_*.dll` / `LingoFuse*.dll` next to your project or add to `PATH` |');
    L.Add('| `Execute_And_Reg_all()` returns False | Beacon not running | Start `pascal_agent_service.exe` first |');
    L.Add('| `LF_PrepareDone` returns 0 | Main thread already active in this process | Reuse the existing runtime, or call `LF_Shutdown` first |');
    L.Add('| `[_register_tool] No response from beacon` | `ipc:agent` unreachable | Confirm beacon is running; check firewall |');
    L.Add('| `[_register_tool] Error: ...` | Tool rejected by beacon | Check `DEBUG_LOG` output; verify schema |');
    L.Add('| Tool missing from agent list | Function filtered out | Check param/return types against §6 whitelist |');
    L.Add('| `callback_<name> Exception` in log | Exception in user code | Inspect the log; the callback wraps user code in try/except |');
    L.Add('| Unicode mojibake in input JSON | Encoding mismatch | Ensure the caller sends UTF-8; `json.loads` defaults to UTF-8 |');
    L.Add('');
    L.Add('### 7.3 Enabling detailed logs');
    L.Add('');
    L.Add('Set `DEBUG_LOG = True` in the module (default: `True`). Every callback');
    L.Add('then prints its input JSON, its result, and any error to the beacon');
    L.Add('via `agent_log`, and to stdout locally.');
    L.Add('');
  end;

  procedure EmitPythonPortability;
  begin
    L.Add('## 8. Python Environment Portability');
    L.Add('');
    L.Add('The generated module is a plain Python 3 source file with no exotic');
    L.Add('dependencies beyond the `lingofuse` package and the standard library');
    L.Add('(`sys`, `json`, `ctypes`, `threading`, `typing`).');
    L.Add('');
    L.Add('### 8.1 Supported Python versions');
    L.Add('');
    L.Add('Python 3.8 and later. Older 3.x versions may work but are untested.');
    L.Add('');
    L.Add('### 8.2 Virtual environments');
    L.Add('');
    L.Add('Either pattern works:');
    L.Add('');
    L.Add('```bash');
    L.Add('# venv');
    L.Add('python -m venv .venv');
    L.Add('.venv\\Scripts\\activate      # Windows');
    L.Add('source .venv/bin/activate      # Linux / macOS');
    L.Add('pip install py-lingofuse');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Path B inside a virtual environment');
    L.Add('');
    L.Add('If you use the v3-shipped `lingofuse/` fallback together with a venv,');
    L.Add('simply set `PYTHONPATH` after activating the venv:');
    L.Add('');
    L.Add('```bash');
    L.Add('.venv\\Scripts\\activate');
    L.Add('set PYTHONPATH=D:\\LingoFuse-pasAgent-v3\\src');
    L.Add('python ' + UnitName + '_tool_provider.py');
    L.Add('```');
    L.Add('');
    L.Add('The venv''s own `site-packages` is always searched first; `PYTHONPATH`');
    L.Add('only adds a fallback location.');
    L.Add('');
    L.Add('### 8.4 Frozen executables (PyInstaller / Nuitka)');
    L.Add('');
    L.Add('The module can be frozen. Add `<v3>/src/lingofuse` to the bundled');
    L.Add('hidden imports and make sure the native `z_ipc_*.dll` files are');
    L.Add('placed next to the resulting `.exe`. See the `build_mcp_api_tool.ps1`');
    L.Add('script in v3 for a reference PyInstaller configuration.');
    L.Add('');
  end;

  procedure EmitResources;
  begin
    L.Add('## 9. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| Standalone `py-lingofuse` (if available) | Preferred source of the `lingofuse` Python package |');
    L.Add('| `LingoFuse-pasAgent-v3` repository | Fallback source of `lingofuse/`, plus beacon and MCP gateway |');
    L.Add('| `<v3>/src/pascal_agent_service.lpr` | Beacon server source |');
    L.Add('| `<v3>/src/mcp_api_tool.py` | MCP gateway that exposes the tools |');
    L.Add('| `<v3>/src/generate_agent_json.py` | MCP client config generator |');
    L.Add('| `<v3>/src/lingofuse/_lf_native.py` | Low-level ctypes bindings used by this provider |');
    L.Add('| `<v3>/src/lingofuse/lf_io.py` | Reference NUL-terminated framing helpers |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('_End of document. Generated by `py_mcp_generator_tool.pas`._');
    L.Add('');
  end;

begin
  Result := TPascalStringList.Create;
  L := Result;

  if Model = nil then
  begin
    L.Add('# README generation skipped');
    L.Add('');
    L.Add('Reason: supplied `TPascal_Func_Model` is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName = '' then
  begin
    L.Add('# README generation skipped');
    L.Add('');
    L.Add('Reason: `Model.UnitName` is empty.');
    Exit;
  end;

  AppName := MakeAppNameFromUnit(UnitName);
  ValidFuncs := CollectValidFunctions(Model);

  EmitHeader;
  EmitOverview;
  EmitArchitecture;
  EmitTestScript;
  EmitBuildTestProcedure;
  EmitToolReference;
  EmitJsonSchemaSpec;
  EmitTroubleshooting;
  EmitPythonPortability;
  EmitResources;

  Log(PFormat('GeneratePythonReadme: %d lines, %d APIs.',
    [L.Count, Length(ValidFuncs)]));
end;

end.
