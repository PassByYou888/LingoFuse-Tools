unit http_R_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallRCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_R_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_R_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_R_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := 'character'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then Result := 'numeric'
  else Result := '';
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
    if c = '|' then Result.Append('\|')
    else if c = #10 then Result.Append(' ')
    else if c = #13 then { skip }
    else Result.Append(c);
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
      Line := StripCommentMarkers(Line);
      if Line.Len > 0 then
      begin
        if Line[1] = '@' then { skip }
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
// Parameter builders
// ---------------------------------------------------------------------------

function BuildRParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRIdent(Params[i].Name, i);
    if i > 0 then Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildRCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRIdent(Params[i].Name, i);
    if i > 0 then Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildRArgListExpr(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := 'list()';
    Exit;
  end;
  Result := 'list(';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRIdent(Params[i].Name, i);
    if i > 0 then Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ')';
end;

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
    if i > 0 then ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;
  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
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
// R SOURCE GENERATOR
// ===========================================================================
//
// [FIX-A] .lfb_bridge_call now passes a JSON STRING to lf_call().
//         The DataHandle path was a line-for-line copy of the C++ bridge
//         client and is wrong for the R binding: lingofuse::lf_call
//         takes (app_name, api_name, payload_string, timeout_ms).
//
// [FIX-C] Every *_async function now checks future::plan() and refuses
//         multisession / multicore. The LingoFuse runtime is not
//         initialized in forked workers, so those plans would always
//         fail at runtime. A clear error at dispatch time is better
//         than a confusing "runtime not loaded" failure inside the
//         future.

function GenerateHTTPCallRCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, RIdent, ParamList, ArgExpr, RetType: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  Description: TP_String;
  HasParams: boolean;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallRCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallRCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

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
    Lines.Add('# Auto-generated by http_R_abi_call_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Call-side R wrapper for the LingoFuse HTTP/JSON service.');
    Lines.Add('#');
    Lines.Add('# ARCHITECTURE');
    Lines.Add('# ------------');
    Lines.Add('# This wrapper calls the LingoFuse HTTP bridge through the same');
    Lines.Add('# LF_Call path that the C++ and Pascal wrappers use. It does');
    Lines.Add('# NOT speak HTTP to the bridge; bridge.py is a LingoFuse App,');
    Lines.Add('# not an HTTP server.');
    Lines.Add('#');
    Lines.Add('#     R wrapper --LF_Call("__lf_http_bridge__")--> bridge.py');
    Lines.Add('#                                                     |');
    Lines.Add('#                                                     | HTTP POST');
    Lines.Add('#                                                     v');
    Lines.Add('#                                                HTTP ingress');
    Lines.Add('#                                                     |');
    Lines.Add('#                                                     | LF_Call');
    Lines.Add('#                                                     v');
    Lines.Add('#                                              service (LF App)');
    Lines.Add('#');
    Lines.Add('# IMPORTANT: the payload passed to lingofuse::lf_call() is a');
    Lines.Add('# length-1 character string (the JSON-encoded bridge request');
    Lines.Add('# envelope), NOT a DataHandle. The C ABI uses data handles;');
    Lines.Add('# the R binding hides that detail. Do NOT translate the C++');
    Lines.Add('# lf_http_bridge_client.hpp line-for-line.');
    Lines.Add('#');
    Lines.Add('# REQUIRED R PACKAGES');
    Lines.Add('# -------------------');
    Lines.Add('#   - lingofuse   (LingoFuse binding)');
    Lines.Add('#   - jsonlite    (JSON)');
    Lines.Add('#   - future      (only for *_async)');
    Lines.Add('#');
    Lines.Add('# Install with:');
    Lines.Add('#   install.packages(c("jsonlite", "future"))');
    Lines.Add('#   # lingofuse comes from the LingoFuse distribution:');
    Lines.Add('#   #   R CMD INSTALL /path/to/lingofuse');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Configuration
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Configuration');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('# HTTP URL prefix of the target service, as seen by bridge.py');
    Lines.Add('# when it performs its outbound HTTP POST. Default assumes');
    Lines.Add('# bridge.py is listening on 127.0.0.1:8081 and its HTTP ingress');
    Lines.Add('# routes /<App>/<Api> to the matching LingoFuse App.');
    Lines.Add('HTTP_CALL_BASE_URL <- ' + RStrLit(BaseUrl) + ';');
    Lines.Add('');
    Lines.Add('# LingoFuse App name of the bridge. This is the LF App that the');
    Lines.Add('# wrapper calls via LF_Call; it is NOT the target service App.');
    Lines.Add('HTTP_BRIDGE_APP_NAME <- "__lf_http_bridge__";');
    Lines.Add('');
    Lines.Add('# LingoFuse API name of the bridge outbound proxy.');
    Lines.Add('HTTP_BRIDGE_API_NAME <- "__lf_outbound_post__";');
    Lines.Add('');
    Lines.Add('# Total time budget for the whole round trip (LF_Call), in ms.');
    Lines.Add('# Must be larger than HTTP_CALL_DEFAULT_TIMEOUT_S * 1000.');
    Lines.Add('HTTP_CALL_TIMEOUT_MS <- 60000L;');
    Lines.Add('');
    Lines.Add('# Outbound HTTP timeout, in seconds, carried inside the bridge');
    Lines.Add('# request envelope. Must be smaller than HTTP_CALL_TIMEOUT_MS.');
    Lines.Add('HTTP_CALL_DEFAULT_TIMEOUT_S <- 25.0;');
    Lines.Add('');
    Lines.Add('# LingoFuse endpoint the client connects to. This must be the');
    Lines.Add('# same endpoint that both the bridge and the service use.');
    Lines.Add('LF_CLIENT_ENDPOINT <- ' + RStrLit('ipc:' + NormalizedUnit + '_http_json') + ';');
    Lines.Add('');
    Lines.Add('# Directory containing the LingoFuse native runtime (LingoFuse64.dll');
    Lines.Add('# or liblingofuse.so). NULL means "use getwd()".');
    Lines.Add('LF_CLIENT_RUNTIME_DIR <- NULL;');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Error type
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Error type');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('# Raised by every sync function on failure.');
    Lines.Add('# Fields:');
    Lines.Add('#   message      human-readable description');
    Lines.Add('#   code         -1 transport, -2 request-shape, -4 protocol,');
    Lines.Add('#                or a service-defined error code');
    Lines.Add('#   http_status  0 for transport errors, 200 for service errors');
    Lines.Add('http_call_error <- function(message, code = -1L, http_status = 0L) {');
    Lines.Add('  structure(');
    Lines.Add('    class = c("http_call_error", "error", "condition"),');
    Lines.Add('    list(');
    Lines.Add('      message     = message,');
    Lines.Add('      call        = NULL,');
    Lines.Add('      code        = as.integer(code),');
    Lines.Add('      http_status = as.integer(http_status)');
    Lines.Add('    )');
    Lines.Add('  )');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // LingoFuse client lifecycle
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# LingoFuse client lifecycle');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('# The wrapper uses an environment to hold mutable state. This');
    Lines.Add('# avoids the `<<-` operator and keeps the public functions pure.');
    Lines.Add('.lf_client_state <- new.env(parent = emptyenv());');
    Lines.Add('.lf_client_state$initialized <- FALSE;');
    Lines.Add('');
    Lines.Add('# lf_http_client_init - load the LingoFuse runtime and connect');
    Lines.Add('# to the LF endpoint. Idempotent; safe to call multiple times.');
    Lines.Add('lf_http_client_init <- function(runtime_dir = NULL, endpoint = NULL) {');
    Lines.Add('  if (isTRUE(.lf_client_state$initialized)) return(invisible(NULL));');
    Lines.Add('');
    Lines.Add('  if (!requireNamespace("lingofuse", quietly = TRUE)) {');
    Lines.Add('    stop("Package ''lingofuse'' is required. ",');
    Lines.Add('         "Install it from the LingoFuse distribution ",');
    Lines.Add('         "with R CMD INSTALL.")');
    Lines.Add('  }');
    Lines.Add('  if (!requireNamespace("jsonlite", quietly = TRUE)) {');
    Lines.Add('    stop("Package ''jsonlite'' is required. ",');
    Lines.Add('         "Install with install.packages(''jsonlite'').")');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  if (is.null(runtime_dir)) {');
    Lines.Add('    runtime_dir <- if (is.null(LF_CLIENT_RUNTIME_DIR)) getwd()');
    Lines.Add('                   else LF_CLIENT_RUNTIME_DIR');
    Lines.Add('  }');
    Lines.Add('  if (is.null(endpoint)) endpoint <- LF_CLIENT_ENDPOINT');
    Lines.Add('');
    Lines.Add('  lingofuse::lf_load(runtime_dir = runtime_dir)');
    Lines.Add('  lingofuse::lf_prepare_client(endpoint, NULL)');
    Lines.Add('  lingofuse::lf_prepare_done()');
    Lines.Add('  .lf_client_state$initialized <- TRUE');
    Lines.Add('  invisible(NULL)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('# lf_http_client_shutdown - shut down the LingoFuse runtime.');
    Lines.Add('# Idempotent; safe to call multiple times.');
    Lines.Add('lf_http_client_shutdown <- function() {');
    Lines.Add('  if (!isTRUE(.lf_client_state$initialized)) return(invisible(NULL));');
    Lines.Add('  tryCatch(lingofuse::lf_exit_main_thread(), error = function(e) NULL)');
    Lines.Add('  tryCatch(lingofuse::lf_shutdown(),         error = function(e) NULL)');
    Lines.Add('  .lf_client_state$initialized <- FALSE');
    Lines.Add('  invisible(NULL)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // [FIX-A] Internal transport: string payload, no DataHandle
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Internal transport');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('# .lfb_bridge_call - build the bridge request envelope, LF_Call the');
    Lines.Add('# bridge with a JSON string payload, parse the response envelope,');
    Lines.Add('# and return the service body.');
    Lines.Add('#');
    Lines.Add('# The envelope layout matches lf_http_bridge_client.hpp:');
    Lines.Add('#   { "url": "...", "method": "POST",');
    Lines.Add('#     "body": {...}, "timeout": N }');
    Lines.Add('#');
    Lines.Add('# The response envelope from bridge.py looks like:');
    Lines.Add('#   { "status_code": 200, "headers": {...}, "body": {...} }');
    Lines.Add('#');
    Lines.Add('# The service body itself is:');
    Lines.Add('#   { "code": 0, "result": ... }     on success');
    Lines.Add('#   { "code": N, "error":  ... }     on failure');
    Lines.Add('#');
    Lines.Add('# IMPORTANT: lingofuse::lf_call(app_name, api_name, payload,');
    Lines.Add('# timeout_ms) takes a STRING payload. The C ABI uses data handles');
    Lines.Add('# but the R binding hides that. Do NOT create a DataHandle here.');
    Lines.Add('#');
    Lines.Add('# On any failure, raises http_call_error.');
    Lines.Add('.lfb_bridge_call <- function(bridge_app, bridge_api, url, method,');
    Lines.Add('                              request_body, http_timeout_s,');
    Lines.Add('                              call_timeout_ms) {');
    Lines.Add('  if (!isTRUE(.lf_client_state$initialized)) {');
    Lines.Add('    lf_http_client_init()');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  if (is.null(url) || nchar(url) == 0L) {');
    Lines.Add('    stop(http_call_error("empty url", code = -2L));');
    Lines.Add('  }');
    Lines.Add('  if (is.null(method) || nchar(method) == 0L) method <- "POST"');
    Lines.Add('  if (is.null(http_timeout_s) || http_timeout_s <= 0) {');
    Lines.Add('    http_timeout_s <- HTTP_CALL_DEFAULT_TIMEOUT_S');
    Lines.Add('  }');
    Lines.Add('  if (is.null(call_timeout_ms) || call_timeout_ms <= 0) {');
    Lines.Add('    call_timeout_ms <- HTTP_CALL_TIMEOUT_MS');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  # Build the bridge request envelope.');
    Lines.Add('  req <- list(');
    Lines.Add('    url     = url,');
    Lines.Add('    method  = method,');
    Lines.Add('    timeout = as.integer(round(http_timeout_s))');
    Lines.Add('  )');
    Lines.Add('  if (!is.null(request_body)) req$body <- request_body');
    Lines.Add('');
    Lines.Add('  payload <- tryCatch(');
    Lines.Add('    jsonlite::toJSON(req, auto_unbox = TRUE),');
    Lines.Add('    error = function(e) {');
    Lines.Add('      stop(http_call_error(');
    Lines.Add('        paste0("failed to serialize bridge request: ",');
    Lines.Add('               conditionMessage(e)),');
    Lines.Add('        code = -2L');
    Lines.Add('      ))');
    Lines.Add('    }');
    Lines.Add('  )');
    Lines.Add('');
    Lines.Add('  # LF_Call the bridge. The payload is a JSON string; the R');
    Lines.Add('  # binding handles transport encoding internally.');
    Lines.Add('  resp_str <- tryCatch(');
    Lines.Add('    lingofuse::lf_call(bridge_app, bridge_api,');
    Lines.Add('                       as.character(payload),');
    Lines.Add('                       as.integer(call_timeout_ms)),');
    Lines.Add('    error = function(e) {');
    Lines.Add('      stop(http_call_error(');
    Lines.Add('        paste0("LF_Call to bridge failed: ", conditionMessage(e)),');
    Lines.Add('        code = -1L');
    Lines.Add('      ))');
    Lines.Add('    }');
    Lines.Add('  )');
    Lines.Add('  if (is.null(resp_str) || !is.character(resp_str) ||');
    Lines.Add('      length(resp_str) != 1L || nchar(resp_str) == 0L) {');
    Lines.Add('    stop(http_call_error(');
    Lines.Add('      "bridge returned an empty response",');
    Lines.Add('      code = -1L');
    Lines.Add('    ))');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  envelope <- tryCatch(');
    Lines.Add('    jsonlite::fromJSON(resp_str, simplifyVector = FALSE),');
    Lines.Add('    error = function(e) NULL');
    Lines.Add('  );');
    Lines.Add('  if (is.null(envelope)) {');
    Lines.Add('    stop(http_call_error(');
    Lines.Add('      paste0("invalid bridge response JSON: ", resp_str),');
    Lines.Add('      code = -4L');
    Lines.Add('    ))');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  if (!is.null(envelope$error)) {');
    Lines.Add('    stop(http_call_error(');
    Lines.Add('      paste0("bridge error: ", as.character(envelope$error)),');
    Lines.Add('      code = -1L');
    Lines.Add('    ))');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  if (is.null(envelope$body)) {');
    Lines.Add('    stop(http_call_error(');
    Lines.Add('      "bridge envelope has no body field",');
    Lines.Add('      code = -4L');
    Lines.Add('    ))');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  body <- envelope$body');
    Lines.Add('  if (is.null(body$code)) {');
    Lines.Add('    stop(http_call_error(');
    Lines.Add('      "service response has no code field",');
    Lines.Add('      code = -4L');
    Lines.Add('    ))');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  code <- as.integer(body$code)');
    Lines.Add('  if (code != 0L) {');
    Lines.Add('    msg <- if (!is.null(body$error)) as.character(body$error)');
    Lines.Add('           else "unknown service error"');
    Lines.Add('    stop(http_call_error(msg, code = code, http_status = 200L));');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  return(body)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // -----------------------------------------------------------------------
    // Sync API
    // -----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Synchronous typed call functions');
    Lines.Add('#');
    Lines.Add('# Each function blocks until the bridge returns a response. On');
    Lines.Add('# failure it raises http_call_error.');
    Lines.Add('# ============================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      RIdent := MakeSafeRIdent(ApiName, i);
      ParamList := BuildRParamList(F.Params);
      ArgExpr := BuildRArgListExpr(F.Params);
      HasParams := Length(F.Params) > 0;

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;

      Lines.Add('# ' + Description.Text);
      Lines.Add('# Original declaration: ' + BuildFullDecl(F));
      Lines.Add('# Bridge route: ' + NormalizedUnit.Text + '/' + ApiName.Text);
      Lines.Add(RIdent + ' <- function(' + ParamList + ') {');
      Lines.Add('  body <- .lfb_bridge_call(');
      Lines.Add('    bridge_app      = HTTP_BRIDGE_APP_NAME,');
      Lines.Add('    bridge_api      = HTTP_BRIDGE_API_NAME,');
      Lines.Add('    url             = paste0(HTTP_CALL_BASE_URL, "/' + ApiName + '"),');
      Lines.Add('    method          = "POST",');
      Lines.Add('    request_body    = list(args = ' + ArgExpr + '),');
      Lines.Add('    http_timeout_s  = HTTP_CALL_DEFAULT_TIMEOUT_S,');
      Lines.Add('    call_timeout_ms = HTTP_CALL_TIMEOUT_MS');
      Lines.Add('  )');
      if F.IsFunction then
        Lines.Add('  return(body$result)')
      else
        Lines.Add('  invisible(body)');
      Lines.Add('}');
      Lines.Add('');
    end;

    // -----------------------------------------------------------------------
    // Async API
    // -----------------------------------------------------------------------
    Lines.Add('');
    Lines.Add('# ============================================================================');
    Lines.Add('# Asynchronous typed call functions');
    Lines.Add('#');
    Lines.Add('# Each *_async variant returns a future::Future. Reading the');
    Lines.Add('# future with future::value(fut) blocks until the call completes.');
    Lines.Add('#');
    Lines.Add('# IMPORTANT: the *_async variants require future::plan("sequential")');
    Lines.Add('# (the default). The LingoFuse runtime is NOT initialized in forked');
    Lines.Add('# workers (multisession / multicore), so those plans would always');
    Lines.Add('# fail at runtime. Each *_async function checks the active plan and');
    Lines.Add('# raises a clear error if it is incompatible.');
    Lines.Add('# ============================================================================');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      RIdent := MakeSafeRIdent(ApiName, i);
      ParamList := BuildRParamList(F.Params);
      if ParamList <> '' then ParamList := ParamList + ', ';

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;

      Lines.Add('# ' + Description.Text + ' (async)');
      Lines.Add(RIdent + '_async <- function(' + ParamList +
        'on_success = NULL, on_error = NULL) {');
      Lines.Add('  if (!requireNamespace("future", quietly = TRUE)) {');
      Lines.Add('    stop("Package ''future'' is required for async calls. ",');
      Lines.Add('         "Install with install.packages(''future'').")');
      Lines.Add('  }');
      // [FIX-C] Plan check
      Lines.Add('  # Reject plans that fork workers: the LingoFuse runtime is');
      Lines.Add('  # not initialized in the worker process, so the inner call');
      Lines.Add('  # would always fail with "runtime not loaded".');
      Lines.Add('  .p <- future::plan();');
      Lines.Add('  if (inherits(.p, "multisession") || inherits(.p, "multicore")) {');
      Lines.Add('    stop("The *_async variants require future::plan(''sequential''). ",');
      Lines.Add('         "The LingoFuse runtime is not initialized in forked workers. ",');
      Lines.Add('         "Either reset the plan with future::plan(future::sequential), ",');
      Lines.Add('         "or use the sync variant instead.")');
      Lines.Add('  }');
      Lines.Add('  # The signature intentionally mirrors the sync variant.');
      Lines.Add('  # on_success / on_error are accepted for symmetry with other');
      Lines.Add('  # language bindings but only fire when the future is realized.');
      Lines.Add('  future::future({');
      Lines.Add('    tryCatch({');
      Lines.Add('      result <- ' + RIdent + '(' + BuildRCallArgList(F.Params) + ')');
      Lines.Add('      if (!is.null(on_success)) on_success(result)');
      if F.IsFunction then
        Lines.Add('      result')
      else
        Lines.Add('      NULL');
      Lines.Add('    }, error = function(e) {');
      Lines.Add('      code <- if (!is.null(e$code)) as.integer(e$code) else -1L');
      Lines.Add('      if (!is.null(on_error)) {');
      Lines.Add('        on_error(conditionMessage(e), code)');
      Lines.Add('      }');
      Lines.Add('      NULL');
      Lines.Add('    })');
      Lines.Add('  })');
      Lines.Add('}');
      Lines.Add('');
    end;

    Lines.Add('');
    Lines.Add('# ============================================================================');
    Lines.Add('# End of file');
    Lines.Add('# ============================================================================');

    Result := Lines;
    Log(PFormat('Generated R call code: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'r', 'R HTTP/JSON call source',
    asCall, akCallCode,
    '_http_json_call.R', False,
    @GenerateHTTPCallRCode);
end.
