unit http_js_abi_call_generator_tool;

// http_js_abi_call_generator_tool - LingoFuse HTTP/JSON ABI Call-Side
// Generator for Web JavaScript (browser).
//
// This unit consumes a TPascal_Func_Model (built with
// Typ_Normalize_Func = tnf_ABI) and produces two independent artifacts:
//
//   1. A standalone browser-side JavaScript client library (IIFE form,
//      attached to window.<UnitName>Api). Suitable for pages served
//      over HTTP where a <script src> tag can load a sibling file.
//
//   2. A self-contained HTML test page. The HTML does NOT reference the
//      library file. All logic is written as plain top-level function
//      declarations directly inside a single inline <script> block.
//      No IIFE, no window namespace, no async/await, no arrow
//      functions: only var, function, and Promise .then/.catch. This
//      structure is chosen for maximum compatibility and so that the
//      page works when opened from file:// as well as from http://.
//
// The generated page reports its state through a visible banner. It
// never fails silently.
//
// Wire protocol (HTTP/JSON, both directions):
//   request  = POST <baseUrl>/<api>  with body
//              { "args": [v1, v2, ...] }
//   response = { "code": 0,  "result": ... }   on success
//              { "code": -1, "error":  ... }   on failure
//
// Author: LingoFuse-pasAgent project

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine, Z.UReplace,
  Z.Pascal_Func_Model,
  Z.Parsing;

function GenerateHTTPCallJsCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallJsHtmlCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallJsReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_js_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_js_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification
// -----------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar') or T.Same('u_string');
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

function ABI_Type_Is_Numeric(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
end;

function ABI_Type_To_Js_Doc(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Numeric(T) then
    Result := 'number'
  else
    Result := '*';
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

function MakeGlobalObjectName(const NormalizedUnit: TP_String): TP_String;
begin
  Result := NormalizedUnit + 'Api';
end;

function MakeSafeJsIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('abstract') or Result.Same('arguments') or Result.Same('await') or Result.Same('boolean') or Result.Same('break') or
    Result.Same('byte') or Result.Same('case') or Result.Same('catch') or Result.Same('char') or Result.Same('class') or Result.Same('const') or
    Result.Same('continue') or Result.Same('debugger') or Result.Same('default') or Result.Same('delete') or Result.Same('do') or
    Result.Same('double') or Result.Same('else') or Result.Same('enum') or Result.Same('eval') or Result.Same('export') or Result.Same('extends') or
    Result.Same('false') or Result.Same('final') or Result.Same('finally') or Result.Same('float') or Result.Same('for') or Result.Same('function') or
    Result.Same('goto') or Result.Same('if') or Result.Same('implements') or Result.Same('import') or Result.Same('in') or
    Result.Same('instanceof') or Result.Same('int') or Result.Same('interface') or Result.Same('let') or Result.Same('long') or
    Result.Same('native') or Result.Same('new') or Result.Same('null') or Result.Same('package') or Result.Same('private') or
    Result.Same('protected') or Result.Same('public') or Result.Same('return') or Result.Same('short') or Result.Same('static') or
    Result.Same('super') or Result.Same('switch') or Result.Same('synchronized') or Result.Same('this') or Result.Same('throw') or
    Result.Same('throws') or Result.Same('transient') or Result.Same('true') or Result.Same('try') or Result.Same('typeof') or
    Result.Same('var') or Result.Same('void') or Result.Same('volatile') or Result.Same('while') or Result.Same('with') or Result.Same('yield') then
    Result := Result + '_';
end;

function JsStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
  hex: array [0..3] of TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #39: Result.Append('\' + #39);
      #34: Result.Append('\"');
      #92: Result.Append('\\');
      #10: Result.Append('\n');
      #13: Result.Append('\r');
      #9:  Result.Append('\t');
      #8:  Result.Append('\b');
      #12: Result.Append('\f');
      else
        if (code < 32) or (code = 127) then
        begin
          hex[0] := HEXDIG[((code shr 12) and $F) + 1];
          hex[1] := HEXDIG[((code shr 8) and $F) + 1];
          hex[2] := HEXDIG[((code shr 4) and $F) + 1];
          hex[3] := HEXDIG[(code and $F) + 1];
          Result.Append('\u');
          Result.Append(hex[0]);
          Result.Append(hex[1]);
          Result.Append(hex[2]);
          Result.Append(hex[3]);
        end
        else
          Result.Append(c);
    end;
  end;
  Result.Append(#39);
end;

function HtmlEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    case c of
      '&': Result.Append('&amp;');
      '<': Result.Append('&lt;');
      '>': Result.Append('&gt;');
      '"': Result.Append('&quot;');
      #39: Result.Append('&#39;');
      else Result.Append(c);
    end;
  end;
end;

// Sanitize_Inline_Script - neutralize every sequence that the HTML
// parser could interpret as an end-of-script or comment boundary
// while scanning an inline <script> element.
//
//   "</"     would end the script element early.
//   "<!--"   enters the HTML5 "script data escaped" state.
//   "-->"    exits that state (and, unpaired, is also suspicious).
//
// We rewrite each sequence by inserting a backslash. Inside JavaScript
// string literals "\/" and "\!" are both valid escapes, and inside
// JavaScript comments the backslash is cosmetic. The rewritten source
// is therefore equivalent to the original from the JavaScript engine's
// point of view, while remaining safe for the HTML parser.
function Sanitize_Inline_Script(const S: TP_String): TP_String;
begin
  Result := S;
  if Result.StrExists('</') then
    Result := U_Replace(Result, '</', '<\/', False, False);
  if Result.StrExists('<!--') then
    Result := U_Replace(Result, '<!--', '<\!--', False, False);
  if Result.StrExists('-->') then
    Result := U_Replace(Result, '-->', '--\>', False, False);
end;

// Sanitize_JSDoc_Line - prevent '*/' inside a comment fragment from
// terminating the surrounding JSDoc block early.
function Sanitize_JSDoc_Line(const S: TP_String): TP_String;
begin
  Result := S;
  if Result.StrExists('*/') then
    Result := U_Replace(Result, '*/', '* /', False, False);
end;

// Sanitize_Html_Text - remove or neutralize every character that could
// confuse the HTML parser if a comment fragment is embedded in a
// plain-text context. This is a stronger guarantee than HtmlEscape:
// it also strips '<', '>', and the sequence '--' which browsers treat
// specially inside comments.
function Sanitize_Html_Text(const S: TP_String): TP_String;
var
  T: TP_String;
begin
  T := S;
  // Replace any run of '<' or '>' with a harmless middle dot.
  if T.StrExists('<') then
    T := U_Replace(T, '<', '(', False, False);
  if T.StrExists('>') then
    T := U_Replace(T, '>', ')', False, False);
  // Replace '--' so '<!--' and '-->' cannot form across fragments.
  if T.StrExists('--') then
    T := U_Replace(T, '--', '- -', False, False);
  Result := T;
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

function BuildJsParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJsIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildJsArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJsIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ']';
end;

// -----------------------------------------------------------------------------
// Supported-function filtering
// -----------------------------------------------------------------------------

type
  TArryFunctionStructure = array of TFunctionStructure;

function CollectSupportedFunctions(Model: TPascal_Func_Model): TArryFunctionStructure;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(f.Params) do
      if not ABI_Type_Is_Supported(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not ABI_Type_Is_Supported(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type',
        [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported and (f.Name.Len = 0) then
    begin
      Supported := False;
      Log('Skipped: routine with empty Name');
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function UniqueApiName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
  candidate: TP_String;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while True do
  begin
    candidate := Base + '_' + umlIntToStr(i).Text;
    if Used.IndexOf(candidate) < 0 then
    begin
      Result := candidate;
      Exit;
    end;
    Inc(i);
  end;
end;

// =============================================================================
// Standalone .js library generator (unchanged IIFE form)
// =============================================================================

procedure EmitJsFunctionJSDoc(Lines: TPascalStringList; const f: TFunctionStructure; const ApiName: TP_String);
var
  i: integer;
  PName, PType, PDesc: TP_String;
  HasDescription: boolean;
  Description: TP_String;
begin
  Description := Sanitize_JSDoc_Line(Sanitize_Html_Text(GetFullDescription(f.Comment)));

  Lines.Add('    /**');

  if Description.Len > 0 then
    Lines.Add('     * ' + Description.Text)
  else
    Lines.Add('     * HTTP/JSON API: ' + ApiName.Text + '.');

  for i := 0 to High(f.Params) do
  begin
    PName := MakeSafeJsIdent(f.Params[i].Name, i);
    PType := ABI_Type_To_Js_Doc(f.Params[i].PascalType);
    PDesc := Sanitize_JSDoc_Line(Sanitize_Html_Text(f.Params[i].Description.TrimChar(#32#9#13#10)));
    PDesc := PDesc.ReplaceChar(#13#10, ' ');
    if PDesc.Len > 200 then
      PDesc := PDesc.GetString(1, 201);
    HasDescription := PDesc.Len > 0;

    if HasDescription then
      Lines.Add('     * @param {' + PType.Text + '} ' + PName.Text + ' - ' + PDesc.Text)
    else
      Lines.Add('     * @param {' + PType.Text + '} ' + PName.Text);
  end;

  if f.IsFunction then
    Lines.Add('     * @returns {Promise<' + ABI_Type_To_Js_Doc(f.ReturnType).Text + '>}')
  else
    Lines.Add('     * @returns {Promise<void>}');

  for i := 0 to High(f.Params) do
    if ABI_Type_Needs_Precision_Note(f.Params[i].PascalType) then
    begin
      Lines.Add('     * @warning Parameter "' + MakeSafeJsIdent(f.Params[i].Name, i).Text +
        '" is a 64-bit integer. JavaScript Number cannot represent all 64-bit values exactly.');
      Break;
    end;

  Lines.Add('     */');
end;

procedure EmitJsFunctionBody(Lines: TPascalStringList; const f: TFunctionStructure; const ApiName: TP_String);
var
  ParamList, ArgList: TP_String;
begin
  ParamList := BuildJsParamList(f.Params);
  ArgList := BuildJsArgList(f.Params);

  Lines.Add('    async function ' + ApiName.Text + '(' + ParamList.Text + ') {');
  Lines.Add('        return await __callApi(' + JsStrLit(ApiName).Text + ', ' + ArgList.Text + ');');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitJsHeader(Lines: TPascalStringList; const UnitName, GlobalObj, BaseUrl: TP_String);
begin
  Lines.Add('/*');
  Lines.Add(' * Auto-generated by http_js_abi_call_generator_tool.');
  Lines.Add(' * Source unit: ' + UnitName.Text + '.');
  Lines.Add(' *');
  Lines.Add(' * Standalone browser-side JavaScript client for the LingoFuse HTTP bridge.');
  Lines.Add(' * No third-party dependencies.');
  Lines.Add(' */');
  Lines.Add('');
  Lines.Add('(function (root) {');
  Lines.Add('    ''use strict'';');
  Lines.Add('');
  Lines.Add('    var __baseUrl = ' + JsStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('    function LFHttpCallError(message, code, httpStatus) {');
  Lines.Add('        this.name = ''LFHttpCallError'';');
  Lines.Add('        this.message = message || ''LingoFuse HTTP call failed'';');
  Lines.Add('        this.code = (typeof code === ''number'') ? code : -1;');
  Lines.Add('        this.httpStatus = (typeof httpStatus === ''number'') ? httpStatus : 0;');
  Lines.Add('        if (typeof Error.captureStackTrace === ''function'') {');
  Lines.Add('            Error.captureStackTrace(this, LFHttpCallError);');
  Lines.Add('        } else {');
  Lines.Add('            this.stack = (new Error(this.message)).stack;');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    LFHttpCallError.prototype = Object.create(Error.prototype);');
  Lines.Add('    LFHttpCallError.prototype.constructor = LFHttpCallError;');
  Lines.Add('');
  Lines.Add('    async function __callApi(apiName, args) {');
  Lines.Add('        var url = __baseUrl + ''/'' + encodeURIComponent(apiName);');
  Lines.Add('        var resp;');
  Lines.Add('        try {');
  Lines.Add('            resp = await fetch(url, {');
  Lines.Add('                method: ''POST'',');
  Lines.Add('                headers: { ''Content-Type'': ''application/json'' },');
  Lines.Add('                body: JSON.stringify({ args: args })');
  Lines.Add('            });');
  Lines.Add('        } catch (e) {');
  Lines.Add('            throw new LFHttpCallError(''Network error: '' + (e && e.message ? e.message : String(e)), -1, 0);');
  Lines.Add('        }');
  Lines.Add('        var text;');
  Lines.Add('        try { text = await resp.text(); } catch (e) {');
  Lines.Add('            throw new LFHttpCallError(''Failed to read response body'', -1, resp.status);');
  Lines.Add('        }');
  Lines.Add('        if (!resp.ok) {');
  Lines.Add('            throw new LFHttpCallError(''HTTP '' + resp.status + '' '' + resp.statusText, -1, resp.status);');
  Lines.Add('        }');
  Lines.Add('        if (!text) {');
  Lines.Add('            throw new LFHttpCallError(''Empty response from bridge'', -1, resp.status);');
  Lines.Add('        }');
  Lines.Add('        var parsed;');
  Lines.Add('        try { parsed = JSON.parse(text); } catch (e) { return text; }');
  Lines.Add('        if (parsed === null || typeof parsed !== ''object'') { return parsed; }');
  Lines.Add('        if (!Object.prototype.hasOwnProperty.call(parsed, ''code'')) {');
  Lines.Add('            if (typeof parsed.error === ''string'') {');
  Lines.Add('                throw new LFHttpCallError(parsed.error, -1, resp.status);');
  Lines.Add('            }');
  Lines.Add('            return parsed;');
  Lines.Add('        }');
  Lines.Add('        if (parsed.code !== 0) {');
  Lines.Add('            throw new LFHttpCallError(parsed.error || ''Remote call failed'', parsed.code, resp.status);');
  Lines.Add('        }');
  Lines.Add('        return parsed.result;');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitJsFooter(Lines: TPascalStringList; const GlobalObj: TP_String;
  const SupportedFuncs: TArryFunctionStructure; const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('    var api = {');
  Lines.Add('        baseUrl: __baseUrl,');
  Lines.Add('        getBaseUrl: function () { return __baseUrl; },');
  Lines.Add('        setBaseUrl: function (url) { __baseUrl = String(url); },');
  Lines.Add('        Error: LFHttpCallError');

  for i := 0 to High(SupportedFuncs) do
    Lines.Add('        , ' + ApiNames[i].Text + ': ' + ApiNames[i].Text);

  Lines.Add('    };');
  Lines.Add('');
  Lines.Add('    root.' + GlobalObj.Text + ' = api;');
  Lines.Add('');
  Lines.Add('})(typeof window !== ''undefined'' ? window :');
  Lines.Add('   (typeof globalThis !== ''undefined'' ? globalThis : this));');
end;

function GenerateHTTPCallJsCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, GlobalObj, BaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  GlobalObj := MakeGlobalObjectName(NormalizedUnit);
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueApiName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    EmitJsHeader(Lines, UnitName, GlobalObj, BaseUrl);
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := ApiNames[i];
      EmitJsFunctionJSDoc(Lines, f, ApiName);
      EmitJsFunctionBody(Lines, f, ApiName);
    end;
    EmitJsFooter(Lines, GlobalObj, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated JS library: %d lines, %d routines.', [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

// =============================================================================
// HTML test page generator (v5 - plain top-level functions, no IIFE)
// =============================================================================

procedure EmitHtml_Card(Html: TPascalStringList; const f: TFunctionStructure;
  const ApiName: TP_String);
var
  i: integer;
  PName, PType, PDesc: TP_String;
  Description: TP_String;
  CardId: TP_String;
begin
  CardId := 'card_' + ApiName;
  Description := Sanitize_Html_Text(GetFullDescription(f.Comment));
  if Description.Len = 0 then
    Description := 'HTTP/JSON API: ' + ApiName;

  Html.Add('      <div class="api-card" id="' + HtmlEscape(CardId).Text + '">');
  Html.Add('        <h3>' + HtmlEscape(ApiName).Text + '</h3>');
  Html.Add('        <p class="api-desc">' + HtmlEscape(Description).Text + '</p>');

  if Length(f.Params) > 0 then
  begin
    Html.Add('        <div class="api-params">');
    for i := 0 to High(f.Params) do
    begin
      PName := MakeSafeJsIdent(f.Params[i].Name, i);
      if ABI_Type_Is_Numeric(f.Params[i].PascalType) then
        PType := 'number'
      else
        PType := 'string';
      PDesc := Sanitize_Html_Text(f.Params[i].Description.TrimChar(#32#9#13#10));
      PDesc := PDesc.ReplaceChar(#13#10, ' ');
      if PDesc.Len > 120 then
        PDesc := PDesc.GetString(1, 121);

      Html.Add('          <label class="api-param">');
      Html.Add('            <span class="api-param-name">' + HtmlEscape(PName).Text +
        ' <em>(' + PType.Text + ')</em></span>');
      if PDesc.Len > 0 then
        Html.Add('            <span class="api-param-desc">' + HtmlEscape(PDesc).Text + '</span>');
      Html.Add('            <input type="text" id="' + HtmlEscape(CardId).Text + '_p_' +
        HtmlEscape(PName).Text + '" data-type="' + PType.Text + '" value="">');
      Html.Add('          </label>');
    end;
    Html.Add('        </div>');
  end;

  Html.Add('        <button type="button" onclick="__call_' + HtmlEscape(ApiName).Text + '()">Call ' +
    HtmlEscape(ApiName).Text + '</button>');
  Html.Add('        <pre class="api-result" id="' + HtmlEscape(CardId).Text + '_r">' + '(not called yet)' + '</pre>');
  Html.Add('      </div>');
end;

// EmitHtml_HelperFunctions - the generic JavaScript plumbing. These
// are top-level function declarations, so the browser hoists them and
// they are always available when the buttons are clicked.
procedure EmitHtml_HelperFunctions(Html: TPascalStringList; const BaseUrl: TP_String);
begin
  Html.Add('');
  Html.Add('  // -------------------------------------------------------------');
  Html.Add('  // Generic helpers. All top-level function declarations.');
  Html.Add('  // -------------------------------------------------------------');
  Html.Add('');
  Html.Add('  var __DEFAULT_BASE_URL = ' + JsStrLit(BaseUrl).Text + ';');
  Html.Add('');
  Html.Add('  function __getBaseUrl() {');
  Html.Add('    var e = document.getElementById(''base-url'');');
  Html.Add('    if (e && e.value) { return e.value; }');
  Html.Add('    return __DEFAULT_BASE_URL;');
  Html.Add('  }');
  Html.Add('');
  Html.Add('  function __setBanner(kind, text) {');
  Html.Add('    var b = document.getElementById(''banner'');');
  Html.Add('    if (!b) { return; }');
  Html.Add('    b.className = ''banner '' + kind;');
  Html.Add('    b.textContent = text;');
  Html.Add('  }');
  Html.Add('');
  Html.Add('  function __showResult(id, kind, text) {');
  Html.Add('    var e = document.getElementById(id);');
  Html.Add('    if (!e) { return; }');
  Html.Add('    e.className = ''api-result '' + kind;');
  Html.Add('    e.textContent = text;');
  Html.Add('  }');
  Html.Add('');
  Html.Add('  function __readParam(id, type) {');
  Html.Add('    var e = document.getElementById(id);');
  Html.Add('    if (!e) { return type === ''number'' ? 0 : ''''; }');
  Html.Add('    var raw = e.value;');
  Html.Add('    if (type === ''number'') {');
  Html.Add('      var n = Number(raw);');
  Html.Add('      return isNaN(n) ? 0 : n;');
  Html.Add('    }');
  Html.Add('    return String(raw);');
  Html.Add('  }');
  Html.Add('');
  Html.Add('  function __postJson(apiName, args) {');
  Html.Add('    var url = __getBaseUrl() + ''/'' + encodeURIComponent(apiName);');
  Html.Add('    return fetch(url, {');
  Html.Add('      method: ''POST'',');
  Html.Add('      headers: { ''Content-Type'': ''application/json'' },');
  Html.Add('      body: JSON.stringify({ args: args })');
  Html.Add('    }).then(function (resp) {');
  Html.Add('      return resp.text().then(function (text) {');
  Html.Add('        if (!resp.ok) {');
  Html.Add('          throw new Error(''HTTP '' + resp.status + '' '' + resp.statusText +');
  Html.Add('            (text ? ('': '' + text) : ''''));');
  Html.Add('        }');
  Html.Add('        if (!text) {');
  Html.Add('          throw new Error(''Empty response from bridge'');');
  Html.Add('        }');
  Html.Add('        var parsed;');
  Html.Add('        try { parsed = JSON.parse(text); }');
  Html.Add('        catch (e) { throw new Error(''Invalid JSON response: '' + text); }');
  Html.Add('        if (parsed === null || typeof parsed !== ''object'') {');
  Html.Add('          return parsed;');
  Html.Add('        }');
  Html.Add('        if (Object.prototype.hasOwnProperty.call(parsed, ''code'')) {');
  Html.Add('          if (parsed.code !== 0) {');
  Html.Add('            var msg = parsed.error || (''remote error code='' + parsed.code);');
  Html.Add('            var err = new Error(msg);');
  Html.Add('            err.code = parsed.code;');
  Html.Add('            throw err;');
  Html.Add('          }');
  Html.Add('          return parsed.result;');
  Html.Add('        }');
  Html.Add('        if (typeof parsed.error === ''string'') {');
  Html.Add('          throw new Error(parsed.error);');
  Html.Add('        }');
  Html.Add('        return parsed;');
  Html.Add('      });');
  Html.Add('    });');
  Html.Add('  }');
  Html.Add('');
  Html.Add('  function __onApplyBaseUrl() {');
  Html.Add('    __setBanner(''ok'', ''Base URL set to '' + __getBaseUrl() + ''.'');');
  Html.Add('  }');
  Html.Add('');
  Html.Add('  function __formatResult(r) {');
  Html.Add('    if (typeof r === ''string'') { return r; }');
  Html.Add('    try { return JSON.stringify(r); }');
  Html.Add('    catch (e) { return String(r); }');
  Html.Add('  }');
  Html.Add('');
end;

// EmitHtml_CallFunction - one dedicated __call_X() per API.
procedure EmitHtml_CallFunction(Html: TPascalStringList; const f: TFunctionStructure;
  const ApiName: TP_String);
var
  i: integer;
  PName, PType, CardId, ResultId, ArgExpr: TP_String;
begin
  CardId := 'card_' + ApiName;
  ResultId := CardId + '_r';

  Html.Add('  function __call_' + ApiName.Text + '() {');
  Html.Add('    var resultId = ' + JsStrLit(ResultId).Text + ';');
  Html.Add('    __showResult(resultId, ''loading'', ''Calling ...'');');

  if Length(f.Params) > 0 then
  begin
    Html.Add('    var args = [');
    for i := 0 to High(f.Params) do
    begin
      PName := MakeSafeJsIdent(f.Params[i].Name, i);
      if ABI_Type_Is_Numeric(f.Params[i].PascalType) then
        PType := 'number'
      else
        PType := 'string';
      ArgExpr := '__readParam(' + JsStrLit(CardId + '_p_' + PName).Text + ', ' +
        JsStrLit(PType).Text + ')';
      if i < High(f.Params) then
        Html.Add('      ' + ArgExpr + ',')
      else
        Html.Add('      ' + ArgExpr);
    end;
    Html.Add('    ];');
  end
  else
    Html.Add('    var args = [];');

  Html.Add('    __postJson(' + JsStrLit(ApiName).Text + ', args)');
  Html.Add('      .then(function (r) {');
  Html.Add('        __showResult(resultId, ''ok'', ''OK: '' + __formatResult(r));');
  Html.Add('        __setBanner(''ok'', ''Last call: ' + HtmlEscape(ApiName).Text + ' succeeded.'');');
  Html.Add('      })');
  Html.Add('      .catch(function (e) {');
  Html.Add('        var msg = (e && e.message) ? e.message : String(e);');
  Html.Add('        __showResult(resultId, ''err'', ''Error: '' + msg);');
  Html.Add('        __setBanner(''err'', ''Last call: ' + HtmlEscape(ApiName).Text + ' failed: '' + msg);');
  Html.Add('      });');
  Html.Add('  }');
  Html.Add('');
end;

procedure EmitHtml_Startup(Html: TPascalStringList);
begin
  Html.Add('  // -------------------------------------------------------------');
  Html.Add('  // Startup');
  Html.Add('  // -------------------------------------------------------------');
  Html.Add('');
  Html.Add('  (function () {');
  Html.Add('    try {');
  Html.Add('      if (typeof location !== ''undefined'' && location.protocol === ''file:'') {');
  Html.Add('        var fw = document.getElementById(''file-warning'');');
  Html.Add('        if (fw) { fw.style.display = ''block''; }');
  Html.Add('      }');
  Html.Add('      var be = document.getElementById(''base-url'');');
  Html.Add('      if (be) { be.value = __DEFAULT_BASE_URL; }');
  Html.Add('      __setBanner(''ok'', ''Page ready. Base URL: '' + __DEFAULT_BASE_URL);');
  Html.Add('    } catch (e) {');
  Html.Add('      __setBanner(''err'', ''Startup error: '' + (e && e.message ? e.message : String(e)));');
  Html.Add('    }');
  Html.Add('  })();');
  Html.Add('');
end;

function GenerateHTTPCallJsHtmlCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl, JsFileName: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  Html: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  JsFileName := NormalizedUnit + '_http_json_call.js';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Html := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueApiName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    Html.Add('<!DOCTYPE html>');
    Html.Add('<html lang="en">');
    Html.Add('<head>');
    Html.Add('  <meta charset="UTF-8">');
    Html.Add('  <meta name="viewport" content="width=device-width, initial-scale=1.0">');
    Html.Add('  <title>' + HtmlEscape(UnitName).Text + ' - LingoFuse HTTP/JSON Test Page</title>');
    Html.Add('  <style>');
    Html.Add('    * { box-sizing: border-box; }');
    Html.Add('    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;');
    Html.Add('      background: #f5f7fa; margin: 0; padding: 24px; color: #1f2937; }');
    Html.Add('    .container { max-width: 960px; margin: 0 auto; }');
    Html.Add('    h1 { font-size: 22px; margin: 0 0 6px; }');
    Html.Add('    .subtitle { color: #6b7280; font-size: 13px; margin: 0 0 18px; }');
    Html.Add('    .banner { border-radius: 8px; padding: 10px 14px; margin: 0 0 12px; font-size: 13px; line-height: 1.5; }');
    Html.Add('    .banner code { background: rgba(255,255,255,0.6); padding: 1px 5px; border-radius: 3px; font-size: 12px; }');
    Html.Add('    .banner.info { background: #e0f2fe; border: 1px solid #7dd3fc; color: #075985; }');
    Html.Add('    .banner.ok   { background: #dcfce7; border: 1px solid #4ade80; color: #14532d; }');
    Html.Add('    .banner.warn { background: #fef3c7; border: 1px solid #f59e0b; color: #92400e; }');
    Html.Add('    .banner.err  { background: #fee2e2; border: 1px solid #ef4444; color: #7f1d1d; }');
    Html.Add('    .global-config { background: #ffffff; border: 1px solid #e5e7eb; border-radius: 8px;');
    Html.Add('      padding: 12px 16px; margin-bottom: 16px; display: flex; align-items: center; gap: 10px; flex-wrap: wrap; font-size: 13px; }');
    Html.Add('    .global-config label { font-weight: 600; color: #374151; }');
    Html.Add('    .global-config input { flex: 1; min-width: 260px; padding: 8px 10px; border: 1px solid #d1d5db;');
    Html.Add('      border-radius: 6px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }');
    Html.Add('    .global-config button { padding: 8px 16px; border: none; background: #2563eb; color: #fff;');
    Html.Add('      border-radius: 6px; cursor: pointer; font-size: 13px; }');
    Html.Add('    .global-config button:hover { background: #1d4ed8; }');
    Html.Add('    .api-card { background: #ffffff; border: 1px solid #e5e7eb; border-radius: 10px;');
    Html.Add('      padding: 16px 18px; margin-bottom: 14px; box-shadow: 0 1px 2px rgba(0,0,0,0.03); }');
    Html.Add('    .api-card h3 { margin: 0 0 4px; font-size: 16px;');
    Html.Add('      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: #111827; }');
    Html.Add('    .api-desc { color: #6b7280; font-size: 13px; margin: 0 0 12px; }');
    Html.Add('    .api-params { display: flex; flex-direction: column; gap: 8px; margin-bottom: 12px; }');
    Html.Add('    .api-param { display: flex; flex-direction: column; gap: 3px; }');
    Html.Add('    .api-param-name { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; color: #111827; }');
    Html.Add('    .api-param-name em { color: #9ca3af; font-style: normal; font-size: 11px; }');
    Html.Add('    .api-param-desc { color: #9ca3af; font-size: 12px; }');
    Html.Add('    .api-param input { padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px;');
    Html.Add('      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }');
    Html.Add('    .api-card > button { padding: 8px 18px; background: #2563eb; color: white; border: none;');
    Html.Add('      border-radius: 6px; font-size: 14px; cursor: pointer; }');
    Html.Add('    .api-card > button:hover { background: #1d4ed8; }');
    Html.Add('    .api-result { margin: 12px 0 0; padding: 10px 12px; background: #f9fafb;');
    Html.Add('      border: 1px solid #e5e7eb; border-radius: 6px;');
    Html.Add('      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px;');
    Html.Add('      min-height: 20px; white-space: pre-wrap; word-break: break-word; color: #374151; }');
    Html.Add('    .api-result.ok { color: #15803d; }');
    Html.Add('    .api-result.err { color: #b91c1c; }');
    Html.Add('    .api-result.loading { color: #b45309; }');
    Html.Add('    footer { margin-top: 24px; font-size: 12px; color: #9ca3af; text-align: center; }');
    Html.Add('    footer code { background: #eef2f6; padding: 2px 6px; border-radius: 4px; }');
    Html.Add('  </style>');
    Html.Add('</head>');
    Html.Add('<body>');
    Html.Add('<div class="container">');
    Html.Add('  <h1>' + HtmlEscape(UnitName).Text + ' &mdash; LingoFuse HTTP/JSON Test Page</h1>');
    Html.Add('  <p class="subtitle">Auto-generated by http_js_abi_call_generator_tool. Sends JSON POST requests to the LingoFuse HTTP bridge.</p>');
    Html.Add('');
    Html.Add('  <div id="banner" class="banner info">Initializing ...</div>');
    Html.Add('');
    Html.Add('  <div id="file-warning" class="banner warn" style="display:none;">');
    Html.Add('    <b>Warning:</b> this page is opened from file://.');
    Html.Add('    The page itself works, but the browser restricts fetch to');
    Html.Add('    http://127.0.0.1 from a file:// origin: the request carries');
    Html.Add('    Origin: null and the bridge must return');
    Html.Add('    Access-Control-Allow-Origin: * (or null).');
    Html.Add('    If calls fail, serve this page over HTTP instead:');
    Html.Add('    python -m http.server 9000 from the directory that contains this');
    Html.Add('    file, then open http://127.0.0.1:9000/' + HtmlEscape(NormalizedUnit).Text + '_http_json_call_test.html.');
    Html.Add('  </div>');
    Html.Add('');
    Html.Add('  <div class="global-config">');
    Html.Add('    <label for="base-url">Base URL:</label>');
    Html.Add('    <input type="text" id="base-url" value="' + HtmlEscape(BaseUrl).Text + '">');
    Html.Add('    <button type="button" onclick="__onApplyBaseUrl()">Apply</button>');
    Html.Add('  </div>');
    Html.Add('');
    Html.Add('  <div id="api-list">');
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := ApiNames[i];
      EmitHtml_Card(Html, f, ApiName);
    end;
    Html.Add('  </div>');
    Html.Add('');
    Html.Add('  <footer>');
    Html.Add('    Standalone library: <code>' + HtmlEscape(JsFileName).Text + '</code>');
    Html.Add('    &middot; API count: <code>' + umlIntToStr(Length(SupportedFuncs)).Text + '</code>');
    Html.Add('  </footer>');
    Html.Add('</div>');
    Html.Add('');
    Html.Add('<!-- ============================================================');
    Html.Add('     All JavaScript for this page is inlined below. There is no');
    Html.Add('     IIFE and no window namespace: every function is a plain');
    Html.Add('     top-level declaration, so the browser hoists it and the');
    Html.Add('     onclick handlers always find it.');
    Html.Add('     ============================================================ -->');
    Html.Add('<script>');
    Html.Add('  "use strict";');
    Html.Add('');

    EmitHtml_HelperFunctions(Html, BaseUrl);

    Html.Add('  // -------------------------------------------------------------');
    Html.Add('  // One handler per API.');
    Html.Add('  // -------------------------------------------------------------');
    Html.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      f := SupportedFuncs[i];
      ApiName := ApiNames[i];
      EmitHtml_CallFunction(Html, f, ApiName);
    end;

    EmitHtml_Startup(Html);

    Html.Add('</script>');
    Html.Add('');
    Html.Add('</body>');
    Html.Add('</html>');

    Result := Html;
    Log(PFormat('Generated HTML: %d lines, %d routines.', [Html.Count, Length(SupportedFuncs)]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Html then Html.Free;
  end;
end;

// =============================================================================
// JS-side README generator
// =============================================================================

function GenerateHTTPCallJsReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, GlobalObj, BaseUrl: TP_String;
  Lines: TPascalStringList;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams: integer;
  HasParams: boolean;
  ParamName, ParamType: TP_String;
  JsFileName, HtmlFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
  ParamList, ArgList: TP_String;
  UrlPath: TP_String;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  GlobalObj := MakeGlobalObjectName(NormalizedUnit);
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  JsFileName := NormalizedUnit + '_http_json_call.js';
  HtmlFileName := NormalizedUnit + '_http_json_call_test.html';

  SupportedFuncs := CollectSupportedFunctions(Model);
  FuncCount := Length(SupportedFuncs);

  TotalParams := 0;
  for i := 0 to FuncCount - 1 do
    TotalParams := TotalParams + Length(SupportedFuncs[i].Params);

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
  ApiNames := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueApiName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    Lines.Add('# ' + UnitName.Text + ' - Browser JavaScript Client');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_js_abi_call_generator_tool.pas`.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **JavaScript library** : `' + JsFileName.Text + '`');
    Lines.Add('> **HTML test page**    : `' + HtmlFileName.Text + '`');
    Lines.Add('> **Global object**     : `window.' + GlobalObj.Text + '` (library only)');
    Lines.Add('> **Exposed functions** : ' + MdInt(FuncCount).Text);
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('Two independent artifacts are produced:');
    Lines.Add('');
    Lines.Add('| File | When to use it |');
    Lines.Add('|------|----------------|');
    Lines.Add('| `' + JsFileName.Text + '` | Your own page is served over HTTP and you want to load a sibling library via `<script src>`. |');
    Lines.Add('| `' + HtmlFileName.Text + '` | You want a zero-dependency test page that works both from `file://` (double-click) and from `http://`. |');
    Lines.Add('');
    Lines.Add('The HTML test page does NOT reference the library file. All logic is written');
    Lines.Add('as plain top-level function declarations in a single inline `<script>` block.');
    Lines.Add('There is no IIFE, no `window` namespace, no `async/await`, and no arrow');
    Lines.Add('functions. This is what makes it work from `file://`.');
    Lines.Add('');
    Lines.Add('## 2. Browser Compatibility');
    Lines.Add('');
    Lines.Add('| Feature | Minimum browser |');
    Lines.Add('|---------|-----------------|');
    Lines.Add('| fetch | Chrome 42, Firefox 39, Safari 10.1 |');
    Lines.Add('| Promise | Chrome 32, Firefox 29, Safari 8 |');
    Lines.Add('');
    Lines.Add('The HTML test page only uses `fetch`, `Promise`, `var`, `function`,');
    Lines.Add('and `JSON`. It does not use `async/await`, arrow functions, or');
    Lines.Add('classes, so it works on every browser that supports `fetch`.');
    Lines.Add('');
    Lines.Add('## 3. Quick Start');
    Lines.Add('');
    Lines.Add('### 3.1 Test page (works from file:// and http://)');
    Lines.Add('');
    Lines.Add('Double-click `' + HtmlFileName.Text + '`. The page opens, shows a');
    Lines.Add('banner with the base URL, and enables every Call button.');
    Lines.Add('');
    Lines.Add('If calls fail with CORS errors and you cannot change the bridge,');
    Lines.Add('serve the page over HTTP instead:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python -m http.server 9000');
    Lines.Add('# open http://127.0.0.1:9000/' + HtmlFileName.Text);
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 3.2 Standalone library (HTTP-served pages only)');
    Lines.Add('');
    Lines.Add('```html');
    Lines.Add('<script src="' + JsFileName.Text + '"></script>');
    Lines.Add('<script>');
    Lines.Add('  var api = window.' + GlobalObj.Text + ';');
    Lines.Add('  api.setBaseUrl(' + JsStrLit(BaseUrl) + ');');
    Lines.Add('  api.someFunction(1, 2).then(function (r) { console.log(r); });');
    Lines.Add('</script>');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('## 4. API Reference');
    Lines.Add('');
    Lines.Add('Total functions: **' + MdInt(FuncCount).Text + '**.');
    Lines.Add('');

    if FuncCount = 0 then
      Lines.Add('_No supported routines were found in the source unit._')
    else
    begin
      if DuplicateNameCount > 0 then
      begin
        Lines.Add('### 4.0 Overloaded routines');
        Lines.Add('');
        Lines.Add('Overloads receive an `_N` suffix (`_1`, `_2`, ...).');
        Lines.Add('');
      end;

      Lines.Add('### 4.1 Summary');
      Lines.Add('');
      Lines.Add('| # | Function | Params | Returns | Description |');
      Lines.Add('|---|----------|--------|---------|-------------|');

      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := ApiNames[i];
        Description := GetFullDescription(f.Comment);
        if Description.Len = 0 then Description := '';
        if f.IsFunction then
          ParamType := ABI_Type_To_Js_Doc(f.ReturnType)
        else
          ParamType := 'void';
        Lines.Add('| ' + MdInt(i + 1).Text + ' | `' + MdCellEscape(ApiName).Text + '`' +
          ' | ' + MdInt(Length(f.Params)).Text +
          ' | `' + MdCellEscape(ParamType).Text + '`' +
          ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := ApiNames[i];
        HasParams := Length(f.Params) > 0;
        ParamList := BuildJsParamList(f.Params);
        ArgList := BuildJsArgList(f.Params);
        UrlPath := '/' + NormalizedUnit + '/' + ApiName;

        Lines.Add('### 4.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');
        Lines.Add('```js');
        Lines.Add('function ' + ApiName.Text + '(' + ParamList.Text + ')');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('- **Returns**: ' + if_(f.IsFunction, '`Promise<' + ABI_Type_To_Js_Doc(f.ReturnType) + '>`', '`Promise<void>`'));
        Lines.Add('- **HTTP route**: `POST ' + UrlPath.Text + '`');
        Lines.Add('');

        Description := GetFullDescription(f.Comment);
        if Description.Len > 0 then
        begin
          Lines.Add('**Description**: ' + Description.Text);
          Lines.Add('');
        end;

        if HasParams then
        begin
          Lines.Add('| # | Name | JS type |');
          Lines.Add('|---|------|---------|');
          for j := 0 to High(f.Params) do
          begin
            ParamName := MakeSafeJsIdent(f.Params[j].Name, j);
            ParamType := ABI_Type_To_Js_Doc(f.Params[j].PascalType);
            Lines.Add('| ' + MdInt(j + 1).Text + ' | `' + MdCellEscape(ParamName).Text + '` | `' +
              MdCellEscape(ParamType).Text + '` |');
          end;
          Lines.Add('');
        end;

        Lines.Add('```js');
        Lines.Add('try {');
        if f.IsFunction then
          Lines.Add('  const r = await window.' + GlobalObj.Text + '.' + ApiName.Text + '(' + ArgList.Text + ');')
        else
          Lines.Add('  await window.' + GlobalObj.Text + '.' + ApiName.Text + '(' + ArgList.Text + ');');
        Lines.Add('} catch (e) { console.error(e.message, e.code, e.httpStatus); }');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    Lines.Add('## 5. Troubleshooting');
    Lines.Add('');
    Lines.Add('| Symptom | Cause | Fix |');
    Lines.Add('|---------|-------|-----|');
    Lines.Add('| Banner is red and buttons do nothing | A JavaScript error occurred while the page was loading | Open DevTools Console |');
    Lines.Add('| CORS error, opened from file:// | Bridge does not allow Origin: null | Serve the page over HTTP, or configure the bridge |');
    Lines.Add('| Network error: Failed to fetch | Bridge is not running | Start bridge.py |');
    Lines.Add('| code: -3 | Bridge pre-check failed | Retry, or start the bridge with --no-precheck |');
    Lines.Add('');

    Lines.Add('## 6. For AI Agents');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('artifacts:');
    Lines.Add('  library: ' + JsFileName.Text);
    Lines.Add('  test_page: ' + HtmlFileName.Text);
    Lines.Add('');
    Lines.Add('test_page_design:');
    Lines.Add('  structure: top-level function declarations only');
    Lines.Add('  no_iife: true');
    Lines.Add('  no_window_namespace: true');
    Lines.Add('  no_async_await: true');
    Lines.Add('  no_arrow_functions: true');
    Lines.Add('  language_features: [var, function, Promise, fetch, JSON]');
    Lines.Add('  works_from_file_protocol: true');
    Lines.Add('');
    Lines.Add('outbound_request:');
    Lines.Add('  method: POST');
    Lines.Add('  content_type: application/json');
    Lines.Add('  body: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('');
    Lines.Add('inbound_response:');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_js_abi_call_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated JS README: %d lines.', [Lines.Count]));
  finally
    UsedApiNames.Free;
    ApiNames.Free;
    if Result <> Lines then Lines.Free;
  end;
end;

end.
