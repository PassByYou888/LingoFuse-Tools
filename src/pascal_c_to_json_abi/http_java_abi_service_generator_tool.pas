unit http_java_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceJavaCode - main entry point for the service module.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServiceJavaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_java_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_java_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Java_Extractor(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'asString'
  else if ABI_Type_Is_Float(T) then
    Result := 'asDouble'
  else
    Result := 'asLong';
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
// SERVICE MODULE GENERATOR
// =============================================================================

procedure EmitJavaHeader(Lines: TPascalStringList;
  const UnitName, ClassName, Endpoint: TP_String);
begin
  Lines.Add('// -*- coding: utf-8 -*-');
  Lines.Add('// Auto-generated by http_java_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// Wire protocol (HTTP/JSON path, both directions):');
  Lines.Add('//   request  = JSON object');
  Lines.Add('//              { "args": [v1, v2, ...] }     positional arguments');
  Lines.Add('//              { "a": v1, "b": v2, ... }     named arguments');
  Lines.Add('//   response = JSON object');
  Lines.Add('//              { "code": 0,  "result": ... }  on success');
  Lines.Add('//              { "code": -1, "error":  ... }  on failure');
  Lines.Add('//');
  Lines.Add('// This class is a LingoFuse Call service. It is designed to be');
  Lines.Add('// reached via bridge.py from any HTTP client (curl / browser /');
  Lines.Add('// any language). The bridge performs the HTTP <-> LingoFuse');
  Lines.Add('// conversion; this class only deals with JSON strings.');
  Lines.Add('//');
  Lines.Add('// The user is expected to:');
  Lines.Add('//   1. Fill in each `internalCall_<api>` stub with a call to the');
  Lines.Add('//      real implementation.');
  Lines.Add('//   2. Run the class:');
  Lines.Add('//        java --enable-native-access=ALL-UNNAMED \\');
  Lines.Add('//             -cp <classpath> ' + ClassName.Text);
  Lines.Add('//   3. Start bridge.py with the SAME endpoint:');
  Lines.Add('//        python3 bridge.py --endpoint ' + Endpoint.Text + ' --no-precheck');
  Lines.Add('//');
  Lines.Add('// All comments and log messages in this file are English.');
  Lines.Add('');
  Lines.Add('import com.fasterxml.jackson.databind.JsonNode;');
  Lines.Add('');
  Lines.Add('import lingofuse.AppHandle;');
  Lines.Add('import lingofuse.DataHandle;');
  Lines.Add('import lingofuse.Framework;');
  Lines.Add('import lingofuse.LfIo;');
  Lines.Add('import lingofuse.LingoFuseStatus;');
  Lines.Add('import lingofuse.NetworkEvents;');
  Lines.Add('');
  Lines.Add('import java.util.LinkedHashMap;');
  Lines.Add('import java.util.Map;');
  Lines.Add('');
  Lines.Add('/**');
  Lines.Add(' * Auto-generated HTTP/JSON service for ' + UnitName.Text + '.');
  Lines.Add(' *');
  Lines.Add(' * <p>Every supported routine is registered as a LingoFuse Call');
  Lines.Add(' * API. The registered callback reads a JSON request from the');
  Lines.Add(' * input handle, extracts typed arguments, dispatches to a static');
  Lines.Add(' * stub (which the user fills in), and writes a JSON response.');
  Lines.Add(' *');
  Lines.Add(' * <p>The service is reached through bridge.py; this class itself');
  Lines.Add(' * never speaks HTTP. It only speaks the LingoFuse wire protocol.');
  Lines.Add(' */');
  Lines.Add('public final class ' + ClassName.Text + ' {');
  Lines.Add('');
end;

procedure EmitJavaConfig(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Configuration');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('    /** LingoFuse application name used by the HTTP/JSON service. */');
  Lines.Add('    public static final String HTTP_SERVICE_APP_NAME = ' + Java_Str_Lit(AppName).Text + ';');
  Lines.Add('');
  Lines.Add('    /** Human-readable description of the service. */');
  Lines.Add('    public static final String HTTP_SERVICE_APP_DESC = ' + Java_Str_Lit(AppDesc).Text + ';');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * The LingoFuse endpoint the service binds to. bridge.py must be');
  Lines.Add('     * started with the same --endpoint value.');
  Lines.Add('     */');
  Lines.Add('    public static final String HTTP_SERVICE_ENDPOINT = ' + Java_Str_Lit(Endpoint).Text + ';');
  Lines.Add('');
  Lines.Add('    /** Set to true to emit per-call debug messages on stderr. */');
  Lines.Add('    public static volatile boolean DEBUG_LOG =');
  Lines.Add('            "1".equals(System.getenv("LINGOFUSE_DEBUG"))');
  Lines.Add('                    || "true".equals(System.getenv("LINGOFUSE_DEBUG"));');
  Lines.Add('');
end;

procedure EmitJavaHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Runtime helpers');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Read and parse a JSON request from a LingoFuse input handle.');
  Lines.Add('     *');
  Lines.Add('     * <p>An empty payload is treated as an empty request object, so a');
  Lines.Add('     * parameterless API can be called with body {@code {}} or even');
  Lines.Add('     * with no body at all.');
  Lines.Add('     *');
  Lines.Add('     * @throws IllegalArgumentException if the payload is not a JSON');
  Lines.Add('     *         object, or is not valid JSON at all');
  Lines.Add('     */');
  Lines.Add('    private static JsonNode readRequest(DataHandle in) {');
  Lines.Add('        JsonNode node;');
  Lines.Add('        try {');
  Lines.Add('            node = LfIo.readJson(in);');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            throw new IllegalArgumentException(');
  Lines.Add('                    "Invalid JSON request: " + t.getMessage(), t);');
  Lines.Add('        }');
  Lines.Add('        if (node == null) {');
  Lines.Add('            return LfIo.loadsJson("{}");');
  Lines.Add('        }');
  Lines.Add('        if (!node.isObject()) {');
  Lines.Add('            throw new IllegalArgumentException(');
  Lines.Add('                    "Request must be a JSON object");');
  Lines.Add('        }');
  Lines.Add('        return node;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Extract one argument from a request object.');
  Lines.Add('     *');
  Lines.Add('     * <p>If the request has an {@code args} array, positional lookup is');
  Lines.Add('     * used. Otherwise every parameter is looked up by its original');
  Lines.Add('     * Pascal name. Returns {@code null} when the value is missing, so');
  Lines.Add('     * that the {@code as*} helpers can supply the type default.');
  Lines.Add('     */');
  Lines.Add('    private static JsonNode extractArg(JsonNode req, int idx, String name) {');
  Lines.Add('        if (req.has("args")) {');
  Lines.Add('            JsonNode arr = req.get("args");');
  Lines.Add('            if (arr.isArray() && idx < arr.size()) {');
  Lines.Add('                JsonNode v = arr.get(idx);');
  Lines.Add('                if (v != null && !v.isNull()) {');
  Lines.Add('                    return v;');
  Lines.Add('                }');
  Lines.Add('            }');
  Lines.Add('            return null;');
  Lines.Add('        }');
  Lines.Add('        if (req.has(name)) {');
  Lines.Add('            JsonNode v = req.get(name);');
  Lines.Add('            if (v != null && !v.isNull()) {');
  Lines.Add('                return v;');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        return null;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static long asLong(JsonNode v, String name) {');
  Lines.Add('        if (v == null || v.isNull()) {');
  Lines.Add('            return 0L;');
  Lines.Add('        }');
  Lines.Add('        if (v.isNumber()) {');
  Lines.Add('            return v.asLong();');
  Lines.Add('        }');
  Lines.Add('        if (v.isTextual()) {');
  Lines.Add('            String s = v.asText().trim();');
  Lines.Add('            if (s.isEmpty()) {');
  Lines.Add('                return 0L;');
  Lines.Add('            }');
  Lines.Add('            try {');
  Lines.Add('                return Long.parseLong(s);');
  Lines.Add('            } catch (NumberFormatException e) {');
  Lines.Add('                throw new IllegalArgumentException(');
  Lines.Add('                        "Argument \"" + name +');
  Lines.Add('                                "\" expects an integer, got: " + s);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        throw new IllegalArgumentException(');
  Lines.Add('                "Argument \"" + name +');
  Lines.Add('                        "\" expects an integer, got: " + v);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static double asDouble(JsonNode v, String name) {');
  Lines.Add('        if (v == null || v.isNull()) {');
  Lines.Add('            return 0.0;');
  Lines.Add('        }');
  Lines.Add('        if (v.isNumber()) {');
  Lines.Add('            return v.asDouble();');
  Lines.Add('        }');
  Lines.Add('        if (v.isTextual()) {');
  Lines.Add('            String s = v.asText().trim();');
  Lines.Add('            if (s.isEmpty()) {');
  Lines.Add('                return 0.0;');
  Lines.Add('            }');
  Lines.Add('            try {');
  Lines.Add('                return Double.parseDouble(s);');
  Lines.Add('            } catch (NumberFormatException e) {');
  Lines.Add('                throw new IllegalArgumentException(');
  Lines.Add('                        "Argument \"" + name +');
  Lines.Add('                                "\" expects a number, got: " + s);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        throw new IllegalArgumentException(');
  Lines.Add('                "Argument \"" + name +');
  Lines.Add('                        "\" expects a number, got: " + v);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static String asString(JsonNode v, String name) {');
  Lines.Add('        if (v == null || v.isNull()) {');
  Lines.Add('            return "";');
  Lines.Add('        }');
  Lines.Add('        if (v.isTextual()) {');
  Lines.Add('            return v.asText();');
  Lines.Add('        }');
  Lines.Add('        return v.toString();');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeSuccess(DataHandle out, Object result) {');
  Lines.Add('        Map<String, Object> envelope = new LinkedHashMap<>();');
  Lines.Add('        envelope.put("code", 0);');
  Lines.Add('        envelope.put("result", result);');
  Lines.Add('        LfIo.writeJson(out, envelope);');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static void writeError(DataHandle out, Throwable err) {');
  Lines.Add('        Map<String, Object> envelope = new LinkedHashMap<>();');
  Lines.Add('        envelope.put("code", -1);');
  Lines.Add('        String msg = (err == null)');
  Lines.Add('                ? "unknown"');
  Lines.Add('                : (err.getMessage() != null');
  Lines.Add('                        ? err.getMessage()');
  Lines.Add('                        : err.getClass().getSimpleName());');
  Lines.Add('        envelope.put("error", msg);');
  Lines.Add('        try {');
  Lines.Add('            LfIo.writeJson(out, envelope);');
  Lines.Add('        } catch (Throwable ignored) {');
  Lines.Add('            // The output handle is unusable; nothing else to do.');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitJavaStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, ArgList, ReturnType, Default, StubName: TP_String;
  Description: TP_String;
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Internal call stubs');
  Lines.Add('    //');
  Lines.Add('    // Each stub mirrors one original routine. Replace the body with a');
  Lines.Add('    // call to the real implementation, for example:');
  Lines.Add('    //     return MyModule.add(a, b);');
  Lines.Add('    // The parameter names and types are already correct.');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := 'internalCall_' + ApiName;
    ParamDecl := BuildJavaParamDecl(F.Params);
    ArgList := BuildJavaArgList(F.Params);
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API stub for ' + ApiName + '.';

    if F.IsFunction then
      ReturnType := ABI_Type_To_Java_Type(F.ReturnType)
    else
      ReturnType := 'void';

    Lines.Add('    /**');
    Lines.Add('     * ' + Description.Text);
    Lines.Add('     *');
    Lines.Add('     * <p>TODO: replace the body with a call to the real implementation.');
    if Length(F.Params) > 0 then
      Lines.Add('     * Suggested call: ' + F.Name.Text + '(' + ArgList.Text + ')')
    else
      Lines.Add('     * Suggested call: ' + F.Name.Text + '()');
    Lines.Add('     */');
    Lines.Add('    private static ' + ReturnType.Text + ' ' + StubName.Text +
      '(' + ParamDecl.Text + ') {');

    if F.IsFunction then
    begin
      Default := ABI_Type_To_Java_Default(F.ReturnType);
      Lines.Add('        // TODO: implement this stub.');
      Lines.Add('        return ' + Default.Text + ';');
    end
    else
    begin
      Lines.Add('        // TODO: implement this stub.');
    end;
    Lines.Add('    }');
    Lines.Add('');
  end;
end;

procedure EmitJavaRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, ParamName, TypeName, Extractor, ArgExpr: TP_String;
  Description: TP_String;
  CallArgs: TP_String;
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Registration');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Register every generated Call API on the given App.');
  Lines.Add('     */');
  Lines.Add('    static void registerAll(AppHandle app) {');

  if Length(SupportedFuncs) = 0 then
  begin
    Lines.Add('        // No supported routines were generated.');
  end
  else
  begin
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      StubName := 'internalCall_' + ApiName;

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'HTTP/JSON api for ' + F.Name;

      Lines.Add('');
      Lines.Add('        // ---- ' + ApiName.Text + ' ----');
      Lines.Add('        app.registerCall(');
      Lines.Add('                ' + Java_Str_Lit(ApiName).Text + ',');
      Lines.Add('                ' + Java_Str_Lit(Description).Text + ',');
      Lines.Add('                (in, out) -> {');
      Lines.Add('                    try {');
      Lines.Add('                        JsonNode req = readRequest(in);');

      CallArgs := '';
      for j := 0 to High(F.Params) do
      begin
        ParamName := MakeSafeJavaIdent(F.Params[j].Name, j);
        TypeName := ABI_Type_To_Java_Type(F.Params[j].PascalType);
        Extractor := ABI_Type_To_Java_Extractor(F.Params[j].PascalType);
        ArgExpr := Extractor + '(extractArg(req, ' + umlIntToStr(j).Text + ', ' +
          Java_Str_Lit(F.Params[j].Name).Text + '), ' +
          Java_Str_Lit(F.Params[j].Name).Text + ')';
        Lines.Add('                        ' + TypeName.Text + ' ' +
          ParamName.Text + ' = ' + ArgExpr + ';');
        if j > 0 then
          CallArgs := CallArgs + ', ';
        CallArgs := CallArgs + ParamName;
      end;

      if F.IsFunction then
      begin
        Lines.Add('                        Object result = ' + StubName.Text +
          '(' + CallArgs.Text + ');');
        Lines.Add('                        writeSuccess(out, result);');
      end
      else
      begin
        Lines.Add('                        ' + StubName.Text + '(' + CallArgs.Text + ');');
        Lines.Add('                        writeSuccess(out, null);');
      end;

      Lines.Add('                    } catch (Throwable err) {');
      Lines.Add('                        writeError(out, err);');
      Lines.Add('                        if (DEBUG_LOG) {');
      Lines.Add('                            System.err.println(');
      Lines.Add('                                    "[' + ApiName.Text + '] callback threw: "');
      Lines.Add('                                            + err);');
      Lines.Add('                        }');
      Lines.Add('                    }');
      Lines.Add('                });');
    end;
  end;

  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Create the App and register every generated Call API on it.');
  Lines.Add('     *');
  Lines.Add('     * <p>The caller owns the returned handle and must call');
  Lines.Add('     * {@code close()} on it when done; {@link #cleanupOnce} does this');
  Lines.Add('     * automatically.');
  Lines.Add('     */');
  Lines.Add('    static AppHandle createAndRegister() {');
  Lines.Add('        AppHandle app = new AppHandle(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
  Lines.Add('        registerAll(app);');
  Lines.Add('        return app;');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitJavaMain(Lines: TPascalStringList;
  const Endpoint: TP_String);
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Main entry point');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Perform the cleanup sequence exactly once.');
  Lines.Add('     *');
  Lines.Add('     * <p>The order is strict and non-negotiable:');
  Lines.Add('     * <ol>');
  Lines.Add('     *   <li>{@code NetworkEvents.clear()} - remove the global event');
  Lines.Add('     *       handlers before the framework starts tearing down.</li>');
  Lines.Add('     *   <li>{@code Framework.exitMainThread()} - stop the simulated');
  Lines.Add('     *       main loop. This also flushes the data handle pool.</li>');
  Lines.Add('     *   <li>{@code app.close()} - the first stage of the two-stage');
  Lines.Add('     *       application destruction.</li>');
  Lines.Add('     *   <li>{@code Framework.shutdown()} - the second stage; releases');
  Lines.Add('     *       the native library.</li>');
  Lines.Add('     * </ol>');
  Lines.Add('     */');
  Lines.Add('    private static void cleanupOnce(AppHandle app, boolean started) {');
  Lines.Add('        try {');
  Lines.Add('            NetworkEvents.clear();');
  Lines.Add('        } catch (Throwable ignored) {');
  Lines.Add('        }');
  Lines.Add('        if (started) {');
  Lines.Add('            try {');
  Lines.Add('                Framework.exitMainThread();');
  Lines.Add('            } catch (Throwable ignored) {');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        if (app != null) {');
  Lines.Add('            try {');
  Lines.Add('                app.close();');
  Lines.Add('            } catch (Throwable ignored) {');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        if (started) {');
  Lines.Add('            try {');
  Lines.Add('                Framework.shutdown();');
  Lines.Add('            } catch (Throwable ignored) {');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    public static void main(String[] args) {');
  Lines.Add('        System.out.println("=== " + HTTP_SERVICE_APP_NAME');
  Lines.Add('                + " HTTP/JSON service ===");');
  Lines.Add('        System.out.println("Endpoint: " + HTTP_SERVICE_ENDPOINT);');
  Lines.Add('        System.out.println();');
  Lines.Add('');
  Lines.Add('        AppHandle app = null;');
  Lines.Add('        boolean started = false;');
  Lines.Add('');
  Lines.Add('        try {');
  Lines.Add('            // Deployment mode: do not block waiting for peers that');
  Lines.Add('            // are not yet ready. This lets bridge.py and this service');
  Lines.Add('            // start in any order.');
  Lines.Add('            Framework.setOption("Wait_Connection_ReadyOk", "False");');
  Lines.Add('            Framework.setOption("Overlap_Connection", "True");');
  Lines.Add('');
  Lines.Add('            Framework.resetPrepare();');
  Lines.Add('');
  Lines.Add('            app = createAndRegister();');
  Lines.Add('');
  Lines.Add('            int servRet = Framework.prepareService(');
  Lines.Add('                    HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT);');
  Lines.Add('            if (servRet < 0) {');
  Lines.Add('                System.err.println(');
  Lines.Add('                        "[FATAL] prepareService returned " + servRet');
  Lines.Add('                                + " for endpoint \""');
  Lines.Add('                                + HTTP_SERVICE_ENDPOINT + "\".");');
  Lines.Add('                throw new RuntimeException("prepareService failed");');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            int clientRet = Framework.prepareClient(');
  Lines.Add('                    HTTP_SERVICE_ENDPOINT, app);');
  Lines.Add('            if (clientRet < 0) {');
  Lines.Add('                System.err.println(');
  Lines.Add('                        "[FATAL] prepareClient returned " + clientRet');
  Lines.Add('                                + " for endpoint \""');
  Lines.Add('                                + HTTP_SERVICE_ENDPOINT + "\".");');
  Lines.Add('                throw new RuntimeException("prepareClient failed");');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            int doneRet = Framework.prepareDone();');
  Lines.Add('            if (doneRet != 1 && !LingoFuseStatus.checkMainThread()) {');
  Lines.Add('                System.err.println("[FATAL] prepareDone returned " + doneRet);');
  Lines.Add('                throw new RuntimeException("prepareDone failed");');
  Lines.Add('            }');
  Lines.Add('            started = true;');
  Lines.Add('');
  Lines.Add('            System.out.println("[OK] Service ready. Press Ctrl+C to stop.");');
  Lines.Add('');
  Lines.Add('            // Install the shutdown hook AFTER the successful startup,');
  Lines.Add('            // so a startup failure is cleaned up by the catch block');
  Lines.Add('            // below without risking a double cleanup.');
  Lines.Add('            final AppHandle appFinal = app;');
  Lines.Add('            final boolean startedFinal = started;');
  Lines.Add('            Runtime.getRuntime().addShutdownHook(new Thread(');
  Lines.Add('                    () -> cleanupOnce(appFinal, startedFinal),');
  Lines.Add('                    "lf-shutdown"));');
  Lines.Add('');
  Lines.Add('            // Block forever. Ctrl+C triggers the shutdown hook.');
  Lines.Add('            try {');
  Lines.Add('                Thread.sleep(Long.MAX_VALUE);');
  Lines.Add('            } catch (InterruptedException e) {');
  Lines.Add('                Thread.currentThread().interrupt();');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('        } catch (Throwable t) {');
  Lines.Add('            System.err.println("[FATAL] "');
  Lines.Add('                    + t.getClass().getSimpleName() + ": " + t.getMessage());');
  Lines.Add('            t.printStackTrace(System.err);');
  Lines.Add('            cleanupOnce(app, started);');
  Lines.Add('            System.exit(1);');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitJavaFooter(Lines: TPascalStringList; const ClassName: TP_String);
begin
  Lines.Add('    private ' + ClassName.Text + '() {');
  Lines.Add('        // Utility class; no instances.');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceJavaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ClassName, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceJavaCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceJavaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  ClassName := UnitName + 'HttpJsonService';
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitJavaHeader(Lines, UnitName, ClassName, Endpoint);
    EmitJavaConfig(Lines, AppName, AppDesc, Endpoint);
    EmitJavaHelpers(Lines);
    EmitJavaStubs(Lines, SupportedFuncs, ApiNames);
    EmitJavaRegistration(Lines, SupportedFuncs, ApiNames);
    EmitJavaMain(Lines, Endpoint);
    EmitJavaFooter(Lines, ClassName);

    Result := Lines;
    Log(PFormat('Generated Java service module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'java', 'Java HTTP/JSON service code',
    asService, akServiceCode,
    'HttpJsonService.java', False,
    @GenerateHTTPServiceJavaCode);
end.
