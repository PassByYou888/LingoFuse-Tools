unit http_csharp_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceCsharpTestCode - generate the service-side test
// program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServiceCsharpTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallCsharpTestCode - generate the call-side test
// program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPCallCsharpTestCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_csharp_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_csharp_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type family classification (mirrors every HTTP/JSON generator in
// this toolchain).
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

// ABI_Type_To_CSharp_Decl - C# type name for a parameter or a return value.
function ABI_Type_To_CSharp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'int'
  else if T.Same('int64') then
    Result := 'long'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'uint'
  else if T.Same('word') then
    Result := 'ushort'
  else if T.Same('smallint') then
    Result := 'short'
  else if T.Same('byte') then
    Result := 'byte'
  else if T.Same('uint64') then
    Result := 'ulong'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if ABI_Type_Is_String(T) then
    Result := 'string'
  else
    Result := '';
end;

// ABI_Type_To_CSharp_Default_Literal - default argument used in the
// call-side test.
function ABI_Type_To_CSharp_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if T.Same('single') then
    Result := '0.0f'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else
    Result := '0';
end;

// ABI_Type_To_Json_Default_Literal - JSON literal used in the service
// test's smoke request envelopes.
function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else
    Result := '0';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsCSharpKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('base') or
    S.Same('bool') or S.Same('break') or S.Same('byte') or
    S.Same('case') or S.Same('catch') or S.Same('char') or
    S.Same('checked') or S.Same('class') or S.Same('const') or
    S.Same('continue') or S.Same('decimal') or S.Same('default') or
    S.Same('delegate') or S.Same('do') or S.Same('double') or
    S.Same('else') or S.Same('enum') or S.Same('event') or
    S.Same('explicit') or S.Same('extern') or S.Same('false') or
    S.Same('finally') or S.Same('fixed') or S.Same('float') or
    S.Same('for') or S.Same('foreach') or S.Same('goto') or
    S.Same('if') or S.Same('implicit') or S.Same('in') or
    S.Same('int') or S.Same('interface') or S.Same('internal') or
    S.Same('is') or S.Same('lock') or S.Same('long') or
    S.Same('namespace') or S.Same('new') or S.Same('null') or
    S.Same('object') or S.Same('operator') or S.Same('out') or
    S.Same('override') or S.Same('params') or S.Same('private') or
    S.Same('protected') or S.Same('public') or S.Same('readonly') or
    S.Same('ref') or S.Same('return') or S.Same('sbyte') or
    S.Same('sealed') or S.Same('short') or S.Same('sizeof') or
    S.Same('stackalloc') or S.Same('static') or S.Same('string') or
    S.Same('struct') or S.Same('switch') or S.Same('this') or
    S.Same('throw') or S.Same('true') or S.Same('try') or
    S.Same('typeof') or S.Same('uint') or S.Same('ulong') or
    S.Same('unchecked') or S.Same('unsafe') or S.Same('ushort') or
    S.Same('using') or S.Same('virtual') or S.Same('void') or
    S.Same('volatile') or S.Same('while');
end;

function MakeSafeCSharpParamName(const Name: TP_String; Index: integer): TP_String;
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

  if IsCSharpKeyword(Result) then
    Result := Result + '_';
end;

// CSharpStrLit - emit a complete C# string literal with surrounding
// double quotes and standard backslash escapes.
function CSharpStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
    begin
      Result.Append('\');
      Result.Append('"');
    end
    else if c = '\' then
    begin
      Result.Append('\');
      Result.Append('\');
    end
    else if c = #10 then
    begin
      Result.Append('\');
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append('\');
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append('\');
      Result.Append('t');
    end
    else if c = #0 then
    begin
      Result.Append('\');
      Result.Append('0');
    end
    else
      Result.Append(c);
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
      // Skip CR.
    else
      Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

// -----------------------------------------------------------------------------
// Supported-function filtering (mirrors every HTTP/JSON generator)
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

// BuildDisambiguatedApiNames - apply the same overload-suffix logic
// every other generator uses, so the tests reference the same names
// the generated service/call modules export.
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

// BuildCSharpDefaultArgList - "0, 0.0, \"\"" for a parameter list.
function BuildCSharpDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + ABI_Type_To_CSharp_Default_Literal(Params[i].PascalType);
  end;
end;

// BuildSmokeJsonArgs - the JSON text inside "args": [ ... ] for the
// smoke test. Returns just the array body (without the outer brackets
// already provided by the caller).
function BuildSmokeJsonArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + ABI_Type_To_Json_Default_Literal(Params[i].PascalType);
  end;
end;

// ============================================================================
// SERVICE-SIDE TEST PROGRAM GENERATOR
// ============================================================================
//
// The service-side test program is intentionally NOT extended with an
// async block. Its --smoke mode uses AppHandle.LocalCall, which
// invokes the registered handler synchronously on the calling thread,
// with caller-owned input and output handles. That is the correct
// model for verifying that a stub is reachable and produces a
// well-formed JSON response; it does not exercise the client-side
// async machinery. The client-side test program (below) covers the
// async path.

function GenerateHTTPServiceCsharpTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, Endpoint, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  SmokeArgs: TP_String;
  CallArgs: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCsharpTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCsharpTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_service';
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  FileName := NormalizedUnit + '_http_json_service_main_test___.cs';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by http_csharp_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Service-side test program for the C# HTTP/JSON service.');
    Lines.Add('//');
    Lines.Add('// This file is meant to be compiled alongside');
    Lines.Add('// ' + NormalizedUnit.Text + '_http_json_service.cs. Its only job is to');
    Lines.Add('// provide a Main() that:');
    Lines.Add('//');
    Lines.Add('//   * in the default mode: starts the service and blocks until');
    Lines.Add('//     Ctrl+C;');
    Lines.Add('//   * in the --smoke mode: runs an in-process LocalCall round trip');
    Lines.Add('//     through every registered API, without starting the LingoFuse');
    Lines.Add('//     mesh and without needing the bridge to be running.');
    Lines.Add('//');
    Lines.Add('// How to use:');
    Lines.Add('//');
    Lines.Add('//   dotnet new console -o ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('//   cd ' + NormalizedUnit.Text + '_service_test');
    Lines.Add('//   cp ../' + NormalizedUnit.Text + '_http_json_service.cs .');
    Lines.Add('//   cp ../' + FileName.Text + ' Program.cs');
    Lines.Add('//   dotnet add reference ../LingoFuse/LingoFuse.csproj');
    Lines.Add('//   cp ../LingoFuse64.dll .                  # Windows, or .so / .dylib');
    Lines.Add('//   dotnet run                              # start the service');
    Lines.Add('//   dotnet run -- --smoke                   # run the smoke test');
    Lines.Add('//');
    Lines.Add('// Expected output (default mode):');
    Lines.Add('//');
    Lines.Add('//   === ' + AppName.Text + ' HTTP/JSON service test ===');
    Lines.Add('//   Endpoint: ' + Endpoint.Text);
    Lines.Add('//   API count: N');
    Lines.Add('//   === ' + AppName.Text + ' HTTP/JSON service ===');
    Lines.Add('//   Endpoint: ' + Endpoint.Text);
    Lines.Add('//   [OK] Service ready. Press Ctrl+C to stop.');
    Lines.Add('//   ...');
    Lines.Add('//   Shutting down...');
    Lines.Add('//');
    Lines.Add('// Expected output (--smoke mode):');
    Lines.Add('//');
    Lines.Add('//   === ' + AppName.Text + ' HTTP/JSON service test ===');
    Lines.Add('//   Endpoint: ' + Endpoint.Text);
    Lines.Add('//   API count: N');
    Lines.Add('//   [smoke] Running in-process LocalCall round trip for every API.');
    Lines.Add('//   [smoke] This does NOT start LingoFuse and does NOT need');
    Lines.Add('//   [smoke] the bridge to be running.');
    Lines.Add('//');
    Lines.Add('//     Add: OK');
    Lines.Add('//     Sub: OK');
    Lines.Add('//     ...');
    Lines.Add('//');
    Lines.Add('//   === Smoke test summary ===');
    Lines.Add('//   Passed: N');
    Lines.Add('//   Failed: 0');
    Lines.Add('//');
    Lines.Add('// Target framework: .NET 8.0 or later.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('using System;');
    Lines.Add('using System.Text.Json;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName.Text + ';');
    Lines.Add('');
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    private static int Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("=== " + AppInfo.Name + " HTTP/JSON service test ===");');
    Lines.Add('        Console.WriteLine("Endpoint: " + AppInfo.Endpoint);');
    Lines.Add('        Console.WriteLine("API count: ' + MdInt(Length(SupportedFuncs)).Text + '");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        if (args.Length > 0 && args[0] == "--smoke")');
    Lines.Add('            return RunSmokeTest();');
    Lines.Add('');
    Lines.Add('        // Default mode: start the service and block until Ctrl+C.');
    Lines.Add('        // Service.RunService() installs its own Ctrl+C handler and');
    Lines.Add('        // performs the full LingoFuse startup / shutdown sequence.');
    Lines.Add('        try');
    Lines.Add('        {');
    Lines.Add('            int rc = Service.RunService();');
    Lines.Add('            Console.WriteLine("[OK] Service stopped cleanly.");');
    Lines.Add('            return rc;');
    Lines.Add('        }');
    Lines.Add('        catch (Exception ex)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] Service.RunService threw: " + ex);');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // Smoke test
    // -------------------------------------------------------------------------
    Lines.Add('    // ----------------------------------------------------------------');
    Lines.Add('    // Smoke test');
    Lines.Add('    //');
    Lines.Add('    // Registers every API on a throwaway AppHandle and invokes each');
    Lines.Add('    // one through AppHandle.LocalCall. This exercises the JSON request');
    Lines.Add('    // parsing, the stub invocation, and the JSON response serialization');
    Lines.Add('    // without starting the LingoFuse mesh and without needing the');
    Lines.Add('    // bridge to be running.');
    Lines.Add('    //');
    Lines.Add('    // A callback never throws: it converts any exception into a');
    Lines.Add('    // {"code": -1, "error": "..."} response. So this test counts a call');
    Lines.Add('    // as failed only when the response carries a non-zero code.');
    Lines.Add('    //');
    Lines.Add('    // AppHandle.LocalCall is synchronous by design: it invokes the');
    Lines.Add('    // registered handler on the calling thread, with caller-owned');
    Lines.Add('    // input and output handles. The purpose of the smoke test is to');
    Lines.Add('    // verify stub reachability and JSON round-trip correctness, not');
    Lines.Add('    // to exercise the client-side async machinery.');
    Lines.Add('    // ----------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    private static int RunSmokeTest()');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("[smoke] Running in-process LocalCall round trip for every API.");');
    Lines.Add('        Console.WriteLine("[smoke] This does NOT start LingoFuse and does NOT need");');
    Lines.Add('        Console.WriteLine("[smoke] the bridge to be running.");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        int ok = 0;');
    Lines.Add('        int failed = 0;');
    Lines.Add('');
    Lines.Add('        using var app = new AppHandle(');
    Lines.Add('            AppInfo.Name + "_smoke",');
    Lines.Add('            "In-process smoke test");');
    Lines.Add('        Service.RegisterAPIs(app);');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('        Console.WriteLine("(no APIs to smoke-test)");');
    end
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        SmokeArgs := BuildSmokeJsonArgs(F.Params);

        Lines.Add('        // ---- ' + ApiName.Text + ' ----');
        Lines.Add('        try');
        Lines.Add('        {');
        Lines.Add('            var resp = SmokeCall(app, ' + CSharpStrLit(ApiName) + ',');
        if SmokeArgs = '' then
          Lines.Add('                "{}");')
        else
          Lines.Add('                ' + CSharpStrLit('{"args": [' + SmokeArgs + ']}') + ');');
        Lines.Add('            if (ResponseCodeIsOk(resp))');
        Lines.Add('            {');
        Lines.Add('                Console.WriteLine("  ' + ApiName.Text + ': OK");');
        Lines.Add('                ok++;');
        Lines.Add('            }');
        Lines.Add('            else');
        Lines.Add('            {');
        Lines.Add('                Console.Error.WriteLine(');
        Lines.Add('                    "  ' + ApiName.Text + ': non-zero code: " + resp);');
        Lines.Add('                failed++;');
        Lines.Add('            }');
        Lines.Add('        }');
        Lines.Add('        catch (Exception ex)');
        Lines.Add('        {');
        Lines.Add('            Console.Error.WriteLine(');
        Lines.Add('                "  ' + ApiName.Text + ': FAILED: " + ex.Message);');
        Lines.Add('            failed++;');
        Lines.Add('        }');
        Lines.Add('');
      end;
    end;

    Lines.Add('        Console.WriteLine();');
    Lines.Add('        Console.WriteLine("=== Smoke test summary ===");');
    Lines.Add('        Console.WriteLine("Passed: " + ok);');
    Lines.Add('        Console.WriteLine("Failed: " + failed);');
    Lines.Add('        return failed == 0 ? 0 : 1;');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    // ----------------------------------------------------------------');
    Lines.Add('    // Smoke helpers');
    Lines.Add('    // ----------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('    private static string SmokeCall(AppHandle app, string apiName,');
    Lines.Add('        string requestJson)');
    Lines.Add('    {');
    Lines.Add('        using var param = new DataHandle(apiName);');
    Lines.Add('        param.WriteString(requestJson);');
    Lines.Add('');
    Lines.Add('        using var resp = app.LocalCall(param);');
    Lines.Add('        if (resp.Size == 0)');
    Lines.Add('            return "";');
    Lines.Add('');
    Lines.Add('        resp.Position = 0;');
    Lines.Add('        return resp.ReadString();');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    private static bool ResponseCodeIsOk(string json)');
    Lines.Add('    {');
    Lines.Add('        if (string.IsNullOrEmpty(json))');
    Lines.Add('            return false;');
    Lines.Add('        try');
    Lines.Add('        {');
    Lines.Add('            using var doc = JsonDocument.Parse(json);');
    Lines.Add('            if (!doc.RootElement.TryGetProperty("code", out var code))');
    Lines.Add('                return false;');
    Lines.Add('            if (code.ValueKind == JsonValueKind.Number)');
    Lines.Add('                return code.GetInt32() == 0;');
    Lines.Add('            if (code.ValueKind == JsonValueKind.String)');
    Lines.Add('                return int.TryParse(code.GetString(), out var v) && v == 0;');
    Lines.Add('            return false;');
    Lines.Add('        }');
    Lines.Add('        catch');
    Lines.Add('        {');
    Lines.Add('            return false;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated C# service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    // Lines is returned to the caller; not freed here.
  end;
end;

// ============================================================================
// CALL-SIDE TEST PROGRAM GENERATOR
// ============================================================================

function GenerateHTTPCallCsharpTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, DefaultBaseUrl, DefaultEndpoint, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, ArgList, RetType: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  HasParams: boolean;
  AsyncAsyncResultType: TP_String;
  AsyncExtraSep: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallCsharpTestCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallCsharpTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_call';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;
  DefaultEndpoint := 'ipc:' + NormalizedUnit + '_http_json';
  FileName := NormalizedUnit + '_http_json_call_main_test___.cs';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // -------------------------------------------------------------------------
    // File header
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by http_csharp_abi_test_generator_tool.pas.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Call-side test program for the C# HTTP/JSON call client.');
    Lines.Add('//');
    Lines.Add('// This file is meant to be compiled alongside');
    Lines.Add('// ' + NormalizedUnit.Text + '_http_json_call.cs. It initializes');
    Lines.Add('// LingoFuse as a pure consumer, then exercises BOTH the');
    Lines.Add('// synchronous and the asynchronous call path for every generated');
    Lines.Add('// API. It prints OK / FAILED per call and a summary at the end.');
    Lines.Add('//');
    Lines.Add('// Sync blocks:  wrapped in try/catch on HTTPCallError.');
    Lines.Add('// Async blocks: use TaskCompletionSource<API.<ApiName>AsyncResult>,');
    Lines.Add('//               submitted through API.<ApiName>Async(...), and waited');
    Lines.Add('//               on for up to 30 seconds.');
    Lines.Add('//');
    Lines.Add('// Prerequisites:');
    Lines.Add('//   * The bridge (bridge.py) must be running and reachable through');
    Lines.Add('//     the LingoFuse endpoint.');
    Lines.Add('//   * The matching service must be running on the same endpoint.');
    Lines.Add('//');
    Lines.Add('// How to use:');
    Lines.Add('//');
    Lines.Add('//   dotnet new console -o ' + NormalizedUnit.Text + '_call_test');
    Lines.Add('//   cd ' + NormalizedUnit.Text + '_call_test');
    Lines.Add('//   cp ../' + NormalizedUnit.Text + '_http_json_call.cs .');
    Lines.Add('//   cp ../' + FileName.Text + ' Program.cs');
    Lines.Add('//   dotnet add reference ../LingoFuse/LingoFuse.csproj');
    Lines.Add('//   dotnet run');
    Lines.Add('//');
    Lines.Add('// Optional command-line arguments:');
    Lines.Add('//');
    Lines.Add('//   dotnet run -- <base_url> <endpoint>');
    Lines.Add('//');
    Lines.Add('// Defaults:');
    Lines.Add('//   <base_url> : ' + DefaultBaseUrl.Text);
    Lines.Add('//   <endpoint> : ' + DefaultEndpoint.Text);
    Lines.Add('//');
    Lines.Add('// Expected output:');
    Lines.Add('//');
    Lines.Add('//   === ' + UnitName.Text + ' HTTP/JSON call test ===');
    Lines.Add('//   Base URL: ' + DefaultBaseUrl.Text);
    Lines.Add('//   Endpoint: ' + DefaultEndpoint.Text);
    Lines.Add('//');
    Lines.Add('//     Add [sync] : OK');
    Lines.Add('//     Add [async]: OK');
    Lines.Add('//     Sub [sync] : OK');
    Lines.Add('//     Sub [async]: OK');
    Lines.Add('//     ...');
    Lines.Add('//');
    Lines.Add('//   === Summary ===');
    Lines.Add('//   Passed: N');
    Lines.Add('//   Failed: 0');
    Lines.Add('//');
    Lines.Add('// Target framework: .NET 8.0 or later.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('using System;');
    Lines.Add('using System.Threading.Tasks;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName.Text + ';');
    Lines.Add('');
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    private static int Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("=== ' + UnitName.Text + ' HTTP/JSON call test ===");');
    Lines.Add('');
    Lines.Add('        string baseUrl = args.Length > 0 && !string.IsNullOrEmpty(args[0])');
    Lines.Add('            ? args[0]');
    Lines.Add('            : ' + CSharpStrLit(DefaultBaseUrl) + ';');
    Lines.Add('        string endpoint = args.Length > 1 && !string.IsNullOrEmpty(args[1])');
    Lines.Add('            ? args[1]');
    Lines.Add('            : ' + CSharpStrLit(DefaultEndpoint) + ';');
    Lines.Add('');
    Lines.Add('        Console.WriteLine("Base URL: " + baseUrl);');
    Lines.Add('        Console.WriteLine("Endpoint: " + endpoint);');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        // ---- Initialize LingoFuse as a pure consumer ----');
    Lines.Add('        Framework.SetOption("Wait_Connection_ReadyOk", "True");');
    Lines.Add('        Framework.SetOption("Overlap_Connection", "True");');
    Lines.Add('        Framework.ResetPrepare();');
    Lines.Add('        Framework.PrepareClient(endpoint, null);');
    Lines.Add('');
    Lines.Add('        if (Framework.PrepareDone() != 1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] LingoFuse initialization failed.");');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        HttpJsonCallConfig.BaseUrl = baseUrl;');
    Lines.Add('');
    Lines.Add('        // Give the mesh a moment to learn about the bridge and the');
    Lines.Add('        // service. In deployment mode the first call can race with the');
    Lines.Add('        // broadcast.');
    Lines.Add('        System.Threading.Thread.Sleep(1000);');
    Lines.Add('');
    Lines.Add('        int ok = 0;');
    Lines.Add('        int failed = 0;');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('        Console.WriteLine("(no APIs to test)");');
    end
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        ArgList := BuildCSharpDefaultArgList(F.Params);
        RetType := '';
        HasParams := Length(F.Params) > 0;

        if F.IsFunction then
          RetType := 'var _r = ';

        // ---- Sync block ----
        Lines.Add('        // ---- ' + ApiName.Text + ' [sync] ----');
        Lines.Add('        try');
        Lines.Add('        {');
        Lines.Add('            ' + RetType + 'API.' + ApiName + '(' + ArgList + ');');
        Lines.Add('            Console.WriteLine("  ' + ApiName.Text + ' [sync] : OK");');
        Lines.Add('            ok++;');
        Lines.Add('        }');
        Lines.Add('        catch (HTTPCallError e)');
        Lines.Add('        {');
        Lines.Add('            Console.Error.WriteLine(');
        Lines.Add('                "  ' + ApiName.Text + ' [sync] : FAILED: " + e.Message +');
        Lines.Add('                " (code=" + e.Code + ", http=" + e.HttpStatus + ")");');
        Lines.Add('            failed++;');
        Lines.Add('        }');
        Lines.Add('');

        // ---- Async block ----
        AsyncAsyncResultType := ApiName + 'AsyncResult';
        if HasParams then
          AsyncExtraSep := ', '
        else
          AsyncExtraSep := '';

        Lines.Add('        // ---- ' + ApiName.Text + ' [async] ----');
        Lines.Add('        {');
        Lines.Add('            var tcs = new TaskCompletionSource<' + AsyncAsyncResultType + '>(');
        Lines.Add('                TaskCreationOptions.RunContinuationsAsynchronously);');
        Lines.Add('            API.' + ApiName + 'Async(' + ArgList + AsyncExtraSep +
          'r => tcs.TrySetResult(r));');
        Lines.Add('            if (tcs.Task.Wait(TimeSpan.FromSeconds(30)))');
        Lines.Add('            {');
        Lines.Add('                var r = tcs.Task.Result;');
        Lines.Add('                if (r.Ok)');
        Lines.Add('                {');
        Lines.Add('                    Console.WriteLine("  ' + ApiName.Text + ' [async]: OK");');
        Lines.Add('                    ok++;');
        Lines.Add('                }');
        Lines.Add('                else');
        Lines.Add('                {');
        Lines.Add('                    Console.Error.WriteLine(');
        Lines.Add('                        "  ' + ApiName.Text + ' [async]: FAILED: " + (r.Error ?? "unknown") +');
        Lines.Add('                        " (code=" + r.Code + ", http=" + r.HttpStatus + ")");');
        Lines.Add('                    failed++;');
        Lines.Add('                }');
        Lines.Add('            }');
        Lines.Add('            else');
        Lines.Add('            {');
        Lines.Add('                Console.Error.WriteLine(');
        Lines.Add('                    "  ' + ApiName.Text + ' [async]: FAILED: timeout after 30s");');
        Lines.Add('                failed++;');
        Lines.Add('            }');
        Lines.Add('        }');
        Lines.Add('');
      end;
    end;

    Lines.Add('        Console.WriteLine();');
    Lines.Add('        Console.WriteLine("=== Summary ===");');
    Lines.Add('        Console.WriteLine("Passed: " + ok);');
    Lines.Add('        Console.WriteLine("Failed: " + failed);');
    Lines.Add('');
    Lines.Add('        // ---- Clean shutdown in the required order ----');
    Lines.Add('        try { NetworkEvents.Clear(); } catch { }');
    Lines.Add('        try { Framework.ExitMainThread(); } catch { }');
    Lines.Add('        try { Framework.Shutdown(); } catch { }');
    Lines.Add('');
    Lines.Add('        return failed == 0 ? 0 : 1;');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated C# call test program: %d lines, %d routines (sync + async).',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    // Lines is returned to the caller; not freed here.
  end;
end;

initialization
  RegisterCodeGenEntry(
    'csharp', 'C# HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.cs', False,
    @GenerateHTTPServiceCsharpTestCode);
  RegisterCodeGenEntry(
    'csharp', 'C# HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.cs', False,
    @GenerateHTTPCallCsharpTestCode);
end.
