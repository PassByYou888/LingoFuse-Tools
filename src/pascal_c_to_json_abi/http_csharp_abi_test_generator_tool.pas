unit http_csharp_abi_test_generator_tool;

// ============================================================================
// http_csharp_abi_test_generator_tool
// ----------------------------------------------------------------------------
// Test-program generator for the C# HTTP/JSON ABI toolchain.
//
// Consumes a TPascal_Func_Model (Typ_Normalize_Func = tnf_ABI) and
// produces three artifacts:
//
//   1. A service-side test program
//        <Unit>_http_json_service_main_test___.cs
//      Pairs with the service module produced by
//      http_csharp_abi_service_generator_tool.
//
//      Default mode: calls Service.RunService() and blocks until Ctrl+C.
//      --smoke mode: runs an in-process LocalCall round trip through
//      every registered API, without starting the LingoFuse mesh and
//      without needing the bridge to be running.
//
//   2. A call-side test program
//        <Unit>_http_json_call_main_test___.cs
//      Pairs with the call module produced by
//      http_csharp_abi_call_generator_tool.
//
//      Initializes LingoFuse as a pure consumer, then calls every
//      generated API with default arguments, printing OK/FAILED per
//      call and a summary at the end. Requires the bridge and the
//      service to be running.
//
//   3. A README
//        <Unit>_http_json_test_csharp.md
//      Documents both test programs: build commands, expected output,
//      end-to-end test scenarios, and troubleshooting.
//
// DESIGN: Both test programs use the official LingoFuse .NET binding
// (namespace LingoFuse) rather than direct P/Invoke or raw HTTP.
//
//   - AppHandle  : RAII application container.
//   - DataHandle : RAII data buffer.
//   - LfIo       : The single sanctioned JSON/string I/O path.
//   - Framework  : Process-wide lifecycle facade.
//   - NetworkEvents : Process-global connect/disconnect events.
//
// Both test programs are meant to be copied to Program.cs inside a
// fresh `dotnet new console` project:
//
//     dotnet new console -o <unit>_service_test
//     cd <unit>_service_test
//     cp ../<unit>_http_json_service.cs .
//     cp ../<unit>_http_json_service_main_test___.cs Program.cs
//     dotnet run
//
// All comments and status output are in English.
//
// Author: LingoFuse-pasAgent project
// ============================================================================

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

// GenerateHTTPServiceCsharpTestCode - generate the service-side test
// program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServiceCsharpTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCallCsharpTestCode - generate the call-side test
// program. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPCallCsharpTestCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateHTTPCsharpTestReadme - generate the README that documents
// both test programs. The returned list is owned by the caller and
// must be released with DisposeObject.
function GenerateHTTPCsharpTestReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  // Enable verbose logging during generation.
  GenerateCode_LogEnabled: boolean = False;

implementation

// ============================================================================
// Logging helpers
// ============================================================================

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

// ============================================================================
// ABI type family classification (mirrors every HTTP/JSON generator in
// this toolchain).
// ============================================================================

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

// ============================================================================
// Identifier helpers
// ============================================================================

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

// ============================================================================
// Markdown helpers
// ============================================================================

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

// ============================================================================
// Supported-function filtering (mirrors every HTTP/JSON generator)
// ============================================================================

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
    Lines.Add('// LingoFuse as a pure consumer, calls every generated API with');
    Lines.Add('// default arguments, prints OK / FAILED per call, and prints a');
    Lines.Add('// summary at the end.');
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
    Lines.Add('//     Add: OK');
    Lines.Add('//     Sub: OK');
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

        if F.IsFunction then
          RetType := 'var _r = ';

        Lines.Add('        // ---- ' + ApiName.Text + ' ----');
        Lines.Add('        try');
        Lines.Add('        {');
        Lines.Add('            ' + RetType + 'API.' + ApiName + '(' + ArgList + ');');
        Lines.Add('            Console.WriteLine("  ' + ApiName.Text + ': OK");');
        Lines.Add('            ok++;');
        Lines.Add('        }');
        Lines.Add('        catch (HTTPCallError e)');
        Lines.Add('        {');
        Lines.Add('            Console.Error.WriteLine(');
        Lines.Add('                "  ' + ApiName.Text + ': FAILED: " + e.Message +');
        Lines.Add('                " (code=" + e.Code + ", http=" + e.HttpStatus + ")");');
        Lines.Add('            failed++;');
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
    Log(PFormat('Generated C# call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    // Lines is returned to the caller; not freed here.
  end;
end;

// ============================================================================
// README GENERATOR
// ============================================================================

function GenerateHTTPCsharpTestReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsService, NsCall, AppName, Endpoint, BaseUrl: TP_String;
  ServiceCs, CallCs, ServiceTest, CallTest, ReadmeName: TP_String;
  i: integer;
  FuncCount: integer;
  ApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  RetType: TP_String;
  ArgList: TP_String;
  HasParams: boolean;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCsharpTestReadme: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCsharpTestReadme: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsService := NormalizedUnit + '_http_json_service';
  NsCall := NormalizedUnit + '_http_json_call';
  AppName := NormalizedUnit;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  ServiceCs := NormalizedUnit + '_http_json_service.cs';
  CallCs := NormalizedUnit + '_http_json_call.cs';
  ServiceTest := NormalizedUnit + '_http_json_service_main_test___.cs';
  CallTest := NormalizedUnit + '_http_json_call_main_test___.cs';
  ReadmeName := NormalizedUnit + '_http_json_test_csharp.md';

  SupportedFuncs := CollectSupportedFunctions(Model);
  FuncCount := Length(SupportedFuncs);
  ApiNames := TPascalStringList.Create;
  L := TPascalStringList.Create;
  Result := L;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    // =========================================================================
    // Header
    // =========================================================================
    L.Add('# ' + UnitName.Text + ' - C# HTTP/JSON Test Programs');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `http_csharp_abi_test_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated test programs.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName.Text + '`');
    L.Add('> **Service test file** : `' + ServiceTest.Text + '`');
    L.Add('> **Call test file**    : `' + CallTest.Text + '`');
    L.Add('> **Service module**    : `' + ServiceCs.Text + '` (generated separately)');
    L.Add('> **Call module**       : `' + CallCs.Text + '` (generated separately)');
    L.Add('> **Exposed APIs**      : ' + MdInt(FuncCount).Text);
    L.Add('> **Target framework**  : .NET 8.0 or later');
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> build and run the two C# test programs without reading the');
    L.Add('> source.');
    L.Add('');
    L.Add('---');
    L.Add('');

    // =========================================================================
    // 1. Overview
    // =========================================================================
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('This document describes the two C# test programs that pair with');
    L.Add('the C# HTTP/JSON service and call modules:');
    L.Add('');
    L.Add('| Test program | Pairs with | Purpose |');
    L.Add('|--------------|-----------|---------|');
    L.Add('| `' + ServiceTest.Text + '` | `' + ServiceCs.Text + '` | Service-side entry point. Starts the service, or runs an in-process smoke test. |');
    L.Add('| `' + CallTest.Text + '` | `' + CallCs.Text + '` | Client-side driver. Calls every exposed API with default arguments. |');
    L.Add('');
    L.Add('Both test programs are **standalone**: each is meant to be copied');
    L.Add('to `Program.cs` inside a fresh `dotnet new console` project,');
    L.Add('alongside the corresponding module.');
    L.Add('');
    L.Add('The two test programs are **independent**: you can run one without');
    L.Add('the other. They become an end-to-end test only when combined with');
    L.Add('the bridge (see §5).');
    L.Add('');
    L.Add('### 1.1 What each test program does');
    L.Add('');
    L.Add('**Service test** (`' + ServiceTest.Text + '`)');
    L.Add('');
    L.Add('- Default mode: calls `Service.RunService()`, which performs the');
    L.Add('  full LingoFuse startup sequence and blocks until Ctrl+C.');
    L.Add('- `--smoke` mode: registers every API on a throwaway `AppHandle`');
    L.Add('  and invokes each one through `AppHandle.LocalCall`. This');
    L.Add('  exercises the JSON request parsing, the stub invocation, and');
    L.Add('  the JSON response serialization, without starting the LingoFuse');
    L.Add('  mesh.');
    L.Add('');
    L.Add('**Call test** (`' + CallTest.Text + '`)');
    L.Add('');
    L.Add('- Initializes LingoFuse as a pure consumer.');
    L.Add('- Calls every exposed API with default arguments.');
    L.Add('- Prints `OK` or `FAILED: <reason>` per call.');
    L.Add('- Prints a summary line and exits with code 0 (all OK) or 1');
    L.Add('  (any failure).');
    L.Add('');
    L.Add('### 1.2 Files produced by the toolchain');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + ServiceCs.Text + '` | The service module (produced by the service generator). |');
    L.Add('| `' + CallCs.Text + '` | The call module (produced by the call generator). |');
    L.Add('| `' + ServiceTest.Text + '` | The service test program (produced by this generator). |');
    L.Add('| `' + CallTest.Text + '` | The call test program (produced by this generator). |');
    L.Add('| `' + ReadmeName.Text + '` | This README. |');
    L.Add('');

    // =========================================================================
    // 2. Compatibility
    // =========================================================================
    L.Add('## 2. Compatibility');
    L.Add('');
    L.Add('| Requirement | Value |');
    L.Add('|-------------|-------|');
    L.Add('| .NET | 8.0 or later |');
    L.Add('| LingoFuse binding | LingoFuse.dll (namespace `LingoFuse`) |');
    L.Add('| Native LingoFuse library | Installed next to the executable, or on the loader search path |');
    L.Add('');
    L.Add('The **call test** additionally requires the bridge (`bridge.py`)');
    L.Add('and the matching service to be running and reachable through the');
    L.Add('LingoFuse endpoint.');
    L.Add('');
    L.Add('The **service test** in default mode also requires the native');
    L.Add('library and a reachable endpoint. Its `--smoke` mode requires only');
    L.Add('the native library (for `AppHandle` / `LocalCall`).');
    L.Add('');

    // =========================================================================
    // 3. The service test program
    // =========================================================================
    L.Add('## 3. The Service Test Program');
    L.Add('');
    L.Add('### 3.1 Build');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet new console -o ' + NormalizedUnit.Text + '_service_test');
    L.Add('cd ' + NormalizedUnit.Text + '_service_test');
    L.Add('cp ../' + ServiceCs.Text + ' .');
    L.Add('cp ../' + ServiceTest.Text + ' Program.cs');
    L.Add('dotnet add reference ../LingoFuse/LingoFuse.csproj');
    L.Add('cp ../LingoFuse64.dll .            # Windows, or .so / .dylib');
    L.Add('cp ../z_ipc_64.dll .               # Windows, or .so');
    L.Add('```');
    L.Add('');
    L.Add('Before building, **fill in every `InternalCalls.<ApiName>` stub**');
    L.Add('inside `' + ServiceCs.Text + '`. The stubs contain `TODO`');
    L.Add('comments; replace the body of each one with a call to the real');
    L.Add('implementation.');
    L.Add('');
    L.Add('### 3.2 Default mode: run the service');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName.Text + ' HTTP/JSON service test ===');
    L.Add('Endpoint: ' + Endpoint.Text);
    L.Add('API count: ' + MdInt(FuncCount).Text);
    L.Add('');
    L.Add('=== ' + AppName.Text + ' HTTP/JSON service ===');
    L.Add('Endpoint: ' + Endpoint.Text);
    L.Add('[OK] Service ready. Press Ctrl+C to stop.');
    L.Add('```');
    L.Add('');
    L.Add('Press **Ctrl+C** to stop the service. The service performs a');
    L.Add('clean shutdown: stop the simulated main thread, free the App, and');
    L.Add('release the LingoFuse library. The test prints');
    L.Add('`[OK] Service stopped cleanly.` before exiting.');
    L.Add('');
    L.Add('### 3.3 Smoke mode: in-process test');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run -- --smoke');
    L.Add('```');
    L.Add('');
    L.Add('The smoke mode does **not** start the LingoFuse mesh and does');
    L.Add('**not** need the bridge to be running. It only needs the native');
    L.Add('library (for `AppHandle.LocalCall`).');
    L.Add('');
    L.Add('For every exposed API it:');
    L.Add('');
    L.Add('1. Creates a throwaway `AppHandle`.');
    L.Add('2. Registers every API on it via `Service.RegisterAPIs`.');
    L.Add('3. Builds a request `DataHandle` with the API name and a JSON');
    L.Add('   request envelope of default arguments.');
    L.Add('4. Calls `AppHandle.LocalCall` with the request.');
    L.Add('5. Checks whether the response carries `"code": 0`.');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName.Text + ' HTTP/JSON service test ===');
    L.Add('Endpoint: ' + Endpoint.Text);
    L.Add('API count: ' + MdInt(FuncCount).Text);
    L.Add('');
    L.Add('[smoke] Running in-process LocalCall round trip for every API.');
    L.Add('[smoke] This does NOT start LingoFuse and does NOT need');
    L.Add('[smoke] the bridge to be running.');
    L.Add('');
    L.Add('  <ApiName1>: OK');
    L.Add('  <ApiName2>: OK');
    L.Add('  ...');
    L.Add('');
    L.Add('=== Smoke test summary ===');
    L.Add('Passed: ' + MdInt(FuncCount).Text);
    L.Add('Failed: 0');
    L.Add('```');
    L.Add('');
    L.Add('### 3.4 Interpreting smoke-mode failures');
    L.Add('');
    L.Add('A smoke test for one API can fail for two reasons:');
    L.Add('');
    L.Add('- **`non-zero code`** - the callback returned a JSON envelope');
    L.Add('  with a non-zero `code`. This almost always means the');
    L.Add('  corresponding `InternalCalls.<ApiName>` stub was not filled in');
    L.Add('  and threw an exception. Check the stderr output.');
    L.Add('- **`FAILED: <exception>`** - a .NET exception was thrown before');
    L.Add('  the callback could produce a response. This usually means the');
    L.Add('  native library is missing or an argument extraction helper');
    L.Add('  failed.');
    L.Add('');

    // =========================================================================
    // 4. The call test program
    // =========================================================================
    L.Add('## 4. The Call Test Program');
    L.Add('');
    L.Add('### 4.1 Build');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet new console -o ' + NormalizedUnit.Text + '_call_test');
    L.Add('cd ' + NormalizedUnit.Text + '_call_test');
    L.Add('cp ../' + CallCs.Text + ' .');
    L.Add('cp ../' + CallTest.Text + ' Program.cs');
    L.Add('dotnet add reference ../LingoFuse/LingoFuse.csproj');
    L.Add('cp ../LingoFuse64.dll .            # Windows, or .so / .dylib');
    L.Add('```');
    L.Add('');
    L.Add('### 4.2 Run');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('or, with a custom base URL and endpoint:');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run -- ' + BaseUrl.Text + ' ' + Endpoint.Text);
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName.Text + ' HTTP/JSON call test ===');
    L.Add('Base URL: ' + BaseUrl.Text);
    L.Add('Endpoint: ' + Endpoint.Text);
    L.Add('');
    L.Add('  <ApiName1>: OK');
    L.Add('  <ApiName2>: OK');
    L.Add('  ...');
    L.Add('');
    L.Add('=== Summary ===');
    L.Add('Passed: ' + MdInt(FuncCount).Text);
    L.Add('Failed: 0');
    L.Add('```');
    L.Add('');
    L.Add('The test exits with code 0 when every call succeeded, and code 1');
    L.Add('otherwise.');
    L.Add('');
    L.Add('### 4.3 What "OK" means');
    L.Add('');
    L.Add('A call is reported as `OK` when the service returned');
    L.Add('`{"code": 0, ...}`. The test does **not** verify that the');
    L.Add('returned value matches any expected value: it only verifies the');
    L.Add('wire round trip.');
    L.Add('');
    L.Add('### 4.4 Testing against a stub service');
    L.Add('');
    L.Add('The call test can be run even if the service implementation is');
    L.Add('still a stub. The stubs return `0` / `""` / `0.0`, so the call');
    L.Add('test will see `{"code": 0, "result": 0}` and report `OK`. This');
    L.Add('confirms the wire protocol end to end, but not the business');
    L.Add('logic.');
    L.Add('');

    // =========================================================================
    // 5. End-to-end test scenario
    // =========================================================================
    L.Add('## 5. End-to-End Test Scenario');
    L.Add('');
    L.Add('The two test programs become an end-to-end test when combined with');
    L.Add('the bridge. The full setup involves three processes:');
    L.Add('');
    L.Add('```');
    L.Add('  +---------------------+        +--------------+        +---------------------+');
    L.Add('  |  Service test       |  LF    |  bridge.py   |  HTTP  |  Call test          |');
    L.Add('  |  ' + ServiceTest.Text + '  | <----> |  :8081       | <----> |  ' + CallTest.Text + '  |');
    L.Add('  +---------------------+        +--------------+        +---------------------+');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Step 1: start the service');
    L.Add('');
    L.Add('In terminal 1:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd ' + NormalizedUnit.Text + '_service_test');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Wait for the line:');
    L.Add('');
    L.Add('```');
    L.Add('[OK] Service ready. Press Ctrl+C to stop.');
    L.Add('```');
    L.Add('');
    L.Add('### 5.2 Step 2: start the bridge');
    L.Add('');
    L.Add('In terminal 2:');
    L.Add('');
    L.Add('```bash');
    L.Add('python3 bridge.py --endpoint ' + Endpoint.Text + ' \\');
    L.Add('    --port 8081 --no-precheck');
    L.Add('```');
    L.Add('');
    L.Add('Wait for the bridge to report that it is listening on port 8081.');
    L.Add('');
    L.Add('### 5.3 Step 3: run the call test');
    L.Add('');
    L.Add('In terminal 3:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd ' + NormalizedUnit.Text + '_call_test');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('The call test calls every API through the bridge. A successful');
    L.Add('run prints `Passed: ' + MdInt(FuncCount).Text + '` and `Failed: 0`.');
    L.Add('');
    L.Add('### 5.4 Step 4: shut down');
    L.Add('');
    L.Add('Stop the bridge (Ctrl+C in terminal 2), then stop the service');
    L.Add('(Ctrl+C in terminal 1). The service prints');
    L.Add('`[OK] Service stopped cleanly.` before exiting.');
    L.Add('');
    L.Add('### 5.5 Testing without the call test');
    L.Add('');
    L.Add('You can also probe the service from the command line:');
    L.Add('');
    L.Add('```bash');
    L.Add('curl -X POST ' + BaseUrl.Text + '/<api-name> \\');
    L.Add('     -H "Content-Type: application/json" \\');
    L.Add('     -d ''{"args": [1, 2]}''');
    L.Add('```');
    L.Add('');

    // =========================================================================
    // 6. Troubleshooting
    // =========================================================================
    L.Add('## 6. Troubleshooting');
    L.Add('');
    L.Add('### 6.1 Service test');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `DllNotFoundException: LingoFuse64.dll` | Native library missing | Copy the native library next to the executable |');
    L.Add('| `BadImageFormatException` | Architecture mismatch | Use the 64-bit native library with a 64-bit runtime |');
    L.Add('| `PrepareService` returned -1 | Endpoint already in use | Use a different endpoint, or stop the conflicting process |');
    L.Add('| `PrepareDone` returned 0 | Already running | Use `Framework.Shutdown` between cycles |');
    L.Add('| `--smoke` reports non-zero code | A stub was not filled in | Search for `TODO` in the service module |');
    L.Add('');
    L.Add('### 6.2 Call test');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `FAILED: ... code=-1, http=0` | Bridge not running, or the LingoFuse call timed out | Start `bridge.py`; verify the endpoint |');
    L.Add('| `FAILED: ... code=-3` | Bridge pre-check failed | Add `--no-precheck` to the bridge |');
    L.Add('| `FAILED: ... code=-4` | Bridge protocol error | Check the bridge log |');
    L.Add('| `FAILED: ... code=-1, http=200` | Service raised an exception | Check the service console |');
    L.Add('| Every call fails immediately | Endpoint mismatch between the call test and the bridge | Pass the correct endpoint as the second argument |');
    L.Add('');

    // =========================================================================
    // 7. API manifest
    // =========================================================================
    L.Add('## 7. API Manifest');
    L.Add('');
    L.Add('Total exposed APIs: **' + MdInt(FuncCount).Text + '**.');
    L.Add('');

    if FuncCount = 0 then
    begin
      L.Add('_No supported routines were found in the source unit._');
      L.Add('');
    end
    else
    begin
      L.Add('The call test invokes the following APIs with default');
      L.Add('arguments. The service test''s smoke mode uses the same order.');
      L.Add('');
      L.Add('| # | API name | Kind | Default arguments |');
      L.Add('|---|----------|------|-------------------|');

      for i := 0 to High(SupportedFuncs) do
      begin
        f := SupportedFuncs[i];
        ApiName := ApiNames[i];
        ArgList := BuildCSharpDefaultArgList(f.Params);
        if ArgList = '' then
          ArgList := '(none)'
        else
          ArgList := '`' + ArgList + '`';

        if f.IsFunction then
          RetType := 'function'
        else
          RetType := 'procedure';

        L.Add('| ' + MdInt(i + 1).Text +
          ' | `' + ApiName.Text + '`' +
          ' | ' + RetType +
          ' | ' + ArgList + ' |');
      end;

      L.Add('');
    end;

    // =========================================================================
    // 8. For AI Agents
    // =========================================================================
    L.Add('## 8. For AI Agents');
    L.Add('');
    L.Add('```yaml');
    L.Add('artifacts:');
    L.Add('  service_test: ' + ServiceTest.Text);
    L.Add('  call_test: ' + CallTest.Text);
    L.Add('  readme: ' + ReadmeName.Text);
    L.Add('');
    L.Add('pairs_with:');
    L.Add('  service_module: ' + ServiceCs.Text);
    L.Add('  call_module: ' + CallCs.Text);
    L.Add('  service_namespace: ' + NsService.Text);
    L.Add('  call_namespace: ' + NsCall.Text);
    L.Add('');
    L.Add('service_test:');
    L.Add('  default_mode: "calls Service.RunService() and blocks on Ctrl+C"');
    L.Add('  smoke_mode: "dotnet run -- --smoke; in-process LocalCall round trip"');
    L.Add('  needs_bridge: false   # smoke mode only');
    L.Add('  needs_native: true    # both modes');
    L.Add('  exit_codes:');
    L.Add('    "0": "clean run"');
    L.Add('    "1": "fatal or smoke-test failure"');
    L.Add('');
    L.Add('call_test:');
    L.Add('  invocation: "API.<ApiName>(defaults) for every API"');
    L.Add('  needs_bridge: true');
    L.Add('  needs_native: true');
    L.Add('  optional_args: "<base_url> <endpoint>"');
    L.Add('  exit_codes:');
    L.Add('    "0": "every call succeeded"');
    L.Add('    "1": "at least one call failed"');
    L.Add('');
    L.Add('end_to_end:');
    L.Add('  step_1: "cd ' + NormalizedUnit.Text + '_service_test && dotnet run"');
    L.Add('  step_2: "python3 bridge.py --endpoint ' + Endpoint.Text + ' --no-precheck"');
    L.Add('  step_3: "cd ' + NormalizedUnit.Text + '_call_test && dotnet run"');
    L.Add('```');
    L.Add('');
    L.Add('### 8.1 What these test programs do NOT cover');
    L.Add('');
    L.Add('- The **bridge implementation**. See the bridge README.');
    L.Add('- The **LingoFuse runtime**. See the LingoFuse documentation.');
    L.Add('- **Business-logic correctness**. The call test verifies the');
    L.Add('  wire round trip, not the returned value.');
    L.Add('- **Concurrency**. Both tests are single-threaded.');
    L.Add('');

    // =========================================================================
    // 9. Resources
    // =========================================================================
    L.Add('## 9. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| `http_csharp_abi_service_generator_tool.pas` | Service module generator |');
    L.Add('| `http_csharp_abi_call_generator_tool.pas` | Call module generator |');
    L.Add('| `http_csharp_abi_test_generator_tool.pas` | This generator |');
    L.Add('| `http_pas_abi_service_generator_tool.pas` | Paired Pascal service generator |');
    L.Add('| `http_pas_abi_call_generator_tool.pas` | Paired Pascal call generator |');
    L.Add('| `http_py_abi_service_generator_tool.pas` | Paired Python service generator |');
    L.Add('| `http_py_abi_call_generator_tool.pas` | Paired Python call generator |');
    L.Add('| `http_cpp_abi_service_generator_tool.pas` | Paired C++ service generator |');
    L.Add('| `http_cpp_abi_call_generator_tool.pas` | Paired C++ call generator |');
    L.Add('| `http_js_abi_call_generator_tool.pas` | Paired JavaScript call generator |');
    L.Add('| `bridge.py` | HTTP <-> LingoFuse bridge |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `http_csharp_abi_test_generator_tool.pas`');
    L.Add('');

    Log(PFormat('Generated C# test README: %d lines, %d routines.',
      [L.Count, FuncCount]));
  finally
    ApiNames.Free;
    // L is returned to the caller; not freed here.
  end;
end;

end.
