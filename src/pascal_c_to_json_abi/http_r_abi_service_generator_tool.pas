unit http_R_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceRCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPServiceRImplStub(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_R_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_R_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_R_Stub_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := '""' else Result := '0';
end;

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

function BuildRParamNameArray(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := 'character(0)';
    Exit;
  end;
  Result := 'c(';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRIdent(Params[i].Name, i);
    if i > 0 then Result := Result + ', ';
    Result := Result + RStrLit(n);
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
// NATIVE R SERVICE SOURCE GENERATOR
// ===========================================================================

function GenerateHTTPServiceRCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, Endpoint, RFileName, ImplFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, ParamNameArr, Description: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceRCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceRCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  RFileName := NormalizedUnit + '_http_json_service.R';
  ImplFileName := NormalizedUnit + '_http_json_service_impl.R';

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

    // ----------------------------------------------------------------------
    // File header
    // ----------------------------------------------------------------------
    Lines.Add('# Auto-generated by http_R_abi_service_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Native R LingoFuse service for ' + UnitName.Text + '.');
    Lines.Add('#');
    Lines.Add('# This file IS the LingoFuse service. It holds the endpoint');
    Lines.Add('# ' + RStrLit(Endpoint) + ' directly through the lingofuse R package.');
    Lines.Add('# It does NOT open any HTTP port. bridge.py is a separate');
    Lines.Add('# LingoFuse client + HTTP ingress.');
    Lines.Add('#');
    Lines.Add('# HOW TO STOP');
    Lines.Add('# -----------');
    Lines.Add('# Open a second PowerShell window and run:');
    Lines.Add('#     '''' > ''<script_dir>\service.exit''');
    Lines.Add('# Or press Ctrl+C in the service window. The service.exit method');
    Lines.Add('# is safe; Ctrl+C is a fallback and may leave the terminal in an');
    Lines.Add('# odd state on some systems.');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Configuration
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Configuration');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('APP_NAME       <- ' + RStrLit(NormalizedUnit) + ';');
    Lines.Add('APP_DESC       <- ' + RStrLit('R native service for ' + UnitName) + ';');
    Lines.Add('LF_ENDPOINT    <- ' + RStrLit(Endpoint) + ';');
    Lines.Add('# Set LF_RUNTIME_DIR to the directory that contains LingoFuse64.dll');
    Lines.Add('# (or liblingofuse.so). When NULL, the service probes the script');
    Lines.Add('# directory and the CWD for the standard runtime locations.');
    Lines.Add('LF_RUNTIME_DIR <- NULL;');
    Lines.Add('IMPL_FILE      <- ' + RStrLit(ImplFileName) + ';');
    Lines.Add('DEBUG_LOG      <- FALSE;');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Dependencies
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Dependencies');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('if (!requireNamespace("lingofuse", quietly = TRUE)) {');
    Lines.Add('  stop(paste0(');
    Lines.Add('    "Package ''lingofuse'' is required. ",');
    Lines.Add('    "Install it from the LingoFuse distribution with R CMD INSTALL."');
    Lines.Add('  ))');
    Lines.Add('}');
    Lines.Add('if (!requireNamespace("jsonlite", quietly = TRUE)) {');
    Lines.Add('  stop(paste0(');
    Lines.Add('    "Package ''jsonlite'' is required. ",');
    Lines.Add('    "Install it with install.packages(''jsonlite'')."');
    Lines.Add('  ))');
    Lines.Add('}');
    Lines.Add('suppressPackageStartupMessages(library(lingofuse))');
    Lines.Add('suppressPackageStartupMessages(library(jsonlite))');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Script directory
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Script directory');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.script_dir <- function() {');
    Lines.Add('  raw_args <- commandArgs(trailingOnly = FALSE)');
    Lines.Add('  m <- grep("^--file=", raw_args, value = TRUE)');
    Lines.Add('  if (length(m) > 0) {');
    Lines.Add('    return(dirname(normalizePath(sub("^--file=", "", m[1]))))');
    Lines.Add('  }');
    Lines.Add('  getwd()');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // [FIX-S14] .onUnload patch
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Patch lingofuse::.onUnload so it does not unload the bridge DLL');
    Lines.Add('#');
    Lines.Add('# The current lingofuse/R/zzz.R has an ordering bug: it sets');
    Lines.Add('# main_thread_started to FALSE before reading it, so ever_started');
    Lines.Add('# is always FALSE, so library.dynam.unload is always called. That');
    Lines.Add('# unload races with C4 worker threads and produces an access');
    Lines.Add('# violation (0xC0000005) on process exit.');
    Lines.Add('#');
    Lines.Add('# Patching the function here means the DLL is left mapped for the');
    Lines.Add('# whole process lifetime. The OS reclaims it at process exit');
    Lines.Add('# (TerminateProcess), which does not run any DLL detach code and');
    Lines.Add('# therefore cannot crash.');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.patch_onUnload <- function() {');
    Lines.Add('  tryCatch({');
    Lines.Add('    ns <- asNamespace("lingofuse");');
    Lines.Add('    if (!exists(".onUnload", envir = ns, inherits = FALSE)) {');
    Lines.Add('      return(invisible(NULL));');
    Lines.Add('    }');
    Lines.Add('    patched <- function(libpath) {');
    Lines.Add('      # Intentionally do NOT call library.dynam.unload.');
    Lines.Add('      invisible(NULL);');
    Lines.Add('    };');
    Lines.Add('    tryCatch(unlockBinding(".onUnload", ns), error = function(e) NULL);');
    Lines.Add('    assign(".onUnload", patched, envir = ns);');
    Lines.Add('    tryCatch(lockBinding(".onUnload", ns), error = function(e) NULL);');
    Lines.Add('    cat("[service] patched lingofuse::.onUnload (no DLL unload at exit)\n");');
    Lines.Add('  }, error = function(e) {');
    Lines.Add('    message("[service] warning: could not patch lingofuse::.onUnload: ",');
    Lines.Add('            conditionMessage(e));');
    Lines.Add('  });');
    Lines.Add('  invisible(NULL);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('.patch_onUnload();');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Runtime directory
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Runtime directory');
    Lines.Add('#');
    Lines.Add('# Resolution order:');
    Lines.Add('#   1. LF_RUNTIME_DIR, if it is set and non-empty.');
    Lines.Add('#   2. lingofuse::lf_find_runtime(), which consults');
    Lines.Add('#      LINGOFUSE_RUNTIME / lingofuse.runtime / relative probes.');
    Lines.Add('#   3. A relative probe of this script''s own directory and the CWD.');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.resolve_runtime_dir <- function() {');
    Lines.Add('  if (!is.null(LF_RUNTIME_DIR) && nzchar(LF_RUNTIME_DIR)) {');
    Lines.Add('    if (!dir.exists(LF_RUNTIME_DIR)) {');
    Lines.Add('      stop(paste0("LF_RUNTIME_DIR does not exist: ", LF_RUNTIME_DIR));');
    Lines.Add('    }');
    Lines.Add('    return(LF_RUNTIME_DIR);');
    Lines.Add('  }');
    Lines.Add('  fr <- tryCatch(lingofuse::lf_find_runtime(), error = function(e) NULL);');
    Lines.Add('  if (is.character(fr) && length(fr) == 1L && nzchar(fr) && dir.exists(fr)) {');
    Lines.Add('    return(fr);');
    Lines.Add('  }');
    Lines.Add('  bases <- unique(c(.script_dir(), getwd()));');
    Lines.Add('  relatives <- c(');
    Lines.Add('    ".", "Binary", "runtime", "runtime/Binary", "lib",');
    Lines.Add('    "../Binary", "../runtime", "../runtime/Binary",');
    Lines.Add('    "../../Binary", "../../runtime", "../../runtime/Binary",');
    Lines.Add('    "../../../Binary",');
    Lines.Add('    "libs", "libs/x64", "r/libs", "r/libs/x64",');
    Lines.Add('    "lingofuse/libs", "lingofuse/libs/x64"');
    Lines.Add('  );');
    Lines.Add('  dll_names <- c(');
    Lines.Add('    "LingoFuse64.dll", "LingoFuse32.dll",');
    Lines.Add('    "liblingofuse.so", "liblingofuse.dylib"');
    Lines.Add('  );');
    Lines.Add('  for (base in bases) {');
    Lines.Add('    for (dll in dll_names) {');
    Lines.Add('      if (file.exists(file.path(base, dll))) return(base);');
    Lines.Add('    }');
    Lines.Add('    for (rel in relatives) {');
    Lines.Add('      p <- file.path(base, rel);');
    Lines.Add('      if (!dir.exists(p)) next;');
    Lines.Add('      for (dll in dll_names) {');
    Lines.Add('        if (file.exists(file.path(p, dll))) return(p);');
    Lines.Add('      }');
    Lines.Add('    }');
    Lines.Add('  }');
    Lines.Add('  stop(paste0(');
    Lines.Add('    "Cannot locate the LingoFuse runtime. ",');
    Lines.Add('    "Set LF_RUNTIME_DIR to the directory that contains ",');
    Lines.Add('    "LingoFuse64.dll (or liblingofuse.so)."');
    Lines.Add('  ));');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Impl loading
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Impl loading');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.impl_path <- function() {');
    Lines.Add('  p <- IMPL_FILE;');
    Lines.Add('  if (!grepl("^([A-Za-z]:|/)", p)) {');
    Lines.Add('    p <- file.path(.script_dir(), p);');
    Lines.Add('  }');
    Lines.Add('  p;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('.impl_env <- new.env(parent = globalenv());');
    Lines.Add('');
    Lines.Add('.load_impl <- function() {');
    Lines.Add('  path <- .impl_path();');
    Lines.Add('  if (!file.exists(path)) {');
    Lines.Add('    stop(paste0("Implementation file not found: ", path));');
    Lines.Add('  }');
    Lines.Add('  sys.source(path, envir = .impl_env, keep.source = FALSE);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    Lines.Add('# ============================================================================');
    Lines.Add('# Missing-implementation error helper');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.stop_missing_impl <- function(api_name) {');
    Lines.Add('  msg <- paste0(');
    Lines.Add('    "Implementation not found for API: ", api_name,');
    Lines.Add('    ". Add a stub to ", .impl_path()');
    Lines.Add('  );');
    Lines.Add('  stop(msg);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Callback factory (probe short-circuit)
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Callback factory');
    Lines.Add('#');
    Lines.Add('# Handler signature: function(input) -> character(1)');
    Lines.Add('#');
    Lines.Add('# `input` is either:');
    Lines.Add('#   * the API description string, when C4 sends its reachability');
    Lines.Add('#     probe right after the App becomes ready; or');
    Lines.Add('#   * a JSON object, when a real client request arrives.');
    Lines.Add('#');
    Lines.Add('# The probe is short-circuited with {"code":0}. Real requests go');
    Lines.Add('# through the normal do.call() path.');
    Lines.Add('#');
    Lines.Add('# Do NOT call lf_data_read / lf_data_write here: the R binding');
    Lines.Add('# already did the handle I/O before invoking us.');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.make_cb <- function(api_name, param_names, description) {');
    Lines.Add('  force(api_name);');
    Lines.Add('  force(param_names);');
    Lines.Add('  force(description);');
    Lines.Add('  function(input) {');
    Lines.Add('    # Reachability probe (C4 built-in).');
    Lines.Add('    if (is.character(input) && length(input) == 1L &&');
    Lines.Add('        !is.na(input) && nzchar(description) &&');
    Lines.Add('        identical(input, description)) {');
    Lines.Add('      if (isTRUE(DEBUG_LOG)) {');
    Lines.Add('        cat("[cb] ", api_name, " probe\n", sep = "");');
    Lines.Add('      }');
    Lines.Add('      return(jsonlite::toJSON(list(code = 0L), auto_unbox = TRUE));');
    Lines.Add('    }');
    Lines.Add('    # Defensive: empty or non-string payload also counts as a probe.');
    Lines.Add('    if (is.null(input) || !is.character(input) ||');
    Lines.Add('        length(input) != 1L || is.na(input) || nchar(input) == 0L) {');
    Lines.Add('      if (isTRUE(DEBUG_LOG)) {');
    Lines.Add('        cat("[cb] ", api_name, " empty-probe\n", sep = "");');
    Lines.Add('      }');
    Lines.Add('      return(jsonlite::toJSON(list(code = 0L), auto_unbox = TRUE));');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    tryCatch({');
    Lines.Add('      if (isTRUE(DEBUG_LOG)) {');
    Lines.Add('        cat("[cb] ", api_name, " payload = ",');
    Lines.Add('            substr(input, 1, 200), "\n", sep = "");');
    Lines.Add('      }');
    Lines.Add('      req <- tryCatch(');
    Lines.Add('        jsonlite::fromJSON(input, simplifyVector = FALSE),');
    Lines.Add('        error = function(e) {');
    Lines.Add('          stop(paste0("invalid request JSON: ", conditionMessage(e)));');
    Lines.Add('        }');
    Lines.Add('      );');
    Lines.Add('      if (!is.list(req)) {');
    Lines.Add('        stop("request JSON must be an object");');
    Lines.Add('      }');
    Lines.Add('');
    Lines.Add('      args <- req$args;');
    Lines.Add('      if (is.null(args)) {');
    Lines.Add('        args <- req;');
    Lines.Add('        args$args <- NULL;');
    Lines.Add('      }');
    Lines.Add('      if (is.null(args)) args <- list();');
    Lines.Add('      if (!is.list(args)) args <- list(args);');
    Lines.Add('');
    Lines.Add('      fn <- get0(api_name, envir = .impl_env, mode = "function");');
    Lines.Add('      if (!is.function(fn)) {');
    Lines.Add('        .stop_missing_impl(api_name);');
    Lines.Add('      }');
    Lines.Add('');
    Lines.Add('      has_names <- !is.null(names(args)) && any(nzchar(names(args)));');
    Lines.Add('      if (length(param_names) > 0L && !has_names &&');
    Lines.Add('          length(args) >= length(param_names)) {');
    Lines.Add('        names(args)[seq_along(param_names)] <- param_names;');
    Lines.Add('      }');
    Lines.Add('');
    Lines.Add('      result <- do.call(fn, args);');
    Lines.Add('');
    Lines.Add('      resp <- list(code = 0L);');
    Lines.Add('      if (!is.null(result)) resp$result <- result;');
    Lines.Add('      jsonlite::toJSON(resp, auto_unbox = TRUE);');
    Lines.Add('    }, error = function(e) {');
    Lines.Add('      jsonlite::toJSON(');
    Lines.Add('        list(code = -1L, error = conditionMessage(e)),');
    Lines.Add('        auto_unbox = TRUE');
    Lines.Add('      );');
    Lines.Add('    });');
    Lines.Add('  };');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('');

    // ----------------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------------
    Lines.Add('# ============================================================================');
    Lines.Add('# Main');
    Lines.Add('# ============================================================================');
    Lines.Add('');
    Lines.Add('.main <- function() {');
    Lines.Add('  cat("=== ", APP_NAME, " native R LingoFuse service ===\n", sep = "");');
    Lines.Add('  cat("Endpoint: ", LF_ENDPOINT, "\n", sep = "");');
    Lines.Add('  cat("APIs    : ' + MdInt(Length(SupportedFuncs)) + '\n", sep = "");');
    Lines.Add('  cat("\n");');
    Lines.Add('');
    Lines.Add('  cat("[1] Loading user implementations from ", .impl_path(), "\n", sep = "");');
    Lines.Add('  .load_impl();');
    Lines.Add('');
    Lines.Add('  rt <- .resolve_runtime_dir();');
    Lines.Add('  cat("[2] LingoFuse runtime: ", rt, "\n", sep = "");');
    Lines.Add('  lingofuse::lf_load(runtime_dir = rt);');
    Lines.Add('');
    Lines.Add('  app <- lingofuse::lf_create_app(APP_NAME, APP_DESC);');
    Lines.Add('  if (is.null(app)) {');
    Lines.Add('    stop("lf_create_app returned NULL");');
    Lines.Add('  }');
    Lines.Add('  cat("[3] LF App created: ", APP_NAME, "\n", sep = "");');
    Lines.Add('');
    Lines.Add('  api_specs <- list(');

    if Length(SupportedFuncs) = 0 then
      Lines.Add('    # no APIs')
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        ParamNameArr := BuildRParamNameArray(F.Params);
        Description := GetFullDescription(F.Comment);
        if Description.Len = 0 then
          Description := 'HTTP/JSON api for ' + ApiName;

        if i < High(SupportedFuncs) then
          Lines.Add('    list(name = ' + RStrLit(ApiName) +
                    ', params = ' + ParamNameArr +
                    ', description = ' + RStrLit(Description) + '),')
        else
          Lines.Add('    list(name = ' + RStrLit(ApiName) +
                    ', params = ' + ParamNameArr +
                    ', description = ' + RStrLit(Description) + ')');
      end;
    end;

    Lines.Add('  );');
    Lines.Add('');
    Lines.Add('  ok_count <- 0L;');
    Lines.Add('  for (spec in api_specs) {');
    Lines.Add('    cb <- .make_cb(spec$name, spec$params, spec$description);');
    Lines.Add('    ok <- lingofuse::lf_register_call(app, spec$name, spec$description, cb);');
    Lines.Add('    if (isTRUE(ok)) {');
    Lines.Add('      ok_count <- ok_count + 1L;');
    Lines.Add('      cat("[4] registered: ", spec$name, " (", spec$description, ")\n", sep = "");');
    Lines.Add('    } else {');
    Lines.Add('      cat("[4] FAILED to register: ", spec$name, "\n", sep = "");');
    Lines.Add('    }');
    Lines.Add('  }');
    Lines.Add('  cat("[4] Registered ", ok_count, " of ", length(api_specs), " APIs.\n", sep = "");');
    Lines.Add('');
    Lines.Add('  cat("[5] Preparing service on ", LF_ENDPOINT, "\n", sep = "");');
    Lines.Add('  svc_tag <- lingofuse::lf_prepare_service(LF_ENDPOINT, LF_ENDPOINT);');
    Lines.Add('  if (is.null(svc_tag) || !is.finite(as.numeric(svc_tag)) ||');
    Lines.Add('      as.numeric(svc_tag) < 0) {');
    Lines.Add('    stop(paste0("lf_prepare_service failed for endpoint: ", LF_ENDPOINT));');
    Lines.Add('  }');
    Lines.Add('  cli_tag <- lingofuse::lf_prepare_client(LF_ENDPOINT, app);');
    Lines.Add('  if (is.null(cli_tag) || !is.finite(as.numeric(cli_tag)) ||');
    Lines.Add('      as.numeric(cli_tag) < 0) {');
    Lines.Add('    stop(paste0("lf_prepare_client failed for endpoint: ", LF_ENDPOINT));');
    Lines.Add('  }');
    Lines.Add('  rc <- lingofuse::lf_prepare_done();');
    Lines.Add('  if (!identical(rc, 1L)) {');
    Lines.Add('    stop(paste0("lf_prepare_done returned: ", rc));');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  # Sentinel file used to signal a graceful exit.');
    Lines.Add('  sentinel <- file.path(.script_dir(), "service.exit");');
    Lines.Add('  tryCatch(file.remove(sentinel), error = function(e) NULL);');
    Lines.Add('');
    Lines.Add('  cat("\n");');
    Lines.Add('  cat("=====================================================================\n");');
    Lines.Add('  cat(" ", APP_NAME, " native R LingoFuse service ready\n", sep = "");');
    Lines.Add('  cat(" App name : ", APP_NAME, "\n", sep = "");');
    Lines.Add('  cat(" Endpoint : ", LF_ENDPOINT, "\n", sep = "");');
    Lines.Add('  cat(" APIs     : ", ok_count, "\n", sep = "");');
    Lines.Add('  cat("=====================================================================\n");');
    Lines.Add('  cat("\n");');
    Lines.Add('  cat("To stop this service, open ANOTHER PowerShell window and run:\n");');
    Lines.Add('  cat("    \"\" > \"", sentinel, "\"\n", sep = "");');
    Lines.Add('  cat("(Or press Ctrl+C in this window as a fallback.)\n");');
    Lines.Add('  cat("\n");');
    Lines.Add('');
    Lines.Add('  running <- TRUE;');
    Lines.Add('  while (running) {');
    Lines.Add('    result <- tryCatch({');
    Lines.Add('      lingofuse::lf_poll(100);');
    Lines.Add('      "ok";');
    Lines.Add('    }, interrupt = function(e) {');
    Lines.Add('      message("[service] interrupted");');
    Lines.Add('      "int";');
    Lines.Add('    }, error = function(e) {');
    Lines.Add('      message("[service] pump error: ", conditionMessage(e));');
    Lines.Add('      "err";');
    Lines.Add('    });');
    Lines.Add('');
    Lines.Add('    if (result != "ok") {');
    Lines.Add('      running <- FALSE;');
    Lines.Add('      break;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if (file.exists(sentinel)) {');
    Lines.Add('      tryCatch(file.remove(sentinel), error = function(e) NULL);');
    Lines.Add('      message("[service] exit command received, shutting down...");');
    Lines.Add('      running <- FALSE;');
    Lines.Add('    }');
    Lines.Add('  }');
    Lines.Add('');
    Lines.Add('  # Orderly shutdown. Because the .onUnload patch above keeps');
    Lines.Add('  # the DLL mapped, the worker threads cannot race with process');
    Lines.Add('  # exit. The sleeps are short and merely polite.');
    Lines.Add('  tryCatch(lingofuse::lf_exit_main_thread(), error = function(e) NULL);');
    Lines.Add('  Sys.sleep(0.3);');
    Lines.Add('  tryCatch(lingofuse::lf_free_app(app), error = function(e) NULL);');
    Lines.Add('  Sys.sleep(0.3);');
    Lines.Add('  tryCatch(lingofuse::lf_shutdown(), error = function(e) NULL);');
    Lines.Add('  Sys.sleep(0.5);');
    Lines.Add('');
    Lines.Add('  message("[service] shutdown complete.");');
    Lines.Add('  quit(save = "no", status = 0);');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('.main();');
    Lines.Add('');
    Lines.Add('# ============================================================================');
    Lines.Add('# End of file');
    Lines.Add('# ============================================================================');

    Result := Lines;
    Log(PFormat('Generated native R service: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

// ===========================================================================
// IMPL STUB GENERATOR
// ===========================================================================

function GenerateHTTPServiceRImplStub(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName, RIdent, ParamList: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  Description, ReturnDefault: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

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

    Lines.Add('# Auto-generated by http_R_abi_service_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('#');
    Lines.Add('# User-editable implementation stubs for ' + NormalizedUnit.Text + '.');
    Lines.Add('#');
    Lines.Add('# This file is sourced at service startup into an isolated');
    Lines.Add('# environment whose parent is globalenv(). Every base R');
    Lines.Add('# function (list, paste0, stop, ...) is therefore available.');
    Lines.Add('#');
    Lines.Add('# Fill in the body of each function with the real business logic.');
    Lines.Add('# The function names below are the API names as seen on the wire.');
    Lines.Add('#');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      RIdent := MakeSafeRIdent(ApiName, i);
      ParamList := BuildRParamList(F.Params);

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON API: ' + ApiName;

      if F.IsFunction then
        ReturnDefault := ABI_Type_To_R_Stub_Default(F.ReturnType)
      else
        ReturnDefault := '';

      Lines.Add('# ' + Description.Text);
      Lines.Add('# Original declaration: ' + BuildFullDecl(F));
      Lines.Add(RIdent + ' <- function(' + ParamList + ') {');
      Lines.Add('  # TODO: implement.');
      if F.IsFunction then
        Lines.Add('  return(' + ReturnDefault + ')')
      else
        Lines.Add('  invisible(NULL)');
      Lines.Add('}');
      Lines.Add('');
    end;

    Result := Lines;
    Log(PFormat('Generated impl stub: %d lines.', [Lines.Count]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'r', 'R HTTP/JSON native service source',
    asService, akServiceCode,
    '_http_json_service.R', False,
    @GenerateHTTPServiceRCode);
  RegisterCodeGenEntry(
    'r', 'R HTTP/JSON service impl stub',
    asService, akServiceCode,
    '_http_json_service_impl.R', False,
    @GenerateHTTPServiceRImplStub);
end.
