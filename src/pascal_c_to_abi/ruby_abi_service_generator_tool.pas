unit ruby_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceRubyCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[ruby_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[ruby_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Ruby_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'read_int32'
  else if T.Same('int64') then Result := 'read_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'read_uint32'
  else if T.Same('word') then Result := 'read_uint16'
  else if T.Same('smallint') then Result := 'read_int16'
  else if T.Same('byte') then Result := 'read_uint8'
  else if T.Same('uint64') then Result := 'read_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'read_double'
  else if T.Same('single') then Result := 'read_single'
  else if IsStringABIType(T) then Result := 'read_string'
  else Result := '';
end;

function ABI_Type_To_Ruby_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'write_int32'
  else if T.Same('int64') then Result := 'write_int64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'write_uint32'
  else if T.Same('word') then Result := 'write_uint16'
  else if T.Same('smallint') then Result := 'write_int16'
  else if T.Same('byte') then Result := 'write_uint8'
  else if T.Same('uint64') then Result := 'write_uint64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'write_double'
  else if T.Same('single') then Result := 'write_single'
  else if IsStringABIType(T) then Result := 'write_string'
  else Result := '';
end;

function ABI_Type_To_Ruby_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := #39 + #39
  else if T.Same('double') or T.Same('extended') or T.Same('real') or T.Same('single') then
    Result := '0.0'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Ruby_Read_Func(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsRubyKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('alias') or S.Same('and') or S.Same('begin') or S.Same('break') or
    S.Same('case') or S.Same('class') or S.Same('def') or S.Same('do') or
    S.Same('else') or S.Same('elsif') or S.Same('end') or S.Same('ensure') or
    S.Same('false') or S.Same('for') or S.Same('if') or S.Same('in') or
    S.Same('module') or S.Same('next') or S.Same('nil') or S.Same('not') or
    S.Same('or') or S.Same('redo') or S.Same('rescue') or S.Same('retry') or
    S.Same('return') or S.Same('self') or S.Same('super') or S.Same('then') or
    S.Same('true') or S.Same('undef') or S.Same('unless') or S.Same('until') or
    S.Same('when') or S.Same('while') or S.Same('yield');
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

  if IsRubyKeyword(Result) then
    Result := Result + '_';

  if (Result.Len > 0) and (Result[1] >= 'A') and (Result[1] <= 'Z') then
  begin
    Result[1] := SystemChar(Ord(Result[1]) + 32);
    Result := Result + '_param';
  end;

  if Result.Same('uid') or Result.Same('p2p_name') or Result.Same('input') or
     Result.Same('output') or Result.Same('param') or Result.Same('target') or
     Result.Same('result') or Result.Same('status') or Result.Same('msg') or
     Result.Same('handle') or Result.Same('resp') or Result.Same('raw') or
     Result.Same('app') or Result.Same('tramp') or Result.Same('issue') or
     Result.Same('deserialize') or Result.Same('ref_addr') or Result.Same('result_addr') then
    Result := Result + '_param';
end;

function RubyNeedsDoubleQuote(const S: TP_String): boolean;
var
  i: integer;
  c: TP_Char;
begin
  Result := False;
  for i := 1 to S.Len do
  begin
    c := S[i];
    if (c < #32) or (c = #127) then
      Exit(True);
  end;
end;

function RubyStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  if RubyNeedsDoubleQuote(S) then
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
  end
  else
  begin
    Result := #39;
    for i := 1 to S.Len do
    begin
      c := S[i];
      if c = #39 then
      begin
        Result.Append('\');
        Result.Append(#39);
      end
      else if c = '\' then
      begin
        Result.Append('\');
        Result.Append('\');
      end
      else
        Result.Append(c);
    end;
    Result.Append(#39);
  end;
end;

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

function BuildRubyParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRubyIdent(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
var
  Tmp: TP_String;
begin
  Result := 'uid, p2p_name';
  Tmp := BuildRubyParamDecl(Params);
  if Tmp <> '' then
    Result := Result + ', ' + Tmp;
end;

function BuildInternalCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := 'safe_uid(input), safe_p2p_name(input)';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeRubyIdent(Params[i].Name, i);
    Result := Result + ', ' + PName;
  end;
end;

procedure EmitInternalCallStub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetDefault: TP_String;
begin
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  Lines.Add('    def self.internal_call_' + ApiName + '(' + ParamDecl + ')');
  if F.IsFunction then
  begin
    RetDefault := ABI_Type_To_Ruby_Default(F.ReturnType);
    Lines.Add('      ' + RetDefault);
  end
  else
    Lines.Add('      nil');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitCallbackImplementation(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ArgList, PName, ReadFn, WriteFn: TP_String;
  i: integer;
  IsCall: boolean;
begin
  IsCall := F.IsFunction;

  if IsCall then
    Lines.Add('    def self.callback_' + ApiName + '(input, output)')
  else
    Lines.Add('    def self.callback_' + ApiName + '(input)');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeRubyIdent(F.Params[i].Name, i);
    ReadFn := ABI_Type_To_Ruby_Read_Func(F.Params[i].PascalType);
    Lines.Add('      begin');
    Lines.Add('        ' + PName + ' = input.' + ReadFn);
    Lines.Add('      rescue StandardError');
    if IsCall then
    begin
      Lines.Add('        output.write_uint8(STATUS_ERROR)');
      Lines.Add('        output.write_string(' + RubyStrLit('input truncated: ' + PName) + ')');
    end;
    Lines.Add('        return');
    Lines.Add('      end');
  end;

  ArgList := BuildInternalCallArgList(F.Params);
  Lines.Add('      begin');
  if IsCall then
  begin
    Lines.Add('        v = internal_call_' + ApiName + '(' + ArgList + ')');
    WriteFn := ABI_Type_To_Ruby_Write_Func(F.ReturnType);
    Lines.Add('        output.write_uint8(STATUS_OK)');
    Lines.Add('        output.' + WriteFn + '(v)');
  end
  else
  begin
    Lines.Add('        internal_call_' + ApiName + '(' + ArgList + ')');
  end;
  Lines.Add('      rescue StandardError => e');
  if IsCall then
  begin
    Lines.Add('        output.write_uint8(STATUS_ERROR)');
    Lines.Add('        output.write_string(e.message)');
  end
  else
  begin
    Lines.Add('        warn(' + RubyStrLit('[callback_' + ApiName + '] ') + ' + e.message)');
  end;
  Lines.Add('      end');
  Lines.Add('    end');
  Lines.Add('');
end;

procedure EmitRegisterAll(Lines: TPascalStringList;
  const SupportedFuncs: TArryFunctionStructure;
  const ApiNames: TPascalStringList);
var
  i: integer;
  F: TFunctionStructure;
  ApiName, Desc: TP_String;
begin
  Lines.Add('    def self.register_all_abi_apis(app)');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Desc := 'ABI api for ' + F.Name;
    if F.IsFunction then
      Lines.Add('      app.register_call(' + RubyStrLit(ApiName) + ', ' + RubyStrLit(Desc) +
        ', &method(:callback_' + ApiName + '))')
    else
      Lines.Add('      app.register_notify(' + RubyStrLit(ApiName) + ', ' + RubyStrLit(Desc) +
        ', &method(:callback_' + ApiName + '))');
  end;
  Lines.Add('    end');
  Lines.Add('');

  Lines.Add('    def self.register_all_p2p_abi_apis');
  for i := 0 to High(SupportedFuncs) do
  begin
    F := SupportedFuncs[i];
    ApiName := ApiNames[i];
    Desc := 'ABI api for ' + F.Name;
    if F.IsFunction then
      Lines.Add('      LingoFuse.register_p2p_call(' + RubyStrLit(ApiName) + ', ' + RubyStrLit(Desc) +
        ', &method(:callback_' + ApiName + '))')
    else
      Lines.Add('      LingoFuse.register_p2p_notify(' + RubyStrLit(ApiName) + ', ' + RubyStrLit(Desc) +
        ', &method(:callback_' + ApiName + '))');
  end;
  Lines.Add('    end');
  Lines.Add('');

  Lines.Add('    def self.create_and_register_abi_app');
  Lines.Add('      app = LingoFuse::AppHandle.new(DEFAULT_APP_NAME, DEFAULT_APP_DESC)');
  Lines.Add('      register_all_abi_apis(app)');
  Lines.Add('      app');
  Lines.Add('    end');
  Lines.Add('');
end;

function GenerateABIServiceRubyCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceRubyCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceRubyCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating Ruby ABI service for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('Service covers %d ABI APIs', [Length(SupportedFuncs)]));

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('# frozen_string_literal: true');
    Lines.Add('');
    Lines.Add('require ' + RubyStrLit('lingofuse'));
    Lines.Add('');
    Lines.Add('module ' + NormalizedUnit + '_abi');
    Lines.Add('  module Service');
    Lines.Add('    DEFAULT_APP_NAME = ' + RubyStrLit(AppName));
    Lines.Add('    DEFAULT_APP_DESC = ' + RubyStrLit(AppDesc));
    Lines.Add('    STATUS_OK = 0x00');
    Lines.Add('    STATUS_ERROR = 0xFF');
    Lines.Add('');
    Lines.Add('    module_function');
    Lines.Add('');
    Lines.Add('    def safe_uid(input)');
    Lines.Add('      v = input.p2p_uid');
    Lines.Add('      v.is_a?(String) && v.bytesize == 32 ? v : (0.chr * 32).b');
    Lines.Add('    end');
    Lines.Add('');
    Lines.Add('    def safe_p2p_name(input)');
    Lines.Add('      v = input.p2p_name');
    Lines.Add('      v.is_a?(String) ? v : ' + #39 + #39);
    Lines.Add('    end');
    Lines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      EmitInternalCallStub(Lines, ApiName, F);
    end;

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      F := SupportedFuncs[i];
      ApiName := MakeApiName(F.Name);
      if UsedApiNames.IndexOf(ApiName) >= 0 then
      begin
        j := 1;
        while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
          Inc(j);
        ApiName := ApiName + '_' + umlIntToStr(j).Text;
      end;
      UsedApiNames.Add(ApiName);
      EmitCallbackImplementation(Lines, ApiName, F);
    end;

    EmitRegisterAll(Lines, SupportedFuncs, UsedApiNames);

    Lines.Add('  end');
    Lines.Add('end');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for Ruby ABI service', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'ruby',
    'xxx_abi_service.rb',
    gkService,
    'Ruby ABI service implementation',
    @GenerateABIServiceRubyCode);

end.
