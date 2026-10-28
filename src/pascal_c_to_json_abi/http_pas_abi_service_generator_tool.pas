unit http_pas_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServicePascalCode - main entry point for the service unit.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;

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

initialization
  RegisterCodeGenEntry(
    'pascal', 'Pascal HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service_unit.pas', False,
    @GenerateHTTPServicePascalCode);
end.
