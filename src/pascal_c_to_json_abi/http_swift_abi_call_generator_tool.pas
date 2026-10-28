unit http_swift_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallSwiftCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_swift_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_swift_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification (mirrors every other generator)
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

function ABI_Type_To_Swift_Extract(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'return (value as? String) ?? ""'
  else if ABI_Type_Is_Float(T) then
    Result := 'return (value as? NSNumber)?.doubleValue ?? 0.0'
  else if ABI_Type_Is_Int(T) then
    Result := 'return (value as? NSNumber)?.int64Value ?? 0'
  else
    Result := 'return'
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

// SwiftStrLit - produce a complete double-quoted Swift string literal
// with the surrounding quotes included.
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
      '"': Result.Append('\"');
      '\': Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9:  Result.Append('\t');
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
// Markdown helpers (used by the README generator only)
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
// Comment description extraction (kept identical across all generators)
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

// BuildSwiftParamDecl - `_ a: Int64, _ b: Int64` for a parameter list.
// The `_` prefix gives the parameter no external label, so call sites
// can pass positional arguments exactly like Python / Rust / Java.
function BuildSwiftParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, t: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeSwiftIdent(Params[i].Name, i);
    t := ABI_Type_To_Swift_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + '_ ' + n + ': ' + t;
  end;
end;

// BuildSwiftArgList - `a, b, c` for a call-site argument list.
function BuildSwiftArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeSwiftIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildSwiftDefaultArgList - `0, 0.0, ""` for a parameter list. Used
// by the README generator only.
function BuildSwiftDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Swift_Default_Literal(Params[i].PascalType);
  end;
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

// BuildSwiftSyncSignature - full Swift sync signature, used by the README only.
function BuildSwiftSyncSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  RetType: TP_String;
begin
  if F.IsFunction then
    RetType := ' -> ' + ABI_Type_To_Swift_Type(F.ReturnType)
  else
    RetType := '';
  Result := 'public static func ' + ApiName + '(' +
    BuildSwiftParamDecl(F.Params) + ')' + RetType;
end;

// BuildSwiftAsyncSignature - full Swift async signature, used by the README only.
function BuildSwiftAsyncSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  RetType: TP_String;
begin
  if F.IsFunction then
    RetType := ' async throws -> ' + ABI_Type_To_Swift_Type(F.ReturnType)
  else
    RetType := ' async throws';
  Result := 'public static func ' + ApiName + '_async(' +
    BuildSwiftParamDecl(F.Params) + ')' + RetType;
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
// SWIFT CALL MODULE GENERATOR
// =============================================================================

procedure EmitSwiftHeader(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('// -*- coding: utf-8 -*-');
  Lines.Add('// Auto-generated by http_swift_abi_call_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI call-side module for Swift.');
  Lines.Add('//');
  Lines.Add('// Every supported routine has TWO functions:');
  Lines.Add('//   * `public static func <ApiName>(...) throws -> T`');
  Lines.Add('//        - synchronous (blocking via DispatchSemaphore)');
  Lines.Add('//   * `public static func <ApiName>_async(...) async throws -> T`');
  Lines.Add('//        - asynchronous (uses URLSession.data(for:) / async-await)');
  Lines.Add('//');
  Lines.Add('// Wire protocol:');
  Lines.Add('//   request  = POST <base_url>/<api>');
  Lines.Add('//              Content-Type: application/json; charset=utf-8');
  Lines.Add('//              Body: { "args": [v1, v2, ...] }');
  Lines.Add('//');
  Lines.Add('//   response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//              { "code": -1, "error":  "<message>" } on failure');
  Lines.Add('//');
  Lines.Add('// Dependencies: Foundation only. No LingoFuse / no native DLL.');
  Lines.Add('//');
  Lines.Add('// Usage:');
  Lines.Add('//   import Foundation');
  Lines.Add('//');
  Lines.Add('//   do {');
  Lines.Add('//       let r = try ' + UnitName.Text + 'HttpJsonClient.Add(1, 2)');
  Lines.Add('//       print("Add(1, 2) = \\(r)")');
  Lines.Add('//   } catch {');
  Lines.Add('//       print("Add failed: \\(error)")');
  Lines.Add('//   }');
  Lines.Add('//');
  Lines.Add('//   Task {');
  Lines.Add('//       let r = try await ' + UnitName.Text + 'HttpJsonClient.Add_async(1, 2)');
  Lines.Add('//       print("Add_async(1, 2) = \\(r)")');
  Lines.Add('//   }');
  Lines.Add('');
  Lines.Add('import Foundation');
  Lines.Add('#if canImport(FoundationNetworking)');
  Lines.Add('import FoundationNetworking');
  Lines.Add('#endif');
  Lines.Add('import Dispatch');
  Lines.Add('');
end;

procedure EmitSwiftConfig(Lines: TPascalStringList;
  const NormalizedUnit, BaseUrl: TP_String);
begin
  Lines.Add('public enum ' + NormalizedUnit.Text + 'HttpJsonClient {');
  Lines.Add('');
  Lines.Add('    /// Base URL of the target bridge, including the target app name.');
  Lines.Add('    public static var baseUrl: String = ' + SwiftStrLit(BaseUrl).Text);
  Lines.Add('');
  Lines.Add('    /// Default per-request timeout, in seconds.');
  Lines.Add('    public static var timeout: TimeInterval = 30.0');
  Lines.Add('');
  Lines.Add('    /// Set to true to log every request and response on stderr.');
  Lines.Add('    public static var debugLog: Bool = false');
  Lines.Add('');
end;

procedure EmitSwiftError(Lines: TPascalStringList);
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Error type');
  Lines.Add('    //');
  Lines.Add('    // The single exception type raised by every generated function.');
  Lines.Add('    //');
  Lines.Add('    //   code        : the numeric code from the bridge / service response,');
  Lines.Add('    //                 or -1 for transport-level failures.');
  Lines.Add('    //   httpStatus  : the HTTP status code, or 0 when no response was');
  Lines.Add('    //                 received (network error, timeout, ...).');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('    public struct HTTPCallError: Error, CustomStringConvertible {');
  Lines.Add('        public let message: String');
  Lines.Add('        public let code: Int');
  Lines.Add('        public let httpStatus: Int');
  Lines.Add('');
  Lines.Add('        public init(_ message: String, code: Int = -1, httpStatus: Int = 0) {');
  Lines.Add('            self.message = message');
  Lines.Add('            self.code = code');
  Lines.Add('            self.httpStatus = httpStatus');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public var description: String {');
  Lines.Add('            return "\(message) (code=\(code), http_status=\(httpStatus))"');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSwiftTransport(Lines: TPascalStringList);
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Internal transport');
  Lines.Add('    //');
  Lines.Add('    // Two transport functions, one per calling convention:');
  Lines.Add('    //   * callSync   - uses URLSession + DispatchSemaphore (blocking)');
  Lines.Add('    //   * callAsync  - uses URLSession.data(for:) (async/await)');
  Lines.Add('    //');
  Lines.Add('    // Both implement the same wire protocol:');
  Lines.Add('    //   POST <base>/<api>  body={"args":[...]}');
  Lines.Add('    //   read response       -> {code, result} or {code, error}');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('    private static func url(for apiName: String) -> URL {');
  Lines.Add('        var base = baseUrl');
  Lines.Add('        while base.hasSuffix("/") { base.removeLast() }');
  Lines.Add('        return URL(string: base + "/" + apiName)!');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func makeRequest(apiName: String, args: [Any]) throws -> URLRequest {');
  Lines.Add('        let envelope: [String: Any] = ["args": args]');
  Lines.Add('        let body = try JSONSerialization.data(withJSONObject: envelope)');
  Lines.Add('');
  Lines.Add('        var req = URLRequest(url: url(for: apiName))');
  Lines.Add('        req.httpMethod = "POST"');
  Lines.Add('        req.timeoutInterval = timeout');
  Lines.Add('        req.setValue("application/json; charset=utf-8",');
  Lines.Add('                     forHTTPHeaderField: "Content-Type")');
  Lines.Add('        req.httpBody = body');
  Lines.Add('');
  Lines.Add('        if debugLog {');
  Lines.Add('            let text = String(data: body, encoding: .utf8) ?? "<binary>"');
  Lines.Add('            if let line = "[http-json] POST \(req.url!.absoluteString) body=\(text)\n".data(using: .utf8) {');
  Lines.Add('                FileHandle.standardError.write(line)');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        return req');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func parseResponse(_ data: Data, httpStatus: Int) throws -> Any? {');
  Lines.Add('        guard !data.isEmpty else {');
  Lines.Add('            throw HTTPCallError("Empty response from bridge",');
  Lines.Add('                                code: -1, httpStatus: httpStatus)');
  Lines.Add('        }');
  Lines.Add('        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {');
  Lines.Add('            throw HTTPCallError("Invalid JSON response",');
  Lines.Add('                                code: -1, httpStatus: httpStatus)');
  Lines.Add('        }');
  Lines.Add('        if httpStatus != 200 {');
  Lines.Add('            let msg = (obj["error"] as? String)');
  Lines.Add('                ?? "HTTP \(httpStatus): \(String(data: data, encoding: .utf8) ?? "")"');
  Lines.Add('            throw HTTPCallError(msg, code: -1, httpStatus: httpStatus)');
  Lines.Add('        }');
  Lines.Add('        guard let codeNum = obj["code"] as? NSNumber else {');
  Lines.Add('            let msg = (obj["error"] as? String) ?? "Response has no code field"');
  Lines.Add('            throw HTTPCallError(msg, code: -1, httpStatus: httpStatus)');
  Lines.Add('        }');
  Lines.Add('        let code = codeNum.intValue');
  Lines.Add('        if code != 0 {');
  Lines.Add('            let msg = (obj["error"] as? String) ?? "Remote call failed"');
  Lines.Add('            throw HTTPCallError(msg, code: code, httpStatus: httpStatus)');
  Lines.Add('        }');
  Lines.Add('        if let result = obj["result"], !(result is NSNull) {');
  Lines.Add('            return result');
  Lines.Add('        }');
  Lines.Add('        return nil');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /// Synchronous call (blocking via DispatchSemaphore).');
  Lines.Add('    private static func callSync(apiName: String, args: [Any]) throws -> Any? {');
  Lines.Add('        let req = try makeRequest(apiName: apiName, args: args)');
  Lines.Add('');
  Lines.Add('        let sema = DispatchSemaphore(value: 0)');
  Lines.Add('        let box = _SyncResultBox()');
  Lines.Add('        let task = URLSession.shared.dataTask(with: req) { data, resp, err in');
  Lines.Add('            if let err = err {');
  Lines.Add('                box.value = .failure(err)');
  Lines.Add('            } else {');
  Lines.Add('                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0');
  Lines.Add('                box.value = .success((data ?? Data(), status))');
  Lines.Add('            }');
  Lines.Add('            sema.signal()');
  Lines.Add('        }');
  Lines.Add('        task.resume()');
  Lines.Add('        sema.wait()');
  Lines.Add('');
  Lines.Add('        guard let r = box.value else {');
  Lines.Add('            throw HTTPCallError("No response from URLSession", code: -1)');
  Lines.Add('        }');
  Lines.Add('        switch r {');
  Lines.Add('        case .failure(let e):');
  Lines.Add('            throw HTTPCallError("Network error: \(e.localizedDescription)", code: -1)');
  Lines.Add('        case .success(let pair):');
  Lines.Add('            return try parseResponse(pair.0, httpStatus: pair.1)');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /// Asynchronous call (async/await).');
  Lines.Add('    @available(macOS 12.0, iOS 15.0, *)');
  Lines.Add('    private static func callAsync(apiName: String, args: [Any]) async throws -> Any? {');
  Lines.Add('        let req = try makeRequest(apiName: apiName, args: args)');
  Lines.Add('        let data: Data');
  Lines.Add('        let resp: URLResponse');
  Lines.Add('        do {');
  Lines.Add('            (data, resp) = try await URLSession.shared.data(for: req)');
  Lines.Add('        } catch {');
  Lines.Add('            throw HTTPCallError("Network error: \(error.localizedDescription)", code: -1)');
  Lines.Add('        }');
  Lines.Add('        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0');
  Lines.Add('        return try parseResponse(data, httpStatus: status)');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSwiftFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, ArgList, RetType, ExtractExpr: TP_String;
  Description: TP_String;
  HasParams: boolean;
begin
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('    // Typed API functions');
  Lines.Add('    //');
  Lines.Add('    // Every routine has TWO functions:');
  Lines.Add('    //   * `public static func <ApiName>(...)` - synchronous');
  Lines.Add('    //   * `public static func <ApiName>_async(...)` - asynchronous');
  Lines.Add('    // ------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildSwiftParamDecl(F.Params);
    ArgList := BuildSwiftArgList(F.Params);
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;
    HasParams := Length(F.Params) > 0;

    if F.IsFunction then
    begin
      RetType := ABI_Type_To_Swift_Type(F.ReturnType);
      ExtractExpr := ABI_Type_To_Swift_Extract(F.ReturnType);
    end
    else
    begin
      RetType := 'Void';
      ExtractExpr := '';
    end;

    // ---- Synchronous variant ------------------------------------------
    Lines.Add('    /// ' + Description.Text);
    Lines.Add('    ///');
    Lines.Add('    /// HTTP route: POST /' + ApiName.Text + ' (relative to baseUrl).');
    Lines.Add('    /// This variant blocks the calling thread.');
    if F.IsFunction then
      Lines.Add('    /// Returns: the remote result (' + RetType.Text + ').')
    else
      Lines.Add('    /// Returns: nothing on success.');
    Lines.Add('    /// Errors: `HTTPCallError` on any failure.');

    if F.IsFunction then
    begin
      if HasParams then
        Lines.Add('    public static func ' + ApiName.Text + '(' + ParamDecl.Text + ') throws -> ' + RetType.Text + ' {')
      else
        Lines.Add('    public static func ' + ApiName.Text + '() throws -> ' + RetType.Text + ' {');
      Lines.Add('        let value = try callSync(apiName: ' + SwiftStrLit(ApiName).Text + ', args: [' + ArgList.Text + '])');
      Lines.Add('        ' + ExtractExpr.Text);
    end
    else
    begin
      if HasParams then
        Lines.Add('    public static func ' + ApiName.Text + '(' + ParamDecl.Text + ') throws {')
      else
        Lines.Add('    public static func ' + ApiName.Text + '() throws {');
      Lines.Add('        _ = try callSync(apiName: ' + SwiftStrLit(ApiName).Text + ', args: [' + ArgList.Text + '])');
    end;
    Lines.Add('    }');
    Lines.Add('');

    // ---- Asynchronous variant -----------------------------------------
    Lines.Add('    /// ' + Description.Text + ' (asynchronous)');
    Lines.Add('    ///');
    Lines.Add('    /// HTTP route: POST /' + ApiName.Text + ' (relative to baseUrl).');
    Lines.Add('    /// Must be awaited inside an `async` context.');
    if F.IsFunction then
      Lines.Add('    /// Resolves with: the remote result (' + RetType.Text + ').')
    else
      Lines.Add('    /// Resolves with: nothing.');
    Lines.Add('    /// Rejects with: `HTTPCallError` on any failure.');
    Lines.Add('    @available(macOS 12.0, iOS 15.0, *)');

    if F.IsFunction then
    begin
      if HasParams then
        Lines.Add('    public static func ' + ApiName.Text + '_async(' + ParamDecl.Text + ') async throws -> ' + RetType.Text + ' {')
      else
        Lines.Add('    public static func ' + ApiName.Text + '_async() async throws -> ' + RetType.Text + ' {');
      Lines.Add('        let value = try await callAsync(apiName: ' + SwiftStrLit(ApiName).Text + ', args: [' + ArgList.Text + '])');
      Lines.Add('        ' + ExtractExpr.Text);
    end
    else
    begin
      if HasParams then
        Lines.Add('    public static func ' + ApiName.Text + '_async(' + ParamDecl.Text + ') async throws {')
      else
        Lines.Add('    public static func ' + ApiName.Text + '_async() async throws {');
      Lines.Add('        _ = try await callAsync(apiName: ' + SwiftStrLit(ApiName).Text + ', args: [' + ArgList.Text + '])');
    end;
    Lines.Add('    }');
    Lines.Add('');
  end;
end;

procedure EmitSwiftFooter(Lines: TPascalStringList);
begin
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('// _SyncResultBox - shared mutable state for the blocking sync transport.');
  Lines.Add('//');
  Lines.Add('// Why @unchecked Sendable is safe here:');
  Lines.Add('//   * The URLSession completion handler (native worker thread) is the');
  Lines.Add('//     only writer.');
  Lines.Add('//   * The caller blocked on DispatchSemaphore (caller thread) is the');
  Lines.Add('//     only reader.');
  Lines.Add('//   * DispatchSemaphore.signal() / wait() establishes the happens-before');
  Lines.Add('//     relationship that the Swift concurrency checker cannot infer');
  Lines.Add('//     across a C-level callback boundary.');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('final class _SyncResultBox: @unchecked Sendable {');
  Lines.Add('    var value: Result<(Data, Int), Error>?');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPCallSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallSwiftCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallSwiftCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Swift call module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitSwiftHeader(Lines, UnitName);
    EmitSwiftConfig(Lines, NormalizedUnit, BaseUrl);
    EmitSwiftError(Lines);
    EmitSwiftTransport(Lines);
    EmitSwiftFunctions(Lines, SupportedFuncs, ApiNames);
    EmitSwiftFooter(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.', [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'swift', 'Swift HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_swift.swift', False,
    @GenerateHTTPCallSwiftCode);
end.
