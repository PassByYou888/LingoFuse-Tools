unit http_py_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallPythonCode - main entry point for the call module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallPythonCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_py_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_py_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification
// -----------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal') or T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

// ABI_Type_To_Pascal_Decl - Pascal type keyword used only by the README
// generator, to show the reader the exact signature they would find
// in the source unit.
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
  else
    Result := '';
end;

// ABI_Type_To_Py_Annotation - Python type annotation for a parameter
// or a return value. Pure documentation; Python is dynamically typed.
function ABI_Type_To_Py_Annotation(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'str'
  else if ABI_Type_Is_Float(T) then
    Result := 'float'
  else if ABI_Type_Is_Int(T) then
    Result := 'int'
  else
    Result := 'Any';
end;

// ABI_Type_To_Json_Wire_Type - Coarse wire type used only by the
// README generator.
function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

// ABI_Type_Needs_Precision_Note - True when the ABI type is a 64-bit
// integer whose full range can exceed a JavaScript Number's precision.
// Used only by the README generator to inject a warning.
function ABI_Type_Needs_Precision_Note(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// MakeApiName - canonicalize an arbitrary identifier into one that is
// safe to use simultaneously as:
//   * an API name on the LingoFuse wire,
//   * a URL path segment for the bridge's HTTP route,
//   * a JavaScript object key,
//   * a C++ / Pascal / Python identifier.
//
// The character set replaced here MUST match the character set replaced
// by every other generator in this toolchain:
//   * http_pas_abi_service_generator_tool
//   * http_pas_abi_call_generator_tool
//   * http_js_abi_call_generator_tool
//   * http_py_abi_service_generator_tool
//   * http_cpp_abi_service_generator_tool
//   * http_cpp_abi_call_generator_tool
//
// If the sets diverge, the same source routine would be routed to
// different API names on the service side and on the call side, and
// every cross-language call would fail at runtime.
//
// Replaced character set:
//   space, tab, '.', '/', '\', '@', ':', '#', '?', '&', '=', '+', '-'
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafePyIdent(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if Result.Same('False') or Result.Same('None') or Result.Same('True') or Result.Same('and') or Result.Same('as') or Result.Same('assert') or
    Result.Same('async') or Result.Same('await') or Result.Same('break') or Result.Same('class') or Result.Same('continue') or
    Result.Same('def') or Result.Same('del') or Result.Same('elif') or Result.Same('else') or Result.Same('except') or Result.Same('finally') or
    Result.Same('for') or Result.Same('from') or Result.Same('global') or Result.Same('if') or Result.Same('import') or Result.Same('in') or
    Result.Same('is') or Result.Same('lambda') or Result.Same('nonlocal') or Result.Same('not') or Result.Same('or') or Result.Same('pass') or
    Result.Same('raise') or Result.Same('return') or Result.Same('try') or Result.Same('while') or Result.Same('with') or Result.Same('yield') then
    Result := Result + '_';
end;

// PyStrLit - produce a complete Python string literal (single quoted,
// with the surrounding quotes included).
function PyStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #39;   // opening single quote
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #39: Result.Append('\' + #39);
      #92: Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9:  Result.Append('\t');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\x');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
        end
        else
          Result.Append(c);
    end;
  end;
  Result.Append(#39);   // closing single quote
end;

// -----------------------------------------------------------------------------
// Markdown helpers (used only by the README generator)
// -----------------------------------------------------------------------------

function MdCellEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '|' then
      Result.Append('\|')
    else if c = #10 then
      Result.Append(' ')
    else if c = #13 then
    // skip
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// -----------------------------------------------------------------------------
// Comment description extraction
// -----------------------------------------------------------------------------

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

function BuildPyParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, ann: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyIdent(Params[i].Name, i);
    ann := ABI_Type_To_Py_Annotation(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + ': ' + ann;
  end;
end;

// BuildPyArgLiteralList - produce the Python list-of-argument-names
// literal, e.g. "[a, b, c]".
function BuildPyArgLiteralList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ']';
end;

function BuildPyCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePyIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildPascalDecl - full Pascal declaration of a routine, using the
// ORIGINAL routine name and Pascal types. Used by the README only.
function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafePyIdent(F.Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    if i > 0 then
      ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

// BuildPySignature - full Python signature of the generated call
// function, using the DISAMBIGUATED API name. Used by the README only.
function BuildPySignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
begin
  if F.IsFunction then
    Result := ApiName + '(' + BuildPyParamList(F.Params) + ') -> ' + ABI_Type_To_Py_Annotation(F.ReturnType)
  else
    Result := ApiName + '(' + BuildPyParamList(F.Params) + ')';
end;

// BuildPyAsyncSignature - full Python signature of the generated async
// call function, using the DISAMBIGUATED API name. Used by the README
// only.
function BuildPyAsyncSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
begin
  if F.IsFunction then
    Result := 'async ' + ApiName + '_async(' + BuildPyParamList(F.Params) + ') -> ' + ABI_Type_To_Py_Annotation(F.ReturnType)
  else
    Result := 'async ' + ApiName + '_async(' + BuildPyParamList(F.Params) + ')';
end;

// -----------------------------------------------------------------------------
// Supported-function filtering
// -----------------------------------------------------------------------------

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  F: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    F := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(F.Params) do
      if not ABI_Type_Is_Supported(F.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"', [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and F.IsFunction and (not ABI_Type_Is_Supported(F.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type', [F.Name.Text, F.ReturnType.Text]));
    end;

    if Supported and (F.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: routine with empty Name');
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := F;
    end;
  end;
end;

// =============================================================================
// PYTHON CALL MODULE GENERATOR
// =============================================================================

procedure EmitPyHeader(Lines: TPascalStringList; const UnitName, NormalizedUnit, BaseUrl: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('"""');
  Lines.Add('Auto-generated by http_py_abi_call_generator_tool.pas.');
  Lines.Add('Source model unit: ' + UnitName.Text + '.');
  Lines.Add('Do not edit by hand unless you know what you are doing.');
  Lines.Add('');
  Lines.Add('Wire protocol (HTTP/JSON path):');
  Lines.Add('  request  = POST <base_url>/<api>  with body');
  Lines.Add('             { "args": [v1, v2, ...] }');
  Lines.Add('  response = { "code": 0,  "result": ... }   on success');
  Lines.Add('             { "code": -1, "error":  ... }   on failure');
  Lines.Add('');
  Lines.Add('This module is a Python HTTP/JSON client. It sends requests');
  Lines.Add('directly to a bridge process (bridge.py) over plain HTTP.');
  Lines.Add('The bridge performs the HTTP <-> LingoFuse conversion; this');
  Lines.Add('module only deals with JSON strings.');
  Lines.Add('');
  Lines.Add('Two callables are generated per supported routine:');
  Lines.Add('  <api>(...)        synchronous, blocking, returns the result.');
  Lines.Add('  <api>_async(...)  asynchronous coroutine, `await`-able.');
  Lines.Add('');
  Lines.Add('The synchronous variant uses `requests` directly. The');
  Lines.Add('asynchronous variant awaits `asyncio.to_thread(...)` (with a');
  Lines.Add('fallback executor on Python 3.7 / 3.8), so the blocking HTTP');
  Lines.Add('call runs in a worker thread and never blocks the event loop.');
  Lines.Add('');
  Lines.Add('The user is expected to:');
  Lines.Add('  1. Install the `requests` package (pip install requests).');
  Lines.Add('  2. Set HTTP_CALL_BASE_URL to the bridge''s base URL plus the');
  Lines.Add('     target app name.');
  Lines.Add('  3. Call any of the generated functions.');
  Lines.Add('');
  Lines.Add('All comments and log messages in this file are English.');
  Lines.Add('"""');
  Lines.Add('');
  Lines.Add('import asyncio');
  Lines.Add('import functools');
  Lines.Add('import json');
  Lines.Add('import logging');
  Lines.Add('from typing import Any, List');
  Lines.Add('');
  Lines.Add('try:');
  Lines.Add('    import requests');
  Lines.Add('except ImportError:');
  Lines.Add('    raise ImportError(');
  Lines.Add('        ''The generated HTTP/JSON call module requires the ''');
  Lines.Add('        ''`requests` package. Install it with: pip install requests''');
  Lines.Add('    )');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# asyncio compatibility');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('#');
  Lines.Add('# ``asyncio.to_thread`` was added in Python 3.9. On 3.7 / 3.8 we');
  Lines.Add('# provide a thin fallback that runs the blocking callable in the');
  Lines.Add('# default thread-pool executor of the running event loop. The');
  Lines.Add('# coroutine awaits a future either way, so it never blocks the');
  Lines.Add('# event loop.');
  Lines.Add('#');
  Lines.Add('try:');
  Lines.Add('    from asyncio import to_thread as _to_thread');
  Lines.Add('except ImportError:');
  Lines.Add('    async def _to_thread(func, *args, **kwargs):');
  Lines.Add('        loop = asyncio.get_event_loop()');
  Lines.Add('        return await loop.run_in_executor(');
  Lines.Add('            None, functools.partial(func, *args, **kwargs))');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Configuration');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('# Base URL of the bridge, including the target app name.');
  Lines.Add('# The full URL for API "X" is: HTTP_CALL_BASE_URL + "/" + "X"');
  Lines.Add('HTTP_CALL_BASE_URL = ' + PyStrLit(BaseUrl).Text);
  Lines.Add('');
  Lines.Add('# Per-request timeout, in seconds. Set to None to wait forever.');
  Lines.Add('HTTP_CALL_TIMEOUT = 30.0');
  Lines.Add('');
  Lines.Add('# Set to True to log every request and response at INFO level.');
  Lines.Add('DEBUG_LOG = False');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Logging');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('log = logging.getLogger(''http_json_call'')');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Exception');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('class HTTPCallError(Exception):');
  Lines.Add('    """');
  Lines.Add('    Raised when a remote HTTP/JSON call fails.');
  Lines.Add('');
  Lines.Add('    Attributes:');
  Lines.Add('        code        : bridge / service error code.');
  Lines.Add('                      -1 for network errors or service exceptions.');
  Lines.Add('                      -2 for request-shape errors.');
  Lines.Add('                      -3 for bridge pre-check failures.');
  Lines.Add('        http_status : HTTP status code of the response, or 0 if the');
  Lines.Add('                      request never produced a response.');
  Lines.Add('    """');
  Lines.Add('    def __init__(self, message: str, code: int = -1,');
  Lines.Add('                 http_status: int = 0):');
  Lines.Add('        super().__init__(message)');
  Lines.Add('        self.code = code');
  Lines.Add('        self.http_status = http_status');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Internal: POST a JSON request to the bridge');
  Lines.Add('#');
  Lines.Add('# On success, returns the value of the response JSON''s "result"');
  Lines.Add('# field. On failure, raises HTTPCallError.');
  Lines.Add('#');
  Lines.Add('# This is the single synchronous transport primitive. The async');
  Lines.Add('# variants call it through `_to_thread(...)` so they do not');
  Lines.Add('# duplicate the wire logic.');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('def _call_api(api_name: str, args: List[Any]) -> Any:');
  Lines.Add('    """');
  Lines.Add('    Send a JSON request to the bridge and return the result.');
  Lines.Add('');
  Lines.Add('    This is the single point where every generated function enters');
  Lines.Add('    the transport layer. It never returns an error object; failures');
  Lines.Add('    are always raised as HTTPCallError.');
  Lines.Add('    """');
  Lines.Add('    url = HTTP_CALL_BASE_URL.rstrip(''/'') + ''/'' + api_name');
  Lines.Add('    body = json.dumps({''args'': args}, ensure_ascii=False)');
  Lines.Add('    headers = {''Content-Type'': ''application/json; charset=utf-8''}');
  Lines.Add('');
  Lines.Add('    if DEBUG_LOG:');
  Lines.Add('        log.info(''POST %s body=%s'', url, body)');
  Lines.Add('');
  Lines.Add('    try:');
  Lines.Add('        resp = requests.post(');
  Lines.Add('            url,');
  Lines.Add('            data=body.encode(''utf-8''),');
  Lines.Add('            headers=headers,');
  Lines.Add('            timeout=HTTP_CALL_TIMEOUT,');
  Lines.Add('        )');
  Lines.Add('    except requests.Timeout as e:');
  Lines.Add('        raise HTTPCallError(''Request timed out: '' + str(e), -1, 0)');
  Lines.Add('    except requests.RequestException as e:');
  Lines.Add('        raise HTTPCallError(''Network error: '' + str(e), -1, 0)');
  Lines.Add('');
  Lines.Add('    if DEBUG_LOG:');
  Lines.Add('        log.info(''Response %d: %s'', resp.status_code, resp.text)');
  Lines.Add('');
  Lines.Add('    if resp.status_code != 200:');
  Lines.Add('        raise HTTPCallError(');
  Lines.Add('            ''HTTP '' + str(resp.status_code) + '' '' + resp.reason +');
  Lines.Add('                '' : '' + (resp.text or ''''),');
  Lines.Add('            -1,');
  Lines.Add('            resp.status_code,');
  Lines.Add('        )');
  Lines.Add('');
  Lines.Add('    text = resp.text');
  Lines.Add('    if not text:');
  Lines.Add('        raise HTTPCallError(''Empty response from bridge'', -1, resp.status_code)');
  Lines.Add('');
  Lines.Add('    try:');
  Lines.Add('        parsed = json.loads(text)');
  Lines.Add('    except json.JSONDecodeError as e:');
  Lines.Add('        raise HTTPCallError(');
  Lines.Add('            ''Invalid JSON response: '' + str(e),');
  Lines.Add('            -1,');
  Lines.Add('            resp.status_code,');
  Lines.Add('        )');
  Lines.Add('');
  Lines.Add('    if not isinstance(parsed, dict):');
  Lines.Add('        raise HTTPCallError(');
  Lines.Add('            ''Response is not a JSON object'',');
  Lines.Add('            -1,');
  Lines.Add('            resp.status_code,');
  Lines.Add('        )');
  Lines.Add('');
  Lines.Add('    if ''code'' not in parsed:');
  Lines.Add('        # Bridge-level error before the LingoFuse call reached a service.');
  Lines.Add('        if isinstance(parsed.get(''error''), str):');
  Lines.Add('            raise HTTPCallError(parsed[''error''], -1, resp.status_code)');
  Lines.Add('        raise HTTPCallError(');
  Lines.Add('            ''Response has no "code" field'',');
  Lines.Add('            -1,');
  Lines.Add('            resp.status_code,');
  Lines.Add('        )');
  Lines.Add('');
  Lines.Add('    if parsed[''code''] != 0:');
  Lines.Add('        raise HTTPCallError(');
  Lines.Add('            parsed.get(''error'') or ''Remote call failed'',');
  Lines.Add('            int(parsed[''code'']),');
  Lines.Add('            resp.status_code,');
  Lines.Add('        )');
  Lines.Add('');
  Lines.Add('    return parsed.get(''result'')');
  Lines.Add('');
  Lines.Add('');
end;

// EmitPyFunction - write one typed synchronous call function and its
// matching asynchronous coroutine.
//
// NOTE: all loop variables are declared in the enclosing var block,
// because FPC does not support Delphi-style inline variable
// declarations (for var i := ...).
procedure EmitPyFunction(Lines: TPascalStringList; const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamList, ArgLiteralList: TP_String;
  Annotation: TP_String;
  Description: TP_String;
  i: integer;
  PName, PDesc: TP_String;
begin
  ParamList := BuildPyParamList(F.Params);
  ArgLiteralList := BuildPyArgLiteralList(F.Params);
  Description := GetFullDescription(F.Comment);

  if F.IsFunction then
    Annotation := ' -> ' + ABI_Type_To_Py_Annotation(F.ReturnType)
  else
    Annotation := '';

  // ---- Synchronous variant ----------------------------------------------
  Lines.Add('def ' + ApiName.Text + '(' + ParamList.Text + ')' + Annotation.Text + ':');

  Lines.Add('    """');
  if Description.Len > 0 then
    Lines.Add('    ' + Description.Text)
  else
    Lines.Add('    HTTP/JSON API: ' + ApiName.Text + '.');
  Lines.Add('');
  Lines.Add('    Sends a POST request to the bridge with the given arguments');
  Lines.Add('    and returns the deserialized result.');
  Lines.Add('');

  // Parameter description block.
  if Length(F.Params) > 0 then
  begin
    Lines.Add('    Args:');
    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafePyIdent(F.Params[i].Name, i);
      PDesc := F.Params[i].Description.TrimChar(#32#9#13#10);
      PDesc := PDesc.ReplaceChar(#13#10, ' ');
      if PDesc.Len > 120 then
        PDesc := PDesc.GetString(1, 121);
      if PDesc.Len = 0 then
        PDesc := '(no description)';
      Lines.Add('        ' + PName.Text + ': ' + PDesc.Text);
    end;
    Lines.Add('');
  end;

  if F.IsFunction then
    Lines.Add('    Returns: The remote result converted to Python.')
  else
    Lines.Add('    Returns: None.');
  Lines.Add('');
  Lines.Add('    Raises:');
  Lines.Add('        HTTPCallError: if the call fails for any reason.');
  Lines.Add('    """');

  if F.IsFunction then
    Lines.Add('    return _call_api(' + PyStrLit(ApiName).Text + ', ' + ArgLiteralList.Text + ')')
  else
    Lines.Add('    _call_api(' + PyStrLit(ApiName).Text + ', ' + ArgLiteralList.Text + ')');
  Lines.Add('');
  Lines.Add('');

  // ---- Asynchronous variant ---------------------------------------------
  Lines.Add('async def ' + ApiName.Text + '_async(' + ParamList.Text + ')' + Annotation.Text + ':');
  Lines.Add('    """');
  if Description.Len > 0 then
    Lines.Add('    ' + Description.Text + ' (asynchronous)')
  else
    Lines.Add('    HTTP/JSON API: ' + ApiName.Text + ' (asynchronous).');
  Lines.Add('');
  Lines.Add('    Coroutine variant of :func:`' + ApiName.Text + '`. The blocking');
  Lines.Add('    HTTP request runs in a worker thread via');
  Lines.Add('    ``asyncio.to_thread`` (or an executor fallback on Python');
  Lines.Add('    3.7 / 3.8), so this coroutine does not block the event loop.');
  Lines.Add('');
  if Length(F.Params) > 0 then
  begin
    Lines.Add('    Args:');
    for i := 0 to High(F.Params) do
    begin
      PName := MakeSafePyIdent(F.Params[i].Name, i);
      PDesc := F.Params[i].Description.TrimChar(#32#9#13#10);
      PDesc := PDesc.ReplaceChar(#13#10, ' ');
      if PDesc.Len > 120 then
        PDesc := PDesc.GetString(1, 121);
      if PDesc.Len = 0 then
        PDesc := '(no description)';
      Lines.Add('        ' + PName.Text + ': ' + PDesc.Text);
    end;
    Lines.Add('');
  end;

  if F.IsFunction then
    Lines.Add('    Returns: The remote result converted to Python.')
  else
    Lines.Add('    Returns: None.');
  Lines.Add('');
  Lines.Add('    Raises:');
  Lines.Add('        HTTPCallError: if the call fails for any reason.');
  Lines.Add('    """');

  if F.IsFunction then
    Lines.Add('    return await _to_thread(_call_api, ' + PyStrLit(ApiName).Text + ', ' + ArgLiteralList.Text + ')')
  else
    Lines.Add('    await _to_thread(_call_api, ' + PyStrLit(ApiName).Text + ', ' + ArgLiteralList.Text + ')');
  Lines.Add('');
  Lines.Add('');
end;

function GenerateHTTPCallPythonCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPythonCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPythonCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Python call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
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
      ApiNames.Add(ApiName);
    end;

    EmitPyHeader(Lines, UnitName, NormalizedUnit, BaseUrl);

    for i := 0 to High(SupportedFuncs) do
      EmitPyFunction(Lines, SupportedFuncs[i], ApiNames[i]);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines (sync + async).',
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
    'python', 'Python HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call.py', False,
    @GenerateHTTPCallPythonCode);
end.
