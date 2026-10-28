unit cpp_abi_service_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIServiceHppCode(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABIServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or
    T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Cpp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'std::int32_t'
  else if T.Same('int64') then
    Result := 'std::int64_t'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'std::uint32_t'
  else if T.Same('word') then
    Result := 'std::uint16_t'
  else if T.Same('smallint') then
    Result := 'std::int16_t'
  else if T.Same('byte') then
    Result := 'std::uint8_t'
  else if T.Same('uint64') then
    Result := 'std::uint64_t'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'double'
  else if T.Same('single') then
    Result := 'float'
  else if IsStringABIType(T) then
    Result := 'std::string'
  else
    Result := '';
end;

function ABI_Type_To_Cpp_Param_Decl(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'const std::string&'
  else
    Result := ABI_Type_To_Cpp_Decl(T);
end;

function ABI_Type_To_Cpp_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'std::string{}'
  else if T.Same('double') or T.Same('extended') or T.Same('real') or T.Same('single') then
    Result := '0.0'
  else
    Result := '0';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Cpp_Decl(T) <> '';
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsCppKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('alignas') or S.Same('alignof') or S.Same('and') or S.Same('and_eq') or
    S.Same('asm') or S.Same('auto') or S.Same('bitand') or S.Same('bitor') or
    S.Same('bool') or S.Same('break') or S.Same('case') or S.Same('catch') or
    S.Same('char') or S.Same('char8_t') or S.Same('char16_t') or S.Same('char32_t') or
    S.Same('class') or S.Same('compl') or S.Same('concept') or S.Same('const') or
    S.Same('consteval') or S.Same('constexpr') or S.Same('constinit') or
    S.Same('const_cast') or S.Same('continue') or S.Same('co_await') or
    S.Same('co_return') or S.Same('co_yield') or S.Same('decltype') or
    S.Same('default') or S.Same('delete') or S.Same('do') or S.Same('double') or
    S.Same('dynamic_cast') or S.Same('else') or S.Same('enum') or
    S.Same('explicit') or S.Same('export') or S.Same('extern') or S.Same('false') or
    S.Same('float') or S.Same('for') or S.Same('friend') or S.Same('goto') or
    S.Same('if') or S.Same('inline') or S.Same('int') or S.Same('long') or
    S.Same('mutable') or S.Same('namespace') or S.Same('new') or S.Same('noexcept') or
    S.Same('not') or S.Same('not_eq') or S.Same('nullptr') or S.Same('operator') or
    S.Same('or') or S.Same('or_eq') or S.Same('private') or S.Same('protected') or
    S.Same('public') or S.Same('register') or S.Same('reinterpret_cast') or
    S.Same('requires') or S.Same('return') or S.Same('short') or S.Same('signed') or
    S.Same('sizeof') or S.Same('static') or S.Same('static_assert') or
    S.Same('static_cast') or S.Same('struct') or S.Same('switch') or
    S.Same('template') or S.Same('this') or S.Same('thread_local') or S.Same('throw') or
    S.Same('true') or S.Same('try') or S.Same('typedef') or S.Same('typeid') or
    S.Same('typename') or S.Same('union') or S.Same('unsigned') or S.Same('using') or
    S.Same('virtual') or S.Same('void') or S.Same('volatile') or S.Same('wchar_t') or
    S.Same('while') or S.Same('xor') or S.Same('xor_eq');
end;

function MakeSafeCppParamName(const Name: TP_String; Index: integer): TP_String;
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

  if IsCppKeyword(Result) then
    Result := Result + '_';
end;

function CppStrLit(const S: TP_String): TP_String;
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
    else
      Result.Append(c);
  end;
  Result.Append('"');
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

function BuildCppParamList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName, PTyp: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCppParamName(Params[i].Name, i);
    PTyp := ABI_Type_To_Cpp_Param_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PTyp + ' ' + PName;
  end;
end;

function BuildCppArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  PName: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    PName := MakeSafeCppParamName(Params[i].Name, i);
    if i > 0 then
      Result := Result + ', ';
    Result := Result + PName;
  end;
end;

function BuildInternalCallParamDecl(const Params: TParamArray): TP_String;
begin
  Result := 'const std::array<std::uint8_t, 32>& _lf_uid, const std::string& _lf_p2p_name';
  if Length(Params) > 0 then
    Result := Result + ', ' + BuildCppParamList(Params);
end;

function BuildInternalCallArgList(const Params: TParamArray): TP_String;
begin
  Result := '_lf_uid, _lf_p2p_name';
  if Length(Params) > 0 then
    Result := Result + ', ' + BuildCppArgList(Params);
end;

procedure EmitSafetyHelpers(Lines: TPascalStringList);
begin
  Lines.Add('inline void Safe_Write_Error(TDataHnd hnd, const std::string& msg) noexcept {');
  Lines.Add('    try {');
  Lines.Add('        LF_WriteUInt8(hnd, STATUS_ERROR);');
  Lines.Add('        lingofuse::io::write_string(hnd, msg);');
  Lines.Add('    } catch (...) {');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('template <typename T>');
  Lines.Add('inline void Safe_Write_Scalar(TDataHnd hnd, T value) noexcept {');
  Lines.Add('    static_assert(std::is_arithmetic<T>::value,');
  Lines.Add('                  "Safe_Write_Scalar requires an arithmetic type");');
  Lines.Add('    try {');
  Lines.Add('        std::uint8_t buf[1 + sizeof(T)];');
  Lines.Add('        buf[0] = STATUS_OK;');
  Lines.Add('        std::memcpy(buf + 1, &value, sizeof(T));');
  Lines.Add('        LF_WriteBuffer(hnd, buf, static_cast<int64_t>(sizeof(buf)));');
  Lines.Add('    } catch (...) {');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('inline void Safe_Write_String(TDataHnd hnd, const std::string& value) noexcept {');
  Lines.Add('    try {');
  Lines.Add('        const std::size_t total = 1 + value.size() + 1;');
  Lines.Add('        std::vector<std::uint8_t> buf(total);');
  Lines.Add('        buf[0] = STATUS_OK;');
  Lines.Add('        if (!value.empty()) {');
  Lines.Add('            std::memcpy(buf.data() + 1, value.data(), value.size());');
  Lines.Add('        }');
  Lines.Add('        buf[total - 1] = 0;');
  Lines.Add('        LF_WriteBuffer(hnd, buf.data(), static_cast<int64_t>(total));');
  Lines.Add('    } catch (...) {');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('inline void Safe_Write_Void(TDataHnd hnd) noexcept {');
  Lines.Add('    try {');
  Lines.Add('        std::uint8_t buf[1] = { STATUS_OK };');
  Lines.Add('        LF_WriteBuffer(hnd, buf, 1);');
  Lines.Add('    } catch (...) {');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitInternalCallDecl(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetType, Desc: TP_String;
begin
  Desc := GetFullDescription(F.Comment);
  if Desc.Len > 0 then
    Lines.Add('// ' + Desc.Text);

  ParamDecl := BuildInternalCallParamDecl(F.Params);
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);

  if F.IsFunction then
    Lines.Add(RetType + ' internal_call_' + ApiName + '(' + ParamDecl + ');')
  else
    Lines.Add('void internal_call_' + ApiName + '(' + ParamDecl + ');');
  Lines.Add('');
end;

procedure EmitInternalCallStub(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  ParamDecl, RetType, RetDefault: TP_String;
  i: integer;
  PName: TP_String;
begin
  ParamDecl := BuildInternalCallParamDecl(F.Params);
  RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
  RetDefault := ABI_Type_To_Cpp_Default(F.ReturnType);

  if F.IsFunction then
    Lines.Add(RetType + ' internal_call_' + ApiName + '(' + ParamDecl + ') {')
  else
    Lines.Add('void internal_call_' + ApiName + '(' + ParamDecl + ') {');

  Lines.Add('    (void)_lf_uid;');
  Lines.Add('    (void)_lf_p2p_name;');
  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeCppParamName(F.Params[i].Name, i);
    Lines.Add('    (void)' + PName + ';');
  end;

  if F.IsFunction then
    Lines.Add('    return ' + RetDefault + ';');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitCallbackDecl(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
begin
  if F.IsFunction then
    Lines.Add('void LF_CDECL Callback_' + ApiName + '(void* _Trigger, void* _In, void* _Out);')
  else
    Lines.Add('void LF_CDECL Callback_' + ApiName + '(void* _Trigger, void* _In);');
  Lines.Add('');
end;

procedure EmitCallbackImplementation(Lines: TPascalStringList; const ApiName: TP_String; const F: TFunctionStructure);
var
  RetType, ArgList: TP_String;
  i: integer;
  PName, PTyp: TP_String;
  IsCall: boolean;
begin
  IsCall := F.IsFunction;

  if IsCall then
    Lines.Add('void LF_CDECL Callback_' + ApiName + '(void* _Trigger, void* _In, void* _Out) {')
  else
    Lines.Add('void LF_CDECL Callback_' + ApiName + '(void* _Trigger, void* _In) {');

  Lines.Add('    (void)_Trigger;');
  Lines.Add('    lingofuse::DataHandle in_h(static_cast<TDataHnd>(_In), false);');
  if IsCall then
    Lines.Add('    lingofuse::DataHandle out_h(static_cast<TDataHnd>(_Out), false);');
  Lines.Add('');
  Lines.Add('    std::array<std::uint8_t, 32> _lf_uid{};');
  Lines.Add('    std::string _lf_p2p_name;');
  Lines.Add('    try {');
  Lines.Add('        _lf_uid = in_h.getP2PUid();');
  Lines.Add('        _lf_p2p_name = in_h.getP2PName();');
  Lines.Add('    } catch (...) {');
  Lines.Add('    }');
  Lines.Add('');

  for i := 0 to High(F.Params) do
  begin
    PName := MakeSafeCppParamName(F.Params[i].Name, i);
    PTyp := ABI_Type_To_Cpp_Decl(F.Params[i].PascalType);

    if IsStringABIType(F.Params[i].PascalType) then
    begin
      Lines.Add('    std::string ' + PName + ';');
      if IsCall then
      begin
        Lines.Add('    try {');
        Lines.Add('        if (!in_h.read(' + PName + ')) {');
        Lines.Add('            Safe_Write_Error(out_h.get(), "input truncated: ' + PName + '");');
        Lines.Add('            return;');
        Lines.Add('        }');
        Lines.Add('    } catch (const std::exception& _e) {');
        Lines.Add('        Safe_Write_Error(out_h.get(), std::string("read ' + PName + ' failed: ") + _e.what());');
        Lines.Add('        return;');
        Lines.Add('    }');
      end
      else
      begin
        Lines.Add('    try {');
        Lines.Add('        if (!in_h.read(' + PName + ')) return;');
        Lines.Add('    } catch (...) {');
        Lines.Add('        return;');
        Lines.Add('    }');
      end;
    end
    else
    begin
      Lines.Add('    ' + PTyp + ' ' + PName + ' = 0;');
      if IsCall then
      begin
        Lines.Add('    if (!in_h.read(' + PName + ')) {');
        Lines.Add('        Safe_Write_Error(out_h.get(), "input truncated: ' + PName + '");');
        Lines.Add('        return;');
        Lines.Add('    }');
      end
      else
      begin
        Lines.Add('    if (!in_h.read(' + PName + ')) return;');
      end;
    end;
  end;

  Lines.Add('');
  ArgList := BuildInternalCallArgList(F.Params);

  if IsCall then
  begin
    RetType := ABI_Type_To_Cpp_Decl(F.ReturnType);
    if IsStringABIType(F.ReturnType) then
    begin
      Lines.Add('    std::string _ret;');
      Lines.Add('    try {');
      Lines.Add('        _ret = internal_call_' + ApiName + '(' + ArgList + ');');
      Lines.Add('    } catch (const std::exception& _e) {');
      Lines.Add('        Safe_Write_Error(out_h.get(), _e.what());');
      Lines.Add('        return;');
      Lines.Add('    } catch (...) {');
      Lines.Add('        Safe_Write_Error(out_h.get(), "unknown exception");');
      Lines.Add('        return;');
      Lines.Add('    }');
      Lines.Add('    Safe_Write_String(out_h.get(), _ret);');
    end
    else
    begin
      Lines.Add('    ' + RetType + ' _ret = 0;');
      Lines.Add('    try {');
      Lines.Add('        _ret = internal_call_' + ApiName + '(' + ArgList + ');');
      Lines.Add('    } catch (const std::exception& _e) {');
      Lines.Add('        Safe_Write_Error(out_h.get(), _e.what());');
      Lines.Add('        return;');
      Lines.Add('    } catch (...) {');
      Lines.Add('        Safe_Write_Error(out_h.get(), "unknown exception");');
      Lines.Add('        return;');
      Lines.Add('    }');
      Lines.Add('    Safe_Write_Scalar<' + RetType + '>(out_h.get(), _ret);');
    end;
  end
  else
  begin
    Lines.Add('    try {');
    Lines.Add('        internal_call_' + ApiName + '(' + ArgList + ');');
    Lines.Add('    } catch (...) {');
    Lines.Add('    }');
  end;

  Lines.Add('}');
  Lines.Add('');
end;

function GenerateABIServiceHppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc: TP_String;
  ProtocolGuard: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceHppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceHppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;
  ProtocolGuard := 'LINGOFUSE_ABI_WIRE_PROTOCOL_' + NsName + '_DEFINED';

  Log(PFormat('Generating C++ ABI service header for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty header.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#pragma once');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('#include <array>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstring>');
    Lines.Add('#include <string>');
    Lines.Add('#include <type_traits>');
    Lines.Add('#include <vector>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');

    Lines.Add('extern const char* DEFAULT_APP_NAME;');
    Lines.Add('extern const char* DEFAULT_APP_DESC;');
    Lines.Add('');

    Lines.Add('#ifndef ' + ProtocolGuard);
    Lines.Add('#define ' + ProtocolGuard);
    Lines.Add('constexpr std::uint8_t STATUS_OK    = 0x00;');
    Lines.Add('constexpr std::uint8_t STATUS_ERROR = 0xFF;');
    Lines.Add('#endif');
    Lines.Add('');

    EmitSafetyHelpers(Lines);

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

      EmitInternalCallDecl(Lines, ApiName, F);
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

      EmitCallbackDecl(Lines, ApiName, F);
    end;

    Lines.Add('int Register_All_ABI_APIs(TAppHnd app);');
    Lines.Add('');
    Lines.Add('int Register_All_P2P_ABI_APIs();');
    Lines.Add('');
    Lines.Add('TAppHnd Create_And_Register_ABI_App();');
    Lines.Add('');
    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service header.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

function GenerateABIServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName, AppName, AppDesc: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, Description: TP_String;
  F: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServiceCppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServiceCppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  AppName := NormalizedUnit + '_abi';
  AppDesc := 'ABI service for ' + UnitName;

  Log(PFormat('Generating C++ ABI service implementation for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty implementation.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('#include "' + NormalizedUnit + '_abi_service.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <array>');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstring>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('#include <type_traits>');
    Lines.Add('#include <vector>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');

    Lines.Add('const char* DEFAULT_APP_NAME = ' + CppStrLit(AppName) + ';');
    Lines.Add('const char* DEFAULT_APP_DESC = ' + CppStrLit(AppDesc) + ';');
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

    Lines.Add('int Register_All_ABI_APIs(TAppHnd app) {');
    Lines.Add('    if (app == nullptr) return -1;');
    Lines.Add('    int _failed = 0;');

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

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;

      if F.IsFunction then
        Lines.Add('    if (LF_RegisterCall(app, ' + CppStrLit(ApiName) + ', ' +
          CppStrLit(Description) + ', nullptr, Callback_' + ApiName + ') != 1) ++_failed;')
      else
        Lines.Add('    if (LF_RegisterNotify(app, ' + CppStrLit(ApiName) + ', ' +
          CppStrLit(Description) + ', nullptr, Callback_' + ApiName + ') != 1) ++_failed;');
    end;

    Lines.Add('    return _failed;');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('int Register_All_P2P_ABI_APIs() {');
    Lines.Add('    int _failed = 0;');

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

      Description := GetFullDescription(F.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + F.Name;

      if F.IsFunction then
        Lines.Add('    if (LF_Register_P2P_Call(' + CppStrLit(ApiName) + ', ' +
          CppStrLit(Description) + ', nullptr, Callback_' + ApiName + ') != 1) ++_failed;')
      else
        Lines.Add('    if (LF_Register_P2P_Notify(' + CppStrLit(ApiName) + ', ' +
          CppStrLit(Description) + ', nullptr, Callback_' + ApiName + ') != 1) ++_failed;');
    end;

    Lines.Add('    return _failed;');
    Lines.Add('}');
    Lines.Add('');

    Lines.Add('TAppHnd Create_And_Register_ABI_App() {');
    Lines.Add('    TAppHnd app = LF_CreateApp(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    Lines.Add('    if (app != nullptr) {');
    Lines.Add('        Register_All_ABI_APIs(app);');
    Lines.Add('    }');
    Lines.Add('    return app;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service implementation.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

initialization

  RegisterGenerator(
    'cpp',
    'xxx_abi_service.hpp',
    gkService,
    'C++ ABI service header',
    @GenerateABIServiceHppCode);

  RegisterGenerator(
    'cpp',
    'xxx_abi_service.cpp',
    gkService,
    'C++ ABI service implementation',
    @GenerateABIServiceCppCode);

end.
