unit http_swift_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceSwiftCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_swift_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_swift_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_Needs_Precision_Note(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
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

// SwiftStrLit - emit a complete double-quoted Swift string literal with
// the surrounding quotes included.
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

function BuildSwiftStubSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  RetType: TP_String;
begin
  if F.IsFunction then
    RetType := ' -> ' + ABI_Type_To_Swift_Type(F.ReturnType)
  else
    RetType := '';
  if Length(F.Params) > 0 then
    Result := 'public static func internal_call_' + ApiName.Text + '(' +
      BuildSwiftParamDecl(F.Params).Text + ')' + RetType.Text
  else
    Result := 'public static func internal_call_' + ApiName.Text + '()' + RetType.Text;
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
// SWIFT SERVICE MODULE GENERATOR
// =============================================================================

procedure EmitSwiftServiceHeader(Lines: TPascalStringList;
  const UnitName, NormalizedUnit: TP_String);
begin
  Lines.Add('// -*- coding: utf-8 -*-');
  Lines.Add('// Auto-generated by http_swift_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI service module for Swift, backed by the LingoFuse');
  Lines.Add('// mesh. Registers one LingoFuse Call API per supported routine,');
  Lines.Add('// and speaks the wire protocol that every other HTTP/JSON');
  Lines.Add('// generator in this toolchain produces:');
  Lines.Add('//');
  Lines.Add('//   request  = POST /<app>/<api>   (routed through bridge.py)');
  Lines.Add('//              Body: { "args": [v1, v2, ...] }   positional');
  Lines.Add('//                or: { "a": v1, "b": v2, ... }   named');
  Lines.Add('//');
  Lines.Add('//   response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//              { "code": -1, "error":  "<message>" } on handler error');
  Lines.Add('//');
  Lines.Add('// ARCHITECTURE');
  Lines.Add('//');
  Lines.Add('//     HTTP client  --HTTP-->  bridge.py  --LF_Call-->  this service');
  Lines.Add('//                             (:8081)                 (this file)');
  Lines.Add('//');
  Lines.Add('// The HTTP side is handled by bridge.py (not generated here).');
  Lines.Add('// This file is the LF-side service. It requires:');
  Lines.Add('//   * the `LingoFuse` Swift binding module');
  Lines.Add('//   * the native LingoFuse shared library');
  Lines.Add('//     (LingoFuse64.dll / liblingofuse.so / liblingofuse.dylib)');
  Lines.Add('//   * a running bridge.py process connected to the SAME endpoint');
  Lines.Add('//');
  Lines.Add('// Dependencies:');
  Lines.Add('//   * LingoFuse    (the Swift binding)');
  Lines.Add('//   * Foundation   (standard library)');
  Lines.Add('//');
  Lines.Add('// Usage as a module:');
  Lines.Add('//   1. Add the generated file to a Swift package or Xcode target');
  Lines.Add('//      that already links against the LingoFuse binding.');
  Lines.Add('//   2. Fill in each `internal_call_<ApiName>` stub.');
  Lines.Add('//   3. From your `main.swift` call:');
  Lines.Add('//          ' + NormalizedUnit.Text + 'HttpJsonService.main()');
  Lines.Add('//');
  Lines.Add('// Everything below the "User-editable API stubs" banner is');
  Lines.Add('// auto-generated and must not be edited by hand.');
  Lines.Add('');
  Lines.Add('import Foundation');
  Lines.Add('import LingoFuse');
  Lines.Add('');
end;

procedure EmitSwiftServiceConfig(Lines: TPascalStringList;
  const NormalizedUnit, AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('public enum ' + NormalizedUnit.Text + 'HttpJsonService {');
  Lines.Add('');
  Lines.Add('    // ================================================================');
  Lines.Add('    // Configuration');
  Lines.Add('    // ================================================================');
  Lines.Add('');
  Lines.Add('    public static let appName: String = ' + SwiftStrLit(AppName).Text);
  Lines.Add('    public static let appDescription: String = ' + SwiftStrLit(AppDesc).Text);
  Lines.Add('    public static let endpoint: String = ' + SwiftStrLit(Endpoint).Text);
  Lines.Add('');
  Lines.Add('    /// Set to true to enable verbose logging on stderr.');
  Lines.Add('    public static var debugLog: Bool = false');
  Lines.Add('');
end;

procedure EmitSwiftServiceError(Lines: TPascalStringList);
begin
  Lines.Add('    // ================================================================');
  Lines.Add('    // Service errors');
  Lines.Add('    // ================================================================');
  Lines.Add('');
  Lines.Add('    public enum ServiceError: Error, CustomStringConvertible {');
  Lines.Add('        case libraryLoadFailed');
  Lines.Add('        case prepareServiceFailed(String)');
  Lines.Add('        case prepareClientFailed(String)');
  Lines.Add('        case prepareDoneFailed');
  Lines.Add('        case invalidArgument(String)');
  Lines.Add('');
  Lines.Add('        public var description: String {');
  Lines.Add('            switch self {');
  Lines.Add('            case .libraryLoadFailed:');
  Lines.Add('                return "LF_LoadLibrary() returned non-1"');
  Lines.Add('            case .prepareServiceFailed(let m):');
  Lines.Add('                return "Framework.prepareService failed: \(m)"');
  Lines.Add('            case .prepareClientFailed(let m):');
  Lines.Add('                return "Framework.prepareClient failed: \(m)"');
  Lines.Add('            case .prepareDoneFailed:');
  Lines.Add('                return "Framework.prepareDone failed and main thread is not running"');
  Lines.Add('            case .invalidArgument(let m):');
  Lines.Add('                return m');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSwiftServiceJsonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('    // ================================================================');
  Lines.Add('    // JSON request / response helpers');
  Lines.Add('    //');
  Lines.Add('    // Translate between the JSON text carried by a DataHandle and');
  Lines.Add('    // the Swift values the stubs operate on. Enforce the shared');
  Lines.Add('    // wire contract: every DataHandle payload is UTF-8 JSON followed');
  Lines.Add('    // by a single NUL byte.');
  Lines.Add('    // ================================================================');
  Lines.Add('');
  Lines.Add('    /// Read and parse the JSON request from a LingoFuse input handle.');
  Lines.Add('    private static func readRequest(_ input: DataHandle) throws -> [String: Any] {');
  Lines.Add('        let text = try LfIo.readString(input)');
  Lines.Add('        if text.isEmpty {');
  Lines.Add('            throw ServiceError.invalidArgument("empty request body")');
  Lines.Add('        }');
  Lines.Add('        guard let data = text.data(using: .utf8) else {');
  Lines.Add('            throw ServiceError.invalidArgument("request is not valid UTF-8")');
  Lines.Add('        }');
  Lines.Add('        let obj: Any');
  Lines.Add('        do {');
  Lines.Add('            obj = try JSONSerialization.jsonObject(with: data)');
  Lines.Add('        } catch {');
  Lines.Add('            throw ServiceError.invalidArgument("invalid JSON request: \(error)")');
  Lines.Add('        }');
  Lines.Add('        guard let dict = obj as? [String: Any] else {');
  Lines.Add('            throw ServiceError.invalidArgument("request must be a JSON object")');
  Lines.Add('        }');
  Lines.Add('        return dict');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /// Locate a raw argument by position (if "args" is present)');
  Lines.Add('    /// or by name (otherwise). Returns nil when the field is');
  Lines.Add('    /// missing or JSON null.');
  Lines.Add('    private static func extractRaw(_ req: [String: Any],');
  Lines.Add('                                   _ name: String,');
  Lines.Add('                                   _ index: Int) -> Any? {');
  Lines.Add('        if let args = req["args"] as? [Any], index < args.count {');
  Lines.Add('            let v = args[index]');
  Lines.Add('            if v is NSNull { return nil }');
  Lines.Add('            return v');
  Lines.Add('        }');
  Lines.Add('        if let v = req[name], !(v is NSNull) {');
  Lines.Add('            return v');
  Lines.Add('        }');
  Lines.Add('        return nil');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func getI64(_ req: [String: Any],');
  Lines.Add('                               _ name: String,');
  Lines.Add('                               _ index: Int) throws -> Int64 {');
  Lines.Add('        guard let raw = extractRaw(req, name, index) else { return 0 }');
  Lines.Add('        if let n = raw as? NSNumber { return n.int64Value }');
  Lines.Add('        throw ServiceError.invalidArgument(');
  Lines.Add('            "Argument ' + #39 + '\(name)' + #39 + ' expects an integer")');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func getF64(_ req: [String: Any],');
  Lines.Add('                               _ name: String,');
  Lines.Add('                               _ index: Int) throws -> Double {');
  Lines.Add('        guard let raw = extractRaw(req, name, index) else { return 0.0 }');
  Lines.Add('        if let n = raw as? NSNumber { return n.doubleValue }');
  Lines.Add('        throw ServiceError.invalidArgument(');
  Lines.Add('            "Argument ' + #39 + '\(name)' + #39 + ' expects a number")');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func getString(_ req: [String: Any],');
  Lines.Add('                                  _ name: String,');
  Lines.Add('                                  _ index: Int) throws -> String {');
  Lines.Add('        guard let raw = extractRaw(req, name, index) else { return "" }');
  Lines.Add('        if let s = raw as? String { return s }');
  Lines.Add('        throw ServiceError.invalidArgument(');
  Lines.Add('            "Argument ' + #39 + '\(name)' + #39 + ' expects a string")');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /// Write a JSON envelope to an output handle. Never throws:');
  Lines.Add('    /// if the output handle is unusable, there is nothing to do.');
  Lines.Add('    private static func writeEnvelope(_ output: DataHandle,');
  Lines.Add('                                      _ envelope: [String: Any]) {');
  Lines.Add('        do {');
  Lines.Add('            let data = try JSONSerialization.data(withJSONObject: envelope)');
  Lines.Add('            try LfIo.writeStringBytes(output, [UInt8](data))');
  Lines.Add('        } catch {');
  Lines.Add('            if debugLog {');
  Lines.Add('                let msg = "[http-json-service] failed to write response: \(error)\n"');
  Lines.Add('                if let d = msg.data(using: .utf8) {');
  Lines.Add('                    FileHandle.standardError.write(d)');
  Lines.Add('                }');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func writeSuccess(_ output: DataHandle,');
  Lines.Add('                                     result: Any = NSNull()) {');
  Lines.Add('        writeEnvelope(output, ["code": 0, "result": result])');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static func writeError(_ output: DataHandle,');
  Lines.Add('                                   _ message: String) {');
  Lines.Add('        writeEnvelope(output, ["code": -1, "error": message])');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSwiftServiceStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, ArgList, RetType, DefaultRet, Description, StubName: TP_String;
  HasParams: boolean;
begin
  Lines.Add('    // ================================================================');
  Lines.Add('    // User-editable API stubs');
  Lines.Add('    //');
  Lines.Add('    // This is the ONLY section you are expected to edit. Replace');
  Lines.Add('    // each stub body with a call to the real implementation, for');
  Lines.Add('    // example:');
  Lines.Add('    //');
  Lines.Add('    //     public static func internal_call_Add(_ a: Int64, _ b: Int64) -> Int64 {');
  Lines.Add('    //         return a + b');
  Lines.Add('    //     }');
  Lines.Add('    //');
  Lines.Add('    // The wire protocol wraps every stub call in the response');
  Lines.Add('    // envelope; stubs only need to return the raw value.');
  Lines.Add('    // ================================================================');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(F.Params) > 0;
    ParamDecl := BuildSwiftParamDecl(F.Params);
    ArgList := BuildSwiftArgList(F.Params);
    StubName := 'internal_call_' + ApiName;

    Description := GetFullDescription(F.Comment);
    if Description.Len > 0 then
      Lines.Add('    /// ' + Description.Text);
    Lines.Add('    ///');
    Lines.Add('    /// Original Pascal: ' + BuildPascalDecl(F).Text);

    if F.IsFunction then
    begin
      RetType := ABI_Type_To_Swift_Type(F.ReturnType);
      DefaultRet := ABI_Type_To_Swift_Default_Literal(F.ReturnType);
      if HasParams then
        Lines.Add('    public static func ' + StubName.Text + '(' + ParamDecl.Text + ') -> ' + RetType.Text + ' {')
      else
        Lines.Add('    public static func ' + StubName.Text + '() -> ' + RetType.Text + ' {');
      if HasParams then
        Lines.Add('        _ = (' + ArgList.Text + ')');
      Lines.Add('        // TODO: replace this body with the real implementation.');
      Lines.Add('        return ' + DefaultRet.Text);
      Lines.Add('    }');
    end
    else
    begin
      if HasParams then
        Lines.Add('    public static func ' + StubName.Text + '(' + ParamDecl.Text + ') {')
      else
        Lines.Add('    public static func ' + StubName.Text + '() {');
      if HasParams then
        Lines.Add('        _ = (' + ArgList.Text + ')');
      Lines.Add('        // TODO: replace this body with the real implementation.');
      Lines.Add('    }');
    end;
    Lines.Add('');
  end;
end;

procedure EmitSwiftServiceCallbacks(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, ParamName, ExtractCall, StubName, ArgList: TP_String;
  HasParams: boolean;
begin
  Lines.Add('    // ================================================================');
  Lines.Add('    // LingoFuse callback wiring');
  Lines.Add('    //');
  Lines.Add('    // One private static function per API. Each callback reads');
  Lines.Add('    // the JSON request from the input handle, extracts the typed');
  Lines.Add('    // arguments, dispatches to the corresponding user stub, and');
  Lines.Add('    // writes the JSON response envelope to the output handle.');
  Lines.Add('    // ================================================================');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(F.Params) > 0;
    StubName := 'internal_call_' + ApiName;
    ArgList := BuildSwiftArgList(F.Params);

    Lines.Add('    private static func cb_' + ApiName.Text +
      '(_ input: DataHandle, _ output: DataHandle) {');
    Lines.Add('        do {');
    Lines.Add('            let req = try readRequest(input)');

    for j := 0 to High(F.Params) do
    begin
      ParamName := MakeSafeSwiftIdent(F.Params[j].Name, j);
      if ABI_Type_Is_String(F.Params[j].PascalType) then
        ExtractCall := 'try getString(req, ' + SwiftStrLit(F.Params[j].Name).Text +
          ', ' + umlIntToStr(j).Text + ')'
      else if ABI_Type_Is_Float(F.Params[j].PascalType) then
        ExtractCall := 'try getF64(req, ' + SwiftStrLit(F.Params[j].Name).Text +
          ', ' + umlIntToStr(j).Text + ')'
      else
        ExtractCall := 'try getI64(req, ' + SwiftStrLit(F.Params[j].Name).Text +
          ', ' + umlIntToStr(j).Text + ')';
      Lines.Add('            let ' + ParamName.Text + ' = ' + ExtractCall);
    end;

    if F.IsFunction then
    begin
      Lines.Add('            let ret = ' + StubName.Text + '(' + ArgList.Text + ')');
      Lines.Add('            writeSuccess(output, result: ret)');
    end
    else
    begin
      Lines.Add('            ' + StubName.Text + '(' + ArgList.Text + ')');
      Lines.Add('            writeSuccess(output)');
    end;
    Lines.Add('        } catch {');
    Lines.Add('            if debugLog {');
    Lines.Add('                let msg = "[' + ApiName.Text + '] callback error: \(error)\n"');
    Lines.Add('                if let d = msg.data(using: .utf8) {');
    Lines.Add('                    FileHandle.standardError.write(d)');
    Lines.Add('                }');
    Lines.Add('            }');
    Lines.Add('            writeError(output, "\(error)")');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
  end;
end;

procedure EmitSwiftServiceRegister(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Desc: TP_String;
begin
  Lines.Add('    // ================================================================');
  Lines.Add('    // Registration');
  Lines.Add('    // ================================================================');
  Lines.Add('');
  Lines.Add('    /// Register every generated Call API on the given App.');
  Lines.Add('    public static func registerAllApis(_ app: AppHandle) throws {');

  if Length(SupportedFuncs) = 0 then
    Lines.Add('        // No supported routines were generated.')
  else
  begin
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      Desc := GetFullDescription(F.Comment);
      if Desc.Len = 0 then
        Desc := 'HTTP/JSON API: ' + ApiName;

      Lines.Add('');
      Lines.Add('        // ---- ' + ApiName.Text + ' ----');
      Lines.Add('        _ = try app.registerCall(');
      Lines.Add('            ' + SwiftStrLit(ApiName).Text + ',');
      Lines.Add('            ' + SwiftStrLit(Desc).Text + ') { input, output in');
      Lines.Add('            cb_' + ApiName.Text + '(input, output)');
      Lines.Add('        }');
    end;
  end;

  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSwiftServiceMain(Lines: TPascalStringList);
begin
  Lines.Add('    // ================================================================');
  Lines.Add('    // Entry point');
  Lines.Add('    // ================================================================');
  Lines.Add('');
  Lines.Add('    /// Start the LingoFuse service and return the AppHandle.');
  Lines.Add('    ///');
  Lines.Add('    /// The caller must keep the handle alive for the lifetime of');
  Lines.Add('    /// the service. On failure the function throws; on success the');
  Lines.Add('    /// service is fully prepared and ready to receive calls.');
  Lines.Add('    public static func runService() throws -> AppHandle {');
  Lines.Add('        guard LF_LoadLibrary() == 1 else {');
  Lines.Add('            throw ServiceError.libraryLoadFailed');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        Framework.setOption("Wait_Connection_ReadyOk", "False")');
  Lines.Add('        Framework.setOption("Overlap_Connection", "True")');
  Lines.Add('        Framework.setOption("Quiet", debugLog ? "False" : "True")');
  Lines.Add('        Framework.resetPrepare()');
  Lines.Add('');
  Lines.Add('        do {');
  Lines.Add('            _ = try Framework.prepareService(');
  Lines.Add('                listeningAddr: endpoint,');
  Lines.Add('                physicsAddr: endpoint)');
  Lines.Add('        } catch {');
  Lines.Add('            throw ServiceError.prepareServiceFailed("\(error)")');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        let app = try AppHandle(name: appName,');
  Lines.Add('                                description: appDescription)');
  Lines.Add('        try registerAllApis(app)');
  Lines.Add('');
  Lines.Add('        do {');
  Lines.Add('            _ = try Framework.prepareClient(');
  Lines.Add('                physicsAddr: endpoint,');
  Lines.Add('                app: app)');
  Lines.Add('        } catch {');
  Lines.Add('            app.dispose()');
  Lines.Add('            throw ServiceError.prepareClientFailed("\(error)")');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        if !Framework.prepareDone() && !Framework.checkMainThread() {');
  Lines.Add('            app.dispose()');
  Lines.Add('            throw ServiceError.prepareDoneFailed');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        return app');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /// Block until the process is terminated (Ctrl+C / SIGINT),');
  Lines.Add('    /// then perform a clean shutdown. This is the standard entry');
  Lines.Add('    /// point for a standalone executable.');
  Lines.Add('    public static func main() {');
  Lines.Add('        print("=== \(appName) HTTP/JSON service ===")');
  Lines.Add('        print("Endpoint: \(endpoint)")');
  Lines.Add('        print("")');
  Lines.Add('');
  Lines.Add('        let app: AppHandle');
  Lines.Add('        do {');
  Lines.Add('            app = try runService()');
  Lines.Add('        } catch {');
  Lines.Add('            let msg = "[FATAL] \(error)\n"');
  Lines.Add('            if let d = msg.data(using: .utf8) {');
  Lines.Add('                FileHandle.standardError.write(d)');
  Lines.Add('            }');
  Lines.Add('            exit(1)');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        print("[OK] Service ready. Press Enter to stop (or send SIGINT).")');
  Lines.Add('        _ = readLine()');
  Lines.Add('');
  Lines.Add('        print("[OK] Shutting down...")');
  Lines.Add('        NetworkEvents.clearNetworkEvent()');
  Lines.Add('        Framework.exitMainThread()');
  Lines.Add('        app.dispose()');
  Lines.Add('        Framework.shutdown()');
  Lines.Add('        LF_FreeLibrary()');
  Lines.Add('        print("[OK] Service stopped cleanly.")');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitSwiftServiceFooter(Lines: TPascalStringList);
begin
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceSwiftCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc, Endpoint: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceSwiftCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceSwiftCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating HTTP/JSON Swift service module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitSwiftServiceHeader(Lines, UnitName, NormalizedUnit);
    EmitSwiftServiceConfig(Lines, NormalizedUnit, AppName, AppDesc, Endpoint);
    EmitSwiftServiceError(Lines);
    EmitSwiftServiceJsonHelpers(Lines);
    EmitSwiftServiceStubs(Lines, SupportedFuncs, ApiNames);
    EmitSwiftServiceCallbacks(Lines, SupportedFuncs, ApiNames);
    EmitSwiftServiceRegister(Lines, SupportedFuncs, ApiNames);
    EmitSwiftServiceMain(Lines);
    EmitSwiftServiceFooter(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
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
    'swift', 'Swift HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service_swift.swift', False,
    @GenerateHTTPServiceSwiftCode);
end.
