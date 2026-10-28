unit http_go_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallGoCode - main entry point for the call package.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallGoCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_go_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_go_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

// ABI_Type_To_Go_Type - Go type used in a parameter or return position.
// Every integer family member collapses to int64, every float family
// member to float64, every string family member to string.
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

// ABI_Type_To_Go_Zero - Go zero literal used as the failure-path
// return value inside the per-API impl function.
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

// MakeApiName - canonicalize an identifier for use in URLs, dict keys,
// and downstream identifiers. The replacement set MUST match every
// other generator in this toolchain.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

// IsGoReservedWord - returns true for Go keywords and predeclared
// identifiers that must not be used as bare identifiers.
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
    // predeclared
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

// MakeSafeGoIdent - parameter / local variable identifier.
// Lowercases the first character, replaces illegal bytes with '_',
// prepends '_' if the result starts with a digit, and appends '_'
// if the result is a Go reserved word.
function MakeSafeGoIdent(const Name: TP_String; Index: integer): TP_String;
var
  i: integer;
  c: TP_Char;
  first_is_lower: boolean;
begin
  if Name.Len = 0 then
  begin
    Result := 'p' + umlIntToStr(Index);
    Exit;
  end;

  Result := '';
  first_is_lower := False;
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if i = 1 then
    begin
      if (c >= 'A') and (c <= 'Z') then
      begin
        Result.Append(TP_Char(Ord(c) + 32));
        first_is_lower := True;
      end
      else if (c = '_') or ((c >= 'a') and (c <= 'z')) then
      begin
        Result.Append(c);
        first_is_lower := True;
      end
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

// MakeExportedGoIdent - exported function name.
// Uppercases the first character, replaces illegal bytes with '_'.
// Does NOT append a suffix for reserved words, because the result
// always starts with an uppercase letter and therefore can never be
// a Go keyword. It also cannot be a predeclared identifier, because
// those all start with a lowercase letter.
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

// MakeGoPackageName - valid Go package identifier derived from a
// unit name. Lowercase, illegal bytes to '_', prepend 'p' if the
// result begins with a digit, append '_' if the result is a Go
// reserved word.
function MakeGoPackageName(const Name: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if Name.Len = 0 then
  begin
    Result := 'lingofuse_call';
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
    Result := 'lingofuse_call';
end;

// GoStringLit - produce a complete double-quoted Go string literal
// with the surrounding quotes included. Non-printable ASCII is
// escaped as \xNN; printable non-ASCII is preserved verbatim.
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

function BuildGoArgsSliceLiteral(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := '[]any{}';
    Exit;
  end;

  Result := '[]any{';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeGoIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + '}';
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
// GO CALL PACKAGE GENERATOR
// =============================================================================

procedure EmitGoCallHeader(Lines: TPascalStringList;
  const UnitName, PackageName: TP_String);
begin
  Lines.Add('// Auto-generated by http_go_abi_call_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI call-side package for Go.');
  Lines.Add('//');
  Lines.Add('// Every supported routine has TWO functions:');
  Lines.Add('//   * `func <ApiName>(...)`             - synchronous, blocking');
  Lines.Add('//   * `func <ApiName>Async(ctx, ...) <-chan AsyncResult[T]`');
  Lines.Add('//                                       - asynchronous, channel');
  Lines.Add('//');
  Lines.Add('// Dependencies: Go standard library only. No third-party modules.');
  Lines.Add('// No LingoFuse dependency. No native library.');
  Lines.Add('//');
  Lines.Add('// Wire protocol:');
  Lines.Add('//   request  = POST <base_url>/<api>');
  Lines.Add('//              Content-Type: application/json; charset=utf-8');
  Lines.Add('//              Body: { "args": [v1, v2, ...] }');
  Lines.Add('//');
  Lines.Add('//   response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//              { "code": -1, "error":  "<message>" } on failure');
  Lines.Add('');
  Lines.Add('package ' + PackageName.Text);
  Lines.Add('');
  Lines.Add('import (');
  Lines.Add('    "bytes"');
  Lines.Add('    "context"');
  Lines.Add('    "encoding/json"');
  Lines.Add('    "fmt"');
  Lines.Add('    "io"');
  Lines.Add('    "log"');
  Lines.Add('    "net/http"');
  Lines.Add('    "strings"');
  Lines.Add('    "time"');
  Lines.Add(')');
  Lines.Add('');
end;

procedure EmitGoCallConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Configuration');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('// DefaultBaseURL is the default bridge URL including the target app name.');
  Lines.Add('const DefaultBaseURL = ' + GoStringLit(BaseUrl).Text);
  Lines.Add('');
  Lines.Add('// HTTPCallBaseURL is the current base URL. Assign to override at runtime.');
  Lines.Add('var HTTPCallBaseURL = DefaultBaseURL');
  Lines.Add('');
  Lines.Add('// HTTPCallTimeout is the per-request timeout. Zero or negative means');
  Lines.Add('// "no client-side deadline" (the underlying context governs).');
  Lines.Add('var HTTPCallTimeout = 30 * time.Second');
  Lines.Add('');
  Lines.Add('// DebugLog enables per-request stderr logging when set to true.');
  Lines.Add('var DebugLog = false');
  Lines.Add('');
  Lines.Add('// httpClient is the shared HTTP client. It carries no timeout of its');
  Lines.Add('// own; every call applies HTTPCallTimeout through its context.');
  Lines.Add('var httpClient = &http.Client{}');
  Lines.Add('');
  Lines.Add('// SetBaseURL overrides the base URL used by every generated function.');
  Lines.Add('func SetBaseURL(url string) {');
  Lines.Add('    HTTPCallBaseURL = url');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('// SetTimeout overrides the per-request timeout. Zero or negative disables');
  Lines.Add('// the client-side deadline.');
  Lines.Add('func SetTimeout(d time.Duration) {');
  Lines.Add('    HTTPCallTimeout = d');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('// SetDebugLog toggles verbose request/response logging on stderr.');
  Lines.Add('func SetDebugLog(enabled bool) {');
  Lines.Add('    DebugLog = enabled');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitGoCallError(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Error type');
  Lines.Add('//');
  Lines.Add('// HTTPCallError is the single error type returned by every generated');
  Lines.Add('// function. It implements the standard error interface.');
  Lines.Add('//');
  Lines.Add('//   Code       : bridge or service error code.');
  Lines.Add('//                -1 for network / HTTP failures.');
  Lines.Add('//                -4 for a response with no "code" field.');
  Lines.Add('//                Other negative values for pre-dispatch errors.');
  Lines.Add('//                Non-zero positive values from the service itself.');
  Lines.Add('//   HTTPStatus : HTTP status code, or 0 when no response was received.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('type HTTPCallError struct {');
  Lines.Add('    Message    string');
  Lines.Add('    Code       int');
  Lines.Add('    HTTPStatus int');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('func (e *HTTPCallError) Error() string {');
  Lines.Add('    return fmt.Sprintf("%s (code=%d, http_status=%d)",');
  Lines.Add('        e.Message, e.Code, e.HTTPStatus)');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('// AsyncResult is delivered through the channel returned by every');
  Lines.Add('// <ApiName>Async function. Exactly one value is delivered per call;');
  Lines.Add('// the channel is closed immediately after.');
  Lines.Add('type AsyncResult[T any] struct {');
  Lines.Add('    Value T');
  Lines.Add('    Err   error');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitGoCallTransport(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Internal transport');
  Lines.Add('//');
  Lines.Add('// callAPI is the single point where every generated function enters');
  Lines.Add('// the HTTP transport. It is not intended to be called directly.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('func callAPI(ctx context.Context, apiName string, args []any) (json.RawMessage, error) {');
  Lines.Add('    if HTTPCallTimeout > 0 {');
  Lines.Add('        var cancel context.CancelFunc');
  Lines.Add('        ctx, cancel = context.WithTimeout(ctx, HTTPCallTimeout)');
  Lines.Add('        defer cancel()');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    base := HTTPCallBaseURL');
  Lines.Add('    if base == "" {');
  Lines.Add('        return nil, &HTTPCallError{Message: "HTTPCallBaseURL is empty", Code: -1}');
  Lines.Add('    }');
  Lines.Add('    url := strings.TrimRight(base, "/") + "/" + apiName');
  Lines.Add('');
  Lines.Add('    body, err := json.Marshal(map[string]any{"args": args})');
  Lines.Add('    if err != nil {');
  Lines.Add('        return nil, &HTTPCallError{Message: "marshal request: " + err.Error(), Code: -1}');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if DebugLog {');
  Lines.Add('        log.Printf("[http-json-call] POST %s body=%s", url, body)');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))');
  Lines.Add('    if err != nil {');
  Lines.Add('        return nil, &HTTPCallError{Message: "create request: " + err.Error(), Code: -1}');
  Lines.Add('    }');
  Lines.Add('    req.Header.Set("Content-Type", "application/json; charset=utf-8")');
  Lines.Add('');
  Lines.Add('    resp, err := httpClient.Do(req)');
  Lines.Add('    if err != nil {');
  Lines.Add('        return nil, &HTTPCallError{Message: "network error: " + err.Error(), Code: -1, HTTPStatus: 0}');
  Lines.Add('    }');
  Lines.Add('    defer resp.Body.Close()');
  Lines.Add('');
  Lines.Add('    respBody, err := io.ReadAll(resp.Body)');
  Lines.Add('    if err != nil {');
  Lines.Add('        return nil, &HTTPCallError{Message: "read response: " + err.Error(), Code: -1, HTTPStatus: resp.StatusCode}');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if DebugLog {');
  Lines.Add('        log.Printf("[http-json-call] response %d: %s", resp.StatusCode, respBody)');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if resp.StatusCode < 200 || resp.StatusCode >= 300 {');
  Lines.Add('        return nil, &HTTPCallError{');
  Lines.Add('            Message:    fmt.Sprintf("HTTP %d: %s", resp.StatusCode, string(respBody)),');
  Lines.Add('            Code:       -1,');
  Lines.Add('            HTTPStatus: resp.StatusCode,');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if len(respBody) == 0 {');
  Lines.Add('        return nil, &HTTPCallError{Message: "empty response from bridge", Code: -1, HTTPStatus: resp.StatusCode}');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    var env struct {');
  Lines.Add('        Code   *int            `json:"code"`');
  Lines.Add('        Result json.RawMessage `json:"result"`');
  Lines.Add('        Error  string          `json:"error"`');
  Lines.Add('    }');
  Lines.Add('    if err := json.Unmarshal(respBody, &env); err != nil {');
  Lines.Add('        return nil, &HTTPCallError{Message: "parse envelope: " + err.Error(), Code: -1, HTTPStatus: resp.StatusCode}');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if env.Code == nil {');
  Lines.Add('        if env.Error != "" {');
  Lines.Add('            return nil, &HTTPCallError{Message: env.Error, Code: -1, HTTPStatus: resp.StatusCode}');
  Lines.Add('        }');
  Lines.Add('        return nil, &HTTPCallError{Message: `response has no "code" field`, Code: -4, HTTPStatus: resp.StatusCode}');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if *env.Code != 0 {');
  Lines.Add('        msg := env.Error');
  Lines.Add('        if msg == "" {');
  Lines.Add('            msg = "remote call failed"');
  Lines.Add('        }');
  Lines.Add('        return nil, &HTTPCallError{Message: msg, Code: *env.Code, HTTPStatus: resp.StatusCode}');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if len(env.Result) == 0 || string(env.Result) == "null" {');
  Lines.Add('        return nil, nil');
  Lines.Add('    }');
  Lines.Add('    return env.Result, nil');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitGoCallFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ExportedName, ParamDecl, ArgsSlice, Description: TP_String;
  HasParams: boolean;
  GoRetType: TP_String;
  AsyncValueType: TP_String;
  ImplName: TP_String;
begin
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Typed API functions');
  Lines.Add('//');
  Lines.Add('// Every routine has THREE functions in the generated file:');
  Lines.Add('//   * `<api>Impl`     - unexported, takes ctx, performs the actual work');
  Lines.Add('//   * `<ApiName>`     - exported, blocking, calls impl with Background');
  Lines.Add('//   * `<ApiName>Async` - exported, channel-delivered, calls impl with ctx');
  Lines.Add('//');
  Lines.Add('// Callers should only use the exported pair.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ExportedName := MakeExportedGoIdent(ApiName);
    ParamDecl := BuildGoParamDecl(F.Params);
    ArgsSlice := BuildGoArgsSliceLiteral(F.Params);
    HasParams := Length(F.Params) > 0;

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    if F.IsFunction then
    begin
      GoRetType := ABI_Type_To_Go_Type(F.ReturnType);
      AsyncValueType := GoRetType;
    end
    else
    begin
      GoRetType := '';
      AsyncValueType := 'struct{}';
    end;

    ImplName := MakeSafeGoIdent(ApiName + 'Impl', 0);

    // ---- Impl function -------------------------------------------------
    Lines.Add('// ' + ImplName.Text + ' is the shared implementation behind the');
    Lines.Add('// exported sync and async variants of ' + ExportedName.Text + '.');
    if HasParams then
    begin
      if F.IsFunction then
        Lines.Add('func ' + ImplName.Text + '(ctx context.Context, ' + ParamDecl.Text + ') (' + GoRetType.Text + ', error) {')
      else
        Lines.Add('func ' + ImplName.Text + '(ctx context.Context, ' + ParamDecl.Text + ') error {');
    end
    else
    begin
      if F.IsFunction then
        Lines.Add('func ' + ImplName.Text + '(ctx context.Context) (' + GoRetType.Text + ', error) {')
      else
        Lines.Add('func ' + ImplName.Text + '(ctx context.Context) error {');
    end;

    if F.IsFunction then
      Lines.Add('    raw, err := callAPI(ctx, ' + GoStringLit(ApiName).Text + ', ' + ArgsSlice.Text + ')')
    else
      Lines.Add('    _, err := callAPI(ctx, ' + GoStringLit(ApiName).Text + ', ' + ArgsSlice.Text + ')');
    Lines.Add('    if err != nil {');
    if F.IsFunction then
      Lines.Add('        return ' + ABI_Type_To_Go_Zero(F.ReturnType).Text + ', err')
    else
      Lines.Add('        return err');
    Lines.Add('    }');

    if F.IsFunction then
    begin
      Lines.Add('    if len(raw) == 0 {');
      Lines.Add('        return ' + ABI_Type_To_Go_Zero(F.ReturnType).Text +
        ', &HTTPCallError{Message: "missing result for non-void function", Code: -1}');
      Lines.Add('    }');
      Lines.Add('    var v ' + GoRetType.Text);
      Lines.Add('    if err := json.Unmarshal(raw, &v); err != nil {');
      Lines.Add('        return ' + ABI_Type_To_Go_Zero(F.ReturnType).Text +
        ', &HTTPCallError{Message: "unmarshal result: " + err.Error(), Code: -1, HTTPStatus: 200}');
      Lines.Add('    }');
      Lines.Add('    return v, nil');
    end
    else
    begin
      Lines.Add('    return nil');
    end;
    Lines.Add('}');
    Lines.Add('');

    // ---- Sync exported function ---------------------------------------
    Lines.Add('// ' + ExportedName.Text + ' ' + Description.Text);
    Lines.Add('//');
    Lines.Add('// Blocks the calling goroutine until the remote call completes.');
    if F.IsFunction then
      Lines.Add('// Returns the remote result, or an *HTTPCallError on failure.')
    else
      Lines.Add('// Returns nil on success, or an *HTTPCallError on failure.');
    if HasParams then
    begin
      if F.IsFunction then
        Lines.Add('func ' + ExportedName.Text + '(' + ParamDecl.Text + ') (' + GoRetType.Text + ', error) {')
      else
        Lines.Add('func ' + ExportedName.Text + '(' + ParamDecl.Text + ') error {');
    end
    else
    begin
      if F.IsFunction then
        Lines.Add('func ' + ExportedName.Text + '() (' + GoRetType.Text + ', error) {')
      else
        Lines.Add('func ' + ExportedName.Text + '() error {');
    end;

    if HasParams then
    begin
      if F.IsFunction then
        Lines.Add('    return ' + ImplName.Text + '(context.Background(), ' + BuildGoArgList(F.Params).Text + ')')
      else
        Lines.Add('    return ' + ImplName.Text + '(context.Background(), ' + BuildGoArgList(F.Params).Text + ')');
    end
    else
    begin
      if F.IsFunction then
        Lines.Add('    return ' + ImplName.Text + '(context.Background())')
      else
        Lines.Add('    return ' + ImplName.Text + '(context.Background())');
    end;

    Lines.Add('}');
    Lines.Add('');

    // ---- Async exported function --------------------------------------
    Lines.Add('// ' + ExportedName.Text + 'Async is the asynchronous variant of ' + ExportedName.Text + '.');
    Lines.Add('//');
    Lines.Add('// Returns a buffered channel (capacity 1) that will carry exactly one');
    Lines.Add('// result. The channel is closed immediately after the result is sent.');
    Lines.Add('// ctx cancellation aborts the in-flight HTTP request.');
    if HasParams then
    begin
      Lines.Add('func ' + ExportedName.Text + 'Async(ctx context.Context, ' + ParamDecl.Text +
        ') <-chan AsyncResult[' + AsyncValueType.Text + '] {')
    end
    else
    begin
      Lines.Add('func ' + ExportedName.Text + 'Async(ctx context.Context) <-chan AsyncResult[' +
        AsyncValueType.Text + '] {')
    end;

    Lines.Add('    ch := make(chan AsyncResult[' + AsyncValueType.Text + '], 1)');
    Lines.Add('    go func() {');
    Lines.Add('        defer close(ch)');
    if HasParams then
    begin
      if F.IsFunction then
        Lines.Add('        v, err := ' + ImplName.Text + '(ctx, ' + BuildGoArgList(F.Params).Text + ')')
      else
        Lines.Add('        err := ' + ImplName.Text + '(ctx, ' + BuildGoArgList(F.Params).Text + ')');
    end
    else
    begin
      if F.IsFunction then
        Lines.Add('        v, err := ' + ImplName.Text + '(ctx)')
      else
        Lines.Add('        err := ' + ImplName.Text + '(ctx)');
    end;

    if F.IsFunction then
      Lines.Add('        ch <- AsyncResult[' + AsyncValueType.Text + ']{Value: v, Err: err}')
    else
      Lines.Add('        ch <- AsyncResult[' + AsyncValueType.Text + ']{Err: err}');
    Lines.Add('    }()');
    Lines.Add('    return ch');
    Lines.Add('}');
    Lines.Add('');
  end;
end;

function GenerateHTTPCallGoCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, PackageName, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallGoCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallGoCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  PackageName := MakeGoPackageName(UnitName) + '_call';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Go call package for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitGoCallHeader(Lines, UnitName, PackageName);
    EmitGoCallConfig(Lines, BaseUrl);
    EmitGoCallError(Lines);
    EmitGoCallTransport(Lines);
    EmitGoCallFunctions(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.', [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'go', 'Go HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_go.go', False,
    @GenerateHTTPCallGoCode);
end.
