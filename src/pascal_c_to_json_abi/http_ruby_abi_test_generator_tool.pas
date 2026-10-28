unit http_ruby_abi_test_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceRubyTestCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateHTTPCallRubyTestCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ruby_abi_test_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ruby_abi_test_generator] %s', [PFormat(Fmt, Args)]);
end;

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

function ABI_Type_To_Ruby_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := #39 + #39
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'nil';
end;

function ABI_Type_To_Json_Default_Literal(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := '""'
  else if ABI_Type_Is_Float(T) then
    Result := '0.0'
  else if ABI_Type_Is_Int(T) then
    Result := '0'
  else
    Result := 'null';
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

function ABI_Type_To_Ruby_Doc_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'Float'
  else if ABI_Type_Is_Int(T) then
    Result := 'Integer'
  else
    Result := 'Object';
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

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsRubyReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('BEGIN') or S.Same('END') or
    S.Same('alias') or S.Same('and') or S.Same('begin') or S.Same('break') or
    S.Same('case') or S.Same('class') or S.Same('def') or
    S.Same('do') or S.Same('else') or S.Same('elsif') or S.Same('end') or
    S.Same('ensure') or S.Same('false') or S.Same('for') or S.Same('if') or
    S.Same('in') or S.Same('module') or S.Same('next') or S.Same('nil') or
    S.Same('not') or S.Same('or') or S.Same('redo') or S.Same('rescue') or
    S.Same('retry') or S.Same('return') or S.Same('self') or S.Same('super') or
    S.Same('then') or S.Same('true') or S.Same('undef') or S.Same('unless') or
    S.Same('until') or S.Same('when') or S.Same('while') or S.Same('yield');
end;

function MakeSafeRubyIdent(const Name: TP_String; Index: integer): TP_String;
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
  if IsRubyReservedWord(Result) then
    Result := Result + '_';
end;

function MakeSafeRubyParamIdent(const Name: TP_String; Index: integer): TP_String;
begin
  Result := MakeSafeRubyIdent(Name, Index);
  if Result.Len = 0 then
    Exit;
  if (Result[1] >= 'A') and (Result[1] <= 'Z') then
    Result[1] := TP_Char(Ord(Result[1]) + 32);
  if IsRubyReservedWord(Result) then
    Result := Result + '_';
end;

function MakeRubyModuleName(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
  upperNext: boolean;
begin
  Result := '';
  upperNext := True;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if (c = '_') or (c = ' ') or (c = '.') or (c = '/') or (c = '-') then
      upperNext := True
    else if upperNext then
    begin
      if (c >= 'a') and (c <= 'z') then
        c := TP_Char(Ord(c) - 32)
      else if not (((c >= 'A') and (c <= 'Z')) or ((c >= '0') and (c <= '9'))) then
        c := '_';
      Result.Append(c);
      upperNext := False;
    end
    else
    begin
      if ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
        ((c >= '0') and (c <= '9')) then
        Result.Append(c)
      else
        Result.Append('_');
    end;
  end;
  if Result.Len = 0 then
    Result := 'Generated'
  else if (Result[1] >= '0') and (Result[1] <= '9') then
    Result := 'U' + Result;
end;

function RubyStrLit(const S: TP_String): TP_String;
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
      '"':  Result.Append('\' + '"');
      '\':  Result.Append('\\');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
      #8:   Result.Append('\b');
      #12:  Result.Append('\f');
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
      Result.Append('\' + '|')
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

// BuildPascalDecl - reconstruct the Pascal declaration of a function.
// Used only by the README generator (§6.1 per-API details).
function BuildPascalDecl(const F: TFunctionStructure): TP_String;
var
  i: integer;
  ParamDecl, n, decl: TP_String;
begin
  ParamDecl := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeRubyParamIdent(F.Params[i].Name, i);
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

function BuildRubyParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeRubyParamIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
end;

function BuildRubyDefaultArgList(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Ruby_Default_Literal(Params[i].PascalType);
  end;
end;

function BuildJsonArgsBody(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Json_Default_Literal(Params[i].PascalType);
  end;
end;

function BuildSmokeJsonRequest(const Params: TParamArray): TP_String;
begin
  if Length(Params) = 0 then
    Result := '{}'
  else
    Result := '{"args": [' + BuildJsonArgsBody(Params) + ']}';
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
// SERVICE-SIDE TEST PROGRAM GENERATOR
// =============================================================================

function GenerateHTTPServiceRubyTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, ServiceModuleFile, TestFileName: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, SmokeBody: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceRubyTestCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceRubyTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := MakeRubyModuleName(NormalizedUnit) + 'HttpJsonService';
  ServiceModuleFile := NormalizedUnit + '_http_json_service';
  TestFileName := NormalizedUnit + '_http_json_service_main_test___.rb';

  Log(PFormat('Generating Ruby service test program for unit "%s"', [UnitName.Text]));
  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('# -*- coding: utf-8 -*-');
    Lines.Add('# Auto-generated by http_ruby_abi_test_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Service-side test program for the Ruby HTTP/JSON service.');
    Lines.Add('# Pairs with ' + ServiceModuleFile.Text + '.rb.');
    Lines.Add('#');
    Lines.Add('# Modes:');
    Lines.Add('#   (default)  Start the service and block until Ctrl+C / SIGINT.');
    Lines.Add('#   --smoke    In-process LocalCall self-tests.');
    Lines.Add('#              No LingoFuse mesh, no bridge.py, no network.');
    Lines.Add('');
    Lines.Add('require ' + #39 + 'json' + #39);
    Lines.Add('require_relative ' + #39 + ServiceModuleFile.Text + #39);
    Lines.Add('');
    Lines.Add('SMOKE_CASES = [');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      SmokeBody := BuildSmokeJsonRequest(F.Params);
      Lines.Add('  [' + RubyStrLit(ApiName).Text + ', ' +
        RubyStrLit(SmokeBody).Text + '],');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('  # (no supported routines)');

    Lines.Add(']');
    Lines.Add('');
    Lines.Add('def run_smoke');
    Lines.Add('  puts ' + #39 + '[smoke] running in-process LocalCall self-tests' + #39);
    Lines.Add('  puts ' + #39 + '[smoke] this mode does NOT start LingoFuse and does NOT need the bridge' + #39);
    Lines.Add('  puts');
    Lines.Add('');
    Lines.Add('  app = ' + ModuleName.Text + '.create_and_register_http_json_app');
    Lines.Add('  unless app');
    Lines.Add('    warn ' + #39 + '[smoke] create_and_register_http_json_app returned nil' + #39);
    Lines.Add('    return 1');
    Lines.Add('  end');
    Lines.Add('');
    Lines.Add('  ok = 0');
    Lines.Add('  fail = 0');
    Lines.Add('');
    Lines.Add('  begin');
    Lines.Add('    SMOKE_CASES.each do |api_name, request_json|');
    Lines.Add('      begin');
    Lines.Add('        req = LingoFuse::DataHandle.new(api_name)');
    Lines.Add('        LingoFuse::LfIo.write_string(req, request_json)');
    Lines.Add('');
    Lines.Add('        resp = app.local_call(req)');
    Lines.Add('        resp_text = LingoFuse::LfIo.read_string(resp)');
    Lines.Add('');
    Lines.Add('        parsed = begin');
    Lines.Add('          JSON.parse(resp_text)');
    Lines.Add('        rescue JSON::ParserError');
    Lines.Add('          nil');
    Lines.Add('        end');
    Lines.Add('');
    Lines.Add('        if parsed.is_a?(Hash) && parsed[' + #39 + 'code' + #39 + '] == 0');
    Lines.Add('          puts "  #{api_name}: OK"');
    Lines.Add('          ok += 1');
    Lines.Add('        else');
    Lines.Add('          warn "  #{api_name}: non-zero code: #{resp_text}"');
    Lines.Add('          fail += 1');
    Lines.Add('        end');
    Lines.Add('      rescue StandardError => e');
    Lines.Add('        warn "  #{api_name}: FAILED: #{e.class}: #{e.message}"');
    Lines.Add('        fail += 1');
    Lines.Add('      ensure');
    Lines.Add('        req.dispose if defined?(req) && req');
    Lines.Add('        resp.dispose if defined?(resp) && resp');
    Lines.Add('      end');
    Lines.Add('    end');
    Lines.Add('  ensure');
    Lines.Add('    app.dispose');
    Lines.Add('  end');
    Lines.Add('');
    Lines.Add('  puts');
    Lines.Add('  puts ' + #39 + '=== Smoke test summary ===' + #39);
    Lines.Add('  puts "Passed: #{ok}"');
    Lines.Add('  puts "Failed: #{fail}"');
    Lines.Add('  fail == 0 ? 0 : 1');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('# Force exit. The LingoFuse NativeBridge dispatcher thread loops');
    Lines.Add('# forever inside NativeBridge.start and never joins; Ruby''s');
    Lines.Add('# normal exit would wait for it indefinitely.');
    Lines.Add('if ARGV.include?(' + #39 + '--smoke' + #39 + ') || ARGV.include?(' + #39 + '-smoke' + #39 + ')');
    Lines.Add('  rc = run_smoke');
    Lines.Add('  $stdout.flush');
    Lines.Add('  $stderr.flush');
    Lines.Add('  exit!(rc)');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('rc = ' + ModuleName.Text + '.main');
    Lines.Add('$stdout.flush');
    Lines.Add('$stderr.flush');
    Lines.Add('exit!(rc)');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated service test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

// =============================================================================
// CALL-SIDE TEST PROGRAM GENERATOR
// =============================================================================

function GenerateHTTPCallRubyTestCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, CallModuleFile, TestFileName, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
  F: TFunctionStructure;
  ApiName, DefaultArgs, ApiMethodName: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallRubyTestCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallRubyTestCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := MakeRubyModuleName(NormalizedUnit) + 'HttpJsonCall';
  CallModuleFile := NormalizedUnit + '_http_json_call';
  TestFileName := NormalizedUnit + '_http_json_call_main_test___.rb';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating Ruby call test program for unit "%s"', [UnitName.Text]));
  SupportedFuncs := CollectSupportedFunctions(Model);

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    Lines.Add('# -*- coding: utf-8 -*-');
    Lines.Add('# Auto-generated by http_ruby_abi_test_generator_tool.pas.');
    Lines.Add('# Source model unit: ' + UnitName.Text + '.');
    Lines.Add('# Do not edit by hand unless you know what you are doing.');
    Lines.Add('#');
    Lines.Add('# Call-side end-to-end test for the Ruby HTTP/JSON call module.');
    Lines.Add('# Pairs with ' + CallModuleFile.Text + '.rb.');
    Lines.Add('#');
    Lines.Add('# Requires bridge.py and the matching service to be running.');
    Lines.Add('');
    Lines.Add('require_relative ' + #39 + CallModuleFile.Text + #39);
    Lines.Add('');
    Lines.Add('DEFAULT_BASE_URL = ' + RubyStrLit(BaseUrl).Text);
    Lines.Add('');
    Lines.Add('TESTS = [');

    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := ApiNames[i];
      ApiMethodName := MakeSafeRubyIdent(ApiName, i);
      DefaultArgs := BuildRubyDefaultArgList(F.Params);

      Lines.Add('  [' + RubyStrLit(ApiName).Text + ',');
      if Length(F.Params) > 0 then
        Lines.Add('   ->(api) { api.' + ApiMethodName.Text + '(' + DefaultArgs.Text + ') }],')
      else
        Lines.Add('   ->(api) { api.' + ApiMethodName.Text + ' }],');
    end;

    if Length(SupportedFuncs) = 0 then
      Lines.Add('  # (no supported routines)');

    Lines.Add(']');
    Lines.Add('');
    Lines.Add('def main');
    Lines.Add('  base_url = ARGV.length >= 1 ? ARGV[0] : DEFAULT_BASE_URL');
    // Use the lowercase setter. `Module::HTTP_CALL_BASE_URL = ...`
    // would be parsed by Ruby as a constant assignment and raise
    // "dynamic constant assignment" inside a method.
    Lines.Add('  ' + ModuleName.Text + '.base_url = base_url');
    Lines.Add('');
    Lines.Add('  puts ' + #39 + '=== ' + UnitName.Text + ' HTTP/JSON call test ===' + #39);
    Lines.Add('  puts');
    Lines.Add('  puts "Base URL: #{base_url}"');
    Lines.Add('  puts');
    Lines.Add('');
    Lines.Add('  sleep(1)');
    Lines.Add('');
    Lines.Add('  ok = 0');
    Lines.Add('  fail = 0');
    Lines.Add('');
    Lines.Add('  TESTS.each do |api_name, fn|');
    Lines.Add('    begin');
    Lines.Add('      fn.call(' + ModuleName.Text + ')');
    Lines.Add('      puts "  #{api_name} [sync] : OK"');
    Lines.Add('      ok += 1');
    Lines.Add('    rescue StandardError => e');
    Lines.Add('      warn "  #{api_name} [sync] : FAILED: #{e.class}: #{e.message}"');
    Lines.Add('      fail += 1');
    Lines.Add('    end');
    Lines.Add('  end');
    Lines.Add('');
    Lines.Add('  puts');
    Lines.Add('  puts ' + #39 + '=== Summary ===' + #39);
    Lines.Add('  puts "Passed: #{ok}"');
    Lines.Add('  puts "Failed: #{fail}"');
    Lines.Add('  fail == 0 ? 0 : 1');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('rc = main');
    Lines.Add('$stdout.flush');
    Lines.Add('$stderr.flush');
    Lines.Add('exit!(rc)');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated call test program: %d lines, %d routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'ruby', 'Ruby HTTP/JSON service test program',
    asBoth, akTestCode,
    '_http_json_service_main_test___.rb', False,
    @GenerateHTTPServiceRubyTestCode);
  RegisterCodeGenEntry(
    'ruby', 'Ruby HTTP/JSON call test program',
    asBoth, akTestCode,
    '_http_json_call_main_test___.rb', False,
    @GenerateHTTPCallRubyTestCode);
end.
