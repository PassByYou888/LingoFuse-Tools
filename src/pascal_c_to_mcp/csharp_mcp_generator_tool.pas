unit csharp_mcp_generator_tool;

{*******************************************************************************
 * csharp_mcp_generator_tool - LingoFuse C# Tool Provider Code & Doc Generator
 *
 * C# analogue of py_mcp_generator_tool. Consumes one TPascal_Func_Model and
 * produces THREE artifacts:
 *
 *   1. GenerateCSharpCode()        -> <unit>_tool_provider.cs
 *      The provider class. Registers every supported top-level routine as a
 *      LingoFuse Call API and advertises each API as an MCP tool through the
 *      beacon. Contains NO Main method, so it can be reused by any host.
 *
 *   2. GenerateCSharpTestProgram() -> <unit>_tool_provider_test.cs
 *      A runnable test entry point. Contains the single Main method that
 *      drives the provider through the entire lifecycle:
 *          load -> register APIs -> connect -> register tools -> wait ->
 *          shutdown cleanly.
 *      Place it in the same project as the provider file.
 *
 *   3. GenerateCSharpReadme()      -> <unit>_tool_provider_csharp.md
 *      An English Markdown user guide covering: the 4-step startup order
 *      (beacon -> provider -> mcp_api_tool -> agent), environment setup,
 *      build, run, tool reference, troubleshooting, and portability.
 *
 * =============================================================================
 * STARTUP ORDER (fixed, must be respected)
 * =============================================================================
 *
 *      Step 1   Start the beacon      : pascal_agent_service.exe
 *      Step 2   Start this provider   : dotnet run
 *      Step 3   Start the MCP gateway : python mcp_api_tool.py
 *      Step 4   Connect the agent     : LM Studio / Claude Desktop / ...
 *
 * =============================================================================
 * .NET BINDING SOURCING POLICY
 * =============================================================================
 * The generated C# source depends on the `LingoFuse` .NET binding assembly.
 * Two ways to provide it:
 *
 *   Preferred: the standalone `LingoFuse` NuGet package or repository.
 *   Fallback : the binding source shipped inside LingoFuse-pasAgent-v3.
 *
 * =============================================================================
 * NOTES
 * =============================================================================
 *   - Fixed beacon application name: 'agent_main_app'
 *   - Fixed IPC endpoint          : 'ipc:agent'
 *   - Nested routines (NestLevel <> 0) are skipped by the model itself.
 *   - C# string literals iterate with TP_Char (UTF-16) so non-ASCII content
 *     survives code generation.
 *   - Generated code targets .NET 8.0 and uses only the BCL plus LingoFuse.
 *   - All README content is generated in English.
 * ****************************************************************************}

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

{$IFDEF FPC}
  {$CODEPAGE UTF8}
{$ENDIF FPC}

interface

uses
  SysUtils, Classes,
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing;

{* Generate the C# provider class. Caller owns the returned list. *}
function GenerateCSharpCode(Model: TPascal_Func_Model): TPascalStringList;

{* Generate the C# test program (Main entry point). Caller owns the list. *}
function GenerateCSharpTestProgram(Model: TPascal_Func_Model): TPascalStringList;

{* Generate the English Markdown README. Caller owns the returned list. *}
function GenerateCSharpReadme(Model: TPascal_Func_Model): TPascalStringList;

const
  { Enable verbose generation logging (DoStatus). }
  GenerateCode_LogEnabled: boolean = False;

implementation

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const
  DEFAULT_BEACON_APP = 'agent_main_app';
  DEFAULT_REGISTER_API = 'register_agent';
  DEFAULT_AGENT_LOG_API = 'agent_log';
  DEFAULT_IPC_ENDPOINT = 'ipc:agent';

  // -----------------------------------------------------------------------------
  // Logging
  // -----------------------------------------------------------------------------

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[csharp_mcp_generator] %s', [Msg.Text]);
end;

// -----------------------------------------------------------------------------
// Type helpers
// -----------------------------------------------------------------------------

function IsSupportedType(const Typ: TP_String): boolean;
begin
  Result := Typ.Same('int64', 'double', 'string');
end;

function PascalTypeToCSharpType(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := 'long'
  else if Typ.Same('double') then Result := 'double'
  else if Typ.Same('string') then Result := 'string'
  else
    Result := 'object';
end;

function PascalTypeToJsonSchemaType(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := 'integer'
  else if Typ.Same('double') then Result := 'number'
  else if Typ.Same('string') then Result := 'string'
  else
    Result := 'string';
end;

function PascalTypeDefaultValue(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := '0L'
  else if Typ.Same('double') then Result := '0.0'
  else if Typ.Same('string') then Result := 'string.Empty'
  else
    Result := 'null';
end;

function PascalTypeToJsonLiteral(const Typ: TP_String): TP_String;
begin
  if Typ.Same('int64') then Result := '0'
  else if Typ.Same('double') then Result := '0.0'
  else if Typ.Same('string') then Result := '""'
  else
    Result := 'null';
end;

// -----------------------------------------------------------------------------
// C# string literal escaping (UTF-16 safe)
// -----------------------------------------------------------------------------

function CSharpStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then Result := Result + '\"'
    else if c = #92 then Result := Result + '\\'
    else if c = #10 then Result := Result + '\n'
    else if c = #13 then Result := Result + '\r'
    else if c = #9 then Result := Result + '\t'
    else
      Result := Result + c;
  end;
  Result := Result + '"';
end;

// -----------------------------------------------------------------------------
// C# identifier maker
// -----------------------------------------------------------------------------

function IsCSharpIdentChar(c: TP_Char): boolean;
begin
  Result := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or ((c >= '0') and (c <= '9')) or (c = '_');
end;

function MakeCSharpIdentifier(const Name: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to Name.Len do
  begin
    c := Name[i];
    if IsCSharpIdentChar(c) then
      Result := Result + c
    else
      Result := Result + '_';
  end;
  if Result.Len = 0 then
    Result := 'unnamed';
  if (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;
end;

// -----------------------------------------------------------------------------
// Comment extraction (UTF-16 safe, Doxygen aware)
// -----------------------------------------------------------------------------

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
      Line := Line.TrimChar(#32#9);

      if Line.Len > 0 then
      begin
        if Line[1] = '@' then
        begin
          // Skip Doxygen tag line.
        end
        else
        begin
          if Line[1] = '*' then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);
          if (Line.Len > 0) and (Line[1] = '*') then
            Line := Line.GetString(2, Line.Len + 1).TrimChar(#32#9);

          if Line.Len > 0 then
          begin
            if Result.Len > 0 then Result := Result + ' ';
            Result := Result + Line;
          end;
        end;
      end;
    end;

    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
end;

function GetTableCellText(const Comment: TP_String): TP_String;
begin
  Result := GetFullDescription(Comment);
  Result := Result.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// -----------------------------------------------------------------------------
// Filtering helpers
// -----------------------------------------------------------------------------

type
  TValidFuncArray = array of TFunctionStructure;

function CollectValidFunctions(Model: TPascal_Func_Model): TValidFuncArray;
var
  i, j: integer;
  f: TFunctionStructure;
  Supported: boolean;
begin
  SetLength(Result, 0);
  if Model = nil then Exit;

  for i := 0 to Model.Funcs.Count - 1 do
  begin
    f := Model.Funcs[i];
    Supported := True;

    for j := 0 to High(f.Params) do
      if not IsSupportedType(f.Params[j].PascalType) then
      begin
        Supported := False;
        Log(PFormat('Skipped "%s": param "%s" has unsupported type "%s"', [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and not IsSupportedType(f.ReturnType) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" unsupported', [f.Name.Text, f.ReturnType.Text]));
    end;

    if Supported then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := f;
    end;
  end;
end;

function UniqueApiName(const BaseName: TP_String; UsedList: TPascalStringList): TP_String;
var
  Counter: integer;
  Candidate: TP_String;
begin
  Result := BaseName;
  if UsedList.IndexOf(Result) < 0 then Exit;

  Counter := 1;
  while True do
  begin
    Candidate := BaseName.Text + '_' + umlIntToStr(Counter).Text;
    if UsedList.IndexOf(Candidate) < 0 then
    begin
      Result := Candidate;
      Exit;
    end;
    Inc(Counter);
  end;
end;

function MakeAppNameFromUnit(const UnitName: TP_String): TP_String;
var
  tmp: TP_String;
begin
  tmp := UnitName;
  if umlMultipleMatch('*.pas', tmp) then
    tmp := umlChangeFileExt(tmp.Text, '').Text;
  Result := tmp.ReplaceChar('.', '_').ReplaceChar('-', '_');
end;

function MakeProviderClassName(const AppName: TP_String): TP_String;
begin
  Result := MakeCSharpIdentifier(AppName) + 'ToolProvider';
end;

// =============================================================================
// SECTION 1 - C# provider class generator (no Main)
// =============================================================================

function GenerateCSharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TValidFuncArray;
  UnitName, AppName, ClassName: TP_String;
  UsedApiNames: TPascalStringList;
  TotalFuncCount: integer;

  function BuildParamDeclCSharp(const Params: TParamArray): TP_String;
  var
    k: integer;
  begin
    Result := '';
    for k := 0 to High(Params) do
    begin
      if k > 0 then Result := Result + ', ';
      Result := Result + PascalTypeToCSharpType(Params[k].PascalType) + ' ' + MakeCSharpIdentifier(Params[k].Name);
    end;
  end;

  function BuildArgListCSharp(const Params: TParamArray): TP_String;
  var
    k: integer;
  begin
    Result := '';
    for k := 0 to High(Params) do
    begin
      if k > 0 then Result := Result + ', ';
      Result := Result + MakeCSharpIdentifier(Params[k].Name);
    end;
  end;

  procedure EmitFileHeader;
  begin
    Result.Add('// Auto-generated by csharp_mcp_generator_tool.');
    Result.Add('// Source unit: ' + UnitName.Text + '.');
    Result.Add('// Provider class: ' + ClassName.Text + '.');
    Result.Add('// Do not edit by hand unless you know what you are doing.');
    Result.Add('//');
    Result.Add('// This file contains the provider class only. The Main method lives');
    Result.Add('// in the companion test program generated by GenerateCSharpTestProgram.');
    Result.Add('//');
    Result.Add('// Startup order for the whole toolchain:');
    Result.Add('//   1. beacon      (pascal_agent_service.exe)');
    Result.Add('//   2. this provider');
    Result.Add('//   3. mcp_api_tool (python mcp_api_tool.py)');
    Result.Add('//   4. agent       (LM Studio / Claude Desktop / ...)');
    Result.Add('');
    Result.Add('using System;');
    Result.Add('using System.Collections.Generic;');
    Result.Add('using System.Text.Json;');
    Result.Add('using System.Threading.Tasks;');
    Result.Add('using LingoFuse;');
    Result.Add('');
    Result.Add('namespace LingoFuseGenerated');
    Result.Add('{');
    Result.Add('    /// <summary>');
    Result.Add('    /// Auto-generated MCP tool provider for the Pascal unit');
    Result.Add('    /// <c>' + UnitName.Text + '</c>.');
    Result.Add('    /// Exposes every supported top-level routine as a LingoFuse Call');
    Result.Add('    /// API and advertises each API as an MCP tool through the beacon.');
    Result.Add('    /// </summary>');
    Result.Add('    public static class ' + ClassName.Text);
    Result.Add('    {');
  end;

  procedure EmitMetadata;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // Application metadata');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        public const string MY_APP_NAME   = ' + CSharpStrLit(AppName) + ';');
    Result.Add('        public const string MY_APP_DESC   = ' + CSharpStrLit('Tool provider for unit ' + UnitName) + ';');
    Result.Add('        public const string IPC_ENDPOINT  = ' + CSharpStrLit(DEFAULT_IPC_ENDPOINT) + ';');
    Result.Add('        public const string BEACON_APP    = ' + CSharpStrLit(DEFAULT_BEACON_APP) + ';');
    Result.Add('        public const string REGISTER_API  = ' + CSharpStrLit(DEFAULT_REGISTER_API) + ';');
    Result.Add('        public const string AGENT_LOG_API = ' + CSharpStrLit(DEFAULT_AGENT_LOG_API) + ';');
    Result.Add('');
    Result.Add('        /// <summary>Verbose logging toggle.</summary>');
    Result.Add('        public static bool DebugLog = true;');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// The AppHandle must remain alive for the entire process');
    Result.Add('        /// lifetime, otherwise the underlying native App would be');
    Result.Add('        /// detached from the mesh while the framework is still running.');
    Result.Add('        /// </summary>');
    Result.Add('        private static AppHandle? _app;');
    Result.Add('');
  end;

  procedure EmitInternalCalls;
  var
    i: integer;
    ApiName, InternalCallName, ParamDeclCSharp, CallArgs: TP_String;
    RetTypeCs: TP_String;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // Internal call stubs (to be implemented by the user)');
    Result.Add('        //');
    Result.Add('        // Each stub corresponds to an original Pascal routine and has');
    Result.Add('        // the correct signature with C# type annotations.');
    Result.Add('        // Replace the placeholder body with the actual implementation.');
    Result.Add('        // ============================================================');
    Result.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeCSharpIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);

        InternalCallName := 'InternalCall_' + ApiName;
        ParamDeclCSharp := BuildParamDeclCSharp(Params);
        CallArgs := BuildArgListCSharp(Params);

        if IsFunction then
          RetTypeCs := PascalTypeToCSharpType(ReturnType)
        else
          RetTypeCs := 'void';

        Result.Add('        public static ' + RetTypeCs + ' ' + InternalCallName + '(' + ParamDeclCSharp + ')');
        Result.Add('        {');
        Result.Add('            // TODO: replace this placeholder with the actual');
        Result.Add('            // implementation of the original Pascal routine');
        Result.Add('            // "' + Name.Text + '".');
        Result.Add('            if (DebugLog)');
        Result.Add('                Console.WriteLine("[' + InternalCallName + '] called");');
        if IsFunction then
          Result.Add('            return ' + PascalTypeDefaultValue(ReturnType) + ';');
        Result.Add('        }');
        Result.Add('');
      end;
    end;
  end;

  procedure EmitLogging;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // Asynchronous logging to the beacon');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// Fire-and-forget log to the beacon''s agent_log API.');
    Result.Add('        /// Runs on a thread-pool thread so the caller is never blocked.');
    Result.Add('        /// </summary>');
    Result.Add('        private static void SendLogAsync(string msg)');
    Result.Add('        {');
    Result.Add('            if (!DebugLog) return;');
    Result.Add('            Task.Run(() =>');
    Result.Add('            {');
    Result.Add('                try');
    Result.Add('                {');
    Result.Add('                    using var request = new DataHandle(AGENT_LOG_API);');
    Result.Add('                    LfIo.WriteJson(request, new { message = msg });');
    Result.Add('                    using var response =');
    Result.Add('                        Framework.Call(BEACON_APP, request, 3000);');
    Result.Add('                }');
    Result.Add('                catch');
    Result.Add('                {');
    Result.Add('                    // Swallow: a failed log must never destabilise');
    Result.Add('                    // the provider.');
    Result.Add('                }');
    Result.Add('            });');
    Result.Add('        }');
    Result.Add('');
  end;

  procedure EmitCallbacks;
  var
    i, j: integer;
    ApiName, CallbackName, InternalCallName: TP_String;
    ParamName, ParamExtract, CallArgs: TP_String;
    parts: TPascalStringList;
    k: integer;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // API callbacks');
    Result.Add('        // ============================================================');
    Result.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeCSharpIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);

        CallbackName := 'Callback_' + ApiName;
        InternalCallName := 'InternalCall_' + ApiName;

        ParamExtract := '';
        CallArgs := '';
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := MakeCSharpIdentifier(Params[j].Name);

          if CallArgs <> '' then
            CallArgs := CallArgs + ', ';
          CallArgs := CallArgs + ParamName;

          if Params[j].PascalType.Same('int64') then
          begin
            ParamExtract := ParamExtract + '                    long ' + ParamName + ' = 0L;' + sLineBreak +
              '                    if (root.TryGetProperty(' + CSharpStrLit(Params[j].Name) + ', out var ' + ParamName +
              '_elem) && ' + ParamName + '_elem.ValueKind == JsonValueKind.Number)' + sLineBreak + '                        ' +
              ParamName + ' = ' + ParamName + '_elem.GetInt64();' + sLineBreak;
          end
          else if Params[j].PascalType.Same('double') then
          begin
            ParamExtract := ParamExtract + '                    double ' + ParamName + ' = 0.0;' + sLineBreak +
              '                    if (root.TryGetProperty(' + CSharpStrLit(Params[j].Name) + ', out var ' + ParamName +
              '_elem) && ' + ParamName + '_elem.ValueKind == JsonValueKind.Number)' + sLineBreak + '                        ' +
              ParamName + ' = ' + ParamName + '_elem.GetDouble();' + sLineBreak;
          end
          else if Params[j].PascalType.Same('string') then
          begin
            ParamExtract := ParamExtract + '                    string ' + ParamName + ' = string.Empty;' + sLineBreak +
              '                    if (root.TryGetProperty(' + CSharpStrLit(Params[j].Name) + ', out var ' + ParamName +
              '_elem) && ' + ParamName + '_elem.ValueKind == JsonValueKind.String)' + sLineBreak + '                        ' +
              ParamName + ' = ' + ParamName + '_elem.GetString() ?? string.Empty;' + sLineBreak;
          end;
        end;

        Result.Add('        /// <summary>Auto-generated callback for API "' + Name.Text + '".</summary>');
        Result.Add('        private static void ' + CallbackName + '(DataHandle input, DataHandle output)');
        Result.Add('        {');
        Result.Add('            try');
        Result.Add('            {');
        Result.Add('                string json = LfIo.ReadString(input);');
        Result.Add('');
        Result.Add('                if (DebugLog)');
        Result.Add('                    Console.WriteLine($"[' + Name.Text + '] Input JSON: {json}");');
        Result.Add('');
        Result.Add('                if (string.IsNullOrEmpty(json))');
        Result.Add('                {');
        Result.Add('                    LfIo.WriteJson(output, new { error = "Empty input" });');
        Result.Add('                    if (DebugLog)');
        Result.Add('                    {');
        Result.Add('                        Console.WriteLine($"[' + Name.Text + '] Error: Empty input");');
        Result.Add('                        SendLogAsync($"[' + Name.Text + '] Error: Empty input");');
        Result.Add('                    }');
        Result.Add('                    return;');
        Result.Add('                }');
        Result.Add('');
        Result.Add('                JsonDocument doc;');
        Result.Add('                try');
        Result.Add('                {');
        Result.Add('                    doc = JsonDocument.Parse(json);');
        Result.Add('                }');
        Result.Add('                catch (JsonException ex)');
        Result.Add('                {');
        Result.Add('                    LfIo.WriteJson(output,');
        Result.Add('                        new { error = "Invalid JSON: " + ex.Message });');
        Result.Add('                    if (DebugLog)');
        Result.Add('                    {');
        Result.Add('                        Console.WriteLine($"[' + Name.Text + '] Invalid JSON: {ex.Message}");');
        Result.Add('                        SendLogAsync($"[' + Name.Text + '] Invalid JSON: {ex.Message}");');
        Result.Add('                    }');
        Result.Add('                    return;');
        Result.Add('                }');
        Result.Add('');
        Result.Add('                using (doc)');
        Result.Add('                {');
        Result.Add('                    var root = doc.RootElement;');
        Result.Add('');

        if ParamExtract <> '' then
        begin
          // ParamExtract contains embedded sLineBreak markers; split it back.
          // Simpler: just append as-is and let the list store it as one big
          // string. To keep one logical line per PascalStringList element,
          // split on sLineBreak here.
          begin
            parts := TPascalStringList.Create;
            try
              umlSeparatorText(ParamExtract, parts, #10);
              for k := 0 to parts.Count - 1 do
                Result.Add(TP_String(parts[k]));
            finally
              parts.Free;
            end;
          end;
          Result.Add('');
        end;

        if IsFunction then
        begin
          Result.Add('                    var ret = ' + InternalCallName + '(' + CallArgs + ');');
          Result.Add('                    LfIo.WriteJson(output, new { result = ret });');
          Result.Add('                    if (DebugLog)');
          Result.Add('                    {');
          Result.Add('                        Console.WriteLine($"[' + Name.Text + '] Called -> {ret}");');
          Result.Add('                        SendLogAsync($"[' + Name.Text + '] Called -> {ret}");');
          Result.Add('                    }');
        end
        else
        begin
          Result.Add('                    ' + InternalCallName + '(' + CallArgs + ');');
          Result.Add('                    LfIo.WriteJson(output, new { status = "ok" });');
          Result.Add('                    if (DebugLog)');
          Result.Add('                    {');
          Result.Add('                        Console.WriteLine($"[' + Name.Text + '] OK");');
          Result.Add('                        SendLogAsync($"[' + Name.Text + '] OK");');
          Result.Add('                    }');
        end;

        Result.Add('                }');
        Result.Add('            }');
        Result.Add('            catch (Exception ex)');
        Result.Add('            {');
        Result.Add('                try');
        Result.Add('                {');
        Result.Add('                    LfIo.WriteJson(output, new { error = ex.Message });');
        Result.Add('                }');
        Result.Add('                catch');
        Result.Add('                {');
        Result.Add('                    // Swallow: even a broken error report must not');
        Result.Add('                    // crash the provider.');
        Result.Add('                }');
        Result.Add('                if (DebugLog)');
        Result.Add('                {');
        Result.Add('                    Console.WriteLine($"[' + Name.Text + '] Exception: {ex.Message}");');
        Result.Add('                    SendLogAsync($"[' + Name.Text + '] Exception: {ex.Message}");');
        Result.Add('                }');
        Result.Add('            }');
        Result.Add('        }');
        Result.Add('');
      end;
    end;
  end;

  procedure EmitRegisterTool;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // Tool registration with the beacon');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// Register a single tool with the beacon via the');
    Result.Add('        /// register_agent API. Returns true on success.');
    Result.Add('        /// </summary>');
    Result.Add('        private static bool RegisterTool(object toolDef)');
    Result.Add('        {');
    Result.Add('            try');
    Result.Add('            {');
    Result.Add('                using var request = new DataHandle(REGISTER_API);');
    Result.Add('                LfIo.WriteJson(request, toolDef);');
    Result.Add('                using var response =');
    Result.Add('                    Framework.Call(BEACON_APP, request, 5000);');
    Result.Add('');
    Result.Add('                if (response.Size == 0)');
    Result.Add('                {');
    Result.Add('                    if (DebugLog)');
    Result.Add('                        Console.WriteLine(');
    Result.Add('                            "[RegisterTool] No response from beacon");');
    Result.Add('                    return false;');
    Result.Add('                }');
    Result.Add('');
    Result.Add('                string respJson = LfIo.ReadString(response);');
    Result.Add('                if (string.IsNullOrEmpty(respJson))');
    Result.Add('                    return false;');
    Result.Add('');
    Result.Add('                using var doc = JsonDocument.Parse(respJson);');
    Result.Add('                if (doc.RootElement.TryGetProperty("status", out var st)');
    Result.Add('                    && st.ValueKind == JsonValueKind.String');
    Result.Add('                    && st.GetString() == "ok")');
    Result.Add('                {');
    Result.Add('                    return true;');
    Result.Add('                }');
    Result.Add('                return false;');
    Result.Add('            }');
    Result.Add('            catch (Exception ex)');
    Result.Add('            {');
    Result.Add('                if (DebugLog)');
    Result.Add('                    Console.WriteLine($"[RegisterTool] Exception: {ex.Message}");');
    Result.Add('                return false;');
    Result.Add('            }');
    Result.Add('        }');
    Result.Add('');
  end;

  procedure EmitRegisterTools;
  var
    i, j: integer;
    ApiName, Description, ParamName, PropEntry, RequiredList: TP_String;
    parts: TPascalStringList;
    k: integer;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // RegisterTools');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// Register all supported routines as tools with the beacon.');
    Result.Add('        /// </summary>');
    Result.Add('        public static bool RegisterTools()');
    Result.Add('        {');
    Result.Add('            int totalCount = ' + umlIntToStr(TotalFuncCount) + ';');
    Result.Add('            int regCount = 0;');
    Result.Add('');
    Result.Add('            if (DebugLog)');
    Result.Add('                Console.WriteLine(');
    Result.Add('                    $"[RegisterTools] Starting registration of ' + '{totalCount} tools...");');
    Result.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeCSharpIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);

        Description := GetFullDescription(Comment);
        if Description = '' then
          Description := 'Auto-generated tool for ' + Name;

        Result.Add('            {');
        Result.Add('                var properties =');
        Result.Add('                    new Dictionary<string, object>();');

        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;

          if Params[j].Description <> '' then
            PropEntry := Params[j].Description
          else
            PropEntry := ParamName + ' parameter';

          Result.Add('                properties[' + CSharpStrLit(ParamName) + '] =');
          Result.Add('                    new Dictionary<string, string>');
          Result.Add('                {');
          Result.Add('                    { "type", ' + CSharpStrLit(PascalTypeToJsonSchemaType(Params[j].PascalType)) + ' },');
          Result.Add('                    { "description", ' + CSharpStrLit(PropEntry) + ' }');
          Result.Add('                };');
        end;

        Result.Add('');

        RequiredList := '';
        for j := 0 to High(Params) do
        begin
          if Params[j].Name = '' then
            ParamName := 'p' + umlIntToStr(j)
          else
            ParamName := Params[j].Name;
          if RequiredList <> '' then
            RequiredList := RequiredList + ', ';
          RequiredList := RequiredList + CSharpStrLit(ParamName);
        end;

        Result.Add('                var parameters =');
        Result.Add('                    new Dictionary<string, object>');
        Result.Add('                {');
        Result.Add('                    { "type", "object" },');
        Result.Add('                    { "properties", properties },');
        if RequiredList <> '' then
          Result.Add('                    { "required", new[] { ' + RequiredList + ' } }')
        else
          Result.Add('                    { "required", Array.Empty<string>() }');
        Result.Add('                };');
        Result.Add('');
        Result.Add('                var toolDef =');
        Result.Add('                    new Dictionary<string, object>');
        Result.Add('                {');
        Result.Add('                    { "name", ' + CSharpStrLit(ApiName) + ' },');
        Result.Add('                    { "description", ' + CSharpStrLit(Description) + ' },');
        Result.Add('                    { "target_app", MY_APP_NAME },');
        Result.Add('                    { "target_api", ' + CSharpStrLit(ApiName) + ' },');
        Result.Add('                    { "parameters", parameters }');
        Result.Add('                };');
        Result.Add('');
        Result.Add('                if (RegisterTool(toolDef))');
        Result.Add('                {');
        Result.Add('                    regCount++;');
        Result.Add('                    if (DebugLog)');
        Result.Add('                        Console.WriteLine(');
        Result.Add('                            "[RegisterTools] OK: ' + ApiName + '");');
        Result.Add('                }');
        Result.Add('                else if (DebugLog)');
        Result.Add('                {');
        Result.Add('                    Console.WriteLine(');
        Result.Add('                        "[RegisterTools] FAIL: ' + ApiName + '");');
        Result.Add('                }');
        Result.Add('            }');
        Result.Add('');
      end;
    end;

    Result.Add('            if (DebugLog)');
    Result.Add('                Console.WriteLine(');
    Result.Add('                    $"[RegisterTools] Registered ' + '{regCount} / {totalCount}");');
    Result.Add('');
    Result.Add('            return regCount == totalCount;');
    Result.Add('        }');
    Result.Add('');
  end;

  procedure EmitRegisterAPIs;
  var
    i: integer;
    ApiName, CallbackName, Description: TP_String;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // RegisterAPIs');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// Create the LingoFuse app and register all API callbacks.');
    Result.Add('        /// </summary>');
    Result.Add('        public static AppHandle? RegisterAPIs()');
    Result.Add('        {');
    Result.Add('            AppHandle app;');
    Result.Add('            try');
    Result.Add('            {');
    Result.Add('                app = new AppHandle(MY_APP_NAME, MY_APP_DESC);');
    Result.Add('            }');
    Result.Add('            catch (Exception ex)');
    Result.Add('            {');
    Result.Add('                Console.Error.WriteLine(');
    Result.Add('                    $"[RegisterAPIs] Failed to create app: {ex.Message}");');
    Result.Add('                return null;');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            if (DebugLog)');
    Result.Add('                Console.WriteLine(');
    Result.Add('                    $"[RegisterAPIs] Application ''{MY_APP_NAME}'' created");');
    Result.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeCSharpIdentifier(Name);
        ApiName := UniqueApiName(ApiName, UsedApiNames);
        UsedApiNames.Add(ApiName);
        CallbackName := 'Callback_' + ApiName;
        Description := GetFullDescription(Comment);
        if Description = '' then
          Description := 'Auto-generated API for ' + Name;

        Result.Add('            app.RegisterCall(');
        Result.Add('                ' + CSharpStrLit(ApiName) + ',');
        Result.Add('                ' + CSharpStrLit(Description) + ',');
        Result.Add('                ' + CallbackName + ');');
      end;
    end;

    Result.Add('');
    Result.Add('            if (DebugLog)');
    Result.Add('                Console.WriteLine(');
    Result.Add('                    $"[RegisterAPIs] Registered ' + umlIntToStr(TotalFuncCount) + ' APIs");');
    Result.Add('');
    Result.Add('            return app;');
    Result.Add('        }');
    Result.Add('');
  end;

  procedure EmitExecuteAndShutdown;
  begin
    Result.Add('        // ============================================================');
    Result.Add('        // Execute_And_Reg_all');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// Full startup sequence:');
    Result.Add('        ///   1. RegisterAPIs         - create app and register callbacks.');
    Result.Add('        ///   2. Framework.PrepareClient - connect to the IPC endpoint.');
    Result.Add('        ///   3. Framework.PrepareDone   - wait until the client is ready.');
    Result.Add('        ///   4. RegisterTools        - advertise all APIs as tools.');
    Result.Add('        /// </summary>');
    Result.Add('        public static bool Execute_And_Reg_all()');
    Result.Add('        {');
    Result.Add('            _app = RegisterAPIs();');
    Result.Add('            if (_app == null)');
    Result.Add('            {');
    Result.Add('                if (DebugLog)');
    Result.Add('                    Console.Error.WriteLine(');
    Result.Add('                        "[Execute_And_Reg_all] RegisterAPIs failed");');
    Result.Add('                return false;');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            Framework.SetOption("Overlap_Connection", "True");');
    Result.Add('            Framework.SetOption("Wait_Connection_ReadyOk", "True");');
    Result.Add('            Framework.ResetPrepare();');
    Result.Add('');
    Result.Add('            if (Framework.PrepareClient(IPC_ENDPOINT, _app) == -1)');
    Result.Add('            {');
    Result.Add('                Console.Error.WriteLine(');
    Result.Add('                    $"[Execute_And_Reg_all] PrepareClient failed for ' + '{IPC_ENDPOINT}");');
    Result.Add('                _app.Dispose();');
    Result.Add('                _app = null;');
    Result.Add('                return false;');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            if (Framework.PrepareDone() <= 0)');
    Result.Add('            {');
    Result.Add('                Console.Error.WriteLine(');
    Result.Add('                    "[Execute_And_Reg_all] PrepareDone failed");');
    Result.Add('                return false;');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            return RegisterTools();');
    Result.Add('        }');
    Result.Add('');
    Result.Add('        // ============================================================');
    Result.Add('        // ShutdownClean');
    Result.Add('        // ============================================================');
    Result.Add('');
    Result.Add('        /// <summary>');
    Result.Add('        /// Ordered shutdown. Order matters: stop the main thread');
    Result.Add('        /// first, dispose the app, then release the process-wide');
    Result.Add('        /// framework state.');
    Result.Add('        /// </summary>');
    Result.Add('        public static void ShutdownClean()');
    Result.Add('        {');
    Result.Add('            try { NetworkEvents.Clear(); } catch { }');
    Result.Add('            try { Framework.ExitMainThread(); } catch { }');
    Result.Add('            try { _app?.Dispose(); } catch { }');
    Result.Add('            try { Framework.Shutdown(); } catch { }');
    Result.Add('            _app = null;');
    Result.Add('        }');
    Result.Add('');
  end;

  procedure EmitFileFooter;
  begin
    Result.Add('    } // class ' + ClassName.Text);
    Result.Add('} // namespace LingoFuseGenerated');
    Result.Add('');
  end;

begin
  Result := nil;

  if Model = nil then
  begin
    Log('GenerateCSharpCode: model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName = '' then
  begin
    Log('GenerateCSharpCode: UnitName is empty.');
    Exit;
  end;

  AppName := MakeAppNameFromUnit(UnitName);
  ClassName := MakeProviderClassName(AppName);
  SupportedFuncs := CollectValidFunctions(Model);
  TotalFuncCount := Length(SupportedFuncs);
  UsedApiNames := TPascalStringList.Create;

  Log(PFormat('GenerateCSharpCode: unit="%s" class="%s" funcs=%d', [UnitName.Text, ClassName.Text, TotalFuncCount]));

  try
    Result := TPascalStringList.Create;
    EmitFileHeader;
    EmitMetadata;
    EmitInternalCalls;
    EmitLogging;
    EmitCallbacks;
    EmitRegisterTool;
    EmitRegisterTools;
    EmitRegisterAPIs;
    EmitExecuteAndShutdown;
    EmitFileFooter;
    Log(PFormat('GenerateCSharpCode: done, %d lines.', [Result.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

// =============================================================================
// SECTION 2 - C# test program generator (Main entry point)
// =============================================================================

function GenerateCSharpTestProgram(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, AppName, ClassName: TP_String;
  SupportedFuncs: TValidFuncArray;
  TotalFuncCount: integer;
begin
  Result := nil;

  if Model = nil then
  begin
    Log('GenerateCSharpTestProgram: model is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName = '' then
  begin
    Log('GenerateCSharpTestProgram: UnitName is empty.');
    Exit;
  end;

  AppName := MakeAppNameFromUnit(UnitName);
  ClassName := MakeProviderClassName(AppName);
  SupportedFuncs := CollectValidFunctions(Model);
  TotalFuncCount := Length(SupportedFuncs);

  Log(PFormat('GenerateCSharpTestProgram: unit="%s" class="%s"', [UnitName.Text, ClassName.Text]));

  Result := TPascalStringList.Create;
  try
    Result.Add('// Auto-generated by csharp_mcp_generator_tool.');
    Result.Add('// Source unit: ' + UnitName.Text + '.');
    Result.Add('// Test entry point for the generated provider class.');
    Result.Add('//');
    Result.Add('// This file contains the single Main method for the project.');
    Result.Add('// It drives the provider class through its entire lifecycle:');
    Result.Add('//   1. print effective configuration');
    Result.Add('//   2. Execute_And_Reg_all()  (register APIs, connect, advertise tools)');
    Result.Add('//   3. wait for the user to press Enter');
    Result.Add('//   4. ShutdownClean()        (orderly teardown)');
    Result.Add('//');
    Result.Add('// Prerequisite: the beacon (pascal_agent_service.exe) must already');
    Result.Add('// be running on the configured IPC endpoint.');
    Result.Add('//');
    Result.Add('// Build: dotnet build');
    Result.Add('// Run  : dotnet run');
    Result.Add('');
    Result.Add('using System;');
    Result.Add('using LingoFuseGenerated;');
    Result.Add('');
    Result.Add('namespace LingoFuseGenerated');
    Result.Add('{');
    Result.Add('    /// <summary>');
    Result.Add('    /// Test entry point for the <c>' + ClassName.Text + '</c> provider.');
    Result.Add('    /// </summary>');
    Result.Add('    public static class Program');
    Result.Add('    {');
    Result.Add('        public static int Main(string[] args)');
    Result.Add('        {');
    Result.Add('            Console.WriteLine("==================================================");');
    Result.Add('            Console.WriteLine("  C# MCP Tool Provider Test");');
    Result.Add('            Console.WriteLine("==================================================");');
    Result.Add('            Console.WriteLine();');
    Result.Add('            Console.WriteLine("Configuration:");');
    Result.Add('            Console.WriteLine("  App name   : " + ' + ClassName + '.MY_APP_NAME);');
    Result.Add('            Console.WriteLine("  App desc   : " + ' + ClassName + '.MY_APP_DESC);');
    Result.Add('            Console.WriteLine("  IPC        : " + ' + ClassName + '.IPC_ENDPOINT);');
    Result.Add('            Console.WriteLine("  Beacon app : " + ' + ClassName + '.BEACON_APP);');
    Result.Add('            Console.WriteLine("  Register   : " + ' + ClassName + '.REGISTER_API);');
    Result.Add('            Console.WriteLine("  Log API    : " + ' + ClassName + '.AGENT_LOG_API);');
    Result.Add('            Console.WriteLine("  Debug log  : " + ' + ClassName + '.DebugLog);');
    Result.Add('            Console.WriteLine("  APIs       : ' + umlIntToStr(TotalFuncCount) + '");');
    Result.Add('            Console.WriteLine();');
    Result.Add('            Console.WriteLine("Connecting to " + ' + ClassName + '.IPC_ENDPOINT + " ...");');
    Result.Add('            Console.WriteLine();');
    Result.Add('');
    Result.Add('            bool ok;');
    Result.Add('            try');
    Result.Add('            {');
    Result.Add('                ok = ' + ClassName + '.Execute_And_Reg_all();');
    Result.Add('            }');
    Result.Add('            catch (Exception ex)');
    Result.Add('            {');
    Result.Add('                Console.Error.WriteLine(');
    Result.Add('                    "[FATAL] Unhandled exception during startup: " + ex);');
    Result.Add('                ' + ClassName + '.ShutdownClean();');
    Result.Add('                return 1;');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            if (!ok)');
    Result.Add('            {');
    Result.Add('                Console.Error.WriteLine();');
    Result.Add('                Console.Error.WriteLine("==================================================");');
    Result.Add('                Console.Error.WriteLine("  [FATAL] Provider startup failed.");');
    Result.Add('                Console.Error.WriteLine("==================================================");');
    Result.Add('                Console.Error.WriteLine();');
    Result.Add('                Console.Error.WriteLine("Checklist:");');
    Result.Add('                Console.Error.WriteLine("  1. Is the beacon running?  ");');
    Result.Add('                Console.Error.WriteLine("       (pascal_agent_service.exe)");');
    Result.Add('                Console.Error.WriteLine("  2. Is the endpoint reachable?");');
    Result.Add('                Console.Error.WriteLine("       " + ' + ClassName + '.IPC_ENDPOINT);');
    Result.Add('                Console.Error.WriteLine("  3. Is the native library on the loader path?");');
    Result.Add('                Console.Error.WriteLine("       Windows : LingoFuse64.dll next to the .exe");');
    Result.Add('                Console.Error.WriteLine("       Linux   : liblingofuse.so on LD_LIBRARY_PATH");');
    Result.Add('                Console.Error.WriteLine("       macOS   : liblingofuse.dylib on DYLD_LIBRARY_PATH");');
    Result.Add('                Console.Error.WriteLine("  4. See DEBUG_LOG output above for details.");');
    Result.Add('                Console.Error.WriteLine();');
    Result.Add('                ' + ClassName + '.ShutdownClean();');
    Result.Add('                return 1;');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            Console.WriteLine();');
    Result.Add('            Console.WriteLine("==================================================");');
    Result.Add('            Console.WriteLine("  [OK] Provider is ready. All tools registered.");');
    Result.Add('            Console.WriteLine("==================================================");');
    Result.Add('            Console.WriteLine();');
    Result.Add('            Console.WriteLine("Next steps:");');
    Result.Add('            Console.WriteLine("  1. Start the MCP gateway:");');
    Result.Add('            Console.WriteLine("       python mcp_api_tool.py --transport stdio");');
    Result.Add('            Console.WriteLine("  2. Connect your agent (LM Studio / Claude Desktop / ...)");');
    Result.Add('            Console.WriteLine("     through the generated MCP config.");');
    Result.Add('            Console.WriteLine();');
    Result.Add('            Console.WriteLine("Press Enter to shut down.");');
    Result.Add('            Console.Out.Flush();');
    Result.Add('');
    Result.Add('            try');
    Result.Add('            {');
    Result.Add('                Console.ReadLine();');
    Result.Add('            }');
    Result.Add('            catch (Exception)');
    Result.Add('            {');
    Result.Add('                // EOF (Ctrl+D / Ctrl+Z) is a normal shutdown trigger.');
    Result.Add('            }');
    Result.Add('');
    Result.Add('            Console.WriteLine();');
    Result.Add('            Console.WriteLine("Shutting down ...");');
    Result.Add('            ' + ClassName + '.ShutdownClean();');
    Result.Add('            Console.WriteLine("[OK] Shutdown complete.");');
    Result.Add('            return 0;');
    Result.Add('        }');
    Result.Add('    } // class Program');
    Result.Add('} // namespace LingoFuseGenerated');
    Result.Add('');

    Log(PFormat('GenerateCSharpTestProgram: done, %d lines.', [Result.Count]));
  except
    Result.Free;
    Result := nil;
    raise;
  end;
end;

// =============================================================================
// SECTION 3 - C# README generator (English Markdown)
// =============================================================================

function GenerateCSharpReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  ValidFuncs: TValidFuncArray;
  UnitName, AppName, ClassName: TP_String;
  i, j: integer;
  f: TFunctionStructure;
  desc, shortDesc, row: TP_String;
  TotalFuncCount: integer;

  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName.Text + ' - C# Tool Provider');
    L.Add('');
    L.Add('> **Auto-generated.** Produced by `csharp_mcp_generator_tool.pas`.');
    L.Add('>');
    L.Add('> **Source unit**      : `' + UnitName.Text + '`');
    L.Add('> **Provider file**    : `' + UnitName.Text + '_tool_provider.cs`');
    L.Add('> **Test file**        : `' + UnitName.Text + '_tool_provider_test.cs`');
    L.Add('> **Provider class**   : `' + ClassName.Text + '`');
    L.Add('> **Exposed APIs**     : ' + umlIntToStr(TotalFuncCount) + '');
    L.Add('> **Runtime target**   : .NET 8.0 or later');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('## Table of Contents');
    L.Add('');
    L.Add('- [1. Overview](#1-overview)');
    L.Add('- [2. Startup Order (read this first)](#2-startup-order-read-this-first)');
    L.Add('- [3. Runtime Architecture](#3-runtime-architecture)');
    L.Add('- [4. Prerequisites and Environment Setup](#4-prerequisites-and-environment-setup)');
    L.Add('- [5. Project Layout](#5-project-layout)');
    L.Add('- [6. Build](#6-build)');
    L.Add('- [7. Run (detailed)](#7-run-detailed)');
    L.Add('- [8. Tool Reference](#8-tool-reference)');
    L.Add('- [9. JSON Schema Specification](#9-json-schema-specification)');
    L.Add('- [10. Debugging and Troubleshooting](#10-debugging-and-troubleshooting)');
    L.Add('- [11. Portability](#11-portability)');
    L.Add('- [12. Reference Resources](#12-reference-resources)');
    L.Add('');
    L.Add('---');
    L.Add('');
  end;

  procedure EmitOverview;
  begin
    L.Add('## 1. Overview');
    L.Add('');
    L.Add('This document is the single reference you need to build, run, and');
    L.Add('test the auto-generated C# tool provider for the Pascal source unit');
    L.Add('`' + UnitName.Text + '`.');
    L.Add('');
    L.Add('The provider registers every top-level function of `' + UnitName.Text + '`');
    L.Add('as a LingoFuse Call API and advertises each API as an MCP tool through');
    L.Add('the LingoFuse beacon. An MCP client (LM Studio, Claude Desktop, or any');
    L.Add('MCP-aware agent) discovers the tools through the beacon and invokes');
    L.Add('them over IPC.');
    L.Add('');
    L.Add('The generator produces **three** files:');
    L.Add('');
    L.Add('| File | Role |');
    L.Add('|------|------|');
    L.Add('| `' + UnitName.Text + '_tool_provider.cs` | Provider class (`' + ClassName.Text + '`); contains every callback and the registration logic. |');
    L.Add('| `' + UnitName.Text + '_tool_provider_test.cs` | Test entry point; contains the single `Main` method for the project. |');
    L.Add('| `' + UnitName.Text + '_tool_provider_csharp.md` | This README. |');
    L.Add('');
    L.Add('Put both `.cs` files into the same .NET console project. Only the');
    L.Add('test file defines `Main`; the provider file is reusable by any host.');
    L.Add('');
    L.Add('### 1.1 LingoFuse .NET binding sourcing policy');
    L.Add('');
    L.Add('The generated code depends on the LingoFuse .NET binding assembly');
    L.Add('(the namespace `LingoFuse`). Two ways to obtain it:');
    L.Add('');
    L.Add('| # | Source | When to use it | How to get it |');
    L.Add('|---|--------|----------------|---------------|');
    L.Add('| 1 | Standalone `LingoFuse` NuGet package or repository | If your deployment publishes one | `dotnet add package LingoFuse` **or** `git clone <lingofuse-dotnet-repo-url>` |');
    L.Add('| 2 | Binding source inside LingoFuse-pasAgent-v3 | Fallback when no standalone package exists | Clone `<v3-repo-url>`, then reference `<v3>/src/bindings/dotnet/LingoFuse/LingoFuse.csproj` |');
    L.Add('');
    L.Add('> **Note**: the URLs above are placeholders. Replace them with the');
    L.Add('> actual clone URLs for your deployment. If no standalone .NET');
    L.Add('> repository exists at the time of reading, use the v3 copy - it is');
    L.Add('> functionally equivalent for the subset of the binding used by the');
    L.Add('> generated provider.');
    L.Add('');
    L.Add('### 1.2 Required external programs');
    L.Add('');
    L.Add('The provider is a **client** of the LingoFuse beacon. The beacon');
    L.Add('binary ships with the Pascal runtime, not with any .NET repository:');
    L.Add('');
    L.Add('| Program | Role | Where to get it |');
    L.Add('|---------|------|-----------------|');
    L.Add('| `pascal_agent_service.exe` | Beacon server; routes tool calls between providers and clients | Build from `<v3>/src/pascal_agent_service.lpr` |');
    L.Add('| `mcp_api_tool.py` | MCP gateway that exposes the registered tools to LLM agents | Ships with v3 at `<v3>/src/mcp_api_tool.py` |');
    L.Add('| `generate_agent_json.py` | Generates MCP client configuration files | Ships with v3 at `<v3>/src/generate_agent_json.py` |');
    L.Add('');
    L.Add('### 1.3 Quick example');
    L.Add('');
    L.Add('```bash');
    L.Add('# Step 1: start the beacon (leave running)');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('./pascal_agent_service.exe');
    L.Add('');
    L.Add('# Step 2: start the provider (leave running)');
    L.Add('cd /path/to/my_provider');
    L.Add('dotnet run');
    L.Add('');
    L.Add('# Step 3: start the MCP gateway (leave running)');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('python mcp_api_tool.py --transport stdio');
    L.Add('');
    L.Add('# Step 4: start your agent (LM Studio / Claude Desktop / ...)');
    L.Add('#         and point it at the generated MCP config.');
    L.Add('```');
    L.Add('');
    L.Add('Details for each step are in section 7.');
    L.Add('');
  end;

  procedure EmitStartupOrder;
  begin
    L.Add('## 2. Startup Order (read this first)');
    L.Add('');
    L.Add('The whole toolchain follows a strict 4-step startup order. Starting');
    L.Add('in the wrong order will leave the provider unable to register its');
    L.Add('tools, or the agent unable to discover them.');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart LR');
    L.Add('    A["Step 1<br/>Start Beacon<br/><i>pascal_agent_service.exe</i>"]');
    L.Add('    B["Step 2<br/>Start Provider<br/><i>dotnet run</i>"]');
    L.Add('    C["Step 3<br/>Start MCP Gateway<br/><i>mcp_api_tool.py</i>"]');
    L.Add('    D["Step 4<br/>Connect Agent<br/><i>LM Studio / Claude</i>"]');
    L.Add('');
    L.Add('    A -->|must be first| B');
    L.Add('    B -->|tools must exist| C');
    L.Add('    C -->|must expose tools| D');
    L.Add('');
    L.Add('    style A fill:#e8f5e9,stroke:#2e7d32,color:#0E4D2A');
    L.Add('    style B fill:#fff3e0,stroke:#e65100,color:#7E5109');
    L.Add('    style C fill:#f3e5f5,stroke:#6a1b9a,color:#4A148C');
    L.Add('    style D fill:#e0f7fa,stroke:#00838f,color:#004D56');
    L.Add('```');
    L.Add('');
    L.Add('| Step | What | Why this order |');
    L.Add('|:----:|------|----------------|');
    L.Add('| 1 | Start the beacon (`pascal_agent_service.exe`) | The beacon is the central registry. Neither the provider nor the gateway can do anything without it. |');
    L.Add('| 2 | Start the provider (`dotnet run`) | The provider connects to the beacon and advertises its tools. Tools must be registered *before* the gateway reads the registry. |');
    L.Add('| 3 | Start the MCP gateway (`mcp_api_tool.py`) | The gateway reads the beacon''s registry on startup. If the provider has not yet registered, the gateway sees an empty list. |');
    L.Add('| 4 | Connect the agent (LM Studio / Claude Desktop / ...) | The agent talks to the gateway; it can only see tools the gateway already exposes. |');
    L.Add('');
    L.Add('**Can I run steps 3 and 4 before step 2?** No. The gateway caches');
    L.Add('the tool list at startup, and the agent only sees what the gateway');
    L.Add('has exposed. Always start the provider first.');
    L.Add('');
    L.Add('**Can I restart the provider without restarting the gateway?** Yes,');
    L.Add('but only if your gateway implementation re-queries the beacon. The');
    L.Add('reference `mcp_api_tool.py` reads the registry once at startup; a');
    L.Add('provider restart therefore requires a gateway restart.');
    L.Add('');
  end;

  procedure EmitArchitecture;
  begin
    L.Add('## 3. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph Runtime["LingoFuse Runtime"]');
    L.Add('        BEACON["pascal_agent_service.exe<br/>(agent_main_app)"]');
    L.Add('        IPC["ipc:agent"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Provider["C# Tool Provider (this project)"]');
    L.Add('        REG_APIS["RegisterAPIs()<br/>create App + register Call APIs"]');
    L.Add('        PREPARE["Framework.PrepareClient<br/>Framework.PrepareDone"]');
    L.Add('        REG_TOOLS["RegisterTools()<br/>advertise tools to beacon"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Tools["Exposed APIs"]');
    L.Add('        T_API["' + umlIntToStr(TotalFuncCount) + ' Call APIs from ' + UnitName.Text + '"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Gateway["MCP Gateway"]');
    L.Add('        MCP["mcp_api_tool.py<br/>(stdio or http)"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["LLM Agent"]');
    L.Add('        LLM["LM Studio / Claude Desktop / ..."]');
    L.Add('    end');
    L.Add('');
    L.Add('    BEACON <--> IPC');
    L.Add('    REG_APIS --> PREPARE');
    L.Add('    PREPARE --> IPC');
    L.Add('    REG_TOOLS -->|register_agent| BEACON');
    L.Add('    MCP -->|read registry| BEACON');
    L.Add('    LLM -->|MCP protocol| MCP');
    L.Add('    MCP -->|invoke over IPC| IPC');
    L.Add('    IPC --> T_API');
    L.Add('');
    L.Add('    style Runtime fill:#e3f2fd,stroke:#1565c0,color:#0D2F52');
    L.Add('    style Provider fill:#fff3e0,stroke:#e65100,color:#7E5109');
    L.Add('    style Tools fill:#e8f5e9,stroke:#2e7d32,color:#0E4D2A');
    L.Add('    style Gateway fill:#f3e5f5,stroke:#6a1b9a,color:#4A148C');
    L.Add('    style Client fill:#e0f7fa,stroke:#00838f,color:#004D56');
    L.Add('```');
    L.Add('');
    L.Add('**Data flow at runtime**');
    L.Add('');
    L.Add('1. The agent sends an MCP `tools/call` request to the gateway.');
    L.Add('2. The gateway translates it into a `register_agent`/`Call` request');
    L.Add('   on the beacon.');
    L.Add('3. The beacon routes the call to the provider that registered the');
    L.Add('   matching tool name.');
    L.Add('4. The provider executes the corresponding');
    L.Add('   `InternalCall_<name>` method and returns a JSON result.');
    L.Add('5. The result travels back through the gateway to the agent.');
    L.Add('');
  end;

  procedure EmitPrerequisites;
  begin
    L.Add('## 4. Prerequisites and Environment Setup');
    L.Add('');
    L.Add('### 4.1 Install the .NET SDK');
    L.Add('');
    L.Add('Download and install the **.NET 8.0 SDK** (or later) from');
    L.Add('<https://dotnet.microsoft.com/download>.');
    L.Add('');
    L.Add('Verify the installation:');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet --version');
    L.Add('# Expected output: 8.0.x or later');
    L.Add('```');
    L.Add('');
    L.Add('### 4.2 Obtain the LingoFuse .NET binding');
    L.Add('');
    L.Add('Choose ONE of the following two options.');
    L.Add('');
    L.Add('**Option A - NuGet package (preferred if available)**:');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet add package LingoFuse');
    L.Add('```');
    L.Add('');
    L.Add('**Option B - Project reference to the binding source**:');
    L.Add('');
    L.Add('```bash');
    L.Add('git clone <lingofuse-dotnet-repo-url>');
    L.Add('cd my_provider');
    L.Add('dotnet add reference ../lingofuse-dotnet/LingoFuse/LingoFuse.csproj');
    L.Add('```');
    L.Add('');
    L.Add('**Option C - Manual reference to a prebuilt DLL**:');
    L.Add('');
    L.Add('Add the following to your `.csproj`:');
    L.Add('');
    L.Add('```xml');
    L.Add('<ItemGroup>');
    L.Add('  <Reference Include="LingoFuse">');
    L.Add('    <HintPath>libs/LingoFuse.dll</HintPath>');
    L.Add('  </Reference>');
    L.Add('</ItemGroup>');
    L.Add('```');
    L.Add('');
    L.Add('### 4.3 Place the native runtime library');
    L.Add('');
    L.Add('The managed binding needs a native library at runtime. Place it so');
    L.Add('the .NET runtime can find it:');
    L.Add('');
    L.Add('| Platform | File name | Where to put it |');
    L.Add('|----------|-----------|-----------------|');
    L.Add('| Windows | `LingoFuse64.dll` + `z_ipc_64.dll` | Next to the built `.exe`, or on `PATH` |');
    L.Add('| Linux   | `liblingofuse.so` + `libz_ipc_64.so` | Next to the built binary, or on `LD_LIBRARY_PATH` |');
    L.Add('| macOS   | `liblingofuse.dylib` + `libz_ipc_64.dylib` | Next to the built binary, or on `DYLD_LIBRARY_PATH` |');
    L.Add('');
    L.Add('Get these files from the LingoFuse runtime distribution or from the');
    L.Add('build output of LingoFuse-pasAgent-v3.');
    L.Add('');
    L.Add('### 4.4 Start the beacon (Step 1 of the startup order)');
    L.Add('');
    L.Add('In a **dedicated terminal**, start the beacon and leave it running:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('');
    L.Add('# Windows:');
    L.Add('pascal_agent_service.exe');
    L.Add('');
    L.Add('# Linux / macOS:');
    L.Add('./pascal_agent_service');
    L.Add('```');
    L.Add('');
    L.Add('The beacon listens on `ipc:agent`. **Do not close this terminal.**');
    L.Add('');
  end;

  procedure EmitProjectLayout;
  begin
    L.Add('## 5. Project Layout');
    L.Add('');
    L.Add('Create a fresh .NET console project and place the two generated');
    L.Add('`.cs` files inside it:');
    L.Add('');
    L.Add('```');
    L.Add('my_provider/');
    L.Add('  my_provider.csproj');
    L.Add('  ' + UnitName.Text + '_tool_provider.cs        <- provider class');
    L.Add('  ' + UnitName.Text + '_tool_provider_test.cs   <- test entry point');
    L.Add('  Program.cs                              <- DELETE the default one');
    L.Add('```');
    L.Add('');
    L.Add('**Important**: the default `dotnet new console` command generates a');
    L.Add('`Program.cs` file that already contains a `Main` method. Delete it,');
    L.Add('otherwise the compiler will report two entry points.');
    L.Add('');
    L.Add('### 5.1 Minimal `.csproj` template');
    L.Add('');
    L.Add('```xml');
    L.Add('<Project Sdk="Microsoft.NET.Sdk">');
    L.Add('');
    L.Add('  <PropertyGroup>');
    L.Add('    <OutputType>Exe</OutputType>');
    L.Add('    <TargetFramework>net8.0</TargetFramework>');
    L.Add('    <Nullable>enable</Nullable>');
    L.Add('    <ImplicitUsings>disable</ImplicitUsings>');
    L.Add('    <LangVersion>latest</LangVersion>');
    L.Add('    <RootNamespace>LingoFuseGenerated</RootNamespace>');
    L.Add('    <AssemblyName>' + AppName.Text + '_provider</AssemblyName>');
    L.Add('  </PropertyGroup>');
    L.Add('');
    L.Add('  <ItemGroup>');
    L.Add('    <!-- Option A: NuGet -->');
    L.Add('    <PackageReference Include="LingoFuse" Version="1.0.0" />');
    L.Add('');
    L.Add('    <!-- Option B: project reference (uncomment and adjust the path) -->');
    L.Add('    <!--');
    L.Add('    <ProjectReference Include="..\\lingofuse-dotnet\\LingoFuse\\LingoFuse.csproj" />');
    L.Add('    -->');
    L.Add('  </ItemGroup>');
    L.Add('');
    L.Add('</Project>');
    L.Add('```');
    L.Add('');
    L.Add('### 5.2 `<RootNamespace>` matters');
    L.Add('');
    L.Add('The generated code declares `namespace LingoFuseGenerated`. The');
    L.Add('`<RootNamespace>` property in the `.csproj` does not affect the');
    L.Add('generated files (they use fully qualified namespaces), but setting it');
    L.Add('to the same value keeps tooling and test scaffolding consistent.');
    L.Add('');
  end;

  procedure EmitBuild;
  begin
    L.Add('## 6. Build');
    L.Add('');
    L.Add('### 6.1 Debug build');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet build');
    L.Add('```');
    L.Add('');
    L.Add('Expected outcome: `bin/Debug/net8.0/' + AppName.Text + '_provider.dll`.');
    L.Add('');
    L.Add('### 6.2 Release build');
    L.Add('');
    L.Add('```bash');
    L.Add('dotnet build -c Release');
    L.Add('```');
    L.Add('');
    L.Add('### 6.3 Self-contained publish');
    L.Add('');
    L.Add('```bash');
    L.Add('# Windows x64');
    L.Add('dotnet publish -c Release -r win-x64 --self-contained true');
    L.Add('');
    L.Add('# Linux x64');
    L.Add('dotnet publish -c Release -r linux-x64 --self-contained true');
    L.Add('');
    L.Add('# macOS ARM64');
    L.Add('dotnet publish -c Release -r osx-arm64 --self-contained true');
    L.Add('```');
    L.Add('');
    L.Add('After publishing, copy the platform-specific native library');
    L.Add('(`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`) next');
    L.Add('to the published executable.');
    L.Add('');
    L.Add('### 6.4 Common build errors and fixes');
    L.Add('');
    L.Add('| Error | Cause | Fix |');
    L.Add('|-------|-------|-----|');
    L.Add('| `CS0246: type or namespace ''LingoFuse'' not found` | Binding not referenced | Add a `PackageReference` or `ProjectReference` (see section 4.2) |');
    L.Add('| `CS0017: Program has more than one entry point` | Default `Program.cs` still present | Delete it (section 5) |');
    L.Add('| `CS5001: Program does not contain a static ''Main'' method` | The test file is missing | Ensure `' + UnitName.Text + '_tool_provider_test.cs` is in the project |');
    L.Add('| `NETSDK1045: SDK does not support net8.0` | Old SDK installed | Install the .NET 8.0 SDK |');
    L.Add('');
  end;

  procedure EmitRunProcedure;
  begin
    L.Add('## 7. Run (detailed)');
    L.Add('');
    L.Add('This section describes each of the four steps in full detail. Follow');
    L.Add('them in order.');
    L.Add('');
    L.Add('```mermaid');
    L.Add('sequenceDiagram');
    L.Add('    participant Beacon as Beacon<br/>(pascal_agent_service.exe)');
    L.Add('    participant Provider as Provider<br/>(dotnet run)');
    L.Add('    participant Gateway as MCP Gateway<br/>(mcp_api_tool.py)');
    L.Add('    participant Agent as Agent<br/>(LM Studio / Claude)');
    L.Add('');
    L.Add('    Note over Beacon: Step 1');
    L.Add('    Beacon->>Beacon: listen on ipc:agent');
    L.Add('');
    L.Add('    Note over Provider: Step 2');
    L.Add('    Provider->>Beacon: LF_PrepareClient(ipc:agent)');
    L.Add('    Provider->>Beacon: register_agent (one call per tool)');
    L.Add('    Beacon-->>Provider: {"status":"ok"}');
    L.Add('');
    L.Add('    Note over Gateway: Step 3');
    L.Add('    Gateway->>Beacon: read tool registry');
    L.Add('    Beacon-->>Gateway: tool list');
    L.Add('');
    L.Add('    Note over Agent: Step 4');
    L.Add('    Agent->>Gateway: tools/list');
    L.Add('    Gateway-->>Agent: tool list');
    L.Add('    Agent->>Gateway: tools/call add {a:5, b:7}');
    L.Add('    Gateway->>Beacon: LF_Call(provider, "add")');
    L.Add('    Beacon->>Provider: dispatch to add callback');
    L.Add('    Provider-->>Beacon: {"result":12}');
    L.Add('    Beacon-->>Gateway: {"result":12}');
    L.Add('    Gateway-->>Agent: {"result":12}');
    L.Add('```');
    L.Add('');
    L.Add('### Step 2 - Start the provider');
    L.Add('');
    L.Add('Open a **second terminal** (keep the beacon terminal running):');
    L.Add('');
    L.Add('```bash');
    L.Add('cd my_provider');
    L.Add('dotnet run');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('==================================================');
    L.Add('  C# MCP Tool Provider Test');
    L.Add('==================================================');
    L.Add('');
    L.Add('Configuration:');
    L.Add('  App name   : ' + AppName.Text);
    L.Add('  App desc   : Tool provider for unit ' + UnitName.Text);
    L.Add('  IPC        : ipc:agent');
    L.Add('  Beacon app : agent_main_app');
    L.Add('  Register   : register_agent');
    L.Add('  Log API    : agent_log');
    L.Add('  Debug log  : True');
    L.Add('  APIs       : ' + umlIntToStr(TotalFuncCount) + '');
    L.Add('');
    L.Add('Connecting to ipc:agent ...');
    L.Add('');
    L.Add('[RegisterAPIs] Application ''' + AppName.Text + ''' created');
    L.Add('[RegisterAPIs] Registered ' + umlIntToStr(TotalFuncCount) + ' APIs');
    L.Add('[RegisterTools] Starting registration of ' + umlIntToStr(TotalFuncCount) + ' tools...');
    L.Add('[RegisterTools] OK: <api-name>');
    L.Add('...');
    L.Add('[RegisterTools] Registered ' + umlIntToStr(TotalFuncCount) + ' / ' + umlIntToStr(TotalFuncCount));
    L.Add('');
    L.Add('==================================================');
    L.Add('  [OK] Provider is ready. All tools registered.');
    L.Add('==================================================');
    L.Add('');
    L.Add('Next steps:');
    L.Add('  1. Start the MCP gateway:');
    L.Add('       python mcp_api_tool.py --transport stdio');
    L.Add('  2. Connect your agent (LM Studio / Claude Desktop / ...)');
    L.Add('     through the generated MCP config.');
    L.Add('');
    L.Add('Press Enter to shut down.');
    L.Add('```');
    L.Add('');
    L.Add('**Do not press Enter yet.** Keep the terminal open.');
    L.Add('');
    L.Add('### Step 3 - Start the MCP gateway');
    L.Add('');
    L.Add('The gateway bridges the MCP protocol (used by LLM agents) to the');
    L.Add('LingoFuse mesh. Open a **third terminal**:');
    L.Add('');
    L.Add('```bash');
    L.Add('cd LingoFuse-pasAgent-v3/src');
    L.Add('');
    L.Add('# Optionally generate client configs for your agent');
    L.Add('python mcp_api_tool.py --generate-configs --output-dir ./mcp_configs');
    L.Add('');
    L.Add('# Then start the gateway');
    L.Add('python mcp_api_tool.py --transport stdio');
    L.Add('```');
    L.Add('');
    L.Add('For HTTP transports instead of stdio:');
    L.Add('');
    L.Add('```bash');
    L.Add('python mcp_api_tool.py --transport http --host 127.0.0.1 --port 8000');
    L.Add('```');
    L.Add('');
    L.Add('### Step 4 - Connect the agent');
    L.Add('');
    L.Add('Depending on the agent:');
    L.Add('');
    L.Add('**LM Studio**');
    L.Add('');
    L.Add('1. Open LM Studio, then Settings -> MCP Servers.');
    L.Add('2. Copy the content of `mcp_configs/lmstudio_stdio.json` (or');
    L.Add('   `lmstudio_http.json` for HTTP transport).');
    L.Add('3. Restart LM Studio.');
    L.Add('4. In a chat, you should now see your tools in the tool list.');
    L.Add('');
    L.Add('**Claude Desktop**');
    L.Add('');
    L.Add('1. Locate `claude_desktop_config.json`:');
    L.Add('   - Windows: `%APPDATA%\\Claude\\claude_desktop_config.json`');
    L.Add('   - macOS:   `~/Library/Application Support/Claude/claude_desktop_config.json`');
    L.Add('2. Merge the `mcpServers` section from `mcp_configs/claude_stdio.json`.');
    L.Add('3. Restart Claude Desktop.');
    L.Add('');
    L.Add('**Continue.dev / Jan / DeepSeek / Generic MCP client**');
    L.Add('');
    L.Add('Merge the corresponding `mcp_configs/*.json` into the client''s MCP');
    L.Add('configuration file, then restart the client.');
    L.Add('');
    L.Add('### Verifying the whole chain');
    L.Add('');
    L.Add('Ask your agent to invoke a registered tool. For example, if the');
    L.Add('source unit registered `add(a: Int64, b: Int64): Int64`:');
    L.Add('');
    L.Add('```');
    L.Add('Please call the "add" tool with a=5 and b=7.');
    L.Add('```');
    L.Add('');
    L.Add('You should see:');
    L.Add('');
    L.Add('1. The agent discovers the tool through the gateway.');
    L.Add('2. The agent sends `tools/call` with `{"a": 5, "b": 7}`.');
    L.Add('3. The gateway forwards the request to the beacon.');
    L.Add('4. The beacon dispatches to the provider.');
    L.Add('5. The provider runs `InternalCall_add(5, 7)` and returns');
    L.Add('   `{"result": 12}`.');
    L.Add('');
    L.Add('In the provider terminal, you should see (with `DebugLog = true`):');
    L.Add('');
    L.Add('```');
    L.Add('[add] Input JSON: {"a":5,"b":7}');
    L.Add('[add] Called -> 12');
    L.Add('```');
    L.Add('');
    L.Add('### Shutting down');
    L.Add('');
    L.Add('Press Enter in the provider terminal. The program calls');
    L.Add('`ShutdownClean()`, which performs the orderly teardown:');
    L.Add('');
    L.Add('1. Clear any installed network event handlers.');
    L.Add('2. Stop the LingoFuse simulated main thread.');
    L.Add('3. Dispose the AppHandle.');
    L.Add('4. Release the framework''s process-wide resources.');
    L.Add('');
    L.Add('Then stop the gateway and the beacon with Ctrl+C.');
    L.Add('');
  end;

  procedure EmitToolReference;
  var
    ii, jj: integer;
  begin
    L.Add('## 8. Tool Reference');
    L.Add('');
    L.Add('Each exposed tool corresponds to one top-level function of');
    L.Add('`' + UnitName.Text + '`.');
    L.Add('');

    if TotalFuncCount = 0 then
    begin
      L.Add('> **WARNING: this provider exposes no APIs.**');
      L.Add('>');
      L.Add('> Possible reasons:');
      L.Add('> 1. The source unit has no top-level functions');
      L.Add('>    (nested routines in `class` / `record` are skipped).');
      L.Add('> 2. Every function failed the type check.');
      L.Add('>');
      L.Add('> Supported types: `Int64`, `Double`, `string` only.');
      L.Add('');
      Exit;
    end;

    L.Add('Total APIs: **' + umlIntToStr(TotalFuncCount) + '**.');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');
    for ii := 0 to High(ValidFuncs) do
    begin
      f := ValidFuncs[ii];
      shortDesc := GetTableCellText(f.Comment);
      if shortDesc.Len > 60 then
        shortDesc := shortDesc.GetString(1, 61) + '...';
      if f.IsFunction then
        row := '| ' + umlIntToStr(ii + 1).Text + ' | `' + MakeCSharpIdentifier(f.Name).Text + '` | function | ' +
          umlIntToStr(Length(f.Params)) + ' | `' + f.ReturnType.Text + '` | ' + shortDesc.Text + ' |'
      else
        row := '| ' + umlIntToStr(ii + 1).Text + ' | `' + MakeCSharpIdentifier(f.Name).Text + '` | procedure | ' +
          umlIntToStr(Length(f.Params)).Text + ' | - | ' + shortDesc.Text + ' |';
      L.Add(row);
    end;
    L.Add('');

    for ii := 0 to High(ValidFuncs) do
    begin
      f := ValidFuncs[ii];
      desc := GetFullDescription(f.Comment);

      L.Add('### 8.' + umlIntToStr(ii + 1).Text + ' `' + MakeCSharpIdentifier(f.Name).Text + '`');
      L.Add('');
      L.Add('- Original Pascal routine: `' + f.Name.Text + '`');
      L.Add('- Exposed API name: `' + MakeCSharpIdentifier(f.Name) + '`');
      if f.IsFunction then
        L.Add('- Kind: `function`, returns `' + f.ReturnType.Text + '`')
      else
        L.Add('- Kind: `procedure`');
      if desc.Len > 0 then
        L.Add('- Description: ' + desc.Text);
      L.Add('');

      if Length(f.Params) > 0 then
      begin
        L.Add('**Parameters**');
        L.Add('');
        L.Add('| Name | Pascal type | C# type | JSON type | Description |');
        L.Add('|------|-------------|---------|-----------|-------------|');
        for jj := 0 to High(f.Params) do
        begin
          L.Add('| `' + f.Params[jj].Name.Text + '` | `' + f.Params[jj].PascalType.Text + '` | `' + PascalTypeToCSharpType(f.Params[jj].PascalType) +
            '` | `' + PascalTypeToJsonSchemaType(f.Params[jj].PascalType) + '` | ' + GetTableCellText(f.Params[jj].Description).Text + ' |');
        end;
        L.Add('');
      end;

      L.Add('**Input JSON example**');
      L.Add('');
      L.Add('```json');
      if Length(f.Params) = 0 then
        L.Add('{}')
      else
      begin
        L.Add('{');
        for jj := 0 to High(f.Params) do
        begin
          row := '  "' + f.Params[jj].Name.Text + '": ' + PascalTypeToJsonLiteral(f.Params[jj].PascalType);
          if jj < High(f.Params) then row := row + ',';
          L.Add(row);
        end;
        L.Add('}');
      end;
      L.Add('```');
      L.Add('');

      L.Add('**Output JSON example**');
      L.Add('');
      L.Add('```json');
      if f.IsFunction then
        L.Add('{ "result": ' + PascalTypeToJsonLiteral(f.ReturnType) + ' }')
      else
        L.Add('{ "status": "ok" }');
      L.Add('```');
      L.Add('');
    end;
  end;

  procedure EmitJsonSchemaSpec;
  begin
    L.Add('## 9. JSON Schema Specification');
    L.Add('');
    L.Add('For each tool the provider sends a JSON Schema to the beacon through');
    L.Add('the `register_agent` API. The type whitelist is fixed by the');
    L.Add('normalized `TPascal_Func_Model` output.');
    L.Add('');
    L.Add('| Pascal normalized type | JSON Schema type | C# type | Example value |');
    L.Add('|------------------------|------------------|---------|---------------|');
    L.Add('| `int64` | `integer` | `long` | `42` |');
    L.Add('| `double` | `number` | `double` | `3.14` |');
    L.Add('| `string` | `string` | `string` | `"hello"` |');
    L.Add('');
    L.Add('**Every other type** (for example `Boolean`, arrays, records, objects,');
    L.Add('enums, interfaces, function pointers) is **NOT supported**. Functions');
    L.Add('that use them are silently dropped. If you need to pass a complex');
    L.Add('value, serialize it into a `string` first.');
    L.Add('');
  end;

  procedure EmitTroubleshooting;
  begin
    L.Add('## 10. Debugging and Troubleshooting');
    L.Add('');
    L.Add('### 10.1 Global configuration');
    L.Add('');
    L.Add('The generated provider exposes the following public constants and');
    L.Add('fields on the `' + ClassName.Text + '` class:');
    L.Add('');
    L.Add('| Name | Default | Purpose |');
    L.Add('|------|---------|---------|');
    L.Add('| `MY_APP_NAME` | `' + AppName.Text + '` | LingoFuse application name |');
    L.Add('| `MY_APP_DESC` | (auto) | Application description |');
    L.Add('| `IPC_ENDPOINT` | `ipc:agent` | IPC endpoint |');
    L.Add('| `BEACON_APP` | `agent_main_app` | Beacon application name |');
    L.Add('| `REGISTER_API` | `register_agent` | Tool-registration API name |');
    L.Add('| `AGENT_LOG_API` | `agent_log` | Log API name |');
    L.Add('| `DebugLog` | `true` | Verbose logging toggle |');
    L.Add('');
    L.Add('### 10.2 Enabling detailed logs');
    L.Add('');
    L.Add('Set `DebugLog = false` in `' + UnitName.Text + '_tool_provider.cs` to');
    L.Add('silence verbose output. When `true`, every callback prints its input');
    L.Add('JSON, its result, and any exception to both `Console.Out` and the');
    L.Add('beacon''s `agent_log` API.');
    L.Add('');
    L.Add('### 10.3 Common problems');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `CS0246: type or namespace ''LingoFuse'' not found` | Binding not referenced | See section 4.2 |');
    L.Add('| `CS0017: Program has more than one entry point` | Default `Program.cs` still present | Delete it (section 5) |');
    L.Add('| `DllNotFoundException: LingoFuse64.dll` | Native library not found | Place it next to the `.exe` (section 4.3) |');
    L.Add('| `[RegisterTools] No response from beacon` | Beacon not running | Start `pascal_agent_service.exe` first |');
    L.Add('| `[RegisterTools] FAIL: <name>` | Tool rejected by beacon | Check `DebugLog` output; verify JSON schema |');
    L.Add('| `Execute_And_Reg_all() returns false` | Beacon unreachable, or PrepareClient failed | Verify `IPC_ENDPOINT`; check for address conflicts |');
    L.Add('| `PrepareDone() returns 0` | Main thread already active in this process | Reuse the existing runtime, or call `Framework.Shutdown` first |');
    L.Add('| Tool missing from agent list | Gateway read the registry before the provider registered | Restart the gateway (Step 3) |');
    L.Add('| Tool missing from agent list (2) | Function filtered out | Check parameter and return types against section 9 |');
    L.Add('| `[<name>] Exception: ...` in log | Exception in user code | Implement the corresponding `InternalCall_<name>` stub |');
    L.Add('| Unicode mojibake in JSON payloads | Encoding mismatch | Ensure the caller sends UTF-8; the binding uses UTF-8 throughout |');
    L.Add('| Address already in use | Another client on `ipc:agent` | Stop the other process, or use `Overlap_Connection=True` |');
    L.Add('');
  end;

  procedure EmitPortability;
  begin
    L.Add('## 11. Portability');
    L.Add('');
    L.Add('The generated code targets **.NET 8.0** and uses only the BCL plus');
    L.Add('the LingoFuse binding.');
    L.Add('');
    L.Add('### 11.1 Supported runtimes');
    L.Add('');
    L.Add('| Runtime | Status |');
    L.Add('|---------|--------|');
    L.Add('| .NET 8.0 | Recommended; matches the binding''s target |');
    L.Add('| .NET 6.0 / 7.0 | May work; not officially tested |');
    L.Add('| .NET Framework 4.x | Not supported (the binding is .NET-only) |');
    L.Add('| Mono | Not supported |');
    L.Add('');
    L.Add('### 11.2 Supported platforms');
    L.Add('');
    L.Add('- **Windows** x64 (primary target).');
    L.Add('- **Linux** x64 (glibc or musl; glibc recommended).');
    L.Add('- **macOS** ARM64 and x64.');
    L.Add('');
    L.Add('### 11.3 Docker deployment');
    L.Add('');
    L.Add('A minimal `Dockerfile` based on the official .NET runtime image:');
    L.Add('');
    L.Add('```dockerfile');
    L.Add('FROM mcr.microsoft.com/dotnet/runtime:8.0 AS base');
    L.Add('WORKDIR /app');
    L.Add('');
    L.Add('FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build');
    L.Add('WORKDIR /src');
    L.Add('COPY . .');
    L.Add('RUN dotnet publish -c Release -o /app/publish');
    L.Add('');
    L.Add('FROM base AS final');
    L.Add('WORKDIR /app');
    L.Add('COPY --from=build /app/publish .');
    L.Add('# Copy the native runtime library too');
    L.Add('COPY libs/liblingofuse.so .');
    L.Add('COPY libs/libz_ipc_64.so .');
    L.Add('ENTRYPOINT ["dotnet", "' + AppName.Text + '_provider.dll"]');
    L.Add('```');
    L.Add('');
    L.Add('### 11.4 Windows deployment as a service');
    L.Add('');
    L.Add('To run the provider as a Windows service, wrap the published');
    L.Add('executable with NSSM or WinSW:');
    L.Add('');
    L.Add('```bat');
    L.Add('nssm install MyCSharpProvider "C:\\path\\to\\' + AppName.Text + '_provider.exe"');
    L.Add('nssm start  MyCSharpProvider');
    L.Add('```');
    L.Add('');
    L.Add('### 11.5 Linux systemd unit');
    L.Add('');
    L.Add('```ini');
    L.Add('[Unit]');
    L.Add('Description=LingoFuse C# Tool Provider');
    L.Add('After=network.target');
    L.Add('');
    L.Add('[Service]');
    L.Add('Type=simple');
    L.Add('ExecStart=/opt/lingofuse/' + AppName.Text + '_provider');
    L.Add('Restart=on-failure');
    L.Add('RestartSec=3');
    L.Add('');
    L.Add('[Install]');
    L.Add('WantedBy=multi-user.target');
    L.Add('```');
    L.Add('');
  end;

  procedure EmitResources;
  begin
    L.Add('## 12. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| Standalone `LingoFuse` .NET package (if available) | Preferred source of the `LingoFuse` namespace |');
    L.Add('| `LingoFuse-pasAgent-v3` repository | Fallback source of the .NET binding, plus beacon and MCP gateway |');
    L.Add('| `LingoFuse_CSharp_Complete_Guide.md` | Full reference for the C# binding |');
    L.Add('| `<v3>/src/pascal_agent_service.lpr` | Beacon server source |');
    L.Add('| `<v3>/src/mcp_api_tool.py` | MCP gateway that exposes the tools |');
    L.Add('| `<v3>/src/generate_agent_json.py` | MCP client config generator |');
    L.Add('| <https://dotnet.microsoft.com/download> | .NET SDK downloads |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('_End of document. Generated by `csharp_mcp_generator_tool.pas`._');
    L.Add('');
  end;

begin
  Result := nil;

  if Model = nil then
  begin
    Result := TPascalStringList.Create;
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: supplied `TPascal_Func_Model` is nil.');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName = '' then
  begin
    Result := TPascalStringList.Create;
    Result.Add('# README generation skipped');
    Result.Add('');
    Result.Add('Reason: `Model.UnitName` is empty.');
    Exit;
  end;

  AppName := MakeAppNameFromUnit(UnitName);
  ClassName := MakeProviderClassName(AppName);
  ValidFuncs := CollectValidFunctions(Model);
  TotalFuncCount := Length(ValidFuncs);

  L := TPascalStringList.Create;
  try
    EmitHeader;
    EmitOverview;
    EmitStartupOrder;
    EmitArchitecture;
    EmitPrerequisites;
    EmitProjectLayout;
    EmitBuild;
    EmitRunProcedure;
    EmitToolReference;
    EmitJsonSchemaSpec;
    EmitTroubleshooting;
    EmitPortability;
    EmitResources;

    Result := L;
    Log(PFormat('GenerateCSharpReadme: done, %d lines, %d APIs.', [L.Count, TotalFuncCount]));
  except
    L.Free;
    raise;
  end;
end;

end.
