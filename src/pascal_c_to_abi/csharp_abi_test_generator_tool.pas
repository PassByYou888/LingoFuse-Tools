unit csharp_abi_test_generator_tool;


// csharp_abi_test_generator_tool - Standalone test-program generator
// for the C# ABI backend of code_decl_to_abi (rebuild edition).
//
// Given a TPascal_Func_Model (built with Typ_Normalize_Func = tnf_ABI),
// this unit produces three artefacts that turn the raw C# ABI sources
// into two runnable, cross-validating test programs plus a Markdown
// user guide:
//
//   GenerateABIServiceMainTestCsharpCode  ->  <unit>_abi_service_test___.cs
//   GenerateABICallMainTestCsharpCode     ->  <unit>_abi_call_test___.cs
//   GenerateABICsharpTestReadme           ->  <unit>_abi_test_csharp.md
//
// Unlike the legacy generator, this rebuild edition does NOT re-declare
// the P/Invoke layer or the serialization helpers. The generated test
// programs build directly on top of the rebuilt LingoFuse C# interface
// (namespace `LingoFuse`), whose public types are:
//
//   Framework           - process-wide ABI facade.
//   AppHandle           - application container with typed registration.
//   DataHandle          - RAII wrapper over the native data buffer.
//   LingoFuseStatus     - status queue and health checks.
//
// The two test programs are designed to be paired:
//
//   * The SERVICE test starts the ABI service endpoint, registers every
//     generated API, prints "[OK] Service ready", and stays alive until
//     the user presses Enter. It then shuts down cleanly.
//
//   * The CALL test connects to that endpoint, invokes every generated
//     API exactly once using placeholder arguments, prints the result
//     of each call, and prints a pass/fail summary.
//
// ---------------------------------------------------------------------------
// WORKFLOW (documented in the generated files themselves)
// ---------------------------------------------------------------------------
//
//   1. Create two C# console projects.
//
//        dotnet new console -o <unit>_service_test
//        dotnet new console -o <unit>_call_test
//
//   2. Copy the paired modules and test files into the projects.
//
//        cp <unit>_abi_service.cs              <unit>_service_test/
//        cp <unit>_abi_service_test___.cs      <unit>_service_test/Program.cs
//        cp LingoFuse64.dll                    <unit>_service_test/     (Windows)
//
//        cp <unit>_abi_call.cs                 <unit>_call_test/
//        cp <unit>_abi_call_test___.cs         <unit>_call_test/Program.cs
//        cp LingoFuse64.dll                    <unit>_call_test/        (Windows)
//
//   3. Run the service test in one terminal, then the call test in
//      another.
//
//        cd <unit>_service_test && dotnet run
//        cd <unit>_call_test    && dotnet run
//
// The generated test files carry the full instructions in their own
// header comment, so the user does not need the README to get started.
//
// ---------------------------------------------------------------------------
// RELATIONSHIP WITH THE OTHER C# GENERATORS
// ---------------------------------------------------------------------------
//
// This unit is the test-program companion of
// csharp_abi_service_generator_tool and csharp_abi_call_generator_tool.
// The generated test files `using` the namespaces declared by the two
// production modules:
//
//   service test: using <unit>_abi;
//   call    test: using <unit>_abi_call;
//
// Because both production modules use only the public types of the
// LingoFuse C# interface, the test file does not require any special
// assembly configuration beyond what the production modules already
// need. The workflow above (one console project per test) satisfies
// the one-Main-per-project constraint automatically.
//
// ---------------------------------------------------------------------------
// WIRE PROTOCOL
// ---------------------------------------------------------------------------
//
// The test programs speak exactly the same wire protocol as every
// other generator in the toolchain:
//
//   request  = [field1][field2]...[fieldN]
//   response = [status:byte][payload]
//     status = 0x00 -> success
//     status = 0xFF -> error followed by a UTF-8 string message
//
// All comments and status output are in English.
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


  // GenerateABIServiceMainTestCsharpCode - generate the C# ABI service
  // test program.
  //
  // The returned list contains the lines of a self-contained .cs file
  // that declares a Program class with a Main entry point. The file
  // uses the namespace declared by
  // csharp_abi_service_generator_tool. The caller owns the list and
  // must release it with DisposeObject.

function GenerateABIServiceMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICallMainTestCsharpCode - generate the C# ABI call test
// program.
  //
  // The returned list contains the lines of a self-contained .cs file
  // that declares a Program class with a Main entry point. The file
  // uses the namespace declared by csharp_abi_call_generator_tool.
  // Every generated API is invoked once with placeholder arguments; a
  // pass/fail summary is printed at the end.
  //
  // The caller owns the list and must release it with DisposeObject.

function GenerateABICallMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICsharpTestReadme - generate the user-facing test README.
//
// The returned list contains the lines of a Markdown document that
// explains the test workflow, the required directory layout, the
// build commands, the expected output, and the troubleshooting table.
// The caller owns the list and must release it with DisposeObject.

function GenerateABICsharpTestReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[csharp_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;


// -----------------------------------------------------------------------------
// ABI type mapping (mirrors the C# service / call generators)
// -----------------------------------------------------------------------------

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or
    T.Same('unicodestring') or T.Same('tpascalstring') or
    T.Same('tupascalstring') or T.Same('tp_string') or
    T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

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
  else if IsStringABIType(T) then
    Result := 'string'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_CSharp_Decl(T) <> '';
end;


// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
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
// BuildCSharpPlaceholderArgs - arguments used in the call test
//
// Produces a comma-separated argument list with type-appropriate
// placeholder values:
//   string family  -> "test"
//   single         -> 0.0f
//   double family  -> 0.0
//   everything else-> 0
// -----------------------------------------------------------------------------

function BuildCSharpPlaceholderArgs(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then Result := Result + ', ';

    if IsStringABIType(Params[i].PascalType) then
      Result := Result + '"test"'
    else if Params[i].PascalType.Same('single') then
      Result := Result + '0.0f'
    else if Params[i].PascalType.Same('double') or
            Params[i].PascalType.Same('extended') or
            Params[i].PascalType.Same('real') then
      Result := Result + '0.0'
    else
      Result := Result + '0';
  end;
end;


// =============================================================================
// GenerateABIServiceMainTestCsharpCode
// =============================================================================

function GenerateABIServiceMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName: TP_String;
  Lines: TPascalStringList;
  ApiCountStr: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceMainTestCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceMainTestCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C# ABI service test program for unit "%s"',
    [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiCountStr := umlIntToStr(Length(SupportedFuncs));

  Lines := TPascalStringList.Create;
  try
    // =========================================================================
    // 1. File header - user-facing instructions
    // =========================================================================
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by csharp_abi_test_generator_tool (rebuild edition).');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// STANDALONE CONSOLE TEST PROGRAM for the C# ABI SERVICE.');
    Lines.Add('//');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// HOW TO RUN');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('//');
    Lines.Add('//   Step 1: create a new C# console project.');
    Lines.Add('//');
    Lines.Add('//       dotnet new console -o ' + NormalizedUnit + '_service_test');
    Lines.Add('//       cd ' + NormalizedUnit + '_service_test');
    Lines.Add('//');
    Lines.Add('//   Step 2: copy the service module into the project directory.');
    Lines.Add('//');
    Lines.Add('//       cp ' + NormalizedUnit + '_abi_service.cs .');
    Lines.Add('//');
    Lines.Add('//   Step 3: copy this file into the project and OVERWRITE the');
    Lines.Add('//           default Program.cs.');
    Lines.Add('//');
    Lines.Add('//       cp ' + NormalizedUnit + '_abi_service_test___.cs Program.cs');
    Lines.Add('//');
    Lines.Add('//           (Deleting the default Program.cs first is also fine.');
    Lines.Add('//            What matters is that the project contains exactly');
    Lines.Add('//            one Main entry point.)');
    Lines.Add('//');
    Lines.Add('//   Step 4: copy the LingoFuse runtime next to the project.');
    Lines.Add('//');
    Lines.Add('//       cp LingoFuse64.dll .          # Windows');
    Lines.Add('//       cp liblingofuse.so .          # Linux');
    Lines.Add('//       cp liblingofuse.dylib .       # macOS');
    Lines.Add('//');
    Lines.Add('//   Step 5: build and run.');
    Lines.Add('//');
    Lines.Add('//       dotnet run');
    Lines.Add('//');
    Lines.Add('// Expected output:');
    Lines.Add('//');
    Lines.Add('//       === ' + UnitName.Text + ' ABI service test ===');
    Lines.Add('//       [OK] Service ready on ipc:' + AppName + '.');
    Lines.Add('//       [OK] Registered ' + ApiCountStr + ' API(s).');
    Lines.Add('//       [OK] Press Enter to shut down.');
    Lines.Add('//');
    Lines.Add('// While the service is running, open a second terminal and start');
    Lines.Add('// the matching call test:');
    Lines.Add('//');
    Lines.Add('//       cd ../' + NormalizedUnit + '_call_test');
    Lines.Add('//       dotnet run');
    Lines.Add('//');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// WHAT THIS PROGRAM DOES');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('//');
    Lines.Add('//   1. Loads the LingoFuse runtime (lazily, on the first LF_* call).');
    Lines.Add('//   2. Prepares and starts the service endpoint.');
    Lines.Add('//   3. Creates an App and registers every generated API.');
    Lines.Add('//   4. Connects a local client to the endpoint.');
    Lines.Add('//   5. Waits for the user to press Enter.');
    Lines.Add('//   6. Shuts down in the recommended order.');
    Lines.Add('//');
    Lines.Add('// The test uses the namespace ' + NsName + ' declared by the paired');
    Lines.Add('// service module, and the public LingoFuse C# interface (namespace');
    Lines.Add('// `LingoFuse`). The host project must reference the compiled');
    Lines.Add('// LingoFuse assembly, or include its source files. See the companion');
    Lines.Add('// README, section 7.4.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');

    // =========================================================================
    // 2. Usings
    // =========================================================================
    Lines.Add('using System;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName + ';');
    Lines.Add('');

    // =========================================================================
    // 3. Program class
    // =========================================================================
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    private static int Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("=== ' + UnitName.Text + ' ABI service test ===");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        // The service endpoint is derived from the App name that');
    Lines.Add('        // was baked into the paired service module. Every LingoFuse');
    Lines.Add('        // service listens on "ipc:<AppName>".');
    Lines.Add('        string endpoint = "ipc:" + AppInfo.Name;');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 1: reset any previous preparation state.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Framework.ResetPrepare();');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 2: prepare the C4 service on the endpoint.');
    Lines.Add('        //         The same string is used for the local listening');
    Lines.Add('        //         address and for the physics address.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Framework.PrepareService(endpoint, endpoint);');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 3: create the App and register every generated API.');
    Lines.Add('        //         CreateAndRegisterABIApp is emitted by the service');
    Lines.Add('        //         generator and returns a new AppHandle with every');
    Lines.Add('        //         API already registered.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        AppHandle app = Service.CreateAndRegisterABIApp();');
    Lines.Add('        if (app == null)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine(');
    Lines.Add('                "[FATAL] CreateAndRegisterABIApp returned null");');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 4: connect a local client to the endpoint. The second');
    Lines.Add('        //         argument is the AppHandle, so the local client is');
    Lines.Add('        //         automatically bound to this service.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        if (Framework.PrepareClient(endpoint, app) == -1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine(');
    Lines.Add('                "[FATAL] PrepareClient failed (duplicate address?)");');
    Lines.Add('            app.Dispose();');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 5: start the simulated main thread.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        if (Framework.PrepareDone() != 1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] PrepareDone failed");');
    Lines.Add('            Framework.ExitMainThread();');
    Lines.Add('            app.Dispose();');
    Lines.Add('            Framework.Shutdown();');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        Console.WriteLine("[OK] Service ready on " + endpoint + ".");');
    Lines.Add('        Console.WriteLine("[OK] Registered ' + ApiCountStr + ' API(s).");');
    Lines.Add('        Console.WriteLine("[OK] Press Enter to shut down.");');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 6: block until the user presses Enter. During this');
    Lines.Add('        //         window, the service is fully operational and the');
    Lines.Add('        //         paired call test can connect to it.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        string _line;');
    Lines.Add('        while ((_line = Console.ReadLine()) != null)');
    Lines.Add('        {');
    Lines.Add('            if (_line.Trim().Equals("exit", StringComparison.OrdinalIgnoreCase))');
    Lines.Add('                break;');
    Lines.Add('            if (_line.Length == 0)');
    Lines.Add('                break;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 7: shutdown in the recommended order.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Framework.ExitMainThread();');
    Lines.Add('        app.Dispose();');
    Lines.Add('        Framework.Shutdown();');
    Lines.Add('        Console.WriteLine("[OK] Shutdown complete.");');
    Lines.Add('        return 0;');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service test program.', [Lines.Count]));
  finally
    // Lines is returned to the caller; not freed here.
  end;
end;


// =============================================================================
// GenerateABICallMainTestCsharpCode
// =============================================================================

function GenerateABICallMainTestCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, Args: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
  ApiCountStr: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallMainTestCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallMainTestCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi_call';
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C# ABI call test program for unit "%s"',
    [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiCountStr := umlIntToStr(Length(SupportedFuncs));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    // =========================================================================
    // 1. File header - user-facing instructions
    // =========================================================================
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by csharp_abi_test_generator_tool (rebuild edition).');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// STANDALONE CONSOLE TEST PROGRAM for the C# ABI CLIENT.');
    Lines.Add('//');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// HOW TO RUN');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('//');
    Lines.Add('//   Step 1: create a new C# console project.');
    Lines.Add('//');
    Lines.Add('//       dotnet new console -o ' + NormalizedUnit + '_call_test');
    Lines.Add('//       cd ' + NormalizedUnit + '_call_test');
    Lines.Add('//');
    Lines.Add('//   Step 2: copy the call module into the project directory.');
    Lines.Add('//');
    Lines.Add('//       cp ' + NormalizedUnit + '_abi_call.cs .');
    Lines.Add('//');
    Lines.Add('//   Step 3: copy this file into the project and OVERWRITE the');
    Lines.Add('//           default Program.cs.');
    Lines.Add('//');
    Lines.Add('//       cp ' + NormalizedUnit + '_abi_call_test___.cs Program.cs');
    Lines.Add('//');
    Lines.Add('//           (Deleting the default Program.cs first is also fine.');
    Lines.Add('//            What matters is that the project contains exactly');
    Lines.Add('//            one Main entry point.)');
    Lines.Add('//');
    Lines.Add('//   Step 4: copy the LingoFuse runtime next to the project.');
    Lines.Add('//');
    Lines.Add('//       cp LingoFuse64.dll .          # Windows');
    Lines.Add('//       cp liblingofuse.so .          # Linux');
    Lines.Add('//       cp liblingofuse.dylib .       # macOS');
    Lines.Add('//');
    Lines.Add('//   Step 5: start the matching service in another terminal.');
    Lines.Add('//');
    Lines.Add('//       cd ../' + NormalizedUnit + '_service_test');
    Lines.Add('//       dotnet run');
    Lines.Add('//');
    Lines.Add('//           Wait for "[OK] Service ready" before continuing.');
    Lines.Add('//');
    Lines.Add('//   Step 6: build and run this test.');
    Lines.Add('//');
    Lines.Add('//       dotnet run');
    Lines.Add('//');
    Lines.Add('// Expected output (with ' + ApiCountStr + ' generated API(s)):');
    Lines.Add('//');
    Lines.Add('//       === ' + UnitName.Text + ' ABI client test ===');
    Lines.Add('//       [OK] Connected. Calling ' + ApiCountStr + ' API(s).');
    Lines.Add('//       <name> = <value>');
    Lines.Add('//       ...');
    Lines.Add('//       === Summary ===');
    Lines.Add('//       Passed: <n>');
    Lines.Add('//       Failed: <m>');
    Lines.Add('//');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// WHAT THIS PROGRAM DOES');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('//');
    Lines.Add('//   1. Loads the LingoFuse runtime (lazily, on the first LF_* call).');
    Lines.Add('//   2. Prepares a client endpoint and connects.');
    Lines.Add('//   3. Calls every generated API exactly once, using placeholder');
    Lines.Add('//      arguments.');
    Lines.Add('//   4. Prints the result of each call and tracks pass/fail.');
    Lines.Add('//   5. Shuts down cleanly.');
    Lines.Add('//');
    Lines.Add('// The test uses the namespace ' + NsName + ' declared by the paired');
    Lines.Add('// call module, and the public LingoFuse C# interface (namespace');
    Lines.Add('// `LingoFuse`). The host project must reference the compiled');
    Lines.Add('// LingoFuse assembly, or include its source files. See the companion');
    Lines.Add('// README, section 7.4.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');

    // =========================================================================
    // 2. Usings
    // =========================================================================
    Lines.Add('using System;');
    Lines.Add('using LingoFuse;');
    Lines.Add('using ' + NsName + ';');
    Lines.Add('');

    // =========================================================================
    // 3. Program class
    // =========================================================================
    Lines.Add('internal static class Program');
    Lines.Add('{');
    Lines.Add('    private static int Main(string[] args)');
    Lines.Add('    {');
    Lines.Add('        Console.WriteLine("=== ' + UnitName.Text + ' ABI client test ===");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');
    Lines.Add('        // The endpoint is derived from ABI.TargetApp, which the call');
    Lines.Add('        // module exposes as a public static field. It defaults to');
    Lines.Add('        // the name baked into the paired service module.');
    Lines.Add('        string endpoint = "ipc:" + ABI.TargetApp;');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 1: reset any previous preparation state.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Framework.ResetPrepare();');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 2: prepare a client endpoint. null is passed as');
    Lines.Add('        //         the App handle because this client does not expose');
    Lines.Add('        //         any API of its own.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Framework.PrepareClient(endpoint, null);');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 3: start the simulated main thread.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        if (Framework.PrepareDone() != 1)');
    Lines.Add('        {');
    Lines.Add('            Console.Error.WriteLine("[FATAL] PrepareDone failed");');
    Lines.Add('            return 1;');
    Lines.Add('        }');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 4: call every generated API once.');
    Lines.Add('        //');
    Lines.Add('        //         Every call is wrapped in its own try/catch so that');
    Lines.Add('        //         a single failing API does not abort the rest of');
    Lines.Add('        //         the run.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        int _pass = 0;');
    Lines.Add('        int _fail = 0;');
    Lines.Add('');
    Lines.Add('        Console.WriteLine("[OK] Connected. Calling ' + ApiCountStr + ' API(s).");');
    Lines.Add('        Console.WriteLine();');
    Lines.Add('');

    // ---- Per-API call -------------------------------------------------------
    UsedApiNames.Clear;
    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('        // No APIs were generated for this unit.');
      Lines.Add('        Console.WriteLine("[WARN] No APIs were generated for this unit.");');
    end
    else
    begin
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

        Args := BuildCSharpPlaceholderArgs(f.Params);

        Lines.Add('        // ---- ' + ApiName.Text + ' ----');
        Lines.Add('        try');
        Lines.Add('        {');
        if f.IsFunction then
        begin
          Lines.Add('            var _ret_' + ApiName + ' = ABI.' + ApiName
            + '(' + Args + ');');
          Lines.Add('            Console.WriteLine("' + ApiName
            + ' = " + _ret_' + ApiName + ');');
        end
        else
        begin
          Lines.Add('            ABI.' + ApiName + '(' + Args + ');');
          Lines.Add('            Console.WriteLine("' + ApiName + ' OK");');
        end;
        Lines.Add('            _pass++;');
        Lines.Add('        }');
        Lines.Add('        catch (LingoFuseCallException _ex)');
        Lines.Add('        {');
        Lines.Add('            Console.Error.WriteLine("' + ApiName
          + ' CALL-FAILED: " + _ex.Message);');
        Lines.Add('            _fail++;');
        Lines.Add('        }');
        Lines.Add('        catch (LingoFuseException _ex)');
        Lines.Add('        {');
        Lines.Add('            Console.Error.WriteLine("' + ApiName
          + ' SERVICE-ERROR: " + _ex.Message);');
        Lines.Add('            _fail++;');
        Lines.Add('        }');
        Lines.Add('        Console.WriteLine();');
      end;
    end;

    // ---- Summary -----------------------------------------------------------
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 5: print the pass/fail summary.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Console.WriteLine("=== Summary ===");');
    Lines.Add('        Console.WriteLine("Passed: " + _pass);');
    Lines.Add('        Console.WriteLine("Failed: " + _fail);');
    Lines.Add('');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        // Step 6: shutdown in the recommended order.');
    Lines.Add('        // -----------------------------------------------------------------');
    Lines.Add('        Framework.ExitMainThread();');
    Lines.Add('        Framework.Shutdown();');
    Lines.Add('        Console.WriteLine("[OK] Client test complete.");');
    Lines.Add('');
    Lines.Add('        // Exit with a non-zero code when any API failed, so that');
    Lines.Add('        // the test can be driven from a CI script.');
    Lines.Add('        return _fail == 0 ? 0 : 2;');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call test program.', [Lines.Count]));
  finally
    UsedApiNames.Free;
    // Lines is returned to the caller; not freed here.
  end;
end;


// =============================================================================
// README generator
// =============================================================================

function CSharpTestReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

function GenerateABICsharpTestReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsService, NsCall, TargetAppName: TP_String;
  ApiCountStr: TP_String;

  // ---------------------------------------------------------------------------
  // §1. Header
  // ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - C# ABI Test Suite');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `csharp_abi_test_generator_tool.pas`');
    L.Add('> (rebuild edition); this file stays in sync with the generated test');
    L.Add('> programs.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Service test**      : `' + NormalizedUnit + '_abi_service_test___.cs`');
    L.Add('> **Call test**         : `' + NormalizedUnit + '_abi_call_test___.cs`');
    L.Add('> **Target App name**   : `' + TargetAppName + '`');
    L.Add('> **Exposed APIs**      : ' + ApiCountStr);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> build, run, and interpret the C# ABI test suite without');
    L.Add('> reading the source of the test programs.');
    L.Add('');
    L.Add('---');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §2. Overview
  // ---------------------------------------------------------------------------
  procedure EmitOverview;
  begin
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('The C# ABI test suite verifies that the generated service and');
    L.Add('call modules interoperate correctly over the LingoFuse wire');
    L.Add('protocol. It consists of **two independent console programs**:');
    L.Add('');
    L.Add('| Program | Role | File |');
    L.Add('|---------|------|------|');
    L.Add('| **Service test** | Starts the ABI service, registers every API, waits for input. | `' + NormalizedUnit + '_abi_service_test___.cs` |');
    L.Add('| **Call test**    | Connects to the service, invokes every API once, prints a summary. | `' + NormalizedUnit + '_abi_call_test___.cs` |');
    L.Add('');
    L.Add('The two programs are designed to be run **in two separate');
    L.Add('terminals** and to exchange real RPC calls over the loopback IPC');
    L.Add('transport. Running the pair exercises the full stack:');
    L.Add('');
    L.Add('- runtime library loading;');
    L.Add('- endpoint preparation and client attachment;');
    L.Add('- API registration and callback dispatch;');
    L.Add('- little-endian serialization and NUL-framed strings;');
    L.Add('- status-byte handling on both sides;');
    L.Add('- clean shutdown.');
    L.Add('');
    L.Add('### 1.1 Why two programs instead of one');
    L.Add('');
    L.Add('Each program owns a `Main` entry point. A single C# project can');
    L.Add('have exactly one `Main`, so the two tests must live in two');
    L.Add('separate console projects. This mirrors the C++ test layout');
    L.Add('produced by `cpp_abi_cmake_generator_tool`.');
    L.Add('');
    L.Add('### 1.2 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + NormalizedUnit + '_abi_service_test___.cs` | Service test entry point. |');
    L.Add('| `' + NormalizedUnit + '_abi_call_test___.cs` | Call test entry point. |');
    L.Add('| `' + UnitName + '_abi_test_csharp.md` | This README. |');
    L.Add('');
    L.Add('These three files sit alongside the four files produced by the');
    L.Add('paired generators:');
    L.Add('');
    L.Add('| File | Producer |');
    L.Add('|------|----------|');
    L.Add('| `' + NormalizedUnit + '_abi_service.cs` | `csharp_abi_service_generator_tool` |');
    L.Add('| `' + NormalizedUnit + '_abi_service_csharp.md` | `csharp_abi_service_generator_tool` |');
    L.Add('| `' + NormalizedUnit + '_abi_call.cs` | `csharp_abi_call_generator_tool` |');
    L.Add('| `' + NormalizedUnit + '_abi_call_csharp.md` | `csharp_abi_call_generator_tool` |');
    L.Add('');
    L.Add('### 1.3 Dependency on the LingoFuse C# interface');
    L.Add('');
    L.Add('The generated test programs use the public types of the rebuilt');
    L.Add('LingoFuse C# interface (namespace `LingoFuse`):');
    L.Add('');
    L.Add('| Type | Role |');
    L.Add('|------|------|');
    L.Add('| `Framework` | Process-wide ABI facade. |');
    L.Add('| `AppHandle` | Application container with typed registration. |');
    L.Add('| `DataHandle` | RAII wrapper over the native data buffer. |');
    L.Add('| `LingoFuseStatus` | Status queue and health checks. |');
    L.Add('| `LingoFuseCallException` | Remote call failure exception. |');
    L.Add('| `LingoFuseException` | Base exception type. |');
    L.Add('');
    L.Add('The host project must therefore either:');
    L.Add('');
    L.Add('- **reference the compiled LingoFuse assembly**, or');
    L.Add('- **include the LingoFuse source files** in the same project.');
    L.Add('');
    L.Add('See §7.4 for the exact list of files.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Prerequisites
  // ---------------------------------------------------------------------------
  procedure EmitPrerequisites;
  begin
    L.Add('## 2. Prerequisites');
    L.Add('');
    L.Add('| Requirement | Version |');
    L.Add('|-------------|---------|');
    L.Add('| .NET SDK | 5.0 or later (6.0+ recommended) |');
    L.Add('| Target platform | x86_64 or aarch64 |');
    L.Add('| LingoFuse C# interface | The rebuilt C# binding (namespace `LingoFuse`) |');
    L.Add('| LingoFuse runtime | `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` |');
    L.Add('| ZNetV2 runtime | `z_ipc_64.dll` / `libz_ipc_64.so` |');
    L.Add('');
    L.Add('Verify your SDK:');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet --version');
    L.Add('```');
    L.Add('');
    L.Add('Expected output: a version number such as `8.0.100`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §4. Directory layout
  // ---------------------------------------------------------------------------
  procedure EmitDirectoryLayout;
  begin
    L.Add('## 3. Directory Layout');
    L.Add('');
    L.Add('Create a workspace directory that will hold both test projects:');
    L.Add('');
    L.Add('```');
    L.Add(NormalizedUnit + '_tests/');
    L.Add('  ' + NormalizedUnit + '_service_test/');
    L.Add('    ' + NormalizedUnit + '_service_test.csproj');
    L.Add('    Program.cs                             <- copy of the service test file');
    L.Add('    ' + NormalizedUnit + '_abi_service.cs   <- from the service generator');
    L.Add('    LingoFuse64.dll                        <- or .so / .dylib');
    L.Add('    z_ipc_64.dll                           <- or .so');
    L.Add('    // plus the LingoFuse C# interface files (see §7.4)');
    L.Add('  ' + NormalizedUnit + '_call_test/');
    L.Add('    ' + NormalizedUnit + '_call_test.csproj');
    L.Add('    Program.cs                             <- copy of the call test file');
    L.Add('    ' + NormalizedUnit + '_abi_call.cs      <- from the call generator');
    L.Add('    LingoFuse64.dll');
    L.Add('    z_ipc_64.dll');
    L.Add('    // plus the LingoFuse C# interface files (see §7.4)');
    L.Add('```');
    L.Add('');
    L.Add('Both projects must have the native libraries placed in their');
    L.Add('own output directory. They are independent processes and do not');
    L.Add('share memory.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Step 1: build the service test
  // ---------------------------------------------------------------------------
  procedure EmitBuildServiceTest;
  begin
    L.Add('## 4. Step 1: Build the Service Test');
    L.Add('');
    L.Add('### 4.1 Create the project');
    L.Add('');
    L.Add('```bash');
    L.Add('mkdir ' + NormalizedUnit + '_tests');
    L.Add('cd    ' + NormalizedUnit + '_tests');
    L.Add('dotnet new console -o ' + NormalizedUnit + '_service_test');
    L.Add('cd    ' + NormalizedUnit + '_service_test');
    L.Add('```');
    L.Add('');
    L.Add('### 4.2 Copy the module and the test file');
    L.Add('');
    L.Add('```bash');
    L.Add('# Copy the service module produced by the service generator:');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_service.cs .');
    L.Add('');
    L.Add('# Copy the test file and OVERWRITE the default Program.cs:');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_service_test___.cs Program.cs');
    L.Add('```');
    L.Add('');
    L.Add('### 4.3 Add the LingoFuse C# interface');
    L.Add('');
    L.Add('Either add a project reference to the LingoFuse assembly, or copy');
    L.Add('the LingoFuse source files into the project directory. See §7.4.');
    L.Add('');
    L.Add('### 4.4 Copy the native libraries');
    L.Add('');
    L.Add('```bash');
    L.Add('cp ../runtime/LingoFuse64.dll .   # Windows');
    L.Add('cp ../runtime/liblingofuse.so .   # Linux');
    L.Add('cp ../runtime/liblingofuse.dylib . # macOS');
    L.Add('cp ../runtime/z_ipc_64.dll .      # Windows');
    L.Add('cp ../runtime/libz_ipc_64.so .    # Linux');
    L.Add('```');
    L.Add('');
    L.Add('### 4.5 Build and start the service');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName + ' ABI service test ===');
    L.Add('[OK] Service ready on ipc:' + TargetAppName + '.');
    L.Add('[OK] Registered ' + ApiCountStr + ' API(s).');
    L.Add('[OK] Press Enter to shut down.');
    L.Add('```');
    L.Add('');
    L.Add('Leave this terminal open. The service is now listening on the');
    L.Add('IPC endpoint `ipc:' + TargetAppName + '`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §6. Step 2: build the call test
  // ---------------------------------------------------------------------------
  procedure EmitBuildCallTest;
  begin
    L.Add('## 5. Step 2: Build the Call Test');
    L.Add('');
    L.Add('Open a **second terminal**.');
    L.Add('');
    L.Add('### 5.1 Create the project');
    L.Add('');
    L.Add('```bash');
    L.Add('cd ' + NormalizedUnit + '_tests');
    L.Add('dotnet new console -o ' + NormalizedUnit + '_call_test');
    L.Add('cd ' + NormalizedUnit + '_call_test');
    L.Add('```');
    L.Add('');
    L.Add('### 5.2 Copy the module and the test file');
    L.Add('');
    L.Add('```bash');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_call.cs .');
    L.Add('cp ../generated/' + NormalizedUnit + '_abi_call_test___.cs Program.cs');
    L.Add('```');
    L.Add('');
    L.Add('### 5.3 Add the LingoFuse C# interface');
    L.Add('');
    L.Add('Same options as the service test (§7.4). The two projects do not');
    L.Add('share memory, so each project needs its own interface reference');
    L.Add('(or its own copy of the interface source files).');
    L.Add('');
    L.Add('### 5.4 Copy the native libraries');
    L.Add('');
    L.Add('Same files as the service project. The two processes do not');
    L.Add('share memory, so each project needs its own copy.');
    L.Add('');
    L.Add('### 5.5 Build and run');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName + ' ABI client test ===');
    L.Add('[OK] Connected. Calling ' + ApiCountStr + ' API(s).');
    L.Add('');
    L.Add('...');
    L.Add('');
    L.Add('=== Summary ===');
    L.Add('Passed: ' + ApiCountStr);
    L.Add('Failed: 0');
    L.Add('[OK] Client test complete.');
    L.Add('```');
    L.Add('');
    L.Add('A non-zero `Failed` count, or a non-zero process exit code,');
    L.Add('indicates that one or more APIs failed. See §8 for');
    L.Add('troubleshooting.');
    L.Add('');
    L.Add('### 5.6 Stop the service');
    L.Add('');
    L.Add('Return to the first terminal and press Enter. The service');
    L.Add('prints `[OK] Shutdown complete.` and exits.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §7. Expected output
  // ---------------------------------------------------------------------------
  procedure EmitExpectedOutput;
  begin
    L.Add('## 6. Expected Output');
    L.Add('');
    L.Add('### 6.1 Service test');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName + ' ABI service test ===');
    L.Add('[OK] Service ready on ipc:' + TargetAppName + '.');
    L.Add('[OK] Registered ' + ApiCountStr + ' API(s).');
    L.Add('[OK] Press Enter to shut down.');
    L.Add('...');
    L.Add('[OK] Shutdown complete.');
    L.Add('```');
    L.Add('');
    L.Add('### 6.2 Call test');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + UnitName + ' ABI client test ===');
    L.Add('[OK] Connected. Calling ' + ApiCountStr + ' API(s).');
    L.Add('');
    L.Add('...');
    L.Add('');
    L.Add('=== Summary ===');
    L.Add('Passed: ' + ApiCountStr);
    L.Add('Failed: 0');
    L.Add('[OK] Client test complete.');
    L.Add('```');
    L.Add('');
    L.Add('Every API is printed once with its returned value (for');
    L.Add('functions) or with the tag `OK` (for procedures).');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §8. Adding the LingoFuse C# interface
  // ---------------------------------------------------------------------------
  procedure EmitAddingInterface;
  begin
    L.Add('## 7. Adding the LingoFuse C# Interface');
    L.Add('');
    L.Add('Both test projects use the public types of the rebuilt LingoFuse');
    L.Add('C# interface. Two options are available.');
    L.Add('');
    L.Add('### 7.1 Option A — reference the compiled assembly');
    L.Add('');
    L.Add('Add a project reference to the assembly that contains the');
    L.Add('`LingoFuse` namespace:');
    L.Add('');
    L.Add('```xml');
    L.Add('<ItemGroup>');
    L.Add('  <ProjectReference Include="..\\src\\LingoFuse\\LingoFuse.csproj" />');
    L.Add('</ItemGroup>');
    L.Add('```');
    L.Add('');
    L.Add('### 7.2 Option B — include the source files directly');
    L.Add('');
    L.Add('Copy the following files into each test project directory. The');
    L.Add('project SDK glob will pick them up automatically:');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `Framework.cs` | Process-wide ABI facade. |');
    L.Add('| `AppHandle.cs` | Application container with typed registration. |');
    L.Add('| `DataHandle.cs` | RAII wrapper over the native data buffer. |');
    L.Add('| `LfIo.cs` | Unified JSON / string I/O. |');
    L.Add('| `LingoFuseException.cs` | Exception hierarchy. |');
    L.Add('| `NetworkEvents.cs` | Process-global connect / disconnect events. |');
    L.Add('| `LingoFuseStatus.cs` | Status queue and health checks. |');
    L.Add('| `NativeMethods.cs` | P/Invoke declarations. |');
    L.Add('| `NativeTypes.cs` | Opaque handle types and callback delegates. |');
    L.Add('| `Utf8Marshal.cs` | UTF-8 marshalling helpers. |');
    L.Add('');
    L.Add('Both options produce the same `LingoFuse` namespace. Choose');
    L.Add('whichever fits your build topology better.');
    L.Add('');
    L.Add('### 7.3 Runtime library location');
    L.Add('');
    L.Add('The runtime library is resolved by the `DllImportResolver`');
    L.Add('installed by the LingoFuse C# interface, which maps the logical');
    L.Add('name `"LingoFuse"` to:');
    L.Add('');
    L.Add('| Platform | File |');
    L.Add('|----------|------|');
    L.Add('| Windows x64 | `LingoFuse64.dll` |');
    L.Add('| Windows x86 | `LingoFuse32.dll` |');
    L.Add('| Linux / BSD | `liblingofuse.so` |');
    L.Add('| macOS | `liblingofuse.dylib` |');
    L.Add('');
    L.Add('Place the file in the application directory, or on the OS');
    L.Add('loader search path (`PATH` / `LD_LIBRARY_PATH` /');
    L.Add('`DYLD_LIBRARY_PATH`).');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Troubleshooting
  // ---------------------------------------------------------------------------
  procedure EmitTroubleshooting;
  begin
    L.Add('## 8. Troubleshooting');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `DllNotFoundException: LingoFuse64.dll` | Runtime library not on the loader path | Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` into the project output directory. |');
    L.Add('| `BadImageFormatException` | Architecture mismatch | Use the matching runtime for your platform. |');
    L.Add('| `error CS0017: Program has more than one entry point` | Default `Program.cs` was not overwritten | Delete the default `Program.cs`, or overwrite it with the test file. |');
    L.Add('| `error CS0246: type or namespace ''Framework'' not found` | LingoFuse C# interface not added | Add the interface assembly reference, or include its source files (see §7). |');
    L.Add('| `error CS0246: type or namespace ''AppInfo'' not found` | Service module not copied | Copy the service module `.cs` file into the service test project. |');
    L.Add('| `error CS0246: type or namespace ''ABI'' not found` | Call module not copied | Copy the call module `.cs` file into the call test project. |');
    L.Add('| `PrepareDone failed` on the service | Endpoint already in use | Another LingoFuse service is listening on `ipc:' + TargetAppName + '`. Stop it first. |');
    L.Add('| `PrepareDone failed` on the client | Service not yet started | Start the service test first and wait for `[OK] Service ready`. |');
    L.Add('| Every API reports `CALL-FAILED: ... empty response` | App name mismatch | Verify `ABI.TargetApp` and the service `AppInfo.Name` are both `' + TargetAppName + '`. |');
    L.Add('| Every API reports `CALL-FAILED: ... empty response` | Service started but not fully initialised | Wait a second after `[OK] Service ready` and re-run. |');
    L.Add('| One API reports `SERVICE-ERROR: input truncated` | The service rejected the request | Regenerate both sides from the same model so their signatures match. |');
    L.Add('| `Passed: 0 Failed: N` | Client cannot reach the service | Check the troubleshooting rows above. |');
    L.Add('| Process hangs after `[OK] Service ready` | Expected | Press Enter in the service terminal to shut down. |');
    L.Add('| Process hangs on the call test | Service not responding | Ensure the service process is still running. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §10. Self-assessment checklist
  // ---------------------------------------------------------------------------
  procedure EmitSelfAssessment;
  begin
    L.Add('## 9. Self-Assessment Checklist');
    L.Add('');
    L.Add('After reading this document you should be able to answer the');
    L.Add('following questions without consulting the source code. If any');
    L.Add('answer is unclear, re-read the corresponding section.');
    L.Add('');
    L.Add('| # | Question | Section |');
    L.Add('|---|----------|---------|');
    L.Add('| 1 | What are the three files produced by this generator? | §1.2 |');
    L.Add('| 2 | Why must the tests live in two separate projects? | §1.1 |');
    L.Add('| 3 | What does the service test do? | §4.5 |');
    L.Add('| 4 | What does the call test do? | §5.5 |');
    L.Add('| 5 | Why must the module `.cs` be copied into the test project? | §1.2, §3 |');
    L.Add('| 6 | Which endpoint does the service listen on? | §4.5 |');
    L.Add('| 7 | Where must the native library be placed? | §3, §7.3 |');
    L.Add('| 8 | What does the call test print on success? | §6.2 |');
    L.Add('| 9 | How do I stop the service after the test? | §5.6 |');
    L.Add('| 10 | What does a non-zero exit code from the call test mean? | §5.5 |');
    L.Add('| 11 | How do I add the LingoFuse C# interface to the tests? | §7 |');
    L.Add('| 12 | What exceptions does the call test catch? | §5.5 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to run the');
    L.Add('C# ABI test suite.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §11. Reference resources
  // ---------------------------------------------------------------------------
  procedure EmitResources;
  begin
    L.Add('## 10. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| LingoFuse C# interface | Rebuilt C# binding (namespace `LingoFuse`) |');
    L.Add('| `csharp_abi_service_generator_tool.pas` | Generates `' + NormalizedUnit + '_abi_service.cs` |');
    L.Add('| `csharp_abi_call_generator_tool.pas` | Generates `' + NormalizedUnit + '_abi_call.cs` |');
    L.Add('| `pas_abi_service_generator_tool.pas` | Paired Pascal service-side generator |');
    L.Add('| `pas_abi_call_generator_tool.pas` | Paired Pascal call-side generator |');
    L.Add('| `py_abi_service_generator_tool.pas` | Paired Python service-side generator |');
    L.Add('| `py_abi_call_generator_tool.pas` | Paired Python call-side generator |');
    L.Add('| `cpp_abi_service_generator_tool.pas` | Paired C++ service-side generator |');
    L.Add('| `cpp_abi_call_generator_tool.pas` | Paired C++ call-side generator |');
    L.Add('| `cpp_abi_cmake_generator_tool.pas` | Reference CMake + test-program generator |');
    L.Add('| LingoFuse runtime distribution | Native `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` |');
    L.Add('| ZNetV2 repository | `z_ipc_*` binaries |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `csharp_abi_test_generator_tool.pas`');
    L.Add('(rebuild edition).');
    L.Add('');
  end;

// =============================================================================
// Main body
// =============================================================================
begin
  Result := TPascalStringList.Create;

  if Model = nil then
  begin
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: supplied TPascal_Func_Model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: Model.UnitName is empty.');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsService := NormalizedUnit + '_abi';
  NsCall := NormalizedUnit + '_abi_call';
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('GenerateABICsharpTestReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiCountStr := umlIntToStr(Length(SupportedFuncs));

  Log(PFormat('GenerateABICsharpTestReadme: %d valid APIs',
    [Length(SupportedFuncs)]));

  L := Result;
  try
    EmitHeader;
    EmitOverview;
    EmitPrerequisites;
    EmitDirectoryLayout;
    EmitBuildServiceTest;
    EmitBuildCallTest;
    EmitExpectedOutput;
    EmitAddingInterface;
    EmitTroubleshooting;
    EmitSelfAssessment;
    EmitResources;
  finally
    // Result already owns L; nothing to free here.
  end;

  Log(PFormat('GenerateABICsharpTestReadme: %d lines generated', [L.Count]));
end;

end.
