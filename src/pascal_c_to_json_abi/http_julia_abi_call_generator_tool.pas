unit http_julia_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallJuliaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_julia_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_julia_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Julia_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'Float64'
  else if ABI_Type_Is_Int(T) then
    Result := 'Int64'
  else
    Result := 'Any';
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

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafeJuliaIdent(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
      ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if Result.Same('abstract') or Result.Same('baremodule') or
    Result.Same('begin') or Result.Same('break') or Result.Same('catch') or
    Result.Same('const') or Result.Same('continue') or Result.Same('do') or
    Result.Same('else') or Result.Same('elseif') or Result.Same('end') or
    Result.Same('export') or Result.Same('false') or Result.Same('finally') or
    Result.Same('for') or Result.Same('function') or Result.Same('global') or
    Result.Same('if') or Result.Same('import') or Result.Same('in') or
    Result.Same('let') or Result.Same('local') or Result.Same('macro') or
    Result.Same('module') or Result.Same('quote') or Result.Same('return') or
    Result.Same('struct') or Result.Same('true') or Result.Same('try') or
    Result.Same('using') or Result.Same('while') then
    Result := Result + '_';
end;

// JuliaStrLit - produce a complete Julia string literal (double quoted,
// with the surrounding quotes included). Single quotes are NOT permitted
// inside the body; callers that need a literal single quote must write
// it via the #39 escape in the generated output.
function JuliaStrLit(const S: TP_String): TP_String;
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
      #92:  Result.Append('\\');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
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

function BuildJuliaParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, typ: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaIdent(Params[i].Name, i);
    typ := ABI_Type_To_Julia_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + '::' + typ;
  end;
end;

function BuildJuliaCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeJuliaIdent(F.Params[i].Name, i);
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
// HEADER EMITTER
// =============================================================================

procedure EmitJuliaHeader(Lines: TPascalStringList;
  const UnitName, NormalizedUnit, ModuleName, BaseUrl: TP_String);
begin
  Lines.Add('# ' + NormalizedUnit.Text + '_http_json_call.jl');
  Lines.Add('#');
  Lines.Add('# Auto-generated by http_julia_abi_call_generator_tool.pas.');
  Lines.Add('# Source model unit: ' + UnitName.Text + '.');
  Lines.Add('# Do not edit by hand unless you know what you are doing.');
  Lines.Add('#');
  Lines.Add('# Call-side Julia module for the LingoFuse HTTP/JSON service that');
  Lines.Add('# was generated from the same source unit.');
  Lines.Add('#');
  Lines.Add('# The module sends requests through the LingoFuse HTTP bridge');
  Lines.Add('# (bridge.py) via the LingoFuse mesh. It does NOT speak HTTP');
  Lines.Add('# directly; it uses lingofuse.call / lingofuse.future to reach');
  Lines.Add('# the bridge''s __lf_outbound_post__ API, exactly like the C++ and');
  Lines.Add('# Python call generators do.');
  Lines.Add('#');
  Lines.Add('# PREREQUISITES FOR THE CALLER');
  Lines.Add('# ----------------------------');
  Lines.Add('# 1. Launch Julia with --threads=2 or more.');
  Lines.Add('# 2. Call lingofuse.start_callback_consumer() before any async call.');
  Lines.Add('# 3. bridge.py must be running on the same LingoFuse endpoint, and');
  Lines.Add('#    the target service must be online.');
  Lines.Add('');
  Lines.Add('module ' + ModuleName.Text);
  Lines.Add('');
  Lines.Add('using LingoFuse');
  Lines.Add('import JSON3');
  Lines.Add('import LingoFuse: app_target, call, future, write_json!');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Configuration');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('# Set HTTP_CALL_BASE_URL before the first call. The other four');
  Lines.Add('# globals are optional overrides: leave them empty (or zero) to');
  Lines.Add('# use the bridge client''s own defaults.');
  Lines.Add('');
  Lines.Add('# Base URL prefix of the target service. The full URL for API "X" is');
  Lines.Add('# HTTP_CALL_BASE_URL * "/" * "X". Must NOT have a trailing slash:');
  Lines.Add('# the generated code adds it.');
  Lines.Add('HTTP_CALL_BASE_URL::String = ' + JuliaStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('# LingoFuse App name of the bridge. An empty string means "use the');
  Lines.Add('# bridge default", which is __lf_http_bridge__.');
  Lines.Add('HTTP_BRIDGE_APP_NAME::String = "";');
  Lines.Add('');
  Lines.Add('# LingoFuse API name of the bridge''s outbound POST proxy. An empty');
  Lines.Add('# string means "use the bridge default", which is');
  Lines.Add('# __lf_outbound_post__.');
  Lines.Add('HTTP_BRIDGE_API_NAME::String = "";');
  Lines.Add('');
  Lines.Add('# Timeout, in milliseconds, for the LingoFuse round trip that carries');
  Lines.Add('# the request to the bridge and the response back. Zero means "use');
  Lines.Add('# the default" (60000 ms). Must be larger than the outbound HTTP');
  Lines.Add('# timeout (HTTP_CALL_DEFAULT_TIMEOUT_S * 1000).');
  Lines.Add('HTTP_CALL_TIMEOUT_MS::Int64 = Int64(0);');
  Lines.Add('');
  Lines.Add('# Outbound HTTP timeout, in seconds, sent inside the bridge request.');
  Lines.Add('# Zero means "use the default" (25.0 s).');
  Lines.Add('HTTP_CALL_DEFAULT_TIMEOUT_S::Float64 = 0.0;');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Error type');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('#');
  Lines.Add('# Raised by every synchronous generated function on failure.');
  Lines.Add('# Asynchronous functions deliver failures through the Task''s');
  Lines.Add('# exception, which fetch(task) re-raises.');
  Lines.Add('#');
  Lines.Add('# code:');
  Lines.Add('#   -1  transport / service failure');
  Lines.Add('#   -2  request shape error (empty URL, un-serializable body)');
  Lines.Add('#   -4  bridge protocol error (malformed envelope)');
  Lines.Add('#   >0  service-defined error code');
  Lines.Add('');
  Lines.Add('struct HTTPCallError <: Exception');
  Lines.Add('    msg::String');
  Lines.Add('    code::Int');
  Lines.Add('    http_status::Int');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function HTTPCallError(msg::String; code::Int = -1, http_status::Int = 0)');
  Lines.Add('    return HTTPCallError(msg, code, http_status)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function Base.showerror(io::IO, e::HTTPCallError)');
  Lines.Add('    print(io, "HTTPCallError(code=", e.code, ", http_status=", e.http_status, "): ", e.msg)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Detail helpers (shared by the sync and async paths)');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('function _parse_envelope(envelope::Dict{String,Any})::Dict{String,Any}');
  Lines.Add('    if !haskey(envelope, "body")');
  Lines.Add('        throw(HTTPCallError("bridge envelope has no ' + #39 + 'body' + #39 + ' field", -4))');
  Lines.Add('    end');
  Lines.Add('    body = envelope["body"]');
  Lines.Add('    if !(body isa Dict)');
  Lines.Add('        throw(HTTPCallError("bridge envelope ' + #39 + 'body' + #39 + ' is not a JSON object", -4))');
  Lines.Add('    end');
  Lines.Add('    if !haskey(body, "code")');
  Lines.Add('        throw(HTTPCallError("service response has no ' + #39 + 'code' + #39 + ' field", -4))');
  Lines.Add('    end');
  Lines.Add('    code = body["code"]');
  Lines.Add('    if !(code isa Number)');
  Lines.Add('        throw(HTTPCallError("service response ' + #39 + 'code' + #39 + ' is not an integer", -4))');
  Lines.Add('    end');
  Lines.Add('    if code != 0');
  Lines.Add('        err = get(body, "error", "service reported an error")');
  Lines.Add('        throw(HTTPCallError(string(err), Int(code), 200))');
  Lines.Add('    end');
  Lines.Add('    return body::Dict{String,Any}');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _default_result_value(::Type{Int64})::Int64');
  Lines.Add('    return Int64(0)');
  Lines.Add('end');
  Lines.Add('function _default_result_value(::Type{Float64})::Float64');
  Lines.Add('    return 0.0');
  Lines.Add('end');
  Lines.Add('function _default_result_value(::Type{String})::String');
  Lines.Add('    return ""');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('# Extract the "result" field with explicit type checking.');
  Lines.Add('#   * Missing or null result    -> type default');
  Lines.Add('#   * Integer T, JSON float     -> throws (rejects silent truncation)');
  Lines.Add('#   * Other type mismatch       -> throws');
  Lines.Add('function _extract_result(body::Dict{String,Any}, ::Type{T})::T where {T}');
  Lines.Add('    if !haskey(body, "result") || body["result"] === nothing');
  Lines.Add('        return _default_result_value(T)');
  Lines.Add('    end');
  Lines.Add('    slot = body["result"]');
  Lines.Add('    if T <: Integer && slot isa AbstractFloat');
  Lines.Add('        throw(HTTPCallError(');
  Lines.Add('            "service response ' + #39 + 'result' + #39 + ' expects an integer, " *');
  Lines.Add('            "but the service sent a floating-point number", -1, 200))');
  Lines.Add('    end');
  Lines.Add('    try');
  Lines.Add('        return convert(T, slot)::T');
  Lines.Add('    catch e');
  Lines.Add('        throw(HTTPCallError(');
  Lines.Add('            "cannot convert service response ' + #39 + 'result' + #39 + ': " * string(e),');
  Lines.Add('            -1, 200))');
  Lines.Add('    end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Internal: bridge transport');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('function _build_bridge_request(url::String, args::Vector{Any})::Dict{String,Any}');
  Lines.Add('    http_timeout = HTTP_CALL_DEFAULT_TIMEOUT_S > 0.0 ? HTTP_CALL_DEFAULT_TIMEOUT_S : 25.0');
  Lines.Add('    return Dict{String,Any}(');
  Lines.Add('        "url" => url,');
  Lines.Add('        "method" => "POST",');
  Lines.Add('        "body" => Dict{String,Any}("args" => args),');
  Lines.Add('        "timeout" => round(Int, http_timeout),');
  Lines.Add('    )');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _effective_bridge_app()::String');
  Lines.Add('    return isempty(HTTP_BRIDGE_APP_NAME) ? "__lf_http_bridge__" : HTTP_BRIDGE_APP_NAME');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _effective_bridge_api()::String');
  Lines.Add('    return isempty(HTTP_BRIDGE_API_NAME) ? "__lf_outbound_post__" : HTTP_BRIDGE_API_NAME');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('function _effective_call_timeout_ms()::Int');
  Lines.Add('    return HTTP_CALL_TIMEOUT_MS > 0 ? Int(HTTP_CALL_TIMEOUT_MS) : 60000');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('# Synchronous bridge call. Blocks until the response arrives.');
  Lines.Add('function _invoke(url::String, args::Vector{Any})::Dict{String,Any}');
  Lines.Add('    bridge_req = _build_bridge_request(url, args)');
  Lines.Add('    timeout_ms = _effective_call_timeout_ms()');
  Lines.Add('    target = app_target(_effective_bridge_app(); timeout_ms=timeout_ms)');
  Lines.Add('    payload_fn = dh -> write_json!(dh, bridge_req)');
  Lines.Add('');
  Lines.Add('    result_bytes = try');
  Lines.Add('        call(target, _effective_bridge_api(), payload_fn; timeout_ms=timeout_ms)');
  Lines.Add('    catch e');
  Lines.Add('        throw(HTTPCallError("LingoFuse call failed: " * string(e), -1))');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    envelope = try');
  Lines.Add('        JSON3.read(result_bytes, Dict{String,Any})');
  Lines.Add('    catch e');
  Lines.Add('        throw(HTTPCallError("failed to parse bridge envelope: " * string(e), -1))');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    if haskey(envelope, "error")');
  Lines.Add('        throw(HTTPCallError(string(envelope["error"]), -1))');
  Lines.Add('    end');
  Lines.Add('    return _parse_envelope(envelope)');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('# Asynchronous bridge call. Returns a Task that yields the parsed');
  Lines.Add('# body object when fetched.');
  Lines.Add('function _invoke_async(url::String, args::Vector{Any})::Base.Task');
  Lines.Add('    bridge_req = _build_bridge_request(url, args)');
  Lines.Add('    timeout_ms = _effective_call_timeout_ms()');
  Lines.Add('    target = app_target(_effective_bridge_app(); timeout_ms=timeout_ms)');
  Lines.Add('    payload_fn = dh -> write_json!(dh, bridge_req)');
  Lines.Add('');
  Lines.Add('    lf_future = future(target, _effective_bridge_api(), payload_fn; timeout_ms=timeout_ms)');
  Lines.Add('');
  Lines.Add('    return Threads.@spawn begin');
  Lines.Add('        result_bytes = try');
  Lines.Add('            fetch(lf_future)');
  Lines.Add('        catch e');
  Lines.Add('            throw(HTTPCallError("LingoFuse async call failed: " * string(e), -1))');
  Lines.Add('        end');
  Lines.Add('');
  Lines.Add('        envelope = try');
  Lines.Add('            JSON3.read(result_bytes, Dict{String,Any})');
  Lines.Add('        catch e');
  Lines.Add('            throw(HTTPCallError("failed to parse bridge envelope: " * string(e), -1))');
  Lines.Add('        end');
  Lines.Add('');
  Lines.Add('        if haskey(envelope, "error")');
  Lines.Add('            throw(HTTPCallError(string(envelope["error"]), -1))');
  Lines.Add('        end');
  Lines.Add('        return _parse_envelope(envelope)');
  Lines.Add('    end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Typed call functions');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
end;

// =============================================================================
// PER-FUNCTION EMITTER
// =============================================================================

procedure EmitJuliaFunction(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName, JuliaFuncName: TP_String);
var
  ParamList, ArgList: TP_String;
  RetType: TP_String;
  Description: TP_String;
  i: integer;
  PName, PDesc: TP_String;
begin
  ParamList := BuildJuliaParamList(F.Params);
  ArgList := BuildJuliaCallArgList(F.Params);
  Description := GetFullDescription(F.Comment);

  if F.IsFunction then
    RetType := ABI_Type_To_Julia_Type(F.ReturnType)
  else
    RetType := 'Nothing';

  // ---- Synchronous ----
  Lines.Add('# ' + Description.Text);
  Lines.Add('# HTTP route: POST /' + ApiName.Text);
  Lines.Add('function ' + JuliaFuncName.Text + '(' + ParamList.Text + ')::' + RetType.Text);
  if Length(F.Params) > 0 then
    Lines.Add('    body = _invoke(HTTP_CALL_BASE_URL * "/' + ApiName.Text + '", Any[' + ArgList.Text + '])')
  else
    Lines.Add('    body = _invoke(HTTP_CALL_BASE_URL * "/' + ApiName.Text + '", Any[])');
  if F.IsFunction then
    Lines.Add('    return _extract_result(body, ' + RetType.Text + ')')
  else
    Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');

  // ---- Asynchronous ----
  Lines.Add('# Async variant. fetch(task) yields the parsed result, or re-raises');
  Lines.Add('# the HTTPCallError carried by the task.');
  Lines.Add('function ' + JuliaFuncName.Text + '_async(' + ParamList.Text + ')::Base.Task');
  if Length(F.Params) > 0 then
    Lines.Add('    task = _invoke_async(HTTP_CALL_BASE_URL * "/' + ApiName.Text + '", Any[' + ArgList.Text + '])')
  else
    Lines.Add('    task = _invoke_async(HTTP_CALL_BASE_URL * "/' + ApiName.Text + '", Any[])');
  Lines.Add('    return Threads.@spawn begin');
  Lines.Add('        body = fetch(task)');
  if F.IsFunction then
    Lines.Add('        return _extract_result(body, ' + RetType.Text + ')')
  else
    Lines.Add('        return nothing');
  Lines.Add('    end');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('');
end;

// =============================================================================
// PUBLIC: GenerateHTTPCallJuliaCode
// =============================================================================

function GenerateHTTPCallJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, BaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  UsedJuliaFuncNames, JuliaFuncNames: TPascalStringList;
  ApiName, JuliaFuncName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallJuliaCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallJuliaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := NormalizedUnit + 'HttpJsonCall';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  UsedJuliaFuncNames := TPascalStringList.Create;
  JuliaFuncNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);

      JuliaFuncName := UniqueName(MakeSafeJuliaIdent(ApiName, i), UsedJuliaFuncNames);
      UsedJuliaFuncNames.Add(JuliaFuncName);
      JuliaFuncNames.Add(JuliaFuncName);
    end;

    EmitJuliaHeader(Lines, UnitName, NormalizedUnit, ModuleName, BaseUrl);

    for i := 0 to High(SupportedFuncs) do
      EmitJuliaFunction(Lines, SupportedFuncs[i], ApiNames[i], JuliaFuncNames[i]);

    // Exports
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Public exports');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('export HTTPCallError');
    Lines.Add('export HTTP_CALL_BASE_URL, HTTP_BRIDGE_APP_NAME,');
    Lines.Add('       HTTP_BRIDGE_API_NAME, HTTP_CALL_TIMEOUT_MS,');
    Lines.Add('       HTTP_CALL_DEFAULT_TIMEOUT_S');
    (* Julia requires the line-continuation comma to trail the preceding
       symbol, never to lead the next line. The old code emitted
       "export A, A_async" followed by "       , B, B_async", which Julia
       rejects with a parse error at the leading comma. Every entry now
       carries its trailing comma, and only the very last entry omits it. *)
    if Length(SupportedFuncs) > 0 then
    begin
      if Length(SupportedFuncs) > 1 then
        Lines.Add('export ' + JuliaFuncNames[0].Text + ', ' +
          JuliaFuncNames[0].Text + '_async,')
      else
        Lines.Add('export ' + JuliaFuncNames[0].Text + ', ' +
          JuliaFuncNames[0].Text + '_async');
      for i := 1 to High(SupportedFuncs) do
      begin
        if i < High(SupportedFuncs) then
          Lines.Add('       ' + JuliaFuncNames[i].Text + ', ' +
            JuliaFuncNames[i].Text + '_async,')
        else
          Lines.Add('       ' + JuliaFuncNames[i].Text + ', ' +
            JuliaFuncNames[i].Text + '_async');
      end;
    end;
    Lines.Add('');
    Lines.Add('end # module ' + ModuleName.Text);

    Result := Lines;
    Log(PFormat('Generated Julia call module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    UsedJuliaFuncNames.Free;
    JuliaFuncNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'julia', 'Julia HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call.jl', False,
    @GenerateHTTPCallJuliaCode);
end.
