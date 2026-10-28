unit http_pas_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallPascalCode - main entry point for the call unit.
//
// Model must be built with Typ_Normalize_Func = tnf_ABI. The returned
// list is owned by the caller and must be released with DisposeObject.
function GenerateHTTPCallPascalCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_pas_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// ---------------------------------------------------------------------------
// ABI type family classification
// ---------------------------------------------------------------------------

function ABI_Type_Is_String(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring')
    or T.Same('tpascalstring') or T.Same('tupascalstring') or T.Same('tp_string')
    or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_Is_Float(const T: TP_String): boolean;
begin
  Result := T.Same('double') or T.Same('single') or T.Same('extended')
    or T.Same('real');
end;

function ABI_Type_Is_Int(const T: TP_String): boolean;
begin
  Result := T.Same('integer') or T.Same('int64') or T.Same('cardinal')
    or T.Same('longint') or T.Same('dword') or T.Same('word')
    or T.Same('smallint') or T.Same('byte') or T.Same('uint64')
    or T.Same('longword');
end;

function ABI_Type_Is_Supported(const T: TP_String): boolean;
begin
  Result := ABI_Type_Is_String(T) or ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T);
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

// ABI_Type_To_Json_Serialize_Stmt - one statement that appends a typed
// parameter to the current request body "args" array.
function ABI_Type_To_Json_Serialize_Stmt(const ParamName, T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '_LFB_RemoteBody.A[''args''].Add(string(' + ParamName + '));'
  else if ABI_Type_Is_Float(T) then
    Result := '_LFB_RemoteBody.A[''args''].AddF(Double(' + ParamName + '));'
  else
    Result := '_LFB_RemoteBody.A[''args''].Add(Int64(' + ParamName + '));';
end;

// ABI_Type_To_Json_Deserialize_Expr - expression that reads body.result
// and converts it to the declared return type.
function ABI_Type_To_Json_Deserialize_Expr(const T: TP_String): TP_String;
var
  Decl: TP_String;
begin
  Decl := ABI_Type_To_Pascal_Decl(T);
  if ABI_Type_Is_String(T) then
    Result := '_LFB_BodyJo.S[''result'']'
  else if ABI_Type_Is_Float(T) then
    Result := Decl + '(_LFB_BodyJo.F[''result''])'
  else
    Result := Decl + '(_LFB_BodyJo.L[''result''])';
end;

// ABI_Type_To_Json_Deserialize_Assign - assignment statement that reads
// body.result into the local _LFB_ResultValue variable.
function ABI_Type_To_Json_Deserialize_Assign(const T: TP_String): TP_String;
var
  Decl: TP_String;
begin
  Decl := ABI_Type_To_Pascal_Decl(T);
  if ABI_Type_Is_String(T) then
    Result := '_LFB_ResultValue := _LFB_BodyJo.S[''result''];'
  else if ABI_Type_Is_Float(T) then
    Result := '_LFB_ResultValue := ' + Decl + '(_LFB_BodyJo.F[''result'']);'
  else
    Result := '_LFB_ResultValue := ' + Decl + '(_LFB_BodyJo.L[''result'']);';
end;

// ---------------------------------------------------------------------------
// Identifier helpers
// ---------------------------------------------------------------------------

// MakeApiName - canonicalize a routine name into an identifier safe as a
// URL path segment, a JSON key, and a Pascal/C#/C++/Python identifier.
function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))
      or ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;
  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

// UniqueName - return a name not yet present in Used, appending _1, _2, ...
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

// PascalStrLit - emit a Pascal string literal (with quotes) from S.
function PascalStrLit(const S: TP_String): TP_String;
begin
  Result := TTextParsing.Translate_Text_To_Pascal_Decl(S);
end;

// ---------------------------------------------------------------------------
// Comment description extraction (kept in sync with the service generator)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Parameter list builders
// ---------------------------------------------------------------------------

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, decl: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafePascalIdent(Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(Params[i].PascalType);
    if i > 0 then Result := Result + '; ';
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
    if i > 0 then Result := Result + ', ';
    Result := Result + n;
  end;
end;

// BuildFullDecl - "function Add(a: Int64; b: Int64): Int64;" or
// "procedure Log(s: string);", using the original Pascal name.
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

// ---------------------------------------------------------------------------
// Supported-function filtering
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Emit helpers
// ---------------------------------------------------------------------------

procedure EmitUnitHeader(Lines: TPascalStringList;
  const UnitName, NormalizedUnit: TP_String);
begin
  Lines.Add('unit ' + NormalizedUnit + '_http_json_call_unit;');
  Lines.Add('');
  Lines.Add('// Auto-generated by http_pas_abi_call_generator_tool.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// This unit is the call-side counterpart of the service unit');
  Lines.Add('// produced by http_pas_abi_service_generator_tool. It provides');
  Lines.Add('// three call functions per supported routine:');
  Lines.Add('//   * Sync    : ApiName(...)                     blocking');
  Lines.Add('//   * AsyncM  : ApiName_Async(..., OnSuccess_M, OnError_M)');
  Lines.Add('//   * AsyncP  : ApiName_Async_P(..., OnSuccess_P, OnError_P)');
  Lines.Add('//');
  Lines.Add('// All three route through the fixed bridge application');
  Lines.Add('// (LFBridgeAppName). UID and P2PName addressing are deliberately');
  Lines.Add('// not generated: the HTTP bridge exposes a single outbound proxy,');
  Lines.Add('// so the bridge App name is the only routing key on this side.');
  Lines.Add('//');
  Lines.Add('// Sync functions raise EHTTPCallError on failure.');
  Lines.Add('// Async functions return True on successful *submission*; the');
  Lines.Add('// actual outcome is delivered through the callbacks, which run');
  Lines.Add('// on a TCompute worker thread.');
  Lines.Add('');
  Lines.Add('{$ifdef FPC}');
  Lines.Add('  {$mode delphi}{$H+}');
  Lines.Add('  {$MODESWITCH NestedProcVars}');
  Lines.Add('  {$modeswitch advancedrecords}');
  Lines.Add('  {$CODEPAGE UTF8}');
  Lines.Add('{$endif}');
  Lines.Add('{$R-}{$I-}{$Q-}{$B-}');
  Lines.Add('');
  Lines.Add('interface');
  Lines.Add('');
  Lines.Add('uses');
  Lines.Add('  SysUtils,');
  Lines.Add('  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib,');
  Lines.Add('  Z.Json,');
  Lines.Add('  lingofuse_import,');
  Lines.Add('  lf_http_bridge_client;');
  Lines.Add('');
end;

procedure EmitTypeSection(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName: TP_String;
  RetType: TP_String;
begin
  Lines.Add('type');
  Lines.Add('  EHTTPCallError = class(Exception);');
  Lines.Add('');
  Lines.Add('  // Shared error callback types. Every async call takes one of');
  Lines.Add('  // these; the ErrorMsg is an English description, and Code is');
  Lines.Add('  // one of: -1 transport, -4 bridge protocol, >0/<0 service code.');
  Lines.Add('  TCallError_M = procedure(const ErrorMsg: string; Code: Integer) of object;');
  Lines.Add('{$IFDEF FPC}');
  Lines.Add('  TCallError_P = procedure(const ErrorMsg: string; Code: Integer) is nested;');
  Lines.Add('{$ELSE}');
  Lines.Add('  TCallError_P = reference to procedure(const ErrorMsg: string; Code: Integer);');
  Lines.Add('{$ENDIF}');
  Lines.Add('');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    if F.IsFunction then
    begin
      RetType := ABI_Type_To_Pascal_Decl(F.ReturnType);
      Lines.Add('  // Success callback for ' + ApiName + '.');
      Lines.Add('  T' + ApiName + '_Success_M = procedure(const Result_: ' + RetType + ') of object;');
      Lines.Add('{$IFDEF FPC}');
      Lines.Add('  T' + ApiName + '_Success_P = procedure(const Result_: ' + RetType + ') is nested;');
      Lines.Add('{$ELSE}');
      Lines.Add('  T' + ApiName + '_Success_P = reference to procedure(const Result_: ' + RetType + ');');
      Lines.Add('{$ENDIF}');
    end
    else
    begin
      Lines.Add('  // Success callback for ' + ApiName + ' (procedure, no result).');
      Lines.Add('  T' + ApiName + '_Success_M = procedure() of object;');
      Lines.Add('{$IFDEF FPC}');
      Lines.Add('  T' + ApiName + '_Success_P = procedure() is nested;');
      Lines.Add('{$ELSE}');
      Lines.Add('  T' + ApiName + '_Success_P = reference to procedure();');
      Lines.Add('{$ENDIF}');
    end;
    Lines.Add('');
    // Per-API async context class (forward-declared here so that every
    // cdecl callback emitted later can reference its own context type).
    Lines.Add('  T' + ApiName + '_AsyncCtx = class');
    Lines.Add('  public');
    Lines.Add('    OnSuccess_M: T' + ApiName + '_Success_M;');
    Lines.Add('    OnSuccess_P: T' + ApiName + '_Success_P;');
    Lines.Add('    OnError_M: TCallError_M;');
    Lines.Add('    OnError_P: TCallError_P;');
    Lines.Add('  end;');
    Lines.Add('');
  end;
end;

procedure EmitVarSection(Lines: TPascalStringList; const DefaultBaseUrl: TP_String);
begin
  Lines.Add('var');
  Lines.Add('  // Base URL prefix of the target service. The full URL for');
  Lines.Add('  // API "X" is HTTP_CALL_BASE_URL + "/" + "X".');
  Lines.Add('  //');
  Lines.Add('  // The default points at the local bridge, with the source');
  Lines.Add('  // unit''s name as the target application.');
  Lines.Add('  HTTP_CALL_BASE_URL: string = ' + PascalStrLit(DefaultBaseUrl) + ';');
  Lines.Add('');
end;

// BuildAsyncHeader_M - prototype for the object-method async variant.
function BuildAsyncHeader_M(const F: TFunctionStructure;
  const ApiName, Suffix: TP_String): TP_String;
var
  ParamDecl, Combined: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(F.Params);
  if ParamDecl <> '' then
    Combined := ParamDecl + '; '
  else
    Combined := '';
  Result := 'function ' + ApiName + Suffix + '(' + Combined +
    'OnSuccess: T' + ApiName + '_Success_M; ' +
    'OnError: TCallError_M): Boolean; overload;';
end;

// BuildAsyncHeader_P - prototype for the nested/anonymous async variant.
function BuildAsyncHeader_P(const F: TFunctionStructure;
  const ApiName, Suffix: TP_String): TP_String;
var
  ParamDecl, Combined: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(F.Params);
  if ParamDecl <> '' then
    Combined := ParamDecl + '; '
  else
    Combined := '';
  Result := 'function ' + ApiName + Suffix + '(' + Combined +
    'OnSuccess: T' + ApiName + '_Success_P; ' +
    'OnError: TCallError_P): Boolean; overload;';
end;

procedure EmitInterfaceFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, RetType: TP_String;
begin
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildTypedParamDecl(F.Params);
    RetType := ABI_Type_To_Pascal_Decl(F.ReturnType);

    Lines.Add('// ============================================================');
    Lines.Add('// ' + ApiName + ' - ' + BuildFullDecl(F));
    Lines.Add('// ============================================================');

    // ---- Sync ----
    if F.IsFunction then
      Lines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetType + '; overload;')
    else
      Lines.Add('procedure ' + ApiName + '(' + ParamDecl + '); overload;');
    Lines.Add('');

    // ---- Async M ----
    Lines.Add(BuildAsyncHeader_M(F, ApiName, '_Async'));
    Lines.Add('');

    // ---- Async P ----
    Lines.Add(BuildAsyncHeader_P(F, ApiName, '_Async_P'));
    Lines.Add('');
  end;
end;

procedure EmitHelpers(Lines: TPascalStringList);
begin
  Lines.Add('{$Region ''_LFB_helpers_''}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Internal helpers shared by every generated function.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');

  Lines.Add('function _LFB_BuildOuterEnvelope(const _LFB_Url, _LFB_RemoteBodyJson: string;');
  Lines.Add('  _LFB_HttpTimeoutSec: Double): string;');
  Lines.Add('begin');
  Lines.Add('  Result := ''{"url":"'' + _LFB_Url + ''","method":"POST"'';');
  Lines.Add('  if _LFB_RemoteBodyJson <> '''' then');
  Lines.Add('    Result := Result + '', "body":'' + _LFB_RemoteBodyJson;');
  Lines.Add('  Result := Result + '', "timeout":'' + IntToStr(Round(_LFB_HttpTimeoutSec)) + ''}'';');
  Lines.Add('end;');
  Lines.Add('');

  Lines.Add('function _LFB_ParseBridgeEnvelope(const _LFB_RespJson: string;');
  Lines.Add('  out _LFB_Resp: TZ_JsonObject; out _LFB_ErrMsg: string): Boolean;');
  Lines.Add('begin');
  Lines.Add('  Result := False;');
  Lines.Add('  _LFB_Resp := nil;');
  Lines.Add('  _LFB_ErrMsg := '''';');
  Lines.Add('  if _LFB_RespJson = '''' then');
  Lines.Add('  begin');
  Lines.Add('    _LFB_ErrMsg := ''Empty bridge response'';');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  _LFB_Resp := TZ_JsonObject.Create;');
  Lines.Add('  try');
  Lines.Add('    if not _LFB_Resp.ParseText(_LFB_RespJson) then');
  Lines.Add('    begin');
  Lines.Add('      _LFB_ErrMsg := ''Failed to parse bridge response JSON'';');
  Lines.Add('      FreeAndNil(_LFB_Resp);');
  Lines.Add('      Exit;');
  Lines.Add('    end;');
  Lines.Add('    if _LFB_Resp.Exists(''error'') then');
  Lines.Add('    begin');
  Lines.Add('      _LFB_ErrMsg := _LFB_Resp.S[''error''];');
  Lines.Add('      FreeAndNil(_LFB_Resp);');
  Lines.Add('      Exit;');
  Lines.Add('    end;');
  Lines.Add('  except');
  Lines.Add('    FreeAndNil(_LFB_Resp);');
  Lines.Add('    _LFB_ErrMsg := ''Exception parsing bridge response JSON'';');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  Result := True;');
  Lines.Add('end;');
  Lines.Add('');

  Lines.Add('function _LFB_CheckServiceCode(_LFB_BodyJo: TZ_JsonObject;');
  Lines.Add('  out _LFB_Code: Integer; out _LFB_ErrMsg: string): Boolean;');
  Lines.Add('var');
  Lines.Add('  _LFB_Tmp: string;');
  Lines.Add('begin');
  Lines.Add('  Result := False;');
  Lines.Add('  _LFB_Code := -1;');
  Lines.Add('  _LFB_ErrMsg := '''';');
  Lines.Add('  if _LFB_BodyJo = nil then');
  Lines.Add('  begin');
  Lines.Add('    _LFB_ErrMsg := ''Service body is nil'';');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  if not _LFB_BodyJo.Exists(''code'') then');
  Lines.Add('  begin');
  Lines.Add('    _LFB_ErrMsg := ''Service response has no "code" field'';');
  Lines.Add('    _LFB_Code := -4;');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  _LFB_Code := _LFB_BodyJo.I[''code''];');
  Lines.Add('  if _LFB_Code <> 0 then');
  Lines.Add('  begin');
  Lines.Add('    _LFB_Tmp := _LFB_BodyJo.S[''error''];');
  Lines.Add('    if _LFB_Tmp = '''' then _LFB_Tmp := ''Unknown service error'';');
  Lines.Add('    _LFB_ErrMsg := _LFB_Tmp;');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  Result := True;');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('{$EndRegion ''_LFB_helpers_''}');
  Lines.Add('');
end;

// EmitAsyncCallback - emit the cdecl OnResult callback for one API. The
// single callback is shared by the M and P variants; the context object
// carries whichever callback field is non-nil.
procedure EmitAsyncCallback(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  CtxType: TP_String;
  RetType: TP_String;
  DeserializeAssign: TP_String;
  InvokeSuccessExpr: TP_String;
begin
  CtxType := 'T' + ApiName + '_AsyncCtx';
  RetType := ABI_Type_To_Pascal_Decl(F.ReturnType);

  Lines.Add('procedure ' + ApiName + '_Async_OnResult(' +
    'Data: Pointer; Result_: TDataHnd___); cdecl;');
  Lines.Add('var');
  Lines.Add('  _LFB_Ctx: ' + CtxType + ';');
  Lines.Add('  _LFB_RespJson, _LFB_ErrMsg: string;');
  Lines.Add('  _LFB_Resp, _LFB_BodyJo: TZ_JsonObject;');
  Lines.Add('  _LFB_Code: Integer;');
  Lines.Add('  _LFB_IsSuccess, _LFB_Handled: Boolean;');
  if F.IsFunction then
  begin
    Lines.Add('  _LFB_ResultValue: ' + RetType + ';');
    DeserializeAssign := ABI_Type_To_Json_Deserialize_Assign(F.ReturnType);
    InvokeSuccessExpr :=
      'try _LFB_Ctx.OnSuccess_M(_LFB_ResultValue) except end;';
  end
  else
  begin
    DeserializeAssign := '';
    InvokeSuccessExpr :=
      'try _LFB_Ctx.OnSuccess_M() except end;';
  end;
  Lines.Add('begin');
  Lines.Add('  _LFB_Ctx := ' + CtxType + '(Data);');
  Lines.Add('  if _LFB_Ctx = nil then Exit;');
  Lines.Add('  try');
  Lines.Add('    try');
  Lines.Add('      _LFB_IsSuccess := False;');
  Lines.Add('      _LFB_ErrMsg := '''';');
  Lines.Add('      _LFB_Code := -1;');
  if F.IsFunction then
  begin
    if ABI_Type_Is_String(F.ReturnType) then
      Lines.Add('      _LFB_ResultValue := '''';')
    else if ABI_Type_Is_Float(F.ReturnType) then
      Lines.Add('      _LFB_ResultValue := 0.0;')
    else
      Lines.Add('      _LFB_ResultValue := 0;');
  end;
  Lines.Add('');
  Lines.Add('      if Result_ = nil then');
  Lines.Add('        _LFB_ErrMsg := ''LF_Async_Call returned a null handle''');
  Lines.Add('      else if LF_GetSize(Result_) = 0 then');
  Lines.Add('        _LFB_ErrMsg := ''Bridge returned an empty response (timeout?)''');
  Lines.Add('      else');
  Lines.Add('      begin');
  Lines.Add('        _LFB_RespJson := LF_ReadString(Result_);');
  Lines.Add('        if _LFB_ParseBridgeEnvelope(_LFB_RespJson, _LFB_Resp, _LFB_ErrMsg) then');
  Lines.Add('        begin');
  Lines.Add('          try');
  Lines.Add('            if not _LFB_Resp.Exists(''body'') then');
  Lines.Add('            begin');
  Lines.Add('              _LFB_ErrMsg := ''Bridge response has no "body" field'';');
  Lines.Add('              _LFB_Code := -4;');
  Lines.Add('            end');
  Lines.Add('            else');
  Lines.Add('            begin');
  Lines.Add('              _LFB_BodyJo := _LFB_Resp.O[''body''];');
  Lines.Add('              if _LFB_CheckServiceCode(_LFB_BodyJo, _LFB_Code, _LFB_ErrMsg) then');
  Lines.Add('              begin');
  if F.IsFunction then
  begin
    Lines.Add('                if not _LFB_BodyJo.Exists(''result'') then');
    Lines.Add('                begin');
    Lines.Add('                  _LFB_ErrMsg := ''Service response has no "result" field'';');
    Lines.Add('                  _LFB_Code := -4;');
    Lines.Add('                end');
    Lines.Add('                else');
    Lines.Add('                begin');
    Lines.Add('                  ' + DeserializeAssign);
    Lines.Add('                  _LFB_IsSuccess := True;');
    Lines.Add('                end;');
  end
  else
  begin
    Lines.Add('                _LFB_IsSuccess := True;');
  end;
  Lines.Add('              end;');
  Lines.Add('            end;');
  Lines.Add('          finally');
  Lines.Add('            _LFB_Resp.Free;');
  Lines.Add('          end;');
  Lines.Add('        end');
  Lines.Add('        else');
  Lines.Add('          _LFB_Code := -4;');
  Lines.Add('      end;');
  Lines.Add('');
  Lines.Add('      if _LFB_IsSuccess then');
  Lines.Add('      begin');
  Lines.Add('        _LFB_Handled := False;');
  Lines.Add('        if Assigned(_LFB_Ctx.OnSuccess_M) then');
  Lines.Add('        begin');
  Lines.Add('          ' + InvokeSuccessExpr);
  Lines.Add('          _LFB_Handled := True;');
  Lines.Add('        end;');
  Lines.Add('        if (not _LFB_Handled) and Assigned(_LFB_Ctx.OnSuccess_P) then');
  Lines.Add('        begin');
  if F.IsFunction then
    Lines.Add('          try _LFB_Ctx.OnSuccess_P(_LFB_ResultValue) except end;')
  else
    Lines.Add('          try _LFB_Ctx.OnSuccess_P() except end;');
  Lines.Add('        end;');
  Lines.Add('      end');
  Lines.Add('      else');
  Lines.Add('      begin');
  Lines.Add('        if Assigned(_LFB_Ctx.OnError_M) then');
  Lines.Add('          try _LFB_Ctx.OnError_M(_LFB_ErrMsg, _LFB_Code) except end');
  Lines.Add('        else if Assigned(_LFB_Ctx.OnError_P) then');
  Lines.Add('          try _LFB_Ctx.OnError_P(_LFB_ErrMsg, _LFB_Code) except end;');
  Lines.Add('      end;');
  Lines.Add('    except');
  Lines.Add('      // Never let exceptions escape into C.');
  Lines.Add('    end;');
  Lines.Add('  finally');
  Lines.Add('    _LFB_Ctx.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Sync implementation (App name addressing)
// ---------------------------------------------------------------------------

procedure EmitSyncByApp(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  i: integer;
  ParamDecl, RetType, ParamName, SerializeStmt, DeserializeExpr: TP_String;
  HeaderLine: TP_String;
begin
  ParamDecl := BuildTypedParamDecl(F.Params);
  RetType := ABI_Type_To_Pascal_Decl(F.ReturnType);
  if F.IsFunction then
    HeaderLine := 'function ' + ApiName + '(' + ParamDecl + '): ' + RetType + '; overload;'
  else
    HeaderLine := 'procedure ' + ApiName + '(' + ParamDecl + '); overload;';
  Lines.Add(HeaderLine);
  Lines.Add('var');
  Lines.Add('  _LFB_Url, _LFB_ErrMsg: string;');
  Lines.Add('  _LFB_RemoteBody, _LFB_Resp, _LFB_BodyJo: TZ_JsonObject;');
  Lines.Add('  _LFB_Code: Integer;');
  Lines.Add('begin');
  Lines.Add('  _LFB_Url := HTTP_CALL_BASE_URL + ''/' + ApiName + ''';');
  Lines.Add('  _LFB_RemoteBody := TZ_JsonObject.Create;');
  Lines.Add('  try');
  for i := 0 to High(F.Params) do
  begin
    ParamName := MakeSafePascalIdent(F.Params[i].Name, i);
    SerializeStmt := ABI_Type_To_Json_Serialize_Stmt(ParamName, F.Params[i].PascalType);
    Lines.Add('    ' + SerializeStmt);
  end;
  Lines.Add('    if not LFHttpPost(_LFB_Url, _LFB_RemoteBody, _LFB_Resp, _LFB_ErrMsg) then');
  Lines.Add('      raise EHTTPCallError.Create(''HTTP call to "' + ApiName + '" failed: '' + _LFB_ErrMsg);');
  Lines.Add('    try');
  Lines.Add('      if not _LFB_Resp.Exists(''body'') then');
  Lines.Add('        raise EHTTPCallError.Create(''HTTP call to "' + ApiName + '": bridge response has no "body" field'');');
  Lines.Add('      _LFB_BodyJo := _LFB_Resp.O[''body''];');
  Lines.Add('      if not _LFB_CheckServiceCode(_LFB_BodyJo, _LFB_Code, _LFB_ErrMsg) then');
  Lines.Add('        raise EHTTPCallError.Create(''HTTP call to "' + ApiName + '" failed: '' + _LFB_ErrMsg);');
  if F.IsFunction then
  begin
    Lines.Add('      if not _LFB_BodyJo.Exists(''result'') then');
    Lines.Add('        raise EHTTPCallError.Create(''HTTP call to "' + ApiName + '": service response has no "result" field'');');
    DeserializeExpr := ABI_Type_To_Json_Deserialize_Expr(F.ReturnType);
    Lines.Add('      Result := ' + DeserializeExpr + ';');
  end;
  Lines.Add('    finally');
  Lines.Add('      _LFB_Resp.Free;');
  Lines.Add('    end;');
  Lines.Add('  finally');
  Lines.Add('    _LFB_RemoteBody.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// Async implementation emitters
// ---------------------------------------------------------------------------

// EmitAsyncFamilyBody - emit the implementation for one async variant.
// Kind is 'M' or 'P'. The body submits an LF_Async_Call to the fixed
// bridge App; the per-API cdecl callback then delivers the outcome.
procedure EmitAsyncFamilyBody(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String;
  const Kind: TP_String;     // 'M' or 'P'
  const FullHeader: TP_String);
var
  i: integer;
  ParamName, SerializeStmt: TP_String;
begin
  Lines.Add(FullHeader);
  Lines.Add('var');
  Lines.Add('  _LFB_Url, _LFB_RemoteBodyJson, _LFB_OuterJson: string;');
  Lines.Add('  _LFB_RemoteBody: TZ_JsonObject;');
  Lines.Add('  _LFB_ReqHandle: TDataHnd___;');
  Lines.Add('  _LFB_Ctx: T' + ApiName + '_AsyncCtx;');
  Lines.Add('  _LFB_Rc: Integer;');
  Lines.Add('begin');
  Lines.Add('  Result := False;');
  Lines.Add('  _LFB_Url := HTTP_CALL_BASE_URL + ''/' + ApiName + ''';');
  Lines.Add('  _LFB_RemoteBody := TZ_JsonObject.Create;');
  Lines.Add('  try');
  for i := 0 to High(F.Params) do
  begin
    ParamName := MakeSafePascalIdent(F.Params[i].Name, i);
    SerializeStmt := ABI_Type_To_Json_Serialize_Stmt(ParamName, F.Params[i].PascalType);
    Lines.Add('    ' + SerializeStmt);
  end;
  Lines.Add('    _LFB_RemoteBodyJson := _LFB_RemoteBody.ToJSONString(False);');
  Lines.Add('  finally');
  Lines.Add('    _LFB_RemoteBody.Free;');
  Lines.Add('  end;');
  Lines.Add('  _LFB_OuterJson := _LFB_BuildOuterEnvelope(_LFB_Url, _LFB_RemoteBodyJson,');
  Lines.Add('    LFBridgeDefaultHttpTimeoutSec);');
  Lines.Add('');
  Lines.Add('  _LFB_ReqHandle := LF_CreateDataEx(LFBridgeApiName);');
  Lines.Add('  if _LFB_ReqHandle = nil then');
  Lines.Add('  begin');
  Lines.Add('    if Assigned(OnError) then');
  Lines.Add('      try OnError(''LF_CreateDataEx failed'', -1) except end;');
  Lines.Add('    Exit;');
  Lines.Add('  end;');
  Lines.Add('  try');
  Lines.Add('    if not LF_WriteString(_LFB_ReqHandle, _LFB_OuterJson) then');
  Lines.Add('    begin');
  Lines.Add('      if Assigned(OnError) then');
  Lines.Add('        try OnError(''LF_WriteString failed'', -1) except end;');
  Lines.Add('      Exit;');
  Lines.Add('    end;');
  Lines.Add('');
  Lines.Add('    _LFB_Ctx := T' + ApiName + '_AsyncCtx.Create;');
  if Kind = 'M' then
  begin
    Lines.Add('    _LFB_Ctx.OnSuccess_M := OnSuccess;');
    Lines.Add('    _LFB_Ctx.OnSuccess_P := nil;');
    Lines.Add('    _LFB_Ctx.OnError_M := OnError;');
    Lines.Add('    _LFB_Ctx.OnError_P := nil;');
  end
  else
  begin
    Lines.Add('    _LFB_Ctx.OnSuccess_M := nil;');
    Lines.Add('    _LFB_Ctx.OnSuccess_P := OnSuccess;');
    Lines.Add('    _LFB_Ctx.OnError_M := nil;');
    Lines.Add('    _LFB_Ctx.OnError_P := OnError;');
  end;
  Lines.Add('');
  Lines.Add('    _LFB_Rc := LF_Async_CallEx(LFBridgeAppName, _LFB_ReqHandle, _LFB_Ctx,');
  Lines.Add('      @' + ApiName + '_Async_OnResult);');
  Lines.Add('    if _LFB_Rc < 0 then');
  Lines.Add('    begin');
  Lines.Add('      _LFB_Ctx.Free;');
  Lines.Add('      if Assigned(OnError) then');
  Lines.Add('        try OnError(''LF_Async_CallEx failed'', -1) except end;');
  Lines.Add('      Exit;');
  Lines.Add('    end;');
  Lines.Add('    Result := True;');
  Lines.Add('  finally');
  Lines.Add('    LF_FreeData(_LFB_ReqHandle);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// ---------------------------------------------------------------------------
// The generator proper
// ---------------------------------------------------------------------------

function GenerateHTTPCallPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, DefaultBaseUrl: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
  HeaderStr: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallPascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallPascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    // Disambiguate API names so overloaded routines get distinct URLs.
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := UniqueName(MakeApiName(SupportedFuncs[i].Name), UsedApiNames);
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    // 1. Unit header
    EmitUnitHeader(Lines, UnitName, NormalizedUnit);

    // 2. Type section
    EmitTypeSection(Lines, SupportedFuncs, ApiNames);

    // 3. Var section
    EmitVarSection(Lines, DefaultBaseUrl);

    // 4. Interface function declarations
    EmitInterfaceFunctions(Lines, SupportedFuncs, ApiNames);

    // 5. Implementation
    Lines.Add('implementation');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  Classes;');
    Lines.Add('');

    // 5a. Shared helpers
    EmitHelpers(Lines);

    // 5b. Async cdecl callbacks (one per API)
    Lines.Add('{$Region ''_LFB_async_callbacks_''}');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Cdecl result callbacks. One per supported routine. The Data');
    Lines.Add('// pointer carries a T<Api>_AsyncCtx instance allocated by the');
    Lines.Add('// submit function and freed here on every path.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
      EmitAsyncCallback(Lines, SupportedFuncs[i], ApiNames[i]);
    Lines.Add('{$EndRegion ''_LFB_async_callbacks_''}');
    Lines.Add('');

    // 5c. Synchronous implementations
    Lines.Add('{$Region ''_LFB_sync_''}');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Synchronous call implementations. Each function blocks until the');
    Lines.Add('// bridge returns a response, then either returns the result or');
    Lines.Add('// raises EHTTPCallError.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
      EmitSyncByApp(Lines, SupportedFuncs[i], ApiNames[i]);
    Lines.Add('{$EndRegion ''_LFB_sync_''}');
    Lines.Add('');

    // 5d. Asynchronous implementations
    Lines.Add('{$Region ''_LFB_async_''}');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('// Asynchronous submit implementations. Each returns True when the');
    Lines.Add('// request has been queued for the bridge; the outcome is delivered');
    Lines.Add('// through the Success/Error callbacks, on a TCompute worker thread.');
    Lines.Add('// ---------------------------------------------------------------------');
    Lines.Add('');
    for i := 0 to High(SupportedFuncs) do
    begin
      // ---- Async M ----
      HeaderStr := BuildAsyncHeader_M(SupportedFuncs[i], ApiNames[i], '_Async');
      EmitAsyncFamilyBody(Lines, SupportedFuncs[i], ApiNames[i], 'M', HeaderStr);

      // ---- Async P ----
      HeaderStr := BuildAsyncHeader_P(SupportedFuncs[i], ApiNames[i], '_Async_P');
      EmitAsyncFamilyBody(Lines, SupportedFuncs[i], ApiNames[i], 'P', HeaderStr);
    end;
    Lines.Add('{$EndRegion ''_LFB_async_''}');
    Lines.Add('');

    Lines.Add('end.');

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
    'pascal', 'Pascal HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call_unit.pas', False,
    @GenerateHTTPCallPascalCode);
end.
