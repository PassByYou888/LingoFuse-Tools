unit http_rust_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallRustCode - main entry point for the call module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallRustCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_rust_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_rust_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

// ABI_Type_To_Rust_ResultExtract - the code that turns a serde_json::Value
// into the declared Rust return type, or returns an HttpCallError.
function ABI_Type_To_Rust_ResultExtract(const T: TP_String; const Expr: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := Expr + '.as_str().map(|s| s.to_string())'
      + '.ok_or_else(|| HttpCallError::new("Result is not a JSON string"))'
  else if ABI_Type_Is_Float(T) then
    Result := Expr + '.as_f64()'
      + '.ok_or_else(|| HttpCallError::new("Result is not a JSON number"))'
  else if ABI_Type_Is_Int(T) then
    Result := Expr + '.as_i64()'
      + '.ok_or_else(|| HttpCallError::new("Result is not a JSON integer"))'
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
// Bytes outside the printable ASCII range are emitted as `\xNN` where
// valid; this only applies to ASCII control codes, since multi-byte
// UTF-8 sequences are preserved verbatim (Rust source is UTF-8).
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
// Comment description extraction (shared with every other generator)
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

// BuildRustArgVecInit - the argument vector initializer, e.g.
// "vec![json!(a), json!(b)]" for two integer parameters. Empty when the
// routine has no parameters; the caller then emits "Vec::new()".
function BuildRustArgVecInit(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := 'Vec::new()';
    Exit;
  end;

  Result := 'vec![';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRustIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + 'json!(' + n + ')';
  end;
  Result := Result + ']';
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

// BuildRustSyncSignature - the full sync Rust signature, used by the README.
function BuildRustSyncSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  RetType: TP_String;
begin
  if F.IsFunction then
    RetType := 'Result<' + ABI_Type_To_Rust_Return(F.ReturnType) + ', HttpCallError>'
  else
    RetType := 'Result<(), HttpCallError>';

  if Length(F.Params) > 0 then
    Result := 'pub fn ' + ApiName + '(' + BuildRustParamDecl(F.Params) + ') -> ' + RetType
  else
    Result := 'pub fn ' + ApiName + '() -> ' + RetType;
end;

// BuildRustAsyncSignature - the full async Rust signature, used by the README.
function BuildRustAsyncSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  RetType: TP_String;
begin
  if F.IsFunction then
    RetType := 'Result<' + ABI_Type_To_Rust_Return(F.ReturnType) + ', HttpCallError>'
  else
    RetType := 'Result<(), HttpCallError>';

  if Length(F.Params) > 0 then
    Result := 'pub async fn ' + ApiName + '_async(' + BuildRustParamDecl(F.Params) + ') -> ' + RetType
  else
    Result := 'pub async fn ' + ApiName + '_async() -> ' + RetType;
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
// RUST CALL MODULE GENERATOR
// =============================================================================

procedure EmitRustHeader(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('// Auto-generated by http_rust_abi_call_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI call-side module for Rust.');
  Lines.Add('//');
  Lines.Add('// Every supported routine has TWO functions:');
  Lines.Add('//   * `pub fn <ApiName>(...)`           - synchronous (ureq)');
  Lines.Add('//   * `pub async fn <ApiName>_async(..)` - asynchronous (reqwest)');
  Lines.Add('//');
  Lines.Add('// The synchronous variant is a plain blocking function; the async');
  Lines.Add('// variant must be awaited inside a tokio runtime.');
  Lines.Add('//');
  Lines.Add('// Wire protocol:');
  Lines.Add('//   request  = POST <base_url>/<api>');
  Lines.Add('//              Content-Type: application/json; charset=utf-8');
  Lines.Add('//              Body: { "args": [v1, v2, ...] }');
  Lines.Add('//');
  Lines.Add('//   response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//              { "code": -1, "error":  "<message>" } on failure');
  Lines.Add('//');
  Lines.Add('// Dependencies (add to Cargo.toml):');
  Lines.Add('//   ureq = "2"');
  Lines.Add('//   reqwest = { version = "0.12", features = ["json"] }');
  Lines.Add('//   tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }');
  Lines.Add('//   serde_json = "1"');
  Lines.Add('//');
  Lines.Add('// Usage as a crate root:');
  Lines.Add('//   Copy this file to `src/main.rs` (or `src/lib.rs`) and call');
  Lines.Add('//   the generated functions from `fn main()` (sync) or');
  Lines.Add('//   `#[tokio::main] async fn main()` (async).');
  Lines.Add('//');
  Lines.Add('// Usage as a sub-module:');
  Lines.Add('//   Save this file as `src/api.rs`, add `mod api;` to your');
  Lines.Add('//   crate root, and remove (or move) the two crate-level');
  Lines.Add('//   attributes below.');
  Lines.Add('');
  Lines.Add('#![allow(non_snake_case)]');
  Lines.Add('#![allow(dead_code)]');
  Lines.Add('');
  Lines.Add('use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};');
  Lines.Add('use std::sync::{Mutex, OnceLock};');
  Lines.Add('use std::time::Duration;');
  Lines.Add('');
  Lines.Add('use serde_json::{json, Value};');
  Lines.Add('');
end;

procedure EmitRustConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Configuration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('/// Default base URL of the target bridge / service, including the app name.');
  Lines.Add('pub const DEFAULT_BASE_URL: &str = ' + RustStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('/// Default per-request timeout, in seconds. Zero means "wait forever"');
  Lines.Add('/// (implemented as a one-year effective timeout).');
  Lines.Add('pub const DEFAULT_TIMEOUT_SECS: u64 = 30;');
  Lines.Add('');
  Lines.Add('static HTTP_CALL_BASE_URL: OnceLock<Mutex<String>> = OnceLock::new();');
  Lines.Add('static HTTP_CALL_TIMEOUT_SECS: AtomicU64 = AtomicU64::new(DEFAULT_TIMEOUT_SECS);');
  Lines.Add('static DEBUG_LOG: AtomicBool = AtomicBool::new(false);');
  Lines.Add('');
  Lines.Add('fn base_url_cell() -> &' + #39 + 'static Mutex<String> {');
  Lines.Add('    HTTP_CALL_BASE_URL.get_or_init(|| Mutex::new(DEFAULT_BASE_URL.to_string()))');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Sets the base URL of the target bridge / service.');
  Lines.Add('pub fn set_base_url(url: &str) {');
  Lines.Add('    *base_url_cell().lock().unwrap() = url.to_string();');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Returns the current base URL.');
  Lines.Add('pub fn get_base_url() -> String {');
  Lines.Add('    base_url_cell().lock().unwrap().clone()');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Sets the per-request timeout, in seconds.');
  Lines.Add('/// Zero is interpreted as "wait forever" (a one-year effective timeout).');
  Lines.Add('pub fn set_timeout_secs(secs: u64) {');
  Lines.Add('    HTTP_CALL_TIMEOUT_SECS.store(secs, Ordering::Relaxed);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Returns the current per-request timeout, in seconds.');
  Lines.Add('pub fn get_timeout_secs() -> u64 {');
  Lines.Add('    HTTP_CALL_TIMEOUT_SECS.load(Ordering::Relaxed)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Enables or disables verbose logging on stderr.');
  Lines.Add('pub fn set_debug_log(enabled: bool) {');
  Lines.Add('    DEBUG_LOG.store(enabled, Ordering::Relaxed);');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Returns whether verbose logging is enabled.');
  Lines.Add('pub fn get_debug_log() -> bool {');
  Lines.Add('    DEBUG_LOG.load(Ordering::Relaxed)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn effective_timeout_secs() -> u64 {');
  Lines.Add('    let t = get_timeout_secs();');
  Lines.Add('    if t > 0 { t } else { 31_536_000 }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRustError(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Error type');
  Lines.Add('//');
  Lines.Add('// The single exception type raised by every generated function.');
  Lines.Add('//');
  Lines.Add('//   code       : the numeric code from the bridge / service response,');
  Lines.Add('//                or -1 for transport-level failures.');
  Lines.Add('//   http_status: the HTTP status code, or 0 when no response was');
  Lines.Add('//                received (network error, timeout, ...).');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('#[derive(Debug, Clone)]');
  Lines.Add('pub struct HttpCallError {');
  Lines.Add('    pub message: String,');
  Lines.Add('    pub code: i32,');
  Lines.Add('    pub http_status: i32,');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('impl HttpCallError {');
  Lines.Add('    pub fn new(message: &str) -> Self {');
  Lines.Add('        Self { message: message.to_string(), code: -1, http_status: 0 }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    pub fn with_code(message: &str, code: i32, http_status: i32) -> Self {');
  Lines.Add('        Self { message: message.to_string(), code, http_status }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('impl std::fmt::Display for HttpCallError {');
  Lines.Add('    fn fmt(&self, f: &mut std::fmt::Formatter<' + #39 + '_>) -> std::fmt::Result {');
  Lines.Add('        write!(f, "{} (code={}, http_status={})",');
  Lines.Add('            self.message, self.code, self.http_status)');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('impl std::error::Error for HttpCallError {}');
  Lines.Add('');
end;

procedure EmitRustTransport(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Internal transport');
  Lines.Add('//');
  Lines.Add('// Two transport functions, one per calling convention:');
  Lines.Add('//   * call_api_sync   - uses ureq (blocking)');
  Lines.Add('//   * call_api_async  - uses reqwest (tokio)');
  Lines.Add('//');
  Lines.Add('// Both implement the same wire protocol:');
  Lines.Add('//   POST <base>/<api>  body={"args":[...]}');
  Lines.Add('//   read response       -> {code, result} or {code, error}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('fn url_for(api_name: &str) -> String {');
  Lines.Add('    let base = get_base_url();');
  Lines.Add('    let base = base.trim_end_matches(' + #39 + '/' + #39 + ');');
  Lines.Add('    format!("{}/{}", base, api_name)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('fn parse_envelope(status: i32, text: &str) -> Result<Value, HttpCallError> {');
  Lines.Add('    if !(200..300).contains(&status) {');
  Lines.Add('        return Err(HttpCallError::with_code(');
  Lines.Add('            &format!("HTTP {}: {}", status, text), -1, status));');
  Lines.Add('    }');
  Lines.Add('    if text.is_empty() {');
  Lines.Add('        return Err(HttpCallError::with_code(');
  Lines.Add('            "Empty response from service", -1, status));');
  Lines.Add('    }');
  Lines.Add('    let parsed: Value = serde_json::from_str(text)');
  Lines.Add('        .map_err(|e| HttpCallError::with_code(');
  Lines.Add('            &format!("Invalid JSON response: {}", e), -1, status))?;');
  Lines.Add('    let code = parsed.get("code")');
  Lines.Add('        .and_then(|v| v.as_i64())');
  Lines.Add('        .ok_or_else(|| HttpCallError::with_code(');
  Lines.Add('            "Response has no integer ''code'' field", -4, status))?;');
  Lines.Add('    if code != 0 {');
  Lines.Add('        let message = parsed.get("error")');
  Lines.Add('            .and_then(|v| v.as_str())');
  Lines.Add('            .unwrap_or("Remote call failed");');
  Lines.Add('        return Err(HttpCallError::with_code(');
  Lines.Add('            message, code as i32, status));');
  Lines.Add('    }');
  Lines.Add('    Ok(parsed.get("result").cloned().unwrap_or(Value::Null))');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Synchronous call (uses `ureq`, no async runtime required).');
  Lines.Add('fn call_api_sync(api_name: &str, args: Vec<Value>) -> Result<Value, HttpCallError> {');
  Lines.Add('    let url = url_for(api_name);');
  Lines.Add('    let body = json!({ "args": args }).to_string();');
  Lines.Add('');
  Lines.Add('    if get_debug_log() {');
  Lines.Add('        eprintln!("[http-json-sync] POST {} body={}", url, body);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    let resp = ureq::post(&url)');
  Lines.Add('        .timeout(Duration::from_secs(effective_timeout_secs()))');
  Lines.Add('        .set("Content-Type", "application/json; charset=utf-8")');
  Lines.Add('        .send_string(&body);');
  Lines.Add('');
  Lines.Add('    let (status, text) = match resp {');
  Lines.Add('        Ok(response) => {');
  Lines.Add('            let status = response.status() as i32;');
  Lines.Add('            let text = response.into_string().map_err(|e| {');
  Lines.Add('                HttpCallError::with_code(');
  Lines.Add('                    &format!("Failed to read response body: {}", e),');
  Lines.Add('                    -1, status)');
  Lines.Add('            })?;');
  Lines.Add('            (status, text)');
  Lines.Add('        }');
  Lines.Add('        Err(ureq::Error::Status(status, response)) => {');
  Lines.Add('            let text = response.into_string().unwrap_or_default();');
  Lines.Add('            (status as i32, text)');
  Lines.Add('        }');
  Lines.Add('        Err(ureq::Error::Transport(transport)) => {');
  Lines.Add('            return Err(HttpCallError::with_code(');
  Lines.Add('                &format!("Network error: {}", transport), -1, 0));');
  Lines.Add('        }');
  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    if get_debug_log() {');
  Lines.Add('        eprintln!("[http-json-sync] response {}: {}", status, text);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    parse_envelope(status, &text)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('/// Asynchronous call (uses `reqwest` + `tokio`).');
  Lines.Add('///');
  Lines.Add('/// Must be awaited inside a tokio runtime. The most common form');
  Lines.Add('/// is `#[tokio::main] async fn main()`.');
  Lines.Add('async fn call_api_async(api_name: &str, args: Vec<Value>) -> Result<Value, HttpCallError> {');
  Lines.Add('    let url = url_for(api_name);');
  Lines.Add('    let body = json!({ "args": args }).to_string();');
  Lines.Add('');
  Lines.Add('    if get_debug_log() {');
  Lines.Add('        eprintln!("[http-json-async] POST {} body={}", url, body);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    let client = reqwest::Client::builder()');
  Lines.Add('        .timeout(Duration::from_secs(effective_timeout_secs()))');
  Lines.Add('        .build()');
  Lines.Add('        .map_err(|e| HttpCallError::with_code(');
  Lines.Add('            &format!("Failed to create HTTP client: {}", e), -1, 0))?;');
  Lines.Add('');
  Lines.Add('    let resp = client.post(&url)');
  Lines.Add('        .header("Content-Type", "application/json; charset=utf-8")');
  Lines.Add('        .body(body)');
  Lines.Add('        .send()');
  Lines.Add('        .await');
  Lines.Add('        .map_err(|e| HttpCallError::with_code(');
  Lines.Add('            &format!("Network error: {}", e), -1, 0))?;');
  Lines.Add('');
  Lines.Add('    let status = resp.status().as_u16() as i32;');
  Lines.Add('    let text = resp.text().await.map_err(|e| HttpCallError::with_code(');
  Lines.Add('        &format!("Failed to read response body: {}", e), -1, status))?;');
  Lines.Add('');
  Lines.Add('    if get_debug_log() {');
  Lines.Add('        eprintln!("[http-json-async] response {}: {}", status, text);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    parse_envelope(status, &text)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitRustFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, ArgInit, Description, ReturnType: TP_String;
  HasParams: boolean;
  ExtractSync, ExtractAsync: TP_String;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Typed API functions');
  Lines.Add('//');
  Lines.Add('// Every routine has TWO functions:');
  Lines.Add('//   * `pub fn <ApiName>(...)`            - synchronous');
  Lines.Add('//   * `pub async fn <ApiName>_async(...)` - asynchronous');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildRustParamDecl(F.Params);
    ArgInit := BuildRustArgVecInit(F.Params);
    HasParams := Length(F.Params) > 0;

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    if F.IsFunction then
      ReturnType := 'Result<' + ABI_Type_To_Rust_Return(F.ReturnType) + ', HttpCallError>'
    else
      ReturnType := 'Result<(), HttpCallError>';

    // ---- Synchronous variant ----------------------------------------------
    Lines.Add('/// ' + Description.Text);
    Lines.Add('///');
    Lines.Add('/// HTTP route: `POST /' + ApiName.Text + '` (relative to the base URL).');
    Lines.Add('/// This variant blocks the calling thread.');
    if F.IsFunction then
      Lines.Add('/// Returns: the remote result ('
        + ABI_Type_To_Rust_Return(F.ReturnType).Text + ').')
    else
      Lines.Add('/// Returns: `Ok(())` on success.');
    Lines.Add('/// Errors: `HttpCallError` on any failure.');
    Lines.Add('#[allow(non_snake_case)]');
    if HasParams then
      Lines.Add('pub fn ' + ApiName.Text + '(' + ParamDecl.Text + ') -> ' + ReturnType.Text + ' {')
    else
      Lines.Add('pub fn ' + ApiName.Text + '() -> ' + ReturnType.Text + ' {');
    Lines.Add('    let value = call_api_sync(' + RustStrLit(ApiName).Text + ', ' + ArgInit.Text + ')?;');

    if F.IsFunction then
    begin
      ExtractSync := ABI_Type_To_Rust_ResultExtract(F.ReturnType, 'value');
      Lines.Add('    ' + ExtractSync.Text);
    end
    else
    begin
      Lines.Add('    let _ = value;');
      Lines.Add('    Ok(())');
    end;
    Lines.Add('}');
    Lines.Add('');

    // ---- Asynchronous variant ---------------------------------------------
    Lines.Add('/// ' + Description.Text + ' (asynchronous)');
    Lines.Add('///');
    Lines.Add('/// HTTP route: `POST /' + ApiName.Text + '` (relative to the base URL).');
    Lines.Add('/// Must be awaited inside a tokio runtime.');
    if F.IsFunction then
      Lines.Add('/// Resolves with: the remote result ('
        + ABI_Type_To_Rust_Return(F.ReturnType).Text + ').')
    else
      Lines.Add('/// Resolves with: `()`.');
    Lines.Add('/// Rejects with: `HttpCallError` on any failure.');
    Lines.Add('#[allow(non_snake_case)]');
    if HasParams then
      Lines.Add('pub async fn ' + ApiName.Text + '_async(' + ParamDecl.Text + ') -> ' + ReturnType.Text + ' {')
    else
      Lines.Add('pub async fn ' + ApiName.Text + '_async() -> ' + ReturnType.Text + ' {');
    Lines.Add('    let value = call_api_async(' + RustStrLit(ApiName).Text + ', ' + ArgInit.Text + ').await?;');

    if F.IsFunction then
    begin
      ExtractAsync := ABI_Type_To_Rust_ResultExtract(F.ReturnType, 'value');
      Lines.Add('    ' + ExtractAsync.Text);
    end
    else
    begin
      Lines.Add('    let _ = value;');
      Lines.Add('    Ok(())');
    end;
    Lines.Add('}');
    Lines.Add('');
  end;
end;

function GenerateHTTPCallRustCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallRustCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallRustCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Rust call module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitRustHeader(Lines, UnitName);
    EmitRustConfig(Lines, BaseUrl);
    EmitRustError(Lines);
    EmitRustTransport(Lines);
    EmitRustFunctions(Lines, SupportedFuncs, ApiNames);

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
    'rust', 'Rust HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_rs.rs', False,
    @GenerateHTTPCallRustCode);
end.
