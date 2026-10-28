unit http_delphi_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallDelphiCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_delphi_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_delphi_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Delphi_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) then
    Result := 'Double'
  else if ABI_Type_Is_Int(T) then
    Result := 'Int64'
  else
    Result := 'Pointer';
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

function MakeSafeDelphiIdent(const Name: TP_String; Index: integer): TP_String;
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

  if Result.Same('and') or Result.Same('array') or Result.Same('as') or
    Result.Same('asm') or Result.Same('begin') or Result.Same('case') or
    Result.Same('class') or Result.Same('const') or Result.Same('constructor') or
    Result.Same('destructor') or Result.Same('dispinterface') or Result.Same('div') or
    Result.Same('do') or Result.Same('downto') or Result.Same('else') or
    Result.Same('end') or Result.Same('except') or Result.Same('exports') or
    Result.Same('file') or Result.Same('finalization') or Result.Same('finally') or
    Result.Same('for') or Result.Same('function') or Result.Same('goto') or
    Result.Same('if') or Result.Same('implementation') or Result.Same('in') or
    Result.Same('inherited') or Result.Same('initialization') or Result.Same('inline') or
    Result.Same('interface') or Result.Same('is') or Result.Same('label') or
    Result.Same('library') or Result.Same('mod') or Result.Same('nil') or
    Result.Same('not') or Result.Same('object') or Result.Same('of') or
    Result.Same('or') or Result.Same('out') or Result.Same('packed') or
    Result.Same('procedure') or Result.Same('program') or Result.Same('property') or
    Result.Same('raise') or Result.Same('record') or Result.Same('repeat') or
    Result.Same('resourcestring') or Result.Same('set') or Result.Same('shl') or
    Result.Same('shr') or Result.Same('string') or Result.Same('then') or
    Result.Same('threadvar') or Result.Same('to') or Result.Same('try') or
    Result.Same('type') or Result.Same('unit') or Result.Same('until') or
    Result.Same('uses') or Result.Same('var') or Result.Same('while') or
    Result.Same('with') or Result.Same('xor') then
    Result := Result + '_';
end;

function Delphi_Str_Lit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = #39 then
    begin
      Result.Append(#39);
      Result.Append(#39);
    end
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

function BuildDelphiParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n, t: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeDelphiIdent(Params[i].Name, i);
    t := ABI_Type_To_Delphi_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + '; ';
    Result := Result + n + ': ' + t;
  end;
end;

function BuildDelphiArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeDelphiIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildDelphiJsonAddStatements(const Params: TParamArray; const Indent: TP_String): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeDelphiIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + #13#10;
    Result := Result + Indent + 'Args.Add(' + n + ');';
  end;
end;

function BuildDelphiResultExtract(const ReturnType: TP_String; const Target: TP_String): TP_String;
begin
  if ABI_Type_Is_String(ReturnType) then
    Result := 'if not RespJo.TryGetValue<string>(''result'', ' + Target + ') then ' +
      Target + ' := ' + #39#39 + ';'
  else if ABI_Type_Is_Float(ReturnType) then
    Result := 'if not RespJo.TryGetValue<Double>(''result'', ' + Target + ') then ' +
      Target + ' := 0.0;'
  else if ABI_Type_Is_Int(ReturnType) then
    Result := 'if not RespJo.TryGetValue<Int64>(''result'', ' + Target + ') then ' +
      Target + ' := 0;'
  else
    Result := '';
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeDelphiIdent(F.Params[i].Name, i);
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

function BuildDelphiSignature(const F: TFunctionStructure; const ApiName: TP_String): TP_String;
var
  ParamDecl: TP_String;
begin
  ParamDecl := BuildDelphiParamDecl(F.Params);
  if F.IsFunction then
    Result := 'function ' + ApiName + '(' + ParamDecl + '): ' +
      ABI_Type_To_Delphi_Type(F.ReturnType) + ';'
  else
    Result := 'procedure ' + ApiName + '(' + ParamDecl + ');';
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
// CALL MODULE GENERATOR
// =============================================================================

procedure EmitDelphiHeader(Lines: TPascalStringList;
  const UnitName, UnitId, BaseUrl: TP_String);
begin
  Lines.Add('unit ' + UnitId.Text + '_http_json_call_delphi;');
  Lines.Add('');
  Lines.Add('// -*- coding: utf-8 -*-');
  Lines.Add('// Auto-generated by http_delphi_abi_call_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// Wire protocol (HTTP/JSON path):');
  Lines.Add('//   request  = POST <base_url>/<api>  with body');
  Lines.Add('//              { "args": [v1, v2, ...] }');
  Lines.Add('//   response = { "code": 0,  "result": ... }   on success');
  Lines.Add('//              { "code": -1, "error":  ... }   on failure');
  Lines.Add('//');
  Lines.Add('// This unit is a native Delphi HTTP/JSON client. It uses ONLY the');
  Lines.Add('// Delphi RTL (System.Net.HttpClient + System.JSON + System.Classes)');
  Lines.Add('// and therefore does NOT depend on the LingoFuse runtime, the Z');
  Lines.Add('// framework, or any third-party package.');
  Lines.Add('//');
  Lines.Add('// ====================================================================');
  Lines.Add('// THREADING CONTRACT');
  Lines.Add('// ====================================================================');
  Lines.Add('// The synchronous entry points block and return on the CALLING');
  Lines.Add('// thread.');
  Lines.Add('//');
  Lines.Add('// The asynchronous entry points (<Api>_Async) spawn a worker');
  Lines.Add('// thread and return immediately. The Success / Error callbacks');
  Lines.Add('// are invoked ON THAT WORKER THREAD, not on the calling thread.');
  Lines.Add('//');
  Lines.Add('// If a callback needs to update a UI control, marshal the update');
  Lines.Add('// yourself, for example:');
  Lines.Add('//');
  Lines.Add('//     procedure(const R: Int64)');
  Lines.Add('//     begin');
  Lines.Add('//       TThread.Queue(nil,');
  Lines.Add('//         procedure');
  Lines.Add('//         begin');
  Lines.Add('//           Label1.Caption := IntToStr(R);');
  Lines.Add('//         end);');
  Lines.Add('//     end');
  Lines.Add('//');
  Lines.Add('// This contract applies to console and GUI applications alike.');
  Lines.Add('// ====================================================================');
  Lines.Add('');
  Lines.Add('interface');
  Lines.Add('');
  Lines.Add('uses');
  Lines.Add('  System.SysUtils, System.Classes, System.Generics.Collections,');
  Lines.Add('  System.JSON, System.Net.HttpClient, System.Net.URLClient;');
  Lines.Add('');
end;

procedure EmitDelphiTypes(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, RetType, HelperName: TP_String;
begin
  Lines.Add('type');
  Lines.Add('  // Raised by every synchronous call on failure, and passed to');
  Lines.Add('  // every asynchronous OnError callback.');
  Lines.Add('  //');
  Lines.Add('  // Code mirrors the wire-level "code" field:');
  Lines.Add('  //   0   - success (never raised)');
  Lines.Add('  //   -1  - transport / HTTP / empty / shape failure');
  Lines.Add('  //   -2  - bridge URL shape error');
  Lines.Add('  //   -3  - bridge pre-check failed');
  Lines.Add('  //   other - service-defined error code');
  Lines.Add('  EHTTPCallError = class(Exception)');
  Lines.Add('  public');
  Lines.Add('    Code: Integer;');
  Lines.Add('    HttpStatus: Integer;');
  Lines.Add('    constructor Create(const AMessage: string; ACode, AHttpStatus: Integer); reintroduce;');
  Lines.Add('  end;');
  Lines.Add('');
  Lines.Add('  // ------------------------------------------------------------------');
  Lines.Add('  // Async helper threads. One per supported routine.');
  Lines.Add('  //');
  Lines.Add('  // Each helper is a TThread subclass whose fields hold the');
  Lines.Add('  // arguments, the callbacks and the outcome. Its Execute method');
  Lines.Add('  // runs the sync wrapper on the worker thread and then invokes');
  Lines.Add('  // the callbacks directly on that same worker thread. No');
  Lines.Add('  // TThread.Queue and no anonymous methods are involved, which');
  Lines.Add('  // keeps the async path reliable in console programs (no message');
  Lines.Add('  // loop required) and sidesteps Delphi 10.4''s lambda-inference');
  Lines.Add('  // limitation for nested lambdas.');
  Lines.Add('  // ------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HelperName := 'T' + ApiName + '_Async_Helper';
    RetType := ABI_Type_To_Delphi_Type(F.ReturnType);

    Lines.Add('  ' + HelperName.Text + ' = class(TThread)');
    Lines.Add('  public');
    for j := 0 to High(F.Params) do
    begin
      Lines.Add('    FParam_' + MakeSafeDelphiIdent(F.Params[j].Name, j).Text +
        ': ' + ABI_Type_To_Delphi_Type(F.Params[j].PascalType) + ';');
    end;
    if F.IsFunction then
      Lines.Add('    FOnResult: TProc<' + RetType + '>;')
    else
      Lines.Add('    FOnResult: TProc;');
    Lines.Add('    FOnError: TProc<Exception>;');
    if F.IsFunction then
      Lines.Add('    FResultValue: ' + RetType + ';');
    Lines.Add('    FErrorMsg: string;');
    Lines.Add('    FErrorCode: Integer;');
    Lines.Add('    FHasError: Boolean;');
    Lines.Add('    procedure DeliverResult;');
    Lines.Add('    procedure DeliverError;');
    Lines.Add('  protected');
    Lines.Add('    procedure Execute; override;');
    Lines.Add('  end;');
    Lines.Add('');
  end;
end;

procedure EmitDelphiConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('var');
  Lines.Add('  // Base URL of the bridge, including the target app name.');
  Lines.Add('  // The full URL for API "X" is: HTTP_CALL_BASE_URL + "/" + "X"');
  Lines.Add('  HTTP_CALL_BASE_URL: string = ' + Delphi_Str_Lit(BaseUrl) + ';');
  Lines.Add('');
  Lines.Add('  // Per-request timeout, in milliseconds. Applied to both the');
  Lines.Add('  // connection and the response. 0 means "use the RTL default".');
  Lines.Add('  HTTP_CALL_TIMEOUT_MS: Integer = 30000;');
  Lines.Add('');
end;

procedure EmitDelphiInterfaceFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, ParamDecl, RetType: TP_String;
begin
  Lines.Add('  // ------------------------------------------------------------------');
  Lines.Add('  // Generated API declarations');
  Lines.Add('  //');
  Lines.Add('  // Each API has two entry points:');
  Lines.Add('  //   * a synchronous function that blocks and returns the result;');
  Lines.Add('  //   * an asynchronous procedure that spawns a helper thread.');
  Lines.Add('  //');
  Lines.Add('  // The _Async callbacks run on the worker thread. See the');
  Lines.Add('  // "THREADING CONTRACT" in the unit header.');
  Lines.Add('  // ------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildDelphiParamDecl(F.Params);
    RetType := ABI_Type_To_Delphi_Type(F.ReturnType);

    if F.IsFunction then
      Lines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetType + '; overload;')
    else
      Lines.Add('procedure ' + ApiName + '(' + ParamDecl + '); overload;');

    if F.IsFunction then
    begin
      if ParamDecl <> '' then
        Lines.Add('procedure ' + ApiName + '_Async(' + ParamDecl + '; ' +
          'const OnResult: TProc<' + RetType + '>; const OnError: TProc<Exception>); overload;')
      else
        Lines.Add('procedure ' + ApiName + '_Async(' +
          'const OnResult: TProc<' + RetType + '>; const OnError: TProc<Exception>); overload;');
    end
    else
    begin
      if ParamDecl <> '' then
        Lines.Add('procedure ' + ApiName + '_Async(' + ParamDecl + '; ' +
          'const OnResult: TProc; const OnError: TProc<Exception>); overload;')
      else
        Lines.Add('procedure ' + ApiName + '_Async(' +
          'const OnResult: TProc; const OnError: TProc<Exception>); overload;');
    end;

    Lines.Add('');
  end;
end;

procedure EmitDelphiImplementationHelpers(Lines: TPascalStringList);
begin
  Lines.Add('{$Region ''transport helpers''}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Transport helpers');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('constructor EHTTPCallError.Create(const AMessage: string;');
  Lines.Add('  ACode, AHttpStatus: Integer);');
  Lines.Add('begin');
  Lines.Add('  inherited Create(AMessage);');
  Lines.Add('  Code := ACode;');
  Lines.Add('  HttpStatus := AHttpStatus;');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function MakeJsonHeaders: TNetHeaders;');
  Lines.Add('begin');
  Lines.Add('  SetLength(Result, 1);');
  Lines.Add('  Result[0].Name := ''Content-Type'';');
  Lines.Add('  Result[0].Value := ''application/json; charset=utf-8'';');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function PostJson(const Url, BodyJson: string): string;');
  Lines.Add('var');
  Lines.Add('  Http: THTTPClient;');
  Lines.Add('  ReqStream: TStringStream;');
  Lines.Add('  Resp: IHTTPResponse;');
  Lines.Add('  Raw: string;');
  Lines.Add('begin');
  Lines.Add('  Http := THTTPClient.Create;');
  Lines.Add('  try');
  Lines.Add('    if HTTP_CALL_TIMEOUT_MS > 0 then');
  Lines.Add('    begin');
  Lines.Add('      Http.ConnectionTimeout := HTTP_CALL_TIMEOUT_MS;');
  Lines.Add('      Http.ResponseTimeout := HTTP_CALL_TIMEOUT_MS;');
  Lines.Add('    end;');
  Lines.Add('');
  Lines.Add('    ReqStream := TStringStream.Create(BodyJson, TEncoding.UTF8);');
  Lines.Add('    try');
  Lines.Add('      try');
  // 4-argument overload: (AURL, ASource, AResponseContent, AHeaders).
  Lines.Add('        Resp := Http.Post(Url, ReqStream, nil, MakeJsonHeaders);');
  Lines.Add('      except');
  Lines.Add('        on E: Exception do');
  Lines.Add('          raise EHTTPCallError.Create(''Network error: '' + E.Message, -1, 0);');
  Lines.Add('      end;');
  Lines.Add('    finally');
  Lines.Add('      ReqStream.Free;');
  Lines.Add('    end;');
  Lines.Add('');
  Lines.Add('    Raw := Resp.ContentAsString(TEncoding.UTF8);');
  Lines.Add('    if Resp.StatusCode <> 200 then');
  Lines.Add('      raise EHTTPCallError.Create(');
  Lines.Add('        Format(''HTTP %d: %s'', [Resp.StatusCode, Raw]),');
  Lines.Add('        -1, Resp.StatusCode);');
  Lines.Add('    if Raw = '''' then');
  Lines.Add('      raise EHTTPCallError.Create(''Empty response from bridge'', -1, 200);');
  Lines.Add('');
  Lines.Add('    Result := Raw;');
  Lines.Add('  finally');
  Lines.Add('    Http.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('function CheckEnvelope(const Raw: string): TJSONObject;');
  Lines.Add('var');
  Lines.Add('  Value: TJSONValue;');
  Lines.Add('  Code: Integer;');
  Lines.Add('  ErrMsg: string;');
  Lines.Add('begin');
  Lines.Add('  Value := TJSONObject.ParseJSONValue(Raw);');
  Lines.Add('  if (not Assigned(Value)) or (not (Value is TJSONObject)) then');
  Lines.Add('  begin');
  Lines.Add('    if Assigned(Value) then Value.Free;');
  Lines.Add('    raise EHTTPCallError.Create(''Response is not a JSON object'', -1, 200);');
  Lines.Add('  end;');
  Lines.Add('  Result := TJSONObject(Value);');
  Lines.Add('  try');
  Lines.Add('    if not Result.TryGetValue<Integer>(''code'', Code) then');
  Lines.Add('      raise EHTTPCallError.Create(''Response has no "code" field'', -1, 200);');
  Lines.Add('    if Code <> 0 then');
  Lines.Add('    begin');
  Lines.Add('      if not Result.TryGetValue<string>(''error'', ErrMsg) then');
  Lines.Add('        ErrMsg := ''Remote call failed'';');
  Lines.Add('      raise EHTTPCallError.Create(ErrMsg, Code, 200);');
  Lines.Add('    end;');
  Lines.Add('  except');
  Lines.Add('    Result.Free;');
  Lines.Add('    raise;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
  Lines.Add('{$EndRegion ''transport helpers''}');
  Lines.Add('');
end;

procedure EmitDelphiSyncBody(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl, RetType, ArgsAdd, ResultExtract: TP_String;
begin
  ParamDecl := BuildDelphiParamDecl(F.Params);
  RetType := ABI_Type_To_Delphi_Type(F.ReturnType);

  if F.IsFunction then
    Lines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetType + ';')
  else
    Lines.Add('procedure ' + ApiName + '(' + ParamDecl + ');');

  Lines.Add('var');
  Lines.Add('  BodyJo: TJSONObject;');
  Lines.Add('  Args: TJSONArray;');
  Lines.Add('  RespJo: TJSONObject;');
  Lines.Add('  Raw: string;');
  Lines.Add('begin');
  Lines.Add('  BodyJo := TJSONObject.Create;');
  Lines.Add('  try');
  Lines.Add('    Args := TJSONArray.Create;');
  if Length(F.Params) > 0 then
  begin
    ArgsAdd := BuildDelphiJsonAddStatements(F.Params, '    ');
    Lines.Add(ArgsAdd);
  end;
  Lines.Add('    BodyJo.AddPair(''args'', Args);');
  Lines.Add('');
  Lines.Add('    Raw := PostJson(HTTP_CALL_BASE_URL + ' +
    Delphi_Str_Lit('/' + ApiName) + ', BodyJo.ToJSON);');
  Lines.Add('  finally');
  Lines.Add('    BodyJo.Free;');
  Lines.Add('  end;');
  Lines.Add('');
  Lines.Add('  RespJo := CheckEnvelope(Raw);');
  Lines.Add('  try');
  if F.IsFunction then
  begin
    ResultExtract := BuildDelphiResultExtract(F.ReturnType, 'Result');
    Lines.Add('    ' + ResultExtract);
  end
  else
    Lines.Add('    // procedure has no result');
  Lines.Add('  finally');
  Lines.Add('    RespJo.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// EmitHelperImpl - emit the implementation of one helper thread class.
//
// This is the core of the async design. The class inherits from
// TThread, so:
//   * its fields hold the arguments, the callbacks, and the outcome;
//   * Execute runs the sync wrapper on the worker thread and writes
//     the outcome into fields;
//   * DeliverResult / DeliverError are ordinary object methods (not
//     lambdas) that invoke the user's TProc<T> / TProc<Exception>
//     DIRECTLY ON THE WORKER THREAD.
//
// No TThread.Queue is used. This is intentional: in console programs
// the queue-based delivery (CheckSynchronize) is unreliable, and the
// anonymous-method inference for nested lambdas that capture TProc<T>
// fails on Delphi 10.4. Invoking the callback directly on the worker
// thread avoids both problems. See the unit header for the exact
// threading contract.
procedure EmitHelperImpl(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  HelperName, RetType, ArgList, ParamName: TP_String;
  i: integer;
begin
  HelperName := 'T' + ApiName + '_Async_Helper';
  RetType := ABI_Type_To_Delphi_Type(F.ReturnType);
  ArgList := '';

  for i := 0 to High(F.Params) do
  begin
    ParamName := 'FParam_' + MakeSafeDelphiIdent(F.Params[i].Name, i);
    if i > 0 then
      ArgList := ArgList + ', ';
    ArgList := ArgList + ParamName;
  end;

  // ---- Execute ----
  Lines.Add('procedure ' + HelperName + '.Execute;');
  Lines.Add('begin');
  Lines.Add('  try');
  if F.IsFunction then
    Lines.Add('    FResultValue := ' + ApiName + '(' + ArgList + ');')
  else
    Lines.Add('    ' + ApiName + '(' + ArgList + ');');
  Lines.Add('    FHasError := False;');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do');
  Lines.Add('    begin');
  Lines.Add('      FHasError := True;');
  Lines.Add('      FErrorMsg := E.Message;');
  Lines.Add('      if E is EHTTPCallError then');
  Lines.Add('        FErrorCode := EHTTPCallError(E).Code');
  Lines.Add('      else');
  Lines.Add('        FErrorCode := -1;');
  Lines.Add('    end;');
  Lines.Add('  end;');
  Lines.Add('');
  Lines.Add('  // Invoke the user callbacks ON THE WORKER THREAD.');
  Lines.Add('  // See the "THREADING CONTRACT" in the unit header.');
  Lines.Add('  try');
  Lines.Add('    if FHasError then');
  Lines.Add('      DeliverError');
  Lines.Add('    else');
  Lines.Add('      DeliverResult;');
  Lines.Add('  except');
  Lines.Add('    // Never let a user callback exception escape into the thread runtime.');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');

  // ---- DeliverResult ----
  Lines.Add('procedure ' + HelperName + '.DeliverResult;');
  Lines.Add('begin');
  if F.IsFunction then
  begin
    Lines.Add('  if Assigned(FOnResult) then');
    Lines.Add('    FOnResult(FResultValue);');
  end
  else
  begin
    Lines.Add('  if Assigned(FOnResult) then');
    Lines.Add('    FOnResult();');
  end;
  Lines.Add('end;');
  Lines.Add('');

  // ---- DeliverError ----
  Lines.Add('procedure ' + HelperName + '.DeliverError;');
  Lines.Add('var');
  Lines.Add('  E: Exception;');
  Lines.Add('begin');
  Lines.Add('  if not Assigned(FOnError) then Exit;');
  Lines.Add('  if FErrorCode = -1 then');
  Lines.Add('    E := EHTTPCallError.Create(FErrorMsg, FErrorCode, 0)');
  Lines.Add('  else');
  Lines.Add('    E := EHTTPCallError.Create(FErrorMsg, FErrorCode, 200);');
  Lines.Add('  try');
  Lines.Add('    FOnError(E);');
  Lines.Add('  finally');
  Lines.Add('    E.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

// EmitAsyncProcImpl - emit the <Api>_Async procedure. All it does is
// allocate and start the helper thread. No lambdas.
procedure EmitAsyncProcImpl(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl, RetType, HelperName, ParamName: TP_String;
  i: integer;
begin
  ParamDecl := BuildDelphiParamDecl(F.Params);
  RetType := ABI_Type_To_Delphi_Type(F.ReturnType);
  HelperName := 'T' + ApiName + '_Async_Helper';

  if F.IsFunction then
  begin
    if ParamDecl <> '' then
      Lines.Add('procedure ' + ApiName + '_Async(' + ParamDecl + '; ' +
        'const OnResult: TProc<' + RetType + '>; const OnError: TProc<Exception>);')
    else
      Lines.Add('procedure ' + ApiName + '_Async(' +
        'const OnResult: TProc<' + RetType + '>; const OnError: TProc<Exception>);');
  end
  else
  begin
    if ParamDecl <> '' then
      Lines.Add('procedure ' + ApiName + '_Async(' + ParamDecl + '; ' +
        'const OnResult: TProc; const OnError: TProc<Exception>);')
    else
      Lines.Add('procedure ' + ApiName + '_Async(' +
        'const OnResult: TProc; const OnError: TProc<Exception>);');
  end;

  Lines.Add('var');
  Lines.Add('  H: ' + HelperName + ';');
  Lines.Add('begin');
  Lines.Add('  H := ' + HelperName + '.Create(True);');
  Lines.Add('  H.FreeOnTerminate := True;');
  for i := 0 to High(F.Params) do
  begin
    ParamName := MakeSafeDelphiIdent(F.Params[i].Name, i);
    Lines.Add('  H.FParam_' + ParamName + ' := ' + ParamName + ';');
  end;
  Lines.Add('  H.FOnResult := OnResult;');
  Lines.Add('  H.FOnError := OnError;');
  Lines.Add('  H.Start;');
  Lines.Add('end;');
  Lines.Add('');
end;

procedure EmitDelphiImplementation(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
begin
  Lines.Add('implementation');
  Lines.Add('');

  EmitDelphiImplementationHelpers(Lines);

  Lines.Add('{$Region ''sync functions''}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Synchronous implementations');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  for i := 0 to High(SupportedFuncs) do
    EmitDelphiSyncBody(Lines, SupportedFuncs[i], ApiNames[i]);
  Lines.Add('{$EndRegion ''sync functions''}');
  Lines.Add('');

  Lines.Add('{$Region ''async helper implementations''}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Async helper thread implementations');
  Lines.Add('//');
  Lines.Add('// The callbacks are invoked directly on the worker thread. See the');
  Lines.Add('// "THREADING CONTRACT" in the unit header.');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  for i := 0 to High(SupportedFuncs) do
    EmitHelperImpl(Lines, SupportedFuncs[i], ApiNames[i]);
  Lines.Add('{$EndRegion ''async helper implementations''}');
  Lines.Add('');

  Lines.Add('{$Region ''async spawners''}');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('// Async spawners');
  Lines.Add('// ---------------------------------------------------------------------');
  Lines.Add('');
  for i := 0 to High(SupportedFuncs) do
    EmitAsyncProcImpl(Lines, SupportedFuncs[i], ApiNames[i]);
  Lines.Add('{$EndRegion ''async spawners''}');
  Lines.Add('');

  Lines.Add('end.');
  Lines.Add('');
end;

function GenerateHTTPCallDelphiCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, UnitId, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallDelphiCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallDelphiCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  UnitId := UnitName;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitDelphiHeader(Lines, UnitName, UnitId, BaseUrl);
    EmitDelphiTypes(Lines, SupportedFuncs, ApiNames);
    EmitDelphiConfig(Lines, BaseUrl);
    EmitDelphiInterfaceFunctions(Lines, SupportedFuncs, ApiNames);
    EmitDelphiImplementation(Lines, SupportedFuncs, ApiNames);

    Result := Lines;
    Log(PFormat('Generated Delphi call unit: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'delphi', 'Delphi HTTP/JSON call unit',
    asCall, akCallCode,
    '_http_json_call_delphi.pas', False,
    @GenerateHTTPCallDelphiCode);
end.
