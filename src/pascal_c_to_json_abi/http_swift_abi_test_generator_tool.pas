unit http_swift_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceSwiftTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallSwiftTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_swift_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_swift_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification
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

function ABI_Type_To_Swift_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'Double'
  else if ABI_Type_Is_Int(T) then
    Result := 'Int64'
  else
    Result := 'Void';
end;

function ABI_Type_To_Swift_Default_Literal(const T: TP_String): TP_String;
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

function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
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

function IsSwiftReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('class') or S.Same('struct') or S.Same('enum') or S.Same('func') or
    S.Same('var') or S.Same('let') or S.Same('if') or S.Same('else') or
    S.Same('for') or S.Same('while') or S.Same('return') or S.Same('self') or
    S.Same('Self') or S.Same('import') or S.Same('true') or S.Same('false') or
    S.Same('nil') or S.Same('as') or S.Same('is') or S.Same('in') or
    S.Same('where') or S.Same('static') or S.Same('public') or S.Same('private') or
    S.Same('internal') or S.Same('fileprivate') or S.Same('switch') or S.Same('case') or
    S.Same('default') or S.Same('break') or S.Same('continue') or S.Same('throw') or
    S.Same('throws') or S.Same('rethrows') or S.Same('try') or S.Same('defer') or
    S.Same('do') or S.Same('catch') or S.Same('guard') or S.Same('protocol') or
    S.Same('extension') or S.Same('init') or S.Same('deinit') or S.Same('subscript') or
    S.Same('typealias') or S.Same('associatedtype') or S.Same('operator') or S.Same('precedencegroup') or
    S.Same('inout') or S.Same('mutating') or S.Same('nonmutating') or S.Same('convenience') or
    S.Same('required') or S.Same('lazy') or S.Same('weak') or S.Same('unowned') or
    S.Same('open') or S.Same('super') or S.Same('await') or S.Same('actor') or
    S.Same('async') or S.Same('some') or S.Same('any');
end;

function MakeSafeSwiftIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsSwiftReservedWord(Result) then
    Result := Result + '_';
end;

function SwiftStrLit(const S: TP_String): TP_String;
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
      else
        if (code < 32) or (code = 127) then
        begin
          Result.Append('\u{');
          Result.Append(HEXDIG[((code shr 4) and $F) + 1]);
          Result.Append(HEXDIG[(code and $F) + 1]);
          Result.Append('}');
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
      // skip
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

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeSwiftIdent(F.Params[i].Name, i);
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

function BuildSwiftArgArray(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  if Length(Params) = 0 then
  begin
    Result := '[]';
    Exit;
  end;
  Result := '[';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Swift_Default_Literal(Params[i].PascalType);
  end;
  Result := Result + ']';
end;

function BuildJsonArgsBody(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  if Length(Params) = 0 then
  begin
    Result := '{}';
    Exit;
  end;
  Result := '{"args": [';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Json_Default_Literal(Params[i].PascalType);
  end;
  Result := Result + ']}';
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

function GenerateHTTPServiceSwiftTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, Endpoint, TestStructName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, RequestJson: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceSwiftTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceSwiftTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  TestStructName := NormalizedUnit + 'HttpJsonServiceTest';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// -*- coding: utf-8 -*-');
    Lines.Add('// Auto-generated by http_swift_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service-side test program for the Swift HTTP/JSON service.');
    Lines.Add('//');
    Lines.Add('// Pairs with ' + NormalizedUnit.Text + '_http_json_service_swift.swift.');
    Lines.Add('//');
    Lines.Add('// Modes:');
    Lines.Add('//   (default)   Delegate to ' + NormalizedUnit.Text + 'HttpJsonService.main().');
    Lines.Add('//   --smoke     In-process LocalCall self-tests. Uses');
    Lines.Add('//               ' + NormalizedUnit.Text + 'HttpJsonService.runService() to');
    Lines.Add('//               bootstrap the App, then invokes every API via');
    Lines.Add('//               AppHandle.localCall. No bridge.py, no network.');
    Lines.Add('//');
    Lines.Add('// Target: Swift 5.9+ (macOS 12+ / iOS 15+).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('import Foundation');
    Lines.Add('import LingoFuse');
    Lines.Add('');
    Lines.Add('@main');
    Lines.Add('struct ' + TestStructName.Text + ' {');
    Lines.Add('');

    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // Smoke-mode helpers');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    static func smokeCall(_ app: AppHandle,');
    Lines.Add('                          apiName: String,');
    Lines.Add('                          requestJson: String) -> (Bool, String) {');
    Lines.Add('        do {');
    Lines.Add('            let req = try DataHandle(apiName: apiName)');
    Lines.Add('            defer { req.dispose() }');
    Lines.Add('');
    Lines.Add('            guard let encoded = requestJson.data(using: .utf8) else {');
    Lines.Add('                return (false, "encode failed")');
    Lines.Add('            }');
    Lines.Add('            try LfIo.writeStringBytes(req, [UInt8](encoded))');
    Lines.Add('            req.position = 0');
    Lines.Add('');
    Lines.Add('            let resp = try app.localCall(req)');
    Lines.Add('            defer { resp.dispose() }');
    Lines.Add('');
    Lines.Add('            let text = try LfIo.readString(resp)');
    Lines.Add('            if text.isEmpty {');
    Lines.Add('                return (false, "empty response")');
    Lines.Add('            }');
    Lines.Add('');
    Lines.Add('            guard let data = text.data(using: .utf8),');
    Lines.Add('                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {');
    Lines.Add('                return (false, "invalid JSON: \(text)")');
    Lines.Add('            }');
    Lines.Add('            guard let code = (obj["code"] as? NSNumber)?.intValue else {');
    Lines.Add('                return (false, "response has no code field")');
    Lines.Add('            }');
    Lines.Add('            if code != 0 {');
    Lines.Add('                let msg = (obj["error"] as? String) ?? "code=\(code)"');
    Lines.Add('                return (false, msg)');
    Lines.Add('            }');
    Lines.Add('            return (true, "OK")');
    Lines.Add('        } catch {');
    Lines.Add('            return (false, "\(error)")');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // Smoke mode');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    static func runSmoke() -> Int32 {');
    Lines.Add('        let svc = ' + NormalizedUnit.Text + 'HttpJsonService.self');
    Lines.Add('        svc.debugLog = true');
    Lines.Add('');
    Lines.Add('        print("[smoke] running in-process LocalCall self-tests")');
    Lines.Add('        print("[smoke] this mode does NOT start bridge.py and does NOT need the network")');
    Lines.Add('        print()');
    Lines.Add('');
    Lines.Add('        let app: AppHandle');
    Lines.Add('        do {');
    Lines.Add('            app = try svc.runService()');
    Lines.Add('        } catch {');
    Lines.Add('            FileHandle.standardError.write(');
    Lines.Add('                "[smoke] failed to start: \(error)\n".data(using: .utf8)!)');
    Lines.Add('            return 1');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        var ok = 0');
    Lines.Add('        var fail = 0');
    Lines.Add('');
    Lines.Add('        let cases: [(String, String)] = [');

    if Length(SupportedFuncs) = 0 then
      Lines.Add('            // (no supported routines)')
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        RequestJson := BuildJsonArgsBody(F.Params);
        Lines.Add('            (' + SwiftStrLit(ApiName).Text + ', ' +
          SwiftStrLit(RequestJson).Text + '),');
      end;
    end;

    Lines.Add('        ]');
    Lines.Add('');
    Lines.Add('        for (apiName, requestJson) in cases {');
    Lines.Add('            let (success, msg) = smokeCall(app, apiName: apiName, requestJson: requestJson)');
    Lines.Add('            if success {');
    Lines.Add('                print("  \(apiName): OK")');
    Lines.Add('                ok += 1');
    Lines.Add('            } else {');
    Lines.Add('                FileHandle.standardError.write(');
    Lines.Add('                    "  \(apiName): FAILED: \(msg)\n".data(using: .utf8)!)');
    Lines.Add('                fail += 1');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        print()');
    Lines.Add('        print("=== Smoke test summary ===")');
    Lines.Add('        print("Passed: \(ok)")');
    Lines.Add('        print("Failed: \(fail)")');
    Lines.Add('');
    Lines.Add('        NetworkEvents.clearNetworkEvent()');
    Lines.Add('        Framework.exitMainThread()');
    Lines.Add('        app.dispose()');
    Lines.Add('        Framework.shutdown()');
    Lines.Add('        LF_FreeLibrary()');
    Lines.Add('');
    Lines.Add('        return fail == 0 ? 0 : 1');
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    static func main() {');
    Lines.Add('        if CommandLine.arguments.contains("--smoke") {');
    Lines.Add('            let code = runSmoke()');
    Lines.Add('            exit(code)');
    Lines.Add('        }');
    Lines.Add('        ' + NormalizedUnit.Text + 'HttpJsonService.main()');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated Swift service test program: %d lines, %d routines.',
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

function GenerateHTTPCallSwiftTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, BaseUrl, TestStructName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, ArgArray: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallSwiftTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallSwiftTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  TestStructName := NormalizedUnit + 'HttpJsonCallTest';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// -*- coding: utf-8 -*-');
    Lines.Add('// Auto-generated by http_swift_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side test program for the Swift HTTP/JSON service.');
    Lines.Add('//');
    Lines.Add('// Drives the wire protocol directly with URLSession +');
    Lines.Add('// JSONSerialization. Does NOT import the generated call module and');
    Lines.Add('// does NOT import LingoFuse.');
    Lines.Add('//');
    Lines.Add('// Target: Swift 5.9+ (macOS 12+ / iOS 15+ for the async pass).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('import Foundation');
    Lines.Add('#if canImport(FoundationNetworking)');
    Lines.Add('import FoundationNetworking');
    Lines.Add('#endif');
    Lines.Add('import Dispatch');
    Lines.Add('');
    Lines.Add('@main');
    Lines.Add('struct ' + TestStructName.Text + ' {');
    Lines.Add('');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // Configuration');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    static let baseUrl: String = ' + SwiftStrLit(BaseUrl).Text);
    Lines.Add('    static let timeout: TimeInterval = 30.0');
    Lines.Add('');

    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // Transport helpers');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    static func makeRequest(apiName: String, args: [Any]) throws -> URLRequest {');
    Lines.Add('        var base = baseUrl');
    Lines.Add('        while base.hasSuffix("/") { base.removeLast() }');
    Lines.Add('        guard let url = URL(string: base + "/" + apiName) else {');
    Lines.Add('            throw NSError(domain: "CallTest", code: -1,');
    Lines.Add('                          userInfo: [NSLocalizedDescriptionKey: "invalid URL"])');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        var req = URLRequest(url: url)');
    Lines.Add('        req.httpMethod = "POST"');
    Lines.Add('        req.timeoutInterval = timeout');
    Lines.Add('        req.setValue("application/json; charset=utf-8",');
    Lines.Add('                     forHTTPHeaderField: "Content-Type")');
    Lines.Add('        req.httpBody = try JSONSerialization.data(');
    Lines.Add('            withJSONObject: ["args": args])');
    Lines.Add('        return req');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static func parseEnvelope(_ data: Data, httpStatus: Int) -> (Bool, String) {');
    Lines.Add('        if data.isEmpty {');
    Lines.Add('            return (false, "empty response")');
    Lines.Add('        }');
    Lines.Add('        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {');
    Lines.Add('            return (false, "invalid JSON response")');
    Lines.Add('        }');
    Lines.Add('        if httpStatus != 200 {');
    Lines.Add('            let msg = (obj["error"] as? String)');
    Lines.Add('                ?? "HTTP \(httpStatus)"');
    Lines.Add('            return (false, msg)');
    Lines.Add('        }');
    Lines.Add('        guard let code = (obj["code"] as? NSNumber)?.intValue else {');
    Lines.Add('            let msg = (obj["error"] as? String) ?? "response has no code field"');
    Lines.Add('            return (false, msg)');
    Lines.Add('        }');
    Lines.Add('        if code != 0 {');
    Lines.Add('            let msg = (obj["error"] as? String) ?? "code=\(code)"');
    Lines.Add('            return (false, msg)');
    Lines.Add('        }');
    Lines.Add('        return (true, "OK")');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // _CallResultBox - shared mutable state for the blocking sync path.');
    Lines.Add('    //');
    Lines.Add('    // @unchecked Sendable is safe because:');
    Lines.Add('    //   * Only the URLSession completion handler writes it.');
    Lines.Add('    //   * Only the caller blocked on DispatchSemaphore reads it.');
    Lines.Add('    //   * sema.signal() / sema.wait() establishes the happens-before');
    Lines.Add('    //     relationship that the Swift concurrency checker cannot see');
    Lines.Add('    //     across a C-level callback boundary.');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    final class _CallResultBox: @unchecked Sendable {');
    Lines.Add('        var payload: Data = Data()');
    Lines.Add('        var status: Int = 0');
    Lines.Add('        var netError: Error? = nil');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static func httpPost(apiName: String, args: [Any]) -> (Bool, String) {');
    Lines.Add('        let req: URLRequest');
    Lines.Add('        do {');
    Lines.Add('            req = try makeRequest(apiName: apiName, args: args)');
    Lines.Add('        } catch {');
    Lines.Add('            return (false, "encode failed: \(error)")');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        let sema = DispatchSemaphore(value: 0)');
    Lines.Add('        let box = _CallResultBox()');
    Lines.Add('');
    Lines.Add('        let task = URLSession.shared.dataTask(with: req) { data, resp, err in');
    Lines.Add('            box.payload = data ?? Data()');
    Lines.Add('            box.status = (resp as? HTTPURLResponse)?.statusCode ?? 0');
    Lines.Add('            box.netError = err');
    Lines.Add('            sema.signal()');
    Lines.Add('        }');
    Lines.Add('        task.resume()');
    Lines.Add('        sema.wait()');
    Lines.Add('');
    Lines.Add('        if let e = box.netError {');
    Lines.Add('            return (false, "network error: \(e.localizedDescription)")');
    Lines.Add('        }');
    Lines.Add('        return parseEnvelope(box.payload, httpStatus: box.status)');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    @available(macOS 12.0, iOS 15.0, *)');
    Lines.Add('    static func httpPostAsync(apiName: String, args: [Any]) async -> (Bool, String) {');
    Lines.Add('        let req: URLRequest');
    Lines.Add('        do {');
    Lines.Add('            req = try makeRequest(apiName: apiName, args: args)');
    Lines.Add('        } catch {');
    Lines.Add('            return (false, "encode failed: \(error)")');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        do {');
    Lines.Add('            let (data, resp) = try await URLSession.shared.data(for: req)');
    Lines.Add('            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0');
    Lines.Add('            return parseEnvelope(data, httpStatus: status)');
    Lines.Add('        } catch {');
    Lines.Add('            return (false, "network error: \(error.localizedDescription)")');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // Per-run counters');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    final class Counters {');
    Lines.Add('        var ok: Int = 0');
    Lines.Add('        var fail: Int = 0');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static func report(_ c: Counters, name: String, variant: String,');
    Lines.Add('                       result: (Bool, String)) {');
    Lines.Add('        if result.0 {');
    Lines.Add('            print("  \(name) [\(variant)]: OK")');
    Lines.Add('            c.ok += 1');
    Lines.Add('        } else {');
    Lines.Add('            FileHandle.standardError.write(');
    Lines.Add('                "  \(name) [\(variant)]: FAILED: \(result.1)\n"');
    Lines.Add('                    .data(using: .utf8)!)');
    Lines.Add('            c.fail += 1');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    static func runSyncPass(_ c: Counters) {');
    Lines.Add('        print("--- Synchronous pass ---")');
    Lines.Add('        print()');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ArgArray := BuildSwiftArgArray(F.Params);
      Lines.Add('        report(c, name: ' + SwiftStrLit(ApiName).Text +
        ', variant: "sync",');
      Lines.Add('               result: httpPost(apiName: ' + SwiftStrLit(ApiName).Text +
        ', args: ' + ArgArray.Text + '))');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('        // (no supported routines)');

    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    @available(macOS 12.0, iOS 15.0, *)');
    Lines.Add('    static func runAsyncPass(_ c: Counters) async {');
    Lines.Add('        print("--- Asynchronous pass ---")');
    Lines.Add('        print()');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ArgArray := BuildSwiftArgArray(F.Params);
      Lines.Add('        report(c, name: ' + SwiftStrLit(ApiName).Text +
        ', variant: "async",');
      Lines.Add('               result: await httpPostAsync(apiName: ' + SwiftStrLit(ApiName).Text +
        ', args: ' + ArgArray.Text + '))');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('        // (no supported routines)');

    Lines.Add('    }');
    Lines.Add('');

    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('    // Entry point');
    Lines.Add('    //');
    Lines.Add('    // The async pass is driven through dispatchMain(): on Windows /');
    Lines.Add('    // Linux a Task { } created inside a synchronous main() does not');
    Lines.Add('    // run unless the main thread is inside a dispatch or run loop.');
    Lines.Add('    // Dispatching the summary/exit work into the Task lets the');
    Lines.Add('    // program terminate as soon as the async pass completes.');
    Lines.Add('    // ------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    static func main() {');
    Lines.Add('        print("=== ' + UnitName.Text + ' HTTP/JSON call test ===")');
    Lines.Add('        print()');
    Lines.Add('        print("Base URL: \\(baseUrl)")');
    Lines.Add('        print("Timeout : \\(timeout)s")');
    Lines.Add('        print()');
    Lines.Add('');
    Lines.Add('        let counters = Counters()');
    Lines.Add('');
    Lines.Add('        // 1. Synchronous pass (runs to completion inline).');
    Lines.Add('        runSyncPass(counters)');
    Lines.Add('');
    Lines.Add('        // 2. Asynchronous pass (driven via dispatchMain).');
    Lines.Add('        if #available(macOS 12.0, iOS 15.0, *) {');
    Lines.Add('            Task {');
    Lines.Add('                await runAsyncPass(counters)');
    Lines.Add('                printSummaryAndExit(counters)');
    Lines.Add('            }');
    Lines.Add('            dispatchMain()');
    Lines.Add('        } else {');
    Lines.Add('            print()');
    Lines.Add('            print("(async pass skipped: requires macOS 12.0 / iOS 15.0+)")');
    Lines.Add('            printSummaryAndExit(counters)');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    static func printSummaryAndExit(_ counters: Counters) -> Never {');
    Lines.Add('        print()');
    Lines.Add('        print("=== Summary ===")');
    Lines.Add('        print("Passed: \\(counters.ok)")');
    Lines.Add('        print("Failed: \\(counters.fail)")');
    Lines.Add('        exit(counters.fail == 0 ? 0 : 1)');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated Swift call test program: %d lines, %d routines (sync + async).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'swift', 'Swift HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.swift', False,
    @GenerateHTTPServiceSwiftTestCode);
  RegisterCodeGenEntry(
    'swift', 'Swift HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.swift', False,
    @GenerateHTTPCallSwiftTestCode);
end.
