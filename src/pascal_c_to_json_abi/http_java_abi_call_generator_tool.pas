unit http_java_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallJavaCode - main entry point for the call module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallJavaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_java_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_java_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

// ABI_Type_To_Java_Type - the Java type used in the generated method
// signature and body. Every integer family member collapses to `long`
// to avoid sign/precision ambiguity; every float family member
// collapses to `double`; every string family member collapses to
// `String`.
function ABI_Type_To_Java_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'double'
  else if ABI_Type_Is_Int(T) then
    Result := 'long'
  else
    Result := 'void';
end;

// ABI_Type_To_Java_Default - the Java literal used when the caller
// does not supply a value. The defaults are chosen so that a
// generated method call site always compiles without an explicit
// cast: `""` for String, `0L` for long, `0.0` for double.
function ABI_Type_To_Java_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0L'
  else
    Result := 'null';
end;

// ABI_Type_To_Json_Wire_Type - coarse wire type used only by the
// README generator.
function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

// ABI_Type_To_Pascal_Decl - Pascal type keyword used only by the
// README generator, to show the original declaration.
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

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// MakeApiName - canonicalize an arbitrary identifier into one that is
// safe as an API name, a URL path segment, a JSON key, and an
// identifier in Java / Pascal / Python / C#.
//
// The replacement set MUST match every other generator in this
// toolchain.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafeJavaIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('abstract') or Result.Same('assert') or Result.Same('boolean') or
    Result.Same('break') or Result.Same('byte') or Result.Same('case') or
    Result.Same('catch') or Result.Same('char') or Result.Same('class') or
    Result.Same('const') or Result.Same('continue') or Result.Same('default') or
    Result.Same('do') or Result.Same('double') or Result.Same('else') or
    Result.Same('enum') or Result.Same('extends') or Result.Same('final') or
    Result.Same('finally') or Result.Same('float') or Result.Same('for') or
    Result.Same('goto') or Result.Same('if') or Result.Same('implements') or
    Result.Same('import') or Result.Same('instanceof') or Result.Same('int') or
    Result.Same('interface') or Result.Same('long') or Result.Same('native') or
    Result.Same('new') or Result.Same('package') or Result.Same('private') or
    Result.Same('protected') or Result.Same('public') or Result.Same('return') or
    Result.Same('short') or Result.Same('static') or Result.Same('strictfp') or
    Result.Same('super') or Result.Same('switch') or Result.Same('synchronized') or
    Result.Same('this') or Result.Same('throw') or Result.Same('throws') or
    Result.Same('transient') or Result.Same('try') or Result.Same('void') or
    Result.Same('volatile') or Result.Same('while') or Result.Same('true') or
    Result.Same('false') or Result.Same('null') then
    Result := Result + '_';
end;

// Java_Str_Lit - emit a complete double-quoted Java string literal
// (with surrounding quotes). Control characters are escaped as \uNNNN
// so the result is a well-formed Java source fragment.
function Java_Str_Lit(const S: TP_String): TP_String;
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
      '"': Result.Append('\"');
      '\': Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9:  Result.Append('\t');
      #8:  Result.Append('\b');
      #12: Result.Append('\f');
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\u');
          Result.Append(HEXDIG[((code shr 12) and $F) + 1]);
          Result.Append(HEXDIG[((code shr 8) and $F) + 1]);
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
      // skip CR
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

// BuildJavaParamDecl - `long a, long b, String c` for a parameter list.
function BuildJavaParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, t: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJavaIdent(Params[i].Name, i);
    t := ABI_Type_To_Java_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + t + ' ' + n;
  end;
end;

// BuildJavaArgList - `a, b, c` for a call-site argument list.
function BuildJavaArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJavaIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildJavaListOfExpr - `List.of(a, b, c)` or `List.of()` when empty.
function BuildJavaListOfExpr(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := 'List.of()';
    Exit;
  end;
  Result := 'List.of(';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJavaIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ')';
end;

// BuildJavaReturnExpr - the `return ...;` expression that converts a
// JsonNode result into the declared ABI type.
function BuildJavaReturnExpr(const ReturnType: TP_String): TP_String;
begin
  if ABI_Type_Is_String(ReturnType) then
    Result := 'result == null ? "" : result.asText()'
  else if ABI_Type_Is_Float(ReturnType) then
    Result := 'result == null ? 0.0 : result.asDouble()'
  else if ABI_Type_Is_Int(ReturnType) then
    Result := 'result == null ? 0L : result.asLong()'
  else
    Result := 'null';
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
    n := MakeSafeJavaIdent(F.Params[i].Name, i);
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

// BuildJavaSignature - `long add(long a, long b)` etc. Used by the
// README only.
function BuildJavaSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
begin
  if F.IsFunction then
    Result := ABI_Type_To_Java_Type(F.ReturnType) + ' ' + ApiName +
      '(' + BuildJavaParamDecl(F.Params) + ')'
  else
    Result := 'void ' + ApiName +
      '(' + BuildJavaParamDecl(F.Params) + ')';
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
// CALL MODULE GENERATOR
// =============================================================================

procedure EmitJavaHeader(Lines: TPascalStringList;
  const UnitName, ClassName, BaseUrl: TP_String);
begin
  Lines.Add('// -*- coding: utf-8 -*-');
  Lines.Add('// Auto-generated by http_java_abi_call_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// Wire protocol (HTTP/JSON path):');
  Lines.Add('//   request  = POST <base_url>/<api>  with body');
  Lines.Add('//              { "args": [v1, v2, ...] }');
  Lines.Add('//   response = { "code": 0,  "result": ... }   on success');
  Lines.Add('//              { "code": -1, "error":  ... }   on failure');
  Lines.Add('//');
  Lines.Add('// This class is a Java HTTP/JSON client. It sends requests');
  Lines.Add('// directly to a bridge process (bridge.py) over plain HTTP.');
  Lines.Add('// It does NOT depend on the `lingofuse` Java binding: it uses');
  Lines.Add('// only the JDK built-in `java.net.http.HttpClient` and Jackson');
  Lines.Add('// for JSON.');
  Lines.Add('');
  Lines.Add('import com.fasterxml.jackson.databind.JsonNode;');
  Lines.Add('import com.fasterxml.jackson.databind.ObjectMapper;');
  Lines.Add('');
  Lines.Add('import java.net.URI;');
  Lines.Add('import java.net.http.HttpClient;');
  Lines.Add('import java.net.http.HttpRequest;');
  Lines.Add('import java.net.http.HttpResponse;');
  Lines.Add('import java.nio.charset.StandardCharsets;');
  Lines.Add('import java.time.Duration;');
  Lines.Add('import java.util.LinkedHashMap;');
  Lines.Add('import java.util.List;');
  Lines.Add('import java.util.Map;');
  Lines.Add('');
  Lines.Add('/**');
  Lines.Add(' * Auto-generated HTTP/JSON client for ' + UnitName.Text + '.');
  Lines.Add(' *');
  Lines.Add(' * <p>Every generated static method POSTs a JSON request to the');
  Lines.Add(' * bridge and returns the deserialized result. The class has no');
  Lines.Add(' * dependency on the LingoFuse native library; it talks plain');
  Lines.Add(' * HTTP to bridge.py and lets the bridge do the mesh conversion.');
  Lines.Add(' */');
  Lines.Add('public final class ' + ClassName.Text + ' {');
  Lines.Add('');
end;

procedure EmitJavaConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('    /**');
  Lines.Add('     * Base URL of the bridge, including the target app name.');
  Lines.Add('     * The full URL for API "X" is: HTTP_CALL_BASE_URL + "/" + "X"');
  Lines.Add('     */');
  Lines.Add('    public static String HTTP_CALL_BASE_URL = ' + Java_Str_Lit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('    /** Per-request timeout, including connect and read. */');
  Lines.Add('    public static Duration HTTP_CALL_TIMEOUT = Duration.ofSeconds(30);');
  Lines.Add('');
  Lines.Add('    private static final ObjectMapper MAPPER = new ObjectMapper();');
  Lines.Add('');
  Lines.Add('    private static final HttpClient HTTP = HttpClient.newBuilder()');
  Lines.Add('            .connectTimeout(Duration.ofSeconds(10))');
  Lines.Add('            .build();');
  Lines.Add('');
end;

procedure EmitJavaErrorAndTransport(Lines: TPascalStringList);
begin
  Lines.Add('    /**');
  Lines.Add('     * Thrown by every generated client method on failure.');
  Lines.Add('     *');
  Lines.Add('     * <p>{@code code} mirrors the wire-level {@code code} field:');
  Lines.Add('     * 0 (never thrown), -1 (transport / HTTP / empty / shape),');
  Lines.Add('     * -2 (bridge URL shape error), -3 (bridge pre-check failed),');
  Lines.Add('     * and any service-defined non-zero code.');
  Lines.Add('     */');
  Lines.Add('    public static final class HTTPCallException extends RuntimeException {');
  Lines.Add('        public final int code;');
  Lines.Add('        public final int httpStatus;');
  Lines.Add('');
  Lines.Add('        public HTTPCallException(String message, int code, int httpStatus) {');
  Lines.Add('            super(message);');
  Lines.Add('            this.code = code;');
  Lines.Add('            this.httpStatus = httpStatus;');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Single transport primitive: POST a JSON request to the bridge');
  Lines.Add('     * and return the value of the {@code result} field.');
  Lines.Add('     *');
  Lines.Add('     * <p>Every generated method funnels through this function, so the');
  Lines.Add('     * wire contract has exactly one implementation.');
  Lines.Add('     */');
  Lines.Add('    static JsonNode callApi(String apiName, List<?> args) {');
  Lines.Add('        try {');
  Lines.Add('            Map<String, Object> body = new LinkedHashMap<>();');
  Lines.Add('            body.put("args", args);');
  Lines.Add('            String bodyText = MAPPER.writeValueAsString(body);');
  Lines.Add('');
  Lines.Add('            String base = HTTP_CALL_BASE_URL.replaceAll("/+$", "");');
  Lines.Add('            String url = base + "/" + apiName;');
  Lines.Add('');
  Lines.Add('            HttpRequest req = HttpRequest.newBuilder()');
  Lines.Add('                    .uri(URI.create(url))');
  Lines.Add('                    .timeout(HTTP_CALL_TIMEOUT)');
  Lines.Add('                    .header("Content-Type", "application/json; charset=utf-8")');
  Lines.Add('                    .POST(HttpRequest.BodyPublishers.ofString(bodyText, StandardCharsets.UTF_8))');
  Lines.Add('                    .build();');
  Lines.Add('');
  Lines.Add('            HttpResponse<String> resp = HTTP.send(');
  Lines.Add('                    req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));');
  Lines.Add('            int status = resp.statusCode();');
  Lines.Add('            String text = resp.body();');
  Lines.Add('');
  Lines.Add('            if (status != 200) {');
  Lines.Add('                throw new HTTPCallException(');
  Lines.Add('                        "HTTP " + status + ": " + text, -1, status);');
  Lines.Add('            }');
  Lines.Add('            if (text == null || text.isEmpty()) {');
  Lines.Add('                throw new HTTPCallException(');
  Lines.Add('                        "Empty response from bridge", -1, status);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            JsonNode parsed = MAPPER.readTree(text);');
  Lines.Add('            if (parsed == null || !parsed.isObject()) {');
  Lines.Add('                throw new HTTPCallException(');
  Lines.Add('                        "Response is not a JSON object", -1, status);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            JsonNode codeNode = parsed.get("code");');
  Lines.Add('            if (codeNode == null) {');
  Lines.Add('                JsonNode errNode = parsed.get("error");');
  Lines.Add('                throw new HTTPCallException(');
  Lines.Add('                        errNode != null && errNode.isTextual()');
  Lines.Add('                                ? errNode.asText()');
  Lines.Add('                                : "Response has no code field",');
  Lines.Add('                        -1, status);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            int code = codeNode.asInt();');
  Lines.Add('            if (code != 0) {');
  Lines.Add('                JsonNode errNode = parsed.get("error");');
  Lines.Add('                throw new HTTPCallException(');
  Lines.Add('                        errNode != null && errNode.isTextual()');
  Lines.Add('                                ? errNode.asText()');
  Lines.Add('                                : "Remote call failed",');
  Lines.Add('                        code, status);');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            return parsed.get("result");');
  Lines.Add('        } catch (HTTPCallException e) {');
  Lines.Add('            throw e;');
  Lines.Add('        } catch (InterruptedException e) {');
  Lines.Add('            Thread.currentThread().interrupt();');
  Lines.Add('            throw new HTTPCallException(');
  Lines.Add('                    "Interrupted: " + e.getMessage(), -1, 0);');
  Lines.Add('        } catch (Exception e) {');
  Lines.Add('            throw new HTTPCallException(');
  Lines.Add('                    "Network error: " + e.getMessage(), -1, 0);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitJavaFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, ArgList, ReturnExpr: TP_String;
  Description: TP_String;
  JavaType: TP_String;
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Generated API methods');
  Lines.Add('    //');
  Lines.Add('    // Each method POSTs a JSON request to the bridge and returns the');
  Lines.Add('    // result converted to the declared ABI type. Failures are thrown');
  Lines.Add('    // as HTTPCallException.');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildJavaParamDecl(F.Params);
    ArgList := BuildJavaListOfExpr(F.Params);
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    if F.IsFunction then
      JavaType := ABI_Type_To_Java_Type(F.ReturnType)
    else
      JavaType := 'void';

    Lines.Add('    /**');
    Lines.Add('     * ' + Description.Text);
    Lines.Add('     *');
    Lines.Add('     * @throws HTTPCallException on any failure.');
    Lines.Add('     */');
    Lines.Add('    public static ' + JavaType.Text + ' ' + ApiName.Text +
      '(' + ParamDecl.Text + ') {');

    if F.IsFunction then
    begin
      Lines.Add('        JsonNode result = callApi(' +
        Java_Str_Lit(ApiName).Text + ', ' + ArgList.Text + ');');
      ReturnExpr := BuildJavaReturnExpr(F.ReturnType);
      Lines.Add('        return ' + ReturnExpr.Text + ';');
    end
    else
    begin
      Lines.Add('        callApi(' +
        Java_Str_Lit(ApiName).Text + ', ' + ArgList.Text + ');');
    end;

    Lines.Add('    }');
    Lines.Add('');
  end;
end;

procedure EmitJavaFooter(Lines: TPascalStringList; const ClassName: TP_String);
begin
  Lines.Add('    private ' + ClassName.Text + '() {');
  Lines.Add('        // Utility class; no instances.');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPCallJavaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ClassName, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallJavaCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallJavaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ClassName := UnitName + 'HttpJsonClient';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitJavaHeader(Lines, UnitName, ClassName, BaseUrl);
    EmitJavaConfig(Lines, BaseUrl);
    EmitJavaErrorAndTransport(Lines);
    EmitJavaFunctions(Lines, SupportedFuncs, ApiNames);
    EmitJavaFooter(Lines, ClassName);

    Result := Lines;
    Log(PFormat('Generated Java call module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'java', 'Java HTTP/JSON call client',
    asCall, akCallCode,
    'HttpJsonClient.java', False,
    @GenerateHTTPCallJavaCode);
end.
