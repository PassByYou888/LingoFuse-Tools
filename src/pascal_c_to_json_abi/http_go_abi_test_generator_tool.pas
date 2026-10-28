unit http_go_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceGoTestCode - generate the service-side smoke test.
function GenerateHTTPServiceGoTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallGoTestCode - generate the call-side end-to-end test.
function GenerateHTTPCallGoTestCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_go_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_go_abi_test_generator] %s', [PFormat(Fmt, Args)]);
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
      d := '0'
    else if ABI_Type_Is_Int(Params[i].PascalType) then
      d := '0'
    else
      d := 'nil';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
end;

function BuildServiceTestJSONBody(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  if Length(Params) = 0 then
  begin
    Result := '{"args": []}';
    Exit;
  end;
  Result := '{"args": [';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := '""'
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0'
    else if ABI_Type_Is_Int(Params[i].PascalType) then
      d := '0'
    else
      d := 'null';
    if i > 0 then
      Result := Result + ', ';
    Result := Result + d;
  end;
  Result := Result + ']}';
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
// SERVICE-SIDE SMOKE TEST
// =============================================================================

function GenerateHTTPServiceGoTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ServiceFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, ExportedName, SmokeBody: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceGoTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceGoTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ServiceFileName := NormalizedUnit + '_http_json_service_go.go';
  TestFileName := NormalizedUnit + '_http_json_service_main_test.go';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// Auto-generated by http_go_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service-side smoke test for the generated Go HTTP/JSON service.');
    Lines.Add('//');
    Lines.Add('// What this program does:');
    Lines.Add('//   1. Starts the process-global LingoFuse framework via TestMain.');
    Lines.Add('//   2. Creates a shared *lingofuse.AppHandle and registers the');
    Lines.Add('//      generated stubs on it.');
    Lines.Add('//   3. For every supported API, sends a JSON request through');
    Lines.Add('//      AppHandle.LocalCall (in-process, no network, no bridge)');
    Lines.Add('//      and verifies that the response envelope carries "code": 0.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * This file must sit next to ' + ServiceFileName.Text + '.');
    Lines.Add('//     Both files are `package main`.');
    Lines.Add('//   * The module must import the LingoFuse Go package:');
    Lines.Add('//       go get github.com/PassByYou888/LingoFuse/go');
    Lines.Add('//   * The native LingoFuse shared library must be on the loader');
    Lines.Add('//     search path (same requirement as the service itself).');
    Lines.Add('//');
    Lines.Add('// How to use:');
    Lines.Add('//   cp ' + TestFileName.Text + ' main_test.go');
    Lines.Add('//   go test -v');
    Lines.Add('//');
    Lines.Add('// No bridge.py is needed. This test proves mesh registration and');
    Lines.Add('// stub dispatch, NOT the HTTP wire.');
    Lines.Add('');
    Lines.Add('package main');
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add('    "encoding/json"');
    Lines.Add('    "fmt"');
    Lines.Add('    "os"');
    Lines.Add('    "testing"');
    Lines.Add('    "time"');
    Lines.Add('');
    Lines.Add('    "github.com/PassByYou888/LingoFuse/go/lingofuse"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('// sharedTestApp is the App used by every TestLocal_* function. It is');
    Lines.Add('// created once in TestMain and closed after m.Run returns.');
    Lines.Add('var sharedTestApp *lingofuse.AppHandle');
    Lines.Add('');
    Lines.Add('// TestMain performs the one-time framework setup and teardown.');
    Lines.Add('func TestMain(m *testing.M) {');
    Lines.Add('    setup := func() error {');
    Lines.Add('        if err := lingofuse.SetOption("Wait_Connection_ReadyOk", "False"); err != nil {');
    Lines.Add('            return fmt.Errorf("SetOption Wait_Connection_ReadyOk: %w", err)');
    Lines.Add('        }');
    Lines.Add('        if err := lingofuse.SetOption("Quiet", "True"); err != nil {');
    Lines.Add('            return fmt.Errorf("SetOption Quiet: %w", err)');
    Lines.Add('        }');
    Lines.Add('        if err := lingofuse.SetOption("Overlap_Connection", "True"); err != nil {');
    Lines.Add('            return fmt.Errorf("SetOption Overlap_Connection: %w", err)');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        if err := lingofuse.ResetPrepare(); err != nil {');
    Lines.Add('            return fmt.Errorf("ResetPrepare: %w", err)');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        appName := fmt.Sprintf("%s_test_%d", AppName, time.Now().UnixNano())');
    Lines.Add('        app, err := lingofuse.NewAppHandle(appName, "service smoke test")');
    Lines.Add('        if err != nil {');
    Lines.Add('            return fmt.Errorf("NewAppHandle: %w", err)');
    Lines.Add('        }');
    Lines.Add('        sharedTestApp = app');
    Lines.Add('');
    Lines.Add('        if err := registerAllAPIs(sharedTestApp); err != nil {');
    Lines.Add('            return fmt.Errorf("registerAllAPIs: %w", err)');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        if _, err := lingofuse.PrepareService(Endpoint, Endpoint); err != nil {');
    Lines.Add('            return fmt.Errorf("PrepareService: %w", err)');
    Lines.Add('        }');
    Lines.Add('        if _, err := lingofuse.PrepareClient(Endpoint, sharedTestApp); err != nil {');
    Lines.Add('            return fmt.Errorf("PrepareClient: %w", err)');
    Lines.Add('        }');
    Lines.Add('        started, err := lingofuse.PrepareDone()');
    Lines.Add('        if err != nil {');
    Lines.Add('            return fmt.Errorf("PrepareDone: %w", err)');
    Lines.Add('        }');
    Lines.Add('        if !started {');
    Lines.Add('            return fmt.Errorf("PrepareDone returned false")');
    Lines.Add('        }');
    Lines.Add('        return nil');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if err := setup(); err != nil {');
    Lines.Add('        fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)');
    Lines.Add('        os.Exit(1)');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    code := m.Run()');
    Lines.Add('');
    Lines.Add('    _ = lingofuse.ExitMainThread()');
    Lines.Add('    if sharedTestApp != nil {');
    Lines.Add('        sharedTestApp.Close()');
    Lines.Add('    }');
    Lines.Add('    _ = lingofuse.Shutdown()');
    Lines.Add('');
    Lines.Add('    os.Exit(code)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// localCall sends a NUL-terminated JSON request to the named API on');
    Lines.Add('// the shared test app and returns the parsed response envelope.');
    Lines.Add('func localCall(t *testing.T, apiName string, jsonBody string) map[string]any {');
    Lines.Add('    t.Helper()');
    Lines.Add('    req, err := lingofuse.NewDataHandle(apiName)');
    Lines.Add('    if err != nil {');
    Lines.Add('        t.Fatalf("%s: NewDataHandle: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('    defer req.Close()');
    Lines.Add('');
    Lines.Add('    if err := req.WriteString(jsonBody); err != nil {');
    Lines.Add('        t.Fatalf("%s: WriteString: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('    if err := req.SetPosition(0); err != nil {');
    Lines.Add('        t.Fatalf("%s: SetPosition: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    res, err := sharedTestApp.LocalCall(req)');
    Lines.Add('    if err != nil {');
    Lines.Add('        t.Fatalf("%s: LocalCall: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('    defer res.Close()');
    Lines.Add('');
    Lines.Add('    sz, err := res.Size()');
    Lines.Add('    if err != nil {');
    Lines.Add('        t.Fatalf("%s: Size: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('    if sz == 0 {');
    Lines.Add('        t.Fatalf("%s: empty response envelope", apiName)');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    if err := res.SetPosition(0); err != nil {');
    Lines.Add('        t.Fatalf("%s: SetPosition: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('    var env map[string]any');
    Lines.Add('    if err := lingofuse.ReadJSON(res, &env); err != nil {');
    Lines.Add('        t.Fatalf("%s: ReadJSON: %v", apiName, err)');
    Lines.Add('    }');
    Lines.Add('    return env');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// checkEnvelope fails the test if the response envelope is not');
    Lines.Add('// a success ({"code": 0}).');
    Lines.Add('func checkEnvelope(t *testing.T, apiName string, env map[string]any) {');
    Lines.Add('    t.Helper()');
    Lines.Add('    raw, ok := env["code"]');
    Lines.Add('    if !ok {');
    Lines.Add('        t.Fatalf("%s: response has no \"code\" field: %v", apiName, env)');
    Lines.Add('    }');
    Lines.Add('    code, ok := raw.(float64)');
    Lines.Add('    if !ok {');
    Lines.Add('        t.Fatalf("%s: \"code\" is not a number: %v", apiName, raw)');
    Lines.Add('    }');
    Lines.Add('    if code != 0 {');
    Lines.Add('        errMsg, _ := env["error"].(string)');
    Lines.Add('        t.Fatalf("%s: code=%v, error=%q", apiName, code, errMsg)');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('// dummy_json_import keeps encoding/json imported even when no');
    Lines.Add('// per-API test needs it directly.');
    Lines.Add('var _ = json.Marshal');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ExportedName := MakeExportedGoIdent(ApiName);
      SmokeBody := BuildServiceTestJSONBody(F.Params);

      Lines.Add('// TestLocal_' + ExportedName.Text + ' exercises the ' + ApiName.Text + ' stub via LocalCall.');
      if Length(F.Params) = 0 then
        Lines.Add('// It calls with an empty argument list ({"args": []}).')
      else
        Lines.Add('// It calls with the per-type defaults: ' + SmokeBody.Text + '.');
      Lines.Add('func TestLocal_' + ExportedName.Text + '(t *testing.T) {');
      Lines.Add('    env := localCall(t, ' + GoStringLit(ApiName).Text + ', ' +
        GoStringLit(SmokeBody).Text + ')');
      Lines.Add('    checkEnvelope(t, ' + GoStringLit(ApiName).Text + ', env)');
      Lines.Add('}');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('// No supported routines were found in the source unit.');
      Lines.Add('');
    end;

    Result := Lines;
    Log(PFormat('Generated service smoke test: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// CALL-SIDE END-TO-END TEST
// =============================================================================

function GenerateHTTPCallGoTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, PackageName, CallFileName, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, ExportedName, DefaultArgs: TP_String;
  HasParams: boolean;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallGoTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallGoTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  PackageName := MakeGoPackageName(UnitName) + '_call';
  CallFileName := NormalizedUnit + '_http_json_call_go.go';
  TestFileName := NormalizedUnit + '_http_json_call_main_test.go';

  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('// Auto-generated by http_go_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side end-to-end test for the generated Go HTTP/JSON client.');
    Lines.Add('//');
    Lines.Add('// What this program does:');
    Lines.Add('//   For every supported API, issues BOTH the sync variant and the');
    Lines.Add('//   async variant. Any failure fails the test.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * This file must sit next to ' + CallFileName.Text + '.');
    Lines.Add('//     Both files are `package ' + PackageName.Text + '`.');
    Lines.Add('//   * A running bridge.py must be reachable at the default base URL');
    Lines.Add('//     (http://127.0.0.1:8081/<unit>).');
    Lines.Add('//   * A running service (any language) must be registered on the');
    Lines.Add('//     same endpoint.');
    Lines.Add('//');
    Lines.Add('// How to use:');
    Lines.Add('//   python3 bridge.py --endpoint ipc:' + NormalizedUnit.Text + '_http_json \\');
    Lines.Add('//       --port 8081 --no-precheck');
    Lines.Add('//   cp ' + TestFileName.Text + ' call_test.go');
    Lines.Add('//   go test -v');
    Lines.Add('');
    Lines.Add('package ' + PackageName.Text);
    Lines.Add('');
    Lines.Add('import (');
    Lines.Add('    "context"');
    Lines.Add('    "testing"');
    Lines.Add('    "time"');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('// asyncWait is the per-call deadline used by the async tests.');
    Lines.Add('const asyncWait = 30 * time.Second');
    Lines.Add('');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ExportedName := MakeExportedGoIdent(ApiName);
      DefaultArgs := BuildGoDefaultArgList(F.Params);
      HasParams := Length(F.Params) > 0;

      // Sync test
      Lines.Add('// TestCall_' + ExportedName.Text + '_Sync exercises ' + ApiName.Text +
        ' through the synchronous HTTP path.');
      Lines.Add('func TestCall_' + ExportedName.Text + '_Sync(t *testing.T) {');
      if HasParams then
      begin
        if F.IsFunction then
          Lines.Add('    _, err := ' + ExportedName.Text + '(' + DefaultArgs.Text + ')')
        else
          Lines.Add('    err := ' + ExportedName.Text + '(' + DefaultArgs.Text + ')');
      end
      else
      begin
        if F.IsFunction then
          Lines.Add('    _, err := ' + ExportedName.Text + '()')
        else
          Lines.Add('    err := ' + ExportedName.Text + '()');
      end;
      Lines.Add('    if err != nil {');
      Lines.Add('        t.Fatalf("' + ApiName.Text + ' (sync): %v", err)');
      Lines.Add('    }');
      Lines.Add('}');
      Lines.Add('');

      // Async test
      Lines.Add('// TestCall_' + ExportedName.Text + '_Async exercises ' + ApiName.Text +
        ' through the asynchronous HTTP path.');
      Lines.Add('func TestCall_' + ExportedName.Text + '_Async(t *testing.T) {');
      Lines.Add('    ctx, cancel := context.WithTimeout(context.Background(), asyncWait)');
      Lines.Add('    defer cancel()');
      if HasParams then
        Lines.Add('    ch := ' + ExportedName.Text + 'Async(ctx, ' + DefaultArgs.Text + ')')
      else
        Lines.Add('    ch := ' + ExportedName.Text + 'Async(ctx)');
      Lines.Add('    r := <-ch');
      Lines.Add('    if r.Err != nil {');
      Lines.Add('        t.Fatalf("' + ApiName.Text + ' (async): %v", r.Err)');
      Lines.Add('    }');
      Lines.Add('}');
      Lines.Add('');
    end;

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('// No supported routines were found in the source unit.');
      Lines.Add('');
    end;

    Result := Lines;
    Log(PFormat('Generated call e2e test: %d lines, %d routines (sync + async).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'go', 'Go HTTP/JSON service test program',
    asService, akTestCode,
    '_http_json_service_main_test.go', False,
    @GenerateHTTPServiceGoTestCode);
  RegisterCodeGenEntry(
    'go', 'Go HTTP/JSON call test program',
    asCall, akTestCode,
    '_http_json_call_main_test.go', False,
    @GenerateHTTPCallGoTestCode);
end.
