unit http_pas_abi_call_generator_tool;

// http_pas_abi_call_generator_tool - LingoFuse HTTP/JSON ABI Call-Side
// Generator for Pascal.
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces a complete Pascal unit that provides typed free
// functions for calling an HTTP/JSON ABI service through bridge.py.
//
// The generated unit is the call-side counterpart of the unit produced
// by http_pas_abi_service_generator_tool. It is designed to reach any
// HTTP/JSON service (including webjs / PHP / nodejs backends) via the
// LingoFuse bridge.
//
// Wire protocol (HTTP/JSON path):
//   request  = JSON object
//              { "args": [v1, v2, ...] }     positional arguments
//   response = JSON object
//              { "code": 0,  "result": ... }  on success
//              { "code": -1, "error":  ... }  on failure
//
// The generated unit relies on lf_http_bridge_client's LFHttpPost helper,
// which performs the LF_Call to bridge.py's __lf_outbound_post__ API and
// returns the parsed bridge response as a TZ_JsonObject. This is the
// same dependency chain used by test_bridge_via_lf.lpr and by any other
// Pascal client of the bridge.
//
// The generated unit exposes:
//   type  EHTTPCallError = class(Exception);
//   var   HTTP_CALL_BASE_URL: string;
//   One typed free function per supported routine.
//
// The user is expected to:
//   1. Ensure LingoFuse is prepared (LF_ResetPrepare / LF_PrepareClient /
//      LF_PrepareDone) and bridge.py is running.
//   2. Set HTTP_CALL_BASE_URL to the bridge's base URL plus target app.
//   3. Call the generated free functions directly.
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> JSON number -> Integer
//   int64                         -> JSON number -> Int64
//   cardinal / dword / longword   -> JSON number -> Cardinal
//   word                          -> JSON number -> Word
//   smallint                      -> JSON number -> SmallInt
//   byte                          -> JSON number -> Byte
//   uint64                        -> JSON number -> UInt64
//   double / extended / real      -> JSON number -> Double
//   single                        -> JSON number -> Single
//   string / PChar family         -> JSON string -> string
//
// The generated unit's interface uses clause mirrors the one used by
// lf_http_bridge_client.pas plus lf_http_bridge_client itself. This is a
// hard requirement: it guarantees that TZ_JsonObject / TZ_JsonArray /
// TDataHnd___ / LF_* resolve identically in the call path and in the
// bridge client unit.
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

// GenerateHTTPCallPascalCode - main entry point for the call unit.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallPascalCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallPascalReadme - main entry point for the call-side README.
//
// Produces a Markdown document that describes the generated call-side
// unit: purpose, outbound wire protocol, type mapping, deployment,
// testing, per-API reference, and a chapter explicitly targeted at AI
// agents.
//
// The document is deliberately parallel to the service-side README
// produced by http_pas_abi_service_generator_tool, but the viewpoint
// is inverted: this README is written for the CALLER, not for the
// SERVICE. It documents:
//
//   * HTTP_CALL_BASE_URL, the global that every generated function
//     reads to compose its target URL.
//   * EHTTPCallError, the exception every generated function raises
//     on failure.
//   * The outbound request shape and the inbound response shape.
//   * The LingoFuse prerequisite (LF_PrepareClient before any call).
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallPascalReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_pas_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Pascal_Decl(T) <> '';
end;

// -----------------------------------------------------------------------------
// Expression builders for the generated call body
//
// Serialize: emit a single statement that appends one argument to the
//            "args" array of the request body.
// Deserialize: emit the expression that reads the "result" field of
//            the response body and casts it to the declared return
//            type.
// -----------------------------------------------------------------------------

function ABI_Type_To_Serialize_Stmt(const ParamName, T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '_ReqBody.A[''args''].Add(string(' + ParamName + '));'
  else if ABI_Type_Is_Float(T) then
    Result := '_ReqBody.A[''args''].AddF(Double(' + ParamName + '));'
  else
    Result := '_ReqBody.A[''args''].Add(Int64(' + ParamName + '));';
end;

function ABI_Type_To_Deserialize_Expr(const T: TP_String): TP_String;
var
  Decl: TP_String;
begin
  Decl := ABI_Type_To_Pascal_Decl(T);
  if ABI_Type_Is_String(T) then
    Result := '_InnerJo.S[''result'']'
  else if ABI_Type_Is_Float(T) then
    Result := Decl + '(_InnerJo.F[''result''])'
  else
    Result := Decl + '(_InnerJo.L[''result''])';
end;

// -----------------------------------------------------------------------------
// JSON wire-type helpers (used only by the README generator)
// -----------------------------------------------------------------------------
//
// On the HTTP/JSON path the wire types are coarser than the binary ABI
// types: every integer width collapses to a single JSON "number", and
// every string family collapses to a single JSON "string". The README
// documents this collapse explicitly so the reader does not expect
// ABI-style type preservation over HTTP.

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

function ABI_Type_To_Json_Wire_Type_Desc(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'JSON string (UTF-8)'
  else if ABI_Type_Is_Float(T) then
    Result := 'JSON number (floating point)'
  else if ABI_Type_Is_Int(T) then
    Result := 'JSON number (integer)'
  else
    Result := '';
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
//   * http_js_abi_call_generator_tool
//   * http_py_abi_service_generator_tool
//   * http_py_abi_call_generator_tool
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

function MakeSafePascalIdent(const Name: TP_String; Index: integer): TP_String;
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
end;

function PascalStrLit(const S: TP_String): TP_String;
begin
  Result := TTextParsing.Translate_Text_To_Pascal_Decl(S);
end;

// -----------------------------------------------------------------------------
// Markdown helpers (used only by the README generator)
// -----------------------------------------------------------------------------

// MdCellEscape - escape a string for safe inclusion in a Markdown table
// cell. Pipes are the only structural character in Markdown tables, so
// they get backslash-escaped. Newlines are replaced with spaces.
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
    // Skip CR; LF already converted the newline above.
    else
      Result.Append(c);
  end;
end;

// MdCodeEscape - wrap a value in backticks for inline code, escaping
// any backticks already present in the string so the fences stay intact.
function MdCodeEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '`';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '`' then
      Result.Append('\`')
    else
      Result.Append(c);
  end;
  Result.Append('`');
end;

// MdInt - render an integer as a Markdown-safe string.
function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// -----------------------------------------------------------------------------
// Comment description extraction (kept in sync with the service generator)
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
// Parameter list builder (for the generated function signature)
// -----------------------------------------------------------------------------

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
  Decl: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePascalIdent(Params[i].Name, i);
    Decl := ABI_Type_To_Pascal_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + '; ';
    Result := Result + n + ': ' + Decl;
  end;
end;

function BuildCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePascalIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildFullDecl - produce a COMPLETE Pascal declaration string for a
// routine, e.g. "function Add(a: Int64; b: Int64): Int64;".
//
// Used by the README generator so the reader sees the full signature
// rather than only the parameter list. The routine name used here is
// the DISAMBIGUATED API name, matching what the generated call unit
// actually exposes.
function BuildFullDecl(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(F.Params);
  if F.IsFunction then
    Result := 'function ' + ApiName + '(' + ParamDecl + '): ' + ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + ApiName + '(' + ParamDecl + ');';
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
      if not IsSupportedABIType(F.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"', [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and F.IsFunction and (not IsSupportedABIType(F.ReturnType)) then
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

// -----------------------------------------------------------------------------
// Emit the declaration for one typed call function (interface section)
// -----------------------------------------------------------------------------

procedure EmitFunctionDecl(Lines: TPascalStringList; const ApiName: TP_String; const IsFunction: boolean; const Params: TParamArray; const ReturnType: TP_String);
var
  ParamDecl, RetType: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(Params);
  RetType := ABI_Type_To_Pascal_Decl(ReturnType);

  if IsFunction then
    Lines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetType + ';')
  else
    Lines.Add('procedure ' + ApiName + '(' + ParamDecl + ');');
end;

// -----------------------------------------------------------------------------
// Emit the definition for one typed call function (implementation section)
//
// The generated body performs the following steps:
//
//   1. Compose the target URL: HTTP_CALL_BASE_URL + '/' + <api>.
//   2. Build the request body: { "args": [<arg1>, <arg2>, ...] }.
//   3. Call LFHttpPost to send the request through the bridge.
//   4. Verify the bridge response: has "body", has "code".
//   5. On code <> 0: raise EHTTPCallError with the "error" text.
//   6. On code  = 0: read "result" and return it.
//
// The bridge response is owned by this function and freed in a finally
// block. On the failure path of LFHttpPost, the out parameter is nil, so
// no free is required there.
// -----------------------------------------------------------------------------

procedure EmitFunctionDef(Lines: TPascalStringList; const ApiName: TP_String; const IsFunction: boolean; const Params: TParamArray; const ReturnType: TP_String);
var
  i: integer;
  ParamDecl, PName, RetType: TP_String;
  SerializeStmt: TP_String;
  DeserializeExpr: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(Params);
  RetType := ABI_Type_To_Pascal_Decl(ReturnType);

  Lines.Add('');
  if IsFunction then
    Lines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetType + ';')
  else
    Lines.Add('procedure ' + ApiName + '(' + ParamDecl + ');');

  Lines.Add('var');
  Lines.Add('  _ReqBody, _RespJo, _InnerJo: TZ_JsonObject;');
  Lines.Add('  _Url, _ErrMsg: string;');
  Lines.Add('begin');

  // ---- Step 1: compose URL ----
  Lines.Add('  // Step 1: compose the target URL.');
  Lines.Add('  _Url := HTTP_CALL_BASE_URL + ''/'' + ' + PascalStrLit(ApiName) + ';');

  // ---- Step 2: build request body ----
  Lines.Add('');
  Lines.Add('  // Step 2: build the request body.');
  Lines.Add('  _ReqBody := TZ_JsonObject.Create;');
  Lines.Add('  try');
  if Length(Params) = 0 then
    Lines.Add('    // No parameters to serialize.')
  else
    for i := 0 to High(Params) do
    begin
      PName := MakeSafePascalIdent(Params[i].Name, i);
      SerializeStmt := ABI_Type_To_Serialize_Stmt(PName, Params[i].PascalType);
      Lines.Add('    ' + SerializeStmt);
    end;

  // ---- Step 3: call through the bridge ----
  Lines.Add('');
  Lines.Add('    // Step 3: call through the bridge.');
  Lines.Add('    if not LFHttpPost(_Url, _ReqBody, _RespJo, _ErrMsg) then');
  Lines.Add('      raise EHTTPCallError.Create(');
  Lines.Add('        ' + PascalStrLit('HTTP call to "' + ApiName + '" failed: ') + ' + _ErrMsg);');
  Lines.Add('  finally');
  Lines.Add('    _ReqBody.Free;');
  Lines.Add('  end;');

  // ---- Step 4-6: parse the bridge response ----
  Lines.Add('');
  Lines.Add('  // Step 4-6: parse the bridge response.');
  Lines.Add('  // _RespJo is owned by this function; free it before returning.');
  Lines.Add('  try');
  Lines.Add('    if not _RespJo.Exists(''body'') then');
  Lines.Add('      raise EHTTPCallError.Create(');
  Lines.Add('        ' + PascalStrLit('HTTP call to "' + ApiName + '": bridge response has no "body"') + ');');
  Lines.Add('    _InnerJo := _RespJo.O[''body''];');
  Lines.Add('');
  Lines.Add('    if not _InnerJo.Exists(''code'') then');
  Lines.Add('      raise EHTTPCallError.Create(');
  Lines.Add('        ' + PascalStrLit('HTTP call to "' + ApiName + '": response has no "code" field') + ');');
  Lines.Add('');
  Lines.Add('    if _InnerJo.I[''code''] <> 0 then');
  Lines.Add('    begin');
  Lines.Add('      _ErrMsg := _InnerJo.S[''error''];');
  Lines.Add('      if _ErrMsg = '''' then');
  Lines.Add('        _ErrMsg := ''unknown error'';');
  Lines.Add('      raise EHTTPCallError.Create(');
  Lines.Add('        ' + PascalStrLit('HTTP call to "' + ApiName + '" failed: ') + ' + _ErrMsg);');
  Lines.Add('    end;');

  if IsFunction then
  begin
    DeserializeExpr := ABI_Type_To_Deserialize_Expr(ReturnType);
    Lines.Add('');
    Lines.Add('    Result := ' + DeserializeExpr + ';');
  end;

  Lines.Add('  finally');
  Lines.Add('    _RespJo.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// =============================================================================
// CALL-UNIT GENERATOR
// =============================================================================

function GenerateHTTPCallPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, DefaultBaseUrl: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;

  HeaderLines, InterfaceLines, DeclLines, ImplLines: TPascalStringList;
  ResultLines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  // The default base URL points to the local bridge, with the source
  // unit's name as the target application. The user is expected to
  // change the host / port, and optionally the app name, before use.
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceLines := TPascalStringList.Create;
  DeclLines := TPascalStringList.Create;
  ImplLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // -------------------------------------------------------------------------
    // 1. Unit header
    // -------------------------------------------------------------------------
    HeaderLines.Add('unit ' + NormalizedUnit + '_http_json_call_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('// Auto-generated by http_pas_abi_call_generator_tool.');
    HeaderLines.Add('// Source model unit: ' + UnitName.Text + '.');
    HeaderLines.Add('// Do not edit by hand unless you know what you are doing.');
    HeaderLines.Add('//');
    HeaderLines.Add('// Wire protocol (HTTP/JSON path):');
    HeaderLines.Add('//   request  = JSON object');
    HeaderLines.Add('//              { "args": [v1, v2, ...] }     positional arguments');
    HeaderLines.Add('//   response = JSON object');
    HeaderLines.Add('//              { "code": 0,  "result": ... }  on success');
    HeaderLines.Add('//              { "code": -1, "error":  ... }  on failure');
    HeaderLines.Add('//');
    HeaderLines.Add('// Requests are sent through the LingoFuse HTTP bridge via');
    HeaderLines.Add('// lf_http_bridge_client.LFHttpPost. The bridge (bridge.py) translates');
    HeaderLines.Add('// the request into an LingoFuse Call and routes it to the target');
    HeaderLines.Add('// HTTP/JSON service.');
    HeaderLines.Add('//');
    HeaderLines.Add('// IMPORTANT: set HTTP_CALL_BASE_URL before calling any generated');
    HeaderLines.Add('// function. The full URL for API "X" is:');
    HeaderLines.Add('//   HTTP_CALL_BASE_URL + ''/'' + ''X''');
    HeaderLines.Add('');
    HeaderLines.Add('{$ifdef FPC}');
    HeaderLines.Add('  {$mode delphi}{$H+}');
    HeaderLines.Add('  {$MODESWITCH NestedProcVars}');
    HeaderLines.Add('  {$modeswitch advancedrecords}');
    HeaderLines.Add('  {$CODEPAGE UTF8}');
    HeaderLines.Add('{$endif}');
    HeaderLines.Add('{$R-}{$I-}{$Q-}{$B-}');
    HeaderLines.Add('');
    HeaderLines.Add('interface');
    HeaderLines.Add('');

    // -------------------------------------------------------------------------
    // 2. Interface section
    //
    // The uses clause mirrors lf_http_bridge_client.pas plus the client
    // unit itself. This is the canonical dependency set for any Pascal
    // consumer of the HTTP bridge.
    // -------------------------------------------------------------------------
    InterfaceLines.Add('uses');
    InterfaceLines.Add('  SysUtils,');
    InterfaceLines.Add('  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib,');
    InterfaceLines.Add('  Z.Json,');
    InterfaceLines.Add('  lingofuse_import,');
    InterfaceLines.Add('  lf_http_bridge_client;');
    InterfaceLines.Add('');
    InterfaceLines.Add('type');
    InterfaceLines.Add('  // Raised when a remote HTTP/JSON call fails: transport error,');
    InterfaceLines.Add('  // bridge error, missing response body, or a non-zero "code" in');
    InterfaceLines.Add('  // the response body.');
    InterfaceLines.Add('  EHTTPCallError = class(Exception);');
    InterfaceLines.Add('');
    InterfaceLines.Add('var');
    InterfaceLines.Add('  // Base URL prefix of the target service. The full URL for API "X"');
    InterfaceLines.Add('  // is HTTP_CALL_BASE_URL + ''/'' + ''X''.');
    InterfaceLines.Add('  //');
    InterfaceLines.Add('  // The default points at the local LingoFuse bridge, with the');
    InterfaceLines.Add('  // source unit''s name as the target application.');
    InterfaceLines.Add('  //');
    InterfaceLines.Add('  // Example: ''http://127.0.0.1:8081/' + NormalizedUnit + '''');
    InterfaceLines.Add('  HTTP_CALL_BASE_URL: string = ' + PascalStrLit(DefaultBaseUrl) + ';');
    InterfaceLines.Add('');

    // -------------------------------------------------------------------------
    // 3. Typed call function declarations
    // -------------------------------------------------------------------------
    DeclLines.Add('// ---------------------------------------------------------------------');
    DeclLines.Add('// Typed HTTP/JSON call functions');
    DeclLines.Add('// ---------------------------------------------------------------------');
    DeclLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitFunctionDecl(DeclLines, ApiName, F.IsFunction, F.Params, F.ReturnType);
    end;

    DeclLines.Add('');

    // -------------------------------------------------------------------------
    // 4. Typed call function definitions
    // -------------------------------------------------------------------------
    ImplLines.Add('{$Region ''typed_call_''}');
    ImplLines.Add('// ---------------------------------------------------------------------');
    ImplLines.Add('// Typed HTTP/JSON call bodies');
    ImplLines.Add('// ---------------------------------------------------------------------');
    ImplLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];

      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);

      EmitFunctionDef(ImplLines, ApiName, F.IsFunction, F.Params, F.ReturnType);
    end;

    ImplLines.Add('{$EndRegion ''typed_call_''}');
    ImplLines.Add('');

    // -------------------------------------------------------------------------
    // 5. Assemble
    // -------------------------------------------------------------------------
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(InterfaceLines);
    ResultLines.AddStrings(DeclLines);
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(ImplLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.', [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    InterfaceLines.Free;
    DeclLines.Free;
    ImplLines.Free;
    UsedApiNames.Free;
    // ResultLines is returned to the caller; not freed here.
  end;
end;

// =============================================================================
// CALL-SIDE README GENERATOR
// =============================================================================
//
// Produces a Markdown document that describes the generated call-side
// unit. The document is deliberately parallel to the service-side
// README produced by http_pas_abi_service_generator_tool, but the
// viewpoint is inverted: this README is written for the CALLER.
//
// The document is also designed to be consumed by AI agents: chapter 13
// provides a machine-readable summary of the outbound request /
// inbound response contract, a list of common anti-patterns, and a
// decision tree.
// =============================================================================

function GenerateHTTPCallPascalReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, DefaultBaseUrl, AppName: TP_String;
  Lines: TPascalStringList;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams, MaxParamCount: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamJsonType: TP_String;
  FullDecl: TP_String;
  CallFileName, ServiceFileName, JsFileName, HtmlFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPascalReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPascalReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  // The default base URL points at the local bridge, with the source
  // unit's name as the target application. This is the value the
  // generated unit assigns to HTTP_CALL_BASE_URL at unit load time.
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  // The target app name is taken from the source unit name, which is
  // the convention used by the service-side generator and by bridge.py
  // when no --app override is given.
  AppName := NormalizedUnit;

  CallFileName := NormalizedUnit + '_http_json_call_unit.pas';
  ServiceFileName := NormalizedUnit + '_http_json_service_unit.pas';
  JsFileName := NormalizedUnit + '_http_json_call.js';
  HtmlFileName := NormalizedUnit + '_http_json_call_test.html';

  Log(PFormat('Generating HTTP/JSON call README for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  FuncCount := Length(SupportedFuncs);

  // Compute a few summary statistics used in the header.
  TotalParams := 0;
  MaxParamCount := 0;
  for i := 0 to FuncCount - 1 do
  begin
    TotalParams := TotalParams + Length(SupportedFuncs[i].Params);
    if Length(SupportedFuncs[i].Params) > MaxParamCount then
      MaxParamCount := Length(SupportedFuncs[i].Params);
  end;

  // Count how many routines are overloads of the same original name.
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
  try
    // =========================================================================
    // Header block
    // =========================================================================
    Lines.Add('# ' + UnitName.Text + ' - Pascal HTTP/JSON Call-Side Wrapper');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_pas_abi_call_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Call unit file**    : `' + CallFileName.Text + '`');
    Lines.Add('> **Target App name**   : `' + AppName.Text + '`');
    Lines.Add('> **Exposed functions** : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('> **Audience**: human engineers and AI assistants who need to');
    Lines.Add('> call the remote HTTP/JSON service without reading the source.');
    Lines.Add('>');
    Lines.Add('> **Language note**: the prose of this README is English. The');
    Lines.Add('> `Description` fields under each API (see §9) reproduce the');
    Lines.Add('> original source comment verbatim, so their language is whatever');
    Lines.Add('> the source unit used. This is intentional and does not affect');
    Lines.Add('> the machine-readable parts of the contract.');
    Lines.Add('>');
    Lines.Add('> **AI agents**: jump straight to §13 "For AI Agents" for a');
    Lines.Add('> compact, machine-readable summary of the outbound request /');
    Lines.Add('> inbound response contract, common anti-patterns, and a');
    Lines.Add('> decision tree.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // =========================================================================
    // 1. Overview
    // =========================================================================
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **call-side wrapper** that was');
    Lines.Add('generated from the Pascal unit `' + UnitName.Text + '`. The unit');
    Lines.Add('exposes one typed Pascal function per supported routine in the');
    Lines.Add('source. Each generated function sends an HTTP POST request to a');
    Lines.Add('remote HTTP/JSON service via the LingoFuse HTTP bridge');
    Lines.Add('(`bridge.py`), parses the response, and returns the result as a');
    Lines.Add('native Pascal value.');
    Lines.Add('');
    Lines.Add('### 1.1 What is an HTTP/JSON call-side wrapper?');
    Lines.Add('');
    Lines.Add('An HTTP/JSON call-side wrapper is a Pascal unit that:');
    Lines.Add('');
    Lines.Add('- exposes one typed free function per remote API;');
    Lines.Add('- serializes the function''s arguments into a JSON request body;');
    Lines.Add('- sends the request over the LingoFuse HTTP bridge;');
    Lines.Add('- deserializes the JSON response into a native Pascal value;');
    Lines.Add('- raises a single exception type on any failure.');
    Lines.Add('');
    Lines.Add('The wrapper is the exact counterpart of the service unit produced');
    Lines.Add('by `http_pas_abi_service_generator_tool.pas`. Both are generated');
    Lines.Add('from the same `TPascal_Func_Model`, so their wire contracts');
    Lines.Add('cannot drift.');
    Lines.Add('');
    Lines.Add('### 1.2 Design principles');
    Lines.Add('');
    Lines.Add('The call-side wrapper is designed around four properties:');
    Lines.Add('');
    Lines.Add('| Property | Value |');
    Lines.Add('|----------|-------|');
    Lines.Add('| Call style | Typed free functions |');
    Lines.Add('| Encoding | Plain-text JSON |');
    Lines.Add('| Transport | HTTP via bridge.py |');
    Lines.Add('| Error model | Single exception type (`EHTTPCallError`) |');
    Lines.Add('| Overhead | Medium: JSON parse/emit + HTTP round trip |');
    Lines.Add('| Ideal for | Cross-language, browser-facing, low-volume RPC |');
    Lines.Add('');
    Lines.Add('### 1.3 Three-step quick start');
    Lines.Add('');
    Lines.Add('1. **Prepare LingoFuse** in your program: call');
    Lines.Add('   `LF_ResetPrepare`, `LF_PrepareClient`, then `LF_PrepareDone`.');
    Lines.Add('   See §7 and §8.');
    Lines.Add('2. **Set the target URL**: assign `HTTP_CALL_BASE_URL` to the');
    Lines.Add('   bridge''s base URL plus the target app name.');
    Lines.Add('3. **Call a generated function**: `Add(3, 4)` returns `7`, or');
    Lines.Add('   raises `EHTTPCallError`.');
    Lines.Add('');
    Lines.Add('### 1.4 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + CallFileName.Text + '` | The call unit (compile into your client program). |');
    Lines.Add('| `' + ServiceFileName.Text + '` | The paired service unit (compile into the server program). |');
    Lines.Add('| `' + JsFileName.Text + '` | Optional browser-side JavaScript client (no deps). |');
    Lines.Add('| `' + HtmlFileName.Text + '` | Optional self-contained HTML test page. |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_call_pascal.md` | This README. |');
    Lines.Add('');

    // =========================================================================
    // 2. Application scope
    // =========================================================================
    Lines.Add('## 2. Application Scope');
    Lines.Add('');
    Lines.Add('### 2.1 When to use this call-side wrapper');
    Lines.Add('');
    Lines.Add('Use this generator when:');
    Lines.Add('');
    Lines.Add('- You have a Pascal client program that needs to call a Pascal');
    Lines.Add('  service through the LingoFuse HTTP bridge.');
    Lines.Add('- You want **static type checking** on every remote call;');
    Lines.Add('  the generated functions have real Pascal signatures.');
    Lines.Add('- You want **compile-time validation** of argument counts and');
    Lines.Add('  types, instead of runtime JSON assembly.');
    Lines.Add('- You control both sides and can regenerate the wrapper when');
    Lines.Add('  the service signature changes.');
    Lines.Add('');
    Lines.Add('Typical use cases:');
    Lines.Add('');
    Lines.Add('- A desktop Pascal client calling a server-side Pascal service.');
    Lines.Add('- A test harness that exercises the service end to end.');
    Lines.Add('- A migration tool that speaks both Pascal and HTTP/JSON.');
    Lines.Add('');
    Lines.Add('### 2.2 When NOT to use this call-side wrapper');
    Lines.Add('');
    Lines.Add('- Your callers are **not Pascal**. Use the JS generator or');
    Lines.Add('  write the HTTP client directly.');
    Lines.Add('- You need **maximum throughput**: the JSON + HTTP round trip');
    Lines.Add('  is slower than a direct LingoFuse call.');
    Lines.Add('- The API surface changes **without a rebuild**. In that case');
    Lines.Add('  use `TZ_JsonObject` directly to assemble requests.');
    Lines.Add('- Your callers are **other LingoFuse nodes only**. Direct');
    Lines.Add('  LingoFuse calls avoid the HTTP hop entirely.');
    Lines.Add('');
    Lines.Add('### 2.3 Comparison with other calling approaches');
    Lines.Add('');
    Lines.Add('| Approach | Typed | Text | Compile-checked | Requires codegen |');
    Lines.Add('|----------|:-----:|:----:|:---------------:|:----------------:|');
    Lines.Add('| This call-side wrapper | yes | yes | yes | yes (regenerate) |');
    Lines.Add('| Manual `LFHttpPost` calls | no | yes | no | no |');
    Lines.Add('| Binary ABI call unit | yes | no | yes | yes (regenerate) |');
    Lines.Add('| Direct `curl` subprocess | no | yes | no | no |');
    Lines.Add('');

    // =========================================================================
    // 3. Compatibility
    // =========================================================================
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('### 3.1 Compiler support');
    Lines.Add('');
    Lines.Add('| Compiler | Minimum version | Notes |');
    Lines.Add('|----------|-----------------|-------|');
    Lines.Add('| Free Pascal (FPC) | 3.2.0 | Preferred; tested on 3.2.2. |');
    Lines.Add('| Delphi | 10.4 (Sydney) | Also works with 11 and 12. |');
    Lines.Add('');
    Lines.Add('The generated unit uses `{$DEFINE FPC_DELPHI_MODE}`, so the same');
    Lines.Add('source compiles under both compilers without modification.');
    Lines.Add('');
    Lines.Add('### 3.2 FPC cross-platform support');
    Lines.Add('');
    Lines.Add('FPC is a cross-platform compiler. This call unit works on every');
    Lines.Add('platform where the LingoFuse runtime and the bridge are available.');
    Lines.Add('');
    Lines.Add('| Platform | Architecture | Status |');
    Lines.Add('|----------|-------------|--------|');
    Lines.Add('| Windows | x86_64 | Primary target |');
    Lines.Add('| Windows | i386 | Supported |');
    Lines.Add('| Linux | x86_64 | Supported |');
    Lines.Add('| Linux | aarch64 | Supported |');
    Lines.Add('| macOS | x86_64 | Supported |');
    Lines.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    Lines.Add('| FreeBSD | x86_64 | Community-tested |');
    Lines.Add('');
    Lines.Add('### 3.3 Runtime dependencies');
    Lines.Add('');
    Lines.Add('| Dependency | Where to get it |');
    Lines.Add('|------------|----------------|');
    Lines.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    Lines.Add('| `lingofuse_import.pas` | LingoFuse-pasAgent source tree |');
    Lines.Add('| `lf_http_bridge_client.pas` | LingoFuse-pasAgent source tree |');
    Lines.Add('| `Z.Core` unit | ZNetV2/ZCore |');
    Lines.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | ZNetV2 binary distribution |');
    Lines.Add('| `bridge.py` | LingoFuse Python package |');
    Lines.Add('| Python 3.7+ and Flask | bridge.py runtime |');
    Lines.Add('');
    Lines.Add('### 3.4 Character encoding');
    Lines.Add('');
    Lines.Add('- **Source files**: UTF-8, no BOM required.');
    Lines.Add('- **JSON payloads**: UTF-8, both directions.');
    Lines.Add('- **FPC**: always add `{$CODEPAGE UTF8}` when the source contains');
    Lines.Add('  non-ASCII literals.');
    Lines.Add('- **Delphi**: add `{$HIGHCHARUNICODE ON}` if you need Unicode');
    Lines.Add('  literals in the source.');
    Lines.Add('');
    Lines.Add('### 3.5 Threading model');
    Lines.Add('');
    Lines.Add('A generated function performs a synchronous call: it blocks the');
    Lines.Add('calling thread until the bridge returns a response. From a');
    Lines.Add('background worker thread this is fine. From the main thread it');
    Lines.Add('will freeze the UI for the duration of the call.');
    Lines.Add('');
    Lines.Add('For asynchronous behaviour, wrap each call in a dedicated');
    Lines.Add('worker thread, e.g. `TThread.CreateAnonymousThread(...).Start`.');
    Lines.Add('');

    // =========================================================================
    // 4. Wire protocol
    // =========================================================================
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The call-side wrapper speaks **plain-text JSON** in both');
    Lines.Add('directions, transported over HTTP by the bridge.');
    Lines.Add('');
    Lines.Add('### 4.1 URL composition');
    Lines.Add('');
    Lines.Add('Every generated function composes its target URL as:');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('HTTP_CALL_BASE_URL + ''/'' + <api-name>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('`HTTP_CALL_BASE_URL` is a unit-level `string` variable, set once');
    Lines.Add('by the caller before any generated function is invoked. Its');
    Lines.Add('default value points at the local bridge:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('HTTP_CALL_BASE_URL := ' + PascalStrLit(DefaultBaseUrl) + ';');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The bridge expects the path to be `/<app>/<api>`. The default');
    Lines.Add('base URL already contains the `/<app>` segment, so the generated');
    Lines.Add('functions only append the `/<api>` part.');
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
    Lines.Add('There is no named-argument form on the outbound path: the');
    Lines.Add('generated function always builds the positional array.');
    Lines.Add('');
    Lines.Add('### 4.3 Inbound response');
    Lines.Add('');
    Lines.Add('The service responds with a JSON object. The bridge wraps it in');
    Lines.Add('an envelope before returning it to the caller:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "status_code": 200,');
    Lines.Add('  "headers":     { "content-type": "application/json", ... },');
    Lines.Add('  "body":        { "code": 0, "result": <value> }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated function unwraps the `body` field and inspects its');
    Lines.Add('`code` field:');
    Lines.Add('');
    Lines.Add('- `code = 0` -> returns `body.result` converted to the declared');
    Lines.Add('  Pascal return type (or nothing, for procedures).');
    Lines.Add('- `code <> 0` -> raises `EHTTPCallError` with `body.error`.');
    Lines.Add('');
    Lines.Add('### 4.4 Error model');
    Lines.Add('');
    Lines.Add('Three distinct error conditions can arise:');
    Lines.Add('');
    Lines.Add('| Condition | Detected by | Raised exception |');
    Lines.Add('|-----------|-------------|------------------|');
    Lines.Add('| Bridge unreachable | `LFHttpPost` returns False | `EHTTPCallError` |');
    Lines.Add('| Bridge envelope missing `body` | `_RespJo.Exists` | `EHTTPCallError` |');
    Lines.Add('| Service returned `code <> 0` | `_InnerJo.I[''code'']` | `EHTTPCallError` |');
    Lines.Add('');
    Lines.Add('All three collapse into the same exception type. The exception');
    Lines.Add('message carries the specific cause.');
    Lines.Add('');
    Lines.Add('### 4.5 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant P as Pascal Client');
    Lines.Add('    participant C as Call Unit');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant S as Remote Service');
    Lines.Add('    P->>C: Add(3, 4)');
    Lines.Add('    C->>C: build {"args": [3, 4]}');
    Lines.Add('    C->>B: HTTP POST /<app>/Add');
    Lines.Add('    B->>S: LF_Call with JSON payload');
    Lines.Add('    S->>S: parse JSON, execute');
    Lines.Add('    S-->>B: {"code": 0, "result": 7}');
    Lines.Add('    B-->>C: HTTP 200 envelope');
    Lines.Add('    C->>C: unwrap body, check code');
    Lines.Add('    C-->>P: 7');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.6 Error response example');
    Lines.Add('');
    Lines.Add('If the remote service raises an exception, the bridge returns:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "status_code": 200,');
    Lines.Add('  "headers":     { ... },');
    Lines.Add('  "body":        { "code": -1, "error": "Division by zero" }');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The generated function detects `code <> 0` and raises:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('EHTTPCallError: HTTP call to "Add" failed: Division by zero');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 5. Runtime architecture
    // =========================================================================
    Lines.Add('## 5. Runtime Architecture');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    subgraph Client["Client process"]');
    Lines.Add('        C_LF["LF_PrepareClient(endpoint, nil)"]');
    Lines.Add('        C_RUN["LF_PrepareDone()"]');
    Lines.Add('        C_URL["HTTP_CALL_BASE_URL := ''...''"]');
    Lines.Add('        C_CALL["Add(3, 4)"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    subgraph Bridge["Bridge process (bridge.py)"]');
    Lines.Add('        B_HTTP["HTTP listen"]');
    Lines.Add('        B_LF["LF_Call to target app"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    subgraph Server["Service process"]');
    Lines.Add('        S_RUN["Service app ready"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    C_LF --> C_RUN');
    Lines.Add('    C_RUN --> C_URL');
    Lines.Add('    C_URL --> C_CALL');
    Lines.Add('    C_CALL -. "HTTP POST" .-> B_HTTP');
    Lines.Add('    B_HTTP --> B_LF');
    Lines.Add('    B_LF -. "LF_Call" .-> S_RUN');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 5.1 Startup sequence');
    Lines.Add('');
    Lines.Add('**Client process:**');
    Lines.Add('');
    Lines.Add('1. `LF_ResetPrepare`');
    Lines.Add('2. `LF_PrepareClient(<endpoint>, nil)`');
    Lines.Add('3. `LF_PrepareDone`');
    Lines.Add('4. `HTTP_CALL_BASE_URL := ''http://.../<app>''`');
    Lines.Add('5. Call any generated function.');
    Lines.Add('');
    Lines.Add('**Bridge and service processes** must already be running when');
    Lines.Add('the client makes its first call. The bridge must be started with');
    Lines.Add('the correct `--endpoint`, matching the service.');
    Lines.Add('');
    Lines.Add('### 5.2 Invocation sequence');
    Lines.Add('');
    Lines.Add('1. The client calls a generated function, e.g. `Add(3, 4)`.');
    Lines.Add('2. The function composes the URL and builds `{"args": [3, 4]}`.');
    Lines.Add('3. `LFHttpPost` sends the request through the LingoFuse bridge.');
    Lines.Add('4. The bridge translates the HTTP request into a LingoFuse call');
    Lines.Add('   and routes it to the target service.');
    Lines.Add('5. The service executes, produces a JSON response, and returns');
    Lines.Add('   it to the bridge.');
    Lines.Add('6. The bridge wraps the response in its standard envelope and');
    Lines.Add('   returns it to the caller as an HTTP response.');
    Lines.Add('7. The generated function unwraps the envelope, checks `code`,');
    Lines.Add('   and either returns the result or raises `EHTTPCallError`.');
    Lines.Add('');
    Lines.Add('### 5.3 Threading notes');
    Lines.Add('');
    Lines.Add('- Generated functions are **synchronous** and **blocking**.');
    Lines.Add('- They can be called from any thread.');
    Lines.Add('- `LFHttpPost` itself is thread-safe.');
    Lines.Add('- For UI code, wrap the call in a worker thread.');
    Lines.Add('- `HTTP_CALL_BASE_URL` is a plain `string` variable with no');
    Lines.Add('  synchronisation. Set it **once** at startup, before any call.');
    Lines.Add('  If you must change it at runtime, protect the assignment with');
    Lines.Add('  your own lock.');
    Lines.Add('');

    // =========================================================================
    // 6. Type mapping
    // =========================================================================
    Lines.Add('## 6. Type Mapping');
    Lines.Add('');
    Lines.Add('### 6.1 The key fact: JSON has fewer types than the binary ABI');
    Lines.Add('');
    Lines.Add('The binary ABI preserves integer widths on the wire: an');
    Lines.Add('`Integer` takes 4 bytes, an `Int64` takes 8 bytes, and so on.');
    Lines.Add('The HTTP/JSON protocol does **NOT**. On the wire, every integer');
    Lines.Add('family member is a single JSON `number`, and every string family');
    Lines.Add('member is a single JSON `string`.');
    Lines.Add('');
    Lines.Add('Consequences for callers:');
    Lines.Add('');
    Lines.Add('- The wrapper will **deserialize** any JSON number into the');
    Lines.Add('  declared Pascal integer type, silently truncating if the');
    Lines.Add('  remote value does not fit.');
    Lines.Add('- A JSON client cannot distinguish an `Integer` field from an');
    Lines.Add('  `Int64` field by inspecting the wire bytes.');
    Lines.Add('- JavaScript Numbers are IEEE-754 doubles and cannot represent');
    Lines.Add('  every 64-bit integer exactly. The bridge preserves precision,');
    Lines.Add('  but a browser using `JSON.parse` will not.');
    Lines.Add('');
    Lines.Add('### 6.2 Supported Pascal types and their JSON wire form');
    Lines.Add('');
    Lines.Add('Every parameter and return type of every generated function is');
    Lines.Add('in this table.');
    Lines.Add('');
    Lines.Add('| ABI type | Pascal type | JSON wire type |');
    Lines.Add('|----------|-------------|----------------|');
    Lines.Add('| `integer` | `Integer` | `number` |');
    Lines.Add('| `longint` | `LongInt` | `number` |');
    Lines.Add('| `int64` | `Int64` | `number` |');
    Lines.Add('| `cardinal` | `Cardinal` | `number` |');
    Lines.Add('| `dword` | `DWord` | `number` |');
    Lines.Add('| `longword` | `LongWord` | `number` |');
    Lines.Add('| `word` | `Word` | `number` |');
    Lines.Add('| `smallint` | `SmallInt` | `number` |');
    Lines.Add('| `byte` | `Byte` | `number` |');
    Lines.Add('| `uint64` | `UInt64` | `number` |');
    Lines.Add('| `double` | `Double` | `number` |');
    Lines.Add('| `single` | `Single` | `number` |');
    Lines.Add('| `extended` | `Extended` | `number` |');
    Lines.Add('| `real` | `Real` | `number` |');
    Lines.Add('| `string` | `string` | `string` |');
    Lines.Add('| `ansistring` | `string` | `string` |');
    Lines.Add('| `unicodestring` | `string` | `string` |');
    Lines.Add('| `tpascalstring` | `string` | `string` |');
    Lines.Add('| `tupascalstring` | `string` | `string` |');
    Lines.Add('| `tp_string` | `string` | `string` |');
    Lines.Add('| `pchar` | `string` | `string` |');
    Lines.Add('| `pansichar` | `string` | `string` |');
    Lines.Add('| `pwidechar` | `string` | `string` |');
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
    Lines.Add('**Workaround**: on the caller side, serialize complex values');
    Lines.Add('into a `string` first (JSON or a custom string format), and');
    Lines.Add('pass the string as a normal `string` argument. The service');
    Lines.Add('decodes it on its side.');
    Lines.Add('');
    Lines.Add('### 6.4 Integer width and truncation');
    Lines.Add('');
    Lines.Add('Because JSON numbers are unbounded on the wire, but Pascal');
    Lines.Add('integers are not, the wrapper uses the widest fitting type');
    Lines.Add('(`Int64`) for every integer argument on the outbound side, and');
    Lines.Add('narrows on the inbound side using the declared return type.');
    Lines.Add('');
    Lines.Add('Example: a remote service returns `99999` for an API whose');
    Lines.Add('declared return type is `Word` (max 65535). The wrapper');
    Lines.Add('truncates without warning. Callers that need bounds checking');
    Lines.Add('must verify on the service side before returning.');
    Lines.Add('');

    // =========================================================================
    // 7. Deployment
    // =========================================================================
    Lines.Add('## 7. Deployment');
    Lines.Add('');
    Lines.Add('### 7.1 Directory layout');
    Lines.Add('');
    Lines.Add('Place the generated call unit next to your LingoFuse runtime.');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('my_http_json_client/');
    Lines.Add('  ' + CallFileName.Text + '         <- generated (described here)');
    Lines.Add('  <UnitName>_client.lpr                     <- your client entry point');
    Lines.Add('  ZNetV2/');
    Lines.Add('    ZCore/');
    Lines.Add('      Z.Core.pas');
    Lines.Add('    lingofuse_import.pas');
    Lines.Add('    lingofuse_helper.pas');
    Lines.Add('    lf_http_bridge_client.pas');
    Lines.Add('    z_ipc_64.dll                            <- Windows');
    Lines.Add('    libz_ipc_64.so                          <- Linux');
    Lines.Add('  LingoFuse64.dll                           <- Windows');
    Lines.Add('  liblingofuse.so                           <- Linux');
    Lines.Add('  liblingofuse.dylib                        <- macOS');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.2 FPC build');
    Lines.Add('');
    Lines.Add('Compile the client:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('fpc -FuZNetV2 -FuZNetV2/ZCore ' + NormalizedUnit.Text + '_client.lpr');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Both `-Fu` paths must be included. Missing either one causes');
    Lines.Add('"Can''t find unit Z.Core" or "Can''t find unit lingofuse_import".');
    Lines.Add('');
    Lines.Add('### 7.3 Delphi build');
    Lines.Add('');
    Lines.Add('1. Add the generated `.pas` file to your Delphi project.');
    Lines.Add('2. Add `ZNetV2` and `ZNetV2\\ZCore` to **Project Options -> Unit');
    Lines.Add('   Directories**.');
    Lines.Add('3. Set the linker search path to include the directory that holds');
    Lines.Add('   `LingoFuse64.dll`.');
    Lines.Add('4. Build.');
    Lines.Add('');
    Lines.Add('### 7.4 Startup order');
    Lines.Add('');
    Lines.Add('Three processes must be running before the client makes its');
    Lines.Add('first call:');
    Lines.Add('');
    Lines.Add('1. **Service** (`<UnitName>_http_json_service_unit` compiled');
    Lines.Add('   into a server). It must be registered at the LingoFuse');
    Lines.Add('   endpoint that bridge.py will use.');
    Lines.Add('2. **Bridge** (`bridge.py`). It must be started with');
    Lines.Add('   `--endpoint <same endpoint>` and must be listening on HTTP.');
    Lines.Add('3. **Client**. It prepares LingoFuse, sets `HTTP_CALL_BASE_URL`,');
    Lines.Add('   then issues calls.');
    Lines.Add('');
    Lines.Add('### 7.5 Client preparation');
    Lines.Add('');
    Lines.Add('The client MUST prepare LingoFuse before its first call. The');
    Lines.Add('minimal sequence is:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('LF_ResetPrepare;');
    Lines.Add('LF_PrepareClient(''<endpoint>'', nil);');
    Lines.Add('if LF_PrepareDone <> 1 then');
    Lines.Add('  Halt(1);');
    Lines.Add('HTTP_CALL_BASE_URL := ''http://127.0.0.1:8081/<app>'';');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Replace `<endpoint>` with the LingoFuse endpoint bridge.py is');
    Lines.Add('connected to. Replace `<app>` with the target app name.');
    Lines.Add('');
    Lines.Add('### 7.6 Runtime files');
    Lines.Add('');
    Lines.Add('At runtime the following files must be reachable from the');
    Lines.Add('client process:');
    Lines.Add('');
    Lines.Add('| File | Where to place it |');
    Lines.Add('|------|-------------------|');
    Lines.Add('| `LingoFuse64.dll` / `liblingofuse.so` | Same directory as the executable, or on `PATH` / `LD_LIBRARY_PATH`. |');
    Lines.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | Same as above. |');
    Lines.Add('');
    Lines.Add('### 7.7 Shutdown');
    Lines.Add('');
    Lines.Add('The recommended shutdown sequence is:');
    Lines.Add('');
    Lines.Add('1. Finish all in-flight calls.');
    Lines.Add('2. `LF_ExitMainThread`');
    Lines.Add('3. `LF_Shutdown`');
    Lines.Add('');
    Lines.Add('Do not skip any step.');
    Lines.Add('');

    // =========================================================================
    // 8. Testing
    // =========================================================================
    Lines.Add('## 8. Testing');
    Lines.Add('');
    Lines.Add('### 8.1 Client program');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('program ' + NormalizedUnit.Text + '_client;');
    Lines.Add('');
    Lines.Add('{$mode objfpc}{$H+}');
    Lines.Add('{$CODEPAGE UTF8}');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  {$IFDEF UNIX}');
    Lines.Add('  cthreads,');
    Lines.Add('  {$ENDIF}');
    Lines.Add('  {$IFDEF MSWINDOWS}');
    Lines.Add('  Windows,');
    Lines.Add('  {$ENDIF}');
    Lines.Add('  SysUtils, Classes,');
    Lines.Add('  Z.Core,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  ' + NormalizedUnit.Text + '_http_json_call_unit;');
    Lines.Add('');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''=== ' + UnitName.Text + ' HTTP/JSON client ==='');');
    Lines.Add('');
    Lines.Add('  LF_ResetPrepare;');
    Lines.Add('  LF_PrepareClient(''ipc:' + NormalizedUnit.Text + '_http_json'', nil);');
    Lines.Add('');
    Lines.Add('  if LF_PrepareDone <> 1 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(''[FATAL] LF_PrepareDone failed'');');
    Lines.Add('    Halt(1);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  // Point the wrapper at the bridge, with the target app name.');
    Lines.Add('  HTTP_CALL_BASE_URL := ' + PascalStrLit(DefaultBaseUrl) + ';');
    Lines.Add('');
    Lines.Add('  try');
    Lines.Add('    // Replace with a real call, e.g.:');
    Lines.Add('    //   WriteLn(''Add(3, 4) = '', Add(3, 4));');
    Lines.Add('  except');
    Lines.Add('    on E: EHTTPCallError do');
    Lines.Add('      WriteLn(''[ERROR] '', E.Message);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  LF_ExitMainThread;');
    Lines.Add('  LF_Shutdown;');
    Lines.Add('end.');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.2 Invoking a specific API');
    Lines.Add('');
    Lines.Add('Every generated function has the exact Pascal signature shown');
    Lines.Add('in §9. Call it directly:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('try');
    Lines.Add('  Result := Add(3, 4);');
    Lines.Add('  WriteLn(''Add(3, 4) = '', Result);');
    Lines.Add('except');
    Lines.Add('  on E: EHTTPCallError do');
    Lines.Add('    WriteLn(''Call failed: '', E.Message);');
    Lines.Add('end;');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.3 Verifying failure paths');
    Lines.Add('');
    Lines.Add('Three failure modes are worth testing explicitly:');
    Lines.Add('');
    Lines.Add('1. **Bridge unreachable**: stop `bridge.py` and call any API.');
    Lines.Add('   Expect `EHTTPCallError` with a message starting');
    Lines.Add('   `HTTP call to "..." failed:` followed by the bridge''s error.');
    Lines.Add('');
    Lines.Add('2. **Service-side exception**: call an API whose implementation');
    Lines.Add('   raises. Expect `EHTTPCallError` with the exception message.');
    Lines.Add('');
    Lines.Add('3. **Unknown API**: call a name that does not exist. The bridge');
    Lines.Add('   returns `{ "code": -3, ... }`; expect `EHTTPCallError` with');
    Lines.Add('   the `-3` message.');
    Lines.Add('');
    Lines.Add('### 8.4 Isolated call testing (no LingoFuse deployment)');
    Lines.Add('');
    Lines.Add('If the remote service is not yet available, you can still test');
    Lines.Add('the wrapper''s URL composition and JSON assembly by pointing');
    Lines.Add('`HTTP_CALL_BASE_URL` at any HTTP server that echoes the request');
    Lines.Add('body. A one-line Python listener is usually enough:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 -m http.server 8081');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('This returns a directory listing rather than a JSON response,');
    Lines.Add('so `EHTTPCallError` will be raised. But it confirms that the');
    Lines.Add('outbound HTTP path is reachable, and you can inspect the');
    Lines.Add('request in the server log.');
    Lines.Add('');
    Lines.Add('For a full round-trip test, use the HTML test page generated by');
    Lines.Add('`http_js_abi_call_generator_tool.pas` (see `' + HtmlFileName.Text + '`), which exercises the same service from the browser.');
    Lines.Add('');

    // =========================================================================
    // 9. API reference
    // =========================================================================
    Lines.Add('## 9. API Reference');
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
      // ----- §9.0 Overloads and disambiguation -----
      if DuplicateNameCount > 0 then
      begin
        Lines.Add('### 9.0 Overloads and disambiguation');
        Lines.Add('');
        Lines.Add('The source unit exposes overloaded routines: the same Pascal');
        Lines.Add('name with two or more distinct signatures. The HTTP/JSON');
        Lines.Add('protocol routes by API name, so two overloads cannot both keep');
        Lines.Add('the original name. The generator appends a numeric suffix');
        Lines.Add('(`_1`, `_2`, ...) to every overload after the first.');
        Lines.Add('');
        Lines.Add('The mapping is deterministic:');
        Lines.Add('');
        Lines.Add('- The **first** overload in source order keeps the bare name.');
        Lines.Add('- Each subsequent overload gets `_N`, where `N` starts at 1 and');
        Lines.Add('  increments for every additional overload.');
        Lines.Add('- The `.0` suffix never appears.');
        Lines.Add('');
        Lines.Add('The "Original declaration" line under each of the following');
        Lines.Add('sections shows the true Pascal signature, so you can always');
        Lines.Add('reconstruct which overload is which.');
        Lines.Add('');
      end;

      Lines.Add('### 9.1 Summary');
      Lines.Add('');
      Lines.Add('| # | Function name | Kind | Params | Return | Description |');
      Lines.Add('|---|---------------|------|--------|--------|-------------|');

      UsedApiNames.Clear;
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];

        ApiName := MakeApiName(F.Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        Description := GetFullDescription(F.Comment);
        if Description.Len = 0 then
          Description := '';

        if F.IsFunction then
          FullDecl := ABI_Type_To_Pascal_Decl(F.ReturnType)
        else
          FullDecl := '-';

        Lines.Add('| ' + MdInt(i + 1).Text + ' | ' + MdCellEscape(ApiName).Text + ' | ' + if_(F.IsFunction, 'function', 'procedure') +
          ' | ' + MdInt(Length(F.Params)).Text + ' | ' + MdCellEscape(FullDecl).Text + ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      // ----- Per-API sections -----
      UsedApiNames.Clear;
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];

        ApiName := MakeApiName(F.Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        HasParams := Length(F.Params) > 0;

        Lines.Add('### 9.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');

        // Full generated Pascal signature. This is what the caller
        // will actually write in his or her code.
        Lines.Add('- **Generated call signature**: `' + BuildFullDecl(F, ApiName) + '`');
        Lines.Add('- **Original declaration**: `' + BuildFullDecl(F, F.Name) + '`');
        Lines.Add('- **Kind**: ' + if_(F.IsFunction, 'function', 'procedure'));
        Lines.Add('- **HTTP route**: `POST /' + AppName.Text + '/' + ApiName.Text + '`');
        Lines.Add('- **Raises**: `EHTTPCallError` on any failure');
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
          Lines.Add('| # | Name | Pascal type | JSON wire type |');
          Lines.Add('|---|------|-------------|----------------|');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafePascalIdent(F.Params[j].Name, j);
            ParamType := ABI_Type_To_Pascal_Decl(F.Params[j].PascalType);
            ParamJsonType := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);

            Lines.Add('| ' + MdInt(j + 1).Text + ' | ' + MdCellEscape(ParamName).Text + ' | `' + MdCellEscape(ParamType).Text +
              '`' + ' | `' + MdCellEscape(ParamJsonType).Text + '` |');
          end;
          Lines.Add('');
        end;

        Lines.Add('#### Outbound request body');
        Lines.Add('');
        Lines.Add('```json');
        if HasParams then
          Lines.Add('{ "args": [' + BuildCallArgList(F.Params) + '] }')
        else
          Lines.Add('{ "args": [] }');
        Lines.Add('```');
        Lines.Add('');

        Lines.Add('#### Inbound result');
        Lines.Add('');
        if F.IsFunction then
        begin
          Lines.Add('The function returns the value of `body.result` converted to `' + ABI_Type_To_Pascal_Decl(F.ReturnType) + '`.');
        end
        else
        begin
          Lines.Add('The function returns nothing. The service''s `body` field');
          Lines.Add('contains only `{"code": 0}`.');
        end;
        Lines.Add('');

        Lines.Add('#### Failure');
        Lines.Add('');
        Lines.Add('```pascal');
        Lines.Add('try');
        Lines.Add('  ' + if_(F.IsFunction, 'Result := ', '') + ApiName.Text + '(' + BuildCallArgList(F.Params) + ');');
        Lines.Add('except');
        Lines.Add('  on E: EHTTPCallError do');
        Lines.Add('    WriteLn(''Call failed: '', E.Message);');
        Lines.Add('end;');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    // =========================================================================
    // 10. Troubleshooting
    // =========================================================================
    Lines.Add('## 10. Troubleshooting');
    Lines.Add('');
    Lines.Add('### 10.1 Symptom, cause, fix');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| `EHTTPCallError: HTTP call to "..." failed: <bridge msg>` | Bridge not running | Start `bridge.py`. |');
    Lines.Add('| `EHTTPCallError` mentioning `-3` | Bridge pre-check failed | Add `--no-precheck`, or wait ~3 s after the service starts. |');
    Lines.Add('| `EHTTPCallError` mentioning `-2` | URL path could not be parsed | Verify `HTTP_CALL_BASE_URL` ends with `/<app>`. |');
    Lines.Add('| `EHTTPCallError` mentioning `-1` with a service message | Remote service raised an exception | Check the service side log. |');
    Lines.Add('| Function hangs indefinitely | Bridge or service not responding | Verify both processes; check `LF_CheckMainThread`. |');
    Lines.Add('| Return value is truncated | JSON number wider than the declared Pascal type | Widen the return type on the service side. |');
    Lines.Add('| Every call fails immediately with a network error | `HTTP_CALL_BASE_URL` points to the wrong host or port | Fix the value; use `curl` to test the URL first. |');
    Lines.Add('| First call after startup fails but later calls succeed | The bridge has not yet seen the service registration | Add `--no-precheck` to `bridge.py`. |');
    Lines.Add('| `LF_PrepareDone` returned 0 | The main thread is already running | It is not an error; continue. |');
    Lines.Add('');
    Lines.Add('### 10.2 Verifying the client''s LingoFuse state');
    Lines.Add('');
    Lines.Add('Before making any call:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('if LF_CheckMainThread = 0 then');
    Lines.Add('  WriteLn(''LingoFuse main thread is not running'');');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 10.3 Testing the URL without the wrapper');
    Lines.Add('');
    Lines.Add('From a shell, verify that the bridge is reachable at the same');
    Lines.Add('URL the wrapper will use:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('curl -X POST ' + DefaultBaseUrl.Text + '/<api-name> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": [1, 2]}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('If `curl` succeeds, the wrapper will succeed too, because it');
    Lines.Add('uses the same URL and the same request shape.');
    Lines.Add('');
    Lines.Add('### 10.4 Enabling verbose logging');
    Lines.Add('');
    Lines.Add('The wrapper itself has no internal logging. To trace calls, wrap');
    Lines.Add('each invocation manually:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('WriteLn(''Calling Add(3, 4) ...'');');
    Lines.Add('try');
    Lines.Add('  Result := Add(3, 4);');
    Lines.Add('  WriteLn(''  -> '', Result);');
    Lines.Add('except');
    Lines.Add('  on E: EHTTPCallError do');
    Lines.Add('    WriteLn(''  !! '', E.Message);');
    Lines.Add('end;');
    Lines.Add('```');
    Lines.Add('');

    // =========================================================================
    // 11. Self-assessment checklist
    // =========================================================================
    Lines.Add('## 11. Self-Assessment Checklist (for human engineers)');
    Lines.Add('');
    Lines.Add('After reading this document you should be able to answer the');
    Lines.Add('following questions without consulting the source code. If any');
    Lines.Add('answer is unclear, re-read the corresponding section.');
    Lines.Add('');
    Lines.Add('| # | Question | Section |');
    Lines.Add('|---|----------|---------|');
    Lines.Add('| 1 | What does the call-side wrapper expose? | §1 |');
    Lines.Add('| 2 | Why use a wrapper instead of hand-written HTTP? | §2 |');
    Lines.Add('| 3 | Which compilers and platforms are supported? | §3 |');
    Lines.Add('| 4 | What does the wrapper do before the first call? | §5.1 |');
    Lines.Add('| 5 | What does the outbound request body look like? | §4.2 |');
    Lines.Add('| 6 | What does the inbound response body look like? | §4.3 |');
    Lines.Add('| 7 | What exception is raised on failure? | §4.4 |');
    Lines.Add('| 8 | Which JSON wire types are supported? | §6.2 |');
    Lines.Add('| 9 | Why can an integer be truncated? | §6.4 |');
    Lines.Add('| 10 | How are overloaded routines disambiguated? | §9.0 |');
    Lines.Add('| 11 | What is the default value of `HTTP_CALL_BASE_URL`? | §4.1 |');
    Lines.Add('| 12 | How do I write a minimal client program? | §8.1 |');
    Lines.Add('| 13 | How do I invoke a specific API? | §8.2 |');
    Lines.Add('| 14 | What is the shutdown order? | §7.7 |');
    Lines.Add('| 15 | How do I test without the full deployment? | §8.4 |');
    Lines.Add('');
    Lines.Add('If you can answer all of the above, you are ready to use this');
    Lines.Add('wrapper.');
    Lines.Add('');

    // =========================================================================
    // 12. Reference resources
    // =========================================================================
    Lines.Add('## 12. Reference Resources');
    Lines.Add('');
    Lines.Add('| Resource | Purpose |');
    Lines.Add('|----------|---------|');
    Lines.Add('| ZNetV2 repository | LingoFuse runtime bindings |');
    Lines.Add('| ZNetV2/ZCore | Core infrastructure units |');
    Lines.Add('| `lingofuse_import.pas` | Low-level C ABI declarations |');
    Lines.Add('| `lf_http_bridge_client.pas` | Pascal HTTP bridge client |');
    Lines.Add('| `bridge.py` | LingoFuse HTTP bridge |');
    Lines.Add('| `http_pas_abi_service_generator_tool.pas` | Paired service-side generator |');
    Lines.Add('| `http_js_abi_call_generator_tool.pas` | Browser JS call-side generator |');
    Lines.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    Lines.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    Lines.Add('');

    // =========================================================================
    // 13. For AI Agents
    // =========================================================================
    // This chapter is deliberately structured and terse. It is meant
    // to be consumed by an LLM without reading the surrounding
    // narrative. Every fact here is also stated somewhere else in the
    // document; the point is to have a single, machine-friendly
    // summary that an AI can quote back to a user.
    // =========================================================================
    Lines.Add('## 13. For AI Agents');
    Lines.Add('');
    Lines.Add('This chapter is a compact, machine-readable summary of the');
    Lines.Add('contract. Everything here is also stated somewhere else in the');
    Lines.Add('document; this is the version to quote back to a user.');
    Lines.Add('');
    Lines.Add('### 13.1 Contract summary');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('call_side_wrapper:');
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  call_unit_file: ' + CallFileName.Text);
    Lines.Add('  default_base_url: ' + DefaultBaseUrl.Text);
    Lines.Add('  target_app_name: ' + AppName.Text);
    Lines.Add('  exposed_functions: ' + MdInt(FuncCount).Text);
    Lines.Add('');
    Lines.Add('global_configuration:');
    Lines.Add('  variable: HTTP_CALL_BASE_URL');
    Lines.Add('  type: string');
    Lines.Add('  default: ' + DefaultBaseUrl.Text);
    Lines.Add('  usage: composed_url = HTTP_CALL_BASE_URL + "/" + <api-name>');
    Lines.Add('  mutability: set once at startup, before any call');
    Lines.Add('');
    Lines.Add('prerequisites:');
    Lines.Add('  - "LF_PrepareClient(endpoint, nil) must have been called"');
    Lines.Add('  - "LF_PrepareDone must have returned 1"');
    Lines.Add('  - "bridge.py must be listening on the host:port in HTTP_CALL_BASE_URL"');
    Lines.Add('');
    Lines.Add('outbound_request:');
    Lines.Add('  method: POST');
    Lines.Add('  content_type: application/json; charset=utf-8');
    Lines.Add('  body_shape: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('  args_order: matches the parameter order of the Pascal function');
    Lines.Add('');
    Lines.Add('inbound_response:');
    Lines.Add('  envelope_shape: ''{"status_code": ..., "headers": {...}, "body": {...}}''');
    Lines.Add('  body_success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  body_failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('  processing_rule: ''code == 0 -> return result; otherwise raise EHTTPCallError''');
    Lines.Add('');
    Lines.Add('exception:');
    Lines.Add('  type: EHTTPCallError');
    Lines.Add('  base: Exception');
    Lines.Add('  raised_on:');
    Lines.Add('    - "LFHttpPost returned False"');
    Lines.Add('    - "bridge envelope is missing body"');
    Lines.Add('    - "body.code is not 0"');
    Lines.Add('  message_format: ''HTTP call to "<api>" failed: <cause>''');
    Lines.Add('');
    Lines.Add('types:');
    Lines.Add('  json_number: "Integer, Int64, Cardinal, Word, SmallInt, Byte, UInt64, Double, Single, Extended, Real"');
    Lines.Add('  json_string: "string, AnsiString, UnicodeString, TPascalString, TUPascalString, PChar, PAnsiChar, PWideChar"');
    Lines.Add('  unsupported: "Boolean, Variant, arrays, records, classes, interfaces, enums, sets, generics, pointers, Currency, Comp, TDateTime"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 13.2 Anti-patterns');
    Lines.Add('');
    Lines.Add('The following constructs are common mistakes. If you see one in');
    Lines.Add('caller code, it is a bug.');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| Calling a generated function without `LF_PrepareDone` | LingoFuse is not started; `LFHttpPost` fails | Prepare LingoFuse first (§5.1). |');
    Lines.Add('| Assigning `HTTP_CALL_BASE_URL` after the first call | Race with in-flight calls; inconsistent URLs | Set it once at startup. |');
    Lines.Add('| Catching `Exception` instead of `EHTTPCallError` | Hides unrelated bugs | Catch `EHTTPCallError` explicitly. |');
    Lines.Add('| Forgetting to call `LF_Shutdown` | LingoFuse resources leak | Always call `LF_Shutdown` at exit (§7.7). |');
    Lines.Add('| Calling a generated function from the UI thread | UI freezes for the duration of the HTTP round trip | Wrap in a worker thread. |');
    Lines.Add('| Assuming a non-`EHTTPCallError` exception from the bridge | The wrapper always converts failures | Trust the exception type. |');
    Lines.Add('| Passing a value larger than the declared return type | Silent truncation on deserialization | Widen the return type in the source unit. |');
    Lines.Add('| Relying on `HTTP_CALL_BASE_URL` being thread-safe | It is a plain `string` | Guard writes with a lock if changed at runtime. |');
    Lines.Add('');
    Lines.Add('### 13.3 Decision tree: how to call an API');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    S["I want to call a remote API"] --> Q1{"Have I prepared LingoFuse?"}');
    Lines.Add('    Q1 -- "no" --> A1["LF_ResetPrepare;\\nLF_PrepareClient(endpoint, nil);\\nLF_PrepareDone"]');
    Lines.Add('    Q1 -- "yes" --> Q2{"Have I set HTTP_CALL_BASE_URL?"}');
    Lines.Add('    A1 --> Q2');
    Lines.Add('    Q2 -- "no" --> A2["HTTP_CALL_BASE_URL := ''http://.../<app>''"]');
    Lines.Add('    Q2 -- "yes" --> Q3{"Which API?"}');
    Lines.Add('    A2 --> Q3');
    Lines.Add('    Q3 -- "known" --> A3["Look up §9.<n>, note the signature"]');
    Lines.Add('    Q3 -- "unknown" --> A4["Look up §9.1 summary table"]');
    Lines.Add('    A3 --> A5["Write the call in a try/except"]');
    Lines.Add('    A4 --> A5');
    Lines.Add('    A5 --> Done["Handle EHTTPCallError"]');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 13.4 Machine-readable function manifest');
    Lines.Add('');

    if FuncCount = 0 then
    begin
      Lines.Add('_No supported routines were found in the source unit._');
      Lines.Add('');
    end
    else
    begin
      Lines.Add('The following JSON array describes every generated function.');
      Lines.Add('It is intended for consumption by code generators and AI agents.');
      Lines.Add('');
      Lines.Add('```json');
      Lines.Add('[');

      UsedApiNames.Clear;
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];

        ApiName := MakeApiName(F.Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        Lines.Add('  {');
        Lines.Add('    "name": "' + ApiName.Text + '",');
        Lines.Add('    "original_name": "' + F.Name.Text + '",');
        Lines.Add('    "kind": "' + if_(F.IsFunction, 'function', 'procedure') + '",');
        Lines.Add('    "signature": "' + BuildFullDecl(F, ApiName) + '",');
        Lines.Add('    "route": "POST /' + AppName.Text + '/' + ApiName.Text + '",');

        if Length(F.Params) > 0 then
        begin
          Lines.Add('    "params": [');
          for j := 0 to High(F.Params) do
          begin
            ParamName := MakeSafePascalIdent(F.Params[j].Name, j);
            ParamType := ABI_Type_To_Pascal_Decl(F.Params[j].PascalType);
            ParamJsonType := ABI_Type_To_Json_Wire_Type(F.Params[j].PascalType);

            Lines.Add('      {"name": "' + ParamName.Text + '", "pascal_type": "' + ParamType.Text + '", "json_type": "' +
              ParamJsonType.Text + '"}' + if_(j < High(F.Params), ',', ''));
          end;
          Lines.Add('    ],');
        end
        else
          Lines.Add('    "params": [],');

        if F.IsFunction then
          Lines.Add('    "returns": "' + ABI_Type_To_Pascal_Decl(F.ReturnType).Text + '"')
        else
          Lines.Add('    "returns": null');

        Lines.Add('  }' + if_(i < High(SupportedFuncs), ',', ''));
      end;

      Lines.Add(']');
      Lines.Add('```');
      Lines.Add('');
    end;

    Lines.Add('### 13.5 How to answer a user question with this document');
    Lines.Add('');
    Lines.Add('An AI assistant should follow this pattern:');
    Lines.Add('');
    Lines.Add('1. **Identify the intent**: call, deploy, debug, or extend?');
    Lines.Add('2. **Locate the relevant section**:');
    Lines.Add('   - "How do I call X?" -> §9.<n> for that function, plus §13.1.');
    Lines.Add('   - "Why does my call fail?" -> §10.1 and §13.2.');
    Lines.Add('   - "What types are allowed?" -> §6.2 and §13.1.');
    Lines.Add('   - "How do I set up the client?" -> §7.5.');
    Lines.Add('   - "How do I handle errors?" -> §4.4 and §8.3.');
    Lines.Add('3. **Quote the specific fact**, not the whole document. Prefer');
    Lines.Add('   the machine-readable forms in §13.1 and §13.4.');
    Lines.Add('4. **If the question is not covered**, say so and point the user');
    Lines.Add('   to the source file for the corresponding function.');
    Lines.Add('');
    Lines.Add('### 13.6 What this document does NOT cover');
    Lines.Add('');
    Lines.Add('- The internal implementation of `bridge.py`. See the bridge');
    Lines.Add('  README for that.');
    Lines.Add('- The internal implementation of `lf_http_bridge_client.pas`.');
    Lines.Add('  See the LingoFuse documentation.');
    Lines.Add('- The service-side contract. See the paired');
    Lines.Add('  `' + NormalizedUnit.Text + '_http_json_service_pascal.md`.');
    Lines.Add('- Alternative transports (binary ABI, gRPC, custom sockets).');
    Lines.Add('  See the corresponding generator.');
    Lines.Add('- Versioning or backward-compatibility guarantees. Every build');
    Lines.Add('  is treated as a fresh API surface; regenerate on change.');
    Lines.Add('');

    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_pas_abi_call_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated README: %d lines, %d supported routines.', [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
