unit http_go_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceGoCode - main entry point for the service program.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServiceGoCode(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_go_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_go_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification (mirrors every HTTP/JSON generator)
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

function ABI_Type_To_Go_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) then
    Result := 'float64'
  else if ABI_Type_Is_Int(T) then
    Result := 'int64'
  else
    Result := 'any';
end;

function ABI_Type_To_Go_Zero(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'nil';
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

function IsGoReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('break') or S.Same('case') or S.Same('chan') or
    S.Same('const') or S.Same('continue') or S.Same('default') or
    S.Same('defer') or S.Same('else') or S.Same('fallthrough') or
    S.Same('for') or S.Same('func') or S.Same('go') or
    S.Same('goto') or S.Same('if') or S.Same('import') or
    S.Same('interface') or S.Same('map') or S.Same('package') or
    S.Same('range') or S.Same('return') or S.Same('select') or
    S.Same('struct') or S.Same('switch') or S.Same('type') or
    S.Same('var') or
    S.Same('bool') or S.Same('byte') or S.Same('complex64') or
    S.Same('complex128') or S.Same('error') or S.Same('float32') or
    S.Same('float64') or S.Same('int') or S.Same('int8') or
    S.Same('int16') or S.Same('int32') or S.Same('int64') or
    S.Same('rune') or S.Same('string') or S.Same('uint') or
    S.Same('uint8') or S.Same('uint16') or S.Same('uint32') or
    S.Same('uint64') or S.Same('uintptr') or S.Same('true') or
    S.Same('false') or S.Same('iota') or S.Same('nil') or
    S.Same('append') or S.Same('cap') or S.Same('close') or
    S.Same('complex') or S.Same('copy') or S.Same('delete') or
    S.Same('imag') or S.Same('len') or S.Same('make') or
    S.Same('new') or S.Same('panic') or S.Same('print') or
    S.Same('println') or S.Same('real') or S.Same('recover');
end;

function MakeSafeGoIdent(const Name: TP_String; Index: integer): TP_String;
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
    if i = 1 then
    begin
      if (c >= 'A') and (c <= 'Z') then
        Result.Append(TP_Char(Ord(c) + 32))
      else if (c = '_') or ((c >= 'a') and (c <= 'z')) then
        Result.Append(c)
      else
        Result.Append('_');
    end
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= 'A') and (c <= 'Z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if IsGoReservedWord(Result) then
    Result := Result + '_';

  if Result.Len = 0 then
    Result := 'p' + umlIntToStr(Index);
end;

function MakeExportedGoIdent(const Name: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'Api';
    Exit;
  end;

  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if i = 1 then
    begin
      if (c >= 'a') and (c <= 'z') then
        Result.Append(TP_Char(Ord(c) - 32))
      else if (c = '_') or ((c >= 'A') and (c <= 'Z')) then
        Result.Append(c)
      else
        Result.Append('_');
    end
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= 'A') and (c <= 'Z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := 'Api' + Result;

  if Result.Len = 0 then
    Result := 'Api';
end;

function MakeGoPackageName(const Name: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'lingofuse_service';
    Exit;
  end;

  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if (c >= 'A') and (c <= 'Z') then
      Result.Append(TP_Char(Ord(c) + 32))
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := 'p' + Result;

  if IsGoReservedWord(Result) then
    Result := Result + '_';

  if Result.Len = 0 then
    Result := 'lingofuse_service';
end;

function GoStringLit(const S: TP_String): TP_String;
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
      #8:   Result.Append('\x08');
      #12:  Result.Append('\x0c');
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

function BuildGoParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeGoIdent(Params[i].Name, i);
    T := ABI_Type_To_Go_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + ' ' + T;
  end;
end;

function BuildGoArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeGoIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildGoDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := '""'
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else if ABI_Type_Is_Int(Params[i].PascalType) then
      d := '0'
    else
      d := 'nil';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
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
    n := MakeSafeGoIdent(F.Params[i].Name, i);
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
// GO SERVICE MODULE GENERATOR
// =============================================================================

procedure EmitGoServiceHeader(Lines: TPascalStringList;
  const UnitName: TP_String);
begin
  Lines.Add('// Auto-generated by http_go_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI service for Go, backed by the LingoFuse mesh.');
  Lines.Add('//');
  Lines.Add('// Wire protocol (the same as every other language in this toolchain):');
  Lines.Add('//   request  = POST /<app>/<api>   (routed through bridge.py)');
  Lines.Add('//              Body: { "args": [v1, v2, ...] }   positional');
  Lines.Add('//                or: { "a": v1, "b": v2, ... }   named');
  Lines.Add('//   response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//              { "code": -1, "error":  "<message>" } on handler error');
  Lines.Add('//              { "code": -2, "error":  "<message>" } on request error');
  Lines.Add('//');
  Lines.Add('// ARCHITECTURE');
  Lines.Add('//     HTTP client  ---> bridge.py ---> LingoFuse mesh ---> this service');
  Lines.Add('//                       (:8081)');
  Lines.Add('//');
  Lines.Add('// The HTTP side is handled by bridge.py (not generated here). This');
  Lines.Add('// file is the LF-side service. It requires:');
  Lines.Add('//   * the "github.com/PassByYou888/LingoFuse/go/lingofuse" package');
  Lines.Add('//   * the native LingoFuse shared library (LingoFuse64.dll / .so / .dylib)');
  Lines.Add('//   * a running bridge.py process on the same endpoint');
  Lines.Add('//');
  Lines.Add('// Dependencies:');
  Lines.Add('//   go get github.com/PassByYou888/LingoFuse/go');
  Lines.Add('//');
  Lines.Add('// Every API has a corresponding "internalCall<ApiName>" stub near');
  Lines.Add('// the bottom of this file. Replace each stub body with a call to the');
  Lines.Add('// real implementation.');
  Lines.Add('');
  Lines.Add('package main');
  Lines.Add('');
  Lines.Add('import (');
  Lines.Add('    "bytes"');
  Lines.Add('    "encoding/json"');
  Lines.Add('    "fmt"');
  Lines.Add('    "os"');
  Lines.Add('    "os/signal"');
  Lines.Add('    "syscall"');
  Lines.Add('');
  Lines.Add('    "github.com/PassByYou888/LingoFuse/go/lingofuse"');
  Lines.Add(')');
  Lines.Add('');
end;

procedure EmitGoServiceConfig(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Configuration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('const (');
  Lines.Add('    // AppName is the LingoFuse application name. bridge.py and every');
  Lines.Add('    // HTTP client must use the same name.');
  Lines.Add('    AppName = ' + GoStringLit(AppName).Text);
  Lines.Add('');
  Lines.Add('    // AppDesc is a human-readable description shown by the mesh.');
  Lines.Add('    AppDesc = ' + GoStringLit(AppDesc).Text);
  Lines.Add('');
  Lines.Add('    // Endpoint is the IPC endpoint this service binds to. bridge.py');
  Lines.Add('    // must be started with the same --endpoint value.');
  Lines.Add('    Endpoint = ' + GoStringLit(Endpoint).Text);
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('// DebugLog enables per-call stderr logging. Set to true when');
  Lines.Add('// diagnosing a deployment.');
  Lines.Add('const DebugLog = false');
  Lines.Add('');
end;

procedure EmitGoServiceExtractors(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Request parsing');
  Lines.Add('//');
  Lines.Add('// The wire protocol supports two request shapes:');
  Lines.Add('//   {"args": [v1, v2, ...]}        positional');
  Lines.Add('//   {"a": v1, "b": v2, ...}        named');
  Lines.Add('//');
  Lines.Add('// If "args" is present and is a JSON array, positional lookup is');
  Lines.Add('// used. Otherwise, named lookup is used.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('func readRequest(input *lingofuse.DataHandle) (map[string]any, error) {');
  Lines.Add('    if err := input.SetPosition(0); err != nil {');
  Lines.Add('        return nil, fmt.Errorf("rewind request: %w", err)');
  Lines.Add('    }');
  Lines.Add('    raw, err := input.ReadStringBytes()');
  Lines.Add('    if err != nil {');
  Lines.Add('        return nil, fmt.Errorf("read request bytes: %w", err)');
  Lines.Add('    }');
  Lines.Add('    if len(raw) == 0 {');
  Lines.Add('        return map[string]any{}, nil');
  Lines.Add('    }');
  Lines.Add('    dec := json.NewDecoder(bytes.NewReader(raw))');
  Lines.Add('    dec.UseNumber()');
  Lines.Add('    var body map[string]any');
  Lines.Add('    if err := dec.Decode(&body); err != nil {');
  Lines.Add('        return nil, fmt.Errorf("parse request JSON: %w", err)');
  Lines.Add('    }');
  Lines.Add('    return body, nil');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func extractRaw(body map[string]any, name string, index int) (any, error) {');
  Lines.Add('    if raw, ok := body["args"]; ok {');
  Lines.Add('        if args, ok := raw.([]any); ok {');
  Lines.Add('            if index >= len(args) {');
  Lines.Add('                return nil, fmt.Errorf("missing positional argument #%d (%q)", index, name)');
  Lines.Add('            }');
  Lines.Add('            return args[index], nil');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    v, ok := body[name]');
  Lines.Add('    if !ok {');
  Lines.Add('        return nil, fmt.Errorf("missing argument %q", name)');
  Lines.Add('    }');
  Lines.Add('    return v, nil');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func extractI64(body map[string]any, name string, index int) (int64, error) {');
  Lines.Add('    v, err := extractRaw(body, name, index)');
  Lines.Add('    if err != nil {');
  Lines.Add('        return 0, err');
  Lines.Add('    }');
  Lines.Add('    switch x := v.(type) {');
  Lines.Add('    case json.Number:');
  Lines.Add('        return x.Int64()');
  Lines.Add('    case float64:');
  Lines.Add('        return int64(x), nil');
  Lines.Add('    case int64:');
  Lines.Add('        return x, nil');
  Lines.Add('    default:');
  Lines.Add('        return 0, fmt.Errorf("argument %q is not an integer", name)');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func extractF64(body map[string]any, name string, index int) (float64, error) {');
  Lines.Add('    v, err := extractRaw(body, name, index)');
  Lines.Add('    if err != nil {');
  Lines.Add('        return 0, err');
  Lines.Add('    }');
  Lines.Add('    switch x := v.(type) {');
  Lines.Add('    case json.Number:');
  Lines.Add('        return x.Float64()');
  Lines.Add('    case float64:');
  Lines.Add('        return x, nil');
  Lines.Add('    case int64:');
  Lines.Add('        return float64(x), nil');
  Lines.Add('    default:');
  Lines.Add('        return 0, fmt.Errorf("argument %q is not a number", name)');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func extractString(body map[string]any, name string, index int) (string, error) {');
  Lines.Add('    v, err := extractRaw(body, name, index)');
  Lines.Add('    if err != nil {');
  Lines.Add('        return "", err');
  Lines.Add('    }');
  Lines.Add('    s, ok := v.(string)');
  Lines.Add('    if !ok {');
  Lines.Add('        return "", fmt.Errorf("argument %q is not a string", name)');
  Lines.Add('    }');
  Lines.Add('    return s, nil');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func writeSuccess(output *lingofuse.DataHandle, result any) {');
  Lines.Add('    if err := lingofuse.WriteJSON(output, map[string]any{');
  Lines.Add('        "code":   0,');
  Lines.Add('        "result": result,');
  Lines.Add('    }); err != nil {');
  Lines.Add('        fmt.Fprintf(os.Stderr, "[service] write success: %v\n", err)');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func writeError(output *lingofuse.DataHandle, code int, msg string) {');
  Lines.Add('    if err := lingofuse.WriteJSON(output, map[string]any{');
  Lines.Add('        "code":  code,');
  Lines.Add('        "error": msg,');
  Lines.Add('    }); err != nil {');
  Lines.Add('        fmt.Fprintf(os.Stderr, "[service] write error: %v\n", err)');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitGoServiceStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, ParamDecl, Description, GoRetType: TP_String;
  HasParams, IsFunc: boolean;
  ParamName: TP_String;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// User-editable API stubs');
  Lines.Add('//');
  Lines.Add('// This is the ONLY section you are expected to edit. Replace each');
  Lines.Add('// stub body with a call to the real implementation, for example:');
  Lines.Add('//');
  Lines.Add('//     func internalCallAdd(a int64, b int64) (int64, error) {');
  Lines.Add('//         return mymodule.Add(a, b), nil');
  Lines.Add('//     }');
  Lines.Add('//');
  Lines.Add('// Return (result, nil) on success, or (zero, err) on failure. The');
  Lines.Add('// error, if non-nil, is automatically converted into a');
  Lines.Add('// {"code": -1, "error": "..."} response.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := 'internalCall' + MakeExportedGoIdent(ApiName).Text;
    ParamDecl := BuildGoParamDecl(F.Params);
    HasParams := Length(F.Params) > 0;
    IsFunc := F.IsFunction;

    Description := GetFullDescription(F.Comment);
    if Description.Len > 0 then
      Lines.Add('// ' + Description.Text);
    Lines.Add('//');
    Lines.Add('// Original Pascal: ' + BuildPascalDecl(F).Text);

    if IsFunc then
    begin
      GoRetType := ABI_Type_To_Go_Type(F.ReturnType);
      if HasParams then
        Lines.Add('func ' + StubName.Text + '(' + ParamDecl.Text + ') (' + GoRetType.Text + ', error) {')
      else
        Lines.Add('func ' + StubName.Text + '() (' + GoRetType.Text + ', error) {');
      for j := 0 to High(F.Params) do
      begin
        ParamName := MakeSafeGoIdent(F.Params[j].Name, j);
        Lines.Add('    _ = ' + ParamName.Text);
      end;
      Lines.Add('    // TODO: replace this body with the real implementation.');
      Lines.Add('    return ' + ABI_Type_To_Go_Zero(F.ReturnType).Text + ', nil');
      Lines.Add('}');
    end
    else
    begin
      if HasParams then
        Lines.Add('func ' + StubName.Text + '(' + ParamDecl.Text + ') error {')
      else
        Lines.Add('func ' + StubName.Text + '() error {');
      for j := 0 to High(F.Params) do
      begin
        ParamName := MakeSafeGoIdent(F.Params[j].Name, j);
        Lines.Add('    _ = ' + ParamName.Text);
      end;
      Lines.Add('    // TODO: replace this body with the real implementation.');
      Lines.Add('    return nil');
      Lines.Add('}');
    end;
    Lines.Add('');
  end;
end;

procedure EmitGoServiceCallbacks(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, CBName, ParamName, ExtractCall, ArgCall: TP_String;
  HasParams: boolean;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// LingoFuse callback wiring');
  Lines.Add('//');
  Lines.Add('// One closure per API. Each closure reads the JSON request from the');
  Lines.Add('// input handle, extracts the typed arguments, invokes the corresponding');
  Lines.Add('// user stub, and writes the JSON response envelope to the output handle.');
  Lines.Add('//');
  Lines.Add('// The callbacks run on a LingoFuse worker thread. They must not block');
  Lines.Add('// and must not call any synchronous LingoFuse function.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    CBName := 'cb' + MakeExportedGoIdent(ApiName).Text;
    StubName := 'internalCall' + MakeExportedGoIdent(ApiName).Text;
    HasParams := Length(F.Params) > 0;

    Lines.Add('func ' + CBName.Text + '(input, output *lingofuse.DataHandle) {');
    if HasParams then
      Lines.Add('    body, err := readRequest(input)')
    else
      Lines.Add('    _, err := readRequest(input)');
    Lines.Add('    if err != nil {');
    Lines.Add('        writeError(output, -2, err.Error())');
    Lines.Add('        return');
    Lines.Add('    }');

    for j := 0 to High(F.Params) do
    begin
      ParamName := MakeSafeGoIdent(F.Params[j].Name, j);
      if ABI_Type_Is_String(F.Params[j].PascalType) then
        ExtractCall := 'extractString'
      else if ABI_Type_Is_Float(F.Params[j].PascalType) then
        ExtractCall := 'extractF64'
      else
        ExtractCall := 'extractI64';

      Lines.Add('    ' + ParamName.Text + ', err := ' + ExtractCall + '(body, ' +
        GoStringLit(F.Params[j].Name).Text + ', ' + umlIntToStr(j).Text + ')');
      Lines.Add('    if err != nil {');
      Lines.Add('        writeError(output, -1, err.Error())');
      Lines.Add('        return');
      Lines.Add('    }');
    end;

    if HasParams then
      ArgCall := BuildGoArgList(F.Params)
    else
      ArgCall := '';

    if F.IsFunction then
    begin
      Lines.Add('    result, err := ' + StubName.Text + '(' + ArgCall.Text + ')');
      Lines.Add('    if err != nil {');
      Lines.Add('        writeError(output, -1, err.Error())');
      Lines.Add('        return');
      Lines.Add('    }');
      Lines.Add('    writeSuccess(output, result)');
    end
    else
    begin
      Lines.Add('    if err := ' + StubName.Text + '(' + ArgCall.Text + '); err != nil {');
      Lines.Add('        writeError(output, -1, err.Error())');
      Lines.Add('        return');
      Lines.Add('    }');
      Lines.Add('    writeSuccess(output, nil)');
    end;

    Lines.Add('}');
    Lines.Add('');
  end;
end;

procedure EmitGoServiceRegister(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, CBName, Description: TP_String;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Registration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('func registerAllAPIs(app *lingofuse.AppHandle) error {');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    CBName := 'cb' + MakeExportedGoIdent(ApiName).Text;

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    Lines.Add('    if err := app.RegisterCall(');
    Lines.Add('        ' + GoStringLit(ApiName).Text + ',');
    Lines.Add('        ' + GoStringLit(Description).Text + ',');
    Lines.Add('        ' + CBName.Text + ',');
    Lines.Add('    ); err != nil {');
    Lines.Add('        return fmt.Errorf("register %q: %w", ' + GoStringLit(ApiName).Text + ', err)');
    Lines.Add('    }');
  end;

  if Length(SupportedFuncs) = 0 then
    Lines.Add('    // no supported routines');

  Lines.Add('    return nil');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitGoServiceMain(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Entry point');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('// runService performs the full LingoFuse lifecycle: create the App,');
  Lines.Add('// register every API, configure the framework, prepare the service and');
  Lines.Add('// the client, start the framework, and block until a termination signal.');
  Lines.Add('//');
  Lines.Add('// The deferred cleanup runs in the documented order:');
  Lines.Add('//     ExitMainThread -> App.Close -> Shutdown');
  Lines.Add('// even on an early error return. All three calls are safe to run even');
  Lines.Add('// when the framework never started.');
  Lines.Add('func runService() error {');
  Lines.Add('    fmt.Println("=== " + AppName + " HTTP/JSON service ===")');
  Lines.Add('    fmt.Println("Endpoint: " + Endpoint)');
  Lines.Add('');
  Lines.Add('    app, err := lingofuse.NewAppHandle(AppName, AppDesc)');
  Lines.Add('    if err != nil {');
  Lines.Add('        return fmt.Errorf("create app: %w", err)');
  Lines.Add('    }');
  Lines.Add('    defer func() {');
  Lines.Add('        _ = lingofuse.ExitMainThread()');
  Lines.Add('        app.Close()');
  Lines.Add('        _ = lingofuse.Shutdown()');
  Lines.Add('    }()');
  Lines.Add('');
  Lines.Add('    if err := registerAllAPIs(app); err != nil {');
  Lines.Add('        return err');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    // Options must be set before ResetPrepare / PrepareService.');
  Lines.Add('    if err := lingofuse.SetOption("Wait_Connection_ReadyOk", "False"); err != nil {');
  Lines.Add('        return fmt.Errorf("set Wait_Connection_ReadyOk: %w", err)');
  Lines.Add('    }');
  Lines.Add('    if err := lingofuse.SetOption("Overlap_Connection", "True"); err != nil {');
  Lines.Add('        return fmt.Errorf("set Overlap_Connection: %w", err)');
  Lines.Add('    }');
  Lines.Add('    if err := lingofuse.SetOption("Quiet", "False"); err != nil {');
  Lines.Add('        return fmt.Errorf("set Quiet: %w", err)');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if err := lingofuse.ResetPrepare(); err != nil {');
  Lines.Add('        return fmt.Errorf("ResetPrepare: %w", err)');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if _, err := lingofuse.PrepareService(Endpoint, Endpoint); err != nil {');
  Lines.Add('        return fmt.Errorf("PrepareService: %w", err)');
  Lines.Add('    }');
  Lines.Add('    if _, err := lingofuse.PrepareClient(Endpoint, app); err != nil {');
  Lines.Add('        return fmt.Errorf("PrepareClient: %w", err)');
  Lines.Add('    }');
  Lines.Add('    started, err := lingofuse.PrepareDone()');
  Lines.Add('    if err != nil {');
  Lines.Add('        return fmt.Errorf("PrepareDone: %w", err)');
  Lines.Add('    }');
  Lines.Add('    if !started {');
  Lines.Add('        return fmt.Errorf("PrepareDone returned false (framework already running)")');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    fmt.Println("[OK] Service ready. Press Ctrl+C to stop.")');
  Lines.Add('');
  Lines.Add('    sigCh := make(chan os.Signal, 1)');
  Lines.Add('    signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)');
  Lines.Add('    <-sigCh');
  Lines.Add('');
  Lines.Add('    fmt.Println("Signal received, shutting down...")');
  Lines.Add('    return nil');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func main() {');
  Lines.Add('    if err := runService(); err != nil {');
  Lines.Add('        fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)');
  Lines.Add('        os.Exit(1)');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceGoCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceGoCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceGoCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating HTTP/JSON Go service module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitGoServiceHeader(Lines, UnitName);
    EmitGoServiceConfig(Lines, AppName, AppDesc, Endpoint);
    EmitGoServiceExtractors(Lines);
    EmitGoServiceStubs(Lines, SupportedFuncs, ApiNames);
    EmitGoServiceCallbacks(Lines, SupportedFuncs, ApiNames);
    EmitGoServiceRegister(Lines, SupportedFuncs, ApiNames);
    EmitGoServiceMain(Lines);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'go', 'Go HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service_go.go', False,
    @GenerateHTTPServiceGoCode);
end.
