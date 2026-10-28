unit http_R_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceRTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallRTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_R_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_R_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// ---------------------------------------------------------------------------
// ABI type classification
// ---------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string')
    or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended')
    or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal')
    or T.Same('longint') or T.Same('dword') or T.Same('word')
    or T.Same('smallint') or T.Same('byte') or T.Same('uint64')
    or T.Same('longword');
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

function ABI_Type_To_R_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else
    Result := '0';
end;

// ---------------------------------------------------------------------------
// Identifier helpers
// ---------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafeRIdent(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or (c = '.') or
       ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
       ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and
     (((Result[1] >= '0') and (Result[1] <= '9')) or (Result[1] = '_')) then
    Result := 'p' + Result;

  if Result.Same('if') or Result.Same('else') or Result.Same('repeat') or
     Result.Same('while') or Result.Same('function') or Result.Same('for') or
     Result.Same('next') or Result.Same('break') or Result.Same('TRUE') or
     Result.Same('FALSE') or Result.Same('NULL') or Result.Same('Inf') or
     Result.Same('NaN') or Result.Same('NA') or Result.Same('in') then
    Result := Result + '_';
end;

function UniqueName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while Used.IndexOf(Base + '_' + umlIntToStr(i).Text) >= 0 do
    Inc(i);
  Result := Base + '_' + umlIntToStr(i).Text;
end;

// RStrLit - emit a double-quoted R string literal.
function RStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #34;
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #34: Result.Append('\' + '"');
      #92: Result.Append('\' + '\');
      #10: Result.Append('\' + 'n');
      #13: Result.Append('\' + 'r');
      #9:  Result.Append('\' + 't');
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
  Result.Append(#34);
end;

// ---------------------------------------------------------------------------
// Markdown helpers
// ---------------------------------------------------------------------------

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
      // skip CR
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// ---------------------------------------------------------------------------
// Comment extraction
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Signature builders
// ---------------------------------------------------------------------------

function BuildFullDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeRIdent(F.Params[i].Name, i);
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

function BuildDefaultRArgList(const F: TFunctionStructure): TP_String;
var
  i: integer;
  lit: TP_String;
begin
  Result := '';
  for i := 0 to High(F.Params) do
  begin
    lit := ABI_Type_To_R_Default_Literal(F.Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + lit;
  end;
end;

// ---------------------------------------------------------------------------
// Supported-function filtering
// ---------------------------------------------------------------------------

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
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not ABI_Type_Is_Supported(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text]));
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

// ===========================================================================
// SERVICE-SIDE TEST DRIVER
// ===========================================================================
//
// [FIX-T1] The --direct mode has been removed. The native R service
//          does not open an HTTP port; the only way to reach it is
//          through bridge.py. The service driver therefore always
//          posts to http://127.0.0.1:8081/<Unit>/<Api>, which is
//          bridge.py's HTTP ingress.
//
// [FIX-T4] SERVICE_BASE_URL is now a straight assignment.
//
// [FIX-T6] The banner prints "Target: bridge HTTP ingress" instead
//          of the removed MODE_LABEL variable.
//
// [FIX-T7] All generated stop() calls use a single paste0() message.
//
// The driver exits 0 when every API returned code == 0, and 1
// otherwise.

function GenerateHTTPServiceRTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BridgeUrl, RFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  DefaultArgs: TP_String;
  HasParams: boolean;
  Description: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceRTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceRTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BridgeUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  RFileName := NormalizedUnit + '_http_json_service.R';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // -----------------------------------------------------------------------
    // File header
    // -----------------------------------------------------------------------
    Lines.Add('# Auto-generated by http_R_abi_test_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Service-side test driver for the R HTTP/JSON service.');
    Lines.Add('# Pairs with ' + RFileName.Text + '.');
    Lines.Add('#');
    Lines.Add('# WHAT THIS TESTS');
    Lines.Add('# ---------------');
    Lines.Add('# Each request is sent to bridge.py''s HTTP ingress:');
    Lines.Add('#');
    Lines.Add('#     ' + BridgeUrl.Text + '/<api>');
    Lines.Add('#');
    Lines.Add('# bridge.py then LF_Call''s the native R service on the');
    Lines.Add('# endpoint ipc:' + NormalizedUnit.Text + '_http_json, waits for the');
    Lines.Add('# service to reply, and returns the JSON to this driver.');
    Lines.Add('#');
    Lines.Add('# This driver therefore verifies:');
    Lines.Add('#     HTTP ingress -> LF_Call -> service -> response -> HTTP');
    Lines.Add('#');
    Lines.Add('# PREREQUISITES');
    Lines.Add('# -------------');
    Lines.Add('#   1. Native R service running:');
    Lines.Add('#          Rscript ' + RFileName.Text);
    Lines.Add('#   2. bridge.py running on the same LF endpoint:');
    Lines.Add('#          python bridge.py --endpoint ipc:' + NormalizedUnit.Text +
      '_http_json --port 8081 --no-precheck');
    Lines.Add('#');
    Lines.Add('# Each API is exercised with canonical default arguments:');
    Lines.Add('#   integer / int64 / cardinal / word / byte / uint64  -> 0');
    Lines.Add('#   double / single / extended / real                  -> 0');
    Lines.Add('#   string / PChar family                              -> empty string');
    Lines.Add('#');
    Lines.Add('# Exit code: 0 if all calls succeeded, 1 otherwise.');
    Lines.Add('#');
    Lines.Add('# Usage:');
    Lines.Add('#   Rscript ' + NormalizedUnit.Text + '_http_json_service_main_test___.R');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Configuration
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Configuration');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('SERVICE_BRIDGE_URL <- ' + RStrLit(BridgeUrl) + ';');
    Lines.Add('SERVICE_BASE_URL   <- SERVICE_BRIDGE_URL;');
    Lines.Add('SERVICE_TIMEOUT_S  <- 25.0;');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Dependencies
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Dependencies');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('if (!requireNamespace("httr", quietly = TRUE)) {');
    Lines.Add('  stop(paste0(');
    Lines.Add('    "Package '#39'httr'#39' is required. ",');
    Lines.Add('    "Install with install.packages('#39'httr'#39')."');
    Lines.Add('  ))');
    Lines.Add('}');
    Lines.Add('if (!requireNamespace("jsonlite", quietly = TRUE)) {');
    Lines.Add('  stop(paste0(');
    Lines.Add('    "Package '#39'jsonlite'#39' is required. ",');
    Lines.Add('    "Install with install.packages('#39'jsonlite'#39')."');
    Lines.Add('  ))');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Per-call harness
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Per-call harness');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.lfb_test_one <- function(api_name, arg_list) {');
    Lines.Add('  url <- paste0(SERVICE_BASE_URL, "/", api_name)');
    Lines.Add('  tryCatch({');
    Lines.Add('    resp <- httr::POST(');
    Lines.Add('      url    = url,');
    Lines.Add('      body   = jsonlite::toJSON(list(args = arg_list), auto_unbox = TRUE),');
    Lines.Add('      config = list(');
    Lines.Add('        httr::content_type_json(),');
    Lines.Add('        httr::timeout(SERVICE_TIMEOUT_S)');
    Lines.Add('      )');
    Lines.Add('    )');
    Lines.Add('    status <- httr::status_code(resp)');
    Lines.Add('    if (status >= 400) {');
    Lines.Add('      text <- httr::content(resp, "text", encoding = "UTF-8")');
    Lines.Add('      return(list(ok = FALSE,');
    Lines.Add('                  message = paste0("HTTP ", status, ": ", text)))');
    Lines.Add('    }');
    Lines.Add('    body <- jsonlite::fromJSON(');
    Lines.Add('      httr::content(resp, "text", encoding = "UTF-8"),');
    Lines.Add('      simplifyVector = FALSE');
    Lines.Add('    )');
    Lines.Add('    if (is.null(body$code)) {');
    Lines.Add('      return(list(ok = FALSE, message = "missing code field"))');
    Lines.Add('    }');
    Lines.Add('    if (body$code != 0) {');
    Lines.Add('      msg <- if (!is.null(body$error)) body$error else "unknown service error"');
    Lines.Add('      return(list(ok = FALSE,');
    Lines.Add('                  message = paste0("code=", body$code, " ", msg)))');
    Lines.Add('    }');
    Lines.Add('    return(list(ok = TRUE, message = "OK"))');
    Lines.Add('  }, error = function(e) {');
    Lines.Add('    return(list(ok = FALSE, message = conditionMessage(e)))');
    Lines.Add('  })');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Test driver
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Test driver');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.lfb_run <- function() {');
    Lines.Add('  cat("=== ' + NormalizedUnit + ' HTTP/JSON service test ===\n")');
    Lines.Add('  cat("Target: bridge HTTP ingress\n")');
    Lines.Add('  cat("Base URL: ", SERVICE_BASE_URL, "\n", sep = "")');
    Lines.Add('  cat("API count: ' + MdInt(Length(SupportedFuncs)) + '", "\n")');
    Lines.Add('  cat("\n")');
    Lines.Add('');
    Lines.Add('  pass <- 0L');
    Lines.Add('  fail <- 0L');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('  cat("  (no APIs to test)\n")');
    end
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        DefaultArgs := BuildDefaultRArgList(F);
        HasParams := Length(F.Params) > 0;

        Description := GetFullDescription(F.Comment);
        if Description.Len = 0 then
          Description := ApiName;

        Lines.Add('  # ' + Description);
        if HasParams then
          Lines.Add('  r <- .lfb_test_one(' + RStrLit(ApiName) + ', list(' + DefaultArgs + '))')
        else
          Lines.Add('  r <- .lfb_test_one(' + RStrLit(ApiName) + ', list())');
        Lines.Add('  if (r$ok) {');
        Lines.Add('    cat("  ' + ApiName + ': OK\n")');
        Lines.Add('    pass <- pass + 1L');
        Lines.Add('  } else {');
        Lines.Add('    cat("  ' + ApiName + ': FAILED -", r$message, "\n")');
        Lines.Add('    fail <- fail + 1L');
        Lines.Add('  }');
        Lines.Add('');
      end;
    end;

    Lines.Add('  cat("\n")');
    Lines.Add('  cat("=== Summary ===\n")');
    Lines.Add('  cat("Passed:", pass, "\n")');
    Lines.Add('  cat("Failed:", fail, "\n")');
    Lines.Add('');
    Lines.Add('  if (fail == 0L) {');
    Lines.Add('    cat("All calls succeeded.\n")');
    Lines.Add('    quit(save = "no", status = 0)');
    Lines.Add('  } else {');
    Lines.Add('    cat(fail, "call(s) failed.\n")');
    Lines.Add('    quit(save = "no", status = 1)');
    Lines.Add('  }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('.lfb_run()');
    Lines.Add('');
    Lines.Add('# ============================================================================');
    Lines.Add('# End of file');
    Lines.Add('# ============================================================================');

    Result := Lines;
    Log(PFormat('Generated R service test driver: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// ===========================================================================
// CALL-SIDE TEST DRIVER
// ===========================================================================
//
// The call driver loads the generated call wrapper and invokes every
// typed function with canonical default arguments. This exercises:
//
//   R wrapper -> LF_Call -> bridge __lf_outbound_post__ ->
//   HTTP ingress -> native R service -> response -> back
//
// [FIX-T5] The tryCatch handlers use fail <<- fail + 1L. This is
//          correct because the handlers are anonymous functions
//          whose enclosing environment is the .lfb_run frame, so
//          <<- updates the right counter. A comment now documents
//          this so future readers don't "fix" it away.
//
// Failures are reported through http_call_error (raised by the
// generated wrapper) and through any unexpected R error.

function GenerateHTTPCallRTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, CallFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  DefaultArgs: TP_String;
  RIdent: TP_String;
  HasParams: boolean;
  Description: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallRTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallRTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  CallFileName := NormalizedUnit + '_http_json_call.R';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // -----------------------------------------------------------------------
    // File header
    // -----------------------------------------------------------------------
    Lines.Add('# Auto-generated by http_R_abi_test_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Call-side test driver for the R HTTP/JSON call wrapper.');
    Lines.Add('# Pairs with ' + CallFileName.Text + '.');
    Lines.Add('#');
    Lines.Add('# WHAT THIS TESTS');
    Lines.Add('# ---------------');
    Lines.Add('# This driver loads the generated call wrapper and invokes');
    Lines.Add('# every typed function with canonical default arguments.');
    Lines.Add('# The full LingoFuse HTTP path is exercised:');
    Lines.Add('#');
    Lines.Add('#   R wrapper -> LF_Call -> bridge __lf_outbound_post__');
    Lines.Add('#             -> HTTP ingress -> native R service -> response');
    Lines.Add('#');
    Lines.Add('# PREREQUISITES');
    Lines.Add('# -------------');
    Lines.Add('#   1. Native R service running:');
    Lines.Add('#          Rscript ' + NormalizedUnit.Text + '_http_json_service.R');
    Lines.Add('#   2. bridge.py running on the same LF endpoint:');
    Lines.Add('#          python bridge.py --endpoint ipc:' + NormalizedUnit.Text +
      '_http_json --port 8081 --no-precheck');
    Lines.Add('#');
    Lines.Add('# Exit code: 0 if all calls succeeded, 1 otherwise.');
    Lines.Add('#');
    Lines.Add('# Usage:');
    Lines.Add('#   Rscript ' + NormalizedUnit.Text + '_http_json_call_main_test___.R');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Dependencies
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Dependencies');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('if (!requireNamespace("jsonlite", quietly = TRUE)) {');
    Lines.Add('  stop(paste0(');
    Lines.Add('    "Package '#39'jsonlite'#39' is required. ",');
    Lines.Add('    "Install with install.packages('#39'jsonlite'#39')."');
    Lines.Add('  ))');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Locate and load the call wrapper
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Load the call wrapper');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('# The call wrapper file is expected to sit next to this test');
    Lines.Add('# driver. Resolve the driver''s own directory from commandArgs so');
    Lines.Add('# the lookup works regardless of the caller''s cwd.');
    Lines.Add('.lfb_test_dir <- tryCatch({');
    Lines.Add('  raw_args <- commandArgs(trailingOnly = FALSE)');
    Lines.Add('  m <- grep("^--file=", raw_args, value = TRUE)');
    Lines.Add('  if (length(m) > 0) {');
    Lines.Add('    dirname(normalizePath(sub("^--file=", "", m[1])))');
    Lines.Add('  } else {');
    Lines.Add('    getwd()');
    Lines.Add('  }');
    Lines.Add('}, error = function(e) getwd())');
    Lines.Add('');
    Lines.Add('.lfb_call_file <- file.path(.lfb_test_dir, ' + RStrLit(CallFileName) + ');');
    Lines.Add('if (!file.exists(.lfb_call_file)) {');
    Lines.Add('  stop(paste0("Call wrapper not found: ", .lfb_call_file))');
    Lines.Add('}');
    Lines.Add('source(.lfb_call_file)');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Test driver
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Test driver');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.lfb_run <- function() {');
    Lines.Add('  cat("=== ' + NormalizedUnit + ' HTTP/JSON call test ===\n")');
    Lines.Add('  cat("Base URL: ", HTTP_CALL_BASE_URL, "\n", sep = "")');
    Lines.Add('  cat("API count: ' + MdInt(Length(SupportedFuncs)) + '", "\n")');
    Lines.Add('  cat("\n")');
    Lines.Add('');
    Lines.Add('  pass <- 0L');
    Lines.Add('  fail <- 0L');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('  cat("  (no APIs to test)\n")');
    end
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        RIdent := MakeSafeRIdent(ApiName, i);
        DefaultArgs := BuildDefaultRArgList(F);
        HasParams := Length(F.Params) > 0;

        Description := GetFullDescription(F.Comment);
        if Description.Len = 0 then
          Description := ApiName;

        Lines.Add('  # ' + Description);
        Lines.Add('  tryCatch({');
        if F.IsFunction then
        begin
          if HasParams then
            Lines.Add('    result <- ' + RIdent + '(' + DefaultArgs + ')')
          else
            Lines.Add('    result <- ' + RIdent + '()');
        end
        else
        begin
          if HasParams then
            Lines.Add('    ' + RIdent + '(' + DefaultArgs + ')')
          else
            Lines.Add('    ' + RIdent + '()');
        end;
        Lines.Add('    cat("  ' + ApiName + ': OK\n")');
        Lines.Add('    pass <- pass + 1L');
        Lines.Add('  }, http_call_error = function(e) {');
        // [FIX-T5] <<- inside the handler updates the .lfb_run counter.
        Lines.Add('    # Handler is an anonymous function whose enclosing');
        Lines.Add('    # environment is the .lfb_run frame, so <<- updates');
        Lines.Add('    # the correct counter.');
        Lines.Add('    code <- if (!is.null(e$code)) e$code else -1L');
        Lines.Add('    cat("  ' + ApiName + ': FAILED -", conditionMessage(e),');
        Lines.Add('        "(code =", code, ")\n")');
        Lines.Add('    fail <<- fail + 1L');
        Lines.Add('  }, error = function(e) {');
        Lines.Add('    cat("  ' + ApiName + ': FAILED - unexpected:",');
        Lines.Add('        conditionMessage(e), "\n")');
        Lines.Add('    fail <<- fail + 1L');
        Lines.Add('  })');
        Lines.Add('');
      end;
    end;

    Lines.Add('  cat("\n")');
    Lines.Add('  cat("=== Summary ===\n")');
    Lines.Add('  cat("Passed:", pass, "\n")');
    Lines.Add('  cat("Failed:", fail, "\n")');
    Lines.Add('');
    Lines.Add('  if (fail == 0L) {');
    Lines.Add('    cat("All calls succeeded.\n")');
    Lines.Add('    quit(save = "no", status = 0)');
    Lines.Add('  } else {');
    Lines.Add('    cat(fail, "call(s) failed.\n")');
    Lines.Add('    quit(save = "no", status = 1)');
    Lines.Add('  }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('.lfb_run()');
    Lines.Add('');
    Lines.Add('# ============================================================================');
    Lines.Add('# End of file');
    Lines.Add('# ============================================================================');

    Result := Lines;
    Log(PFormat('Generated R call test driver: %d lines, %d routines.',
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
    'r', 'R HTTP/JSON service test driver',
    asBoth, akTestCode,
    '_http_json_service_main_test___.R', False,
    @GenerateHTTPServiceRTestCode);
  RegisterCodeGenEntry(
    'r', 'R HTTP/JSON call test driver',
    asBoth, akTestCode,
    '_http_json_call_main_test___.R', False,
    @GenerateHTTPCallRTestCode);
end.
