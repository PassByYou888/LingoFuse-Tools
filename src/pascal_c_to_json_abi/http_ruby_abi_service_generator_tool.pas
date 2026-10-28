unit http_ruby_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPServiceRubyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ruby_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ruby_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_Needs_Precision_Note(const T: TP_String): boolean;
begin
  Result := T.Same('int64') or T.Same('uint64');
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

// MakeSafeRubyParamIdent - parameter names must start lowercase
// (otherwise Ruby rejects them as constants).
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

function BuildRubyNameArrayLiteral(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + RubyStrLit(Params[i].Name);
  end;
  Result := Result + ']';
end;

function BuildRubyDefaultArgArrayLiteral(const Params: TParamArray): TP_String;
var
  i: integer;
begin
  Result := '[';
  for i := 0 to High(Params) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ABI_Type_To_Ruby_Default_Literal(Params[i].PascalType);
  end;
  Result := Result + ']';
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

function BuildRubyStubSignature(const F: TFunctionStructure;
  const StubName: TP_String): TP_String;
begin
  Result := 'def self.' + StubName + '(' + BuildRubyParamList(F.Params) + ')';
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

procedure EmitRubyServiceHeader(Lines: TPascalStringList;
  const UnitName: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('# Auto-generated by http_ruby_abi_service_generator_tool.pas.');
  Lines.Add('# Source model unit: ' + UnitName.Text + '.');
  Lines.Add('# Do not edit by hand unless you know what you are doing.');
  Lines.Add('#');
  Lines.Add('# HTTP/JSON ABI service module for Ruby, backed by the LingoFuse');
  Lines.Add('# mesh. It registers one JSON-RPC API per supported routine.');
  Lines.Add('#');
  Lines.Add('# This module requires:');
  Lines.Add('#   * the `lingofuse` Ruby gem (compiled C extension)');
  Lines.Add('#   * the native LingoFuse shared library on the loader path');
  Lines.Add('#   * a running bridge.py process on the SAME endpoint');
  Lines.Add('');
  Lines.Add('require ' + #39 + 'lingofuse' + #39);
  Lines.Add('require ' + #39 + 'json' + #39);
  Lines.Add('');
end;

procedure EmitRubyServiceConfig(Lines: TPascalStringList;
  const ModuleName, AppName, AppDesc, Endpoint: TP_String);
begin
  Lines.Add('module ' + ModuleName.Text);
  Lines.Add('');
  Lines.Add('  APP_NAME = ' + RubyStrLit(AppName).Text);
  Lines.Add('  APP_DESC = ' + RubyStrLit(AppDesc).Text);
  Lines.Add('  ENDPOINT = ' + RubyStrLit(Endpoint).Text);
  Lines.Add('');
  Lines.Add('  DEBUG_LOG = ENV[' + #39 + 'LINGOFUSE_DEBUG' + #39 + '] == ' + #39 + '1' + #39 + ' ||');
  Lines.Add('              ENV[' + #39 + 'LINGOFUSE_DEBUG' + #39 + '] == ' + #39 + 'true' + #39);
  Lines.Add('');
end;

procedure EmitRubyServiceHelpers(Lines: TPascalStringList);
begin
  Lines.Add('  def self._extract_args(body, param_names, defaults)');
  Lines.Add('    unless body.is_a?(Hash)');
  Lines.Add('      raise ArgumentError, ' + #39 + 'Request must be a JSON object' + #39);
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    if body.key?(' + #39 + 'args' + #39 + ')');
  Lines.Add('      arr = body[' + #39 + 'args' + #39 + ']');
  Lines.Add('      unless arr.is_a?(Array)');
  Lines.Add('        raise ArgumentError, ' + #39 + '"args" must be a JSON array' + #39);
  Lines.Add('      end');
  Lines.Add('      result = []');
  Lines.Add('      param_names.each_index do |i|');
  Lines.Add('        if i < arr.length && !arr[i].nil?');
  Lines.Add('          result << arr[i]');
  Lines.Add('        else');
  Lines.Add('          result << defaults[i]');
  Lines.Add('        end');
  Lines.Add('      end');
  Lines.Add('      return result');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    result = []');
  Lines.Add('    param_names.each_with_index do |name, i|');
  Lines.Add('      if body.key?(name) && !body[name].nil?');
  Lines.Add('        result << body[name]');
  Lines.Add('      else');
  Lines.Add('        result << defaults[i]');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('    result');
  Lines.Add('  end');
  Lines.Add('');
  Lines.Add('  def self._read_request(input)');
  Lines.Add('    body = LingoFuse::LfIo.read_json(input)');
  Lines.Add('    return {} if body.nil?');
  Lines.Add('    unless body.is_a?(Hash)');
  Lines.Add('      raise ArgumentError, ' + #39 + 'Request must be a JSON object' + #39);
  Lines.Add('    end');
  Lines.Add('    body');
  Lines.Add('  end');
  Lines.Add('');
  Lines.Add('  def self._write_error(output, message)');
  Lines.Add('    begin');
  Lines.Add('      LingoFuse::LfIo.write_json(output, {');
  Lines.Add('        ' + #39 + 'code' + #39 + ' => -1,');
  Lines.Add('        ' + #39 + 'error' + #39 + ' => message.to_s');
  Lines.Add('      })');
  Lines.Add('    rescue StandardError');
  Lines.Add('    end');
  Lines.Add('  end');
  Lines.Add('');
  Lines.Add('  def self._make_call_adapter(fn, api_name, param_names, defaults)');
  Lines.Add('    lambda do |input, output|');
  Lines.Add('      begin');
  Lines.Add('        body = _read_request(input)');
  Lines.Add('        if DEBUG_LOG');
  Lines.Add('          warn "[service] ' + #39 + ' + api_name + ' + #39 + ': request=#{body.inspect}"');
  Lines.Add('        end');
  Lines.Add('        args = _extract_args(body, param_names, defaults)');
  Lines.Add('        result = fn.call(*args)');
  Lines.Add('        if DEBUG_LOG');
  Lines.Add('          warn "[service] ' + #39 + ' + api_name + ' + #39 + ': result=#{result.inspect}"');
  Lines.Add('        end');
  Lines.Add('        LingoFuse::LfIo.write_json(output, {');
  Lines.Add('          ' + #39 + 'code' + #39 + ' => 0,');
  Lines.Add('          ' + #39 + 'result' + #39 + ' => result');
  Lines.Add('        })');
  Lines.Add('      rescue StandardError => e');
  Lines.Add('        warn "[service] ' + #39 + ' + api_name + ' + #39 + ': exception #{e.class}: #{e.message}"');
  Lines.Add('        _write_error(output, e.message)');
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('  end');
  Lines.Add('');
end;

procedure EmitRubyServiceStubs(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, StubName, Description, DefaultRet: TP_String;
begin
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('  # User-editable API stubs');
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := 'internal_call_' + MakeSafeRubyIdent(ApiName, i);

    Description := GetFullDescription(F.Comment);
    if Description.Len > 0 then
      Lines.Add('  # ' + Description.Text);
    Lines.Add('  #');
    Lines.Add('  # Original Pascal: ' + BuildPascalDecl(F).Text);

    Lines.Add('  ' + BuildRubyStubSignature(F, StubName).Text);

    for j := 0 to High(F.Params) do
      Lines.Add('    # ' + MakeSafeRubyParamIdent(F.Params[j].Name, j) + ' : ' +
        ABI_Type_To_Ruby_Doc_Type(F.Params[j].PascalType));

    Lines.Add('    # TODO: replace this body with the real implementation.');

    if F.IsFunction then
    begin
      DefaultRet := ABI_Type_To_Ruby_Default_Literal(F.ReturnType);
      Lines.Add('    ' + DefaultRet.Text);
    end
    else
      Lines.Add('    nil');
    Lines.Add('  end');
    Lines.Add('');
  end;
end;

procedure EmitRubyServiceRegistration(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, StubName, Description, NameArr, DefaultArr: TP_String;
begin
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('  # Registration');
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('  def self.register_all_apis(app)');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    StubName := 'internal_call_' + MakeSafeRubyIdent(ApiName, i);

    Description := GetFullDescription(F.Comment);
    if Description.Len = 0 then
      Description := 'HTTP/JSON API: ' + ApiName;

    NameArr := BuildRubyNameArrayLiteral(F.Params);
    DefaultArr := BuildRubyDefaultArgArrayLiteral(F.Params);

    Lines.Add('    app.register_call(');
    Lines.Add('      ' + RubyStrLit(ApiName).Text + ',');
    Lines.Add('      ' + RubyStrLit(Description).Text + ',');
    Lines.Add('      &_make_call_adapter(');
    Lines.Add('        method(:' + StubName.Text + '),');
    Lines.Add('        ' + RubyStrLit(ApiName).Text + ',');
    Lines.Add('        ' + NameArr.Text + ',');
    Lines.Add('        ' + DefaultArr.Text);
    Lines.Add('      )');
    Lines.Add('    )');
  end;

  if Length(SupportedFuncs) = 0 then
    Lines.Add('    # No supported routines were generated.');

  Lines.Add('  end');
  Lines.Add('');
  Lines.Add('  def self.create_and_register_http_json_app');
  Lines.Add('    app = LingoFuse::AppHandle.new(APP_NAME, APP_DESC)');
  Lines.Add('    register_all_apis(app)');
  Lines.Add('    app');
  Lines.Add('  end');
  Lines.Add('');
end;

procedure EmitRubyServiceMain(Lines: TPascalStringList);
begin
  Lines.Add('  def self.main');
  Lines.Add('    $stdout.puts "=== #{APP_NAME} HTTP/JSON service ==="');
  Lines.Add('    $stdout.puts "Endpoint: #{ENDPOINT}"');
  Lines.Add('    $stdout.flush');
  Lines.Add('');
  Lines.Add('    begin');
  Lines.Add('      LingoFuse.set_opt_wait_connection_ready_ok(false)');
  Lines.Add('      LingoFuse.set_opt_overlap_connection(true)');
  Lines.Add('    rescue StandardError');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    LingoFuse::Framework.reset_prepare');
  Lines.Add('');
  Lines.Add('    begin');
  Lines.Add('      LingoFuse::Framework.prepare_service(ENDPOINT, ENDPOINT)');
  Lines.Add('    rescue StandardError => e');
  Lines.Add('      warn "[FATAL] prepare_service failed for endpoint #{ENDPOINT}: #{e.message}"');
  Lines.Add('      LingoFuse::Framework.shutdown rescue nil');
  Lines.Add('      return 1');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    app = begin');
  Lines.Add('      create_and_register_http_json_app');
  Lines.Add('    rescue StandardError => e');
  Lines.Add('      warn "[FATAL] create_and_register failed: #{e.message}"');
  Lines.Add('      LingoFuse::Framework.shutdown rescue nil');
  Lines.Add('      return 1');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    if app.nil?');
  Lines.Add('      warn "[FATAL] failed to create the App."');
  Lines.Add('      LingoFuse::Framework.shutdown rescue nil');
  Lines.Add('      return 1');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    begin');
  Lines.Add('      LingoFuse::Framework.prepare_client(ENDPOINT, app)');
  Lines.Add('    rescue StandardError => e');
  Lines.Add('      warn "[FATAL] prepare_client failed: #{e.message}"');
  Lines.Add('      app.dispose rescue nil');
  Lines.Add('      LingoFuse::Framework.shutdown rescue nil');
  Lines.Add('      return 1');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    unless LingoFuse::Framework.prepare_done');
  Lines.Add('      warn "[FATAL] prepare_done failed."');
  Lines.Add('      app.dispose rescue nil');
  Lines.Add('      LingoFuse::Framework.shutdown rescue nil');
  Lines.Add('      return 1');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    $stdout.puts ' + #39 + '[OK] Service ready. Press Ctrl+C to stop.' + #39);
  Lines.Add('    $stdout.flush');
  Lines.Add('');
  Lines.Add('    stop = false');
  Lines.Add('    prev_int = trap(' + #39 + 'INT' + #39 + ') { stop = true }');
  Lines.Add('    prev_term = nil');
  Lines.Add('    begin');
  Lines.Add('      prev_term = trap(' + #39 + 'TERM' + #39 + ') { stop = true }');
  Lines.Add('    rescue ArgumentError');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    begin');
  Lines.Add('      until stop');
  Lines.Add('        sleep(0.5)');
  Lines.Add('      end');
  Lines.Add('    rescue Interrupt');
  Lines.Add('      stop = true');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    trap(' + #39 + 'INT' + #39 + ', prev_int || ' + #39 + 'DEFAULT' + #39 + ')');
  Lines.Add('    begin');
  Lines.Add('      trap(' + #39 + 'TERM' + #39 + ', prev_term || ' + #39 + 'DEFAULT' + #39 + ')');
  Lines.Add('    rescue ArgumentError');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    LingoFuse::Framework.exit_main_thread rescue nil');
  Lines.Add('    app.dispose rescue nil');
  Lines.Add('    LingoFuse::Framework.shutdown rescue nil');
  Lines.Add('');
  Lines.Add('    $stdout.puts ' + #39 + 'Service stopped.' + #39);
  Lines.Add('    0');
  Lines.Add('  end');
  Lines.Add('');
end;

function GenerateHTTPServiceRubyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, AppName, AppDesc, Endpoint: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPServiceRubyCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPServiceRubyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := MakeRubyModuleName(NormalizedUnit) + 'HttpJsonService';
  AppName := NormalizedUnit;
  AppDesc := 'HTTP/JSON service for ' + UnitName;
  Endpoint := 'ipc:' + NormalizedUnit + '_http_json';

  Log(PFormat('Generating HTTP/JSON Ruby service module for unit "%s"', [UnitName.Text]));
  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);
    EmitRubyServiceHeader(Lines, UnitName);
    EmitRubyServiceConfig(Lines, ModuleName, AppName, AppDesc, Endpoint);
    EmitRubyServiceHelpers(Lines);
    EmitRubyServiceStubs(Lines, SupportedFuncs, ApiNames);
    EmitRubyServiceRegistration(Lines, SupportedFuncs, ApiNames);
    EmitRubyServiceMain(Lines);
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('if __FILE__ == $PROGRAM_NAME');
    Lines.Add('  rc = ' + ModuleName.Text + '.main');
    Lines.Add('  $stdout.flush');
    Lines.Add('  $stderr.flush');
    Lines.Add('  exit!(rc)');
    Lines.Add('end');
    Lines.Add('');
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
    'ruby', 'Ruby HTTP/JSON service code',
    asService, akServiceCode,
    '_http_json_service.rb', False,
    @GenerateHTTPServiceRubyCode);
end.
