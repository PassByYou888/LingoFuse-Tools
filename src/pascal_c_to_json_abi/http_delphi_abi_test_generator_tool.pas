unit http_delphi_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPCallDelphiTestCode - generate the console test program.
//
// The returned list is owned by the caller and must be released with
// DisposeObject.
function GenerateHTTPCallDelphiTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_delphi_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_delphi_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type classification (mirrors every other generator)
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

// ABI_Type_To_Delphi_Type - must mirror the call generator exactly.
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

// ABI_Type_To_Delphi_Default_Lit - default literal used at the call
// site when constructing the argument list.
function ABI_Type_To_Delphi_Default_Lit(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := #39#39
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'nil';
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
end;

// Delphi_Str_Lit - produce a complete Delphi string literal from S.
// Any single quote inside S is doubled, matching Delphi's escaping rule.
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

// BuildDelphiArgList - "0, 0, ''" list of default values for the
// generated test program.
function BuildDelphiArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    d := ABI_Type_To_Delphi_Default_Lit(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
end;

// BuildPascalDecl - full Pascal declaration, used by the README only.
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
// TEST-PROGRAM GENERATOR
// =============================================================================

// EmitPerApiTest - emit one _Sync and one _Async test procedure for the
// given API. Assumes the client unit <Unit>_http_json_call_delphi has
// already declared the sync and async wrappers.
procedure EmitPerApiTest(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  ArgList, RetType, TagSync, TagAsync, DoneParam: TP_String;
begin
  ArgList := BuildDelphiArgList(F.Params);
  RetType := ABI_Type_To_Delphi_Type(F.ReturnType);
  TagSync := ApiName + '[sync]';
  TagAsync := ApiName + '[async]';

  // ---- Sync test ----
  Lines.Add('procedure Test_' + ApiName + '_Sync;');
  Lines.Add('begin');
  Lines.Add('  try');
  if ArgList = '' then
    Lines.Add('    ' + ApiName + '();')
  else
    Lines.Add('    ' + ApiName + '(' + ArgList + ');');
  Lines.Add('    ReportOk(' + Delphi_Str_Lit(TagSync) + ');');
  Lines.Add('  except');
  Lines.Add('    on E: Exception do');
  Lines.Add('      ReportFail(' + Delphi_Str_Lit(TagSync) + ', E.Message);');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');

  // ---- Async test ----
  Lines.Add('procedure Test_' + ApiName + '_Async;');
  Lines.Add('var');
  Lines.Add('  _Done: TEvent;');
  Lines.Add('  _HasError: Boolean;');
  Lines.Add('  _ErrMsg: string;');
  Lines.Add('begin');
  Lines.Add('  _Done := TEvent.Create;');
  Lines.Add('  try');
  Lines.Add('    _HasError := False;');
  Lines.Add('    _ErrMsg := '''' ;');

  // Dispatch. Note: if the async wrapper itself raises (rare; usually
  // happens only on a programming error), we still report it as a
  // failure without an unhandled exception escaping the test program.
  Lines.Add('    try');
  if F.IsFunction then
    DoneParam := 'procedure(R: ' + RetType + ')'
  else
    DoneParam := 'procedure';

  if ArgList = '' then
  begin
    Lines.Add('      ' + ApiName + '_Async(');
    Lines.Add('        ' + DoneParam + '');
  end
  else
  begin
    Lines.Add('      ' + ApiName + '_Async(' + ArgList + ',');
    Lines.Add('        ' + DoneParam + '');
  end;
  Lines.Add('        begin');
  Lines.Add('          _Done.SetEvent;');
  Lines.Add('        end,');
  Lines.Add('        procedure(E: Exception)');
  Lines.Add('        begin');
  Lines.Add('          _HasError := True;');
  Lines.Add('          _ErrMsg := E.Message;');
  Lines.Add('          _Done.SetEvent;');
  Lines.Add('        end);');
  Lines.Add('    except');
  Lines.Add('      on E: Exception do');
  Lines.Add('      begin');
  Lines.Add('        ReportFail(' + Delphi_Str_Lit(TagAsync) + ', E.Message);');
  Lines.Add('        Exit;');
  Lines.Add('      end;');
  Lines.Add('    end;');
  Lines.Add('');
  Lines.Add('    if not PumpUntilSignaled(_Done, CALL_TIMEOUT_MS) then');
  Lines.Add('      ReportFail(' + Delphi_Str_Lit(TagAsync) + ', ''timeout'')');
  Lines.Add('    else if _HasError then');
  Lines.Add('      ReportFail(' + Delphi_Str_Lit(TagAsync) + ', _ErrMsg)');
  Lines.Add('    else');
  Lines.Add('      ReportOk(' + Delphi_Str_Lit(TagAsync) + ');');
  Lines.Add('  finally');
  Lines.Add('    _Done.Free;');
  Lines.Add('  end;');
  Lines.Add('end;');
  Lines.Add('');
end;

function GenerateHTTPCallDelphiTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, UnitId, ProgramId, ClientUnitId, Endpoint, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
  ArgList: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallDelphiTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallDelphiTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;

  UnitId := UnitName;
  ClientUnitId := UnitName + '_http_json_call_delphi';
  ProgramId := NormalizedUnit + '_http_json_call_delphi_test___';
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('program ' + ProgramId.Text + ';');
    Lines.Add('');
    Lines.Add('// -*- coding: utf-8 -*-');
    Lines.Add('// Auto-generated by http_delphi_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Console test program for the Delphi HTTP/JSON client unit.');
    Lines.Add('// Pairs with ' + ClientUnitId.Text + '.pas.');
    Lines.Add('//');
    Lines.Add('// For every supported routine this program issues TWO calls:');
    Lines.Add('//   - <Api>          sync  / App name');
    Lines.Add('//   - <Api>_Async    async / App name');
    Lines.Add('//');
    Lines.Add('// Both variants go through bridge.py to the target HTTP/JSON');
    Lines.Add('// service. The bridge and the service must already be running.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * the matching HTTP/JSON service is running;');
    Lines.Add('//   * bridge.py is running on the same LingoFuse endpoint;');
    Lines.Add('//   * ' + ClientUnitId.Text + '.pas is compiled together with this');
    Lines.Add('//     program (same project group / same output directory).');
    Lines.Add('//');
    Lines.Add('// Usage:');
    Lines.Add('//   ' + ProgramId.Text + '.exe');
    Lines.Add('//   ' + ProgramId.Text + '.exe <base_url>');
    Lines.Add('//');
    Lines.Add('// Defaults:');
    Lines.Add('//   <base_url> = ' + BaseUrl.Text);
    Lines.Add('//');
    Lines.Add('// Target: Delphi 10.3 (Rio) or later.');
    Lines.Add('//');
    Lines.Add('// The async callbacks are delivered via TThread.Queue(nil, ...)');
    Lines.Add('// from the generated client unit. This program therefore pumps the');
    Lines.Add('// main-thread queue with CheckSynchronize while waiting for each');
    Lines.Add('// async result. Without that pump, async tests would hang.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('{$APPTYPE CONSOLE}');
    Lines.Add('');
    Lines.Add('uses');
    Lines.Add('  System.SysUtils,');
    Lines.Add('  System.Classes,');
    Lines.Add('  System.SyncObjs,');
    Lines.Add('  ' + ClientUnitId.Text + ';');
    Lines.Add('');
    Lines.Add('const');
    Lines.Add('  EXIT_OK         = 0;');
    Lines.Add('  EXIT_FAILED     = 1;');
    Lines.Add('  CALL_TIMEOUT_MS = 5000;');
    Lines.Add('');
    Lines.Add('var');
    Lines.Add('  gPass: Integer = 0;');
    Lines.Add('  gFail: Integer = 0;');
    Lines.Add('');
    Lines.Add('procedure ReportOk(const Tag_: string);');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''  '' + Tag_ + '': OK'');');
    Lines.Add('  Inc(gPass);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('procedure ReportFail(const Tag_, Msg: string);');
    Lines.Add('begin');
    Lines.Add('  WriteLn(ErrOutput, ''  '' + Tag_ + '': FAILED: '' + Msg);');
    Lines.Add('  Inc(gFail);');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// PumpUntilSignaled waits for Ev to become signaled while');
    Lines.Add('// continuously draining the main-thread queue with');
    Lines.Add('// CheckSynchronize. This is what makes the async callbacks run.');
    Lines.Add('function PumpUntilSignaled(Ev: TEvent; TimeoutMs: Cardinal): Boolean;');
    Lines.Add('var');
    Lines.Add('  Start: Cardinal;');
    Lines.Add('begin');
    Lines.Add('  Start := TThread.GetTickCount;');
    Lines.Add('  while True do');
    Lines.Add('  begin');
    Lines.Add('    if Ev.WaitFor(10) = wrSignaled then');
    Lines.Add('      Exit(True);');
    Lines.Add('    CheckSynchronize;');
    Lines.Add('    if TThread.GetTickCount - Start > TimeoutMs then');
    Lines.Add('      Exit(False);');
    Lines.Add('  end;');
    Lines.Add('end;');
    Lines.Add('');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Per-API tests');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
      EmitPerApiTest(Lines, SupportedFuncs[i], ApiNames[i]);

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Main');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('begin');
    Lines.Add('  WriteLn(''=== ' + UnitName.Text + ' HTTP/JSON call test ==='');');
    Lines.Add('  WriteLn;');
    Lines.Add('');
    Lines.Add('  if ParamCount >= 1 then');
    Lines.Add('    HTTP_CALL_BASE_URL := ParamStr(1);');
    Lines.Add('');
    Lines.Add('  WriteLn(''Base URL: '' + HTTP_CALL_BASE_URL);');
    Lines.Add('  WriteLn;');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := ApiNames[i];
      Lines.Add('  Test_' + ApiName + '_Sync;');
      Lines.Add('  Test_' + ApiName + '_Async;');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('  WriteLn(''  (no APIs to test)'');');

    Lines.Add('');
    Lines.Add('  WriteLn;');
    Lines.Add('  WriteLn(''=== Summary ==='');');
    Lines.Add('  WriteLn(''Passed: '', gPass);');
    Lines.Add('  WriteLn(''Failed: '', gFail);');
    Lines.Add('');
    Lines.Add('  if gFail = 0 then');
    Lines.Add('    ExitCode := EXIT_OK');
    Lines.Add('  else');
    Lines.Add('    ExitCode := EXIT_FAILED;');
    Lines.Add('end.');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated Delphi call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'delphi', 'Delphi HTTP/JSON call test program',
    asCall, akTestCode,
    '_http_json_call_delphi_test___.dpr', False,
    @GenerateHTTPCallDelphiTestCode);
end.
