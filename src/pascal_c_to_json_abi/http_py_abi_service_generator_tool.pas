unit http_py_abi_service_generator_tool;

// http_py_abi_service_generator_tool - LingoFuse HTTP/JSON ABI Service
// Provider Generator for Python.
//
// This unit consumes a TPascal_Func_Model (built with
// Typ_Normalize_Func = tnf_ABI) and produces a complete Python module
// that can be executed as a LingoFuse HTTP/JSON service provider.
//
// The generated Python module is a LingoFuse Call service that expects
// JSON requests and produces JSON responses. It is designed to be
// reached via bridge.py from any HTTP client (webjs / PHP / nodejs).
// The bridge performs the HTTP <-> LingoFuse conversion; the generated
// module only deals with JSON strings.
//
// Wire protocol (HTTP/JSON path, both directions):
//   request  = JSON object
//              { "args": [v1, v2, ...] }     positional arguments
//              { "a": v1, "b": v2, ... }     named arguments
//   response = JSON object
//              { "code": 0,  "result": ... }  on success
//              { "code": -1, "error":  ... }  on failure
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   Every integer family member collapses to Python int.
//   Every float family member collapses to Python float.
//   Every string family member collapses to Python str.
//
// The generated module imports the `lingofuse` Python package. Rather
// than hard-coding a single module path (which would break whenever
// the package reorganises its internals), the generated code resolves
// each required symbol against a list of candidate module paths, from
// most-public to most-internal. If every candidate fails, it prints a
// diagnostic that names the missing symbol and lists every attempted
// path, then exits. A user can point the generated file at a
// different top-level module name via the LINGOFUSE_MODULE
// environment variable, without editing the file.
//
// The generated module exposes:
//   HTTP_SERVICE_APP_NAME       - LingoFuse application name.
//   HTTP_SERVICE_APP_DESC       - Human-readable description.
//   HTTP_SERVICE_ENDPOINT       - The LingoFuse endpoint to bind to.
//   create_and_register_http_json_app()
//   register_all_http_json_apis(app)
//   main()                      - Entry point when run as a script.
//
// The user is expected to:
//   1. Fill in each `internal_call_<api>` stub in the generated Python
//      file with a call to the real implementation.
//   2. Run the module:
//        python3 <unit>_http_json_service.py
//   3. Start bridge.py with the SAME endpoint:
//        python3 bridge.py --endpoint <endpoint> --no-precheck
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

// GenerateHTTPServicePythonCode - main entry point for the service
// module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServicePythonCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPServicePythonReadme - main entry point for the README.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServicePythonReadme(Model: TPascal_Func_Model): TPascalStringList;

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
  Lines.Add('        "FATAL: cannot import ''{0}'' from the lingofuse package.\\n"');
  Lines.Add('        .format(symbol))');
  Lines.Add('    sys.stderr.write("\\nDiagnostic:\\n")');
  Lines.Add('    for line in _IMPORT_DIAG:');
  Lines.Add('        sys.stderr.write("  " + line + "\\n")');
  Lines.Add('    sys.stderr.write("\\nHow to check:\\n")');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "  python -c \\"import lingofuse; '
    + 'print(lingofuse.__file__)\\"\\n")');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "  python -c \\"import lingofuse; '
    + 'print(dir(lingofuse))\\"\\n")');
  Lines.Add('    sys.stderr.write(');
  Lines.Add('        "\\nTo use a different top-level module name, set the "');
  Lines.Add('        "environment variable LINGOFUSE_MODULE.\\n")');
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
  Lines.Add('        format=''[%(asctime)s] [%(levelname)s] %(name)s: %(message)s'','');');
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

// =============================================================================
// PYTHON SERVICE README GENERATOR
// =============================================================================

function GenerateHTTPServicePythonReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamWire: TP_String;
  ServiceFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  ArgList: TP_String;
  PascalDecl, PySig: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServicePythonReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServicePythonReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  ServiceFileName := NormalizedUnit + '_http_json_service.py';

  Log(PFormat('Generating HTTP/JSON Python service README for unit "%s"',
    [UnitName.Text]));

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

    Lines.Add('# ' + UnitName.Text + ' - Python HTTP/JSON Service Provider');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_py_abi_service_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Service file**      : `' + ServiceFileName.Text + '`');
    Lines.Add('> **Default App name**  : `' + AppName.Text + '`');
    Lines.Add('> **Default endpoint**  : `' + Endpoint.Text + '`');
    Lines.Add('> **Exposed APIs**      : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('>');
    Lines.Add('> **Audience**: Python developers and AI assistants who need to');
    Lines.Add('> fill in the generated stubs, launch the process, and expose the');
    Lines.Add('> service to HTTP clients through `bridge.py`.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **HTTP/JSON service** that was');
    Lines.Add('generated from the Pascal unit `' + UnitName.Text + '`. The');
    Lines.Add('service is a Python module that registers one or more functions');
    Lines.Add('as LingoFuse Call APIs, and is reached from HTTP clients through');
    Lines.Add('the LingoFuse HTTP bridge (`bridge.py`).');
    Lines.Add('');
    Lines.Add('### 1.1 What is an HTTP/JSON Python service?');
    Lines.Add('');
    Lines.Add('An HTTP/JSON Python service is:');
    Lines.Add('');
    Lines.Add('- a plain Python script that imports the `lingofuse` package;');
    Lines.Add('- a set of functions registered with a decorator-free API:');
    Lines.Add('  every stub lives in the same file as the registration code;');
    Lines.Add('- a JSON RPC endpoint that speaks the same wire protocol as the');
    Lines.Add('  Pascal, JavaScript, and C++ services generated from the same');
    Lines.Add('  source unit;');
    Lines.Add('- reachable by any HTTP client (browser, `curl`, `requests`,');
    Lines.Add('  Node.js, PHP, another Python program) through `bridge.py`.');
    Lines.Add('');
    Lines.Add('### 1.2 Design principles');
    Lines.Add('');
    Lines.Add('| Property | Value |');
    Lines.Add('|----------|-------|');
    Lines.Add('| Parameter encoding | Plain-text JSON |');
    Lines.Add('| Type system | Python runtime types (see §6) |');
    Lines.Add('| Discovery | Via the bridge''s HTTP URL path |');
    Lines.Add('| Client | Any HTTP client; no paired code required |');
    Lines.Add('| Runtime dependency | `lingofuse` Python package only |');
    Lines.Add('');
    Lines.Add('### 1.3 Three-step quick start');
    Lines.Add('');
    Lines.Add('1. **Fill in the stubs** in `' + ServiceFileName.Text + '`.');
    Lines.Add('   Each `internal_call_<api>` has a `TODO` comment. See §8.1.');
    Lines.Add('2. **Run the module**: `python3 ' + ServiceFileName.Text + '`.');
    Lines.Add('3. **Start `bridge.py`** with the same endpoint:');
    Lines.Add('   `python3 bridge.py --endpoint ' + Endpoint.Text + ' --no-precheck`.');
    Lines.Add('');
    Lines.Add('After step 3, the service is live and reachable at:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('POST http://<bridge-host>:<bridge-port>/' + AppName.Text + '/<api>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 1.4 The generated module and the lingofuse package');
    Lines.Add('');
    Lines.Add('The generated module imports several symbols from the `lingofuse`');
    Lines.Add('package. Because different installations of that package expose');
    Lines.Add('the same symbols from different module paths, the generated code');
    Lines.Add('resolves each symbol against a list of candidates (from the most');
    Lines.Add('public to the most internal). If every candidate fails, it prints');
    Lines.Add('a diagnostic that names the missing symbol and every attempted');
    Lines.Add('path, then exits.');
    Lines.Add('');
    Lines.Add('If your installation uses a different top-level module name, set');
    Lines.Add('the environment variable `LINGOFUSE_MODULE` before running the');
    Lines.Add('script:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('set LINGOFUSE_MODULE=my_lingofuse            # Windows');
    Lines.Add('export LINGOFUSE_MODULE=my_lingofuse         # Linux / macOS');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 1.5 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + ServiceFileName.Text + '` | The service module (fill in the stubs, then run it). |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_service_python.md` | This README. |');
    Lines.Add('');
    Lines.Add('## 2. Application Scope');
    Lines.Add('');
    Lines.Add('### 2.1 When to use an HTTP/JSON Python service');
    Lines.Add('');
    Lines.Add('Use this generator when:');
    Lines.Add('');
    Lines.Add('- The source unit is a Pascal unit, but you want to expose its');
    Lines.Add('  API surface from a Python process.');
    Lines.Add('- You want **plain-text debugging** — logs and proxies can');
    Lines.Add('  inspect JSON traffic directly.');
    Lines.Add('- You want **cross-language parity**: the Python service uses');
    Lines.Add('  the exact same wire protocol as the Pascal, JavaScript, and');
    Lines.Add('  C++ services.');
    Lines.Add('- You want a **small dependency footprint**: only the `lingofuse`');
    Lines.Add('  package is required on the Python side.');
    Lines.Add('');
    Lines.Add('### 2.2 When NOT to use an HTTP/JSON Python service');
    Lines.Add('');
    Lines.Add('- You need **maximum throughput**. Prefer the binary ABI service.');
    Lines.Add('- You need **strict integer-width preservation**. JSON collapses');
    Lines.Add('  every width into a single Python `int`.');
    Lines.Add('- You need to expose **LingoFuse-native** APIs (no HTTP). Prefer');
    Lines.Add('  a direct Python LingoFuse service.');
    Lines.Add('');
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('### 3.1 Python version');
    Lines.Add('');
    Lines.Add('| Requirement | Minimum version |');
    Lines.Add('|-------------|-----------------|');
    Lines.Add('| CPython | 3.7 |');
    Lines.Add('| PyPy | 3.9+ (untested) |');
    Lines.Add('');
    Lines.Add('### 3.2 Platform support');
    Lines.Add('');
    Lines.Add('| Platform | Architecture | Status |');
    Lines.Add('|----------|-------------|--------|');
    Lines.Add('| Windows | x86_64 | Primary target |');
    Lines.Add('| Linux | x86_64 | Supported |');
    Lines.Add('| Linux | aarch64 | Supported |');
    Lines.Add('| macOS | x86_64 | Supported |');
    Lines.Add('| macOS | aarch64 | Supported |');
    Lines.Add('');
    Lines.Add('### 3.3 Runtime dependencies');
    Lines.Add('');
    Lines.Add('| Dependency | Where to get it |');
    Lines.Add('|------------|----------------|');
    Lines.Add('| Python 3.7+ | python.org or the system package manager |');
    Lines.Add('| `lingofuse` Python package | LingoFuse distribution |');
    Lines.Add('| `LingoFuse64.dll` / `liblingofuse.so` | LingoFuse runtime distribution |');
    Lines.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | LingoFuse runtime distribution |');
    Lines.Add('| `bridge.py` | LingoFuse Python package |');
    Lines.Add('| Flask (for `bridge.py` only) | `pip install flask` |');
    Lines.Add('');
    Lines.Add('The generated service module itself has **no** third-party');
    Lines.Add('dependency beyond the `lingofuse` package. Only `bridge.py`');
    Lines.Add('needs Flask.');
    Lines.Add('');
    Lines.Add('### 3.4 Character encoding');
    Lines.Add('');
    Lines.Add('- **Source files**: UTF-8, declared by the `# -*- coding: utf-8 -*-`');
    Lines.Add('  header.');
    Lines.Add('- **JSON payloads**: UTF-8, both directions.');
    Lines.Add('- **On the wire**: the bridge strips the trailing NUL from');
    Lines.Add('  LingoFuse strings before forwarding to HTTP clients.');
    Lines.Add('');
    Lines.Add('### 3.5 Threading model');
    Lines.Add('');
    Lines.Add('Callbacks execute on LingoFuse worker threads, not on the main');
    Lines.Add('thread. The service can therefore handle several concurrent calls.');
    Lines.Add('');
    Lines.Add('- The main thread blocks in a `threading.Event.wait()` loop and');
    Lines.Add('  does not execute any user code.');
    Lines.Add('- User functions are responsible for their own thread safety,');
    Lines.Add('  exactly as in the Pascal service.');
    Lines.Add('- The module installs SIGINT and SIGTERM handlers to shut down');
    Lines.Add('  gracefully on Ctrl+C or `kill`.');
    Lines.Add('');
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The Python service uses **plain-text JSON** on both directions.');
    Lines.Add('There is **no binary framing**.');
    Lines.Add('');
    Lines.Add('### 4.1 Request');
    Lines.Add('');
    Lines.Add('The HTTP client sends an `HTTP POST` with a JSON object body:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "args": [v1, v2, ..., vN]');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `args` field is an **array of positional arguments**. Named');
    Lines.Add('arguments are also accepted as an alternative:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "a": v1,');
    Lines.Add('  "b": v2');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('If the `args` field is present, named lookup is skipped.');
    Lines.Add('Otherwise, every parameter is looked up by its original Pascal');
    Lines.Add('name. Missing fields fall back to the type''s default value');
    Lines.Add('(`0` for int, `0.0` for float, `""` for str, `None` otherwise).');
    Lines.Add('');
    Lines.Add('### 4.2 Response');
    Lines.Add('');
    Lines.Add('The service always responds with a JSON object:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": 0, "result": <value> }     on success');
    Lines.Add('{ "code": -1, "error":  "<message>" } on failure');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.3 Encoding rules');
    Lines.Add('');
    Lines.Add('| Rule | Value |');
    Lines.Add('|------|-------|');
    Lines.Add('| Text encoding | UTF-8, no BOM |');
    Lines.Add('| Integer type | JSON `number` (Python `int`, unbounded) |');
    Lines.Add('| Floating point type | JSON `number` (Python `float`) |');
    Lines.Add('| String type | JSON `string` (Python `str`) |');
    Lines.Add('| Boolean | Not produced by the service |');
    Lines.Add('');
    Lines.Add('### 4.4 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant H as HTTP Client');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant P as Python Service');
    Lines.Add('    H->>B: POST /<app>/<api>');
    Lines.Add('    Note over H,B: Body: {"args": [a, b]}');
    Lines.Add('    B->>P: LF_Call with JSON payload');
    Lines.Add('    P->>P: _read_request, _extract_args');
    Lines.Add('    P->>P: call internal_call_<api>');
    Lines.Add('    P->>P: _write_success or _write_error');
    Lines.Add('    P-->>B: JSON response');
    Lines.Add('    B-->>H: HTTP 200 with JSON body');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.5 Error response example');
    Lines.Add('');
    Lines.Add('If the user function raises an exception, the service returns:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "code": -1,');
    Lines.Add('  "error": "division by zero"');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The HTTP status is still `200`; the JSON `code` distinguishes');
    Lines.Add('success from failure. The bridge may also return `-2` for a');
    Lines.Add('request-shape error (HTTP 400) and `-3` for a pre-check failure.');
    Lines.Add('');
    Lines.Add('## 5. Runtime Architecture');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    subgraph Python["Python service process"]');
    Lines.Add('        P_APP["create_and_register_http_json_app()"]');
    Lines.Add('        P_SVC["LF_PrepareService(''' + Endpoint.Text + ''')"]');
    Lines.Add('        P_CLI["LF_PrepareClient(''' + Endpoint.Text + ''', app)"]');
    Lines.Add('        P_RUN["LF_PrepareDone()"]');
    Lines.Add('        P_LOOP["wait for SIGINT / SIGTERM"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    subgraph Bridge["Bridge process (bridge.py)"]');
    Lines.Add('        B_HTTP["HTTP listen on :8081"]');
    Lines.Add('        B_LF["LF_Call to ''' + AppName.Text + '''"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    subgraph Client["HTTP client"]');
    Lines.Add('        C_POST["POST /' + AppName.Text + '/<api>"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    P_APP --> P_SVC');
    Lines.Add('    P_SVC --> P_CLI');
    Lines.Add('    P_CLI --> P_RUN');
    Lines.Add('    P_RUN --> P_LOOP');
    Lines.Add('    C_POST --> B_HTTP');
    Lines.Add('    B_HTTP --> B_LF');
    Lines.Add('    B_LF -. "LF_Call" .-> P_LOOP');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 5.1 Startup sequence');
    Lines.Add('');
    Lines.Add('**Python service process:**');
    Lines.Add('');
    Lines.Add('1. Set `Wait_Connection_ReadyOk` to `False`');
    Lines.Add('2. `LF_ResetPrepare()`');
    Lines.Add('3. `LF_PrepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT)`');
    Lines.Add('4. `app = create_and_register_http_json_app()`');
    Lines.Add('5. `LF_PrepareClient(HTTP_SERVICE_ENDPOINT, app.raw)`');
    Lines.Add('6. `LF_PrepareDone()`');
    Lines.Add('7. Block on the shutdown event.');
    Lines.Add('');
    Lines.Add('**Bridge process:**');
    Lines.Add('');
    Lines.Add('1. `python3 bridge.py --endpoint ' + Endpoint.Text + ' \\');
    Lines.Add('        --port 8081 --no-precheck`');
    Lines.Add('2. Wait for the bridge''s HTTP listener to come up.');
    Lines.Add('');
    Lines.Add('## 6. Type Mapping');
    Lines.Add('');
    Lines.Add('### 6.1 The key fact: JSON has fewer types than the binary ABI');
    Lines.Add('');
    Lines.Add('On the wire, every integer family member is a single JSON');
    Lines.Add('`number`, and every string family member is a single JSON');
    Lines.Add('`string`. Python is dynamically typed, so this collapse is');
    Lines.Add('invisible at runtime: the caller receives a Python `int` or');
    Lines.Add('`str` regardless of the declared Pascal type.');
    Lines.Add('');
    Lines.Add('### 6.2 Supported Pascal types and their Python mapping');
    Lines.Add('');
    Lines.Add('| ABI type | Pascal type | Python type | JSON wire type |');
    Lines.Add('|----------|-------------|-------------|----------------|');
    Lines.Add('| `integer` | `Integer` | `int` | `number` |');
    Lines.Add('| `longint` | `LongInt` | `int` | `number` |');
    Lines.Add('| `int64` | `Int64` | `int` | `number` |');
    Lines.Add('| `cardinal` | `Cardinal` | `int` | `number` |');
    Lines.Add('| `dword` | `DWord` | `int` | `number` |');
    Lines.Add('| `longword` | `LongWord` | `int` | `number` |');
    Lines.Add('| `word` | `Word` | `int` | `number` |');
    Lines.Add('| `smallint` | `SmallInt` | `int` | `number` |');
    Lines.Add('| `byte` | `Byte` | `int` | `number` |');
    Lines.Add('| `uint64` | `UInt64` | `int` | `number` |');
    Lines.Add('| `double` | `Double` | `float` | `number` |');
    Lines.Add('| `single` | `Single` | `float` | `number` |');
    Lines.Add('| `extended` | `Extended` | `float` | `number` |');
    Lines.Add('| `real` | `Real` | `float` | `number` |');
    Lines.Add('| `string` | `string` | `str` | `string` |');
    Lines.Add('| `ansistring` | `string` | `str` | `string` |');
    Lines.Add('| `unicodestring` | `string` | `str` | `string` |');
    Lines.Add('| `tpascalstring` | `string` | `str` | `string` |');
    Lines.Add('| `tupascalstring` | `string` | `str` | `string` |');
    Lines.Add('| `tp_string` | `string` | `str` | `string` |');
    Lines.Add('| `pchar` | `string` | `str` | `string` |');
    Lines.Add('| `pansichar` | `string` | `str` | `string` |');
    Lines.Add('| `pwidechar` | `string` | `str` | `string` |');
    Lines.Add('');
    Lines.Add('### 6.3 Unsupported types');
    Lines.Add('');
    Lines.Add('Anything not in §6.2 causes the **entire routine** to be');
    Lines.Add('silently dropped during generation. Common examples:');
    Lines.Add('');
    Lines.Add('- `Boolean`, `WordBool`, `LongBool`');
    Lines.Add('- `Variant`, `OleVariant`');
    Lines.Add('- Arrays, records, classes, interfaces');
    Lines.Add('- Enumerations, sets, generics');
    Lines.Add('- Pointers, function pointers');
    Lines.Add('- `Currency`, `Comp`, `TDateTime`');
    Lines.Add('');
    Lines.Add('## 7. Deployment');
    Lines.Add('');
    Lines.Add('### 7.1 Directory layout');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('my_http_json_py_service/');
    Lines.Add('  ' + ServiceFileName.Text + '      <- generated (described here)');
    Lines.Add('  bridge.py                                 <- from the LingoFuse Python package');
    Lines.Add('  lingofuse/                                <- Python package directory');
    Lines.Add('  LingoFuse64.dll                           <- Windows');
    Lines.Add('  liblingofuse.so                           <- Linux');
    Lines.Add('  liblingofuse.dylib                        <- macOS');
    Lines.Add('  z_ipc_64.dll                              <- Windows');
    Lines.Add('  libz_ipc_64.so                            <- Linux');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.2 Running the service');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 ' + ServiceFileName.Text);
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Expected output:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('[OK] Service ready. Press Ctrl+C to stop.');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.3 Starting the bridge');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 bridge.py --endpoint ' + Endpoint.Text + ' \\');
    Lines.Add('    --port 8081 --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `--no-precheck` flag skips the bridge''s `check_api` step,');
    Lines.Add('which depends on a network broadcast that can lag by up to 3');
    Lines.Add('seconds after the service starts.');
    Lines.Add('');
    Lines.Add('### 7.4 Startup order');
    Lines.Add('');
    Lines.Add('Either order works, because the service uses deployment mode.');
    Lines.Add('If both processes are launched from a script, add a short delay:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 ' + ServiceFileName.Text + ' &');
    Lines.Add('sleep 1');
    Lines.Add('python3 bridge.py --endpoint ' + Endpoint.Text + ' --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.5 Shutdown');
    Lines.Add('');
    Lines.Add('The module installs a SIGINT handler. Press **Ctrl+C** in the');
    Lines.Add('service terminal. The sequence is:');
    Lines.Add('');
    Lines.Add('1. Signal handler sets a stop event.');
    Lines.Add('2. The main loop wakes up and calls `LF_ExitMainThread()`.');
    Lines.Add('3. The App is freed with `app.free()`.');
    Lines.Add('4. `LF_Shutdown()` releases the LingoFuse library.');
    Lines.Add('5. `main()` returns 0.');
    Lines.Add('');
    Lines.Add('SIGTERM (Unix `kill`) triggers the same sequence.');
    Lines.Add('');
    Lines.Add('## 8. Testing');
    Lines.Add('');
    Lines.Add('### 8.1 Filling in a stub');
    Lines.Add('');
    Lines.Add('Open `' + ServiceFileName.Text + '` and locate a stub. Every');
    Lines.Add('stub has the shape:');
    Lines.Add('');
    Lines.Add('```python');
    Lines.Add('def internal_call_<ApiName>(<params>):');
    Lines.Add('    """');
    Lines.Add('    <description>');
    Lines.Add('');
    Lines.Add('    TODO: replace the body with a call to the real implementation.');
    Lines.Add('    Suggested call: <OriginalName>(<args>)');
    Lines.Add('    """');
    Lines.Add('    # TODO: implement this stub.');
    Lines.Add('    return <default>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Replace the `# TODO` line and the `return <default>` line with');
    Lines.Add('the actual call.');
    Lines.Add('');
    Lines.Add('### 8.2 Verifying failure paths');
    Lines.Add('');
    Lines.Add('To exercise the error path, add `raise ValueError(''boom'')` to a');
    Lines.Add('stub body, restart the service, and re-issue the request. The');
    Lines.Add('response should be `{ "code": -1, "error": "boom" }`.');
    Lines.Add('');
    Lines.Add('### 8.3 Enabling verbose logging');
    Lines.Add('');
    Lines.Add('Set `DEBUG_LOG = True` at the top of');
    Lines.Add('`' + ServiceFileName.Text + '` before starting the service.');
    Lines.Add('');
    Lines.Add('### 8.4 Diagnosing an import failure');
    Lines.Add('');
    Lines.Add('If the script exits at startup with a diagnostic listing missing');
    Lines.Add('symbols, run the two commands that the diagnostic prints:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python -c "import lingofuse; print(lingofuse.__file__)"');
    Lines.Add('python -c "import lingofuse; print(dir(lingofuse))"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The first shows where the package is loaded from. The second');
    Lines.Add('shows every top-level symbol it exports. Compare the second with');
    Lines.Add('the diagnostic to see which symbols your installation does not');
    Lines.Add('provide.');
    Lines.Add('');
    Lines.Add('## 9. API Reference');
    Lines.Add('');
    Lines.Add('Total APIs: **' + MdInt(FuncCount).Text + '**.');
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
        Lines.Add('### 9.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('The source unit exposes overloaded routines. The HTTP/JSON');
        Lines.Add('protocol routes by API name, so two overloads cannot both keep');
        Lines.Add('the original name. The generator appends a numeric suffix');
        Lines.Add('(`_1`, `_2`, ...) to every overload after the first.');
        Lines.Add('');
      end;

      Lines.Add('### 9.1 Summary');
      Lines.Add('');
      Lines.Add('| # | API name | Kind | Params | Returns | Description |');
      Lines.Add('|---|----------|------|--------|---------|-------------|');

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

        Lines.Add('| ' + MdInt(i + 1).Text + ' | `' + MdCellEscape(ApiName).Text + '`' +
          ' | ' + if_(F.IsFunction, 'function', 'procedure') +
          ' | ' + MdInt(Length(F.Params)).Text +
          ' | `' + MdCellEscape(ParamWire).Text + '`' +
          ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        HasParams := Length(F.Params) > 0;

        ArgList := BuildPyCallArgList(F.Params);
        PascalDecl := BuildPascalDecl(F);
        PySig := BuildPySignature(F, ApiName);

        Lines.Add('### 9.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');
        Lines.Add('- **Pascal source**: `' + PascalDecl.Text + '`');
        Lines.Add('- **Python signature**: `' + PySig.Text + '`');
        Lines.Add('- **Exposed API name**: `' + ApiName.Text + '`');
        Lines.Add('- **Kind**: ' + if_(F.IsFunction, 'function', 'procedure'));
        if F.IsFunction then
          Lines.Add('- **Returns**: `' + ABI_Type_To_Py_Annotation(F.ReturnType) + '`');
        Lines.Add('- **HTTP route**: `POST /' + AppName.Text + '/' + ApiName.Text + '`');
        Lines.Add('- **Stub to fill in**: `' + MakeInternalCallName(ApiName).Text + '`');
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
          Lines.Add('#### Parameters');
          Lines.Add('');
          Lines.Add('| # | Name | Python type | JSON wire type |');
          Lines.Add('|---|------|-------------|----------------|');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafePyIdent(F.Params[j].Name, j);
            ParamType := ABI_Type_To_Py_Annotation(F.Params[j].PascalType);
            ParamWire := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);
            Lines.Add('| ' + MdInt(j + 1).Text + ' | `' +
              MdCellEscape(ParamName).Text + '`' +
              ' | `' + MdCellEscape(ParamType).Text + '`' +
              ' | `' + MdCellEscape(ParamWire).Text + '` |');
          end;
          Lines.Add('');

          Lines.Add('#### Request layout');
          Lines.Add('');
          Lines.Add('```json');
          Lines.Add('{ "args": [' + ArgList.Text + '] }');
          Lines.Add('```');
          Lines.Add('');
        end
        else
        begin
          Lines.Add('#### Request layout');
          Lines.Add('');
          Lines.Add('```json');
          Lines.Add('{}');
          Lines.Add('```');
          Lines.Add('');
        end;

        Lines.Add('#### Success response layout');
        Lines.Add('');
        Lines.Add('```json');
        if F.IsFunction then
          Lines.Add('{ "code": 0, "result": <' +
            ABI_Type_To_Json_Wire_Type(F.ReturnType).Text + '> }')
        else
          Lines.Add('{ "code": 0 }');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('#### Error response');
        Lines.Add('');
        Lines.Add('```json');
        Lines.Add('{ "code": -1, "error": "<message>" }');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    Lines.Add('## 10. Troubleshooting');
    Lines.Add('');
    Lines.Add('### 10.1 Symptom, cause, fix');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| Script exits with "FATAL: cannot import ..." | A required symbol is not exposed by the installed lingofuse package | Follow the diagnostic; run the two "how to check" commands it prints |');
    Lines.Add('| `LF_PrepareService failed` | The endpoint is already in use | Use a different endpoint, or stop the conflicting process |');
    Lines.Add('| `LF_PrepareDone failed` | The LingoFuse library could not initialise | Check the console output |');
    Lines.Add('| HTTP 404 or connection refused | Bridge not running | Start `bridge.py` |');
    Lines.Add('| `{"code": -3}` | Bridge pre-check failed | Add `--no-precheck`, or wait ~3 s after the service starts |');
    Lines.Add('| `{"code": -3}` despite the service running | Bridge endpoint mismatch | Check `--endpoint` matches `' + Endpoint.Text + '` |');
    Lines.Add('| `{"code": -1, "error": "<traceback message>"}` | User stub raised an exception | Check the service log |');
    Lines.Add('| Callback never fires | The stub was not filled in | Search for `TODO` in the generated module |');
    Lines.Add('');
    Lines.Add('## 11. For AI Agents');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('service:');
    Lines.Add('  app_name: ' + AppName.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  service_file: ' + ServiceFileName.Text);
    Lines.Add('  lf_endpoint: ' + Endpoint.Text);
    Lines.Add('  bridge_default_http_port: 8081');
    Lines.Add('');
    Lines.Add('http:');
    Lines.Add('  method: POST');
    Lines.Add('  route_format: "/<app>/<api>"');
    Lines.Add('  content_type: "application/json; charset=utf-8"');
    Lines.Add('  success_status: 200');
    Lines.Add('  failure_status: 200');
    Lines.Add('');
    Lines.Add('request:');
    Lines.Add('  positional: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('  named: ''{"param1": v1, "param2": v2}''');
    Lines.Add('  precedence: args wins when both are present');
    Lines.Add('  missing_field_default: 0 / 0.0 / "" / None');
    Lines.Add('');
    Lines.Add('response:');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('import_policy:');
    Lines.Add('  strategy: progressive_symbol_resolution');
    Lines.Add('  override_env: LINGOFUSE_MODULE');
    Lines.Add('  failure_mode: print diagnostic and exit');
    Lines.Add('');
    Lines.Add('types:');
    Lines.Add('  python_int: "every ABI integer family member"');
    Lines.Add('  python_float: "every ABI float family member"');
    Lines.Add('  python_str: "every ABI string family member"');
    Lines.Add('  unsupported: "Boolean, Variant, arrays, records, classes, interfaces, enums, sets, generics, pointers, Currency, Comp, TDateTime"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_py_abi_service_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated Python service README: %d lines, %d routines.',
      [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
