unit http_dart_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallDartCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_dart_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_dart_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Dart_Type(const T: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := 'String'
  else if ABI_Type_Is_Float(T) then
    Result := 'double'
  else if ABI_Type_Is_Int(T) then
    Result := 'int'
  else
    Result := 'void';
end;

function ABI_Type_To_Dart_Extract(const T: TP_String; const Expr: TP_String): TP_String;
begin
  if ABI_Type_Is_String(T) then
    Result := Expr + ' as String'
  else if ABI_Type_Is_Float(T) then
    Result := '(' + Expr + ' as num).toDouble()'
  else if ABI_Type_Is_Int(T) then
    Result := '(' + Expr + ' as num).toInt()'
  else
    Result := Expr;
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@:#?&=+-', '_');
end;

function IsDartReservedWord(const S: TP_String): boolean;
begin
  Result :=
    S.Same('abstract') or S.Same('as') or S.Same('assert') or
    S.Same('async') or S.Same('await') or S.Same('break') or
    S.Same('case') or S.Same('catch') or S.Same('class') or
    S.Same('const') or S.Same('continue') or S.Same('covariant') or
    S.Same('default') or S.Same('deferred') or S.Same('do') or
    S.Same('dynamic') or S.Same('else') or S.Same('enum') or
    S.Same('export') or S.Same('extends') or S.Same('extension') or
    S.Same('external') or S.Same('factory') or S.Same('false') or
    S.Same('final') or S.Same('finally') or S.Same('for') or
    S.Same('Function') or S.Same('get') or S.Same('hide') or
    S.Same('if') or S.Same('implements') or S.Same('import') or
    S.Same('in') or S.Same('interface') or S.Same('is') or
    S.Same('late') or S.Same('library') or S.Same('mixin') or
    S.Same('new') or S.Same('null') or S.Same('on') or
    S.Same('operator') or S.Same('part') or S.Same('required') or
    S.Same('rethrow') or S.Same('return') or S.Same('set') or
    S.Same('show') or S.Same('static') or S.Same('super') or
    S.Same('switch') or S.Same('sync') or S.Same('this') or
    S.Same('throw') or S.Same('true') or S.Same('try') or
    S.Same('typedef') or S.Same('var') or S.Same('void') or
    S.Same('while') or S.Same('with') or S.Same('yield');
end;

function MakeSafeDartIdent(const Name: TP_String; Index: integer): TP_String;
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

  if IsDartReservedWord(Result) then
    Result := Result + '_';
end;

function DartStrLit(const S: TP_String): TP_String;
const
  HEXDIG = '0123456789abcdef';
var
  i, code: integer;
  c: TP_Char;
begin
  Result := #39;
  for i := 1 to S.Len do
  begin
    c := S[i];
    code := Ord(c);
    case c of
      #39:  Result.Append('\' + #39);
      #92:  Result.Append('\\');
      #36:  Result.Append('\$');
      #10:  Result.Append('\n');
      #13:  Result.Append('\r');
      #9:   Result.Append('\t');
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
  Result.Append(#39);
end;

function GetFullDescription(const Comment: TP_String): TP_String;
var
  i, j: integer;
  Line, T: TP_String;
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

      if T.Len > 0 then
      begin
        if T[1] = '@' then
        begin
        end
        else
        begin
          if T[1] = '*' then
            T := T.GetString(2, T.Len + 1).TrimChar(#32#9);
          if (T.Len > 0) and (T[1] = '*') then
            T := T.GetString(2, T.Len + 1).TrimChar(#32#9);

          if T.Len > 0 then
          begin
            Result := T;
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

function BuildDartParamDeclList(const Params: TParamArray): TP_String;
var
  i: integer;
  n, T: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeDartIdent(Params[i].Name, i);
    T := ABI_Type_To_Dart_Type(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + T + ' ' + n;
  end;
end;

function BuildDartArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    n := MakeSafeDartIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
  end;
  Result := Result + ']';
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

procedure EmitDartHeader(Lines: TPascalStringList;
  const BaseUrl: TP_String);
begin
  Lines.Add('import ' + #39 + 'dart:async' + #39 + ';');
  Lines.Add('import ' + #39 + 'dart:convert' + #39 + ';');
  Lines.Add('');
  Lines.Add('import ' + #39 + 'package:http/http.dart' + #39 + ' as http;');
  Lines.Add('');
  Lines.Add('const String DEFAULT_BASE_URL = ' + DartStrLit(BaseUrl).Text + ';');
  Lines.Add('');
  Lines.Add('Duration HTTP_CALL_TIMEOUT = const Duration(seconds: 30);');
  Lines.Add('');
  Lines.Add('bool DEBUG_LOG = false;');
  Lines.Add('');
  Lines.Add('String? _baseUrlOverride;');
  Lines.Add('');
  Lines.Add('void setBaseUrl(String url) {');
  Lines.Add('  _baseUrlOverride = url;');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('String getBaseUrl() => _baseUrlOverride ?? DEFAULT_BASE_URL;');
  Lines.Add('');
  Lines.Add('class HttpCallError implements Exception {');
  Lines.Add('  final String message;');
  Lines.Add('  final int code;');
  Lines.Add('  final int httpStatus;');
  Lines.Add('');
  Lines.Add('  HttpCallError(this.message, {this.code = -1, this.httpStatus = 0});');
  Lines.Add('');
  Lines.Add('  @override');
  Lines.Add('  String toString() =>');
  Lines.Add('      ' + #39 + 'HttpCallError[code=$code, http=$httpStatus]: $message' + #39 + ';');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Future<dynamic> _callApi(String apiName, List<dynamic> args) async {');
  Lines.Add('  final base = getBaseUrl();');
  Lines.Add('  final trimmedBase = base.endsWith(' + #39 + '/' + #39 + ')');
  Lines.Add('      ? base.substring(0, base.length - 1)');
  Lines.Add('      : base;');
  Lines.Add('  final url = ' + #39 + '$trimmedBase/$apiName' + #39 + ';');
  Lines.Add('  final body = jsonEncode(<String, dynamic>{' + #39 + 'args' + #39 + ': args});');
  Lines.Add('');
  Lines.Add('  if (DEBUG_LOG) {');
  Lines.Add('    print(' + #39 + '[http-json] POST $url body=$body' + #39 + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  http.Response response;');
  Lines.Add('  try {');
  Lines.Add('    response = await http.post(');
  Lines.Add('      Uri.parse(url),');
  Lines.Add('      headers: const <String, String>{');
  Lines.Add('        ' + #39 + 'Content-Type' + #39 + ': ' + #39 + 'application/json; charset=utf-8' + #39 + ',');
  Lines.Add('      },');
  Lines.Add('      body: utf8.encode(body),');
  Lines.Add('    ).timeout(HTTP_CALL_TIMEOUT);');
  Lines.Add('  } on TimeoutException catch (e) {');
  Lines.Add('    throw HttpCallError(' + #39 + 'Request timed out: $e' + #39 + ', code: -1);');
  Lines.Add('  } on http.ClientException catch (e) {');
  Lines.Add('    throw HttpCallError(' + #39 + 'Network error: $e' + #39 + ', code: -1);');
  Lines.Add('  } catch (e) {');
  Lines.Add('    throw HttpCallError(' + #39 + 'Transport error: $e' + #39 + ', code: -1);');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (DEBUG_LOG) {');
  Lines.Add('    final bodyText =');
  Lines.Add('        utf8.decode(response.bodyBytes, allowMalformed: true);');
  Lines.Add('    print(' + #39 + '[http-json] response ${response.statusCode}: $bodyText' + #39 + ');');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  if (response.statusCode != 200) {');
  Lines.Add('    final text =');
  Lines.Add('        utf8.decode(response.bodyBytes, allowMalformed: true);');
  Lines.Add('    throw HttpCallError(');
  Lines.Add('      ' + #39 + 'HTTP ${response.statusCode}: $text' + #39 + ',');
  Lines.Add('      code: -1,');
  Lines.Add('      httpStatus: response.statusCode,');
  Lines.Add('    );');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  final text = utf8.decode(response.bodyBytes, allowMalformed: true);');
  Lines.Add('  if (text.isEmpty) {');
  Lines.Add('    throw HttpCallError(' + #39 + 'Empty response from bridge' + #39 + ',');
  Lines.Add('        code: -1, httpStatus: 200);');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  Map<String, dynamic> parsed;');
  Lines.Add('  try {');
  Lines.Add('    parsed = jsonDecode(text) as Map<String, dynamic>;');
  Lines.Add('  } on FormatException catch (e) {');
  Lines.Add('    throw HttpCallError(' + #39 + 'Invalid JSON response: $e' + #39 + ',');
  Lines.Add('        code: -1, httpStatus: 200);');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  final code = (parsed[' + #39 + 'code' + #39 + '] as num?)?.toInt();');
  Lines.Add('  if (code == null) {');
  Lines.Add('    final err = parsed[' + #39 + 'error' + #39 + '];');
  Lines.Add('    if (err is String) {');
  Lines.Add('      throw HttpCallError(err, code: -1, httpStatus: 200);');
  Lines.Add('    }');
  Lines.Add('    throw HttpCallError(' + #39 + 'Response has no "code" field' + #39 + ',');
  Lines.Add('        code: -1, httpStatus: 200);');
  Lines.Add('  }');
  Lines.Add('  if (code != 0) {');
  Lines.Add('    final err = parsed[' + #39 + 'error' + #39 + '] as String?;');
  Lines.Add('    throw HttpCallError(err ?? ' + #39 + 'Remote call failed' + #39 + ',');
  Lines.Add('        code: code, httpStatus: 200);');
  Lines.Add('  }');
  Lines.Add('');
  Lines.Add('  return parsed[' + #39 + 'result' + #39 + '];');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitDartFunction(Lines: TPascalStringList;
  const F: TFunctionStructure; const ApiName: TP_String);
var
  ParamDecl, ArgList, ReturnType: TP_String;
  HasParams: boolean;
begin
  ParamDecl := BuildDartParamDeclList(F.Params);
  ArgList := BuildDartArgList(F.Params);
  HasParams := Length(F.Params) > 0;

  if F.IsFunction then
    ReturnType := 'Future<' + ABI_Type_To_Dart_Type(F.ReturnType) + '>'
  else
    ReturnType := 'Future<void>';

  if HasParams then
    Lines.Add(ReturnType.Text + ' ' + ApiName.Text + '(' + ParamDecl.Text + ') async {')
  else
    Lines.Add(ReturnType.Text + ' ' + ApiName.Text + '() async {');

  if F.IsFunction then
  begin
    Lines.Add('  final result = await _callApi(' + DartStrLit(ApiName).Text +
      ', ' + ArgList.Text + ');');
    Lines.Add('  return ' + ABI_Type_To_Dart_Extract(F.ReturnType, 'result') + ';');
  end
  else
  begin
    Lines.Add('  await _callApi(' + DartStrLit(ApiName).Text + ', ' + ArgList.Text + ');');
  end;
  Lines.Add('}');
  Lines.Add('');
end;

function GenerateHTTPCallDartCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
  i: integer;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallDartCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallDartCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Dart call module for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);

    EmitDartHeader(Lines, BaseUrl);

    for i := 0 to High(SupportedFuncs) do
      EmitDartFunction(Lines, SupportedFuncs[i], ApiNames[i]);

    Result := Lines;
    Log(PFormat('Generated %d lines, %d supported routines.',
      [Lines.Count, Length(SupportedFuncs)]));
  finally
    ApiNames.Free;
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'dart', 'Dart HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call.dart', False,
    @GenerateHTTPCallDartCode);
end.
