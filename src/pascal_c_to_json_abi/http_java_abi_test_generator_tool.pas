unit http_java_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceJavaTestCode - generate the service-side test
// program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServiceJavaTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallJavaTestCode - generate the call-side test program.
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPCallJavaTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_java_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_java_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification (mirrors every other generator)
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

function ABI_Type_To_Java_Default_Lit(const T: TP_String): TP_String;
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

function BuildJavaArgLitList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Java_Default_Lit(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
end;

function BuildJavaArgsArrayLit(const Params: TParamArray): TP_String;
begin
  if Length(Params) = 0 then
    Result := 'new Object[0]'
  else
    Result := 'new Object[]{ ' + BuildJavaArgLitList(Params) + ' }';
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
// SERVICE-SIDE TEST PROGRAM GENERATOR
// =============================================================================

function GenerateHTTPServiceJavaTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceClass, ServiceTestClass, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  ApiName, ArgsArrayLit, RequestJson: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceJavaTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceJavaTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceClass := UnitName + 'HttpJsonService';
  ServiceTestClass := UnitName + 'HttpJsonServiceTest';
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// -*- coding: utf-8 -*-');
    Lines.Add('// Auto-generated by http_java_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service-side test program for the Java HTTP/JSON service.');
    Lines.Add('// Pairs with ' + ServiceClass.Text + '.java.');
    Lines.Add('//');
    Lines.Add('// Modes:');
    Lines.Add('//   (default)  Delegate to ' + ServiceClass.Text + '.main(args).');
    Lines.Add('//              That method blocks until shutdown (success) or');
    Lines.Add('//              calls System.exit(1) (failure), so this wrapper');
    Lines.Add('//              simply forwards the args.');
    Lines.Add('//   --smoke    In-process LocalCall self-tests. Creates a local');
    Lines.Add('//              AppHandle, registers every API on it, and invokes');
    Lines.Add('//              each one via AppHandle.localCall. No LingoFuse');
    Lines.Add('//              mesh, no bridge.py, no network.');
    Lines.Add('//');
    Lines.Add('// Usage:');
    Lines.Add('//   java --enable-native-access=ALL-UNNAMED \\');
    Lines.Add('//        -cp <classpath> ' + ServiceTestClass.Text);
    Lines.Add('//   java --enable-native-access=ALL-UNNAMED \\');
    Lines.Add('//        -cp <classpath> ' + ServiceTestClass.Text + ' --smoke');
    Lines.Add('//');
    Lines.Add('// Prerequisite: this file must sit next to ' + ServiceClass.Text + '.java');
    Lines.Add('// (or its compiled class), because the service class is imported');
    Lines.Add('// by name.');
    Lines.Add('');
    Lines.Add('import com.fasterxml.jackson.databind.JsonNode;');
    Lines.Add('');
    Lines.Add('import lingofuse.AppHandle;');
    Lines.Add('import lingofuse.DataHandle;');
    Lines.Add('import lingofuse.LfIo;');
    Lines.Add('');
    Lines.Add('import java.util.LinkedHashMap;');
    Lines.Add('import java.util.List;');
    Lines.Add('import java.util.Map;');
    Lines.Add('');
    Lines.Add('public final class ' + ServiceTestClass.Text + ' {');
    Lines.Add('');
    Lines.Add('    public static void main(String[] args) throws Exception {');
    Lines.Add('        boolean smoke = false;');
    Lines.Add('        for (String a : args) {');
    Lines.Add('            if ("--smoke".equals(a)) {');
    Lines.Add('                smoke = true;');
    Lines.Add('                break;');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        if (smoke) {');
    Lines.Add('            System.exit(runSmoke());');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        // Default mode: delegate to the service module.');
    Lines.Add('        //');
    Lines.Add('        // The service''s main() either blocks (success) or calls');
    Lines.Add('        // System.exit(1) after its own cleanup (failure). It never');
    Lines.Add('        // returns normally.');
    Lines.Add('        ' + ServiceClass.Text + '.main(args);');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static int runSmoke() {');
    Lines.Add('        System.out.println("[smoke] running in-process LocalCall self-tests");');
    Lines.Add('        System.out.println("[smoke] this mode creates a local AppHandle and calls every API in-process");');
    Lines.Add('        System.out.println("[smoke] it does NOT bind to any network endpoint and does NOT need the bridge");');
    Lines.Add('        System.out.println();');
    Lines.Add('');
    Lines.Add('        AppHandle app;');
    Lines.Add('        try {');
    Lines.Add('            app = ' + ServiceClass.Text + '.createAndRegister();');
    Lines.Add('        } catch (Throwable t) {');
    Lines.Add('            System.err.println("[smoke] failed to create App: " + t.getMessage());');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        int ok = 0;');
    Lines.Add('        int fail = 0;');
    Lines.Add('        try {');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ArgsArrayLit := BuildJavaArgsArrayLit(F.Params);

      Lines.Add('            // ---- ' + ApiName.Text + ' ----');
      Lines.Add('            try {');
      Lines.Add('                Map<String, Object> body = new LinkedHashMap<>();');
      if Length(F.Params) > 0 then
        Lines.Add('                body.put("args", List.of(' + BuildJavaArgLitList(F.Params) + '));');
      Lines.Add('                try (DataHandle req = new DataHandle(' +
        Java_Str_Lit(ApiName).Text + ')) {');
      Lines.Add('                    LfIo.writeJson(req, body);');
      Lines.Add('                    try (DataHandle resp = app.localCall(req)) {');
      Lines.Add('                        JsonNode parsed = LfIo.readJson(resp);');
      Lines.Add('                        if (parsed != null && parsed.has("code")');
      Lines.Add('                                && parsed.get("code").asInt() == 0) {');
      Lines.Add('                            System.out.println("  ' + ApiName.Text + ': OK");');
      Lines.Add('                            ok++;');
      Lines.Add('                        } else {');
      Lines.Add('                            System.err.println("  ' + ApiName.Text + ': non-zero code: "');
      Lines.Add('                                    + (parsed == null ? "null" : parsed.toString()));');
      Lines.Add('                            fail++;');
      Lines.Add('                        }');
      Lines.Add('                    }');
      Lines.Add('                }');
      Lines.Add('            } catch (Throwable t) {');
      Lines.Add('                System.err.println("  ' + ApiName.Text + ': FAILED: " + t.getMessage());');
      Lines.Add('                fail++;');
      Lines.Add('            }');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('            // (no supported routines)');
    Lines.Add('        } finally {');
    Lines.Add('            try {');
    Lines.Add('                app.close();');
    Lines.Add('            } catch (Throwable ignored) {');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        System.out.println();');
    Lines.Add('        System.out.println("=== Smoke test summary ===");');
    Lines.Add('        System.out.println("Passed: " + ok);');
    Lines.Add('        System.out.println("Failed: " + fail);');
    Lines.Add('        return fail == 0 ? 0 : 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private ' + ServiceTestClass.Text + '() {');
    Lines.Add('        // Utility class; no instances.');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// CALL-SIDE TEST PROGRAM GENERATOR
// =============================================================================

function GenerateHTTPCallJavaTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, BaseUrl, TestClass: TP_String;
  ApiNames: TPascalStringList;
  ApiName, ArgsArrayLit: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallJavaTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallJavaTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  TestClass := UnitName + 'HttpJsonCallTest';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// -*- coding: utf-8 -*-');
    Lines.Add('// Auto-generated by http_java_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side test program for the Java HTTP/JSON service.');
    Lines.Add('//');
    Lines.Add('// Drives the wire protocol directly with java.net.http.HttpClient');
    Lines.Add('// and Jackson. The class does NOT import the LingoFuse Java binding');
    Lines.Add('// and does NOT import the generated call module, so its classpath');
    Lines.Add('// is minimal: JDK 11+ plus Jackson.');
    Lines.Add('//');
    Lines.Add('// Every supported routine is POSTed to the bridge and checked for');
    Lines.Add('// a {"code": 0} response. Sequential execution keeps the output');
    Lines.Add('// readable; a slow bridge cannot pile up concurrent requests.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * bridge.py must be running on the target base URL;');
    Lines.Add('//   * the matching service must be running and reachable through');
    Lines.Add('//     the same bridge.');
    Lines.Add('//');
    Lines.Add('// Usage:');
    Lines.Add('//   java -cp <classpath> ' + TestClass.Text);
    Lines.Add('//   java -cp <classpath> ' + TestClass.Text + ' <base_url>');
    Lines.Add('//');
    Lines.Add('// Defaults:');
    Lines.Add('//   <base_url> = ' + BaseUrl.Text);
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
    Lines.Add('public final class ' + TestClass.Text + ' {');
    Lines.Add('');
    Lines.Add('    private static final String DEFAULT_BASE_URL = ' +
      Java_Str_Lit(BaseUrl).Text + ';');
    Lines.Add('');
    Lines.Add('    private static final ObjectMapper MAPPER = new ObjectMapper();');
    Lines.Add('    private static final HttpClient HTTP = HttpClient.newBuilder()');
    Lines.Add('            .connectTimeout(Duration.ofSeconds(10))');
    Lines.Add('            .build();');
    Lines.Add('');
    Lines.Add('    private static void callApi(String baseUrl, String apiName, List<?> args) throws Exception {');
    Lines.Add('        Map<String, Object> body = new LinkedHashMap<>();');
    Lines.Add('        if (args != null && !args.isEmpty()) {');
    Lines.Add('            body.put("args", args);');
    Lines.Add('        }');
    Lines.Add('        String bodyText = MAPPER.writeValueAsString(body);');
    Lines.Add('');
    Lines.Add('        String url = baseUrl.replaceAll("/+$", "") + "/" + apiName;');
    Lines.Add('        HttpRequest req = HttpRequest.newBuilder()');
    Lines.Add('                .uri(URI.create(url))');
    Lines.Add('                .timeout(Duration.ofSeconds(10))');
    Lines.Add('                .header("Content-Type", "application/json; charset=utf-8")');
    Lines.Add('                .POST(HttpRequest.BodyPublishers.ofString(');
    Lines.Add('                        bodyText, StandardCharsets.UTF_8))');
    Lines.Add('                .build();');
    Lines.Add('');
    Lines.Add('        HttpResponse<String> resp = HTTP.send(');
    Lines.Add('                req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));');
    Lines.Add('        int status = resp.statusCode();');
    Lines.Add('        String text = resp.body();');
    Lines.Add('');
    Lines.Add('        if (status != 200) {');
    Lines.Add('            throw new RuntimeException("HTTP " + status + ": " + text);');
    Lines.Add('        }');
    Lines.Add('        if (text == null || text.isEmpty()) {');
    Lines.Add('            throw new RuntimeException("Empty response from bridge");');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        JsonNode parsed = MAPPER.readTree(text);');
    Lines.Add('        if (parsed == null || !parsed.isObject()) {');
    Lines.Add('            throw new RuntimeException("Response is not a JSON object");');
    Lines.Add('        }');
    Lines.Add('        JsonNode codeNode = parsed.get("code");');
    Lines.Add('        if (codeNode == null) {');
    Lines.Add('            JsonNode errNode = parsed.get("error");');
    Lines.Add('            throw new RuntimeException(');
    Lines.Add('                    errNode != null ? errNode.asText()');
    Lines.Add('                            : "Response has no code field");');
    Lines.Add('        }');
    Lines.Add('        if (codeNode.asInt() != 0) {');
    Lines.Add('            JsonNode errNode = parsed.get("error");');
    Lines.Add('            throw new RuntimeException(');
    Lines.Add('                    errNode != null ? errNode.asText()');
    Lines.Add('                            : "Remote call failed (code="');
    Lines.Add('                                    + codeNode.asInt() + ")");');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      Lines.Add('    private static void call_' + ApiName.Text +
        '(String baseUrl) throws Exception {');
      if Length(F.Params) > 0 then
        Lines.Add('        callApi(baseUrl, ' + Java_Str_Lit(ApiName).Text +
          ', List.of(' + BuildJavaArgLitList(F.Params) + '));')
      else
        Lines.Add('        callApi(baseUrl, ' + Java_Str_Lit(ApiName).Text +
          ', List.of());');
      Lines.Add('    }');
      Lines.Add('');
    end;

    Lines.Add('    public static void main(String[] args) throws Exception {');
    Lines.Add('        String baseUrl = (args.length >= 1 && args[0] != null && !args[0].isEmpty())');
    Lines.Add('                ? args[0]');
    Lines.Add('                : DEFAULT_BASE_URL;');
    Lines.Add('');
    Lines.Add('        System.out.println("=== ' + UnitName.Text + ' HTTP/JSON call test ===");');
    Lines.Add('        System.out.println();');
    Lines.Add('        System.out.println("Base URL: " + baseUrl);');
    Lines.Add('        System.out.println();');
    Lines.Add('');
    Lines.Add('        int ok = 0;');
    Lines.Add('        int fail = 0;');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Lines.Add('        // ---- ' + ApiName.Text + ' ----');
      Lines.Add('        try {');
      Lines.Add('            call_' + ApiName.Text + '(baseUrl);');
      Lines.Add('            System.out.println("  ' + ApiName.Text + ': OK");');
      Lines.Add('            ok++;');
      Lines.Add('        } catch (Throwable t) {');
      Lines.Add('            System.err.println("  ' + ApiName.Text + ': FAILED: " + t.getMessage());');
      Lines.Add('            fail++;');
      Lines.Add('        }');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('        // (no supported routines)');

    Lines.Add('        System.out.println();');
    Lines.Add('        System.out.println("=== Summary ===");');
    Lines.Add('        System.out.println("Passed: " + ok);');
    Lines.Add('        System.out.println("Failed: " + fail);');
    Lines.Add('');
    Lines.Add('        if (fail != 0) {');
    Lines.Add('            System.exit(1);');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private ' + TestClass.Text + '() {');
    Lines.Add('        // Utility class; no instances.');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'java', 'Java HTTP/JSON service test program',
    asService, akTestCode,
    'HttpJsonServiceTest.java', False,
    @GenerateHTTPServiceJavaTestCode);
  RegisterCodeGenEntry(
    'java', 'Java HTTP/JSON call test program',
    asCall, akTestCode,
    'HttpJsonCallTest.java', False,
    @GenerateHTTPCallJavaTestCode);
end.
