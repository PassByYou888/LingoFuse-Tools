unit http_csharp_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

// GenerateHTTPServiceCsharpCode - generate the C# HTTP/JSON service
// module. The returned list is owned by the caller and must be
// released with DisposeObject.
function GenerateHTTPServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[http_csharp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_csharp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

// ABI_Type_To_Json_Extractor - the JsonArgs helper method name used to
// pull this parameter out of the request JSON envelope.
function ABI_Type_To_Json_Extractor(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'GetInt32'
  else if T.Same('int64') then
    Result := 'GetInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'GetUInt32'
  else if T.Same('word') then
    Result := 'GetUInt16'
  else if T.Same('smallint') then
    Result := 'GetInt16'
  else if T.Same('byte') then
    Result := 'GetByte'
  else if T.Same('uint64') then
    Result := 'GetUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'GetDouble'
  else if T.Same('single') then
    Result := 'GetSingle'
  else if ABI_Type_Is_String(T) then
    Result := 'GetString'
  else
    Result := '';
end;

// ABI_Type_To_CSharp_Default - literal used in a stub body before the
// user fills it in.
function ABI_Type_To_CSharp_Default(const T: TP_String): TP_String;
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

// ABI_Type_To_Json_Wire_Type - coarse wire type, used by the README only.
function ABI_Type_To_Json_Wire_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'string'
  else if ABI_Type_Is_Float(T) or ABI_Type_Is_Int(T) then
    Result := 'number'
  else
    Result := '';
end;

// ============================================================================
// Identifier helpers
// ============================================================================

// MakeApiName - canonicalize a routine name into an identifier that is
// simultaneously safe as a URL path segment, a JSON object key, and an
// identifier in C#, Pascal, Python, and JavaScript.
//
// The replacement set MUST match every other generator in this
// toolchain.
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
// Comment description extraction
// ============================================================================

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

// ============================================================================
// Parameter helpers
// ============================================================================

function BuildCSharpParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCSharpParamName(Params[i].Name, i);
    PTyp := ABI_Type_To_CSharp_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PTyp + ' ' + PName;
  end;
end;

function BuildCSharpArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCSharpParamName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

// BuildPascalDecl - full Pascal declaration, used by the README only.
function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
  PascalType: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeCSharpParamName(F.Params[i].Name, i);
    PascalType := F.Params[i].PascalType;
    decl := PascalType;
    if i > 0 then
      ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;

  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' + F.ReturnType + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
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

// ============================================================================
// C# SERVICE MODULE GENERATOR
// ============================================================================

procedure EmitCSharpHeader(Lines: TPascalStringList;
  const UnitName, NsName, AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('// Auto-generated by http_csharp_abi_service_generator_tool.pas.');
  Lines.Add('// Source model unit: ' + UnitName.Text + '.');
  Lines.Add('// Do not edit by hand unless you know what you are doing.');
  Lines.Add('//');
  Lines.Add('// HTTP/JSON ABI service module for C#.');
  Lines.Add('//');
  Lines.Add('// This module uses the LingoFuse .NET binding (namespace LingoFuse)');
  Lines.Add('// rather than direct P/Invoke. The binding provides:');
  Lines.Add('//   * AppHandle  - RAII application container');
  Lines.Add('//   * DataHandle - RAII data buffer');
  Lines.Add('//   * LfIo       - the single sanctioned JSON/string I/O path');
  Lines.Add('//   * Framework  - process-wide lifecycle facade');
  Lines.Add('//   * NetworkEvents - process-global connect/disconnect events');
  Lines.Add('//');
  Lines.Add('// Wire protocol (both directions):');
  Lines.Add('//   request  = {"args": [v1, v2, ...]}      positional arguments');
  Lines.Add('//              {"a": v1, "b": v2, ...}      named arguments');
  Lines.Add('//   response = {"code": 0, "result": ...}   on success');
  Lines.Add('//              {"code": -1, "error":  ...}  on failure');
  Lines.Add('//');
  Lines.Add('// These shapes match the Pascal, Python, JavaScript, and C++');
  Lines.Add('// HTTP/JSON service generators, so any of them can call each');
  Lines.Add('// other through bridge.py without changes.');
  Lines.Add('//');
  Lines.Add('// This file contains NO Main entry point. It is meant to be');
  Lines.Add('// compiled as a class library. Provide your own Main that calls');
  Lines.Add('// ' + NsName.Text + '.Service.RunService(), or use the companion test');
  Lines.Add('// program generator.');
  Lines.Add('//');
  Lines.Add('// Target framework: .NET 8.0 or later.');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('using System;');
  Lines.Add('using System.Text.Json;');
  Lines.Add('using System.Threading;');
  Lines.Add('using LingoFuse;');
  Lines.Add('');
  Lines.Add('namespace ' + NsName.Text);
  Lines.Add('{');
  Lines.Add('');
end;

procedure EmitCSharpAppInfo(Lines: TPascalStringList;
  const AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // Application metadata.');
  Lines.Add('    //');
  Lines.Add('    // The AppName is the mesh-wide identifier used for routing. The');
  Lines.Add('    // Endpoint is the LingoFuse endpoint the service binds to. bridge.py');
  Lines.Add('    // must be started with the same --endpoint value.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class AppInfo');
  Lines.Add('    {');
  Lines.Add('        public const string Name = ' + CSharpStrLit(AppName) + ';');
  Lines.Add('        public const string Desc = ' + CSharpStrLit(AppDesc) + ';');
  Lines.Add('        public const string Endpoint = ' + CSharpStrLit(Endpoint) + ';');
  Lines.Add('        public const bool DebugLog = false;');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCSharpJsonArgs(Lines: TPascalStringList);
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // JsonArgs - request envelope navigation helpers.');
  Lines.Add('    //');
  Lines.Add('    // The wire protocol accepts two request shapes:');
  Lines.Add('    //   {"args": [v1, v2, ...]}      positional arguments');
  Lines.Add('    //   {"a": v1, "b": v2, ...}      named arguments');
  Lines.Add('    //');
  Lines.Add('    // If the "args" field is present, positional extraction is used and');
  Lines.Add('    // named lookup is skipped. Otherwise, every parameter is looked up');
  Lines.Add('    // by its original Pascal name.');
  Lines.Add('    //');
  Lines.Add('    // Type policy (matches every other HTTP/JSON generator):');
  Lines.Add('    //   * Integer parameters accept a JSON integer or a numeric string.');
  Lines.Add('    //   * Floating-point parameters accept a JSON number only.');
  Lines.Add('    //   * String parameters accept a JSON string only.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    internal static class JsonArgs');
  Lines.Add('    {');
  Lines.Add('        // Try to get the raw JsonElement for the given parameter.');
  Lines.Add('        public static bool TryGet(JsonElement req, string name, int index,');
  Lines.Add('            out JsonElement value)');
  Lines.Add('        {');
  Lines.Add('            value = default;');
  Lines.Add('            if (req.ValueKind != JsonValueKind.Object) return false;');
  Lines.Add('');
  Lines.Add('            if (req.TryGetProperty("args", out var args))');
  Lines.Add('            {');
  Lines.Add('                if (args.ValueKind != JsonValueKind.Array) return false;');
  Lines.Add('                int i = 0;');
  Lines.Add('                foreach (var e in args.EnumerateArray())');
  Lines.Add('                {');
  Lines.Add('                    if (i == index) { value = e; return true; }');
  Lines.Add('                    i++;');
  Lines.Add('                }');
  Lines.Add('                return false;');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            if (req.TryGetProperty(name, out var named))');
  Lines.Add('            {');
  Lines.Add('                value = named;');
  Lines.Add('                return true;');
  Lines.Add('            }');
  Lines.Add('            return false;');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // Extract a 64-bit signed integer.');
  Lines.Add('        public static long GetInt64(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            switch (e.ValueKind)');
  Lines.Add('            {');
  Lines.Add('                case JsonValueKind.Number:');
  Lines.Add('                    if (e.TryGetInt64(out var l)) return l;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an integer: " + name);');
  Lines.Add('                case JsonValueKind.String:');
  Lines.Add('                    if (long.TryParse(e.GetString(), out var s)) return s;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an integer: " + name);');
  Lines.Add('                default:');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an integer: " + name);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static int GetInt32(JsonElement req, string name, int index)');
  Lines.Add('            => checked((int)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static short GetInt16(JsonElement req, string name, int index)');
  Lines.Add('            => checked((short)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static byte GetByte(JsonElement req, string name, int index)');
  Lines.Add('            => checked((byte)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static uint GetUInt32(JsonElement req, string name, int index)');
  Lines.Add('            => checked((uint)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        public static ushort GetUInt16(JsonElement req, string name, int index)');
  Lines.Add('            => checked((ushort)GetInt64(req, name, index));');
  Lines.Add('');
  Lines.Add('        // Extract a 64-bit unsigned integer.');
  Lines.Add('        public static ulong GetUInt64(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            switch (e.ValueKind)');
  Lines.Add('            {');
  Lines.Add('                case JsonValueKind.Number:');
  Lines.Add('                    if (e.TryGetUInt64(out var u)) return u;');
  Lines.Add('                    if (e.TryGetInt64(out var l) && l >= 0) return (ulong)l;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an unsigned integer: " + name);');
  Lines.Add('                case JsonValueKind.String:');
  Lines.Add('                    if (ulong.TryParse(e.GetString(), out var s)) return s;');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an unsigned integer: " + name);');
  Lines.Add('                default:');
  Lines.Add('                    throw new ArgumentException(');
  Lines.Add('                        "Argument is not an unsigned integer: " + name);');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // Extract a 64-bit IEEE 754 floating-point number.');
  Lines.Add('        public static double GetDouble(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            if (e.ValueKind != JsonValueKind.Number)');
  Lines.Add('                throw new ArgumentException(');
  Lines.Add('                    "Argument is not a number: " + name);');
  Lines.Add('            return e.GetDouble();');
  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        public static float GetSingle(JsonElement req, string name, int index)');
  Lines.Add('            => (float)GetDouble(req, name, index);');
  Lines.Add('');
  Lines.Add('        // Extract a UTF-8 string.');
  Lines.Add('        public static string GetString(JsonElement req, string name, int index)');
  Lines.Add('        {');
  Lines.Add('            if (!TryGet(req, name, index, out var e))');
  Lines.Add('                throw new ArgumentException("Missing argument: " + name);');
  Lines.Add('            if (e.ValueKind != JsonValueKind.String)');
  Lines.Add('                throw new ArgumentException(');
  Lines.Add('                    "Argument is not a string: " + name);');
  Lines.Add('            return e.GetString() ?? "";');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCSharpStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  f: TFunctionStructure;
  ApiName, ParamDecl, ArgList, RetType: TP_String;
  Description: TP_String;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // InternalCalls - one stub per API.');
  Lines.Add('    //');
  Lines.Add('    // This is the ONLY class you are expected to edit. Replace each');
  Lines.Add('    // TODO body with a call to the real implementation, for example:');
  Lines.Add('    //     return MyNamespace.MyClass.Add(a, b);');
  Lines.Add('    //');
  Lines.Add('    // The parameter names and types are already correct. The stub');
  Lines.Add('    // body runs on a native worker thread, so it must be thread-safe');
  Lines.Add('    // and must never call a blocking LingoFuse function');
  Lines.Add('    // (Framework.Call, Framework.Notify, Framework.SequencedNotify,');
  Lines.Add('    // AppHandle.LocalCall, AppHandle.LocalNotify, Framework.PrepareDone,');
  Lines.Add('    // Framework.Shutdown).');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class InternalCalls');
  Lines.Add('    {');

  for i := 0 to High(SupportedFuncs) do
  begin
    f := SupportedFuncs[i];
    ApiName := ApiNames[i];
    ParamDecl := BuildCSharpParamList(f.Params);
    ArgList := BuildCSharpArgList(f.Params);
    RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);

    Description := GetFullDescription(f.Comment);
    if Description.Len > 0 then
      Lines.Add('        // ' + Description.Text);

    Lines.Add('');
    if f.IsFunction then
      Lines.Add('        public static ' + RetType + ' ' + ApiName + '(' + ParamDecl + ')')
    else
      Lines.Add('        public static void ' + ApiName + '(' + ParamDecl + ')');
    Lines.Add('        {');
    Lines.Add('            // TODO: replace the body with a call to the real implementation.');
    if Length(f.Params) > 0 then
      Lines.Add('            // Suggested call: ' + f.Name.Text + '(' + ArgList + ');')
    else
      Lines.Add('            // Suggested call: ' + f.Name.Text + '();');
    if f.IsFunction then
      Lines.Add('            return ' + ABI_Type_To_CSharp_Default(f.ReturnType) + ';');
    Lines.Add('        }');
  end;

  Lines.Add('    }');
  Lines.Add('');
end;

procedure EmitCSharpRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  f: TFunctionStructure;
  ApiName, RetType, PName, Extractor, ParamNameLit, IdxLit: TP_String;
  Description: TP_String;
  HasParams: boolean;
begin
  Lines.Add('    // ======================================================================');
  Lines.Add('    // Service - registration and entry point.');
  Lines.Add('    // ======================================================================');
  Lines.Add('    public static class Service');
  Lines.Add('    {');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // Register every supported API on the given application.');
  Lines.Add('        //');
  Lines.Add('        // Each API is registered with a callback that reads the JSON');
  Lines.Add('        // request envelope, extracts the arguments, invokes the');
  Lines.Add('        // corresponding InternalCalls stub, and writes the JSON');
  Lines.Add('        // response envelope.');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        public static void RegisterAPIs(AppHandle app)');
  Lines.Add('        {');

  for i := 0 to High(SupportedFuncs) do
  begin
    f := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(f.Params) > 0;
    RetType := ABI_Type_To_CSharp_Decl(f.ReturnType);
    Description := GetFullDescription(f.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    Lines.Add('');
    Lines.Add('            // ---- ' + ApiName.Text + ' ----');

    if f.IsFunction then
    begin
      Lines.Add('            app.RegisterCall(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ',');
      Lines.Add('                ' + CSharpStrLit(Description) + ',');
      Lines.Add('                (input, output) =>');
      Lines.Add('                {');
      Lines.Add('                    try');
      Lines.Add('                    {');
      Lines.Add('                        var req = LfIo.ReadJson<JsonElement>(input);');

      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        Extractor := ABI_Type_To_Json_Extractor(f.Params[j].PascalType);
        ParamNameLit := CSharpStrLit(f.Params[j].Name);
        IdxLit := umlIntToStr(j);
        Lines.Add('                        var ' + PName + ' = JsonArgs.' +
          Extractor + '(req, ' + ParamNameLit + ', ' + IdxLit + ');');
      end;

      Lines.Add('');
      if HasParams then
        Lines.Add('                        var result = InternalCalls.' + ApiName +
          '(' + BuildCSharpArgList(f.Params) + ');')
      else
        Lines.Add('                        var result = InternalCalls.' + ApiName + '();');
      Lines.Add('                        LfIo.WriteJson(output, new { code = 0, result });');
      Lines.Add('                    }');
      Lines.Add('                    catch (Exception ex)');
      Lines.Add('                    {');
      Lines.Add('                        try');
      Lines.Add('                        {');
      Lines.Add('                            LfIo.WriteJson(output, new { code = -1, error = ex.Message });');
      Lines.Add('                        }');
      Lines.Add('                        catch');
      Lines.Add('                        {');
      Lines.Add('                            // The output handle is unusable.');
      Lines.Add('                        }');
      Lines.Add('                    }');
      Lines.Add('                });');
    end
    else
    begin
      Lines.Add('            app.RegisterCall(');
      Lines.Add('                ' + CSharpStrLit(ApiName) + ',');
      Lines.Add('                ' + CSharpStrLit(Description) + ',');
      Lines.Add('                (input, output) =>');
      Lines.Add('                {');
      Lines.Add('                    try');
      Lines.Add('                    {');
      Lines.Add('                        var req = LfIo.ReadJson<JsonElement>(input);');

      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCSharpParamName(f.Params[j].Name, j);
        Extractor := ABI_Type_To_Json_Extractor(f.Params[j].PascalType);
        ParamNameLit := CSharpStrLit(f.Params[j].Name);
        IdxLit := umlIntToStr(j);
        Lines.Add('                        var ' + PName + ' = JsonArgs.' +
          Extractor + '(req, ' + ParamNameLit + ', ' + IdxLit + ');');
      end;

      Lines.Add('');
      if HasParams then
        Lines.Add('                        InternalCalls.' + ApiName +
          '(' + BuildCSharpArgList(f.Params) + ');')
      else
        Lines.Add('                        InternalCalls.' + ApiName + '();');
      Lines.Add('                        LfIo.WriteJson(output, new { code = 0 });');
      Lines.Add('                    }');
      Lines.Add('                    catch (Exception ex)');
      Lines.Add('                    {');
      Lines.Add('                        try');
      Lines.Add('                        {');
      Lines.Add('                            LfIo.WriteJson(output, new { code = -1, error = ex.Message });');
      Lines.Add('                        }');
      Lines.Add('                        catch');
      Lines.Add('                        {');
      Lines.Add('                            // The output handle is unusable.');
      Lines.Add('                        }');
      Lines.Add('                    }');
      Lines.Add('                });');
    end;
  end;

  Lines.Add('        }');
  Lines.Add('');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        // RunService - full startup, run loop, and clean shutdown.');
  Lines.Add('        //');
  Lines.Add('        // Returns 0 on success, 1 on a fatal startup error.');
  Lines.Add('        //');
  Lines.Add('        // Call this method from your own Main:');
  Lines.Add('        //     static int Main(string[] args)');
  Lines.Add('        //         => <namespace>.Service.RunService();');
  Lines.Add('        // ----------------------------------------------------------------');
  Lines.Add('        public static int RunService()');
  Lines.Add('        {');
  Lines.Add('            Console.WriteLine("=== " + AppInfo.Name + " HTTP/JSON service ===");');
  Lines.Add('            Console.WriteLine("Endpoint: " + AppInfo.Endpoint);');
  Lines.Add('');
  Lines.Add('            // Deployment mode: do not block waiting for peers that are not');
  Lines.Add('            // yet ready. This lets bridge.py and this service start in any');
  Lines.Add('            // order.');
  Lines.Add('            Framework.SetOption("Wait_Connection_ReadyOk", "False");');
  Lines.Add('            // Allow multiple clients on the same address so that a bridge');
  Lines.Add('            // restart does not require a service restart.');
  Lines.Add('            Framework.SetOption("Overlap_Connection", "True");');
  Lines.Add('');
  Lines.Add('            Framework.ResetPrepare();');
  Lines.Add('');
  Lines.Add('            if (Framework.PrepareService(AppInfo.Endpoint, AppInfo.Endpoint) < 0)');
  Lines.Add('            {');
  Lines.Add('                Console.Error.WriteLine("[FATAL] PrepareService failed: " + AppInfo.Endpoint);');
  Lines.Add('                return 1;');
  Lines.Add('            }');
  Lines.Add('');
  Lines.Add('            AppHandle? app = null;');
  Lines.Add('            try');
  Lines.Add('            {');
  Lines.Add('                app = new AppHandle(AppInfo.Name, AppInfo.Desc);');
  Lines.Add('                RegisterAPIs(app);');
  Lines.Add('');
  Lines.Add('                if (Framework.PrepareClient(AppInfo.Endpoint, app) < 0)');
  Lines.Add('                {');
  Lines.Add('                    Console.Error.WriteLine("[FATAL] PrepareClient failed: " + AppInfo.Endpoint);');
  Lines.Add('                    return 1;');
  Lines.Add('                }');
  Lines.Add('');
  Lines.Add('                if (Framework.PrepareDone() != 1)');
  Lines.Add('                {');
  Lines.Add('                    Console.Error.WriteLine("[FATAL] PrepareDone failed.");');
  Lines.Add('                    return 1;');
  Lines.Add('                }');
  Lines.Add('');
  Lines.Add('                Console.WriteLine("[OK] Service ready. Press Ctrl+C to stop.");');
  Lines.Add('');
  Lines.Add('                var stop = new ManualResetEventSlim(false);');
  Lines.Add('                Console.CancelKeyPress += (s, e) =>');
  Lines.Add('                {');
  Lines.Add('                    e.Cancel = true;');
  Lines.Add('                    stop.Set();');
  Lines.Add('                };');
  Lines.Add('');
  Lines.Add('                while (!stop.IsSet)');
  Lines.Add('                    Thread.Sleep(500);');
  Lines.Add('');
  Lines.Add('                Console.WriteLine("Shutting down...");');
  Lines.Add('                return 0;');
  Lines.Add('            }');
  Lines.Add('            finally');
  Lines.Add('            {');
  Lines.Add('                // Required cleanup order:');
  Lines.Add('                //   NetworkEvents.Clear() -> ExitMainThread');
  Lines.Add('                //   -> app.Dispose() -> Shutdown');
  Lines.Add('                try { NetworkEvents.Clear(); } catch { }');
  Lines.Add('                try { Framework.ExitMainThread(); } catch { }');
  Lines.Add('                try { app?.Dispose(); } catch { }');
  Lines.Add('                try { Framework.Shutdown(); } catch { }');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPServiceCsharpCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc, Endpoint: TP_String;
  UsedApiNames, ApiNames: TPascalStringList;
  ApiName: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceCsharpCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceCsharpCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  NsName := NormalizedUnit + '_http_json_service';
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating C# HTTP/JSON service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  UsedApiNames := TPascalStringList.Create;
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    for i := 0 to High(SupportedFuncs) do
    begin
      ApiName := MakeApiName(SupportedFuncs[i].Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      ApiNames.Add(ApiName);
    end;

    EmitCSharpHeader(Lines, UnitName, NsName, AppName, AppDesc, Endpoint);
    EmitCSharpAppInfo(Lines, AppName, AppDesc, Endpoint);
    EmitCSharpJsonArgs(Lines);
    EmitCSharpStubs(Lines, SupportedFuncs, ApiNames);
    EmitCSharpRegistration(Lines, SupportedFuncs, ApiNames);

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
    'csharp', 'C# HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.cs', False,
    @GenerateHTTPServiceCsharpCode);
end.
