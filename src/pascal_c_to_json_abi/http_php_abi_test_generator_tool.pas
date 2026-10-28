unit http_php_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallPhpTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_php_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_php_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

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

function ABI_Type_To_Php_Decl(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then Result := 'string'
  else if ABI_Type_Is_Float(T) then Result := 'float'
  else if ABI_Type_Is_Int(T) then Result := 'int'
  else Result := 'mixed';
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

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsPhpReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('__halt_compiler') or S.Same('abstract') or S.Same('and') or
    S.Same('array') or S.Same('as') or S.Same('break') or
    S.Same('callable') or S.Same('case') or S.Same('catch') or
    S.Same('class') or S.Same('clone') or S.Same('const') or
    S.Same('continue') or S.Same('declare') or S.Same('default') or
    S.Same('die') or S.Same('do') or S.Same('echo') or
    S.Same('else') or S.Same('elseif') or S.Same('empty') or
    S.Same('enddeclare') or S.Same('endfor') or S.Same('endforeach') or
    S.Same('endif') or S.Same('endswitch') or S.Same('endwhile') or
    S.Same('eval') or S.Same('exit') or S.Same('extends') or
    S.Same('final') or S.Same('finally') or S.Same('fn') or
    S.Same('for') or S.Same('foreach') or S.Same('function') or
    S.Same('global') or S.Same('goto') or S.Same('if') or
    S.Same('implements') or S.Same('include') or S.Same('include_once') or
    S.Same('instanceof') or S.Same('insteadof') or S.Same('interface') or
    S.Same('isset') or S.Same('list') or S.Same('match') or
    S.Same('namespace') or S.Same('new') or S.Same('or') or
    S.Same('print') or S.Same('private') or S.Same('protected') or
    S.Same('public') or S.Same('readonly') or S.Same('require') or
    S.Same('require_once') or S.Same('return') or S.Same('static') or
    S.Same('switch') or S.Same('throw') or S.Same('trait') or
    S.Same('try') or S.Same('unset') or S.Same('use') or
    S.Same('var') or S.Same('while') or S.Same('xor') or
    S.Same('yield');
end;

function SanitizePhpIdentifier(const Name: TP_String; Index: integer): TP_String;
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
end;

function MakeSafePhpMethodName(const Name: TP_String; Index: integer): TP_String;
begin
  Result := SanitizePhpIdentifier(MakeApiName(Name), Index);
  if IsPhpReservedWord(Result) then
    Result := Result + '_';
end;

function MakeSafePhpNamespace(const Name: TP_String): TP_String;
begin
  Result := SanitizePhpIdentifier(Name, 0);
  if Result.Len = 0 then
    Result := 'LingoFuseApi';
  if IsPhpReservedWord(Result) then
    Result := Result + '_';
end;

function PhpStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if (c = #39) or (c = #92) then
      Result.Append('\' + c)
    else
      Result.Append(c);
  end;
  Result.Append(#39);
end;

function MdCellEscape(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '|' then Result.Append('\|')
    else if c = #10 then Result.Append(' ')
    else if c = #13 then
    else Result.Append(c);
  end;
end;

function MdInt(const V: integer): TP_String;
begin
  Result := umlIntToStr(V);
end;

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  if T.Len > 0 then
  begin
    if T[1] = '{' then T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;
  if T.Len > 0 then
  begin
    if T[T.Len] = '}' then T := T.GetString(1, T.Len).TrimChar(#32#9)
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

function BuildPhpParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := SanitizePhpIdentifier(Params[i].Name, i);
    T := ABI_Type_To_Php_Decl(Params[i].PascalType);
    if i > 0 then Result := Result + ', ';
    Result := Result + T + ' $' + n;
  end;
end;

function BuildPhpDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  d: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if ABI_Type_Is_String(Params[i].PascalType) then
      d := #39#39
    else if ABI_Type_Is_Float(Params[i].PascalType) then
      d := '0.0'
    else
      d := '0';
    if i > 0 then Result := Result + ', ';
    Result := Result + d;
  end;
end;

function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := SanitizePhpIdentifier(F.Params[i].Name, i);
    decl := ABI_Type_To_Pascal_Decl(F.Params[i].PascalType);
    if i > 0 then ParamDecl := ParamDecl + '; ';
    ParamDecl := ParamDecl + n + ': ' + decl;
  end;
  if F.IsFunction then
    Result := 'function ' + F.Name.Text + '(' + ParamDecl + '): ' +
      ABI_Type_To_Pascal_Decl(F.ReturnType) + ';'
  else
    Result := 'procedure ' + F.Name.Text + '(' + ParamDecl + ');';
end;

function BuildPhpSignature(const F: TFunctionStructure; const MethodName: TP_String): TP_String;
var
  ParamPart, RetType: TP_String;
begin
  ParamPart := BuildPhpParamList(F.Params);
  if ParamPart.Len > 0 then
    ParamPart := ParamPart + ', array $options = []'
  else
    ParamPart := 'array $options = []';
  if F.IsFunction then
    RetType := ': ' + ABI_Type_To_Php_Decl(F.ReturnType)
  else
    RetType := ': void';
  Result := 'public static function ' + MethodName + '(' + ParamPart + ')' + RetType;
end;

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
        Log('Skipped "%s": parameter "%s" has unsupported ABI type "%s"',
          [F.Name.Text, F.Params[j].Name.Text, F.Params[j].PascalType.Text]);
        Break;
      end;
    if Supported and F.IsFunction and
       (not ABI_Type_Is_Supported(F.ReturnType)) then
    begin
      Supported := False;
      Log('Skipped "%s": return type "%s" is not a supported ABI type',
        [F.Name.Text, F.ReturnType.Text]);
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

procedure BuildDisambiguatedPhpApiNames(
  const SupportedFuncs: TArryFunctionStructure;
  ApiNames: TPascalStringList);
var
  i, j, k: integer;
  Base, Candidate: TP_String;
  Conflict: boolean;
begin
  ApiNames.Clear;
  for i := 0 to High(SupportedFuncs) do
  begin
    Base := MakeSafePhpMethodName(SupportedFuncs[i].Name, i);
    Conflict := False;
    for j := 0 to ApiNames.Count - 1 do
      if ApiNames[j].Same(Base) then
      begin
        Conflict := True;
        Break;
      end;
    if Conflict then
    begin
      k := 1;
      repeat
        Candidate := Base + '_' + umlIntToStr(k).Text;
        Conflict := False;
        for j := 0 to ApiNames.Count - 1 do
          if ApiNames[j].Same(Candidate) then
          begin
            Conflict := True;
            Break;
          end;
        if not Conflict then
        begin
          Base := Candidate;
          Break;
        end;
        Inc(k);
      until False;
    end;
    ApiNames.Add(Base);
  end;
end;

function GenerateHTTPCallPhpTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, SafeNamespace, CallModuleName, DefaultBaseUrl, FileName: TP_String;
  ApiNames: TPascalStringList;
  ApiName, DefaultArgs: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
  HasParams: boolean;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  SafeNamespace := MakeSafePhpNamespace(UnitName);
  CallModuleName := UnitName + '_http_json_call_php';
  DefaultBaseUrl := 'http://127.0.0.1:8081/' + UnitName;
  FileName := UnitName + '_http_json_call_main_test___.php';

  SupportedFuncs := CollectSupportedFunctions(Model);
  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedPhpApiNames(SupportedFuncs, ApiNames);

    Lines.Add('<?php');
    Lines.Add('// ============================================================================');
    Lines.Add('//  ' + UnitName.Text + '_http_json_call_main_test___.php');
    Lines.Add('// ----------------------------------------------------------------------------');
    Lines.Add('//  Auto-generated by http_php_abi_test_generator_tool.pas.');
    Lines.Add('//  Source model unit: ' + UnitName.Text + '.');
    Lines.Add('//  Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('//  Call-side test program for the PHP HTTP/JSON call module.');
    Lines.Add('//  Pairs with ' + CallModuleName.Text + '.php.');
    Lines.Add('//');
    Lines.Add('//  How to run:');
    Lines.Add('//    php ' + FileName.Text);
    Lines.Add('//    php ' + FileName.Text + ' <base_url>');
    Lines.Add('//');
    Lines.Add('//  Defaults:');
    Lines.Add('//    <base_url> = ' + DefaultBaseUrl.Text);
    Lines.Add('// ============================================================================');
    Lines.Add('');
    Lines.Add('declare(strict_types=0);');
    Lines.Add('');
    Lines.Add('require_once __DIR__ . ' + PhpStrLit('/' + CallModuleName + '.php').Text + ';');
    Lines.Add('');
    Lines.Add('use ' + SafeNamespace.Text + '\HttpJsonCallApi;');
    Lines.Add('use ' + SafeNamespace.Text + '\HttpJsonCallConfig;');
    Lines.Add('use ' + SafeNamespace.Text + '\HttpJsonCallError;');
    Lines.Add('');
    Lines.Add('$DEFAULT_BASE_URL = ' + PhpStrLit(DefaultBaseUrl).Text + ';');
    Lines.Add('');

    Lines.Add('function runAll(): array');
    Lines.Add('{');
    Lines.Add('    $results = [];');
    Lines.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      Lines.Add('    // No supported routines were generated.');
    end
    else
    begin
      for i := 0 to High(SupportedFuncs) do
      begin
        F := SupportedFuncs[i];
        ApiName := ApiNames[i];
        DefaultArgs := BuildPhpDefaultArgList(F.Params);
        HasParams := Length(F.Params) > 0;

        Lines.Add('    // ---- ' + ApiName.Text + ' ----');
        Lines.Add('    try {');
        if F.IsFunction then
        begin
          if HasParams then
            Lines.Add('        $r = HttpJsonCallApi::' + ApiName.Text + '(' + DefaultArgs.Text + ');')
          else
            Lines.Add('        $r = HttpJsonCallApi::' + ApiName.Text + '();');
          Lines.Add('        unset($r);');
        end
        else
        begin
          if HasParams then
            Lines.Add('        HttpJsonCallApi::' + ApiName.Text + '(' + DefaultArgs.Text + ');')
          else
            Lines.Add('        HttpJsonCallApi::' + ApiName.Text + '();');
        end;
        Lines.Add('        $results[] = [' +
          PhpStrLit('name').Text + ' => ' + PhpStrLit(ApiName).Text +
          ', ' + PhpStrLit('ok').Text + ' => true, ' +
          PhpStrLit('message').Text + ' => ' + PhpStrLit('').Text + '];');
        Lines.Add('    } catch (\Throwable $e) {');
        Lines.Add('        $results[] = [' +
          PhpStrLit('name').Text + ' => ' + PhpStrLit(ApiName).Text +
          ', ' + PhpStrLit('ok').Text + ' => false, ' +
          PhpStrLit('message').Text + ' => $e->getMessage()];');
        Lines.Add('    }');
        Lines.Add('');
      end;
    end;

    Lines.Add('    return $results;');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('function main(): int');
    Lines.Add('{');
    Lines.Add('    global $argv, $DEFAULT_BASE_URL;');
    Lines.Add('    $baseUrl = (isset($argv[1]) && $argv[1] !== ' + PhpStrLit('').Text + ')');
    Lines.Add('        ? $argv[1] : $DEFAULT_BASE_URL;');
    Lines.Add('');
    Lines.Add('    echo ' + PhpStrLit('=== ' + UnitName + ' HTTP/JSON call test ===').Text + ' . "\n\n";');
    Lines.Add('    echo ' + PhpStrLit('Base URL: ').Text + ' . $baseUrl . "\n\n";');
    Lines.Add('');
    Lines.Add('    HttpJsonCallConfig::$baseUrl = $baseUrl;');
    Lines.Add('');
    Lines.Add('    $results = runAll();');
    Lines.Add('');
    Lines.Add('    $ok = 0;');
    Lines.Add('    $fail = 0;');
    Lines.Add('    foreach ($results as $r) {');
    Lines.Add('        if ($r[' + PhpStrLit('ok').Text + ']) {');
    Lines.Add('            echo ' + PhpStrLit('  ').Text + ' . $r[' + PhpStrLit('name').Text + '] . ' +
      PhpStrLit(': OK').Text + ' . "\n";');
    Lines.Add('            $ok++;');
    Lines.Add('        } else {');
    Lines.Add('            fwrite(STDERR, ' + PhpStrLit('  ').Text + ' . $r[' + PhpStrLit('name').Text + '] . ' +
      PhpStrLit(': FAILED: ').Text + ' . $r[' + PhpStrLit('message').Text + '] . "\n");');
    Lines.Add('            $fail++;');
    Lines.Add('        }');
    Lines.Add('    }');
    Lines.Add('');
    Lines.Add('    echo "\n=== Summary ===\n";');
    Lines.Add('    echo ' + PhpStrLit('Passed: ').Text + ' . $ok . "\n";');
    Lines.Add('    echo ' + PhpStrLit('Failed: ').Text + ' . $fail . "\n";');
    Lines.Add('');
    Lines.Add('    return $fail === 0 ? 0 : 1;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('exit(main());');
    Lines.Add('');

    Result := Lines;
    Log('Generated PHP call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]);
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'php', 'PHP HTTP/JSON call test program',
    asCall, akTestCode,
    '_http_json_call_main_test___.php', False,
    @GenerateHTTPCallPhpTestCode);
end.
