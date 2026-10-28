unit http_rust_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceRustCode - main entry point for the service module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServiceRustCode(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_rust_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_rust_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification
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

// ABI_Type_To_Rust_Return - Rust return type. Every integer family member
// collapses to i64; every float family member to f64; every string family
// member to String. Procedures use the unit type ().
function ABI_Type_To_Rust_Return(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'f64'
  else if ABI_Type_Is_Int(T) then
    Result := 'i64'
  else
    Result := '()';
end;

// ABI_Type_To_Rust_Param - Rust parameter type. Strings are taken by
// &str (zero-copy), which is the idiomatic Rust way to accept
// caller-owned text.
function ABI_Type_To_Rust_Param(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '&str'
  else if ABI_Type_Is_Float(T) then
    Result := 'f64'
  else if ABI_Type_Is_Int(T) then
    Result := 'i64'
  else
    Result := '()';
end;

// ABI_Type_To_Rust_Extract - the extract_* helper name and the Rust
// type it returns.
procedure ABI_Type_To_Extract_Info(const T: TP_String;
  var HelperName, RustType: TP_String);
begin
  if ABI_Type_Is_String(T) then
  begin
    HelperName := 'extract_string';
    RustType := 'String';
  end
  else if ABI_Type_Is_Float(T) then
  begin
    HelperName := 'extract_f64';
    RustType := 'f64';
  end
  else
  begin
    HelperName := 'extract_i64';
    RustType := 'i64';
  end;
end;

// ABI_Type_To_Rust_Default - Rust literal used as the stub body before
// the user replaces it with a real implementation.
function ABI_Type_To_Rust_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String::new()'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := '()';
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

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

function ABI_Type_Needs_Precision_Note(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// MakeApiName - canonicalize an arbitrary identifier into one that is
// safe to use simultaneously as:
//   * an API name on the wire,
//   * a URL path segment,
//   * a JSON object key,
//   * an identifier in Rust, Pascal, Python, C++, C#, JavaScript,
//     TypeScript, and PHP.
//
// The character set replaced here MUST match every other HTTP/JSON
// generator in this toolchain. If the sets diverge, the same source
// routine would be routed to different API names on the service side
// and on the call side, and every cross-language call would fail.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsRustReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('as') or S.Same('async') or S.Same('await') or S.Same('break') or
    S.Same('const') or S.Same('continue') or S.Same('crate') or S.Same('dyn') or
    S.Same('else') or S.Same('enum') or S.Same('extern') or S.Same('false') or
    S.Same('fn') or S.Same('for') or S.Same('if') or S.Same('impl') or
    S.Same('in') or S.Same('let') or S.Same('loop') or S.Same('match') or
    S.Same('mod') or S.Same('move') or S.Same('mut') or S.Same('pub') or
    S.Same('ref') or S.Same('return') or S.Same('self') or S.Same('Self') or
    S.Same('static') or S.Same('struct') or S.Same('super') or S.Same('trait') or
    S.Same('true') or S.Same('type') or S.Same('unsafe') or S.Same('use') or
    S.Same('where') or S.Same('while') or S.Same('try') or S.Same('abstract') or
    S.Same('become') or S.Same('box') or S.Same('do') or S.Same('final') or
    S.Same('macro') or S.Same('override') or S.Same('priv') or S.Same('typeof') or
    S.Same('unsized') or S.Same('virtual') or S.Same('yield') or
    S.Same('union');
end;

function MakeSafeRustIdent(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if IsRustReservedWord(Result) then
    Result := Result + '_';
end;

// RustStrLit - produce a complete double-quoted Rust string literal with
// the surrounding quotes included. Backslash-escapes follow the Rust
// rules: `"` -> `\"`, `\` -> `\\`, and the common control characters.
function RustStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      '"':  Result.Append('\"');
      '\':  Result.Append('\\');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
      #8:   Result.Append('\x08');
      #12:  Result.Append('\x0c');
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
  Result.Append('"');
end;

// -----------------------------------------------------------------------------
// Markdown helpers (used by the README only)
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
      // Skip CR.
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

function BuildRustParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRustIdent(Params[i].Name, i);
    T := ABI_Type_To_Rust_Param(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + ': ' + T;
  end;
end;

// BuildRustCallArgList - the comma-separated list of argument
// expressions used when calling the user stub. Strings are passed by
// reference (`&name`), so the stub signature uses `&str`.
function BuildRustCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRustIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    if ABI_Type_Is_String(Params[i].PascalType) then
      Result := Result + '&' + n
    else
      Result := Result + n;
  end;
end;

// BuildRustNamesTuple - the tuple literal that silences the unused-
// variable warnings in the generated stub, e.g. "(a, b)" or "a" or "()".
function BuildRustNamesTuple(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := '()';
    Exit;
  end;
  if Length(Params) = 1 then
  begin
    Result := MakeSafeRustIdent(Params[0].Name, 0);
    Exit;
  end;
  Result := '(';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRustIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ')';
end;

// BuildRustDefaultArgList - the "0, 0" default literal list used by the
// README and test generator.
function BuildRustDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := '""'
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else
      d := '0';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
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
    n := MakeSafeRustIdent(F.Params[i].Name, i);
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

// BuildRustStubSignature - full Rust stub signature, used by the README.
function BuildRustStubSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  RetType: TP_String;
begin
  if F.IsFunction then
    RetType := ' -> ' + ABI_Type_To_Rust_Return(F.ReturnType)
  else
    RetType := '';

  if Length(F.Params) > 0 then
    Result := 'pub fn internal_call_' + ApiName + '(' + BuildRustParamDecl(F.Params) + ')' + RetType
  else
    Result := 'pub fn internal_call_' + ApiName + '()' + RetType;
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

procedure BuildDisambiguatedApiNames(
  const SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList);
var
  i, j: integer;
  ApiName: TP_String;
begin
  ApiNames.Clear;
  for i := 0 to High(SupportedFuncs) do
  begin
    ApiName := MakeApiName(SupportedFuncs[i].Name);
    if ApiNames.IndexOf(ApiName) >= 0 then
    begin
      j := 1;
      while ApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
        Inc(j);
      ApiName := ApiName + '_' + umlIntToStr(j).Text;
    end;
    ApiNames.Add(ApiName);
  end;
end;

// =============================================================================
// RUST SERVICE MODULE GENERATOR
// =============================================================================

procedure EmitRustServiceHeader(Lines: TPascalStringList;
  const UnitName: TP_String);
begin
  Lines.Add('// Auto-generated by http_rust_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI service module for Rust, backed by the LingoFuse');
  Lines.Add('// mesh. It registers one JSON-RPC API per supported routine on a');
  Lines.Add('// LingoFuse application, and speaks the wire protocol that every');
  Lines.Add('// other HTTP/JSON generator in this toolchain produces:');
  Lines.Add('//');
  Lines.Add('//   request  = POST /<app>/<api>   (routed through bridge.py)');
  Lines.Add('//              Body: { "args": [v1, v2, ...] }   positional');
  Lines.Add('//                or: { "a": v1, "b": v2, ... }   named');
  Lines.Add('//');
  Lines.Add('//   response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//              { "code": -1, "error":  "<message>" } on handler error');
  Lines.Add('//              { "code": -2, "error":  "<message>" } on request error');
  Lines.Add('//');
  Lines.Add('// ARCHITECTURE');
  Lines.Add('//');
  Lines.Add('//     HTTP client  ──▶  bridge.py  ──▶  LingoFuse mesh  ──▶  this service');
  Lines.Add('//                       (:8081)');
  Lines.Add('//');
  Lines.Add('// The HTTP side is handled by bridge.py (not generated here).');
  Lines.Add('// This file is the LF-side service. It requires:');
  Lines.Add('//   * the `lingofuse` crate');
  Lines.Add('//   * the native LingoFuse shared library (LingoFuse64.dll / .so / .dylib)');
  Lines.Add('//   * a running bridge.py process connected to the SAME endpoint');
  Lines.Add('//');
  Lines.Add('// Crate dependencies (add to Cargo.toml):');
  Lines.Add('//   lingofuse = { path = "../LingoFuse/rust" }   # or crates.io, if published');
  Lines.Add('//   serde_json = "1"');
  Lines.Add('//');
  Lines.Add('// Usage as a crate root:');
  Lines.Add('//   Copy this file to `src/main.rs` and run `cargo run`.');
  Lines.Add('//');
  Lines.Add('// Usage as a sub-module:');
  Lines.Add('//   Save this file as `src/api_service.rs`, add `mod api_service;`');
  Lines.Add('//   to your crate root, and call `api_service::run_service()`');
  Lines.Add('//   from your `fn main()` after the two #![allow] attributes have');
  Lines.Add('//   been converted to module-level #[allow(...)] attributes.');
  Lines.Add('//');
  Lines.Add('// Every API has a corresponding `internal_call_<ApiName>` stub');
  Lines.Add('// near the bottom of this file. Replace each stub body with a call');
  Lines.Add('// to the real implementation.');
  Lines.Add('');
  Lines.Add('#![allow(non_snake_case)]');
  Lines.Add('#![allow(dead_code)]');
  Lines.Add('');
  Lines.Add('use std::time::Duration;');
  Lines.Add('');
  Lines.Add('use lingofuse::app_handle::AppHandle;');
  Lines.Add('use lingofuse::{framework, io};');
  Lines.Add('use serde_json::{json, Value};');
  Lines.Add('');
end;

procedure EmitRustServiceConfig(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Configuration');
  Lines.Add('//');
  Lines.Add('// APP_NAME  : the LingoFuse application name. bridge.py and any');
  Lines.Add('//             HTTP client must use the same name.');
  Lines.Add('// APP_DESC  : human-readable description, shown by the LingoFuse mesh.');
  Lines.Add('// ENDPOINT  : the IPC endpoint that the service binds to. bridge.py');
  Lines.Add('//             must be started with the same --endpoint value.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub const APP_NAME: &str = ' + RustStrLit(AppName).Text + ';');
  Lines.Add('pub const APP_DESC: &str = ' + RustStrLit(AppDesc).Text + ';');
  Lines.Add('pub const ENDPOINT: &str = ' + RustStrLit(Endpoint).Text + ';');
  Lines.Add('');
  Lines.Add('/// Set to true to log every request and response on stderr.');
  Lines.Add('pub const DEBUG_LOG: bool = false;');
  Lines.Add('');
end;

procedure EmitRustServiceExtractors(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Argument extraction');
  Lines.Add('//');
  Lines.Add('// The wire protocol supports two request shapes:');
  Lines.Add('//   {"args": [v1, v2, ...]}        positional');
  Lines.Add('//   {"a": v1, "b": v2, ...}        named');
  Lines.Add('//');
  Lines.Add('// If "args" is present and is a JSON array, positional lookup is');
  Lines.Add('// used. Otherwise, named lookup is used.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('fn extract_raw<' + #39 + 'a>(body: &' + #39 + 'a Value, name: &str, index: usize)');
  Lines.Add('    -> Result<&' + #39 + 'a Value, String>');
  Lines.Add('{');
  Lines.Add('    if let Some(arr) = body.get("args").and_then(|v| v.as_array()) {');
  Lines.Add('        return arr.get(index).ok_or_else(|| {');
  Lines.Add('            format!("Missing positional argument #{} (''{}'')", index, name)');
  Lines.Add('        });');
  Lines.Add('    }');
  Lines.Add('    body.get(name).ok_or_else(|| {');
  Lines.Add('        format!("Missing argument ''{}''", name)');
  Lines.Add('    })');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn extract_i64(body: &Value, name: &str, index: usize)');
  Lines.Add('    -> Result<i64, String>');
  Lines.Add('{');
  Lines.Add('    extract_raw(body, name, index)?');
  Lines.Add('        .as_i64()');
  Lines.Add('        .ok_or_else(|| format!("Argument ''{}'' is not an integer", name))');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn extract_f64(body: &Value, name: &str, index: usize)');
  Lines.Add('    -> Result<f64, String>');
  Lines.Add('{');
  Lines.Add('    extract_raw(body, name, index)?');
  Lines.Add('        .as_f64()');
  Lines.Add('        .ok_or_else(|| format!("Argument ''{}'' is not a number", name))');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn extract_string(body: &Value, name: &str, index: usize)');
  Lines.Add('    -> Result<String, String>');
  Lines.Add('{');
  Lines.Add('    extract_raw(body, name, index)?');
  Lines.Add('        .as_str()');
  Lines.Add('        .map(|s| s.to_string())');
  Lines.Add('        .ok_or_else(|| format!("Argument ''{}'' is not a string", name))');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRustServiceStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, NamesTuple, RetType, DefaultRet, Description: TP_String;
  HasParams: boolean;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// User-editable API stubs');
  Lines.Add('//');
  Lines.Add('// This is the ONLY section you are expected to edit. Replace each');
  Lines.Add('// stub body with a call to the real implementation, for example:');
  Lines.Add('//');
  Lines.Add('//     pub fn internal_call_Add(a: i64, b: i64) -> i64 {');
  Lines.Add('//         my_crate::math::add(a, b)');
  Lines.Add('//     }');
  Lines.Add('//');
  Lines.Add('// The parameter names and types are already correct. String');
  Lines.Add('// parameters are taken as &str, so no allocation is required to');
  Lines.Add('// read them. The wire protocol wraps every stub call in the');
  Lines.Add('// response envelope; stubs only need to return the raw value.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(F.Params) > 0;
    ParamDecl := BuildRustParamDecl(F.Params);

    Description := GetFullDescription(F.Comment);
    if Description.Len > 0 then
      Lines.Add('/// ' + Description.Text);
    Lines.Add('///');
    Lines.Add('/// Original Pascal: ' + BuildPascalDecl(F).Text);

    if F.IsFunction then
    begin
      RetType := ABI_Type_To_Rust_Return(F.ReturnType);
      DefaultRet := ABI_Type_To_Rust_Default(F.ReturnType);
      if HasParams then
        Lines.Add('pub fn internal_call_' + ApiName.Text + '(' + ParamDecl.Text + ') -> ' + RetType.Text + ' {')
      else
        Lines.Add('pub fn internal_call_' + ApiName.Text + '() -> ' + RetType.Text + ' {');
      if HasParams then
      begin
        NamesTuple := BuildRustNamesTuple(F.Params);
        Lines.Add('    let _ = ' + NamesTuple.Text + ';');
      end;
      Lines.Add('    // TODO: replace this body with the real implementation.');
      Lines.Add('    ' + DefaultRet.Text);
      Lines.Add('}');
    end
    else
    begin
      if HasParams then
        Lines.Add('pub fn internal_call_' + ApiName.Text + '(' + ParamDecl.Text + ') {')
      else
        Lines.Add('pub fn internal_call_' + ApiName.Text + '() {');
      if HasParams then
      begin
        NamesTuple := BuildRustNamesTuple(F.Params);
        Lines.Add('    let _ = ' + NamesTuple.Text + ';');
      end;
      Lines.Add('    // TODO: replace this body with the real implementation.');
      Lines.Add('}');
    end;
    Lines.Add('');
  end;
end;

procedure EmitRustServiceCallbacks(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, Description, ParamName, HelperName, RustType, ArgCall: TP_String;
  HasParams: boolean;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// LingoFuse callback wiring');
  Lines.Add('//');
  Lines.Add('// One closure per API. Each closure reads the JSON request from the');
  Lines.Add('// input DataHandle, extracts the typed arguments, invokes the');
  Lines.Add('// corresponding user stub, and writes the JSON response envelope to');
  Lines.Add('// the output DataHandle.');
  Lines.Add('//');
  Lines.Add('// A DataHandle here is a LingoFuse handle, not a file descriptor.');
  Lines.Add('// Input is read-only; output is write-only. Both are freed by the');
  Lines.Add('// LingoFuse mesh when the callback returns.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(F.Params) > 0;

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    Lines.Add('fn cb_' + ApiName.Text +
      '(input: &mut lingofuse::data_handle::DataHandle,');
    Lines.Add('    output: &mut lingofuse::data_handle::DataHandle) {');
    Lines.Add('    // Parse the request envelope.');
    Lines.Add('    let body: Value = match io::read_json(input) {');
    Lines.Add('        Ok(v) => v,');
    Lines.Add('        Err(e) => {');
    Lines.Add('            let _ = io::write_json(output, &json!({');
    Lines.Add('                "code": -2,');
    Lines.Add('                "error": format!("Invalid JSON request: {}", e)');
    Lines.Add('            }));');
    Lines.Add('            return;');
    Lines.Add('        }');
    Lines.Add('    };');
    Lines.Add('    if DEBUG_LOG {');
    Lines.Add('        eprintln!("[service] ' + ApiName.Text + ' request: {}", body);');
    Lines.Add('    }');
    Lines.Add('');

    // Extract each parameter.
    for j := 0 to High(F.Params) do
    begin
      ParamName := MakeSafeRustIdent(F.Params[j].Name, j);
      ABI_Type_To_Extract_Info(F.Params[j].PascalType, HelperName, RustType);
      Lines.Add('    let ' + ParamName.Text + ': ' + RustType.Text + ' = match ' +
        HelperName.Text + '(&body, ' +
        RustStrLit(F.Params[j].Name).Text + ', ' + umlIntToStr(j).Text + ') {');
      Lines.Add('        Ok(v) => v,');
      Lines.Add('        Err(msg) => {');
      Lines.Add('            let _ = io::write_json(output, &json!({');
      Lines.Add('                "code": -1,');
      Lines.Add('                "error": msg');
      Lines.Add('            }));');
      Lines.Add('            return;');
      Lines.Add('        }');
      Lines.Add('    };');
    end;

    if HasParams then
      ArgCall := BuildRustCallArgList(F.Params)
    else
      ArgCall := '';

    if F.IsFunction then
    begin
      Lines.Add('    let result = internal_call_' + ApiName.Text + '(' + ArgCall + ');');
      Lines.Add('    let _ = io::write_json(output, &json!({');
      Lines.Add('        "code": 0,');
      Lines.Add('        "result": result');
      Lines.Add('    }));');
    end
    else
    begin
      Lines.Add('    internal_call_' + ApiName.Text + '(' + ArgCall + ');');
      Lines.Add('    let _ = io::write_json(output, &json!({');
      Lines.Add('        "code": 0,');
      Lines.Add('        "result": null');
      Lines.Add('    }));');
    end;

    Lines.Add('}');
    Lines.Add('');
  end;
end;

procedure EmitRustServiceRegister(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Description: TP_String;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Registration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('pub fn register_all_apis(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    Lines.Add('    app.register_call(');
    Lines.Add('        ' + RustStrLit(ApiName).Text + ',');
    Lines.Add('        ' + RustStrLit(Description).Text + ',');
    Lines.Add('        cb_' + ApiName.Text + ',');
    Lines.Add('    )?;');
  end;

  Lines.Add('    Ok(())');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRustServiceMain(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Entry point');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('/// Starts the LingoFuse service and blocks until the process is');
  Lines.Add('/// terminated.');
  Lines.Add('///');
  Lines.Add('/// This function performs the full LingoFuse lifecycle:');
  Lines.Add('///   1. Create the AppHandle.');
  Lines.Add('///   2. Register every API on it.');
  Lines.Add('///   3. Configure the framework for deployment mode.');
  Lines.Add('///   4. Prepare the service (listen) and the client (self-connect).');
  Lines.Add('///   5. Call prepare_done().');
  Lines.Add('///   6. Block forever.');
  Lines.Add('///');
  Lines.Add('/// On failure the function prints the error and exits with code 1.');
  Lines.Add('pub fn run_service() -> Result<AppHandle, Box<dyn std::error::Error>> {');
  Lines.Add('    println!("=== {} HTTP/JSON service ===", APP_NAME);');
  Lines.Add('    println!("Endpoint: {}", ENDPOINT);');
  Lines.Add('');
  Lines.Add('    // Step 1 + 2: create the app and register every API.');
  Lines.Add('    let app = AppHandle::new(APP_NAME, APP_DESC)?;');
  Lines.Add('    register_all_apis(&app)?;');
  Lines.Add('    println!("Registered APIs on LingoFuse app ''{}''", APP_NAME);');
  Lines.Add('');
  Lines.Add('    // Step 3: configure the framework.');
  Lines.Add('    framework::set_option("Wait_Connection_ReadyOk", "False")?;');
  Lines.Add('    framework::set_option("Overlap_Connection", "True")?;');
  Lines.Add('    framework::set_option("Quiet", if DEBUG_LOG { "False" } else { "True" })?;');
  Lines.Add('    framework::reset_prepare();');
  Lines.Add('');
  Lines.Add('    // Step 4: prepare the service (listen) and the client');
  Lines.Add('    // (self-connect). Both use the same endpoint, which makes this');
  Lines.Add('    // process a full LingoFuse node. bridge.py connects to the same');
  Lines.Add('    // endpoint from its own process.');
  Lines.Add('    let serv_tag = framework::prepare_service(ENDPOINT, ENDPOINT)?;');
  Lines.Add('    if serv_tag < 0 {');
  Lines.Add('        return Err(format!("prepare_service failed: tag={}", serv_tag).into());');
  Lines.Add('    }');
  Lines.Add('    let cli_tag = framework::prepare_client(ENDPOINT, Some(&app))?;');
  Lines.Add('    if cli_tag < 0 {');
  Lines.Add('        return Err(format!("prepare_client failed: tag={}", cli_tag).into());');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    // Step 5: start the mesh.');
  Lines.Add('    if !framework::prepare_done()? {');
  Lines.Add('        return Err("prepare_done returned false (framework is already running)".into());');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    println!();');
  Lines.Add('    println!("[OK] Service ready. Press Ctrl+C to stop.");');
  Lines.Add('');
  Lines.Add('    // Step 6: block forever. The LingoFuse mesh dispatches calls on');
  Lines.Add('    // its own worker threads, so this loop only needs to keep the');
  Lines.Add('    // process alive.');
  Lines.Add('    Ok(app)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn main() {');
  Lines.Add('    // Hold the AppHandle until the process exits, so that the');
  Lines.Add('    // LingoFuse runtime keeps its registration alive. Ctrl+C will');
  Lines.Add('    // terminate the process directly; the OS cleans up.');
  Lines.Add('    let _app = match run_service() {');
  Lines.Add('        Ok(a) => a,');
  Lines.Add('        Err(e) => {');
  Lines.Add('            eprintln!("[FATAL] {}", e);');
  Lines.Add('            std::process::exit(1);');
  Lines.Add('        }');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    loop {');
  Lines.Add('        std::thread::sleep(Duration::from_millis(500));');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceRustCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceRustCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceRustCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating HTTP/JSON Rust service module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitRustServiceHeader(Lines, UnitName);
    EmitRustServiceConfig(Lines, AppName, AppDesc, Endpoint);
    EmitRustServiceExtractors(Lines);
    EmitRustServiceStubs(Lines, SupportedFuncs, ApiNames);
    EmitRustServiceCallbacks(Lines, SupportedFuncs, ApiNames);
    EmitRustServiceRegister(Lines, SupportedFuncs, ApiNames);
    EmitRustServiceMain(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'rust', 'Rust HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service_rs.rs', False,
    @GenerateHTTPServiceRustCode);
end.
