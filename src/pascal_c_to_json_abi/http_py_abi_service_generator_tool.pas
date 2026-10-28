unit http_py_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServicePythonCode - main entry point for the service
// module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServicePythonCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_py_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_py_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification
// -----------------------------------------------------------------------------

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

function ABI_Type_To_Py_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := ''''''
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'None';
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

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// MakeApiName - canonicalize an identifier for use in URLs, dict keys,
// and downstream identifiers. The replacement set MUST match every
// other generator in this toolchain (service and call sides; Pascal,
// JS, Python, C++).
//
// Replaced: space, tab, '.', '/', '\', '@', ':', '#', '?', '&', '=',
//           '+', '-'
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeInternalCallName(const ApiName: TP_String): TP_String;
begin
  Result := 'internal_call_' + ApiName;
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

  if Result.Same('False') or Result.Same('None') or Result.Same('True') or
    Result.Same('and') or Result.Same('as') or Result.Same('assert') or
    Result.Same('async') or Result.Same('await') or Result.Same('break') or
    Result.Same('class') or Result.Same('continue') or Result.Same('def') or
    Result.Same('del') or Result.Same('elif') or Result.Same('else') or
    Result.Same('except') or Result.Same('finally') or Result.Same('for') or
    Result.Same('from') or Result.Same('global') or Result.Same('if') or
    Result.Same('import') or Result.Same('in') or Result.Same('is') or
    Result.Same('lambda') or Result.Same('nonlocal') or Result.Same('not') or
    Result.Same('or') or Result.Same('pass') or Result.Same('raise') or
    Result.Same('return') or Result.Same('try') or Result.Same('while') or
    Result.Same('with') or Result.Same('yield') then
    Result := Result + '_';
end;

// PyStrLit - produce a complete Python string literal (single quoted,
// with the surrounding quotes included). Non-printable ASCII is
// escaped as \xNN. Printable non-ASCII characters are preserved
// verbatim; the generated file is intended to be UTF-8 encoded.
function PyStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #39;
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
  Result.Append(#39);
end;

// -----------------------------------------------------------------------------
// Markdown helpers
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

function BuildPyNameList(const Params: TParamArray): TP_String;
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
    Result := Result + PyStrLit(n);
  end;
  Result := Result + ']';
end;

function BuildPyDefaultList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Py_Default(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
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

// BuildPascalDecl - full Pascal declaration, used by the README only.
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
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

// BuildPySignature - full Python signature, used by the README only.
function BuildPySignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
begin
  if F.IsFunction then
    Result := ApiName + '(' + BuildPyParamList(F.Params) + ') -> ' +
      ABI_Type_To_Py_Annotation(F.ReturnType)
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
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and F.IsFunction and (not ABI_Type_Is_Supported(F.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [F.Name.Text, F.ReturnType.Text]));
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
// PYTHON SERVICE MODULE GENERATOR
// =============================================================================

// EmitPyHeader - write the module docstring, imports, configuration
// constants, and the progressive symbol resolver.
//
// The import section is the critical piece. Different installations of
// the lingofuse Python package expose the same symbols from different
// module paths. Instead of hard-coding one path (which would break on
// any reorganisation), the generated code tries each candidate in
// turn, from the most public to the most internal. If every candidate
// fails, it prints a diagnostic naming the missing symbol and every
// path that was tried, and exits.
//
// A user can point the generated file at a different top-level module
// name via the LINGOFUSE_MODULE environment variable, without editing
// the generated source.
//
// NOTE: The `_fail` diagnostic block below intentionally writes
//       Python escape sequences into the generated file. In Pascal,
//       backslash is NOT an escape character, so `'\n'` is two
//       characters (backslash + n) that Python interprets as a
//       newline, and `'\"'` is two characters (backslash + double
//       quote) that Python interprets as an escaped double quote.
//       Do NOT write `'\\n'` or `'\\"'`: those would generate the
//       three-character sequence `\\n` / `\\"` in the Python source,
//       which either produces a literal backslash or, in the `\\"`
//       case, terminates the string early and produces a
//       SyntaxError.
procedure EmitPyHeader(Lines: TPascalStringList;
  const UnitName, NormalizedUnit, AppName, Endpoint: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('"""');
  Lines.Add('Auto-generated by http_py_abi_service_generator_tool.pas.');
  Lines.Add('Source model unit: ' + UnitName.Text + '.');
  Lines.Add('Do not edit by hand unless you know what you are doing.');
  Lines.Add('');
  Lines.Add('Wire protocol (HTTP/JSON path, both directions):');
  Lines.Add('  request  = JSON object');
  Lines.Add('             { "args": [v1, v2, ...] }     positional arguments');
  Lines.Add('             { "a": v1, "b": v2, ... }     named arguments');
  Lines.Add('  response = JSON object');
  Lines.Add('             { "code": 0,  "result": ... }  on success');
  Lines.Add('             { "code": -1, "error":  ... }  on failure');
  Lines.Add('');
  Lines.Add('This module is a LingoFuse Call service. It is designed to be');
  Lines.Add('reached via bridge.py from any HTTP client (webjs / PHP / nodejs).');
  Lines.Add('The bridge performs the HTTP <-> LingoFuse conversion; this');
  Lines.Add('module only deals with JSON strings.');
  Lines.Add('');
  Lines.Add('The user is expected to:');
  Lines.Add('  1. Fill in each `internal_call_<api>` stub with a call to the');
  Lines.Add('     real implementation.');
  Lines.Add('  2. Run the module:');
  Lines.Add('       python3 ' + NormalizedUnit.Text + '_http_json_service.py');
  Lines.Add('  3. Start bridge.py with the SAME endpoint:');
  Lines.Add('       python3 bridge.py --endpoint ' + Endpoint.Text + ' --no-precheck');
  Lines.Add('');
  Lines.Add('All comments and log messages in this file are English.');
  Lines.Add('"""');
  Lines.Add('');
  Lines.Add('import importlib');
  Lines.Add('import json');
  Lines.Add('import logging');
  Lines.Add('import os');
  Lines.Add('import signal');
  Lines.Add('import sys');
  Lines.Add('import threading');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# LingoFuse imports, with progressive fallback');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('#');
  Lines.Add('# Different installations of the lingofuse Python package expose');
  Lines.Add('# the same symbols from different module paths. Rather than');
  Lines.Add('# hard-coding one path, we resolve each required symbol against a');
  Lines.Add('# list of candidates, from the most public to the most internal.');
  Lines.Add('#');
  Lines.Add('# If every candidate fails, a diagnostic naming the missing symbol');
  Lines.Add('# and every attempted path is printed, and the process exits.');
  Lines.Add('#');
  Lines.Add('# To point at a different top-level module name without editing');
  Lines.Add('# this file, set the environment variable LINGOFUSE_MODULE.');
  Lines.Add('#');
  Lines.Add('');
  Lines.Add('_IMPORT_DIAG = []');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _import_module_or_none(dotted):');
  Lines.Add('    try:');
  Lines.Add('        return importlib.import_module(dotted)');
  Lines.Add('    except Exception as _exc:');
  Lines.Add('        _IMPORT_DIAG.append(');
  Lines.Add('            "import {0}: {1}".format(dotted, _exc))');
  Lines.Add('        return None');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _resolve_symbol(symbol, *candidates):');
  Lines.Add('    for mod_path in candidates:');
  Lines.Add('        mod = _import_module_or_none(mod_path)');
  Lines.Add('        if mod is None:');
  Lines.Add('            continue');
  Lines.Add('        if hasattr(mod, symbol):');
  Lines.Add('            return getattr(mod, symbol)');
  Lines.Add('        _IMPORT_DIAG.append(');
  Lines.Add('            "{0}.{1}: attribute not found".format(mod_path, symbol))');
  Lines.Add('    return None');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _fail(symbol):');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "FATAL: cannot import ''{0}'' from the lingofuse package.\n".format(symbol))');
  Lines.Add('    sys.stderr.write("\nDiagnostic:\n")');
  Lines.Add('    for line in _IMPORT_DIAG:');
  Lines.Add('        sys.stderr.write("  " + line + "\n")');
  Lines.Add('    sys.stderr.write("\nHow to check:\n")');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "  python -c \"import lingofuse; '
    + 'print(lingofuse.__file__)\"\n")');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "  python -c \"import lingofuse; '
    + 'print(dir(lingofuse))\"\n")');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "\nTo use a different top-level module name, set the "');
  Lines.Add('        "environment variable LINGOFUSE_MODULE.\n")');
  Lines.Add('    sys.exit(1)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('_TOP = os.environ.get("LINGOFUSE_MODULE", "lingofuse")');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _require(symbol, *candidates):');
  Lines.Add('    value = _resolve_symbol(symbol, *candidates)');
  Lines.Add('    if value is None:');
  Lines.Add('        _fail(symbol)');
  Lines.Add('    return value');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('App = _require("App", _TOP)');
  Lines.Add('');
  Lines.Add('DataHandle = _require(');
  Lines.Add('    "DataHandle",');
  Lines.Add('    _TOP + ".core",');
  Lines.Add('    _TOP + ".handle",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('cstr = _require(');
  Lines.Add('    "cstr",');
  Lines.Add('    _TOP + ".lf_io",');
  Lines.Add('    _TOP + ".io",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('dumps_json = _require(');
  Lines.Add('    "dumps_json",');
  Lines.Add('    _TOP + ".lf_io",');
  Lines.Add('    _TOP + ".io",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('read_string_bytes = _require(');
  Lines.Add('    "read_string_bytes",');
  Lines.Add('    _TOP + ".lf_io",');
  Lines.Add('    _TOP + ".io",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('write_string_bytes = _require(');
  Lines.Add('    "write_string_bytes",');
  Lines.Add('    _TOP + ".lf_io",');
  Lines.Add('    _TOP + ".io",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('LF_ResetPrepare = _require(');
  Lines.Add('    "LF_ResetPrepare",');
  Lines.Add('    _TOP + "._lf_native",');
  Lines.Add('    _TOP + ".lf_native",');
  Lines.Add('    _TOP + ".native",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('LF_PrepareService = _require(');
  Lines.Add('    "LF_PrepareService",');
  Lines.Add('    _TOP + "._lf_native",');
  Lines.Add('    _TOP + ".lf_native",');
  Lines.Add('    _TOP + ".native",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('LF_PrepareClient = _require(');
  Lines.Add('    "LF_PrepareClient",');
  Lines.Add('    _TOP + "._lf_native",');
  Lines.Add('    _TOP + ".lf_native",');
  Lines.Add('    _TOP + ".native",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('LF_PrepareDone = _require(');
  Lines.Add('    "LF_PrepareDone",');
  Lines.Add('    _TOP + "._lf_native",');
  Lines.Add('    _TOP + ".lf_native",');
  Lines.Add('    _TOP + ".native",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('LF_ExitMainThread = _require(');
  Lines.Add('    "LF_ExitMainThread",');
  Lines.Add('    _TOP + "._lf_native",');
  Lines.Add('    _TOP + ".lf_native",');
  Lines.Add('    _TOP + ".native",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('LF_Shutdown = _require(');
  Lines.Add('    "LF_Shutdown",');
  Lines.Add('    _TOP + "._lf_native",');
  Lines.Add('    _TOP + ".lf_native",');
  Lines.Add('    _TOP + ".native",');
  Lines.Add('    _TOP)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Configuration');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('# LingoFuse application name used by the HTTP/JSON service.');
  Lines.Add('HTTP_SERVICE_APP_NAME = ' + PyStrLit(AppName).Text);
  Lines.Add('');
  Lines.Add('# Human-readable description of the service.');
  Lines.Add('HTTP_SERVICE_APP_DESC = ' + PyStrLit('HTTP/JSON service for ' + UnitName).Text);
  Lines.Add('');
  Lines.Add('# The LingoFuse endpoint the service binds to. bridge.py must be');
  Lines.Add('# started with the same --endpoint value.');
  Lines.Add('HTTP_SERVICE_ENDPOINT = ' + PyStrLit(Endpoint).Text);
  Lines.Add('');
  Lines.Add('# Set to True to emit per-call debug messages via the module logger.');
  Lines.Add('DEBUG_LOG = False');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Logging');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('log = logging.getLogger("http_json_service")');
  Lines.Add('');
  Lines.Add('');
end;

// EmitPyJsonHelpers - request parsing, response serialization, and the
// LingoFuse Call adapters.
procedure EmitPyJsonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# JSON request / response helpers');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('def _read_request(inp):');
  Lines.Add('    """');
  Lines.Add('    Read and parse a JSON request from a LingoFuse input handle.');
  Lines.Add('');
  Lines.Add('    Returns (True, dict) on success, (False, error_message) on');
  Lines.Add('    failure. The caller distinguishes the two cases with the');
  Lines.Add('    first element of the tuple.');
  Lines.Add('    """');
  Lines.Add('    try:');
  Lines.Add('        raw = read_string_bytes(inp.raw)');
  Lines.Add('    except Exception as e:');
  Lines.Add('        return False, "Failed to read request bytes: " + str(e)');
  Lines.Add('');
  Lines.Add('    if not raw:');
  Lines.Add('        return False, "Empty request body"');
  Lines.Add('');
  Lines.Add('    try:');
  Lines.Add('        text = raw.decode("utf-8")');
  Lines.Add('    except UnicodeDecodeError as e:');
  Lines.Add('        return False, "Request is not valid UTF-8: " + str(e)');
  Lines.Add('');
  Lines.Add('    try:');
  Lines.Add('        obj = json.loads(text)');
  Lines.Add('    except json.JSONDecodeError as e:');
  Lines.Add('        return False, "Invalid JSON request: " + str(e)');
  Lines.Add('');
  Lines.Add('    if not isinstance(obj, dict):');
  Lines.Add('        return False, "Request must be a JSON object"');
  Lines.Add('');
  Lines.Add('    return True, obj');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _extract_args(req, param_names, defaults):');
  Lines.Add('    """');
  Lines.Add('    Extract positional or keyword arguments from the request.');
  Lines.Add('');
  Lines.Add('    If the request contains "args", it is treated as a JSON array');
  Lines.Add('    of positional arguments. Otherwise, every parameter is looked');
  Lines.Add('    up by name. Missing values fall back to the corresponding');
  Lines.Add('    entry in `defaults`.');
  Lines.Add('    """');
  Lines.Add('    if "args" in req:');
  Lines.Add('        arr = req["args"]');
  Lines.Add('        if not isinstance(arr, list):');
  Lines.Add('            raise ValueError("\"args\" must be a JSON array")');
  Lines.Add('        args = []');
  Lines.Add('        for i in range(len(param_names)):');
  Lines.Add('            if i < len(arr):');
  Lines.Add('                args.append(arr[i])');
  Lines.Add('            else:');
  Lines.Add('                args.append(defaults[i])');
  Lines.Add('        return tuple(args), {}');
  Lines.Add('');
  Lines.Add('    kwargs = {}');
  Lines.Add('    for i, name in enumerate(param_names):');
  Lines.Add('        if name in req:');
  Lines.Add('            kwargs[name] = req[name]');
  Lines.Add('        else:');
  Lines.Add('            kwargs[name] = defaults[i]');
  Lines.Add('    return (), kwargs');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_success(out, result):');
  Lines.Add('    """Write a { "code": 0, "result": <result> } response."""');
  Lines.Add('    data = dumps_json({"code": 0, "result": result}).encode("utf-8")');
  Lines.Add('    write_string_bytes(out.raw, data)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _write_error(out, message):');
  Lines.Add('    """Write a { "code": -1, "error": "<message>" } response."""');
  Lines.Add('    data = dumps_json(');
  Lines.Add('        {"code": -1, "error": str(message)}).encode("utf-8")');
  Lines.Add('    write_string_bytes(out.raw, data)');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _make_call_adapter(func, api_name, param_names, defaults):');
  Lines.Add('    """');
  Lines.Add('    Build a LingoFuse Call adapter for a Python function.');
  Lines.Add('');
  Lines.Add('    The adapter reads the JSON request from the input handle,');
  Lines.Add('    dispatches to `func`, and writes a JSON response to the output');
  Lines.Add('    handle. Any exception raised by `func` is caught and converted');
  Lines.Add('    into a { "code": -1, "error": "..." } response; the exception');
  Lines.Add('    is also logged so it shows up in the service log.');
  Lines.Add('    """');
  Lines.Add('    def adapter(trigger, inp, out):');
  Lines.Add('        try:');
  Lines.Add('            ok, data = _read_request(inp)');
  Lines.Add('            if not ok:');
  Lines.Add('                if DEBUG_LOG:');
  Lines.Add('                    log.warning("Call %s: %s", api_name, data)');
  Lines.Add('                _write_error(out, data)');
  Lines.Add('                return');
  Lines.Add('');
  Lines.Add('            if DEBUG_LOG:');
  Lines.Add('                log.info("Call %s: request=%r", api_name, data)');
  Lines.Add('');
  Lines.Add('            args, kwargs = _extract_args(data, param_names, defaults)');
  Lines.Add('            result = func(*args, **kwargs)');
  Lines.Add('');
  Lines.Add('            if DEBUG_LOG:');
  Lines.Add('                log.info("Call %s: result=%r", api_name, result)');
  Lines.Add('');
  Lines.Add('            _write_success(out, result)');
  Lines.Add('');
  Lines.Add('        except Exception as e:');
  Lines.Add('            log.exception("Call API %s raised an exception", api_name)');
  Lines.Add('            try:');
  Lines.Add('                _write_error(out, str(e) or type(e).__name__)');
  Lines.Add('            except Exception:');
  Lines.Add('                log.exception("Failed to write error response for %s",');
  Lines.Add('                              api_name)');
  Lines.Add('');
  Lines.Add('    return adapter');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('def _make_notify_adapter(func, api_name, param_names, defaults):');
  Lines.Add('    """');
  Lines.Add('    Build a LingoFuse Notify adapter for a Python function.');
  Lines.Add('');
  Lines.Add('    Notify callbacks have no output handle. The adapter reads the');
  Lines.Add('    request, dispatches to `func`, and logs any exception without');
  Lines.Add('    propagating it.');
  Lines.Add('    """');
  Lines.Add('    def adapter(trigger, inp):');
  Lines.Add('        try:');
  Lines.Add('            ok, data = _read_request(inp)');
  Lines.Add('            if not ok:');
  Lines.Add('                if DEBUG_LOG:');
  Lines.Add('                    log.warning("Notify %s: %s", api_name, data)');
  Lines.Add('                return');
  Lines.Add('');
  Lines.Add('            if DEBUG_LOG:');
  Lines.Add('                log.info("Notify %s: request=%r", api_name, data)');
  Lines.Add('');
  Lines.Add('            args, kwargs = _extract_args(data, param_names, defaults)');
  Lines.Add('            func(*args, **kwargs)');
  Lines.Add('');
  Lines.Add('        except Exception:');
  Lines.Add('            log.exception("Notify API %s raised an exception", api_name)');
  Lines.Add('');
  Lines.Add('    return adapter');
  Lines.Add('');
  Lines.Add('');
end;

// EmitPyStubs - one internal_call_<api> stub per supported routine.
procedure EmitPyStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName: TP_String;
  ParamList: TP_String;
  CallArgs: TP_String;
  Annotation: TP_String;
  Description: TP_String;
  StubName: TP_String;
begin
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Internal call stubs');
  Lines.Add('#');
  Lines.Add('# Each stub mirrors one original routine. Replace the body with a');
  Lines.Add('# call to the real implementation, for example:');
  Lines.Add('#     return MyModule.Add(a, b)');
  Lines.Add('# The parameter names and type annotations are already correct.');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := MakeInternalCallName(ApiName);

    ParamList := BuildPyParamList(F.Params);
    CallArgs := BuildPyCallArgList(F.Params);
    Description := GetFullDescription(F.Comment);

    if F.IsFunction then
      Annotation := ' -> ' + ABI_Type_To_Py_Annotation(F.ReturnType)
    else
      Annotation := '';

    Lines.Add('def ' + StubName.Text + '(' + ParamList.Text + ')' +
      Annotation.Text + ':');

    Lines.Add('    """');
    if Description.Len > 0 then
      Lines.Add('    ' + Description.Text)
    else
      Lines.Add('    HTTP/JSON API stub for ' + ApiName.Text + '.');
    Lines.Add('');
    Lines.Add('    TODO: replace the body with a call to the real implementation.');
    if Length(F.Params) > 0 then
      Lines.Add('    Suggested call: ' + F.Name.Text + '(' + CallArgs.Text + ')')
    else
      Lines.Add('    Suggested call: ' + F.Name.Text + '()');
    Lines.Add('    """');

    if F.IsFunction then
    begin
      Lines.Add('    # TODO: implement this stub.');
      Lines.Add('    return ' + ABI_Type_To_Py_Default(F.ReturnType));
    end
    else
    begin
      Lines.Add('    # TODO: implement this stub.');
      Lines.Add('    pass');
    end;
    Lines.Add('');
    Lines.Add('');
  end;
end;

// EmitPyRegistration - RegisterAllHTTPJsonAPIs and the App factory.
procedure EmitPyRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName: TP_String;
  StubName: TP_String;
  NameList: TP_String;
  DefaultList: TP_String;
  Description: TP_String;
begin
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Registration');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('def register_all_http_json_apis(app):');
  Lines.Add('    """Register every generated Call API on the given App."""');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := MakeInternalCallName(ApiName);
    NameList := BuildPyNameList(F.Params);
    DefaultList := BuildPyDefaultList(F.Params);

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON api for ' + F.Name;

    Lines.Add('    app.register_call(');
    Lines.Add('        ' + PyStrLit(ApiName).Text + ',');
    Lines.Add('        _make_call_adapter(' + StubName.Text + ', ' +
      PyStrLit(ApiName).Text + ', ' + NameList.Text + ', ' +
      DefaultList.Text + '),');
    Lines.Add('        ' + PyStrLit(Description).Text + ',');
    Lines.Add('    )');
    Lines.Add('');
  end;

  if Length(SupportedFuncs) = 0 then
  begin
    Lines.Add('    # No supported routines were generated.');
    Lines.Add('    pass');
    Lines.Add('');
  end;

  Lines.Add('');
  Lines.Add('def create_and_register_http_json_app():');
  Lines.Add('    """');
  Lines.Add('    Create a new LingoFuse App and register every generated Call API.');
  Lines.Add('');
  Lines.Add('    The caller owns the returned App object and must call `free()`');
  Lines.Add('    on it when done. The generated `main()` handles this');
  Lines.Add('    automatically on shutdown.');
  Lines.Add('    """');
  Lines.Add('    app = App(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)');
  Lines.Add('    if app is not None:');
  Lines.Add('        register_all_http_json_apis(app)');
  Lines.Add('    return app');
  Lines.Add('');
  Lines.Add('');
end;

// EmitPyMain - main() entry point and the script guard.
// EmitPyMain - main() entry point and the script guard.
procedure EmitPyMain(Lines: TPascalStringList; const Endpoint: TP_String);
begin
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Main entry point');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('def main() -> int:');
  Lines.Add('    """');
  Lines.Add('    Start the service and block until a termination signal arrives.');
  Lines.Add('');
  Lines.Add('    Returns the process exit code: 0 on success, 1 on any fatal');
  Lines.Add('    startup error.');
  Lines.Add('    """');
  Lines.Add('    logging.basicConfig(');
  Lines.Add('        level=logging.DEBUG if DEBUG_LOG else logging.INFO,');
  Lines.Add('        format=' + #39 + '[%(asctime)s] [%(levelname)s] %(name)s: %(message)s' + #39 + ',');
  Lines.Add('    )');
  Lines.Add('');
  Lines.Add('    log.info("=== %s HTTP/JSON service ===", HTTP_SERVICE_APP_NAME)');
  Lines.Add('    log.info("Endpoint: %s", HTTP_SERVICE_ENDPOINT)');
  Lines.Add('');
  Lines.Add('    # Deployment mode: do not block waiting for peers that are');
  Lines.Add('    # not yet ready. This lets bridge.py and this service start');
  Lines.Add('    # in any order.');
  Lines.Add('    try:');
  Lines.Add('        import lingofuse');
  Lines.Add('        if hasattr(lingofuse, "set_option"):');
  Lines.Add('            lingofuse.set_option("Wait_Connection_ReadyOk", "False")');
  Lines.Add('    except Exception:');
  Lines.Add('        pass');
  Lines.Add('');
  Lines.Add('    LF_ResetPrepare()');
  Lines.Add('');
  Lines.Add('    serv_ret = LF_PrepareService(');
  Lines.Add('        cstr(HTTP_SERVICE_ENDPOINT),');
  Lines.Add('        cstr(HTTP_SERVICE_ENDPOINT),');
  Lines.Add('    )');
  Lines.Add('    if serv_ret == -1:');
  Lines.Add('        log.error("LF_PrepareService failed for endpoint \"%s\"",');
  Lines.Add('                  HTTP_SERVICE_ENDPOINT)');
  Lines.Add('        log.error("The address may already be in use, or invalid.")');
  Lines.Add('        return 1');
  Lines.Add('');
  Lines.Add('    app = create_and_register_http_json_app()');
  Lines.Add('    if app is None:');
  Lines.Add('        log.error("Failed to create the LingoFuse App.")');
  Lines.Add('        return 1');
  Lines.Add('');
  Lines.Add('    client_ret = LF_PrepareClient(');
  Lines.Add('        cstr(HTTP_SERVICE_ENDPOINT),');
  Lines.Add('        app.raw,');
  Lines.Add('    )');
  Lines.Add('    if client_ret == -1:');
  Lines.Add('        log.error("LF_PrepareClient failed for endpoint \"%s\"",');
  Lines.Add('                  HTTP_SERVICE_ENDPOINT)');
  Lines.Add('        app.free()');
  Lines.Add('        return 1');
  Lines.Add('');
  Lines.Add('    if LF_PrepareDone() != 1:');
  Lines.Add('        log.error("LF_PrepareDone failed.")');
  Lines.Add('        app.free()');
  Lines.Add('        return 1');
  Lines.Add('');
  Lines.Add('    log.info("[OK] Service ready. Press Ctrl+C to stop.")');
  Lines.Add('');
  Lines.Add('    # ---- Signal-driven shutdown ----');
  Lines.Add('    stop_event = threading.Event()');
  Lines.Add('');
  Lines.Add('    def _on_signal(signum, _frame):');
  Lines.Add('        log.info("Signal %d received, shutting down...", signum)');
  Lines.Add('        stop_event.set()');
  Lines.Add('');
  Lines.Add('    original_sigint = signal.signal(signal.SIGINT, _on_signal)');
  Lines.Add('    try:');
  Lines.Add('        original_sigterm = signal.signal(signal.SIGTERM, _on_signal)');
  Lines.Add('    except (AttributeError, ValueError):');
  Lines.Add('        original_sigterm = None');
  Lines.Add('');
  Lines.Add('    try:');
  Lines.Add('        while not stop_event.is_set():');
  Lines.Add('            stop_event.wait(0.5)');
  Lines.Add('    except KeyboardInterrupt:');
  Lines.Add('        log.info("KeyboardInterrupt received, shutting down...")');
  Lines.Add('    finally:');
  Lines.Add('        signal.signal(signal.SIGINT, original_sigint)');
  Lines.Add('        if original_sigterm is not None:');
  Lines.Add('            signal.signal(signal.SIGTERM, original_sigterm)');
  Lines.Add('');
  Lines.Add('    # ---- Clean shutdown ----');
  Lines.Add('    LF_ExitMainThread()');
  Lines.Add('    app.free()');
  Lines.Add('    LF_Shutdown()');
  Lines.Add('');
  Lines.Add('    log.info("Service stopped.")');
  Lines.Add('    return 0');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('if __name__ == "__main__":');
  Lines.Add('    sys.exit(main())');
  Lines.Add('');
end;

function GenerateHTTPServicePythonCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServicePythonCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServicePythonCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating HTTP/JSON Python service code for unit "%s"',
    [UnitName.Text]));

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

    EmitPyHeader(Lines, UnitName, NormalizedUnit, AppName, Endpoint);
    EmitPyJsonHelpers(Lines);
    EmitPyStubs(Lines, SupportedFuncs, ApiNames);
    EmitPyRegistration(Lines, SupportedFuncs, ApiNames);
    EmitPyMain(Lines, Endpoint);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
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
    'python', 'Python HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.py', False,
    @GenerateHTTPServicePythonCode);
end.
