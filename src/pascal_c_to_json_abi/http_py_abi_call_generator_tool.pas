unit http_py_abi_call_generator_tool;

// http_py_abi_call_generator_tool - LingoFuse HTTP/JSON ABI Call-Side
// Generator for Python.
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces a complete Python module that provides typed
// functions for calling an HTTP/JSON ABI service through bridge.py.
//
// The generated module uses only the Python standard library plus the
// `requests` package. It does NOT depend on the `lingofuse` Python
// package, because the caller is expected to reach the bridge over
// plain HTTP. This makes the module usable from any Python process,
// regardless of whether that process is part of a LingoFuse mesh.
//
// Wire protocol (HTTP/JSON path):
//   request  = POST <base_url>/<api>  with body
//              { "args": [v1, v2, ...] }
//   response = { "code": 0,  "result": ... }   on success
//              { "code": -1, "error":  ... }   on failure
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> JSON number -> Python int
//   int64                         -> JSON number -> Python int
//   cardinal / dword / longword   -> JSON number -> Python int
//   word / smallint / byte        -> JSON number -> Python int
//   uint64                        -> JSON number -> Python int
//   double / extended / real      -> JSON number -> Python float
//   single                        -> JSON number -> Python float
//   string / PChar family         -> JSON string -> Python str
//
// The generated module exposes:
//   class HTTPCallError(Exception)   - the only exception type raised
//   HTTP_CALL_BASE_URL               - configurable base URL
//   HTTP_CALL_TIMEOUT                - configurable request timeout
//   DEBUG_LOG                        - verbose logging toggle
//   One typed free function per supported routine.
//
// The user is expected to:
//   1. Install the `requests` package (pip install requests).
//   2. Set HTTP_CALL_BASE_URL to the bridge's base URL plus the
//      target app name.
//   3. Call the generated free functions directly.
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

// GenerateHTTPCallPythonCode - main entry point for the call module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallPythonCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallPythonReadme - main entry point for the call-side README.
//
// Produces a Markdown document that describes the generated call-side
// module: purpose, outbound wire protocol, type mapping, deployment,
// testing, per-API reference, and a chapter explicitly targeted at AI
// agents.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallPythonReadme(Model: TPascal_Func_Model): TPascalStringList;

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
  Lines.Add('The user is expected to:');
  Lines.Add('  1. Install the `requests` package (pip install requests).');
  Lines.Add('  2. Set HTTP_CALL_BASE_URL to the bridge''s base URL plus the');
  Lines.Add('     target app name.');
  Lines.Add('  3. Call any of the generated free functions.');
  Lines.Add('');
  Lines.Add('All comments and log messages in this file are English.');
  Lines.Add('"""');
  Lines.Add('');
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

// EmitPyFunction - write one typed call function.
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
    Log(PFormat('Generated %d lines, %d supported routines.', [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// PYTHON CALL README GENERATOR
// =============================================================================

function GenerateHTTPCallPythonReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, BaseUrl: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamWire: TP_String;
  CallFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  PascalDecl, PySig: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPythonReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPythonReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  CallFileName := NormalizedUnit + '_http_json_call.py';

  Log(PFormat('Generating HTTP/JSON Python call README for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  FuncCount := Length(SupportedFuncs);

  TotalParams := 0;
  for i := 0 to FuncCount - 1 do
    TotalParams := TotalParams + Length(SupportedFuncs[i].Params);

  DuplicateNameCount := 0;
  LastOriginalName := '';
  for i := 0 to FuncCount - 1 do
  begin
    if SupportedFuncs[i].Name.Same(LastOriginalName) then
      Inc(DuplicateNameCount)
    else
      LastOriginalName := SupportedFuncs[i].Name;
  end;

  Lines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
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

    // =========================================================================
    // Header
    // =========================================================================
    Lines.Add('# ' + UnitName.Text + ' - Python HTTP/JSON Call-Side Wrapper');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_py_abi_call_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Call module file**  : `' + CallFileName.Text + '`');
    Lines.Add('> **Target App name**   : `' + AppName.Text + '`');
    Lines.Add('> **Default base URL**  : `' + BaseUrl.Text + '`');
    Lines.Add('> **Exposed functions** : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('>');
    Lines.Add('> **Audience**: Python developers and AI assistants who need to');
    Lines.Add('> import the generated module and call the remote service through');
    Lines.Add('> `bridge.py`.');
    Lines.Add('>');
    Lines.Add('> **AI agents**: jump straight to §9 "For AI Agents" for a');
    Lines.Add('> compact, machine-readable summary of the contract, common');
    Lines.Add('> anti-patterns, and a decision tree.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // =========================================================================
    // 1. Overview
    // =========================================================================
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **call-side wrapper** that was');
    Lines.Add('generated from the Pascal unit `' + UnitName.Text + '`. The');
    Lines.Add('module exposes one typed Python function per supported routine');
    Lines.Add('in the source. Each generated function sends an HTTP POST request');
    Lines.Add('to a remote HTTP/JSON service through the LingoFuse HTTP bridge');
    Lines.Add('(`bridge.py`), parses the response, and returns the result as a');
    Lines.Add('native Python value.');
    Lines.Add('');
    Lines.Add('### 1.1 What is an HTTP/JSON Python client?');
    Lines.Add('');
    Lines.Add('An HTTP/JSON Python client is a plain Python module that:');
    Lines.Add('');
    Lines.Add('- exposes one typed free function per remote API;');
    Lines.Add('- serializes the function''s arguments into a JSON request body;');
    Lines.Add('- sends the request over HTTP to the bridge;');
    Lines.Add('- deserializes the JSON response into a native Python value;');
    Lines.Add('- raises a single exception type on any failure.');
    Lines.Add('');
    Lines.Add('The wrapper is the exact counterpart of the service unit produced');
    Lines.Add('by `http_py_abi_service_generator_tool.pas`. Both are generated');
    Lines.Add('from the same `TPascal_Func_Model`, so their wire contracts');
    Lines.Add('cannot drift.');
    Lines.Add('');
    Lines.Add('### 1.2 Design principles');
    Lines.Add('');
    Lines.Add('| Property | Value |');
    Lines.Add('|----------|-------|');
    Lines.Add('| Call style | Typed free functions |');
    Lines.Add('| Encoding | Plain-text JSON |');
    Lines.Add('| Transport | HTTP via `requests` |');
    Lines.Add('| Error model | Single exception type (`HTTPCallError`) |');
    Lines.Add('| Runtime dependency | `requests` (the only third-party library) |');
    Lines.Add('');
    Lines.Add('### 1.3 Three-step quick start');
    Lines.Add('');
    Lines.Add('1. **Install the dependency**: `pip install requests`.');
    Lines.Add('2. **Import the module and set the base URL**:');
    Lines.Add('   `import ' + NormalizedUnit.Text + '_http_json_call as api`');
    Lines.Add('   then `api.HTTP_CALL_BASE_URL = ''...''`.');
    Lines.Add('3. **Call any generated function**: `api.Add(3, 4)` returns `7`,');
    Lines.Add('   or raises `HTTPCallError`.');
    Lines.Add('');
    Lines.Add('### 1.4 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + CallFileName.Text + '` | The call module (import and use). |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_call_python.md` | This README. |');
    Lines.Add('');

    // =========================================================================
    // 2. Quick Start
    // =========================================================================
    Lines.Add('## 2. Quick Start');
    Lines.Add('');
    Lines.Add('### 2.1 Install the dependency');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('pip install requests');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 2.2 Import the module');
    Lines.Add('');
    Lines.Add('Place `' + CallFileName.Text + '` next to your script, then:');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('import ' + NormalizedUnit.Text + '_http_json_call as api');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 2.3 Configure the base URL');
    Lines.Add('');
    Lines.Add('The module already defaults to the local bridge:');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('api.HTTP_CALL_BASE_URL = ' + PyStrLit(BaseUrl).Text);
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Change it if the bridge runs on a different host or port, or if');
    Lines.Add('the target app name is different.');
    Lines.Add('');
    Lines.Add('### 2.4 Make a call');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('try:');
    Lines.Add('    result = api.Add(3, 4)');
    Lines.Add('    print(''Add(3, 4) ='', result)');
    Lines.Add('except api.HTTPCallError as e:');
    Lines.Add('    print(''Call failed:'', e,');
    Lines.Add('          ''code='', e.code, ''http_status='', e.http_status)');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 3. Compatibility
    // =========================================================================
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('### 3.1 Python version');
    Lines.Add('');
    Lines.Add('| Requirement | Minimum version | Notes |');
    Lines.Add('|-------------|-----------------|-------|');
    Lines.Add('| CPython | 3.7 | Tested on 3.7 through 3.12. |');
    Lines.Add('| PyPy | 3.9+ | Not officially tested; should work. |');
    Lines.Add('');
    Lines.Add('### 3.2 Platform support');
    Lines.Add('');
    Lines.Add('Every platform where Python and `requests` run:');
    Lines.Add('');
    Lines.Add('| Platform | Architecture | Status |');
    Lines.Add('|----------|-------------|--------|');
    Lines.Add('| Windows | x86_64 | Supported |');
    Lines.Add('| Linux | x86_64 | Supported |');
    Lines.Add('| Linux | aarch64 | Supported |');
    Lines.Add('| macOS | x86_64 | Supported |');
    Lines.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    Lines.Add('');
    Lines.Add('### 3.3 Runtime dependencies');
    Lines.Add('');
    Lines.Add('| Dependency | Where to get it |');
    Lines.Add('|------------|----------------|');
    Lines.Add('| Python 3.7+ | python.org or system package manager |');
    Lines.Add('| `requests` | `pip install requests` |');
    Lines.Add('');
    Lines.Add('The generated module has **no** other dependency. It does NOT');
    Lines.Add('require the `lingofuse` Python package, because it talks to the');
    Lines.Add('bridge over plain HTTP.');
    Lines.Add('');
    Lines.Add('### 3.4 Character encoding');
    Lines.Add('');
    Lines.Add('- **Source files**: UTF-8, declared by the `# -*- coding: utf-8 -*-`');
    Lines.Add('  header.');
    Lines.Add('- **JSON payloads**: UTF-8, both directions.');
    Lines.Add('- **On the wire**: `requests` sends the body as UTF-8 bytes;');
    Lines.Add('  the bridge strips the LingoFuse NUL terminator before relaying');
    Lines.Add('  to the target service.');
    Lines.Add('');
    Lines.Add('### 3.5 Threading model');
    Lines.Add('');
    Lines.Add('Generated functions are **synchronous and blocking**. They can');
    Lines.Add('be called from any thread, but `requests` is not necessarily');
    Lines.Add('thread-safe across shared sessions. The generated module uses a');
    Lines.Add('fresh connection per call (via `requests.post`), so concurrent');
    Lines.Add('calls from multiple threads are safe.');
    Lines.Add('');
    Lines.Add('For UI code or async frameworks, offload the call to a worker');
    Lines.Add('thread or use `asyncio.to_thread`.');
    Lines.Add('');

    // =========================================================================
    // 4. Wire protocol
    // =========================================================================
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The call module speaks **plain-text JSON** in both directions,');
    Lines.Add('transported over HTTP by the bridge.');
    Lines.Add('');
    Lines.Add('### 4.1 URL composition');
    Lines.Add('');
    Lines.Add('Every generated function composes its target URL as:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('HTTP_CALL_BASE_URL + ''/'' + <api-name>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('`HTTP_CALL_BASE_URL` is a module-level `str`, set once by the');
    Lines.Add('caller before any generated function is invoked. Its default');
    Lines.Add('value points at the local bridge with the target app already');
    Lines.Add('embedded:');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('HTTP_CALL_BASE_URL = ' + PyStrLit(BaseUrl).Text);
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.2 Outbound request');
    Lines.Add('');
    Lines.Add('Every generated function sends a JSON object body:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "args": [v1, v2, ..., vN]');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `args` array holds the arguments **in positional order**.');
    Lines.Add('There is no named-argument form on the outbound path.');
    Lines.Add('');
    Lines.Add('### 4.3 Inbound response');
    Lines.Add('');
    Lines.Add('The bridge returns a plain JSON object:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": 0,  "result": <value> }');
    Lines.Add('{ "code": -1, "error":  "<message>" }');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated function inspects `code`:');
    Lines.Add('');
    Lines.Add('- `code = 0` -> returns `result` converted to the declared');
    Lines.Add('  Python type (or `None`, for procedures).');
    Lines.Add('- `code <> 0` -> raises `HTTPCallError` with `error`.');
    Lines.Add('');
    Lines.Add('### 4.4 Error model');
    Lines.Add('');
    Lines.Add('Four distinct error conditions can arise:');
    Lines.Add('');
    Lines.Add('| Condition | Detected by | Raised exception |');
    Lines.Add('|-----------|-------------|------------------|');
    Lines.Add('| Network failure or timeout | `requests` | `HTTPCallError` with `code = -1`, `http_status = 0` |');
    Lines.Add('| HTTP status != 200 | `resp.status_code` | `HTTPCallError` with `code = -1`, `http_status = <status>` |');
    Lines.Add('| Response is not a JSON object or lacks `code` | `json.loads` / dict check | `HTTPCallError` with `code = -1` |');
    Lines.Add('| Service returned `code <> 0` | `parsed[''code'']` | `HTTPCallError` with `code = <value>` |');
    Lines.Add('');
    Lines.Add('All collapse into the same exception type. The exception message');
    Lines.Add('carries the specific cause.');
    Lines.Add('');
    Lines.Add('### 4.5 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant P as Python Client');
    Lines.Add('    participant C as Call Module');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant S as Remote Service');
    Lines.Add('    P->>C: api.Add(3, 4)');
    Lines.Add('    C->>C: build {"args": [3, 4]}');
    Lines.Add('    C->>B: HTTP POST /' + AppName.Text + '/Add');
    Lines.Add('    B->>S: LF_Call with JSON payload');
    Lines.Add('    S->>S: parse JSON, execute');
    Lines.Add('    S-->>B: {"code": 0, "result": 7}');
    Lines.Add('    B-->>C: HTTP 200 with JSON body');
    Lines.Add('    C->>C: check code, extract result');
    Lines.Add('    C-->>P: 7');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.6 Error response example');
    Lines.Add('');
    Lines.Add('If the remote service raises an exception:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": -1, "error": "Division by zero" }');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated function detects `code <> 0` and raises:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('HTTPCallError: Division by zero');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 5. Global configuration
    // =========================================================================
    Lines.Add('## 5. Global Configuration');
    Lines.Add('');
    Lines.Add('The module exposes three module-level variables. Set them once');
    Lines.Add('at import time, before any call.');
    Lines.Add('');
    Lines.Add('| Variable | Type | Default | Purpose |');
    Lines.Add('|----------|------|---------|---------|');
    Lines.Add('| `HTTP_CALL_BASE_URL` | `str` | `' + BaseUrl.Text + '` | Bridge URL plus target app name. |');
    Lines.Add('| `HTTP_CALL_TIMEOUT` | `float` or `None` | `30.0` | Per-request timeout, in seconds. |');
    Lines.Add('| `DEBUG_LOG` | `bool` | `False` | If True, logs each request and response at INFO level. |');
    Lines.Add('');
    Lines.Add('### 5.1 Setting the base URL');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('import ' + NormalizedUnit.Text + '_http_json_call as api');
    Lines.Add('api.HTTP_CALL_BASE_URL = ''http://192.168.1.10:8081/' + AppName.Text + '''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 5.2 Changing the timeout');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('api.HTTP_CALL_TIMEOUT = 60.0      # wait up to 60 seconds');
    Lines.Add('api.HTTP_CALL_TIMEOUT = None      # wait forever');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 5.3 Enabling verbose logging');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('import logging');
    Lines.Add('logging.basicConfig(level=logging.INFO)');
    Lines.Add('api.DEBUG_LOG = True');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 6. Error Handling
    // =========================================================================
    Lines.Add('## 6. Error Handling');
    Lines.Add('');
    Lines.Add('Every generated function either returns the result value or');
    Lines.Add('raises `HTTPCallError`. There is no partial-failure mode.');
    Lines.Add('');
    Lines.Add('### 6.1 The exception class');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('class HTTPCallError(Exception):');
    Lines.Add('    def __init__(self, message, code=-1, http_status=0):');
    Lines.Add('        ...');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 6.2 Exception fields');
    Lines.Add('');
    Lines.Add('| Field | Type | Meaning |');
    Lines.Add('|-------|------|---------|');
    Lines.Add('| `str(e)` | `str` | Human-readable description. |');
    Lines.Add('| `e.code` | `int` | Bridge / service error code. `-1` for network errors. |');
    Lines.Add('| `e.http_status` | `int` | HTTP status code, or `0` if no response was produced. |');
    Lines.Add('');
    Lines.Add('### 6.3 Error codes');
    Lines.Add('');
    Lines.Add('| Code | Meaning | Typical `http_status` |');
    Lines.Add('|------|---------|-----------------------|');
    Lines.Add('| `0` | Success. Never raised. | `200` |');
    Lines.Add('| `-1` | Remote call failed (service exception, network error, timeout). | `200` for service errors, `0` for network errors, `4xx`/`5xx` for HTTP errors. |');
    Lines.Add('| `-2` | Request shape error (URL path could not be parsed by the bridge). | `400` |');
    Lines.Add('| `-3` | Bridge pre-check failed: the bridge did not see the target API. | `200` |');
    Lines.Add('');
    Lines.Add('### 6.4 Recommended catch pattern');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('try:');
    Lines.Add('    result = api.Add(3, 4)');
    Lines.Add('except api.HTTPCallError as e:');
    Lines.Add('    if e.code == -3:');
    Lines.Add('        # Backend not ready yet; retry after a delay.');
    Lines.Add('        print(''Backend not ready:'', e)');
    Lines.Add('    elif e.code == -2:');
    Lines.Add('        print(''Request shape error:'', e)');
    Lines.Add('    elif e.code == -1 and e.http_status == 0:');
    Lines.Add('        print(''Network error:'', e)');
    Lines.Add('    else:');
    Lines.Add('        print(''Remote error:'', e)');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 7. API Reference
    // =========================================================================
    Lines.Add('## 7. API Reference');
    Lines.Add('');
    Lines.Add('Total functions: **' + MdInt(FuncCount).Text + '**.');
    Lines.Add('');

    if FuncCount = 0 then
    begin
      Lines.Add('_No supported routines were found in the source unit._');
      Lines.Add('');
    end
    else
    begin
      if DuplicateNameCount > 0 then
      begin
        Lines.Add('### 7.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('The source unit exposes overloaded routines: the same Pascal');
        Lines.Add('name with two or more distinct signatures. The HTTP/JSON');
        Lines.Add('protocol routes by API name, so two overloads cannot both keep');
        Lines.Add('the original name. The generator appends a numeric suffix');
        Lines.Add('(`_1`, `_2`, ...) to every overload after the first.');
        Lines.Add('');
        Lines.Add('- The **first** overload keeps the bare name.');
        Lines.Add('- Each subsequent overload gets `_N`.');
        Lines.Add('- The `.0` suffix never appears.');
        Lines.Add('');
        Lines.Add('The "Pascal source" line under each section shows the true');
        Lines.Add('Pascal signature, so you can reconstruct which overload is');
        Lines.Add('which.');
        Lines.Add('');
      end;

      // ----- §7.1 Summary -----
      Lines.Add('### 7.1 Summary');
      Lines.Add('');
      Lines.Add('| # | Function | Params | Returns | Description |');
      Lines.Add('|---|----------|--------|---------|-------------|');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];

        Description := GetFullDescription(F.Comment);
        if Description.Len = 0 then
          Description := '';

        if F.IsFunction then
          ParamWire := ABI_Type_To_Py_Annotation(F.ReturnType)
        else
          ParamWire := '-';

        Lines.Add('| ' + MdInt(i + 1).Text + ' | `' + MdCellEscape(ApiName).Text + '`' + ' | ' + MdInt(Length(F.Params)).Text +
          ' | `' + MdCellEscape(ParamWire).Text + '`' + ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      // ----- §7.2..N Per-API sections -----
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        HasParams := Length(F.Params) > 0;

        PascalDecl := BuildPascalDecl(F);
        PySig := BuildPySignature(F, ApiName);
        CallArgs := BuildPyCallArgList(F.Params);

        Lines.Add('### 7.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');

        Lines.Add('- **Python signature**: `' + PySig.Text + '`');
        Lines.Add('- **Pascal source**: `' + PascalDecl.Text + '`');
        Lines.Add('- **HTTP route**: `POST /' + AppName.Text + '/' + ApiName.Text + '`');
        Lines.Add('- **Raises**: `HTTPCallError` on any failure');
        Lines.Add('');

        Description := GetFullDescription(F.Comment);
        if Description.Len > 0 then
        begin
          Lines.Add('#### Description');
          Lines.Add('');
          Lines.Add(Description.Text);
          Lines.Add('');
        end;

        if HasParams then
        begin
          Lines.Add('#### Arguments');
          Lines.Add('');
          Lines.Add('| # | Name | Python type | JSON wire type |');
          Lines.Add('|---|------|-------------|----------------|');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafePyIdent(F.Params[j].Name, j);
            ParamType := ABI_Type_To_Py_Annotation(F.Params[j].PascalType);
            ParamWire := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);
            Lines.Add('| ' + MdInt(j + 1).Text + ' | `' + MdCellEscape(ParamName).Text + '`' + ' | `' +
              MdCellEscape(ParamType).Text + '`' + ' | `' + MdCellEscape(ParamWire).Text + '` |');
          end;
          Lines.Add('');
        end;

        Lines.Add('#### Example');
        Lines.Add('');
        Lines.Add('```python');
        Lines.Add('try:');
        if F.IsFunction then
          Lines.Add('    result = api.' + ApiName.Text + '(' + CallArgs.Text + ')')
        else
          Lines.Add('    api.' + ApiName.Text + '(' + CallArgs.Text + ')');
        if F.IsFunction then
          Lines.Add('    print(result)')
        else
          Lines.Add('    print(''Called successfully'')');
        Lines.Add('except api.HTTPCallError as e:');
        Lines.Add('    print(''Call failed:'', e,');
        Lines.Add('          ''code='', e.code, ''http_status='', e.http_status)');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    // =========================================================================
    // 8. Troubleshooting
    // =========================================================================
    Lines.Add('## 8. Troubleshooting');
    Lines.Add('');
    Lines.Add('### 8.1 Symptom, cause, fix');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| `ImportError: No module named ''requests''` | The `requests` package is not installed | `pip install requests` |');
    Lines.Add('| `HTTPCallError: Network error: ...` | The bridge is not running, or `HTTP_CALL_BASE_URL` is wrong | Start `bridge.py`; verify the URL with `curl`. |');
    Lines.Add('| `HTTPCallError: Request timed out` | The bridge or the target service is slow | Increase `HTTP_CALL_TIMEOUT`. |');
    Lines.Add('| `HTTPCallError: HTTP 404 ...` | The URL path is wrong | Verify `HTTP_CALL_BASE_URL` ends with `/<app>`. |');
    Lines.Add('| `HTTPCallError: ... code=-3` | Bridge pre-check failed | Add `--no-precheck` to the bridge, or retry after ~3 s. |');
    Lines.Add('| `HTTPCallError: ... code=-2` | Request shape error | Verify the URL path and the app name. |');
    Lines.Add('| `HTTPCallError: ... code=-1` | Remote service raised an exception | Check the service log; the exception message is in `str(e)`. |');
    Lines.Add('| Return value is truncated | JSON number larger than the declared Pascal return type | Widen the return type in the source unit. |');
    Lines.Add('| `HTTPCallError: Invalid JSON response` | The bridge returned non-JSON (an HTTP error page, etc.) | Check `e.http_status` and the bridge log. |');
    Lines.Add('');
    Lines.Add('### 8.2 Testing the URL without the module');
    Lines.Add('');
    Lines.Add('From a shell:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('curl -X POST ' + BaseUrl.Text + '/<api-name> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": [1, 2]}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('If `curl` succeeds, the module will succeed too, because it uses');
    Lines.Add('the same URL and the same request shape.');
    Lines.Add('');
    Lines.Add('### 8.3 Enabling verbose logging');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('import logging');
    Lines.Add('logging.basicConfig(level=logging.INFO)');
    Lines.Add('api.DEBUG_LOG = True');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Every request URL and body, and every response status and body,');
    Lines.Add('is then printed at INFO level.');
    Lines.Add('');

    // =========================================================================
    // 9. For AI Agents
    // =========================================================================
    Lines.Add('## 9. For AI Agents');
    Lines.Add('');
    Lines.Add('This chapter is a compact, machine-readable summary. Everything');
    Lines.Add('here is also stated elsewhere in the document.');
    Lines.Add('');
    Lines.Add('### 9.1 Contract summary');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('artifact:');
    Lines.Add('  type: python_http_json_client');
    Lines.Add('  module_file: ' + CallFileName.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  target_app_name: ' + AppName.Text);
    Lines.Add('  default_base_url: ' + BaseUrl.Text);
    Lines.Add('  dependency: requests');
    Lines.Add('');
    Lines.Add('global_configuration:');
    Lines.Add('  HTTP_CALL_BASE_URL: "str, default ''" + BaseUrl.Text + "''"');
    Lines.Add('  HTTP_CALL_TIMEOUT: "float or None, default 30.0"');
    Lines.Add('  DEBUG_LOG: "bool, default False"');
    Lines.Add('');
    Lines.Add('outbound_request:');
    Lines.Add('  method: POST');
    Lines.Add('  url: "HTTP_CALL_BASE_URL + ''/'' + api_name"');
    Lines.Add('  headers:');
    Lines.Add('    Content-Type: "application/json; charset=utf-8"');
    Lines.Add('  body: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('  timeout: "HTTP_CALL_TIMEOUT seconds"');
    Lines.Add('');
    Lines.Add('inbound_response:');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('  bridge_shape_error: ''{"code": -2, "error": "<message>"}''');
    Lines.Add('  bridge_precheck_failed: ''{"code": -3, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('exception:');
    Lines.Add('  type: HTTPCallError');
    Lines.Add('  base: Exception');
    Lines.Add('  fields:');
    Lines.Add('    code: "int, -1 / -2 / -3 / <service code>"');
    Lines.Add('    http_status: "int, 0 for network errors"');
    Lines.Add('');
    Lines.Add('types:');
    Lines.Add('  python_int: "every ABI integer family member"');
    Lines.Add('  python_float: "every ABI float family member"');
    Lines.Add('  python_str: "every ABI string family member"');
    Lines.Add('  unsupported: "Boolean, Variant, arrays, records, classes, interfaces, enums, sets, generics, pointers, Currency, Comp, TDateTime"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 9.2 Anti-patterns');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Forgetting to `pip install requests` | ImportError at module load | Install `requests` first. |');
    Lines.Add('| Setting `HTTP_CALL_BASE_URL` after the first call | Race / inconsistent URLs | Set it once, before any call. |');
    Lines.Add('| Catching `Exception` instead of `HTTPCallError` | Hides unrelated bugs | Catch `HTTPCallError` explicitly. |');
    Lines.Add('| Assuming `code = 0` also means `result` is present | Procedures do not return a result | Read `result` via `e.result` or check `hasattr`; procedures use `None`. |');
    Lines.Add('| Sending huge integers as Python ints | JSON is fine, but a JS front-end reading the same response loses precision above 2^53 | Send large integers as strings. |');
    Lines.Add('| Relying on `HTTP_CALL_TIMEOUT = 0` | `requests` treats 0 as "fail immediately" | Use `None` to wait forever. |');
    Lines.Add('| Using the module from an async event loop | Blocks the loop | Wrap in `asyncio.to_thread(api.Add, 3, 4)`. |');
    Lines.Add('| Editing `_call_api` | Breaks the wire contract | Only edit the caller-side logic around the generated functions. |');
    Lines.Add('');
    Lines.Add('### 9.3 Decision tree: how to call an API');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    S["I want to call a remote API"] --> Q1{"Have I installed requests?"}');
    Lines.Add('    Q1 -- "no" --> A1["pip install requests"]');
    Lines.Add('    Q1 -- "yes" --> Q2{"Have I imported the module?"}');
    Lines.Add('    A1 --> Q2');
    Lines.Add('    Q2 -- "no" --> A2["import ' + NormalizedUnit.Text + '_http_json_call as api"]');
    Lines.Add('    Q2 -- "yes" --> Q3{"Have I set HTTP_CALL_BASE_URL?"}');
    Lines.Add('    A2 --> Q3');
    Lines.Add('    Q3 -- "no" --> A3["api.HTTP_CALL_BASE_URL = ''...''"]');
    Lines.Add('    Q3 -- "yes" --> A4["result = api.<ApiName>(args)"]');
    Lines.Add('    A3 --> A4');
    Lines.Add('    A4 --> Done["Handle HTTPCallError"]');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 9.4 Machine-readable function manifest');
    Lines.Add('');

    if FuncCount = 0 then
    begin
      Lines.Add('_No supported routines were found in the source unit._');
      Lines.Add('');
    end
    else
    begin
      Lines.Add('```json');
      Lines.Add('[');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];

        Lines.Add('  {');
        Lines.Add('    "name": "' + ApiName.Text + '",');
        Lines.Add('    "original_name": "' + F.Name.Text + '",');
        Lines.Add('    "kind": "' + if_(F.IsFunction, 'function', 'procedure') + '",');
        Lines.Add('    "route": "POST /' + AppName.Text + '/' + ApiName.Text + '",');

        if Length(F.Params) > 0 then
        begin
          Lines.Add('    "params": [');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafePyIdent(F.Params[j].Name, j);
            ParamType := ABI_Type_To_Py_Annotation(F.Params[j].PascalType);
            ParamWire := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);
            Lines.Add('      {"name": "' + ParamName.Text + '", "python_type": "' + ParamType.Text + '", "json_type": "' +
              ParamWire.Text + '"}' + if_(j < High(F.Params), ',', ''));
          end;
          Lines.Add('    ],');
        end
        else
          Lines.Add('    "params": [],');

        if F.IsFunction then
          Lines.Add('    "returns": "' + ABI_Type_To_Py_Annotation(F.ReturnType).Text + '"')
        else
          Lines.Add('    "returns": null');

        Lines.Add('  }' + if_(i < High(SupportedFuncs), ',', ''));
      end;

      Lines.Add(']');
      Lines.Add('```');
      Lines.Add('');
    end;

    Lines.Add('### 9.5 How to answer a user question with this document');
    Lines.Add('');
    Lines.Add('1. **Identify the intent**: install, call, configure, or debug?');
    Lines.Add('2. **Locate the relevant section**:');
    Lines.Add('   - "How do I install it?" -> §2.1.');
    Lines.Add('   - "How do I call API X?" -> §7.<n>.');
    Lines.Add('   - "How do I configure the URL?" -> §5.1.');
    Lines.Add('   - "Why does my call fail?" -> §6 and §8.1.');
    Lines.Add('3. **Quote the specific fact**, not the whole document. Prefer');
    Lines.Add('   the machine-readable forms in §9.1 and §9.4.');
    Lines.Add('4. **If the question is not covered**, say so and point the');
    Lines.Add('   user to the source module.');
    Lines.Add('');
    Lines.Add('### 9.6 What this document does NOT cover');
    Lines.Add('');
    Lines.Add('- The backend service implementation.');
    Lines.Add('- The bridge (`bridge.py`) configuration.');
    Lines.Add('- The LingoFuse wire format below the HTTP layer.');
    Lines.Add('- Other language bindings (Pascal, JavaScript, C++).');
    Lines.Add('- Async / asyncio integration beyond the one-liner in §3.5.');
    Lines.Add('');

    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_py_abi_call_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated Python call README: %d lines, %d supported routines.', [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
