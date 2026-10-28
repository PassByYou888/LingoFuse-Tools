unit http_php_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine, Z.UReplace,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallPhpCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_php_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_php_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification
// -----------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or
    T.Same('unicodestring') or T.Same('tpascalstring') or
    T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or
    T.Same('extended') or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('longint') or
    T.Same('int64') or T.Same('cardinal') or T.Same('dword') or
    T.Same('longword') or T.Same('word') or T.Same('smallint') or
    T.Same('byte') or T.Same('uint64');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function ABI_Type_To_Php_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) then
    Result := 'float'
  else if ABI_Type_Is_Int(T) then
    Result := 'int'
  else
    Result := 'mixed';
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

function IsPhpReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('__halt_compiler') or S.Same('abstract') or S.Same('and') or
    S.Same('array') or S.Same('as') or S.Same('break') or
    S.Same('callable') or S.Same('case') or S.Same('catch') or
    S.Same('class') or S.Same('clone') or S.Same('const') or
    S.Same('continue') or S.Same('declare') or S.Same('default') or
    S.Same('die') or S.Same('do') or S.Same('echo') or
    S.Same('else') or S.Same('elseif') or S.Same('empty') or
    S.Same('enddeclare') or S.Same('endfor') or S.Same('endforeach') or
    S.Same('endif') or S.Same('endswitch') or S.Same('endwhile') or
    S.Same('eval') or S.Same('exit') or S.Same('extends') or
    S.Same('final') or S.Same('finally') or S.Same('fn') or
    S.Same('for') or S.Same('foreach') or S.Same('function') or
    S.Same('global') or S.Same('goto') or S.Same('if') or
    S.Same('implements') or S.Same('include') or S.Same('include_once') or
    S.Same('instanceof') or S.Same('insteadof') or S.Same('interface') or
    S.Same('isset') or S.Same('list') or S.Same('match') or
    S.Same('namespace') or S.Same('new') or S.Same('or') or
    S.Same('print') or S.Same('private') or S.Same('protected') or
    S.Same('public') or S.Same('readonly') or S.Same('require') or
    S.Same('require_once') or S.Same('return') or S.Same('static') or
    S.Same('switch') or S.Same('throw') or S.Same('trait') or
    S.Same('try') or S.Same('unset') or S.Same('use') or
    S.Same('var') or S.Same('while') or S.Same('xor') or
    S.Same('yield');
end;

function SanitizePhpIdentifier(const Name: TP_String; Index: integer): TP_String;
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or
       ((c >= 'A') and (c <= 'Z')) or
       ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

function MakeSafePhpMethodName(const Name: TP_String; Index: integer): TP_String;
begin
  Result := SanitizePhpIdentifier(MakeApiName(Name), Index);
  if IsPhpReservedWord(Result) then
    Result := Result + '_';
end;

function MakeSafePhpNamespace(const Name: TP_String): TP_String;
begin
  Result := SanitizePhpIdentifier(Name, 0);
  if Result.Len = 0 then
    Result := 'LingoFuseApi';
  if IsPhpReservedWord(Result) then
    Result := Result + '_';
end;

function PhpStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if (c = #39) or (c = #92) then
      Result.Append('\' + c)
    else
      Result.Append(c);
  end;
  Result.Append(#39);
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
    if c = '|' then Result.Append('\|')
    else if c = #10 then Result.Append(' ')
    else if c = #13 then
    else Result.Append(c);
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
    if T[1] = '{' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;
  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then T := T.GetString(1, T.Len).TrimChar(#32#9)
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
  if Comment.Len = 0 then Exit;
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
// PHP signature helpers
// -----------------------------------------------------------------------------

function BuildPhpParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := SanitizePhpIdentifier(Params[i].Name, i);
    T := ABI_Type_To_Php_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + T + ' $' + n;
  end;
end;

// BuildPhpArgList - POSITIONAL array, not a named object.
//
// Emits "['$a', '$b']" (a PHP list literal), so json_encode produces
// {"args": [<a>, <b>]} and the service's extractArgs (which requires
// Array.isArray(req.args)) accepts it.
function BuildPhpArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := SanitizePhpIdentifier(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + '$' + n;
  end;
  Result := Result + ']';
end;

function BuildPhpDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := #39#39
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else
      d := '0';
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
    n := SanitizePhpIdentifier(F.Params[i].Name, i);
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

function BuildPhpSignature(const F: TFunctionStructure; const MethodName: TP_String): TP_String;
var
  ParamPart, RetType: TP_String;
begin
  ParamPart := BuildPhpParamList(F.Params);
  if ParamPart.Len > 0 then
    ParamPart := ParamPart + ', array $options = []'
  else
    ParamPart := 'array $options = []';
  if F.IsFunction then
    RetType := ': ' + ABI_Type_To_Php_Decl(F.ReturnType)
  else
    RetType := ': void';
  Result := 'public static function ' + MethodName + '(' + ParamPart + ')' + RetType;
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
        Log('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]);
        Break;
      end;
    if Supported and F.IsFunction and
       (not ABI_Type_Is_Supported(F.ReturnType)) then
    begin
      Supported := False;
      Log('Skipped "%s": return type "%s" is not a supported ABI type',
        [F.Name.Text, F.ReturnType.Text]);
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

procedure BuildDisambiguatedPhpApiNames(
  const SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList);
var
  i, j, k: integer;
  Base, Candidate: TP_String;
  Conflict: boolean;
begin
  ApiNames.Clear;
  for i := 0 to High(SupportedFuncs) do
  begin
    Base := MakeSafePhpMethodName(SupportedFuncs[i].Name, i);
    Conflict := False;
    for j := 0 to ApiNames.Count - 1 do
      if ApiNames[j].Same(Base) then
      begin
        Conflict := True;
        Break;
      end;
    if Conflict then
    begin
      k := 1;
      repeat
        Candidate := Base + '_' + umlIntToStr(k).Text;
        Conflict := False;
        for j := 0 to ApiNames.Count - 1 do
          if ApiNames[j].Same(Candidate) then
          begin
            Conflict := True;
            Break;
          end;
        if not Conflict then
        begin
          Base := Candidate;
          Break;
        end;
        Inc(k);
      until False;
    end;
    ApiNames.Add(Base);
  end;
end;

// =============================================================================
// CALL MODULE GENERATOR
// =============================================================================

procedure EmitPhpHeader(Lines: TPascalStringList;
  const UnitName, SafeNamespace: TP_String);
begin
  Lines.Add('<?php');
  Lines.Add('// ============================================================================');
  Lines.Add('//  ' + UnitName.Text + '_http_json_call_php.php');
  Lines.Add('// ----------------------------------------------------------------------------');
  Lines.Add('//  Auto-generated by http_php_abi_call_generator_tool.pas.');
  Lines.Add('//  Source model unit: ' + UnitName.Text + '.');
  Lines.Add('//  Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('//  HTTP/JSON ABI call-side wrapper for PHP (PHP 7.4+).');
  Lines.Add('//');
  Lines.Add('//  This module speaks plain HTTP/JSON directly to the service.');
  Lines.Add('//  It does NOT depend on any package or extension beyond:');
  Lines.Add('//    - built-in json_encode / json_decode');
  Lines.Add('//    - built-in curl_* (preferred) or fopen + stream_get_meta_data');
  Lines.Add('//');
  Lines.Add('//  It does NOT touch the LingoFuse mesh. PHP is a CALLER only.');
  Lines.Add('//');
  Lines.Add('//  Wire protocol (both directions):');
  Lines.Add('//    request  = POST <baseUrl>/<api>');
  Lines.Add('//               Content-Type: application/json; charset=utf-8');
  Lines.Add('//               Body: { "args": [v1, v2, ...] }');
  Lines.Add('//                 NOTE: "args" is a POSITIONAL JSON ARRAY.');
  Lines.Add('//                 A named object is rejected by the service.');
  Lines.Add('//');
  Lines.Add('//    response = { "code": 0,  "result": <value> }   on success');
  Lines.Add('//               { "code": -1, "error":  "<message>" } on failure');
  Lines.Add('// ============================================================================');
  Lines.Add('');
  Lines.Add('declare(strict_types=0);');
  Lines.Add('');
  Lines.Add('namespace ' + SafeNamespace.Text + ';');
  Lines.Add('');
end;

procedure EmitPhpConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('// ============================================================================');
  Lines.Add('// Configuration');
  Lines.Add('// ============================================================================');
  Lines.Add('');
  Lines.Add('class HttpJsonCallConfig');
  Lines.Add('{');
  Lines.Add('    /**');
  Lines.Add('     * Base URL of the target service.');
  Lines.Add('     * The full URL for API "X" is: HttpJsonCallConfig::$baseUrl . "/" . "X"');
  Lines.Add('     */');
  Lines.Add('    public static string $baseUrl = ' + PhpStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Per-request timeout, in seconds.');
  Lines.Add('     */');
  Lines.Add('    public static int $httpTimeoutSec = 30;');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Set to true to log every request and response on stderr.');
  Lines.Add('     */');
  Lines.Add('    public static bool $debugLog = false;');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitPhpException(Lines: TPascalStringList);
begin
  Lines.Add('// ============================================================================');
  Lines.Add('// Exception');
  Lines.Add('// ============================================================================');
  Lines.Add('');
  Lines.Add('/**');
  Lines.Add(' * Raised by every generated method on any failure.');
  Lines.Add(' *');
  Lines.Add(' *   getCode()   : numeric code from the service response, or -1/-4');
  Lines.Add(' *                 for transport-level failures.');
  Lines.Add(' *   httpStatus  : HTTP status code, or 0 when no response was received.');
  Lines.Add(' */');
  Lines.Add('class HttpJsonCallError extends \RuntimeException');
  Lines.Add('{');
  Lines.Add('    public int $httpStatus;');
  Lines.Add('');
  Lines.Add('    public function __construct(');
  Lines.Add('        string $message,');
  Lines.Add('        int $code = -1,');
  Lines.Add('        int $httpStatus = 0,');
  Lines.Add('        ?\Throwable $previous = null');
  Lines.Add('    ) {');
  Lines.Add('        parent::__construct($message, $code, $previous);');
  Lines.Add('        $this->httpStatus = $httpStatus;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitPhpTransport(Lines: TPascalStringList);
begin
  Lines.Add('// ============================================================================');
  Lines.Add('// Internal: HTTP transport');
  Lines.Add('// ============================================================================');
  Lines.Add('');
  Lines.Add('final class _HttpJsonInternal');
  Lines.Add('{');
  Lines.Add('    /**');
  Lines.Add('     * POST a JSON request and return the raw response body.');
  Lines.Add('     *');
  Lines.Add('     * @throws HttpJsonCallError on transport failure.');
  Lines.Add('     */');
  Lines.Add('    public static function post(string $url, string $body, int $timeoutSec): string');
  Lines.Add('    {');
  Lines.Add('        if (HttpJsonCallConfig::$debugLog) {');
  Lines.Add('            fwrite(STDERR, "[http-json] POST " . $url . " body=" . $body . "\n");');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        if (function_exists(' + PhpStrLit('curl_init').Text + ')) {');
  Lines.Add('            $raw = self::postViaCurl($url, $body, $timeoutSec);');
  Lines.Add('        } else {');
  Lines.Add('            $raw = self::postViaStream($url, $body, $timeoutSec);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        if (HttpJsonCallConfig::$debugLog) {');
  Lines.Add('            fwrite(STDERR, "[http-json] response: " . substr($raw, 0, 500) . "\n");');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        return $raw;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static function postViaCurl(string $url, string $body, int $timeoutSec): string');
  Lines.Add('    {');
  Lines.Add('        $ch = curl_init($url);');
  Lines.Add('        if ($ch === false) {');
  Lines.Add('            throw new HttpJsonCallError(' + PhpStrLit('curl_init failed').Text + ', -1, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        curl_setopt_array($ch, [');
  Lines.Add('            CURLOPT_POST           => true,');
  Lines.Add('            CURLOPT_POSTFIELDS     => $body,');
  Lines.Add('            CURLOPT_HTTPHEADER     => [');
  Lines.Add('                ' + PhpStrLit('Content-Type: application/json; charset=utf-8').Text + ',');
  Lines.Add('                ' + PhpStrLit('Accept: application/json').Text + ',');
  Lines.Add('            ],');
  Lines.Add('            CURLOPT_RETURNTRANSFER => true,');
  Lines.Add('            CURLOPT_FOLLOWLOCATION => false,');
  Lines.Add('            CURLOPT_TIMEOUT        => $timeoutSec,');
  Lines.Add('            CURLOPT_CONNECTTIMEOUT => min(10, $timeoutSec),');
  Lines.Add('        ]);');
  Lines.Add('');
  Lines.Add('        $raw = curl_exec($ch);');
  Lines.Add('        if ($raw === false) {');
  Lines.Add('            $errno = curl_errno($ch);');
  Lines.Add('            $msg   = curl_error($ch);');
  Lines.Add('            // curl_close() is deprecated since PHP 8.5 and has no');
  Lines.Add('            // effect since PHP 8.0. Only call it on older versions.');
  Lines.Add('            if (PHP_VERSION_ID < 80000) {');
  Lines.Add('                curl_close($ch);');
  Lines.Add('            } else {');
  Lines.Add('                unset($ch);');
  Lines.Add('            }');
  Lines.Add('            if ($errno === CURLE_OPERATION_TIMEDOUT) {');
  Lines.Add('                throw new HttpJsonCallError(');
  Lines.Add('                    ' + PhpStrLit('Request timed out after ').Text + ' . $timeoutSec . ' + PhpStrLit(' s').Text + ',');
  Lines.Add('                    -1, 0);');
  Lines.Add('            }');
  Lines.Add('            throw new HttpJsonCallError(' + PhpStrLit('Network error: ').Text + ' . $msg, -1, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);');
  Lines.Add('        if (PHP_VERSION_ID < 80000) {');
  Lines.Add('            curl_close($ch);');
  Lines.Add('        } else {');
  Lines.Add('            unset($ch);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        if ($status < 200 || $status >= 300) {');
  Lines.Add('            throw new HttpJsonCallError(' + PhpStrLit('HTTP ').Text + ' . $status, -1, $status);');
  Lines.Add('        }');
  Lines.Add('        return (string) $raw;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    private static function postViaStream(string $url, string $body, int $timeoutSec): string');
  Lines.Add('    {');
  Lines.Add('        // Use fopen + stream_get_meta_data instead of');
  Lines.Add('        // file_get_contents + $http_response_header: the latter');
  Lines.Add('        // is deprecated since PHP 8.4.');
  Lines.Add('        $ctx = stream_context_create([');
  Lines.Add('            ' + PhpStrLit('http').Text + ' => [');
  Lines.Add('                ' + PhpStrLit('method').Text + '  => ' + PhpStrLit('POST').Text + ',');
  Lines.Add('                ' + PhpStrLit('header').Text + '  => ' + PhpStrLit('Content-Type: application/json; charset=utf-8').Text + ' . "\r\n" .');
  Lines.Add('                                ' + PhpStrLit('Accept: application/json').Text + ' . "\r\n",');
  Lines.Add('                ' + PhpStrLit('content').Text + ' => $body,');
  Lines.Add('                ' + PhpStrLit('timeout').Text + ' => $timeoutSec,');
  Lines.Add('                ' + PhpStrLit('ignore_errors').Text + ' => true,');
  Lines.Add('            ],');
  Lines.Add('        ]);');
  Lines.Add('');
  Lines.Add('        $fp = @fopen($url, ' + PhpStrLit('rb').Text + ', false, $ctx);');
  Lines.Add('        if ($fp === false) {');
  Lines.Add('            $err = error_get_last();');
  Lines.Add('            $msg = $err !== null ? $err[' + PhpStrLit('message').Text + '] : ' + PhpStrLit('unknown stream error').Text + ';');
  Lines.Add('            throw new HttpJsonCallError(' + PhpStrLit('Network error: ').Text + ' . $msg, -1, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        $meta = stream_get_meta_data($fp);');
  Lines.Add('        $raw  = stream_get_contents($fp);');
  Lines.Add('        @fclose($fp);');
  Lines.Add('        if ($raw === false) {');
  Lines.Add('            $raw = ' + PhpStrLit('').Text + ';');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        $status = 200;');
  Lines.Add('        if (isset($meta[' + PhpStrLit('wrapper_data').Text + ']) && is_array($meta[' + PhpStrLit('wrapper_data').Text + '])) {');
  Lines.Add('            foreach ($meta[' + PhpStrLit('wrapper_data').Text + '] as $hdr) {');
  Lines.Add('                if (is_string($hdr) && preg_match(' + PhpStrLit('#^HTTP/\S+\s+(\d+)#').Text + ', $hdr, $m)) {');
  Lines.Add('                    $status = (int) $m[1];');
  Lines.Add('                }');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        if ($status < 200 || $status >= 300) {');
  Lines.Add('            throw new HttpJsonCallError(' + PhpStrLit('HTTP ').Text + ' . $status, -1, $status);');
  Lines.Add('        }');
  Lines.Add('        return $raw;');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    /**');
  Lines.Add('     * Issue a request and decode the service response envelope.');
  Lines.Add('     *');
  Lines.Add('     * @return mixed The deserialized result field.');
  Lines.Add('     * @throws HttpJsonCallError on any failure.');
  Lines.Add('     */');
  Lines.Add('    public static function callApi(string $apiName, array $args, int $timeoutSec)');
  Lines.Add('    {');
  Lines.Add('        $base = rtrim(HttpJsonCallConfig::$baseUrl, ' + PhpStrLit('/').Text + ');');
  Lines.Add('        $url  = $base . ' + PhpStrLit('/').Text + ' . rawurlencode($apiName);');
  Lines.Add('');
  Lines.Add('        // IMPORTANT: $args MUST be a PHP list (indexed array), not');
  Lines.Add('        // a named map. json_encode then produces {"args": [...]},');
  Lines.Add('        // which is the only shape the service accepts.');
  Lines.Add('        $body = json_encode(');
  Lines.Add('            [' + PhpStrLit('args').Text + ' => array_values($args)],');
  Lines.Add('            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES');
  Lines.Add('        );');
  Lines.Add('        if ($body === false) {');
  Lines.Add('            throw new HttpJsonCallError(');
  Lines.Add('                ' + PhpStrLit('json_encode failed: ').Text + ' . json_last_error_msg(), -1, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        $raw = self::post($url, $body, $timeoutSec);');
  Lines.Add('        if ($raw === ' + PhpStrLit('').Text + ') {');
  Lines.Add('            throw new HttpJsonCallError(' + PhpStrLit('Empty response from service').Text + ', -1, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        $parsed = json_decode($raw, true);');
  Lines.Add('        if (!is_array($parsed)) {');
  Lines.Add('            throw new HttpJsonCallError(');
  Lines.Add('                ' + PhpStrLit('Invalid JSON response: ').Text + ' . substr($raw, 0, 200), -1, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        if (!array_key_exists(' + PhpStrLit('code').Text + ', $parsed) || !is_int($parsed[' + PhpStrLit('code').Text + '])) {');
  Lines.Add('            if (isset($parsed[' + PhpStrLit('error').Text + ']) && is_string($parsed[' + PhpStrLit('error').Text + '])) {');
  Lines.Add('                throw new HttpJsonCallError($parsed[' + PhpStrLit('error').Text + '], -1, 0);');
  Lines.Add('            }');
  Lines.Add('            throw new HttpJsonCallError(');
  Lines.Add('                ' + PhpStrLit('Response has no integer "code" field').Text + ', -4, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        $code = (int) $parsed[' + PhpStrLit('code').Text + '];');
  Lines.Add('        if ($code !== 0) {');
  Lines.Add('            $msg = isset($parsed[' + PhpStrLit('error').Text + ']) && is_string($parsed[' + PhpStrLit('error').Text + '])');
  Lines.Add('                ? $parsed[' + PhpStrLit('error').Text + ']');
  Lines.Add('                : ' + PhpStrLit('Remote call failed').Text + ';');
  Lines.Add('            throw new HttpJsonCallError($msg, $code, 0);');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        return $parsed[' + PhpStrLit('result').Text + '] ?? null;');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitPhpApi(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, ParamPart, ArgList, RetType, Description: TP_String;
begin
  Lines.Add('// ============================================================================');
  Lines.Add('// Typed API');
  Lines.Add('// ============================================================================');
  Lines.Add('');
  Lines.Add('class HttpJsonCallApi');
  Lines.Add('{');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamPart := BuildPhpParamList(F.Params);
    ArgList := BuildPhpArgList(F.Params);
    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    if F.IsFunction then
      RetType := ABI_Type_To_Php_Decl(F.ReturnType)
    else
      RetType := 'void';

    Lines.Add('');
    Lines.Add('    /**');
    Lines.Add('     * ' + Description.Text);
    Lines.Add('     *');
    for j := 0 to High(F.Params) do
      Lines.Add('     * @param ' + ABI_Type_To_Php_Decl(F.Params[j].PascalType).Text +
        ' $' + SanitizePhpIdentifier(F.Params[j].Name, j).Text);
    Lines.Add('     * @param array $options Optional; supports "timeoutSec" => int.');
    if F.IsFunction then
      Lines.Add('     * @return ' + ABI_Type_To_Php_Decl(F.ReturnType).Text)
    else
      Lines.Add('     * @return void');
    Lines.Add('     * @throws HttpJsonCallError on any failure.');
    for j := 0 to High(F.Params) do
      if ABI_Type_Needs_Precision_Note(F.Params[j].PascalType) then
      begin
        Lines.Add('     * @note Parameter $' +
          SanitizePhpIdentifier(F.Params[j].Name, j).Text +
          ' is a 64-bit integer; PHP int is 64-bit on 64-bit platforms.');
        Break;
      end;
    Lines.Add('     */');

    if ParamPart.Len > 0 then
      ParamPart := ParamPart + ', array $options = []'
    else
      ParamPart := 'array $options = []';

    if F.IsFunction then
      Lines.Add('    public static function ' + ApiName.Text +
        '(' + ParamPart.Text + '): ' + RetType.Text)
    else
      Lines.Add('    public static function ' + ApiName.Text +
        '(' + ParamPart.Text + '): void');
    Lines.Add('    {');
    Lines.Add('        $timeout = $options[' + PhpStrLit('timeoutSec').Text + ']');
    Lines.Add('            ?? HttpJsonCallConfig::$httpTimeoutSec;');
    if F.IsFunction then
    begin
      Lines.Add('        return (' + RetType.Text + ') _HttpJsonInternal::callApi(');
      Lines.Add('            ' + PhpStrLit(ApiName).Text + ', ' + ArgList.Text + ', $timeout);');
    end
    else
    begin
      Lines.Add('        _HttpJsonInternal::callApi(');
      Lines.Add('            ' + PhpStrLit(ApiName).Text + ', ' + ArgList.Text + ', $timeout);');
    end;
    Lines.Add('    }');
  end;

  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPCallPhpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, SafeNamespace, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPhpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPhpCode: UnitName is empty');
    Exit;
  end;

  SafeNamespace := MakeSafePhpNamespace(UnitName);
  BaseUrl := 'http://127.0.0.1:8081/' + UnitName;

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedPhpApiNames(SupportedFuncs, ApiNames);

    EmitPhpHeader(Lines, UnitName, SafeNamespace);
    EmitPhpConfig(Lines, BaseUrl);
    EmitPhpException(Lines);
    EmitPhpTransport(Lines);
    EmitPhpApi(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log('Generated PHP call module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]);
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'php', 'PHP HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_php.php', False,
    @GenerateHTTPCallPhpCode);
end.
