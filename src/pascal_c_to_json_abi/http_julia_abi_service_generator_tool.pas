unit http_julia_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceJuliaCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_julia_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_julia_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification
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

function ABI_Type_To_Julia_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'Float64'
  else if ABI_Type_Is_Int(T) then
    Result := 'Int64'
  else
    Result := 'Any';
end;

function ABI_Type_To_Julia_Default(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := 'Int64(0)'
  else
    Result := 'nothing';
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

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function MakeSafeJuliaIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('abstract') or Result.Same('baremodule') or
    Result.Same('begin') or Result.Same('break') or Result.Same('catch') or
    Result.Same('const') or Result.Same('continue') or Result.Same('do') or
    Result.Same('else') or Result.Same('elseif') or Result.Same('end') or
    Result.Same('export') or Result.Same('false') or Result.Same('finally') or
    Result.Same('for') or Result.Same('function') or Result.Same('global') or
    Result.Same('if') or Result.Same('import') or Result.Same('in') or
    Result.Same('let') or Result.Same('local') or Result.Same('macro') or
    Result.Same('module') or Result.Same('quote') or Result.Same('return') or
    Result.Same('struct') or Result.Same('true') or Result.Same('try') or
    Result.Same('using') or Result.Same('while') then
    Result := Result + '_';
end;

function JuliaStrLit(const S: TP_String): TP_String;
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
      #92:  Result.Append('\\');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
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

function UniqueName(const Base: TP_String; Used: TPascalStringList): TP_String;
var
  i: integer;
begin
  if Used.IndexOf(Base) < 0 then
  begin
    Result := Base;
    Exit;
  end;
  i := 1;
  while Used.IndexOf(Base + '_' + umlIntToStr(i).Text) >= 0 do
    Inc(i);
  Result := Base + '_' + umlIntToStr(i).Text;
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

function BuildJuliaStubParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, typ: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaIdent(Params[i].Name, i);
    typ := ABI_Type_To_Julia_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n + '::' + typ;
  end;
end;

function BuildJuliaCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildJuliaParamNameArray - produce a Julia expression for the
// parameter-name array constant.
//
// For routines with NO parameters, return the explicitly typed
// literal "String[]". A bare "[]" would be inferred by Julia as
// Vector{Any} and would fail to match the
// param_names::Vector{String} parameter of _make_call_handler.
function BuildJuliaParamNameArray(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := 'String[]';
    Exit;
  end;

  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeJuliaIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + '"' + n.Text + '"';
  end;
  Result := Result + ']';
end;

function BuildJuliaDefaultArray(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := 'Any[';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Julia_Default(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
  Result := Result + ']';
end;

function BuildJuliaTypeArray(const Params: TParamArray): TP_String;
var
  i: integer;
  t: TP_String;
begin
  Result := 'DataType[';
  for i := 0 to High(Params) do
  begin
    t := ABI_Type_To_Julia_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + t;
  end;
  Result := Result + ']';
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeJuliaIdent(F.Params[i].Name, i);
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

// =============================================================================
// MODULE HEADER EMITTER
// =============================================================================

procedure EmitJuliaModuleHeader(Lines: TPascalStringList;
  const UnitName, NormalizedUnit, ModuleName, AppName, Endpoint: TP_String);
begin
  Lines.Add('# ' + NormalizedUnit.Text + '_http_json_service.jl');
  Lines.Add('#');
  Lines.Add('# Auto-generated by http_julia_abi_service_generator_tool.pas.');
  Lines.Add('# Source model unit: ' + UnitName.Text + '.');
  Lines.Add('# Do not edit by hand unless you know what you are doing.');
  Lines.Add('#');
  Lines.Add('# Service-side Julia module for the LingoFuse HTTP/JSON service');
  Lines.Add('# that was generated from the same source unit.');
  Lines.Add('#');
  Lines.Add('# DEPLOYMENT MODEL');
  Lines.Add('# ----------------');
  Lines.Add('# This module owns the LingoFuse mesh endpoint via prepare_service,');
  Lines.Add('# then joins it as a CLIENT via prepare_client. The HTTP port');
  Lines.Add('# (default 8081) is owned by bridge.py, which joins the same mesh.');
  Lines.Add('#');
  Lines.Add('#   HTTP client -> bridge.py (:8081) -> LingoFuse mesh -> this module');
  Lines.Add('#');
  Lines.Add('# bridge.py MAY be started before or after this service; both are');
  Lines.Add('# equally valid. The service creates the mesh; bridge.py joins it.');
  Lines.Add('#');
  Lines.Add('# PREREQUISITES');
  Lines.Add('# -------------');
  Lines.Add('# 1. Launch Julia with --threads=2 or more.');
  Lines.Add('# 2. bridge.py must eventually join the same mesh endpoint for');
  Lines.Add('#    HTTP clients to reach this service.');
  Lines.Add('# 3. Fill in every internal_call_<api> stub before starting the');
  Lines.Add('#    service. Unfilled stubs return type defaults.');
  Lines.Add('');
  Lines.Add('module ' + ModuleName.Text);
  Lines.Add('');
  Lines.Add('using LingoFuse');
  Lines.Add('import JSON3');
  Lines.Add('import LingoFuse: App, register_call!, reset_prepare,');
  Lines.Add('                 prepare_service, prepare_client, prepare_done,');
  Lines.Add('                 exit_main_thread, shutdown, dispose!, set_option');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Configuration');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('const HTTP_SERVICE_APP_NAME::String = ' + JuliaStrLit(AppName).Text);
  Lines.Add('const HTTP_SERVICE_APP_DESC::String = ' +
    JuliaStrLit('HTTP/JSON service for ' + UnitName).Text);
  Lines.Add('const HTTP_SERVICE_ENDPOINT::String = ' + JuliaStrLit(Endpoint).Text);
  Lines.Add('');
  Lines.Add('# Set to true to print per-call diagnostics on stderr.');
  Lines.Add('const DEBUG_LOG::Bool = false');
  Lines.Add('');
  Lines.Add('');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('# Internal call stubs');
  Lines.Add('#');
  Lines.Add('# Each stub mirrors one original routine. Replace the body with a');
  Lines.Add('# call to the real implementation, for example:');
  Lines.Add('#');
  Lines.Add('#     return MyModule.Add(a, b)');
  Lines.Add('#');
  Lines.Add('# The parameter names and type annotations are already correct.');
  Lines.Add('# ----------------------------------------------------------------------');
  Lines.Add('');
end;

// =============================================================================
// PER-API EMITTERS
// =============================================================================

procedure EmitJuliaStub(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName, StubName: TP_String);
var
  ParamList, CallArgs: TP_String;
  RetType: TP_String;
  Description: TP_String;
begin
  ParamList := BuildJuliaStubParamList(F.Params);
  CallArgs := BuildJuliaCallArgList(F.Params);
  Description := GetFullDescription(F.Comment);

  if F.IsFunction then
    RetType := ABI_Type_To_Julia_Type(F.ReturnType)
  else
    RetType := 'Nothing';

  Lines.Add('# ' + Description.Text);
  Lines.Add('function ' + StubName.Text + '(' + ParamList.Text + ')::' + RetType.Text);
  Lines.Add('    # TODO: implement this stub.');
  if Length(F.Params) > 0 then
    Lines.Add('    # Suggested call: ' + F.Name.Text + '(' + CallArgs.Text + ')')
  else
    Lines.Add('    # Suggested call: ' + F.Name.Text + '()');
  if F.IsFunction then
    Lines.Add('    return ' + ABI_Type_To_Julia_Default(F.ReturnType))
  else
    Lines.Add('    return nothing');
  Lines.Add('end');
  Lines.Add('');
  Lines.Add('');
end;

procedure EmitJuliaParamTables(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName, StubName: TP_String);
var
  NameArr, DefaultArr, TypeArr: TP_String;
begin
  NameArr := BuildJuliaParamNameArray(F.Params);
  DefaultArr := BuildJuliaDefaultArray(F.Params);
  TypeArr := BuildJuliaTypeArray(F.Params);

  Lines.Add('const _PARAM_NAMES_' + StubName.Text + ' = ' + NameArr.Text);
  Lines.Add('const _DEFAULTS_' + StubName.Text + ' = ' + DefaultArr.Text);
  Lines.Add('const _PARAM_TYPES_' + StubName.Text + ' = ' + TypeArr.Text);
  Lines.Add('');
end;

procedure EmitJuliaRegistration(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName, StubName: TP_String);
var
  Description: TP_String;
begin
  Description := GetFullDescription(F.Comment);
  if Description.Len = 0 then
    Description := 'HTTP/JSON api for ' + F.Name;

  Lines.Add('    if !register_call!(app, ' + JuliaStrLit(ApiName).Text + ', ' +
    JuliaStrLit(Description).Text + ',');
  Lines.Add('                       _make_call_handler(' + JuliaStrLit(ApiName).Text + ', ' +
    StubName.Text + ',');
  Lines.Add('                                          _PARAM_NAMES_' + StubName.Text + ',');
  Lines.Add('                                          _DEFAULTS_' + StubName.Text + ',');
  Lines.Add('                                          _PARAM_TYPES_' + StubName.Text + ');');
  Lines.Add('                       warmup=true)');
  Lines.Add('        println(stderr, "[WARN] Failed to register API ", ' +
    JuliaStrLit(ApiName).Text + ')');
  Lines.Add('    end');
end;

// =============================================================================
// PUBLIC: GenerateHTTPServiceJuliaCode
// =============================================================================

function GenerateHTTPServiceJuliaCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName, Endpoint: TP_String;
  UsedStubNames, StubNames: TPascalStringList;
  StubName, ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceJuliaCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceJuliaCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := NormalizedUnit + 'HttpJsonService';
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  SupportedFuncs := CollectSupportedFunctions(Model);

  UsedStubNames := TPascalStringList.Create;
  StubNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      StubName := UniqueName(MakeSafeJuliaIdent(ApiName, i), UsedStubNames);
      UsedStubNames.Add(StubName);
      StubNames.Add(StubName);
    end;

    EmitJuliaModuleHeader(Lines, UnitName, NormalizedUnit, ModuleName, AppName, Endpoint);

    for i := 0 to High(SupportedFuncs) do
      EmitJuliaStub(Lines, SupportedFuncs[i],
        MakeApiName(SupportedFuncs[i].Name), StubNames[i]);

    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Request / response helpers');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('# Read a JSON request object from the input bytes.');
    Lines.Add('#');
    Lines.Add('# The LingoFuse Julia binding delivers the input as a Vector{UInt8}');
    Lines.Add('# (the raw bytes of the request payload, possibly with a trailing');
    Lines.Add('# NUL byte). This helper decodes them and parses them as a JSON');
    Lines.Add('# object.');
    Lines.Add('#');
    Lines.Add('# Contract:');
    Lines.Add('#   * Empty buffer           -> ArgumentError');
    Lines.Add('#   * Invalid UTF-8 / JSON   -> exception from JSON3');
    Lines.Add('#   * Valid JSON, not object -> exception from JSON3');
    Lines.Add('#');
    Lines.Add('# Exceptions propagate to _make_call_handler, which converts them');
    Lines.Add('# into {"code": -1, "error": "..."} responses.');
    Lines.Add('function _read_request(in_bytes::Vector{UInt8})::Dict{String,Any}');
    Lines.Add('    if isempty(in_bytes)');
    Lines.Add('        throw(ArgumentError("Empty request body"))');
    Lines.Add('    end');
    Lines.Add('    text = String(copy(in_bytes))');
    Lines.Add('    text = rstrip(text, Char(0))');
    Lines.Add('    if isempty(text)');
    Lines.Add('        throw(ArgumentError("Empty request body"))');
    Lines.Add('    end');
    Lines.Add('    return JSON3.read(text, Dict{String,Any})');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# Coerce one argument to its declared type.');
    Lines.Add('#');
    Lines.Add('# Rejects a floating-point JSON value when the declared type is');
    Lines.Add('# integral. Silent truncation (3.7 -> 3) across a public API boundary');
    Lines.Add('# is almost never what the caller intended, so it is forbidden.');
    Lines.Add('function _coerce_arg(value, ::Type{T}, name::String)::T where {T}');
    Lines.Add('    if T <: Integer && value isa AbstractFloat');
    Lines.Add('        throw(ArgumentError("Argument ''" * name *');
    Lines.Add('                            "'' expects an integer, " *');
    Lines.Add('                            "but received a floating-point number"))');
    Lines.Add('    end');
    Lines.Add('    try');
    Lines.Add('        return convert(T, value)::T');
    Lines.Add('    catch e');
    Lines.Add('        throw(ArgumentError("Argument ''" * name *');
    Lines.Add('                            "'' cannot be converted to " *');
    Lines.Add('                            string(T) * ": " * string(e)))');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# Extract positional or keyword arguments from the request.');
    Lines.Add('#');
    Lines.Add('# If the request contains "args", it is treated as a JSON array of');
    Lines.Add('# positional arguments. Otherwise, every parameter is looked up by');
    Lines.Add('# name. Missing or null values fall back to the corresponding entry');
    Lines.Add('# in defaults.');
    Lines.Add('function _extract_args(req::Dict{String,Any},');
    Lines.Add('                       param_names::Vector{String},');
    Lines.Add('                       defaults::Vector{Any},');
    Lines.Add('                       param_types::Vector{DataType})::Vector{Any}');
    Lines.Add('    n = length(param_names)');
    Lines.Add('    args = Vector{Any}(undef, n)');
    Lines.Add('    for i in 1:n');
    Lines.Add('        args[i] = defaults[i]');
    Lines.Add('    end');
    Lines.Add('    if haskey(req, "args") && req["args"] isa Vector');
    Lines.Add('        arr = req["args"]');
    Lines.Add('        for i in 1:n');
    Lines.Add('            if i <= length(arr) && arr[i] !== nothing');
    Lines.Add('                args[i] = _coerce_arg(arr[i], param_types[i], param_names[i])');
    Lines.Add('            end');
    Lines.Add('        end');
    Lines.Add('    else');
    Lines.Add('        for i in 1:n');
    Lines.Add('            name = param_names[i]');
    Lines.Add('            if haskey(req, name) && req[name] !== nothing');
    Lines.Add('                args[i] = _coerce_arg(req[name], param_types[i], name)');
    Lines.Add('            end');
    Lines.Add('        end');
    Lines.Add('    end');
    Lines.Add('    return args');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# Serialize a success response: {"code": 0, "result": <result>}.');
    Lines.Add('function _serialize_success(result)::Vector{UInt8}');
    Lines.Add('    resp = Dict{String,Any}("code" => 0, "result" => result)');
    Lines.Add('    return Vector{UInt8}(codeunits(JSON3.write(resp)))');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# Serialize an error response: {"code": -1, "error": "<msg>"}.');
    Lines.Add('function _serialize_error(msg::String)::Vector{UInt8}');
    Lines.Add('    resp = Dict{String,Any}("code" => -1, "error" => msg)');
    Lines.Add('    return Vector{UInt8}(codeunits(JSON3.write(resp)))');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# Build a LingoFuse call handler for one API.');
    Lines.Add('#');
    Lines.Add('# The LingoFuse Julia binding expects a callback of type');
    Lines.Add('#     Function(Vector{UInt8}) -> Vector{UInt8}.');
    Lines.Add('# The handler parses the request, dispatches to the stub, and');
    Lines.Add('# serializes the response. Every exception is caught and converted');
    Lines.Add('# into a {"code": -1, "error": "..."} response.');
    Lines.Add('#');
    Lines.Add('# NOTE: the inner function is an ANONYMOUS function. Julia does not');
    Lines.Add('# allow return-type annotations on anonymous functions, so the');
    Lines.Add('# inner function has no ::Vector{UInt8} suffix. The outer function');
    Lines.Add('# annotation ::Function supplies the type contract.');
    Lines.Add('function _make_call_handler(api_name::String, stub::Function,');
    Lines.Add('                            param_names::Vector{String},');
    Lines.Add('                            defaults::Vector{Any},');
    Lines.Add('                            param_types::Vector{DataType})::Function');
    Lines.Add('    return function(in_bytes::Vector{UInt8})');
    Lines.Add('        try');
    Lines.Add('            req = _read_request(in_bytes)');
    Lines.Add('            args = _extract_args(req, param_names, defaults, param_types)');
    Lines.Add('            result = stub(args...)');
    Lines.Add('            return _serialize_success(result)');
    Lines.Add('        catch e');
    Lines.Add('            if DEBUG_LOG');
    Lines.Add('                println(stderr, "[DEBUG] ", api_name, ": ", string(e))');
    Lines.Add('            end');
    Lines.Add('            return _serialize_error(string(e))');
    Lines.Add('        end');
    Lines.Add('    end');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Per-API parameter tables');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      EmitJuliaParamTables(Lines, SupportedFuncs[i],
        MakeApiName(SupportedFuncs[i].Name), StubNames[i]);

    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Registration');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('function register_all_http_json_apis(app::App)::Nothing');

    for i := 0 to High(SupportedFuncs) do
      EmitJuliaRegistration(Lines, SupportedFuncs[i],
        MakeApiName(SupportedFuncs[i].Name), StubNames[i]);

    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Signal handling');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('const _STOP_REQUESTED = Ref{Bool}(false)');
    Lines.Add('');
    Lines.Add('# Wait for SIGINT (Ctrl+C). Julia translates SIGINT into an');
    Lines.Add('# InterruptException at the next yield point; we catch it here and');
    Lines.Add('# set the stop flag. SIGTERM is not handled by this loop; the');
    Lines.Add('# operator should use Ctrl+C or `kill -INT`.');
    Lines.Add('function _wait_for_signal()::Nothing');
    Lines.Add('    try');
    Lines.Add('        while !_STOP_REQUESTED[]');
    Lines.Add('            sleep(0.5)');
    Lines.Add('        end');
    Lines.Add('    catch e');
    Lines.Add('        if e isa InterruptException');
    Lines.Add('            _STOP_REQUESTED[] = true');
    Lines.Add('        else');
    Lines.Add('            rethrow()');
    Lines.Add('        end');
    Lines.Add('    end');
    Lines.Add('    return nothing');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('# Entry point');
    Lines.Add('# ----------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('# Start the service and block until SIGINT.');
    Lines.Add('#');
    Lines.Add('# Returns:');
    Lines.Add('#   0  clean run');
    Lines.Add('#   1  startup failure');
    Lines.Add('#');
    Lines.Add('# Startup sequence:');
    Lines.Add('#   1. set_option("Wait_Connection_ReadyOk", "False")');
    Lines.Add('#   2. reset_prepare()');
    Lines.Add('#   3. prepare_service(ENDPOINT, ENDPOINT)    <-- OWN the mesh');
    Lines.Add('#   4. App(APP_NAME, APP_DESC)');
    Lines.Add('#   5. register_all_http_json_apis(app)');
    Lines.Add('#   6. prepare_client(ENDPOINT, app)          <-- JOIN the mesh');
    Lines.Add('#   7. prepare_done()');
    Lines.Add('#   8. wait for SIGINT');
    Lines.Add('#   9. exit_main_thread()');
    Lines.Add('#  10. dispose!(app) / shutdown()');
    Lines.Add('#');
    Lines.Add('# Why prepare_service AND prepare_client: the service owns the mesh');
    Lines.Add('# endpoint (prepare_service) so that bridge.py can join it later,');
    Lines.Add('# and also joins the mesh as a client (prepare_client) so that the');
    Lines.Add('# framework can route inbound calls to the registered APIs.');
    Lines.Add('function run_service()::Int32');
    Lines.Add('    set_option("Wait_Connection_ReadyOk", "False")');
    Lines.Add('    reset_prepare()');
    Lines.Add('');
    Lines.Add('    serv_ret = prepare_service(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT)');
    Lines.Add('    if serv_ret == -1');
    Lines.Add('        println(stderr, "[ERROR] prepare_service returned -1 for endpoint "');
    Lines.Add('                * HTTP_SERVICE_ENDPOINT');
    Lines.Add('                * ". Address may already be in use by another service.")');
    Lines.Add('        return Int32(1)');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    app = App(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)');
    Lines.Add('    try');
    Lines.Add('        register_all_http_json_apis(app)');
    Lines.Add('');
    Lines.Add('        client_ret = prepare_client(HTTP_SERVICE_ENDPOINT, app)');
    Lines.Add('        if client_ret == -1');
    Lines.Add('            println(stderr, "[ERROR] prepare_client returned -1 for endpoint "');
    Lines.Add('                    * HTTP_SERVICE_ENDPOINT');
    Lines.Add('                    * ". Address may already be in use or invalid.")');
    Lines.Add('            return Int32(1)');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        if prepare_done() != 1');
    Lines.Add('            println(stderr, "[ERROR] prepare_done failed")');
    Lines.Add('            return Int32(1)');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        println("[OK] Service ready. Press Ctrl+C to stop.")');
    Lines.Add('        Base.exit_on_sigint(false)');
    Lines.Add('        try');
    Lines.Add('            _wait_for_signal()');
    Lines.Add('        finally');
    Lines.Add('            Base.exit_on_sigint(true)');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        exit_main_thread()');
    Lines.Add('        println("[OK] Service stopped.")');
    Lines.Add('    finally');
    Lines.Add('        dispose!(app)');
    Lines.Add('        shutdown()');
    Lines.Add('    end');
    Lines.Add('    return Int32(0)');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('function main()::Int32');
    Lines.Add('    return run_service()');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('');
    Lines.Add('if abspath(PROGRAM_FILE) == @__FILE__');
    Lines.Add('    exit(main())');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('end # module ' + ModuleName.Text);

    Result := Lines;
    Log(PFormat('Generated Julia service module: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    UsedStubNames.Free;
    StubNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'julia', 'Julia HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.jl', False,
    @GenerateHTTPServiceJuliaCode);
end.
