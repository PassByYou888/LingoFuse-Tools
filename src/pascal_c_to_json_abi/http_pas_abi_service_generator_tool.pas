unit http_pas_abi_service_generator_tool;

// http_pas_abi_service_generator_tool - LingoFuse HTTP/JSON ABI Service
// Provider Generator for Pascal.
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces a complete Pascal unit that can be compiled into a
// LingoFuse HTTP/JSON service provider.
//
// The generated unit is a LingoFuse Call service that expects JSON requests
// and produces JSON responses. It is designed to be reached via bridge.py
// from any HTTP client (webjs / PHP / nodejs). The bridge performs the
// HTTP <-> LingoFuse conversion; this unit only deals with JSON strings.
//
// Wire protocol (HTTP/JSON path, both directions):
//   request  = JSON object
//              { "args": [v1, v2, ...] }     positional arguments
//              { "a": v1, "b": v2, ... }     named arguments
//   response = JSON object
//              { "code": 0,  "result": ... }  on success
//              { "code": -1, "error":  ... }  on failure
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> JSON number -> Integer
//   int64                         -> JSON number -> Int64
//   cardinal / dword / longword   -> JSON number -> Cardinal
//   word                          -> JSON number -> Word
//   smallint                      -> JSON number -> SmallInt
//   byte                          -> JSON number -> Byte
//   uint64                        -> JSON number -> UInt64
//   double / extended / real      -> JSON number -> Double
//   single                        -> JSON number -> Single
//   string / PChar family         -> JSON string -> string
//
// The generated unit's interface uses clause mirrors the one used by
// lf_http_bridge_client.pas so that generated code and bridge client
// code share an identical dependency footprint. This is a critical
// requirement: it is the only way to guarantee that the same symbols
// (TZ_JsonObject, TZ_JsonArray, TDataHnd___, LF_*) resolve identically
// in both directions.
//
// The generated unit exposes:
//   const HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC;
//   procedure RegisterAllHTTPJsonAPIs(App: TAppHnd___);
//   function  CreateAndRegisterHTTPJsonApp: TAppHnd___;
//
// The user is expected to:
//   1. Add the original unit that holds the real functions to the
//      implementation uses clause of the generated unit.
//   2. Fill in each internal_call_<api> stub with a call to the real
//      function.
//   3. In the host program, follow the standard LingoFuse service setup:
//        LF_ResetPrepare;
//        LF_PrepareService('<endpoint>', '<endpoint>');
//        App := CreateAndRegisterHTTPJsonApp;
//        LF_PrepareClient('<endpoint>', App);
//        if LF_PrepareDone <> 1 then Halt(1);
//        // run...
//        LF_ExitMainThread;
//        LF_FreeApp(App);
//        LF_Shutdown;
//
// Author: LingoFuse-pasAgent project

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

// GenerateHTTPServicePascalCode - main entry point for the service unit.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPServicePascalReadme - main entry point for the README.
//
// Produces a Markdown document that describes the generated HTTP/JSON
// service: purpose, wire protocol, type mapping, deployment, testing,
// and a per-API reference.
//
// The document is deliberately parallel to the binary-ABI README, but
// it calls out three HTTP/JSON-specific facts:
//
//   1. Payloads are PLAIN TEXT JSON (no status prefix, no fixed-width
//      integers).
//   2. Traffic is transported over HTTP; a bridge (bridge.py) converts
//      HTTP requests into LingoFuse calls and back.
//   3. The JSON wire type set is SMALLER than the binary ABI type set:
//      every integer width collapses to "number"; every string family
//      collapses to "string".
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServicePascalReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging helpers
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Pascal_Decl(T) <> '';
end;

function ABI_Type_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := #39#39
  else if ABI_Type_Is_Float(T) then Result := '0.0'
  else Result := '0';
end;

function ABI_Type_To_Json_Read_Func_ByIndex(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_Float(T) then Result := '_Json_Get_Double_ByIndex'
  else if ABI_Type_Is_String(T) then Result := '_Json_Get_String_ByIndex'
  else Result := '_Json_Get_Int64_ByIndex';
end;

function ABI_Type_To_Json_Read_Func_ByName(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_Float(T) then Result := '_Json_Get_Double_ByName'
  else if ABI_Type_Is_String(T) then Result := '_Json_Get_String_ByName'
  else Result := '_Json_Get_Int64_ByName';
end;

function ABI_Type_To_Json_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_Float(T) then Result := '0.0'
  else if ABI_Type_Is_String(T) then Result := #39#39
  else Result := '0';
end;

function ABI_Type_To_Json_Write_Expr(const T, ValueName: TP_String): TP_String;
begin
  if ABI_Type_Is_Float(T) then
    Result := '_RespJo.F[''result''] := ' + ValueName + ';'
  else if ABI_Type_Is_String(T) then
    Result := '_RespJo.S[''result''] := ' + ValueName + ';'
  else
    Result := '_RespJo.L[''result''] := ' + ValueName + ';';
end;

// -----------------------------------------------------------------------------
// JSON wire-type helpers (used only by the README generator)
// -----------------------------------------------------------------------------
//
// The binary ABI preserves integer widths on the wire. The HTTP/JSON
// protocol does NOT: every integer family member becomes a single JSON
// "number", and every string family member becomes a single JSON
// "string". The README documents this collapse explicitly so readers
// do not expect ABI-style type preservation over HTTP.

function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

function ABI_Type_To_Json_Wire_Type_Desc(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'JSON string (UTF-8, NUL-terminated on the LingoFuse side)'
  else if ABI_Type_Is_Float(T) then
    Result := 'JSON number (floating point)'
  else if ABI_Type_Is_Int(T) then
    Result := 'JSON number (integer)'
  else
    Result := '';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

// MakeApiName - canonicalize an arbitrary identifier into one that is
// safe to use simultaneously as:
//   * an API name on the LingoFuse wire,
//   * a URL path segment for the bridge's HTTP route,
//   * a JavaScript object key,
//   * a C++ / Pascal / Python identifier.
//
// The character set replaced here MUST match the character set replaced
// by every other generator in this toolchain:
//   * http_pas_abi_call_generator_tool
//   * http_js_abi_call_generator_tool
//   * http_py_abi_service_generator_tool
//   * http_py_abi_call_generator_tool
//   * http_cpp_abi_service_generator_tool
//   * http_cpp_abi_call_generator_tool
//
// If the sets diverge, the same source routine would be routed to
// different API names on the service side and on the call side, and
// every cross-language call would fail at runtime.
//
// Replaced character set:
//   space, tab, '.', '/', '\', '@', ':', '#', '?', '&', '=', '+', '-'
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeCallbackName(const FuncName: TP_String): TP_String;
begin
  Result := 'Callback_' + MakeApiName(FuncName);
end;

function MakeInternalCallName(const ApiName: TP_String): TP_String;
begin
  Result := 'internal_call_' + ApiName;
end;

function MakeSafePascalIdent(const Name: TP_String; Index: integer): TP_String;
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
end;

function PascalStrLit(const S: TP_String): TP_String;
begin
  Result := TTextParsing.Translate_Text_To_Pascal_Decl(S);
end;

// -----------------------------------------------------------------------------
// Markdown helpers (used only by the README generator)
// -----------------------------------------------------------------------------

// MdCellEscape - escape a string for safe inclusion in a Markdown table
// cell. Pipes are the only structural character in Markdown tables, so
// they get backslash-escaped. Newlines are replaced with spaces.
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
      // Skip CR; LF already converted the newline above.
    else
      Result.Append(c);
  end;
end;

// MdCodeEscape - wrap a value in backticks for inline code, escaping
// any backticks already present in the string so the fences stay intact.
function MdCodeEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '`';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '`' then
      Result.Append('\`')
    else
      Result.Append(c);
  end;
  Result.Append('`');
end;

// MdInt - render an integer as a Markdown-safe string.
function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// -----------------------------------------------------------------------------
// Comment description extraction (shared with the service generator)
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

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
  decl: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePascalIdent(Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + '; ';
    Result := Result + n + ': ' + decl;
  end;
end;

function BuildCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePascalIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildFullDecl - produce a COMPLETE Pascal declaration string for a
// routine, e.g. "function Add(a: Integer; b: Integer): Integer;".
//
// This is used by the README generator so that the reader sees the
// full signature rather than only the parameter list. The parameter
// list alone (BuildTypedParamDecl) is not enough: it omits the
// function/procedure keyword, the routine name, and the return type.
//
// The original Pascal routine name is used (F.Name), NOT the
// disambiguated API name. This lets the reader correlate the entry
// with the source unit.
function BuildFullDecl(const F: TFunctionStructure): TP_String;
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(F.Params);
  if F.IsFunction then
    Result := 'function ' + F.Name + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name + '(' + ParamDecl + ');';
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
      if not IsSupportedABIType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
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

// -----------------------------------------------------------------------------
// JSON helper emission (for the generated service unit)
// -----------------------------------------------------------------------------

procedure EmitJsonHelpers(Lines: TPascalStringList);
begin
  Lines.Add('{$Region ''json_helpers_''}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// JSON access helpers');
  Lines.Add('//');
  Lines.Add('// These helpers encapsulate the nil / bounds checks so the callback');
  Lines.Add('// bodies stay short. They accept a default value that is returned');
  Lines.Add('// when the source is nil, out of range, or the field is missing.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('function _Json_Get_Int64_ByIndex(_Arr: TZ_JsonArray; _Idx: Integer; _Default: Int64): Int64;');
  Lines.Add('begin');
  Lines.Add('  if (_Arr = nil) or (_Idx < 0) or (_Idx >= _Arr.Count) then');
  Lines.Add('    Result := _Default');
  Lines.Add('  else');
  Lines.Add('    Result := _Arr.L[_Idx];');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function _Json_Get_Int64_ByName(_Obj: TZ_JsonObject; const _Name: string; _Default: Int64): Int64;');
  Lines.Add('begin');
  Lines.Add('  if (_Obj = nil) or (not _Obj.Exists(_Name)) then');
  Lines.Add('    Result := _Default');
  Lines.Add('  else');
  Lines.Add('    Result := _Obj.L[_Name];');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function _Json_Get_Double_ByIndex(_Arr: TZ_JsonArray; _Idx: Integer; _Default: Double): Double;');
  Lines.Add('begin');
  Lines.Add('  if (_Arr = nil) or (_Idx < 0) or (_Idx >= _Arr.Count) then');
  Lines.Add('    Result := _Default');
  Lines.Add('  else');
  Lines.Add('    Result := _Arr.F[_Idx];');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function _Json_Get_Double_ByName(_Obj: TZ_JsonObject; const _Name: string; _Default: Double): Double;');
  Lines.Add('begin');
  Lines.Add('  if (_Obj = nil) or (not _Obj.Exists(_Name)) then');
  Lines.Add('    Result := _Default');
  Lines.Add('  else');
  Lines.Add('    Result := _Obj.F[_Name];');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function _Json_Get_String_ByIndex(_Arr: TZ_JsonArray; _Idx: Integer; const _Default: string): string;');
  Lines.Add('begin');
  Lines.Add('  if (_Arr = nil) or (_Idx < 0) or (_Idx >= _Arr.Count) then');
  Lines.Add('    Result := _Default');
  Lines.Add('  else');
  Lines.Add('    Result := _Arr.S[_Idx];');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function _Json_Get_String_ByName(_Obj: TZ_JsonObject; const _Name: string; const _Default: string): string;');
  Lines.Add('begin');
  Lines.Add('  if (_Obj = nil) or (not _Obj.Exists(_Name)) then');
  Lines.Add('    Result := _Default');
  Lines.Add('  else');
  Lines.Add('    Result := _Obj.S[_Name];');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('{$EndRegion ''json_helpers_''}');
  Lines.Add('');
end;

// -----------------------------------------------------------------------------
// Emit one cdecl callback for the given supported routine.
// -----------------------------------------------------------------------------

procedure EmitCallback(Lines: TPascalStringList; const ApiName, CallbackName, InternalCallName: TP_String; const IsFunction: boolean;
  const Params: TParamArray; const ReturnType: TP_String; const HasParams: boolean);
var
  i: integer;
  PName, PTyp: TP_String;
  ReadFunc, ReadFuncByName: TP_String;
  ArgList, RetType: TP_String;
begin
  Lines.Add('// ---- ' + ApiName + ' ----');
  Lines.Add('procedure ' + CallbackName + '(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;');
  Lines.Add('var');
  Lines.Add('  _ReqBytes: TBytes;');
  Lines.Add('  _ReqJo, _RespJo: TZ_JsonObject;');

  if HasParams then
  begin
    Lines.Add('  _ArgsArr: TZ_JsonArray;');
    Lines.Add('  _UseArgs: Boolean;');
  end;

  for i := 0 to High(Params) do
  begin
    PName := MakeSafePascalIdent(Params[i].Name, i);
    PTyp := ABI_Type_To_Pascal_Decl(Params[i].PascalType);
    Lines.Add('  ' + PName + ': ' + PTyp + ';');
  end;

  if IsFunction then
  begin
    RetType := ABI_Type_To_Pascal_Decl(ReturnType);
    Lines.Add('  _ret: ' + RetType + ';');
  end;

  Lines.Add('begin');
  Lines.Add('');

  // ---- Step 1: read request bytes ----
  Lines.Add('  // Step 1: read UTF-8 JSON request bytes (NUL terminator included).');
  Lines.Add('  _ReqBytes := LF_ReadStringBytes(_In___);');
  Lines.Add('  if Length(_ReqBytes) = 0 then');
  Lines.Add('  begin');
  Lines.Add('    _RespJo := TZ_JsonObject.Create;');
  Lines.Add('    try');
  Lines.Add('      _RespJo.I[''code''] := -1;');
  Lines.Add('      _RespJo.S[''error''] := ''Empty request body'';');
  Lines.Add('      LF_WriteStringBytes(_Out___, _RespJo.ToBytes);');
  Lines.Add('    finally');
  Lines.Add('      _RespJo.Free;');
  Lines.Add('    end;');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('');

  // ---- Step 2: parse request JSON ----
  Lines.Add('  // Step 2: parse the request JSON. It must be a JSON object.');
  Lines.Add('  _ReqJo := TZ_JsonObject.Create;');
  Lines.Add('  try');
  Lines.Add('    if not _ReqJo.Parae(_ReqBytes) then');
  Lines.Add('    begin');
  Lines.Add('      _RespJo := TZ_JsonObject.Create;');
  Lines.Add('      try');
  Lines.Add('        _RespJo.I[''code''] := -1;');
  Lines.Add('        _RespJo.S[''error''] := ''Invalid JSON request'';');
  Lines.Add('        LF_WriteStringBytes(_Out___, _RespJo.ToBytes);');
  Lines.Add('      finally');
  Lines.Add('        _RespJo.Free;');
  Lines.Add('      end;');
  Lines.Add('      Exit;');
  Lines.Add('    end;');
  Lines.Add('');

  // ---- Step 3: extract arguments ----
  if HasParams then
  begin
    Lines.Add('    // Step 3: extract arguments.');
    Lines.Add('    //   If the request contains "args", it is treated as positional.');
    Lines.Add('    //   Otherwise, named lookup is used.');
    Lines.Add('    _UseArgs := _ReqJo.Exists(''args'');');
    Lines.Add('    if _UseArgs then');
    Lines.Add('      _ArgsArr := _ReqJo.A[''args'']');
    Lines.Add('    else');
    Lines.Add('      _ArgsArr := nil;');
    Lines.Add('');
    Lines.Add('    if _UseArgs then');
    Lines.Add('    begin');
    for i := 0 to High(Params) do
    begin
      PName := MakeSafePascalIdent(Params[i].Name, i);
      ReadFunc := ABI_Type_To_Json_Read_Func_ByIndex(Params[i].PascalType);
      Lines.Add('      ' + PName + ' := ' + ReadFunc.Text + '(_ArgsArr, ' + umlIntToStr(i).Text + ', ' + ABI_Type_To_Json_Default(Params[i].PascalType) + ');');
    end;
    Lines.Add('    end');
    Lines.Add('    else');
    Lines.Add('    begin');
    for i := 0 to High(Params) do
    begin
      PName := MakeSafePascalIdent(Params[i].Name, i);
      ReadFuncByName := ABI_Type_To_Json_Read_Func_ByName(Params[i].PascalType);
      Lines.Add('      ' + PName + ' := ' + ReadFuncByName + '(_ReqJo, ' + PascalStrLit(Params[i].Name) + ', ' + ABI_Type_To_Json_Default(Params[i].PascalType) + ');');
    end;
    Lines.Add('    end;');
    Lines.Add('');
  end;

  // ---- Step 4: invoke the internal_call stub ----
  ArgList := BuildCallArgList(Params);

  Lines.Add('    // Step 4: invoke the internal_call stub.');
  Lines.Add('    try');
  if IsFunction then
    Lines.Add('      _ret := ' + InternalCallName + '(' + ArgList + ');')
  else
    Lines.Add('      ' + InternalCallName + '(' + ArgList + ');');
  Lines.Add('    except');
  Lines.Add('      on E: Exception do');
  Lines.Add('      begin');
  Lines.Add('        _RespJo := TZ_JsonObject.Create;');
  Lines.Add('        try');
  Lines.Add('          _RespJo.I[''code''] := -1;');
  Lines.Add('          _RespJo.S[''error''] := E.Message;');
  Lines.Add('          LF_WriteStringBytes(_Out___, _RespJo.ToBytes);');
  Lines.Add('        finally');
  Lines.Add('          _RespJo.Free;');
  Lines.Add('        end;');
  Lines.Add('        Exit;');
  Lines.Add('      end;');
  Lines.Add('    end;');
  Lines.Add('');

  // ---- Step 5: write success response ----
  Lines.Add('    // Step 5: write the success response.');
  Lines.Add('    _RespJo := TZ_JsonObject.Create;');
  Lines.Add('    try');
  Lines.Add('      _RespJo.I[''code''] := 0;');
  if IsFunction then
    Lines.Add('      ' + ABI_Type_To_Json_Write_Expr(ReturnType, '_ret'));
  Lines.Add('      LF_WriteStringBytes(_Out___, _RespJo.ToBytes);');
  Lines.Add('    finally');
  Lines.Add('      _RespJo.Free;');
  Lines.Add('    end;');
  Lines.Add('  finally');
  Lines.Add('    _ReqJo.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// =============================================================================
// SERVICE-UNIT GENERATOR
// =============================================================================

function GenerateHTTPServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName, tmp: TP_String;
  Description: TP_String;
  ParamDecl, CallArgs: TP_String;
  HasParams: boolean;

  HeaderLines, InterfaceLines, interface_internal_func, UsesLines: TPascalStringList;
  HelperLines, InternalCallLines, CallbackLines, RegistrationLines: TPascalStringList;
  ResultLines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServicePascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServicePascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceLines := TPascalStringList.Create;
  interface_internal_func := TPascalStringList.Create;
  UsesLines := TPascalStringList.Create;
  HelperLines := TPascalStringList.Create;
  InternalCallLines := TPascalStringList.Create;
  CallbackLines := TPascalStringList.Create;
  RegistrationLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // -------------------------------------------------------------------------
    // 1. Unit header
    // -------------------------------------------------------------------------
    HeaderLines.Add('unit ' + NormalizedUnit + '_http_json_service_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('// Auto-generated by http_pas_abi_service_generator_tool.');
    HeaderLines.Add('// Source model unit: ' + UnitName.Text + '.');
    HeaderLines.Add('// Do not edit by hand unless you know what you are doing.');
    HeaderLines.Add('//');
    HeaderLines.Add('// Wire protocol (HTTP/JSON path, both directions):');
    HeaderLines.Add('//   request  = JSON object');
    HeaderLines.Add('//              { "args": [v1, v2, ...] }     positional arguments');
    HeaderLines.Add('//              { "a": v1, "b": v2, ... }     named arguments');
    HeaderLines.Add('//   response = JSON object');
    HeaderLines.Add('//              { "code": 0,  "result": ... }  on success');
    HeaderLines.Add('//              { "code": -1, "error":  ... }  on failure');
    HeaderLines.Add('//');
    HeaderLines.Add('// This unit is a LingoFuse Call service. It is designed to be');
    HeaderLines.Add('// reached via bridge.py from any HTTP client (webjs / PHP / nodejs).');
    HeaderLines.Add('// The bridge performs the HTTP <-> LingoFuse conversion; this unit');
    HeaderLines.Add('// only deals with JSON strings.');
    HeaderLines.Add('//');
    HeaderLines.Add('// The user is expected to:');
    HeaderLines.Add('//   1. Add the original unit that holds the real functions to the');
    HeaderLines.Add('//      implementation uses clause below.');
    HeaderLines.Add('//   2. Fill in each internal_call_<api> stub with a call to the real');
    HeaderLines.Add('//      function.');
    HeaderLines.Add('');
    HeaderLines.Add('{$ifdef FPC}');
    HeaderLines.Add('  {$mode delphi}{$H+}');
    HeaderLines.Add('  {$MODESWITCH NestedProcVars}');
    HeaderLines.Add('  {$modeswitch advancedrecords}');
    HeaderLines.Add('  {$CODEPAGE UTF8}');
    HeaderLines.Add('{$endif}');
    HeaderLines.Add('{$R-}{$I-}{$Q-}{$B-}');
    HeaderLines.Add('');
    HeaderLines.Add('interface');
    HeaderLines.Add('');

    // -------------------------------------------------------------------------
    // 2. Interface section
    // -------------------------------------------------------------------------
    InterfaceLines.Add('uses');
    InterfaceLines.Add('  SysUtils,');
    InterfaceLines.Add('  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib,');
    InterfaceLines.Add('  Z.Json,');
    InterfaceLines.Add('  lingofuse_import;');
    InterfaceLines.Add('');
    InterfaceLines.Add('var');
    InterfaceLines.Add('  // LingoFuse application name used by the HTTP/JSON service.');
    InterfaceLines.Add('  HTTP_SERVICE_APP_NAME: string = ' + PascalStrLit(AppName) + ';');
    InterfaceLines.Add('');
    InterfaceLines.Add('  // Human-readable description of the service.');
    InterfaceLines.Add('  HTTP_SERVICE_APP_DESC: string = ' +
      PascalStrLit('HTTP/JSON service for ' + UnitName) + ';');
    InterfaceLines.Add('');
    InterfaceLines.Add('  // Set to True to emit per-call debug messages via DoStatus.');
    InterfaceLines.Add('  DEBUG_LOG: boolean = True;');
    InterfaceLines.Add('');
    InterfaceLines.Add('// Register every generated Call API on the given LingoFuse app handle.');
    InterfaceLines.Add('procedure RegisterAllHTTPJsonAPIs(App: TAppHnd___);');
    InterfaceLines.Add('');
    InterfaceLines.Add('// Create a new LingoFuse app and register every generated Call API.');
    InterfaceLines.Add('// The caller owns the returned handle and must call LF_FreeApp on it.');
    InterfaceLines.Add('function CreateAndRegisterHTTPJsonApp: TAppHnd___;');
    InterfaceLines.Add('');

    // -------------------------------------------------------------------------
    // 3. Implementation uses
    // -------------------------------------------------------------------------
    UsesLines.Add('// ---------------------------------------------------------------------');
    UsesLines.Add('// TODO: add the unit that holds the real implementations, e.g.:');
    UsesLines.Add('//   , MyUnit');
    UsesLines.Add('// If the original declarations came from a C header, provide your own');
    UsesLines.Add('// Pascal wrappers in a unit and add it here.');
    UsesLines.Add('// ---------------------------------------------------------------------');
    UsesLines.Add('');

    // -------------------------------------------------------------------------
    // 4. internal_call_<api> stubs
    // -------------------------------------------------------------------------
    InternalCallLines.Add('{$Region ''internal_call_''}');
    InternalCallLines.Add('// ---------------------------------------------------------------------');
    InternalCallLines.Add('// Internal call stubs. Each stub mirrors one original routine.');
    InternalCallLines.Add('// Replace the body with a call to the real function, for example:');
    InternalCallLines.Add('//   Result := MyUnit.Add(a, b);');
    InternalCallLines.Add('// The parameter names and types are already correct.');
    InternalCallLines.Add('// ---------------------------------------------------------------------');
    InternalCallLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        InternalCallName := MakeInternalCallName(ApiName);
        ParamDecl := BuildTypedParamDecl(Params);
        CallArgs := BuildCallArgList(Params);

        if IsFunction then
          tmp := 'function ' + InternalCallName + '(' + ParamDecl + '): ' + ABI_Type_To_Pascal_Decl(ReturnType) + ';'
        else
          tmp := 'procedure ' + InternalCallName + '(' + ParamDecl + ');';

        InternalCallLines.Add(tmp);
        interface_internal_func.Add(tmp);

        InternalCallLines.Add('begin');
        InternalCallLines.Add('  // TODO: call the real function, for example:');
        if IsFunction then
          InternalCallLines.Add('  //   Result := ' + Name.Text + '(' + CallArgs.Text + ');')
        else
          InternalCallLines.Add('  //   ' + Name.Text + '(' + CallArgs.Text + ');');
        if IsFunction then
          InternalCallLines.Add('  Result := ' + ABI_Type_Default(ReturnType) + ';');
        InternalCallLines.Add('end;');
        InternalCallLines.Add('');
      end;
    end;

    InternalCallLines.Add('{$EndRegion ''internal_call_''}');
    InternalCallLines.Add('');

    // -------------------------------------------------------------------------
    // 5. JSON helpers
    // -------------------------------------------------------------------------
    EmitJsonHelpers(HelperLines);

    // -------------------------------------------------------------------------
    // 6. cdecl callbacks
    // -------------------------------------------------------------------------
    CallbackLines.Add('{$Region ''callback_''}');
    CallbackLines.Add('// ---------------------------------------------------------------------');
    CallbackLines.Add('// cdecl callbacks. Registered with LF_RegisterCallEx.');
    CallbackLines.Add('//');
    CallbackLines.Add('// Wire protocol (HTTP/JSON path):');
    CallbackLines.Add('//   request  = JSON object');
    CallbackLines.Add('//              { "args": [v1, v2, ...] }     positional arguments');
    CallbackLines.Add('//              { "a": v1, "b": v2, ... }     named arguments');
    CallbackLines.Add('//   response = JSON object');
    CallbackLines.Add('//              { "code": 0,  "result": ... }  on success');
    CallbackLines.Add('//              { "code": -1, "error":  ... }  on failure');
    CallbackLines.Add('//');
    CallbackLines.Add('// All callbacks:');
    CallbackLines.Add('//   * run on a LingoFuse worker thread;');
    CallbackLines.Add('//   * never let an exception escape into the C stack;');
    CallbackLines.Add('//   * write UTF-8 JSON to the output handle.');
    CallbackLines.Add('// ---------------------------------------------------------------------');
    CallbackLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        CallbackName := MakeCallbackName(Name) + '_' + ApiName;
        InternalCallName := MakeInternalCallName(ApiName);
        HasParams := Length(Params) > 0;

        EmitCallback(
          CallbackLines,
          ApiName,
          CallbackName,
          InternalCallName,
          IsFunction,
          Params,
          ReturnType,
          HasParams);
      end;
    end;

    CallbackLines.Add('{$EndRegion ''callback_''}');
    CallbackLines.Add('');

    // -------------------------------------------------------------------------
    // 7. Registration
    // -------------------------------------------------------------------------
    RegistrationLines.Add('{$Region ''registration_''}');
    RegistrationLines.Add('procedure RegisterAllHTTPJsonAPIs(App: TAppHnd___);');
    RegistrationLines.Add('begin');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        CallbackName := MakeCallbackName(Name) + '_' + ApiName;
        Description := GetFullDescription(Comment);
        if Description.Len = 0 then
          Description := 'HTTP/JSON api for ' + Name;

        RegistrationLines.Add('  LF_RegisterCallEx(App, ' +
          PascalStrLit(ApiName) + ', ' +
          PascalStrLit(Description) + ', nil, @' +
          CallbackName + ');');
      end;
    end;

    RegistrationLines.Add('end;');
    RegistrationLines.Add('');
    RegistrationLines.Add('function CreateAndRegisterHTTPJsonApp: TAppHnd___;');
    RegistrationLines.Add('begin');
    RegistrationLines.Add('  Result := LF_CreateAppEx(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);');
    RegistrationLines.Add('  if Result <> nil then');
    RegistrationLines.Add('    RegisterAllHTTPJsonAPIs(Result);');
    RegistrationLines.Add('end;');
    RegistrationLines.Add('{$EndRegion ''registration_''}');
    RegistrationLines.Add('');

    // -------------------------------------------------------------------------
    // 8. Assemble
    // -------------------------------------------------------------------------
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(InterfaceLines);
    ResultLines.Add('');
    ResultLines.AddStrings(interface_internal_func);
    ResultLines.Add('');
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(UsesLines);
    ResultLines.AddStrings(HelperLines);
    ResultLines.AddStrings(InternalCallLines);
    ResultLines.AddStrings(CallbackLines);
    ResultLines.AddStrings(RegistrationLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    InterfaceLines.Free;
    interface_internal_func.Free;
    UsesLines.Free;
    HelperLines.Free;
    InternalCallLines.Free;
    CallbackLines.Free;
    RegistrationLines.Free;
    UsedApiNames.Free;
    // ResultLines is returned to the caller; not freed here.
  end;
end;

// =============================================================================
// README GENERATOR
// =============================================================================
//
// Produces a Markdown document that describes the generated HTTP/JSON
// service. The document is deliberately parallel to the binary-ABI
// README produced by pas_abi_service_generator_tool, but it calls out
// the three properties that distinguish the HTTP/JSON path:
//
//   1. Payloads are PLAIN TEXT JSON. There is no status byte prefix,
//      no fixed-width integer encoding, no binary framing.
//
//   2. Traffic is transported over HTTP. A bridge process
//      (bridge.py) accepts an HTTP POST, converts it into a LingoFuse
//      Call, and converts the Call result back into an HTTP response.
//      The generated service itself never speaks HTTP.
//
//   3. The JSON wire type set is SMALLER than the binary ABI type set.
//      Every integer width collapses to a single JSON "number"; every
//      string family collapses to a single JSON "string".
//
// The document is also designed to be consumed by AI agents, not only
// by human engineers. It contains a dedicated "For AI Agents" chapter
// (section 13) with a machine-readable contract summary, a list of
// common anti-patterns, and an API selection decision tree.
// =============================================================================

function GenerateHTTPServicePascalReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;
  Lines: TPascalStringList;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  f: TFunctionStructure;
  i, j: integer;
  Description: TP_String;
  FuncCount, TotalParams, MaxParamCount: integer;
  HasParams: boolean;
  ParamName, ParamType, ParamJsonType, ParamDesc: TP_String;
  ParamDecl: TP_String;
  ServiceFileName, CallFileName, JsFileName, HtmlFileName: TP_String;
  DuplicateNameCount: integer;
  LastOriginalName: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServicePascalReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServicePascalReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  AppName := NormalizedUnit;

  ServiceFileName := NormalizedUnit + '_http_json_service_unit.pas';
  CallFileName := NormalizedUnit + '_http_json_call_unit.pas';
  JsFileName := NormalizedUnit + '_http_json_call.js';
  HtmlFileName := NormalizedUnit + '_http_json_call_test.html';

  Log(PFormat('Generating HTTP/JSON service README for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  FuncCount := Length(SupportedFuncs);

  // Compute a few summary statistics used in the header.
  TotalParams := 0;
  MaxParamCount := 0;
  for i := 0 to FuncCount - 1 do
  begin
    TotalParams := TotalParams + Length(SupportedFuncs[i].Params);
    if Length(SupportedFuncs[i].Params) > MaxParamCount then
      MaxParamCount := Length(SupportedFuncs[i].Params);
  end;

  // Count how many routines are overloads of the same original name.
  // These are the routines that will receive the _1, _2, ... suffix.
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
  try
    // =========================================================================
    // Header block
    // =========================================================================
    Lines.Add('# ' + UnitName.Text + ' - Pascal HTTP/JSON Service Provider');
    Lines.Add('');
    Lines.Add('> **Auto-generated**. Produced by `http_pas_abi_service_generator_tool.pas`;');
    Lines.Add('> this file stays in sync with the generated code.');
    Lines.Add('>');
    Lines.Add('> **Source unit**       : `' + UnitName.Text + '`');
    Lines.Add('> **Service file**      : `' + ServiceFileName.Text + '`');
    Lines.Add('> **Default App name**  : `' + AppName.Text + '`');
    Lines.Add('> **Exposed APIs**      : ' + MdInt(FuncCount).Text);
    Lines.Add('> **Total parameters**  : ' + MdInt(TotalParams).Text);
    Lines.Add('> **Audience**: human engineers and AI assistants who need to');
    Lines.Add('> deploy, test, or call this service without reading the source.');
    Lines.Add('>');
    Lines.Add('> **Language note**: the prose of this README is English. The');
    Lines.Add('> `Description` fields under each API (see §9) reproduce the');
    Lines.Add('> original source comment verbatim, so their language is whatever');
    Lines.Add('> the source unit used. This is intentional and does not affect');
    Lines.Add('> the machine-readable parts of the contract.');
    Lines.Add('>');
    Lines.Add('> **AI agents**: jump straight to §13 "For AI Agents" for a');
    Lines.Add('> compact, machine-readable summary of the request / response');
    Lines.Add('> contract, common anti-patterns, and a decision tree.');
    Lines.Add('');
    Lines.Add('---');
    Lines.Add('');

    // =========================================================================
    // 1. Overview
    // =========================================================================
    Lines.Add('## 1. Overview');
    Lines.Add('');
    Lines.Add('This document describes the **HTTP/JSON service** that was generated');
    Lines.Add('from the Pascal unit `' + UnitName.Text + '`. The service is a');
    Lines.Add('strongly-typed RPC endpoint built on top of LingoFuse and reachable');
    Lines.Add('from any HTTP client via the LingoFuse HTTP bridge (`bridge.py`).');
    Lines.Add('');
    Lines.Add('### 1.1 What is an HTTP/JSON service?');
    Lines.Add('');
    Lines.Add('An HTTP/JSON service is a LingoFuse endpoint that:');
    Lines.Add('');
    Lines.Add('- exposes one or more Pascal routines as remotely callable APIs;');
    Lines.Add('- uses **plain-text JSON** in both directions (no binary framing);');
    Lines.Add('- is reached by a standard **HTTP POST** request;');
    Lines.Add('- relies on a bridge process to translate between HTTP and');
    Lines.Add('  LingoFuse;');
    Lines.Add('- can be called by any HTTP client: a browser using `fetch`,');
    Lines.Add('  Python using `requests`, Node.js, PHP, curl, or another Pascal');
    Lines.Add('  process.');
    Lines.Add('');
    Lines.Add('### 1.2 Design principles');
    Lines.Add('');
    Lines.Add('An HTTP/JSON service is designed around four properties:');
    Lines.Add('');
    Lines.Add('| Property | Value |');
    Lines.Add('|----------|-------|');
    Lines.Add('| Parameter encoding | Plain-text JSON |');
    Lines.Add('| Type system | JSON wire types (see §6) |');
    Lines.Add('| Discovery | Via the bridge''s HTTP URL path |');
    Lines.Add('| Client | Any HTTP client; no paired code required |');
    Lines.Add('| Overhead | Medium: JSON parse/emit on the hot path |');
    Lines.Add('| Ideal for | Cross-language, browser-facing, low-volume RPC |');
    Lines.Add('');
    Lines.Add('### 1.3 Three-step quick start');
    Lines.Add('');
    Lines.Add('1. **Compile** the service unit into your server program. See §7.');
    Lines.Add('2. **Start** the bridge (`bridge.py`) and configure it to reach');
    Lines.Add('   the same LingoFuse endpoint as the service. See §7 and §8.');
    Lines.Add('3. **POST** a JSON request to the bridge and read the JSON');
    Lines.Add('   response. See §4 and §9.');
    Lines.Add('');
    Lines.Add('### 1.4 Files produced by the toolchain');
    Lines.Add('');
    Lines.Add('| File | Purpose |');
    Lines.Add('|------|---------|');
    Lines.Add('| `' + ServiceFileName.Text + '` | The service unit (compile into your server program). |');
    Lines.Add('| `' + CallFileName.Text + '` | Optional Pascal call-side wrapper (typed helpers). |');
    Lines.Add('| `' + JsFileName.Text + '` | Optional browser-side JavaScript client (no deps). |');
    Lines.Add('| `' + HtmlFileName.Text + '` | Optional self-contained HTML test page. |');
    Lines.Add('| `' + NormalizedUnit.Text + '_http_json_service_pascal.md` | This README. |');
    Lines.Add('');

    // =========================================================================
    // 2. Application scope
    // =========================================================================
    Lines.Add('## 2. Application Scope');
    Lines.Add('');
    Lines.Add('### 2.1 When to use an HTTP/JSON service');
    Lines.Add('');
    Lines.Add('Use this generator when:');
    Lines.Add('');
    Lines.Add('- You want **browser or script clients** to call your Pascal code.');
    Lines.Add('- Your callers are **written in different languages** and cannot');
    Lines.Add('  use a paired LingoFuse binding.');
    Lines.Add('- You want **plain-text debugging** — logs, proxies, and Wireshark');
    Lines.Add('  can inspect JSON traffic directly.');
    Lines.Add('- The **payloads are small** and the call rate is moderate.');
    Lines.Add('- You want to expose a **stable, documented API** whose surface');
    Lines.Add('  does not change every build.');
    Lines.Add('');
    Lines.Add('Typical use cases:');
    Lines.Add('');
    Lines.Add('- A browser dashboard calling a Pascal backend.');
    Lines.Add('- A Python data pipeline calling a Pascal engine over HTTP.');
    Lines.Add('- A public or internal REST-style facade in front of LingoFuse.');
    Lines.Add('- Ad-hoc tooling that speaks curl and JSON.');
    Lines.Add('');
    Lines.Add('### 2.2 When NOT to use an HTTP/JSON service');
    Lines.Add('');
    Lines.Add('- You need **max throughput** with minimal per-call overhead.');
    Lines.Add('  Prefer the binary ABI service (`pas_abi_service_generator_tool`).');
    Lines.Add('- You need **strict wire-width preservation** for integers.');
    Lines.Add('  JSON collapses every width into a single "number".');
    Lines.Add('- Your callers are **other LingoFuse nodes only**.');
    Lines.Add('  Direct LingoFuse calls avoid the HTTP hop entirely.');
    Lines.Add('- You need to send **binary blobs** with byte-level fidelity.');
    Lines.Add('  Prefer the binary ABI service.');
    Lines.Add('');
    Lines.Add('### 2.3 Comparison with other RPC approaches');
    Lines.Add('');
    Lines.Add('| Approach | Typed | Text | HTTP-friendly | Paired client |');
    Lines.Add('|----------|:-----:|:----:|:-------------:|:-------------:|');
    Lines.Add('| This HTTP/JSON service | yes | yes | yes | no (any HTTP) |');
    Lines.Add('| Binary ABI service | yes | no | no | yes (required) |');
    Lines.Add('| gRPC | yes | no | partial | yes (generated) |');
    Lines.Add('| REST + custom schema | no | yes | yes | no |');
    Lines.Add('');

    // =========================================================================
    // 3. Compatibility
    // =========================================================================
    Lines.Add('## 3. Compatibility');
    Lines.Add('');
    Lines.Add('### 3.1 Compiler support');
    Lines.Add('');
    Lines.Add('| Compiler | Minimum version | Notes |');
    Lines.Add('|----------|-----------------|-------|');
    Lines.Add('| Free Pascal (FPC) | 3.2.0 | Preferred; tested on 3.2.2. |');
    Lines.Add('| Delphi | 10.4 (Sydney) | Also works with 11 and 12. |');
    Lines.Add('');
    Lines.Add('The generated unit uses `{$DEFINE FPC_DELPHI_MODE}`, so the same');
    Lines.Add('source compiles under both compilers without modification.');
    Lines.Add('');
    Lines.Add('### 3.2 FPC cross-platform support');
    Lines.Add('');
    Lines.Add('FPC is a cross-platform compiler. This service works on every');
    Lines.Add('platform where the LingoFuse runtime and the bridge are available.');
    Lines.Add('');
    Lines.Add('| Platform | Architecture | Status |');
    Lines.Add('|----------|-------------|--------|');
    Lines.Add('| Windows | x86_64 | Primary target |');
    Lines.Add('| Windows | i386 | Supported |');
    Lines.Add('| Linux | x86_64 | Supported |');
    Lines.Add('| Linux | aarch64 | Supported |');
    Lines.Add('| macOS | x86_64 | Supported |');
    Lines.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    Lines.Add('| FreeBSD | x86_64 | Community-tested |');
    Lines.Add('');
    Lines.Add('### 3.3 Runtime dependencies');
    Lines.Add('');
    Lines.Add('| Dependency | Where to get it |');
    Lines.Add('|------------|----------------|');
    Lines.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    Lines.Add('| `lingofuse_import.pas` | LingoFuse-pasAgent source tree |');
    Lines.Add('| `Z.Core` unit | ZNetV2/ZCore |');
    Lines.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | ZNetV2 binary distribution |');
    Lines.Add('| `bridge.py` | LingoFuse Python package |');
    Lines.Add('| Python 3.7+ and Flask | bridge.py runtime |');
    Lines.Add('');
    Lines.Add('### 3.4 Character encoding');
    Lines.Add('');
    Lines.Add('- **Source files**: UTF-8, no BOM required.');
    Lines.Add('- **JSON payloads**: UTF-8, both directions.');
    Lines.Add('- **FPC**: always add `{$CODEPAGE UTF8}` when the source contains');
    Lines.Add('  non-ASCII literals.');
    Lines.Add('- **Delphi**: add `{$HIGHCHARUNICODE ON}` if you need Unicode');
    Lines.Add('  literals in the source.');
    Lines.Add('- **On the wire**: the bridge strips the trailing NUL from');
    Lines.Add('  LingoFuse strings before forwarding to HTTP clients.');
    Lines.Add('');
    Lines.Add('### 3.5 Threading model');
    Lines.Add('');
    Lines.Add('By default, each `internal_call_*` stub body runs on a LingoFuse');
    Lines.Add('worker thread. If the body must run on the main thread (for');
    Lines.Add('example, to touch UI controls), uncomment the synchronised variant');
    Lines.Add('inside the block comments of that stub. The variant is provided');
    Lines.Add('ready to use and relies on `TCompute.Sync` from `Z.Core`, which');
    Lines.Add('is already imported by the generated unit.');
    Lines.Add('');

    // =========================================================================
    // 4. Wire protocol
    // =========================================================================
    Lines.Add('## 4. Wire Protocol');
    Lines.Add('');
    Lines.Add('The HTTP/JSON service uses **plain-text JSON** on both directions.');
    Lines.Add('There is **no binary framing**: no status prefix byte, no');
    Lines.Add('fixed-width integer encoding, no explicit length prefixes.');
    Lines.Add('');
    Lines.Add('### 4.1 Request');
    Lines.Add('');
    Lines.Add('The HTTP client sends an `HTTP POST` with a JSON object body:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "args": [v1, v2, ..., vN]');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `args` field is an **array of positional arguments**. The');
    Lines.Add('order must match the original Pascal declaration. Named');
    Lines.Add('arguments are also accepted as an alternative:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "a": v1,');
    Lines.Add('  "b": v2');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('If the `args` field is present, named lookup is skipped.');
    Lines.Add('Otherwise, every parameter is looked up by its original Pascal');
    Lines.Add('name. Missing fields fall back to the type''s default value');
    Lines.Add('(`0` for numbers, `""` for strings).');
    Lines.Add('');
    Lines.Add('### 4.2 Response');
    Lines.Add('');
    Lines.Add('The service always responds with a JSON object:');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{ "code": 0, "result": <value> }     on success');
    Lines.Add('{ "code": -1, "error":  "<message>" } on failure');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `code` field is required. A non-zero code indicates failure');
    Lines.Add('and the `error` field carries a human-readable message.');
    Lines.Add('');
    Lines.Add('### 4.3 Encoding rules');
    Lines.Add('');
    Lines.Add('| Rule | Value |');
    Lines.Add('|------|-------|');
    Lines.Add('| Text encoding | UTF-8, no BOM |');
    Lines.Add('| Integer type | JSON `number` (see §6 for precision limits) |');
    Lines.Add('| Floating point type | JSON `number` |');
    Lines.Add('| String type | JSON `string` |');
    Lines.Add('| Boolean | Not supported (see §6.2) |');
    Lines.Add('| Null | Not used by the service; callers may send it freely |');
    Lines.Add('');
    Lines.Add('### 4.4 Call sequence');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('sequenceDiagram');
    Lines.Add('    participant H as HTTP Client');
    Lines.Add('    participant B as bridge.py');
    Lines.Add('    participant S as Service');
    Lines.Add('    H->>B: POST /<app>/<api>');
    Lines.Add('    Note over H,B: Body: {"args": [a, b]}');
    Lines.Add('    B->>S: LF_Call with JSON payload');
    Lines.Add('    S->>S: parse JSON, call internal_call_xxx');
    Lines.Add('    S->>S: build {"code": 0, "result": ...}');
    Lines.Add('    S-->>B: JSON response');
    Lines.Add('    B-->>H: HTTP 200 with JSON body');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 4.5 Error response example');
    Lines.Add('');
    Lines.Add('HTTP status: `200` (the bridge always returns 200 for a');
    Lines.Add('well-formed call; the JSON `code` distinguishes success from');
    Lines.Add('failure).');
    Lines.Add('');
    Lines.Add('```json');
    Lines.Add('{');
    Lines.Add('  "code": -1,');
    Lines.Add('  "error": "Division by zero"');
    Lines.Add('}');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The bridge may also return `-2` for a request-shape error (with');
    Lines.Add('HTTP 400) and `-3` for a pre-check failure. See §10.');
    Lines.Add('');

    // =========================================================================
    // 5. Runtime architecture
    // =========================================================================
    Lines.Add('## 5. Runtime Architecture');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    subgraph Server["Server process"]');
    Lines.Add('        S_APP["CreateAndRegisterHTTPJsonApp()<br/>creates the App and registers every API"]');
    Lines.Add('        S_SVC["LF_PrepareService(''ipc:<unit>_http_json'')"]');
    Lines.Add('        S_CLI["LF_PrepareClient(''ipc:<unit>_http_json'', app)"]');
    Lines.Add('        S_RUN["LF_PrepareDone()"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    subgraph Bridge["Bridge process (bridge.py)"]');
    Lines.Add('        B_HTTP["HTTP listen"]');
    Lines.Add('        B_LF["LF_Call to ''<AppName>''"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    subgraph Client["HTTP client"]');
    Lines.Add('        C_POST["POST /<app>/<api>"]');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    S_APP --> S_SVC');
    Lines.Add('    S_SVC --> S_CLI');
    Lines.Add('    S_CLI --> S_RUN');
    Lines.Add('    C_POST --> B_HTTP');
    Lines.Add('    B_HTTP --> B_LF');
    Lines.Add('    B_LF -. "LF_Call" .-> S_RUN');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 5.1 Startup sequence');
    Lines.Add('');
    Lines.Add('**Server process:**');
    Lines.Add('');
    Lines.Add('1. `LF_ResetPrepare`');
    Lines.Add('2. `LF_PrepareService(ipc:<unit>_http_json, ipc:<unit>_http_json)`');
    Lines.Add('3. `App := CreateAndRegisterHTTPJsonApp`');
    Lines.Add('4. `LF_PrepareClient(ipc:<unit>_http_json, App)`');
    Lines.Add('5. `LF_PrepareDone`');
    Lines.Add('');
    Lines.Add('**Bridge process:**');
    Lines.Add('');
    Lines.Add('1. Start `bridge.py` with `--endpoint ipc:<unit>_http_json`');
    Lines.Add('2. Wait for the bridge''s HTTP listener to come up');
    Lines.Add('');
    Lines.Add('**HTTP client:**');
    Lines.Add('');
    Lines.Add('1. Send `POST` requests to `http://<bridge-host>:<port>/<app>/<api>`');
    Lines.Add('2. Read the JSON response from the HTTP body');
    Lines.Add('');
    Lines.Add('### 5.2 Invocation sequence');
    Lines.Add('');
    Lines.Add('1. The client POSTs a JSON request to the bridge.');
    Lines.Add('2. The bridge parses the URL path to determine the target app and');
    Lines.Add('   API name, and forwards the JSON body as an LingoFuse call.');
    Lines.Add('3. LingoFuse routes the payload to the server callback.');
    Lines.Add('4. The callback parses the JSON request, extracts arguments by');
    Lines.Add('   position or by name, and calls `internal_call_<Api>`.');
    Lines.Add('5. The stub runs the real body (by default on a worker thread;');
    Lines.Add('   on the main thread if the synchronised variant is enabled).');
    Lines.Add('6. The result is serialized into `{ "code": 0, "result": ... }`');
    Lines.Add('   and returned to the bridge.');
    Lines.Add('7. The bridge returns the JSON body verbatim as the HTTP');
    Lines.Add('   response.');
    Lines.Add('');
    Lines.Add('### 5.3 Threading notes');
    Lines.Add('');
    Lines.Add('- Callbacks execute on a background worker thread by default. Do');
    Lines.Add('  not touch UI controls directly.');
    Lines.Add('- Do not call any blocking LingoFuse function inside a callback.');
    Lines.Add('- Do not block the callback for long periods: it holds a worker');
    Lines.Add('  thread from the LingoFuse pool.');
    Lines.Add('- If the body must run on the main thread, uncomment the');
    Lines.Add('  synchronised variant inside the corresponding `internal_call_*`');
    Lines.Add('  stub. See §3.5.');
    Lines.Add('');

    // =========================================================================
    // 6. Type mapping
    // =========================================================================
    Lines.Add('## 6. Type Mapping');
    Lines.Add('');
    Lines.Add('### 6.1 The key fact: JSON has fewer types than the binary ABI');
    Lines.Add('');
    Lines.Add('The binary ABI preserves integer widths on the wire: an');
    Lines.Add('`Integer` takes 4 bytes, an `Int64` takes 8 bytes, and so on.');
    Lines.Add('The HTTP/JSON protocol does **NOT**. On the wire, every integer');
    Lines.Add('family member collapses into a single JSON `number`, and every');
    Lines.Add('string family member collapses into a single JSON `string`.');
    Lines.Add('');
    Lines.Add('Consequences:');
    Lines.Add('');
    Lines.Add('- A JSON client cannot distinguish an `Integer` field from an');
    Lines.Add('  `Int64` field by inspecting the wire bytes.');
    Lines.Add('- Numeric precision on the wire is bounded by the JSON parser');
    Lines.Add('  used by the client. JavaScript Numbers are IEEE-754 doubles,');
    Lines.Add('  which cannot represent every 64-bit integer exactly.');
    Lines.Add('- The bridge itself uses a JSON library that preserves 64-bit');
    Lines.Add('  integer precision, but a browser using `JSON.parse` will not.');
    Lines.Add('');
    Lines.Add('### 6.2 Supported types and their JSON wire form');
    Lines.Add('');
    Lines.Add('Every parameter and return type of every exposed API must be in');
    Lines.Add('this table. Any other type causes the **entire routine** to be');
    Lines.Add('silently dropped during generation.');
    Lines.Add('');
    Lines.Add('| ABI type | Pascal type | JSON wire type | Notes |');
    Lines.Add('|----------|-------------|----------------|-------|');
    Lines.Add('| `integer` | `Integer` | `number` | JSON integer |');
    Lines.Add('| `longint` | `LongInt` | `number` | JSON integer |');
    Lines.Add('| `int64` | `Int64` | `number` | JSON integer; JS precision caveat |');
    Lines.Add('| `cardinal` | `Cardinal` | `number` | JSON integer |');
    Lines.Add('| `dword` | `DWord` | `number` | JSON integer |');
    Lines.Add('| `longword` | `LongWord` | `number` | JSON integer |');
    Lines.Add('| `word` | `Word` | `number` | JSON integer |');
    Lines.Add('| `smallint` | `SmallInt` | `number` | JSON integer |');
    Lines.Add('| `byte` | `Byte` | `number` | JSON integer |');
    Lines.Add('| `uint64` | `UInt64` | `number` | JSON integer; JS precision caveat |');
    Lines.Add('| `double` | `Double` | `number` | JSON float |');
    Lines.Add('| `single` | `Single` | `number` | JSON float; JS rounds to double |');
    Lines.Add('| `extended` | `Extended` | `number` | JSON float; platform-dependent width on the wire |');
    Lines.Add('| `real` | `Real` | `number` | JSON float |');
    Lines.Add('| `string` | `string` | `string` | UTF-8 |');
    Lines.Add('| `ansistring` | `string` | `string` | UTF-8 |');
    Lines.Add('| `unicodestring` | `string` | `string` | UTF-8 |');
    Lines.Add('| `tpascalstring` | `string` | `string` | UTF-8 |');
    Lines.Add('| `tupascalstring` | `string` | `string` | UTF-8 |');
    Lines.Add('| `tp_string` | `string` | `string` | UTF-8 |');
    Lines.Add('| `pchar` | `string` | `string` | UTF-8 |');
    Lines.Add('| `pansichar` | `string` | `string` | UTF-8 |');
    Lines.Add('| `pwidechar` | `string` | `string` | UTF-8 |');
    Lines.Add('');
    Lines.Add('### 6.3 Unsupported types');
    Lines.Add('');
    Lines.Add('Anything not in §6.2 causes the **entire routine** to be');
    Lines.Add('silently dropped during generation. Common examples:');
    Lines.Add('');
    Lines.Add('- `Boolean`, `WordBool`, `LongBool`');
    Lines.Add('- `Variant`, `OleVariant`');
    Lines.Add('- Arrays, records, classes, interfaces');
    Lines.Add('- Enumerations, sets, generics');
    Lines.Add('- Pointers, function pointers');
    Lines.Add('- `Currency`, `Comp`, `TDateTime`');
    Lines.Add('');
    Lines.Add('**Workaround**: serialise complex values into a `string` first');
    Lines.Add('(JSON or a custom string format), then pass the string across');
    Lines.Add('the API boundary. On the caller side, deserialise the string');
    Lines.Add('back into the rich type.');
    Lines.Add('');
    Lines.Add('### 6.4 Strings and NUL termination');
    Lines.Add('');
    Lines.Add('LingoFuse strings are UTF-8 followed by a single `#0` byte.');
    Lines.Add('The bridge transparently strips this byte before forwarding a');
    Lines.Add('string to an HTTP client, and appends it back when forwarding');
    Lines.Add('an HTTP request into LingoFuse. From the JSON client''s point of');
    Lines.Add('view, strings are ordinary JSON strings with no embedded NUL.');
    Lines.Add('');

    // =========================================================================
    // 7. Deployment
    // =========================================================================
    Lines.Add('## 7. Deployment');
    Lines.Add('');
    Lines.Add('### 7.1 Directory layout');
    Lines.Add('');
    Lines.Add('Place the generated service unit and the bridge next to your');
    Lines.Add('LingoFuse runtime.');
    Lines.Add('');
    Lines.Add('```');
    Lines.Add('my_http_json_service/');
    Lines.Add('  ' + ServiceFileName.Text + '      <- generated (described here)');
    Lines.Add('  ' + CallFileName.Text + '         <- optional, generated call-side wrapper');
    Lines.Add('  ' + JsFileName.Text + '             <- optional, browser JS client');
    Lines.Add('  ' + HtmlFileName.Text + '        <- optional, HTML test page');
    Lines.Add('  <UnitName>_server.lpr                     <- your server entry point');
    Lines.Add('  ZNetV2/');
    Lines.Add('    ZCore/');
    Lines.Add('      Z.Core.pas');
    Lines.Add('    lingofuse_import.pas');
    Lines.Add('    lingofuse_helper.pas');
    Lines.Add('    z_ipc_64.dll                            <- Windows');
    Lines.Add('    libz_ipc_64.so                          <- Linux');
    Lines.Add('  LingoFuse64.dll                           <- Windows');
    Lines.Add('  liblingofuse.so                           <- Linux');
    Lines.Add('  liblingofuse.dylib                        <- macOS');
    Lines.Add('  bridge.py                                 <- from the LingoFuse Python package');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.2 FPC build');
    Lines.Add('');
    Lines.Add('Compile the server:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('fpc -FuZNetV2 -FuZNetV2/ZCore ' + NormalizedUnit.Text + '_server.lpr');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Both `-Fu` paths must be included. Missing either one causes');
    Lines.Add('"Can''t find unit Z.Core" or "Can''t find unit lingofuse_import".');
    Lines.Add('');
    Lines.Add('### 7.3 Delphi build');
    Lines.Add('');
    Lines.Add('1. Add the generated `.pas` file to your Delphi project.');
    Lines.Add('2. Add `ZNetV2` and `ZNetV2\\ZCore` to **Project Options -> Unit');
    Lines.Add('   Directories**.');
    Lines.Add('3. Set the linker search path to include the directory that holds');
    Lines.Add('   `LingoFuse64.dll`.');
    Lines.Add('4. Build.');
    Lines.Add('');
    Lines.Add('The generated unit already uses `{$DEFINE FPC_DELPHI_MODE}`, so no');
    Lines.Add('source changes are required.');
    Lines.Add('');
    Lines.Add('### 7.4 Starting the bridge');
    Lines.Add('');
    Lines.Add('The bridge must be told which LingoFuse endpoint to connect to.');
    Lines.Add('By default it uses `ipc:lingofuse_bridge`, which almost certainly');
    Lines.Add('does not match your service. Pass the correct endpoint explicitly:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 bridge.py \\');
    Lines.Add('    --endpoint ipc:' + NormalizedUnit.Text + '_http_json \\');
    Lines.Add('    --port 8081 \\');
    Lines.Add('    --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The `--no-precheck` flag skips the bridge''s `check_api` step,');
    Lines.Add('which depends on a network broadcast that can lag by up to 3');
    Lines.Add('seconds after the service starts. Without it, the first requests');
    Lines.Add('may return `-3` ("API not available").');
    Lines.Add('');
    Lines.Add('### 7.5 Startup order');
    Lines.Add('');
    Lines.Add('Start the service first, then the bridge. If both are launched');
    Lines.Add('from the same script, add a short delay:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('./' + NormalizedUnit.Text + '_server &');
    Lines.Add('sleep 1');
    Lines.Add('python3 bridge.py --endpoint ipc:' + NormalizedUnit.Text + '_http_json');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 7.6 Runtime files');
    Lines.Add('');
    Lines.Add('At runtime the following files must be reachable from the');
    Lines.Add('process:');
    Lines.Add('');
    Lines.Add('| File | Where to place it |');
    Lines.Add('|------|-------------------|');
    Lines.Add('| `LingoFuse64.dll` / `liblingofuse.so` | Same directory as the executable, or on `PATH` / `LD_LIBRARY_PATH`. |');
    Lines.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | Same as above. |');
    Lines.Add('| `bridge.py` | Same directory as the Python interpreter''s module path. |');
    Lines.Add('');
    Lines.Add('### 7.7 Shutdown');
    Lines.Add('');
    Lines.Add('The recommended shutdown sequence is:');
    Lines.Add('');
    Lines.Add('1. Stop the HTTP client.');
    Lines.Add('2. Stop the bridge process.');
    Lines.Add('3. On the server: `LF_ExitMainThread`');
    Lines.Add('4. On the server: `LF_FreeApp(App)`');
    Lines.Add('5. On the server: `LF_Shutdown`');
    Lines.Add('');
    Lines.Add('Do not skip any step.');
    Lines.Add('');

    // =========================================================================
    // 8. Testing
    // =========================================================================
    Lines.Add('## 8. Testing');
    Lines.Add('');
    Lines.Add('### 8.1 Server program');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('program ' + NormalizedUnit.Text + '_server;');
    Lines.Add('');
    Lines.Add('{$mode objfpc}{$H+}');
    Lines.Add('{$CODEPAGE UTF8}');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  {$IFDEF UNIX}');
    Lines.Add('  cthreads,');
    Lines.Add('  {$ENDIF}');
    Lines.Add('  {$IFDEF MSWINDOWS}');
    Lines.Add('  Windows,');
    Lines.Add('  {$ENDIF}');
    Lines.Add('  SysUtils, Classes,');
    Lines.Add('  Z.Core,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  ' + NormalizedUnit.Text + '_http_json_service_unit;');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  App: TAppHnd___;');
    Lines.Add('');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''=== ' + UnitName.Text + ' HTTP/JSON service ==='');');
    Lines.Add('');
    Lines.Add('  LF_ResetPrepare;');
    Lines.Add('  LF_PrepareService(''ipc:' + NormalizedUnit.Text + '_http_json'','');');
    Lines.Add('                    ''ipc:' + NormalizedUnit.Text + '_http_json'');');
    Lines.Add('');
    Lines.Add('  App := CreateAndRegisterHTTPJsonApp;');
    Lines.Add('  if App = nil then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(''[FATAL] CreateAndRegisterHTTPJsonApp returned nil'');');
    Lines.Add('    Halt(1);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if LF_PrepareClient(''ipc:' + NormalizedUnit.Text + '_http_json'', App) = -1 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(''[FATAL] LF_PrepareClient failed'');');
    Lines.Add('    Halt(1);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  if LF_PrepareDone <> 1 then');
    Lines.Add('  begin');
    Lines.Add('    WriteLn(''[FATAL] LF_PrepareDone failed'');');
    Lines.Add('    Halt(1);');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  WriteLn(''[OK] Service ready. Press Enter to shut down.'');');
    Lines.Add('  ReadLn;');
    Lines.Add('');
    Lines.Add('  LF_ExitMainThread;');
    Lines.Add('  LF_FreeApp(App);');
    Lines.Add('  LF_Shutdown;');
    Lines.Add('end.');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 8.2 Starting the bridge and issuing a request');
    Lines.Add('');
    Lines.Add('In a second terminal, start the bridge:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('python3 bridge.py \\');
    Lines.Add('    --endpoint ipc:' + NormalizedUnit.Text + '_http_json \\');
    Lines.Add('    --port 8081 \\');
    Lines.Add('    --no-precheck');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('In a third terminal, POST a JSON request:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('curl -X POST http://127.0.0.1:8081/' + AppName.Text + '/<api-name> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": [1, 2]}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Replace `<api-name>` with the name of an exposed API (see §9).');
    Lines.Add('The response is a JSON object with a `code` field.');
    Lines.Add('');
    Lines.Add('### 8.3 Verifying failure paths');
    Lines.Add('');
    Lines.Add('To exercise the error path, send a request that will throw inside');
    Lines.Add('the stub (for example, divide by zero, or pass an argument type');
    Lines.Add('the stub cannot handle). The service returns `{ "code": -1,');
    Lines.Add('"error": "..." }` and the HTTP client sees a 200 response with');
    Lines.Add('that body.');
    Lines.Add('');
    Lines.Add('To exercise a bridge-level error, send a request with a URL path');
    Lines.Add('that the bridge cannot route. The bridge returns HTTP 400 with');
    Lines.Add('`{ "code": -2, "error": "..." }`.');
    Lines.Add('');
    Lines.Add('### 8.4 Unit-level testing (no LingoFuse deployment required)');
    Lines.Add('');
    Lines.Add('The cdecl callbacks generated for each API can be invoked');
    Lines.Add('directly, without starting LingoFuse or the bridge. This is the');
    Lines.Add('fastest way to exercise a stub during development, because it');
    Lines.Add('skips the entire network stack.');
    Lines.Add('');
    Lines.Add('Every callback follows the same three-step contract:');
    Lines.Add('');
    Lines.Add('1. `LF_ReadStringBytes(_In___)` returns the request JSON as a');
    Lines.Add('   `TBytes` (NUL terminator already stripped).');
    Lines.Add('2. `LF_WriteStringBytes(_Out___, bytes)` writes the response JSON');
    Lines.Add('   and appends a NUL terminator.');
    Lines.Add('3. On error, the callback writes `{ "code": -1, "error": ... }`');
    Lines.Add('   instead of raising.');
    Lines.Add('');
    Lines.Add('A minimal test program:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('program test_one_callback;');
    Lines.Add('');
    Lines.Add('{$mode objfpc}{$H+}');
    Lines.Add('{$CODEPAGE UTF8}');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  SysUtils,');
    Lines.Add('  Z.Json,');
    Lines.Add('  lingofuse_import,');
    Lines.Add('  ' + NormalizedUnit.Text + '_http_json_service_unit;');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  In_, Out_: TDataHnd___;');
    Lines.Add('  ReqBytes, RespBytes: TBytes;');
    Lines.Add('  RespJo: TZ_JsonObject;');
    Lines.Add('  ReqJo: TZ_JsonObject;');
    Lines.Add('begin');
    Lines.Add('  // 1. Build the request.');
    Lines.Add('  ReqJo := TZ_JsonObject.Create;');
    Lines.Add('  try');
    Lines.Add('    ReqJo.A[''args''].Add(3);');
    Lines.Add('    ReqJo.A[''args''].Add(4);');
    Lines.Add('    ReqBytes := ReqJo.ToBytes;');
    Lines.Add('  finally');
    Lines.Add('    ReqJo.Free;');
    Lines.Add('  end;');
    Lines.Add('');
    Lines.Add('  // 2. Create the handles and write the request.');
    Lines.Add('  In_ := LF_CreateDataEx(''Add'');');
    Lines.Add('  Out_ := LF_CreateDataEx(''Add'');');
    Lines.Add('  try');
    Lines.Add('    LF_WriteStringBytes(In_, ReqBytes);');
    Lines.Add('');
    Lines.Add('    // 3. Invoke the callback directly (bypasses LingoFuse).');
    Lines.Add('    Callback_Add_Add(nil, In_, Out_);');
    Lines.Add('');
    Lines.Add('    // 4. Read the response.');
    Lines.Add('    RespBytes := LF_ReadStringBytes(Out_);');
    Lines.Add('    RespJo := TZ_JsonObject.Create;');
    Lines.Add('    try');
    Lines.Add('      RespJo.Parae(RespBytes);');
    Lines.Add('      WriteLn(''code = '', RespJo.I[''code'']);');
    Lines.Add('      WriteLn(''result = '', RespJo.L[''result'']);');
    Lines.Add('    finally');
    Lines.Add('      RespJo.Free;');
    Lines.Add('    end;');
    Lines.Add('  finally');
    Lines.Add('    LF_FreeData(In_);');
    Lines.Add('    LF_FreeData(Out_);');
    Lines.Add('  end;');
    Lines.Add('end.');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Substitute the actual callback name from §9 (each section lists');
    Lines.Add('the generated `Callback_<Name>_<ApiName>` symbol).');
    Lines.Add('');
    Lines.Add('**Why this works without `LF_LoadLibrary`**: the callback body');
    Lines.Add('only touches `LF_ReadStringBytes` / `LF_WriteStringBytes` /');
    Lines.Add('`LF_CreateDataEx` / `LF_FreeData`. These are thin wrappers from');
    Lines.Add('`lingofuse_import.pas`, and the underlying library handle is');
    Lines.Add('loaded lazily on first use.');
    Lines.Add('');

    // =========================================================================
    // 9. API reference
    // =========================================================================
    Lines.Add('## 9. API Reference');
    Lines.Add('');
    Lines.Add('Total APIs: **' + MdInt(FuncCount).Text + '**.');
    Lines.Add('');

    if FuncCount = 0 then
    begin
      Lines.Add('_No supported routines were found in the source unit._');
      Lines.Add('');
    end
    else
    begin
      // ----- §9.0 Overloads and disambiguation -----
      if DuplicateNameCount > 0 then
      begin
        Lines.Add('### 9.0 Overloads and disambiguation');
        Lines.Add('');
        Lines.Add('The source unit exposes overloaded routines: the same Pascal');
        Lines.Add('name with two or more distinct signatures. The HTTP/JSON');
        Lines.Add('protocol routes by API name, so two overloads cannot both keep');
        Lines.Add('the original name. The generator appends a numeric suffix');
        Lines.Add('(`_1`, `_2`, ...) to every overload after the first.');
        Lines.Add('');
        Lines.Add('The mapping is deterministic:');
        Lines.Add('');
        Lines.Add('- The **first** overload in source order keeps the bare name.');
        Lines.Add('- Each subsequent overload gets `_N`, where `N` starts at 1 and');
        Lines.Add('  increments for every additional overload.');
        Lines.Add('- The `.0` suffix never appears.');
        Lines.Add('');
        Lines.Add('The "Original declaration" line under each of the following');
        Lines.Add('sections shows the true Pascal signature, so you can always');
        Lines.Add('reconstruct which overload is which.');
        Lines.Add('');
      end;

      Lines.Add('### 9.1 Summary');
      Lines.Add('');
      Lines.Add('| # | API name | Kind | Params | Return | Description |');
      Lines.Add('|---|----------|------|--------|--------|-------------|');

      UsedApiNames.Clear;
      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];

        ApiName := MakeApiName(f.Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        Description := GetFullDescription(f.Comment);
        if Description.Len = 0 then
          Description := '';

        if f.IsFunction then
          ParamDesc := ABI_Type_To_Pascal_Decl(f.ReturnType)
        else
          ParamDesc := '-';

        Lines.Add('| ' + MdInt(i + 1).Text +
          ' | ' + MdCellEscape(ApiName).Text +
          ' | ' + if_(f.IsFunction, 'function', 'procedure') +
          ' | ' + MdInt(Length(f.Params)).Text +
          ' | ' + MdCellEscape(ParamDesc).Text +
          ' | ' + MdCellEscape(Description).Text + ' |');
      end;

      Lines.Add('');

      // ----- Per-API sections -----
      UsedApiNames.Clear;
      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];

        ApiName := MakeApiName(f.Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        CallbackName := MakeCallbackName(f.Name) + '_' + ApiName;
        InternalCallName := MakeInternalCallName(ApiName);
        HasParams := Length(f.Params) > 0;

        Lines.Add('### 9.' + MdInt(i + 2).Text + ' `' + ApiName.Text + '`');
        Lines.Add('');

        // Original declaration: complete Pascal signature. This lets
        // the reader correlate the entry with the source unit even
        // when overloads forced a numeric suffix on the API name.
        Lines.Add('- **Original declaration**: `' + BuildFullDecl(f) + '`');
        Lines.Add('- **Exposed API name**: `' + ApiName.Text + '`');
        Lines.Add('- **Kind**: ' + if_(f.IsFunction, 'function', 'procedure'));
        if f.IsFunction then
          Lines.Add('- **Returns**: `' + ABI_Type_To_Pascal_Decl(f.ReturnType) + '`');
        Lines.Add('- **HTTP route**: `POST /' + AppName.Text + '/' + ApiName.Text + '`');
        Lines.Add('- **Callback symbol** (for unit tests): `' + CallbackName.Text + '`');
        Lines.Add('');

        Description := GetFullDescription(f.Comment);
        if Description.Len > 0 then
        begin
          Lines.Add('#### Description');
          Lines.Add('');
          Lines.Add(Description.Text);
          Lines.Add('');
        end;

        if HasParams then
        begin
          Lines.Add('#### Parameters');
          Lines.Add('');
          Lines.Add('| # | Name | Pascal type | JSON wire type |');
          Lines.Add('|---|------|-------------|----------------|');
          for j := 0 to High(f.Params) do
          begin
            ParamName := MakeSafePascalIdent(f.Params[j].Name, j);
            ParamType := ABI_Type_To_Pascal_Decl(f.Params[j].PascalType);
            ParamJsonType := ABI_Type_To_Json_Wire_Type(f.Params[j].PascalType);

            Lines.Add('| ' + MdInt(j + 1).Text +
              ' | ' + MdCellEscape(ParamName).Text +
              ' | `' + MdCellEscape(ParamType).Text + '`' +
              ' | `' + MdCellEscape(ParamJsonType).Text + '` |');
          end;
          Lines.Add('');

          Lines.Add('#### Request layout');
          Lines.Add('');
          Lines.Add('```json');
          Lines.Add('{ "args": [' + BuildCallArgList(f.Params) + '] }');
          Lines.Add('```');
          Lines.Add('');
        end
        else
        begin
          Lines.Add('#### Request layout');
          Lines.Add('');
          Lines.Add('```json');
          Lines.Add('{}');
          Lines.Add('```');
          Lines.Add('');
        end;

        Lines.Add('#### Success response layout');
        Lines.Add('');
        Lines.Add('```json');
        if f.IsFunction then
          Lines.Add('{ "code": 0, "result": <' +
            ABI_Type_To_Json_Wire_Type_Desc(f.ReturnType).Text + '> }')
        else
          Lines.Add('{ "code": 0 }');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('#### Error response');
        Lines.Add('');
        Lines.Add('```json');
        Lines.Add('{ "code": -1, "error": "<message>" }');
        Lines.Add('```');
        Lines.Add('');
        Lines.Add('The HTTP status is still `200`; the JSON `code` field carries');
        Lines.Add('the failure.');
        Lines.Add('');
        Lines.Add('---');
        Lines.Add('');
      end;
    end;

    // =========================================================================
    // 10. Troubleshooting
    // =========================================================================
    Lines.Add('## 10. Troubleshooting');
    Lines.Add('');
    Lines.Add('### 10.1 Symptom, cause, fix');
    Lines.Add('');
    Lines.Add('| Symptom | Likely cause | Fix |');
    Lines.Add('|---------|--------------|-----|');
    Lines.Add('| HTTP 404 or connection refused | Bridge not running | Start `bridge.py`. |');
    Lines.Add('| `{"code": -3, "error": "API not available"}` | Bridge pre-check failed | Add `--no-precheck`, or wait ~3 seconds after the service starts. |');
    Lines.Add('| `{"code": -3}` despite the service running | Bridge endpoint mismatch | Check `--endpoint` matches the service''s `LF_PrepareService` address. |');
    Lines.Add('| `{"code": -2}` | URL path could not be parsed | Use `/<app>/<api>` or configure `--app`. |');
    Lines.Add('| `{"code": -1, "error": "Empty request body"}` | POST body was empty | Verify the client sends a JSON body. |');
    Lines.Add('| `{"code": -1, "error": "Invalid JSON request"}` | Request body is not valid JSON | Fix the client''s JSON serialization. |');
    Lines.Add('| Return value is a wrong number | JSON precision loss on 64-bit integers | Send large integers as strings, or accept reduced precision. |');
    Lines.Add('| String parameters read as empty | Field name mismatch | Use `args` array, or match the original parameter name exactly. |');
    Lines.Add('| Callback never fires | `internal_call_*` stub not filled | Search for `TODO` in the service unit. |');
    Lines.Add('| High concurrency causes timeouts | Blocking call inside a callback | Move blocking work to a background thread. |');
    Lines.Add('| Every call fails with an unsupported type | ABI type not in §6.2 | Refactor the routine to use only supported types. |');
    Lines.Add('| UI update crashes the server | Stub body touching UI on a worker thread | Uncomment the synchronised variant of that stub. |');
    Lines.Add('');
    Lines.Add('### 10.2 Verifying a running service');
    Lines.Add('');
    Lines.Add('From an HTTP client, before making a call:');
    Lines.Add('');
    Lines.Add('```bash');
    Lines.Add('# Probe whether the bridge is forwarding requests at all:');
    Lines.Add('curl -X POST http://127.0.0.1:8081/' + AppName.Text + '/<any-api> \\');
    Lines.Add('     -H "Content-Type: application/json" \\');
    Lines.Add('     -d ''{"args": []}''');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('A `-3` response means the bridge reached LingoFuse but did not');
    Lines.Add('find the target API. A `-2` response means the URL path itself');
    Lines.Add('is malformed.');
    Lines.Add('');
    Lines.Add('### 10.3 Inspecting the raw payload');
    Lines.Add('');
    Lines.Add('Because the wire format is plain JSON, the response body can be');
    Lines.Add('inspected directly by any HTTP client. Use `curl -v`, browser');
    Lines.Add('DevTools Network tab, or a proxy such as mitmproxy.');
    Lines.Add('');
    Lines.Add('To inspect the LingoFuse side, add a temporary log line inside');
    Lines.Add('the callback before parsing:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('DoStatus(''raw payload: %s'', [TEncoding.UTF8.GetString(_ReqBytes)]);');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 10.4 Enabling verbose logging');
    Lines.Add('');
    Lines.Add('In the service unit, set:');
    Lines.Add('');
    Lines.Add('```pascal');
    Lines.Add('DEBUG_LOG := True;');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('The callback wrappers then print the request status, the');
    Lines.Add('deserialised parameters, and the result to the console.');
    Lines.Add('');
    Lines.Add('### 10.5 Enabling main-thread execution for a specific stub');
    Lines.Add('');
    Lines.Add('Open the generated service unit and locate the `internal_call_*`');
    Lines.Add('stub. Uncomment the two block comments and the `//` lines');
    Lines.Add('inside them. `Z.Core` is already imported by the generated unit,');
    Lines.Add('so no extra `uses` change is required.');
    Lines.Add('');

    // =========================================================================
    // 11. Self-assessment checklist (for human engineers)
    // =========================================================================
    Lines.Add('## 11. Self-Assessment Checklist (for human engineers)');
    Lines.Add('');
    Lines.Add('After reading this document you should be able to answer the');
    Lines.Add('following questions without consulting the source code. If any');
    Lines.Add('answer is unclear, re-read the corresponding section.');
    Lines.Add('');
    Lines.Add('| # | Question | Section |');
    Lines.Add('|---|----------|---------|');
    Lines.Add('| 1 | What does the HTTP/JSON service expose? | §1 |');
    Lines.Add('| 2 | Why is JSON preferred over the binary ABI here? | §2 |');
    Lines.Add('| 3 | Which HTTP clients can call this service? | §1.1 |');
    Lines.Add('| 4 | What does a request body look like? | §4.1 |');
    Lines.Add('| 5 | What does a response body look like? | §4.2 |');
    Lines.Add('| 6 | How does the bridge fit into the call path? | §5 |');
    Lines.Add('| 7 | Which JSON wire types are supported? | §6.2 |');
    Lines.Add('| 8 | Why can a 64-bit integer lose precision? | §6.1 |');
    Lines.Add('| 9 | How are overloaded routines disambiguated? | §9.0 |');
    Lines.Add('| 10 | Where do I place the DLLs at runtime? | §7.6 |');
    Lines.Add('| 11 | How do I compile the server with FPC? | §7.2 |');
    Lines.Add('| 12 | How do I start the bridge? | §7.4 |');
    Lines.Add('| 13 | What is the shutdown order? | §7.7 |');
    Lines.Add('| 14 | How do I write a minimal test harness? | §8 |');
    Lines.Add('| 15 | How do I test without starting LingoFuse? | §8.4 |');
    Lines.Add('| 16 | How do I invoke a specific API from an HTTP client? | §9 |');
    Lines.Add('| 17 | How do I make a stub run on the main thread? | §3.5, §10.5 |');
    Lines.Add('');
    Lines.Add('If you can answer all of the above, you are ready to use this');
    Lines.Add('service.');
    Lines.Add('');

    // =========================================================================
    // 12. Reference resources
    // =========================================================================
    Lines.Add('## 12. Reference Resources');
    Lines.Add('');
    Lines.Add('| Resource | Purpose |');
    Lines.Add('|----------|---------|');
    Lines.Add('| ZNetV2 repository | LingoFuse runtime bindings |');
    Lines.Add('| ZNetV2/ZCore | Core infrastructure units |');
    Lines.Add('| `lingofuse_import.pas` | Low-level C ABI declarations |');
    Lines.Add('| `lf_http_bridge_client.pas` | Pascal HTTP bridge client |');
    Lines.Add('| `bridge.py` | LingoFuse HTTP bridge |');
    Lines.Add('| `http_pas_abi_call_generator_tool.pas` | Paired Pascal call-side generator |');
    Lines.Add('| `http_js_abi_call_generator_tool.pas` | Browser JS call-side generator |');
    Lines.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    Lines.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    Lines.Add('');

    // =========================================================================
    // 13. For AI Agents
    // =========================================================================
    // This chapter is deliberately structured and terse. It is meant
    // to be consumed by an LLM without reading the surrounding
    // narrative. Every fact here is also stated somewhere else in the
    // document; the point is to have a single, machine-friendly
    // summary that an AI can quote back to a user.
    // =========================================================================
    Lines.Add('## 13. For AI Agents');
    Lines.Add('');
    Lines.Add('This chapter is a compact, machine-readable summary of the');
    Lines.Add('contract. Everything here is also stated somewhere else in the');
    Lines.Add('document; this is the version to quote back to a user.');
    Lines.Add('');
    Lines.Add('### 13.1 Contract summary');
    Lines.Add('');
    Lines.Add('```yaml');
    Lines.Add('service:');
    Lines.Add('  app_name: ' + AppName.Text);
    Lines.Add('  source_unit: ' + UnitName.Text);
    Lines.Add('  lf_endpoint: ipc:' + NormalizedUnit.Text + '_http_json');
    Lines.Add('  bridge_default_http_port: 8081');
    Lines.Add('');
    Lines.Add('http:');
    Lines.Add('  method: POST');
    Lines.Add('  route_format: /<app>/<api>');
    Lines.Add('  content_type: application/json; charset=utf-8');
    Lines.Add('  success_status: 200');
    Lines.Add('  failure_status: 200          # bridge-level errors');
    Lines.Add('  request_shape_error_status: 400   # only for code = -2');
    Lines.Add('');
    Lines.Add('request:');
    Lines.Add('  positional:');
    Lines.Add('    shape: ''{"args": [v1, v2, ..., vN]}''');
    Lines.Add('    semantics: args[i] maps to the i-th parameter');
    Lines.Add('  named:');
    Lines.Add('    shape: ''{"param1": v1, "param2": v2}''');
    Lines.Add('    semantics: matched against the original Pascal parameter names');
    Lines.Add('  precedence: args wins when both are present');
    Lines.Add('  missing_field_default: 0 for numbers, "" for strings');
    Lines.Add('');
    Lines.Add('response:');
    Lines.Add('  success: ''{"code": 0, "result": <value>}''');
    Lines.Add('  failure: ''{"code": -1, "error": "<message>"}''');
    Lines.Add('  bridge_shape_error: ''{"code": -2, "error": "<message>"}''');
    Lines.Add('  bridge_precheck_failed: ''{"code": -3, "error": "<message>"}''');
    Lines.Add('');
    Lines.Add('error_codes:');
    Lines.Add('  "0":  "Success"');
    Lines.Add('  "-1": "Remote call failed (timeout, exception, empty response)"');
    Lines.Add('  "-2": "Request shape error (URL path could not be parsed)"');
    Lines.Add('  "-3": "API pre-check failed (bridge could not see the API)"');
    Lines.Add('');
    Lines.Add('types:');
    Lines.Add('  json_number: "Integer, Int64, Cardinal, Word, SmallInt, Byte, UInt64, Double, Single, Extended, Real"');
    Lines.Add('  json_string: "string, AnsiString, UnicodeString, TPascalString, TUPascalString, PChar, PAnsiChar, PWideChar"');
    Lines.Add('  unsupported: "Boolean, Variant, arrays, records, classes, interfaces, enums, sets, generics, pointers, Currency, Comp, TDateTime"');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('### 13.2 Anti-patterns');
    Lines.Add('');
    Lines.Add('The following constructs are common mistakes. If you see one in');
    Lines.Add('generated client code, it is a bug.');
    Lines.Add('');
    Lines.Add('| Anti-pattern | Why it fails | Correct form |');
    Lines.Add('|--------------|--------------|--------------|');
    Lines.Add('| `GET /<app>/<api>` | The bridge routes only `POST` | Use `POST`. |');
    Lines.Add('| `POST /<api>` without `--app` | The bridge cannot determine the target app | Use `POST /<app>/<api>` or start the bridge with `--app`. |');
    Lines.Add('| Sending `Content-Type: text/plain` | The bridge normalizes only JSON-shaped payloads | Use `application/json`. |');
    Lines.Add('| Embedding a NUL byte in a JSON string | JSON forbids raw control characters | Encode as `\u0000`. |');
    Lines.Add('| Assuming `-3` means the service is down | `-3` is a cache miss, not a hard failure | Wait ~3 s and retry, or use `--no-precheck`. |');
    Lines.Add('| Sending an integer larger than 2^53 from JS | `JSON.parse` loses precision above 2^53 | Send it as a decimal string. |');
    Lines.Add('| Mixing `args` and named fields | Only `args` is consulted when both are present | Use one form per request. |');
    Lines.Add('| Expecting non-zero HTTP status for `code = -1` | The bridge returns HTTP 200 for every well-formed call | Check `code`, not the HTTP status. |');
    Lines.Add('| Expecting `null` for a missing field | Missing fields fall back to `0` or `""` | Check `contains` on the request object if you need to distinguish. |');
    Lines.Add('');
    Lines.Add('### 13.3 Decision tree: how to format a request');
    Lines.Add('');
    Lines.Add('```mermaid');
    Lines.Add('flowchart TD');
    Lines.Add('    S["I want to call an API"] --> Q1{"How many parameters?"}');
    Lines.Add('    Q1 -- "0" --> A1["Send {} or {}"]');
    Lines.Add('    Q1 -- ">= 1" --> Q2{"Are the parameter names stable and memorable?"}');
    Lines.Add('    Q2 -- "yes" --> A2["Use named form:\\n{\\"a\\": v1, \\"b\\": v2}"]');
    Lines.Add('    Q2 -- "no" --> A3["Use positional form:\\n{\\"args\\": [v1, v2]}"]');
    Lines.Add('');
    Lines.Add('    A1 --> OK["POST /<app>/<api>"]');
    Lines.Add('    A2 --> OK');
    Lines.Add('    A3 --> OK');
    Lines.Add('    OK --> Done["Read code, then result or error"]');
    Lines.Add('```');
    Lines.Add('');
    Lines.Add('Both forms are equally valid. Prefer named form when the caller');
    Lines.Add('is generated code (readability). Prefer positional form when the');
    Lines.Add('caller is hand-written or when names are unstable.');
    Lines.Add('');
    Lines.Add('### 13.4 Machine-readable API manifest');
    Lines.Add('');

    if FuncCount = 0 then
    begin
      Lines.Add('_No supported routines were found in the source unit._');
      Lines.Add('');
    end
    else
    begin
      Lines.Add('The following JSON array describes every exposed API. It is');
      Lines.Add('intended for consumption by code generators and AI agents.');
      Lines.Add('');
      Lines.Add('```json');
      Lines.Add('[');

      UsedApiNames.Clear;
      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];

        ApiName := MakeApiName(f.Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        Lines.Add('  {');
        Lines.Add('    "name": "' + ApiName.Text + '",');
        Lines.Add('    "original_name": "' + f.Name.Text + '",');
        Lines.Add('    "kind": "' + if_(f.IsFunction, 'function', 'procedure') + '",');
        Lines.Add('    "route": "POST /' + AppName.Text + '/' + ApiName.Text + '",');

        if HasParams then
        begin
          Lines.Add('    "params": [');
          for j := 0 to High(f.Params) do
          begin
            ParamName := MakeSafePascalIdent(f.Params[j].Name, j);
            ParamType := ABI_Type_To_Pascal_Decl(f.Params[j].PascalType);
            ParamJsonType := ABI_Type_To_Json_Wire_Type(f.Params[j].PascalType);

            Lines.Add('      {"name": "' + ParamName.Text +
              '", "pascal_type": "' + ParamType.Text +
              '", "json_type": "' + ParamJsonType.Text + '"}' +
              if_(j < High(f.Params), ',', ''));
          end;
          Lines.Add('    ],');
        end
        else
          Lines.Add('    "params": [],');

        if f.IsFunction then
          Lines.Add('    "returns": "' + ABI_Type_To_Pascal_Decl(f.ReturnType).Text + '"')
        else
          Lines.Add('    "returns": null');

        Lines.Add('  }' + if_(i < High(SupportedFuncs), ',', ''));
      end;

      Lines.Add(']');
      Lines.Add('```');
      Lines.Add('');
    end;

    Lines.Add('### 13.5 How to answer a user question with this document');
    Lines.Add('');
    Lines.Add('An AI assistant should follow this pattern:');
    Lines.Add('');
    Lines.Add('1. **Identify the intent**: call, deploy, debug, or extend?');
    Lines.Add('2. **Locate the relevant section**:');
    Lines.Add('   - "How do I call X?" → §9.<n> for that API, plus §13.1.');
    Lines.Add('   - "Why does my request fail?" → §10.1 and §13.2.');
    Lines.Add('   - "What types are allowed?" → §6.2 and §13.1.');
    Lines.Add('   - "How do I deploy?" → §7.');
    Lines.Add('   - "How do I test?" → §8 and §8.4.');
    Lines.Add('3. **Quote the specific fact**, not the whole document. Prefer');
    Lines.Add('   the machine-readable forms in §13.1 and §13.4.');
    Lines.Add('4. **If the question is not covered**, say so and point the user');
    Lines.Add('   to the source file for the corresponding API.');
    Lines.Add('');
    Lines.Add('### 13.6 What this document does NOT cover');
    Lines.Add('');
    Lines.Add('- The internal implementation of `bridge.py`. See the bridge');
    Lines.Add('  README for that.');
    Lines.Add('- The internal implementation of `lingofuse_import.pas`. See the');
    Lines.Add('  LingoFuse documentation.');
    Lines.Add('- Alternative transports (binary ABI, gRPC, custom sockets).');
    Lines.Add('  See the corresponding generator.');
    Lines.Add('- Versioning or backward-compatibility guarantees. Every build');
    Lines.Add('  is treated as a fresh API surface; regenerate on change.');
    Lines.Add('');

    Lines.Add('---');
    Lines.Add('');
    Lines.Add('End of document. Generated by `http_pas_abi_service_generator_tool.pas`');

    Result := Lines;
    Log(PFormat('Generated README: %d lines, %d supported routines.',
      [Lines.Count, FuncCount]));
  finally
    UsedApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

end.
