unit http_rust_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceRustTestCode - generate the service-side smoke
// test program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServiceRustTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallRustTestCode - generate the call-side end-to-end
// test program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPCallRustTestCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_rust_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_rust_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification (mirrors every HTTP/JSON generator)
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

// ABI_Type_To_Rust_Default_Literal - the default literal used inside
// the Rust test's call site. Strings use `""`, numbers use 0 / 0.0.
function ABI_Type_To_Rust_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := '()';
end;

// ABI_Type_To_Json_Default_Literal - default value embedded in the
// JSON request envelope used by the smoke test. Strings use "" and
// numbers use 0 / 0.0.
function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

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

// BuildRustDefaultArgList - "0, 0.0, \"\"" for a parameter list. Used
// when the call-side e2e test invokes each generated function.
function BuildRustDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + ABI_Type_To_Rust_Default_Literal(Params[i].PascalType);
  end;
end;

// BuildSmokeJsonBody - the JSON body used by the service smoke test.
// Returns '{}' when the routine has no parameters, otherwise
// '{"args": [<defaults>]}'.
function BuildSmokeJsonBody(const Params: TParamArray): TP_String;
var
  i: integer;
  inner: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := '{}';
    Exit;
  end;
  inner := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then inner := inner + ', ';
    inner := inner + ABI_Type_To_Json_Default_Literal(Params[i].PascalType);
  end;
  Result := '{"args": [' + inner + ']}';
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
// SERVICE-SIDE SMOKE TEST GENERATOR (LingoFuse mesh, no bridge)
// =============================================================================

function GenerateHTTPServiceRustTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint, ServiceFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, SmokeBody: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceRustTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceRustTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  ServiceFileName := NormalizedUnit + '_http_json_service_rs.rs';
  TestFileName := NormalizedUnit + '_http_json_service_main_test___.rs';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_rust_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service-side smoke test for the generated Rust LingoFuse service.');
    Lines.Add('//');
    Lines.Add('// What this program does:');
    Lines.Add('//');
    Lines.Add('//   1. Includes the generated service module via #[path].');
    Lines.Add('//   2. Spawns the service on a background thread.');
    Lines.Add('//   3. Waits for the LingoFuse mesh to become ready.');
    Lines.Add('//   4. Calls every exposed API through `framework::call(...)` and');
    Lines.Add('//      checks that the response envelope carries "code": 0.');
    Lines.Add('//   5. Prints a summary and exits with code 0 (all OK) or 1 (any');
    Lines.Add('//      failure).');
    Lines.Add('//');
    Lines.Add('// This test uses the LingoFuse mesh DIRECTLY. It does NOT need');
    Lines.Add('// bridge.py and it does NOT need the native LingoFuse shared');
    Lines.Add('// library to be any different from what the service itself needs.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * This file must sit next to ' + ServiceFileName.Text + ' (the');
    Lines.Add('//     generated service module). Both live in the same directory,');
    Lines.Add('//     normally src/.');
    Lines.Add('//   * Cargo.toml must include:');
    Lines.Add('//       lingofuse = { path = "../LingoFuse/rust" }');
    Lines.Add('//       serde_json = "1"');
    Lines.Add('//   * The native LingoFuse shared library must be on the loader');
    Lines.Add('//     search path (same requirement as the service itself).');
    Lines.Add('//');
    Lines.Add('// How to use:');
    Lines.Add('//   cargo new ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('//   cd ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('//   cargo add lingofuse --path ../LingoFuse/rust');
    Lines.Add('//   cargo add serde_json');
    Lines.Add('//   cp ../' + ServiceFileName.Text + ' src/');
    Lines.Add('//   cp ../' + TestFileName.Text + ' src/main.rs');
    Lines.Add('//   cargo run');
    Lines.Add('');
    Lines.Add('#![allow(non_snake_case)]');
    Lines.Add('#![allow(dead_code)]');
    Lines.Add('');
    Lines.Add('// Include the service module. The `#[path]` attribute is relative to');
    Lines.Add('// the directory that contains this file, which is why both files');
    Lines.Add('// must live under `src/`.');
    Lines.Add('#[path = "' + ServiceFileName.Text + '"]');
    Lines.Add('mod service;');
    Lines.Add('');
    Lines.Add('use std::time::Duration;');
    Lines.Add('');
    Lines.Add('use lingofuse::data_handle::DataHandle;');
    Lines.Add('use lingofuse::framework;');
    Lines.Add('use lingofuse::io;');
    Lines.Add('use serde_json::Value;');
    Lines.Add('');
    Lines.Add('const APP_NAME: &str = ' + RustStrLit(AppName).Text + ';');
    Lines.Add('const ENDPOINT: &str = ' + RustStrLit(Endpoint).Text + ';');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Helpers');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('/// Waits for the LingoFuse mesh to become ready, up to 5 seconds.');
    Lines.Add('fn wait_until_ready() -> bool {');
    Lines.Add('    for _ in 0..50 {');
    Lines.Add('        match framework::check_main_thread() {');
    Lines.Add('            Ok(true) => return true,');
    Lines.Add('            _ => std::thread::sleep(Duration::from_millis(100)),');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('    false');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('/// Calls one API through the LingoFuse mesh and returns the');
    Lines.Add('/// parsed envelope. On any transport-level failure, returns Err.');
    Lines.Add('fn call_via_mesh(api_name: &str, request_json: &str) -> Result<Value, String> {');
    Lines.Add('    // Build the input handle.');
    Lines.Add('    let mut param = DataHandle::new(api_name)');
    Lines.Add('        .map_err(|e| format!("create handle: {}", e))?;');
    Lines.Add('    let body: Value = serde_json::from_str(request_json)');
    Lines.Add('        .map_err(|e| format!("parse request: {}", e))?;');
    Lines.Add('    io::write_json(&mut param, &body)');
    Lines.Add('        .map_err(|e| format!("write request: {}", e))?;');
    Lines.Add('    param.set_position(0)');
    Lines.Add('        .map_err(|e| format!("rewind request: {}", e))?;');
    Lines.Add('');
    Lines.Add('    // Call.');
    Lines.Add('    let mut resp = framework::call(APP_NAME, &param, 5000)');
    Lines.Add('        .map_err(|e| format!("call: {}", e))?;');
    Lines.Add('');
    Lines.Add('    // Empty response means the target never produced a result.');
    Lines.Add('    let size = resp.size().map_err(|e| format!("size: {}", e))?;');
    Lines.Add('    if size == 0 {');
    Lines.Add('        return Err("empty response (target unreachable or timed out)".to_string());');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // Parse the response envelope.');
    Lines.Add('    resp.set_position(0)');
    Lines.Add('        .map_err(|e| format!("rewind response: {}", e))?;');
    Lines.Add('    let parsed: Value = io::read_json(&mut resp)');
    Lines.Add('        .map_err(|e| format!("read response: {}", e))?;');
    Lines.Add('    Ok(parsed)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('/// Returns true when the envelope carries `"code": 0`.');
    Lines.Add('fn response_is_ok(resp: &Result<Value, String>) -> bool {');
    Lines.Add('    match resp {');
    Lines.Add('        Ok(v) => v.get("code").and_then(|c| c.as_i64()) == Some(0),');
    Lines.Add('        Err(_) => false,');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('/// Prints a one-line diagnostic for a non-OK response.');
    Lines.Add('fn print_diagnostic(api_name: &str, resp: &Result<Value, String>) {');
    Lines.Add('    match resp {');
    Lines.Add('        Err(msg) => eprintln!("    {}: {}", api_name, msg),');
    Lines.Add('        Ok(v) => {');
    Lines.Add('            let code = v.get("code").and_then(|c| c.as_i64()).unwrap_or(-999);');
    Lines.Add('            let err = v.get("error")');
    Lines.Add('                .and_then(|e| e.as_str())');
    Lines.Add('                .unwrap_or("<no error message>");');
    Lines.Add('            eprintln!("    {}: code={} error={}", api_name, code, err);');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Entry point');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('fn main() {');
    Lines.Add('    println!("=== {} LingoFuse service smoke test ===", APP_NAME);');
    Lines.Add('    println!("Endpoint : {}", ENDPOINT);');
    Lines.Add('    println!("API count: ' + MdInt(Length(SupportedFuncs)).Text + '");');
    Lines.Add('    println!();');
    Lines.Add('');
    Lines.Add('    // Step 1: spawn the service on a background thread.');
    Lines.Add('    println!("[test] spawning service on a background thread");');
    Lines.Add('    std::thread::spawn(|| service::main());');
    Lines.Add('');
    Lines.Add('    // Step 2: wait for the mesh.');
    Lines.Add('    if !wait_until_ready() {');
    Lines.Add('        eprintln!("[test] service did not become ready within 5 seconds");');
    Lines.Add('        std::process::exit(1);');
    Lines.Add('    }');
    Lines.Add('    println!("[test] mesh is ready");');
    Lines.Add('    println!();');
    Lines.Add('');
    Lines.Add('    let mut ok: i32 = 0;');
    Lines.Add('    let mut fail: i32 = 0;');
    Lines.Add('');

    // One test block per API.
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      SmokeBody := BuildSmokeJsonBody(F.Params);

      Lines.Add('    // ---- ' + ApiName.Text + ' ----');
      Lines.Add('    print!("  ' + ApiName.Text + ': ");');
      Lines.Add('    {');
      Lines.Add('        let r = call_via_mesh(' + RustStrLit(ApiName).Text + ', ' +
        RustStrLit(SmokeBody).Text + ');');
      Lines.Add('        if response_is_ok(&r) {');
      Lines.Add('            println!("OK");');
      Lines.Add('            ok += 1;');
      Lines.Add('        } else {');
      Lines.Add('            println!("FAILED");');
      Lines.Add('            print_diagnostic(' + RustStrLit(ApiName).Text + ', &r);');
      Lines.Add('            fail += 1;');
      Lines.Add('        }');
      Lines.Add('    }');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    println!("(no APIs to smoke-test)");');
      Lines.Add('');
    end;

    Lines.Add('    println!();');
    Lines.Add('    println!("=== Smoke test summary ===");');
    Lines.Add('    println!("Passed: {}", ok);');
    Lines.Add('    println!("Failed: {}", fail);');
    Lines.Add('');
    Lines.Add('    std::process::exit(if fail == 0 { 0 } else { 1 });');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated service smoke test: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// CALL-SIDE END-TO-END TEST GENERATOR (HTTP through bridge.py)
// =============================================================================

function GenerateHTTPCallRustTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, BaseUrl, CallFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, DefaultArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallRustTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallRustTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  CallFileName := NormalizedUnit + '_http_json_call_rs.rs';
  TestFileName := NormalizedUnit + '_http_json_call_main_test___.rs';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// Auto-generated by http_rust_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side end-to-end test for the generated Rust HTTP/JSON client.');
    Lines.Add('//');
    Lines.Add('// What this program does:');
    Lines.Add('//');
    Lines.Add('//   1. Includes the generated call module via #[path].');
    Lines.Add('//   2. For every exposed routine, exercises BOTH the synchronous');
    Lines.Add('//      variant and the asynchronous variant.');
    Lines.Add('//   3. Prints OK / FAILED per call and a summary at the end.');
    Lines.Add('//   4. Exits with code 0 (all OK) or 1 (any failure).');
    Lines.Add('//');
    Lines.Add('// This test goes through bridge.py. It requires:');
    Lines.Add('//   * a running bridge.py on the SAME endpoint as the service;');
    Lines.Add('//   * a running service (any language) registered on that endpoint.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * This file must sit next to ' + CallFileName.Text + ' (the');
    Lines.Add('//     generated call module). Both live in the same directory,');
    Lines.Add('//     normally src/.');
    Lines.Add('//   * Cargo.toml must include:');
    Lines.Add('//       ureq = "2"');
    Lines.Add('//       reqwest = { version = "0.12", features = ["json"] }');
    Lines.Add('//       tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }');
    Lines.Add('//       serde_json = "1"');
    Lines.Add('//');
    Lines.Add('// How to use:');
    Lines.Add('//   # Terminal 1: start bridge.py');
    Lines.Add('//   python3 bridge.py --endpoint ipc:' + NormalizedUnit.Text + '_http_json \\');
    Lines.Add('//       --port 8081 --no-precheck');
    Lines.Add('//');
    Lines.Add('//   # Terminal 2: start the service (any language) on the same endpoint');
    Lines.Add('//');
    Lines.Add('//   # Terminal 3: run the test');
    Lines.Add('//   cargo new ' + NormalizedUnit.Text + '_call_test');
    Lines.Add('//   cd ' + NormalizedUnit.Text + '_call_test');
    Lines.Add('//   cargo add ureq');
    Lines.Add('//   cargo add reqwest --features json');
    Lines.Add('//   cargo add tokio --features rt,rt-multi-thread,macros');
    Lines.Add('//   cargo add serde_json');
    Lines.Add('//   cp ../' + CallFileName.Text + ' src/');
    Lines.Add('//   cp ../' + TestFileName.Text + ' src/main.rs');
    Lines.Add('//   cargo run');
    Lines.Add('');
    Lines.Add('#![allow(non_snake_case)]');
    Lines.Add('#![allow(dead_code)]');
    Lines.Add('');
    Lines.Add('// Include the call module. The `#[path]` attribute is relative to');
    Lines.Add('// the directory that contains this file, which is why both files');
    Lines.Add('// must live under `src/`.');
    Lines.Add('#[path = "' + CallFileName.Text + '"]');
    Lines.Add('mod call;');
    Lines.Add('');
    Lines.Add('const APP_NAME: &str = ' + RustStrLit(AppName).Text + ';');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Main - sync pass
    // -------------------------------------------------------------------------
    Lines.Add('fn run_sync_pass(ok: &mut i32, fail: &mut i32) {');
    Lines.Add('    println!("--- Synchronous pass (ureq) ---");');
    Lines.Add('    println!();');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildRustDefaultArgList(F.Params);

      Lines.Add('    // ---- ' + ApiName.Text + ' [sync] ----');
      Lines.Add('    print!("  ' + ApiName.Text + ' [sync] : ");');
      Lines.Add('    match call::' + ApiName.Text + '(' + DefaultArgs.Text + ') {');
      Lines.Add('        Ok(_) => {');
      Lines.Add('            println!("OK");');
      Lines.Add('            *ok += 1;');
      Lines.Add('        }');
      Lines.Add('        Err(e) => {');
      Lines.Add('            println!("FAILED: {}", e);');
      Lines.Add('            *fail += 1;');
      Lines.Add('        }');
      Lines.Add('    }');
      Lines.Add('');
    end;

    Lines.Add('}');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Main - async pass
    // -------------------------------------------------------------------------
    Lines.Add('async fn run_async_pass(ok: &mut i32, fail: &mut i32) {');
    Lines.Add('    println!("--- Asynchronous pass (reqwest + tokio) ---");');
    Lines.Add('    println!();');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      DefaultArgs := BuildRustDefaultArgList(F.Params);

      Lines.Add('    // ---- ' + ApiName.Text + ' [async] ----');
      Lines.Add('    print!("  ' + ApiName.Text + ' [async]: ");');
      Lines.Add('    match call::' + ApiName.Text + '_async(' + DefaultArgs.Text + ').await {');
      Lines.Add('        Ok(_) => {');
      Lines.Add('            println!("OK");');
      Lines.Add('            *ok += 1;');
      Lines.Add('        }');
      Lines.Add('        Err(e) => {');
      Lines.Add('            println!("FAILED: {}", e);');
      Lines.Add('            *fail += 1;');
      Lines.Add('        }');
      Lines.Add('    }');
      Lines.Add('');
    end;

    Lines.Add('}');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Main entry point
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Entry point');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#[tokio::main]');
    Lines.Add('async fn main() {');
    Lines.Add('    println!("=== {} HTTP/JSON call test ===", APP_NAME);');
    Lines.Add('    println!("Base URL : {}", call::DEFAULT_BASE_URL);');
    Lines.Add('    println!("API count: ' + MdInt(Length(SupportedFuncs)).Text + '");');
    Lines.Add('    println!("Each API is tested twice (sync + async).");');
    Lines.Add('    println!();');
    Lines.Add('');
    Lines.Add('    let mut ok: i32 = 0;');
    Lines.Add('    let mut fail: i32 = 0;');
    Lines.Add('');
    Lines.Add('    // First pass: synchronous variant of every API.');
    Lines.Add('    run_sync_pass(&mut ok, &mut fail);');
    Lines.Add('');
    Lines.Add('    // Second pass: asynchronous variant of every API.');
    Lines.Add('    run_async_pass(&mut ok, &mut fail).await;');
    Lines.Add('');
    Lines.Add('    println!();');
    Lines.Add('    println!("=== Summary ===");');
    Lines.Add('    println!("Passed: {}", ok);');
    Lines.Add('    println!("Failed: {}", fail);');
    Lines.Add('');
    Lines.Add('    std::process::exit(if fail == 0 { 0 } else { 1 });');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated call e2e test: %d lines, %d routines (sync + async).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'rust', 'Rust HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.rs', False,
    @GenerateHTTPServiceRustTestCode);
  RegisterCodeGenEntry(
    'rust', 'Rust HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.rs', False,
    @GenerateHTTPCallRustTestCode);
end.
