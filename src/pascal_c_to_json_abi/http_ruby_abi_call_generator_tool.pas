unit http_ruby_abi_call_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_json_abi_registry;

function GenerateHTTPCallRubyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ruby_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ruby_abi_call_generator] %s', [PFormat(Fmt, Args)]);
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

// MakeSafeRubyParamIdent - parameter names must start lowercase.
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

function BuildRubyArgArrayLiteral(const Params: TParamArray): TP_String;
begin
  Result := '[' + BuildRubyParamList(Params) + ']';
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

function BuildRubySignature(const F: TFunctionStructure;
  const ApiName: TP_String): TP_String;
var
  i: integer;
  ParamStr, n, T: TP_String;
begin
  ParamStr := '';
  for i := 0 to High(F.Params) do
  begin
    n := MakeSafeRubyParamIdent(F.Params[i].Name, i);
    T := ABI_Type_To_Ruby_Doc_Type(F.Params[i].PascalType);
    if i > 0 then
      ParamStr := ParamStr + ', ';
    ParamStr := ParamStr + n + ': ' + T;
  end;
  if F.IsFunction then
    Result := ApiName + '(' + ParamStr + ') -> ' +
      ABI_Type_To_Ruby_Doc_Type(F.ReturnType)
  else
    Result := ApiName + '(' + ParamStr + ') -> nil';
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

procedure EmitRubyHeader(Lines: TPascalStringList; const UnitName: TP_String);
begin
  Lines.Add('# -*- coding: utf-8 -*-');
  Lines.Add('# Auto-generated by http_ruby_abi_call_generator_tool.pas.');
  Lines.Add('# Source model unit: ' + UnitName.Text + '.');
  Lines.Add('# Do not edit by hand unless you know what you are doing.');
  Lines.Add('#');
  Lines.Add('# Pure HTTP client. Talks to bridge.py. No LingoFuse dependency.');
  Lines.Add('#');
  Lines.Add('# Configuration:');
  Lines.Add('#   <Module>.base_url          = "http://..."   (mutable)');
  Lines.Add('#   <Module>.http_call_timeout = 30.0           (mutable)');
  Lines.Add('#   <Module>.debug_log         = true           (mutable)');
  Lines.Add('#');
  Lines.Add('# The old uppercase names (HTTP_CALL_BASE_URL / HTTP_CALL_TIMEOUT');
  Lines.Add('# / DEBUG_LOG) are READ-ONLY accessors kept for compatibility.');
  Lines.Add('# Do NOT assign to them: Ruby parses `Module::NAME = ...` as a');
  Lines.Add('# constant assignment and raises "dynamic constant assignment".');
  Lines.Add('');
  Lines.Add('require ' + #39 + 'net/http' + #39);
  Lines.Add('require ' + #39 + 'json' + #39);
  Lines.Add('require ' + #39 + 'uri' + #39);
  Lines.Add('');
end;

procedure EmitRubyModuleOpen(Lines: TPascalStringList;
  const ModuleName: TP_String);
begin
  Lines.Add('module ' + ModuleName.Text);
  Lines.Add('');
end;

procedure EmitRubyConfig(Lines: TPascalStringList; const BaseUrl: TP_String);
begin
  Lines.Add('  # ------------------------------------------------------------------');
  Lines.Add('  # Configuration (module instance variables + accessors)');
  Lines.Add('  #');
  Lines.Add('  # Use the lowercase accessors to change these values:');
  Lines.Add('  #   ' + #39 + 'Module.base_url = "http://..."' + #39);
  Lines.Add('  #');
  Lines.Add('  # The uppercase compatibility readers (HTTP_CALL_BASE_URL etc.)');
  Lines.Add('  # are READ-ONLY. Assignment to them would be parsed as a constant');
  Lines.Add('  # assignment by Ruby, which is illegal inside a method.');
  Lines.Add('  # ------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('  @base_url          = ' + RubyStrLit(BaseUrl).Text);
  Lines.Add('  @http_call_timeout = 30.0');
  Lines.Add('  @debug_log         = (ENV[' + #39 + 'LINGOFUSE_DEBUG' + #39 + '] == ' + #39 + '1' + #39 + ') ||');
  Lines.Add('                       (ENV[' + #39 + 'LINGOFUSE_DEBUG' + #39 + '] == ' + #39 + 'true' + #39 + ')');
  Lines.Add('');
  Lines.Add('  class << self');
  Lines.Add('    attr_accessor :base_url');
  Lines.Add('    attr_accessor :http_call_timeout');
  Lines.Add('    attr_accessor :debug_log');
  Lines.Add('');
  Lines.Add('    # ---- Compatibility readers (do NOT assign) --------------------');
  Lines.Add('    def HTTP_CALL_BASE_URL; @base_url; end');
  Lines.Add('    def HTTP_CALL_TIMEOUT; @http_call_timeout; end');
  Lines.Add('    def DEBUG_LOG; @debug_log; end');
  Lines.Add('  end');
  Lines.Add('');
  Lines.Add('  # Single exception type raised by every generated function.');
  Lines.Add('  class HTTPCallError < StandardError');
  Lines.Add('    attr_reader :code, :http_status');
  Lines.Add('');
  Lines.Add('    def initialize(message, code = -1, http_status = 0)');
  Lines.Add('      super(message)');
  Lines.Add('      @code = code');
  Lines.Add('      @http_status = http_status');
  Lines.Add('    end');
  Lines.Add('  end');
  Lines.Add('');
end;

procedure EmitRubyTransport(Lines: TPascalStringList);
begin
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('  # Transport primitive (single point of entry)');
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('  def self._call_api(api_name, args)');
  Lines.Add('    base = @base_url.to_s.sub(%r{/+$}, ' + #39 + #39 + ')');
  Lines.Add('    url  = URI.parse("#{base}/#{api_name}")');
  Lines.Add('    body = JSON.generate({ ' + #39 + 'args' + #39 + ' => args })');
  Lines.Add('');
  Lines.Add('    if @debug_log');
  Lines.Add('      warn "[http-json-call] POST #{url} body=#{body}"');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    http = Net::HTTP.new(url.host, url.port)');
  Lines.Add('    http.use_ssl      = (url.scheme == ' + #39 + 'https' + #39 + ')');
  Lines.Add('    http.open_timeout = @http_call_timeout');
  Lines.Add('    http.read_timeout = @http_call_timeout');
  Lines.Add('');
  Lines.Add('    request = Net::HTTP::Post.new(url.request_uri)');
  Lines.Add('    request[' + #39 + 'Content-Type' + #39 + '] = ' +
    #39 + 'application/json; charset=utf-8' + #39);
  Lines.Add('    request.body = body');
  Lines.Add('');
  Lines.Add('    response = begin');
  Lines.Add('      http.request(request)');
  Lines.Add('    rescue Net::OpenTimeout, Net::ReadTimeout => e');
  Lines.Add('      raise HTTPCallError.new("Request timed out: #{e.message}", -1, 0)');
  Lines.Add('    rescue StandardError => e');
  Lines.Add('      raise HTTPCallError.new("Network error: #{e.message}", -1, 0)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    if @debug_log');
  Lines.Add('      warn "[http-json-call] response #{response.code}: #{response.body}"');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    http_status = response.code.to_i');
  Lines.Add('    text        = response.body');
  Lines.Add('');
  Lines.Add('    if http_status < 200 || http_status >= 300');
  Lines.Add('      raise HTTPCallError.new("HTTP #{http_status}: #{text}", -1, http_status)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    if text.nil? || text.empty?');
  Lines.Add('      raise HTTPCallError.new(' + #39 + 'Empty response from bridge' + #39 +
    ', -1, http_status)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    parsed = begin');
  Lines.Add('      JSON.parse(text)');
  Lines.Add('    rescue JSON::ParserError => e');
  Lines.Add('      raise HTTPCallError.new("Invalid JSON response: #{e.message}", -1, http_status)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    unless parsed.is_a?(Hash)');
  Lines.Add('      raise HTTPCallError.new(' + #39 + 'Response is not a JSON object' + #39 +
    ', -1, http_status)');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    unless parsed.key?(' + #39 + 'code' + #39 + ')');
  Lines.Add('      error = parsed[' + #39 + 'error' + #39 + ']');
  Lines.Add('      raise HTTPCallError.new(');
  Lines.Add('        error.is_a?(String) ? error : ' + #39 +
    'Response has no "code" field' + #39 + ',');
  Lines.Add('        -1,');
  Lines.Add('        http_status');
  Lines.Add('      )');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    if parsed[' + #39 + 'code' + #39 + '] != 0');
  Lines.Add('      raise HTTPCallError.new(');
  Lines.Add('        parsed[' + #39 + 'error' + #39 + '] || ' + #39 +
    'Remote call failed' + #39 + ',');
  Lines.Add('        parsed[' + #39 + 'code' + #39 + '].to_i,');
  Lines.Add('        http_status');
  Lines.Add('      )');
  Lines.Add('    end');
  Lines.Add('');
  Lines.Add('    parsed[' + #39 + 'result' + #39 + ']');
  Lines.Add('  end');
  Lines.Add('');
end;

procedure EmitRubyFunctions(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i, j: integer;
  F: TFunctionStructure;
  ApiName, ParamList, ArgList, Description: TP_String;
  MethodName: TP_String;
  ParamType: TP_String;
  ReturnType: TP_String;
  HasParams: boolean;
begin
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('  # Typed call functions');
  Lines.Add('  #');
  Lines.Add('  # Every function is synchronous. Wrap in Thread.new { ... } for');
  Lines.Add('  # concurrent calls.');
  Lines.Add('  # ---------------------------------------------------------------------');
  Lines.Add('');

  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    HasParams := Length(F.Params) > 0;

    ParamList := BuildRubyParamList(F.Params);
    ArgList := BuildRubyArgArrayLiteral(F.Params);
    Description := GetFullDescription(F.Comment);
    MethodName := MakeSafeRubyIdent(ApiName, i);

    Lines.Add('  # ' + Description.Text);
    for j := 0 to High(F.Params) do
    begin
      ParamType := ABI_Type_To_Ruby_Doc_Type(F.Params[j].PascalType);
      Lines.Add('  # @param ' +
        MakeSafeRubyParamIdent(F.Params[j].Name, j) +
        ' [' + ParamType.Text + ']');
    end;

    if F.IsFunction then
    begin
      ReturnType := ABI_Type_To_Ruby_Doc_Type(F.ReturnType);
      Lines.Add('  # @return [' + ReturnType.Text + ']');
    end
    else
      Lines.Add('  # @return [nil]');
    Lines.Add('  # @raise [HTTPCallError] on any failure.');

    if HasParams then
      Lines.Add('  def self.' + MethodName.Text + '(' + ParamList.Text + ')')
    else
      Lines.Add('  def self.' + MethodName.Text);

    Lines.Add('    _call_api(' + RubyStrLit(ApiName).Text + ', ' + ArgList.Text + ')');
    Lines.Add('  end');
    Lines.Add('');
  end;
end;

procedure EmitRubyModuleClose(Lines: TPascalStringList);
begin
  Lines.Add('end');
  Lines.Add('');
end;

function GenerateHTTPCallRubyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, ModuleName, BaseUrl: TP_String;
  ApiNames: TPascalStringList;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateHTTPCallRubyCode: Model is nil');
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateHTTPCallRubyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  if (NormalizedUnit.Len > 0) and (NormalizedUnit[1] >= '0') and (NormalizedUnit[1] <= '9') then
    NormalizedUnit := '_' + NormalizedUnit;
  ModuleName := MakeRubyModuleName(NormalizedUnit) + 'HttpJsonCall';
  BaseUrl := 'http://127.0.0.1:8081/' + NormalizedUnit;

  Log(PFormat('Generating HTTP/JSON Ruby call module for unit "%s"', [UnitName.Text]));
  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  ApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    BuildDisambiguatedApiNames(SupportedFuncs, ApiNames);
    EmitRubyHeader(Lines, UnitName);
    EmitRubyModuleOpen(Lines, ModuleName);
    EmitRubyConfig(Lines, BaseUrl);
    EmitRubyTransport(Lines);
    EmitRubyFunctions(Lines, SupportedFuncs, ApiNames);
    EmitRubyModuleClose(Lines);
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
    'ruby', 'Ruby HTTP/JSON call code',
    asCall, akCallCode,
    '_http_json_call.rb', False,
    @GenerateHTTPCallRubyCode);
end.
