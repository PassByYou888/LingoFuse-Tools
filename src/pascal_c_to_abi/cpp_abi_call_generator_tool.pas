unit cpp_abi_call_generator_tool;


// cpp_abi_call_generator_tool - LingoFuse ABI Call-Side Generator for C++.
//
// This unit is the C++ counterpart of pas_abi_call_generator_tool and
// py_abi_call_generator_tool. It consumes the same TPascal_Func_Model
// (Typ_Normalize_Func = tnf_ABI) and produces TWO self-contained C++
// artefacts:
//
//   GenerateABICallHppCode  ->  <unit>_abi_call.hpp
//       The declaration header. Exposes:
//         extern std::string  ABI_TargetApp;
//         extern std::uint64_t ABI_Timeout;
//         constexpr std::uint8_t STATUS_OK / STATUS_ERROR;
//         class EABI_RemoteError;
//         One typed free-function declaration per supported routine.
//       Include this header to call the matching ABI service from any
//       other translation unit.
//
//   GenerateABICallCppCode  ->  <unit>_abi_call.cpp
//       The implementation. Includes the .hpp above and provides:
//         ABI_TargetApp / ABI_Timeout definitions,
//         One typed free-function definition per supported routine.
//
// Wire protocol (matches cpp_abi_service_generator_tool):
//   request  = [field1][field2]...[fieldN]
//   response = [status:uint8_t][payload]
//     status = 0x00 -> success
//     status = 0xFF -> error followed by a NUL-terminated UTF-8 message
//
// Deployment notes:
//   Neither artefact calls LF_PrepareClient / LF_PrepareDone / LF_Shutdown.
//   The host program is responsible for wiring up LingoFuse before
//   calling any generated function. A typical host program:
//
//       #include "LingoFuse.hpp"
//       #include "my_unit_abi_call.hpp"
//       #include <iostream>
//
//       int main() {
//           lingofuse::LibraryLoader loader;
//           lingofuse::resetPrepare();
//           lingofuse::prepareClient("ipc:my_unit_abi", nullptr);
//           if (lingofuse::prepareDone() != 1) return 1;
//           try {
//               std::cout << my_unit_abi::Add(3, 4) << "\n";
//           } catch (const std::exception& e) {
//               std::cerr << e.what() << "\n";
//           }
//           lingofuse::exitMainThread();
//           lingofuse::shutdown();
//           return 0;
//       }
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


  // GenerateABICallHppCode - generate the call-side declaration header.
  //
  // The returned list contains the lines of a .hpp file that declares
  // every symbol used by the call-side client. The caller owns the list
  // and must release it with DisposeObject.

function GenerateABICallHppCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICallCppCode - generate the call-side implementation file.
//
// The returned list contains the lines of a .cpp file that includes
// the matching .hpp and defines every symbol declared there. The
// caller owns the list and must release it with DisposeObject.

function GenerateABICallCppCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICallCppReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// call-side type mapping, and every exported C++ function. The document
// is written so that both human readers and AI assistants can learn the
// call-side module's usage model from the README alone.
//
// The call-side module produces two files (.hpp + .cpp). This README
// describes the pair as a single unit.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABICallCppReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[cpp_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type mapping
// -----------------------------------------------------------------------------

function IsStringABIType(const T: TP_String): boolean;
begin
  Result := T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar');
end;

function ABI_Type_To_Cpp_Decl(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'int32_t'
  else if T.Same('int64') then Result := 'int64_t'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'uint32_t'
  else if T.Same('word') then Result := 'uint16_t'
  else if T.Same('smallint') then Result := 'int16_t'
  else if T.Same('byte') then Result := 'uint8_t'
  else if T.Same('uint64') then Result := 'uint64_t'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'double'
  else if T.Same('single') then Result := 'float'
  else if IsStringABIType(T) then Result := 'std::string'
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

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Cpp_Decl(T) <> '';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function IsCppKeyword(const S: TP_String): boolean;
begin
  Result :=
    S.Same('alignas') or S.Same('alignof') or S.Same('and') or S.Same('and_eq') or S.Same('asm') or S.Same('atomic_cancel') or
    S.Same('atomic_commit') or S.Same('atomic_noexcept') or S.Same('auto') or S.Same('bitand') or S.Same('bitor') or S.Same('bool') or
    S.Same('break') or S.Same('case') or S.Same('catch') or S.Same('char') or S.Same('char8_t') or S.Same('char16_t') or S.Same('char32_t') or
    S.Same('class') or S.Same('compl') or S.Same('concept') or S.Same('const') or S.Same('consteval') or S.Same('constexpr') or
    S.Same('constinit') or S.Same('const_cast') or S.Same('continue') or S.Same('co_await') or S.Same('co_return') or S.Same('co_yield') or
    S.Same('decltype') or S.Same('default') or S.Same('delete') or S.Same('do') or S.Same('double') or S.Same('dynamic_cast') or
    S.Same('else') or S.Same('enum') or S.Same('explicit') or S.Same('export') or S.Same('extern') or S.Same('false') or S.Same('float') or
    S.Same('for') or S.Same('friend') or S.Same('goto') or S.Same('if') or S.Same('inline') or S.Same('int') or S.Same('long') or
    S.Same('mutable') or S.Same('namespace') or S.Same('new') or S.Same('noexcept') or S.Same('not') or S.Same('not_eq') or S.Same('nullptr') or
    S.Same('operator') or S.Same('or') or S.Same('or_eq') or S.Same('private') or S.Same('protected') or S.Same('public') or
    S.Same('reflexpr') or S.Same('register') or S.Same('reinterpret_cast') or S.Same('requires') or S.Same('return') or S.Same('short') or
    S.Same('signed') or S.Same('sizeof') or S.Same('static') or S.Same('static_assert') or S.Same('static_cast') or S.Same('struct') or
    S.Same('switch') or S.Same('synchronized') or S.Same('template') or S.Same('this') or S.Same('thread_local') or S.Same('throw') or
    S.Same('true') or S.Same('try') or S.Same('typedef') or S.Same('typeid') or S.Same('typename') or S.Same('union') or S.Same('unsigned') or
    S.Same('using') or S.Same('virtual') or S.Same('void') or S.Same('volatile') or S.Same('wchar_t') or S.Same('while') or S.Same('xor') or S.Same('xor_eq');
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
    if (c = '_') or ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or ((i > 1) and (c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append('_');
  end;

  if (Result.Len > 0) and (Result[1] >= '0') and (Result[1] <= '9') then
    Result := '_' + Result;

  if IsCppKeyword(Result) then
    Result := Result + '_';
end;

// -----------------------------------------------------------------------------
// C++ string literal helper
// -----------------------------------------------------------------------------

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
        Log(PFormat('Skipped "%s": parameter "%s" has unsupported ABI type "%s"', [f.Name.Text, f.Params[j].Name.Text, f.Params[j].PascalType.Text]));
        Break;
      end;

    if Supported and f.IsFunction and (not IsSupportedABIType(f.ReturnType)) then
    begin
      Supported := False;
      Log(PFormat('Skipped "%s": return type "%s" is not a supported ABI type', [f.Name.Text, f.ReturnType.Text]));
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
// Build parameter list from a TParamArray
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Emit one typed remote-call function DECLARATION (for the .hpp)
// -----------------------------------------------------------------------------

procedure EmitFunctionDecl(Lines: TPascalStringList; const ApiName: TP_String; const IsFunction: boolean; const Params: TParamArray; const ReturnType: TP_String);
var
  ParamDecl, RetType: TP_String;
begin
  ParamDecl := BuildCppParamList(Params);
  RetType := ABI_Type_To_Cpp_Decl(ReturnType);

  if IsFunction then
    Lines.Add(RetType + ' ' + ApiName + '(' + ParamDecl + ');')
  else
    Lines.Add('void ' + ApiName + '(' + ParamDecl + ');');
end;

// -----------------------------------------------------------------------------
// Emit one typed remote-call function DEFINITION (for the .cpp)
// -----------------------------------------------------------------------------

procedure EmitFunctionDef(Lines: TPascalStringList; const ApiName: TP_String; const IsFunction: boolean; const Params: TParamArray; const ReturnType: TP_String);
var
  i: integer;
  ParamDecl, ParamName, PTyp, RetType: TP_String;
begin
  ParamDecl := BuildCppParamList(Params);
  RetType := ABI_Type_To_Cpp_Decl(ReturnType);

  Lines.Add('');
  if IsFunction then
    Lines.Add(RetType + ' ' + ApiName + '(' + ParamDecl + ') {')
  else
    Lines.Add('void ' + ApiName + '(' + ParamDecl + ') {');

  Lines.Add('    lingofuse::DataHandle _data(' + CppStrLit(ApiName) + ');');

  for i := 0 to High(Params) do
  begin
    ParamName := MakeSafeCppParamName(Params[i].Name, i);
    Lines.Add('    _data.write(' + ParamName + ');');
  end;

  Lines.Add('');
  Lines.Add('    auto _res_opt = lingofuse::tryCall(ABI_TargetApp, _data, ABI_Timeout);');
  Lines.Add('    if (!_res_opt) {');
  Lines.Add('        throw EABI_RemoteError(');
  Lines.Add('            "ABI call \"' + ApiName + '\" returned nil (timeout or target not found)");');
  Lines.Add('    }');
  Lines.Add('    lingofuse::DataHandle& _res = *_res_opt;');
  Lines.Add('');
  Lines.Add('    _res.seek(0);');
  Lines.Add('    std::uint8_t _status = 0;');
  Lines.Add('    if (!_res.read(_status)) {');
  Lines.Add('        throw EABI_RemoteError(');
  Lines.Add('            "ABI call \"' + ApiName + '\": response truncated (status byte)");');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (_status != STATUS_OK) {');
  Lines.Add('        std::string _err;');
  Lines.Add('        try { _res.read(_err); } catch (...) {}');
  Lines.Add('        throw EABI_RemoteError(');
  Lines.Add('            std::string("ABI call \"' + ApiName + '\" failed: ") + _err);');
  Lines.Add('    }');

  if IsFunction then
  begin
    Lines.Add('');
    if IsStringABIType(ReturnType) then
    begin
      Lines.Add('    std::string _ret;');
      Lines.Add('    if (!_res.read(_ret)) {');
      Lines.Add('        throw EABI_RemoteError(');
      Lines.Add('            "ABI call \"' + ApiName + '\": response truncated (result)");');
      Lines.Add('    }');
      Lines.Add('    return _ret;');
    end
    else
    begin
      Lines.Add('    ' + RetType + ' _ret = 0;');
      Lines.Add('    if (!_res.read(_ret)) {');
      Lines.Add('        throw EABI_RemoteError(');
      Lines.Add('            "ABI call \"' + ApiName + '\": response truncated (result)");');
      Lines.Add('    }');
      Lines.Add('    return _ret;');
    end;
  end;

  Lines.Add('}');
  Lines.Add('');
end;

// -----------------------------------------------------------------------------
// GenerateABICallHppCode
// -----------------------------------------------------------------------------

function GenerateABICallHppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName, NsName: TP_String;
  ProtocolGuard: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallHppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallHppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetAppName := NormalizedUnit + '_abi';
  NsName := NormalizedUnit + '_abi';

  // The call header and the matching service header share the same
  // namespace and both need STATUS_OK / STATUS_ERROR. Wrapping the
  // constants in an include guard keyed by the namespace name lets a
  // single translation unit include both headers without a
  // redefinition error. Different units produce different namespaces
  // and therefore different guards, so they remain independent.
  ProtocolGuard := 'LINGOFUSE_ABI_WIRE_PROTOCOL_' + NsName + '_DEFINED';

  Log(PFormat('Generating C++ ABI call header for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty header.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    // -------------------------------------------------------------------------
    // 1. Header
    // -------------------------------------------------------------------------
    Lines.Add('#pragma once');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by cpp_abi_call_generator_tool.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (both directions):');
    Lines.Add('//   request  = [field1][field2]...[fieldN]');
    Lines.Add('//   response = [status:uint8_t][payload]');
    Lines.Add('//     status = 0x00 -> success; payload is the serialised result.');
    Lines.Add('//     status = 0xFF -> error; payload is a UTF-8 string message.');
    Lines.Add('//');
    Lines.Add('// This is the call-side declaration header. The matching');
    Lines.Add('// definition lives in the companion .cpp file produced by the same');
    Lines.Add('// generator.');
    Lines.Add('//');
    Lines.Add('// Neither artefact calls LF_PrepareClient / LF_PrepareDone /');
    Lines.Add('// LF_Shutdown. The host program is responsible for wiring up');
    Lines.Add('// LingoFuse before calling any function in this header.');
    Lines.Add('//');
    Lines.Add('// This header may be included in the same translation unit as the');
    Lines.Add('// matching service header (<unit>_abi_service.hpp). The shared');
    Lines.Add('// protocol constants are guarded so that no redefinition occurs.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <optional>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 2. Remote call target configuration (extern declarations)
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Remote call target configuration');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// LingoFuse application name of the ABI service. Must match');
    Lines.Add('// DEFAULT_APP_NAME on the service side.');
    Lines.Add('extern std::string ABI_TargetApp;');
    Lines.Add('');
    Lines.Add('// Per-call timeout in milliseconds.');
    Lines.Add('extern std::uint64_t ABI_Timeout;');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 3. Wire protocol constants (guarded)
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Wire protocol constants');
    Lines.Add('//');
    Lines.Add('// These constants are also emitted by the matching service header.');
    Lines.Add('// An include guard keyed by the namespace name ensures that a');
    Lines.Add('// translation unit which includes both headers sees exactly one');
    Lines.Add('// definition.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#ifndef ' + ProtocolGuard);
    Lines.Add('#define ' + ProtocolGuard);
    Lines.Add('constexpr std::uint8_t STATUS_OK    = 0x00;');
    Lines.Add('constexpr std::uint8_t STATUS_ERROR = 0xFF;');
    Lines.Add('#endif // ' + ProtocolGuard);
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 4. Exception type
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Exception type');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('class EABI_RemoteError : public std::runtime_error {');
    Lines.Add('public:');
    Lines.Add('    explicit EABI_RemoteError(const std::string& msg)');
    Lines.Add('        : std::runtime_error(msg) {}');
    Lines.Add('};');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 5. Typed remote call function declarations
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Typed remote call functions (definitions in the companion .cpp file).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');

    UsedApiNames.Clear;
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

      EmitFunctionDecl(Lines, ApiName, f.IsFunction, f.Params, f.ReturnType);
    end;

    Lines.Add('');
    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call header.', [Lines.Count]));
  finally
    UsedApiNames.Free;
    // Lines is returned to the caller; not freed here.
  end;
end;

// -----------------------------------------------------------------------------
// GenerateABICallCppCode  (unchanged from the original)
// -----------------------------------------------------------------------------

function GenerateABICallCppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName, NsName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  f: TFunctionStructure;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallCppCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallCppCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetAppName := NormalizedUnit + '_abi';
  NsName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C++ ABI call implementation for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty implementation.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by cpp_abi_call_generator_tool.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (both directions):');
    Lines.Add('//   request  = [field1][field2]...[fieldN]');
    Lines.Add('//   response = [status:uint8_t][payload]');
    Lines.Add('//     status = 0x00 -> success; payload is the serialised result.');
    Lines.Add('//     status = 0xFF -> error; payload is a UTF-8 string message.');
    Lines.Add('//');
    Lines.Add('// This is the call-side implementation file. Include the companion');
    Lines.Add('// header to see the declarations and the wire protocol description.');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#include "' + NormalizedUnit + '_abi_call.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <optional>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');

    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Remote call target configuration');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('std::string ABI_TargetApp = ' + CppStrLit(TargetAppName) + ';');
    Lines.Add('std::uint64_t ABI_Timeout = 5000;');
    Lines.Add('');

    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Typed remote call functions');
    Lines.Add('// ---------------------------------------------------------------------------');

    UsedApiNames.Clear;
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

      EmitFunctionDef(Lines, ApiName, f.IsFunction, f.Params, f.ReturnType);
    end;

    Lines.Add('');
    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the call implementation.', [Lines.Count]));
  finally
    UsedApiNames.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Comment description extraction
//
// Operates on UTF-16 TP_String directly. Strips comment markers, Doxygen
// tag lines, and continuation '*' markers. Only the first non-empty,
// non-Doxygen line is returned, capped at 200 characters.
// -----------------------------------------------------------------------------

function StripCommentMarkers(const Line: TP_String): TP_String;
var
  T: TP_String;
begin
  T := Line.TrimChar(#32#9);

  // Strip "//" prefix.
  if (T.Len >= 2) and (T[1] = '/') and (T[2] = '/') then
    T := T.GetString(3, T.Len + 1).TrimChar(#32#9);

  // Strip leading "{" or "(*".
  if T.Len > 0 then
  begin
    if T[1] = '{' then
      T := T.GetString(2, T.Len + 1).TrimChar(#32#9)
    else if (T.Len >= 2) and (T[1] = '(') and (T[2] = '*') then
      T := T.GetString(3, T.Len + 1).TrimChar(#32#9);
  end;

  // Strip trailing "}" or "*)".
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

// =============================================================================
// SECTION 3 - README generator
// =============================================================================
//
// This section is self-contained. It depends only on the helpers already
// present in this unit (MakeApiName, MakeSafeCppParamName, CppStrLit,
// ABI_Type_To_Cpp_Decl, ABI_Type_To_Cpp_Param_Decl, IsStringABIType,
// CollectSupportedFunctions) plus StripCommentMarkers and
// GetFullDescription, which are defined earlier in this unit.
//
// The README is organised into twelve sections:
//
//   §1  Overview
//   §2  Application scope
//   §3  Compatibility (C++ standard, compilers, platforms)
//   §4  Wire protocol
//   §5  Runtime architecture (call-side view)
//   §6  Type mapping
//   §7  Deployment
//   §8  Testing
//   §9  API reference
//   §10 Troubleshooting
//   §11 Self-assessment checklist
//   §12 Reference resources
//
// The document is written so that both human readers and AI assistants
// can learn the C++ call-side module's usage model from the README alone.
// =============================================================================

// Returns the "wire size" column text for the ABI type table.
function CppCallReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '1 byte'
  else if ABI_Type.Same('word') or ABI_Type.Same('smallint') then
    Result := '2 bytes'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or ABI_Type.Same('longword') or ABI_Type.Same('integer') or
    ABI_Type.Same('longint') or ABI_Type.Same('single') then
    Result := '4 bytes'
  else if ABI_Type.Same('int64') or ABI_Type.Same('uint64') or ABI_Type.Same('double') or ABI_Type.Same('extended') or ABI_Type.Same('real') then
    Result := '8 bytes'
  else if ABI_Type.Same('string') or ABI_Type.Same('ansistring') or ABI_Type.Same('unicodestring') or ABI_Type.Same('tpascalstring') or
    ABI_Type.Same('tupascalstring') or ABI_Type.Same('tp_string') or ABI_Type.Same('pchar') or ABI_Type.Same('pansichar') or ABI_Type.Same('pwidechar') then
    Result := 'variable + NUL'
  else
    Result := 'unknown';
end;

// Sanitise a description for use inside a Markdown table cell.
function CppCallReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// Sanitise a description for use as standalone paragraph text.
function CppCallReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

// Build the README for a given model.
function GenerateABICallCppReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName, NsName, HppName, CppName: TP_String;

// ---------------------------------------------------------------------------
// §1. Header
// ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - C++ ABI Call Client');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `cpp_abi_call_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Call-side header**  : `' + HppName + '`');
    L.Add('> **Call-side impl**    : `' + CppName + '`');
    L.Add('> **Namespace**         : `' + NsName + '`');
    L.Add('> **Target App name**   : `' + TargetAppName + '`');
    L.Add('> **Exported functions**: ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> compile, deploy, or call this module without reading the source.');
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
    L.Add('This document describes the **C++ call-side client module** that');
    L.Add('was generated from the Pascal unit `' + UnitName + '`. The module is');
    L.Add('a strongly-typed wrapper around LingoFuse that talks to a matching');
    L.Add('ABI service over a compact binary wire protocol.');
    L.Add('');
    L.Add('### 1.1 What is a call-side client?');
    L.Add('');
    L.Add('A C++ call-side client is a two-file pair (`.hpp` + `.cpp`) that:');
    L.Add('');
    L.Add('- exports one **free function** per API of the matching service;');
    L.Add('- each free function mirrors the signature of the original routine;');
    L.Add('- serialises its arguments with `lingofuse::DataHandle::write`,');
    L.Add('  sends them through `lingofuse::tryCall`, and decodes the');
    L.Add('  response with `DataHandle::read`;');
    L.Add('- throws `EABI_RemoteError` on timeout, empty response, or when');
    L.Add('  the service returns a `STATUS_ERROR` byte.');
    L.Add('');
    L.Add('The module is a **client**: it never registers APIs of its own,');
    L.Add('never calls `LF_PrepareService`, and never touches the LingoFuse');
    L.Add('main-thread setup beyond what the host program provides.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Target resolution | Direct by App name (no discovery) |');
    L.Add('| Service dependency | Must be generated from the same model |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Implementation | C++17, exceptions on the call boundary only |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Compile** the call-side pair (`.hpp` + `.cpp`) into your');
    L.Add('   client program. See §7.');
    L.Add('2. **Start** the matching service process. See §5.');
    L.Add('3. **Call** the exported free functions. See §8 and §9.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + HppName + '` | Call-side declaration header. |');
    L.Add('| `' + CppName + '` | Call-side implementation file. |');
    L.Add('| `' + UnitName + '_abi_call_cpp.md` | This README. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use this call-side module');
    L.Add('');
    L.Add('Use this module when:');
    L.Add('');
    L.Add('- You need to call a **specific, known ABI service**.');
    L.Add('- The service signature is **stable** and known at build time.');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- A C++ client calling a Pascal or Python ABI service.');
    L.Add('- A native front-end consuming a C++ compute engine.');
    L.Add('- A high-frequency consumer of a typed event producer.');
    L.Add('- A test harness exercising a native ABI service.');
    L.Add('');
    L.Add('### 2.2 When NOT to use this call-side module');
    L.Add('');
    L.Add('- You need to discover the API surface at runtime.');
    L.Add('- The target service signature changes without a rebuild.');
    L.Add('- Parameters include complex types (STL containers, custom structs).');
    L.Add('- You need a client that can target **arbitrary** third-party');
    L.Add('  services without prior generation.');
    L.Add('- You need to talk to a JSON-based service.');
    L.Add('');
    L.Add('### 2.3 Comparison with other RPC clients');
    L.Add('');
    L.Add('| Approach | Typed | Binary | Self-describing | Paired codegen |');
    L.Add('|----------|:-----:|:------:|:---------------:|:--------------:|');
    L.Add('| This ABI client | yes | yes | no | yes (required) |');
    L.Add('| gRPC client | yes | yes | yes (proto) | yes (generated) |');
    L.Add('| REST + JSON client | no | no | yes | no |');
    L.Add('| Raw TCP client | no | yes | no | yes |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §4. Compatibility
  // ---------------------------------------------------------------------------
  procedure EmitCompatibility;
  begin
    L.Add('## 3. Compatibility');
    L.Add('');
    L.Add('### 3.1 C++ standard');
    L.Add('');
    L.Add('The generated code targets **C++17** and uses only the standard');
    L.Add('library plus three headers (`LingoFuse.hpp`, `lf_io.hpp`, and the');
    L.Add('generated `.hpp`).');
    L.Add('');
    L.Add('### 3.2 Compiler support');
    L.Add('');
    L.Add('| Compiler | Minimum version | Notes |');
    L.Add('|----------|-----------------|-------|');
    L.Add('| MSVC | Visual Studio 2019 (16.8) | `/std:c++17` required. |');
    L.Add('| g++ | 7.0 | `-std=c++17` required. |');
    L.Add('| clang++ | 5.0 | `-std=c++17` required. |');
    L.Add('');
    L.Add('### 3.3 Platform support');
    L.Add('');
    L.Add('| Platform | Architecture | Status |');
    L.Add('|----------|-------------|--------|');
    L.Add('| Windows | x86_64 | Primary target |');
    L.Add('| Linux | x86_64 | Supported |');
    L.Add('| Linux | aarch64 | Supported |');
    L.Add('| macOS | x86_64 | Supported |');
    L.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    L.Add('');
    L.Add('**Byte order note**: the ABI wire format is little-endian. Every');
    L.Add('platform listed above is little-endian, so the generated code never');
    L.Add('performs byte swapping. Big-endian platforms are **not supported**.');
    L.Add('');
    L.Add('### 3.4 Runtime dependencies');
    L.Add('');
    L.Add('| Dependency | Where to get it |');
    L.Add('|------------|----------------|');
    L.Add('| `LingoFuse.hpp` | LingoFuse runtime distribution |');
    L.Add('| `lf_io.hpp` | LingoFuse runtime distribution |');
    L.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    L.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | ZNetV2 binary distribution |');
    L.Add('');
    L.Add('### 3.5 Character encoding');
    L.Add('');
    L.Add('- **Source files**: UTF-8, no BOM required.');
    L.Add('- **MSVC users**: add `/utf-8` to the compiler command line, or');
    L.Add('  the non-ASCII characters in the API description strings will be');
    L.Add('  encoded with the system codepage and may not match what the');
    L.Add('  LingoFuse registry expects (UTF-8).');
    L.Add('- **String payloads**: UTF-8 followed by a single `\\0` terminator.');
    L.Add('');
    L.Add('### 3.6 Threading model');
    L.Add('');
    L.Add('Every exported free function is thread-safe with respect to');
    L.Add('LingoFuse. Different threads may call different free functions in');
    L.Add('parallel. `lingofuse::tryCall` performs its own internal');
    L.Add('synchronisation and blocks the calling thread until the response');
    L.Add('arrives or the timeout expires.');
    L.Add('');
    L.Add('**Do not call an exported free function from inside a LingoFuse');
    L.Add('callback.** Doing so deadlocks the calling worker thread. If you');
    L.Add('need to call a remote service from inside a callback, offload the');
    L.Add('call to a separate `std::thread`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The call-side module speaks the same wire format as the matching');
    L.Add('service.');
    L.Add('');
    L.Add('### 4.1 Request');
    L.Add('');
    L.Add('```');
    L.Add('request = [field1][field2]...[fieldN]');
    L.Add('```');
    L.Add('');
    L.Add('Fields are serialised in the **exact order** in which they appear');
    L.Add('in the original Pascal declaration. Each exported free function');
    L.Add('performs this serialisation automatically.');
    L.Add('');
    L.Add('### 4.2 Response');
    L.Add('');
    L.Add('```');
    L.Add('response = [status:uint8_t][payload]');
    L.Add('```');
    L.Add('');
    L.Add('The first byte is a status code:');
    L.Add('');
    L.Add('| Status | Value | Meaning | Payload |');
    L.Add('|--------|-------|---------|---------|');
    L.Add('| `STATUS_OK` | `0x00` | Success | Serialised result (functions) or empty (procedures). |');
    L.Add('| `STATUS_ERROR` | `0xFF` | Error | UTF-8 message, terminated by `\\0`. |');
    L.Add('');
    L.Add('The exported free functions decode this automatically:');
    L.Add('');
    L.Add('- `STATUS_OK` -> returns the deserialised result (or returns');
    L.Add('  normally for procedures).');
    L.Add('- `STATUS_ERROR` -> throws `EABI_RemoteError` with the decoded');
    L.Add('  message.');
    L.Add('');
    L.Add('### 4.3 Encoding rules');
    L.Add('');
    L.Add('| Rule | Value |');
    L.Add('|------|-------|');
    L.Add('| Byte order | Little-endian |');
    L.Add('| Integer | Fixed-width, little-endian |');
    L.Add('| Float | IEEE 754, little-endian |');
    L.Add('| String | UTF-8 bytes terminated by a single `\\0` |');
    L.Add('| Boolean | Not supported |');
    L.Add('| STL container | Not supported |');
    L.Add('');
    L.Add('### 4.4 Call sequence');
    L.Add('');
    L.Add('```mermaid');
    L.Add('sequenceDiagram');
    L.Add('    participant C as Call-side module');
    L.Add('    participant S as Service');
    L.Add('    C->>C: DataHandle::write(a), ::write(b)');
    L.Add('    C->>S: lingofuse::tryCall(payload)');
    L.Add('    S-->>C: [status][payload]');
    L.Add('    C->>C: read status byte');
    L.Add('    alt status == STATUS_OK');
    L.Add('        C->>C: DataHandle::read -> result');
    L.Add('    else status == STATUS_ERROR');
    L.Add('        C->>C: DataHandle::read -> error');
    L.Add('        C->>C: throw EABI_RemoteError');
    L.Add('    end');
    L.Add('```');
    L.Add('');
    L.Add('### 4.5 Error response example');
    L.Add('');
    L.Add('Bytes on the wire:');
    L.Add('');
    L.Add('```');
    L.Add('FF                                  <- STATUS_ERROR');
    L.Add('72 65 61 64 20 66 61 69 6C 65 64    <- "read failed" (UTF-8)');
    L.Add('00                                  <- NUL terminator');
    L.Add('```');
    L.Add('');
    L.Add('The call-side module throws `EABI_RemoteError` with the decoded');
    L.Add('message. Callers should wrap their calls in a `try/catch` block.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §6. Runtime architecture (call-side view)
  // ---------------------------------------------------------------------------
  procedure EmitRuntimeArchitecture;
  begin
    L.Add('## 5. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph Client["Client process (this module)"]');
    L.Add('        C_PREP["LF_ResetPrepare()"]');
    L.Add('        C_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, nullptr)"]');
    L.Add('        C_RUN["LF_PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;ns&gt;::&lt;ApiName&gt;(args)"]');
    L.Add('        C_CATCH["try / catch EABI_RemoteError"]');
    L.Add('        C_OFF["LF_ExitMainThread() + LF_Shutdown()"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Service["Service process (external)"]');
    L.Add('        S_RUN["ABI service running<br/>App = &lt;unit&gt;_abi"]');
    L.Add('    end');
    L.Add('');
    L.Add('    C_PREP --> C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "lingofuse::tryCall over IPC" .-> S_RUN');
    L.Add('    S_RUN -. "response" .-> C_CATCH');
    L.Add('    C_CATCH --> C_OFF');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (client)');
    L.Add('');
    L.Add('1. `LF_ResetPrepare();`');
    L.Add('2. `LF_PrepareClient("ipc:<unit>_abi", nullptr);`');
    L.Add('   (pass `nullptr` because the client does not expose any APIs)');
    L.Add('3. `if (LF_PrepareDone() != 1) { /* handle failure */ }`');
    L.Add('');
    L.Add('The service process must be running before step 3 completes.');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The caller invokes an exported free function, e.g.');
    L.Add('   `' + NsName + '::<ApiName>(a, b)`.');
    L.Add('2. The free function creates a `lingofuse::DataHandle` with the');
    L.Add('   API name.');
    L.Add('3. It writes every argument with `DataHandle::write`.');
    L.Add('4. It calls `lingofuse::tryCall(ABI_TargetApp, _data, ABI_Timeout)`;');
    L.Add('   the returned `std::optional<DataHandle>` is checked for');
    L.Add('   validity.');
    L.Add('5. LingoFuse routes the payload to the service and waits for the');
    L.Add('   response (blocking).');
    L.Add('6. On a null response: throws `EABI_RemoteError`.');
    L.Add('7. On `STATUS_ERROR`: reads the UTF-8 message and throws');
    L.Add('   `EABI_RemoteError`.');
    L.Add('8. On `STATUS_OK`: reads the result and returns it.');
    L.Add('');
    L.Add('### 5.3 Timeout');
    L.Add('');
    L.Add('The timeout is controlled by the namespace-level variable');
    L.Add('`ABI_Timeout` (default `5000` ms). Change it before making calls:');
    L.Add('');
    L.Add('```cpp');
    L.Add(NsName + '::ABI_Timeout = 30000;  // 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('A value of `0` disables the timeout, which means the call blocks');
    L.Add('indefinitely if the service never responds.');
    L.Add('');
    L.Add('### 5.4 Target application name');
    L.Add('');
    L.Add('The target service is identified by the namespace-level variable');
    L.Add('`ABI_TargetApp` (default `' + TargetAppName + '`). Change it to');
    L.Add('point at a differently-named service:');
    L.Add('');
    L.Add('```cpp');
    L.Add(NsName + '::ABI_TargetApp = "my_other_service_abi";');
    L.Add('```');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §7. Type mapping
  // ---------------------------------------------------------------------------
  procedure EmitTypeMapping;
  begin
    L.Add('## 6. Type Mapping');
    L.Add('');
    L.Add('### 6.1 Supported types');
    L.Add('');
    L.Add('The call-side module accepts the same type set as the matching');
    L.Add('service. Every exported free function''s parameters and return');
    L.Add('type are drawn from this table.');
    L.Add('');
    L.Add('| ABI type | C++ type | Wire size |');
    L.Add('|----------|----------|-----------|');
    L.Add('| `integer` | `std::int32_t` | 4 bytes |');
    L.Add('| `longint` | `std::int32_t` | 4 bytes |');
    L.Add('| `int64` | `std::int64_t` | 8 bytes |');
    L.Add('| `cardinal` | `std::uint32_t` | 4 bytes |');
    L.Add('| `dword` | `std::uint32_t` | 4 bytes |');
    L.Add('| `longword` | `std::uint32_t` | 4 bytes |');
    L.Add('| `word` | `std::uint16_t` | 2 bytes |');
    L.Add('| `smallint` | `std::int16_t` | 2 bytes |');
    L.Add('| `byte` | `std::uint8_t` | 1 byte |');
    L.Add('| `uint64` | `std::uint64_t` | 8 bytes |');
    L.Add('| `double` | `double` | 8 bytes |');
    L.Add('| `single` | `float` | 4 bytes |');
    L.Add('| `extended` | `double` | 8 bytes |');
    L.Add('| `real` | `double` | 8 bytes |');
    L.Add('| `string` | `std::string` | variable + NUL |');
    L.Add('| `ansistring` | `std::string` | variable + NUL |');
    L.Add('| `unicodestring` | `std::string` | variable + NUL |');
    L.Add('| `tpascalstring` | `std::string` | variable + NUL |');
    L.Add('| `tupascalstring` | `std::string` | variable + NUL |');
    L.Add('| `tp_string` | `std::string` | variable + NUL |');
    L.Add('| `pchar` | `std::string` | variable + NUL |');
    L.Add('| `pansichar` | `std::string` | variable + NUL |');
    L.Add('| `pwidechar` | `std::string` | variable + NUL |');
    L.Add('');
    L.Add('Parameter passing convention:');
    L.Add('');
    L.Add('- scalar types -> passed by value;');
    L.Add('- string types -> passed as `const std::string&`.');
    L.Add('');
    L.Add('### 6.2 Unsupported types');
    L.Add('');
    L.Add('Anything not in §6.1 cannot appear in an exported function''s');
    L.Add('signature. If the original routine used a complex type, the');
    L.Add('matching free function is **not generated at all**.');
    L.Add('');
    L.Add('Common examples of unsupported types:');
    L.Add('');
    L.Add('- `bool`');
    L.Add('- `std::vector`, `std::map`, `std::unordered_map`, `std::array`');
    L.Add('- Custom classes and structs');
    L.Add('- `std::optional`, `std::variant`, `std::any`');
    L.Add('- `std::chrono::*`');
    L.Add('- Pointers, function pointers');
    L.Add('');
    L.Add('**Workaround**: serialise the complex value into a `std::string`');
    L.Add('first (JSON or a custom format) on the caller side, then call a');
    L.Add('string-typed overload of the service. On the service side,');
    L.Add('deserialise the string back into the rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The wire format is little-endian for all integers and floats. All');
    L.Add('supported platforms are little-endian, so the generated code never');
    L.Add('performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('The exported free functions use `lingofuse::io::write_string` and');
    L.Add('`lingofuse::io::read_string` for string parameters and return');
    L.Add('values. `write_string` always appends a single `\\0` byte after');
    L.Add('the UTF-8 payload. `read_string` scans forward until it finds that');
    L.Add('byte.');
    L.Add('');
    L.Add('**Recommendation**: do not hand-roll string encoding. Always rely');
    L.Add('on the generated free functions.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §8. Deployment
  // ---------------------------------------------------------------------------
  procedure EmitDeployment;
  begin
    L.Add('## 7. Deployment');
    L.Add('');
    L.Add('### 7.1 Directory layout');
    L.Add('');
    L.Add('```');
    L.Add('my_abi_client/');
    L.Add('  ' + HppName + '         <- generated (declaration)');
    L.Add('  ' + CppName + '         <- generated (implementation)');
    L.Add('  main.cpp                                <- your client entry point');
    L.Add('  LingoFuse.hpp                           <- from the LingoFuse runtime');
    L.Add('  lf_io.hpp                               <- from the LingoFuse runtime');
    L.Add('  LingoFuse64.dll                         <- Windows');
    L.Add('  liblingofuse.so                         <- Linux');
    L.Add('  liblingofuse.dylib                      <- macOS');
    L.Add('```');
    L.Add('');
    L.Add('The matching service process must be running independently and must');
    L.Add('expose the App name `' + TargetAppName + '`.');
    L.Add('');
    L.Add('### 7.2 Build commands');
    L.Add('');
    L.Add('**Linux / macOS (g++):**');
    L.Add('');
    L.Add('```bash');
    L.Add('g++ -std=c++17 -O2 -I. \\');
    L.Add('    main.cpp ' + CppName + ' \\');
    L.Add('    -L. -lLingoFuse -Wl,-rpath,. \\');
    L.Add('    -o ' + NormalizedUnit + '_client');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (MSVC):**');
    L.Add('');
    L.Add('```bat');
    L.Add('cl /std:c++17 /EHsc /utf-8 /I. main.cpp ' + CppName + ' ^');
    L.Add('   /link /LIBPATH:. LingoFuse.lib /OUT:' + NormalizedUnit + '_client.exe');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (MinGW-w64):**');
    L.Add('');
    L.Add('```bat');
    L.Add('g++ -std=c++17 -O2 -I. main.cpp ' + CppName + ' ^');
    L.Add('    -L. -lLingoFuse -o ' + NormalizedUnit + '_client.exe');
    L.Add('```');
    L.Add('');
    L.Add('### 7.3 Setting the runtime library path');
    L.Add('');
    L.Add('**Linux / macOS:**');
    L.Add('');
    L.Add('```bash');
    L.Add('LD_LIBRARY_PATH=. ./' + NormalizedUnit + '_client    # Linux');
    L.Add('DYLD_LIBRARY_PATH=. ./' + NormalizedUnit + '_client  # macOS');
    L.Add('```');
    L.Add('');
    L.Add('**Windows:** place `LingoFuse64.dll` and `z_ipc_*.dll` next to the');
    L.Add('executable, or add their directory to `PATH`.');
    L.Add('');
    L.Add('### 7.4 Startup order');
    L.Add('');
    L.Add('The service must be running before the client calls');
    L.Add('`LF_PrepareDone`. If the client starts first, retry or poll:');
    L.Add('');
    L.Add('```cpp');
    L.Add('#include <chrono>');
    L.Add('#include <thread>');
    L.Add('');
    L.Add('while (LF_CheckApp("' + TargetAppName + '") == 0) {');
    L.Add('    std::this_thread::sleep_for(std::chrono::milliseconds(100));');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('### 7.5 Runtime files');
    L.Add('');
    L.Add('At runtime the following files must be reachable from the process:');
    L.Add('');
    L.Add('| File | Where to place it |');
    L.Add('|------|-------------------|');
    L.Add('| `LingoFuse64.dll` / `liblingofuse.so` | Same directory as the executable, or on `PATH` / `LD_LIBRARY_PATH`. |');
    L.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | Same as above. |');
    L.Add('');
    L.Add('### 7.6 Shutdown');
    L.Add('');
    L.Add('The recommended shutdown sequence on the client side is:');
    L.Add('');
    L.Add('1. `LF_ExitMainThread();`');
    L.Add('2. `LF_Shutdown();`');
    L.Add('');
    L.Add('The client does not own an App handle, so there is nothing to');
    L.Add('release with `LF_FreeApp`.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Testing
  // ---------------------------------------------------------------------------
  procedure EmitTesting;
  begin
    L.Add('## 8. Testing');
    L.Add('');
    L.Add('The program below is a complete, copy-paste-ready test client.');
    L.Add('Save it as `main.cpp` next to the generated pair and compile as');
    L.Add('described in §7.2.');
    L.Add('');
    L.Add('### 8.1 Client program (`main.cpp`)');
    L.Add('');
    L.Add('```cpp');
    L.Add('// main.cpp - test entry point for the generated C++ ABI client.');
    L.Add('//');
    L.Add('// Build:');
    L.Add('//   g++ -std=c++17 -O2 -I. main.cpp ' + CppName + ' \\');
    L.Add('//       -L. -lLingoFuse -Wl,-rpath,. \\');
    L.Add('//       -o ' + NormalizedUnit + '_client');
    L.Add('');
    L.Add('#include "' + HppName + '"');
    L.Add('');
    L.Add('#include "LingoFuse.hpp"');
    L.Add('');
    L.Add('#include <cstdio>');
    L.Add('#include <cstdlib>');
    L.Add('#include <string>');
    L.Add('');
    L.Add('int main() {');
    L.Add('    std::printf("=== ' + UnitName + ' ABI client ===\n");');
    L.Add('');
    L.Add('    LF_ResetPrepare();');
    L.Add('    LF_PrepareClient("ipc:' + TargetAppName + '", nullptr);');
    L.Add('');
    L.Add('    if (LF_PrepareDone() != 1) {');
    L.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareDone failed\n");');
    L.Add('        return 1;');
    L.Add('    }');
    L.Add('');
    L.Add('    try {');
    L.Add('        // Replace with actual calls to the generated functions.');
    L.Add('        // Example:');
    L.Add('        //     auto r = ' + NsName + '::<ApiName>(3, 4);');
    L.Add('        //     std::printf("result = %s\n", std::to_string(r).c_str());');
    L.Add('    } catch (const ' + NsName + '::EABI_RemoteError& e) {');
    L.Add('        std::fprintf(stderr, "[ERROR] %s\n", e.what());');
    L.Add('    }');
    L.Add('');
    L.Add('    LF_ExitMainThread();');
    L.Add('    LF_Shutdown();');
    L.Add('    return 0;');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Running the test');
    L.Add('');
    L.Add('Make sure the matching service process is running first. Then:');
    L.Add('');
    L.Add('```bash');
    L.Add('./' + NormalizedUnit + '_client');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path:');
    L.Add('');
    L.Add('1. Stop the service process.');
    L.Add('2. Run the client again.');
    L.Add('3. The free function throws `EABI_RemoteError` with a timeout or');
    L.Add('   "target not found" message.');
    L.Add('');
    L.Add('### 8.4 Unit-level testing of the serialisation helpers');
    L.Add('');
    L.Add('To test the serialisation helpers without a running service, use');
    L.Add('`lingofuse::DataHandle` directly:');
    L.Add('');
    L.Add('```cpp');
    L.Add('#include "LingoFuse.hpp"');
    L.Add('#include "lf_io.hpp"');
    L.Add('');
    L.Add('lingofuse::DataHandle hnd("<ApiName>");');
    L.Add('hnd.write(static_cast<std::int32_t>(42));');
    L.Add('hnd.write(std::string("hello"));');
    L.Add('hnd.seek(0);');
    L.Add('std::int32_t i = 0;');
    L.Add('hnd.read(i);');
    L.Add('std::string s;');
    L.Add('hnd.read(s);');
    L.Add('// i == 42, s == "hello"');
    L.Add('```');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §10. API reference
  // ---------------------------------------------------------------------------
  procedure EmitApiReference;
  var
    ii, jj: integer;
    Func: TFunctionStructure;
    FuncDesc: TP_String;
    ShortDesc: TP_String;
    ApiNm: TP_String;
    RowStr: TP_String;
    ParamDecl: TP_String;
    RetDecl: TP_String;
    CallExpr: TP_String;
    PName, PTyp: TP_String;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this call-side module exports no functions.**');
      L.Add('>');
      L.Add('> Possible reasons:');
      L.Add('>');
      L.Add('> 1. The source unit has no top-level routines.');
      L.Add('> 2. Every routine failed the ABI type check.');
      L.Add('>');
      L.Add('> Supported types are listed in §6.1.');
      L.Add('');
      Exit;
    end;

    L.Add('Total exported functions: **' + umlIntToStr(Length(SupportedFuncs)).Text + '**.');
    L.Add('');
    L.Add('Every function is a **free function** declared inside the');
    L.Add('`' + NsName + '` namespace. Include the header and call them:');
    L.Add('');
    L.Add('```cpp');
    L.Add('#include "' + HppName + '"');
    L.Add('');
    L.Add('auto r = ' + NsName + '::<ApiName>(...);');
    L.Add('```');
    L.Add('');

    // ---- Summary table ---------------------------------------------------
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | Function | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');

    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      ShortDesc := CppCallReadmeTableCell(GetFullDescription(Func.Comment));
      if ShortDesc.Len > 60 then
        ShortDesc := ShortDesc.GetString(1, 61) + '...';

      if Func.IsFunction then
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | function | ' + umlIntToStr(Length(Func.Params)).Text +
          ' | `' + ABI_Type_To_Cpp_Decl(Func.ReturnType) + '` | ' + ShortDesc + ' |'
      else
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | procedure | ' + umlIntToStr(Length(Func.Params)).Text + ' | - | ' + ShortDesc + ' |';
      L.Add(RowStr);
    end;

    L.Add('');

    // ---- Per-API details -------------------------------------------------
    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      FuncDesc := CppCallReadmeParagraph(GetFullDescription(Func.Comment));

      // Reconstruct the exported signature.
      ParamDecl := '';
      for jj := 0 to High(Func.Params) do
      begin
        PName := MakeSafeCppParamName(Func.Params[jj].Name, jj);
        PTyp := ABI_Type_To_Cpp_Param_Decl(Func.Params[jj].PascalType);
        if jj > 0 then
          ParamDecl := ParamDecl + ', ';
        ParamDecl := ParamDecl + PTyp + ' ' + PName;
      end;

      // Build the call expression for the example.
      CallExpr := ApiNm + '(';
      for jj := 0 to High(Func.Params) do
      begin
        if jj > 0 then
          CallExpr := CallExpr + ', ';
        if IsStringABIType(Func.Params[jj].PascalType) then
          CallExpr := CallExpr + '"hello"'
        else if Func.Params[jj].PascalType.Same('double') or Func.Params[jj].PascalType.Same('single') or
          Func.Params[jj].PascalType.Same('extended') or Func.Params[jj].PascalType.Same('real') then
          CallExpr := CallExpr + '0.0'
        else
          CallExpr := CallExpr + '0';
      end;
      CallExpr := CallExpr + ')';

      L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
      L.Add('');

      if Func.IsFunction then
      begin
        RetDecl := ABI_Type_To_Cpp_Decl(Func.ReturnType);
        L.Add('- **Declaration**: `' + RetDecl + ' ' + ApiNm + '(' + ParamDecl + ');`');
        L.Add('- **Kind**: function; returns `' + RetDecl + '`');
      end
      else
      begin
        L.Add('- **Declaration**: `void ' + ApiNm + '(' + ParamDecl + ');`');
        L.Add('- **Kind**: procedure');
      end;
      L.Add('- **Throws**: `EABI_RemoteError` on timeout, empty response, or `STATUS_ERROR`');
      L.Add('');

      if FuncDesc.Len > 0 then
      begin
        L.Add('#### Description');
        L.Add('');
        L.Add(FuncDesc);
        L.Add('');
      end;

      // Parameters table
      if Length(Func.Params) > 0 then
      begin
        L.Add('#### Parameters');
        L.Add('');
        L.Add('| # | Name | C++ type | ABI type | Wire size |');
        L.Add('|---|------|----------|----------|-----------|');
        for jj := 0 to High(Func.Params) do
        begin
          PName := MakeSafeCppParamName(Func.Params[jj].Name, jj);
          PTyp := ABI_Type_To_Cpp_Param_Decl(Func.Params[jj].PascalType);
          RowStr := '| ' + umlIntToStr(jj + 1).Text + ' | `' + PName + '`' + ' | `' + PTyp + '`' + ' | `' +
            Func.Params[jj].PascalType + '`' + ' | ' + CppCallReadmeWireSizeText(Func.Params[jj].PascalType) + ' |';
          L.Add(RowStr);
        end;
        L.Add('');
      end;

      // Call example
      L.Add('#### Call example');
      L.Add('');
      L.Add('```cpp');
      L.Add('#include "' + HppName + '"');
      L.Add('');
      L.Add('try {');
      if Func.IsFunction then
        L.Add('    auto result = ' + NsName + '::' + CallExpr + ';')
      else
        L.Add('    ' + NsName + '::' + CallExpr + ';');
      L.Add('} catch (const ' + NsName + '::EABI_RemoteError& e) {');
      L.Add('    // Handle the failure.');
      L.Add('    std::fprintf(stderr, "Call failed: %s\n", e.what());');
      L.Add('}');
      L.Add('```');
      L.Add('');

      L.Add('---');
      L.Add('');
    end;
  end;

  // ---------------------------------------------------------------------------
  // §11. Troubleshooting
  // ---------------------------------------------------------------------------
  procedure EmitTroubleshooting;
  begin
    L.Add('## 10. Troubleshooting');
    L.Add('');
    L.Add('### 10.1 Symptom, cause, fix');
    L.Add('');
    L.Add('| Symptom | Likely cause | Fix |');
    L.Add('|---------|--------------|-----|');
    L.Add('| `fatal error: LingoFuse.hpp: No such file` | Header not on the include path | Add `-I.` (or the actual directory) to the compiler command. |');
    L.Add('| `fatal error: lf_io.hpp: No such file` | Header not on the include path | Same as above. |');
    L.Add('| `undefined reference to LF_*` | LingoFuse library not linked | Add `-lLingoFuse` and the correct `-L<path>`. |');
    L.Add('| Runtime `cannot open shared object file` | Library not on the loader path | `export LD_LIBRARY_PATH=.` (Linux) or copy the DLL next to the exe (Windows). |');
    L.Add('| `LF_PrepareDone` returns 0 | Service not running | Start the service before the client, or poll `LF_CheckApp`. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | App name mismatch | Check `ABI_TargetApp` and the service `DEFAULT_APP_NAME`. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | Timeout too short | Increase `ABI_Timeout`. |');
    L.Add('| `EABI_RemoteError: "input truncated"` | Service rejected the request | Verify the client and service were generated from the same model. |');
    L.Add('| `EABI_RemoteError: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| `EABI_RemoteError` on every call | Service App not registered | Verify the service is running and registered. |');
    L.Add('| Deadlock inside a callback | Calling a free function inside a LingoFuse callback | Offload the call to a separate `std::thread`. |');
    L.Add('| Client hangs forever | Timeout set to 0 | Set `ABI_Timeout` to a positive value. |');
    L.Add('| MSVC warns about non-ASCII characters | Missing `/utf-8` | Add `/utf-8` to the compiler command. |');
    L.Add('');
    L.Add('### 10.2 Verifying the service is reachable');
    L.Add('');
    L.Add('Before making a call:');
    L.Add('');
    L.Add('```cpp');
    L.Add('if (LF_CheckMainThread() == 0) {');
    L.Add('    std::fprintf(stderr, "Main thread is not running\n");');
    L.Add('}');
    L.Add('if (LF_CheckApp("' + TargetAppName + '") == 0) {');
    L.Add('    std::fprintf(stderr, "Target service is not registered\n");');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('### 10.3 Inspecting the raw payload');
    L.Add('');
    L.Add('To dump the raw bytes of a `TDataHnd` for debugging:');
    L.Add('');
    L.Add('```cpp');
    L.Add('#include <cstdint>');
    L.Add('#include <cstdio>');
    L.Add('');
    L.Add('const std::int64_t sz = LF_GetSize(res);');
    L.Add('const auto* p = static_cast<const std::uint8_t*>(LF_GetBuffer(res));');
    L.Add('for (std::int64_t i = 0; i < sz; ++i) {');
    L.Add('    std::printf("%02X ", p[i]);');
    L.Add('}');
    L.Add('std::printf("\n");');
    L.Add('```');
    L.Add('');
    L.Add('### 10.4 Adjusting the timeout');
    L.Add('');
    L.Add('Increase `ABI_Timeout` when calling a slow service:');
    L.Add('');
    L.Add('```cpp');
    L.Add(NsName + '::ABI_Timeout = 30000;  // 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('A value of `0` disables the timeout, which means the call blocks');
    L.Add('indefinitely if the service never responds.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §12. Self-assessment checklist
  // ---------------------------------------------------------------------------
  procedure EmitSelfAssessment;
  begin
    L.Add('## 11. Self-Assessment Checklist');
    L.Add('');
    L.Add('After reading this document you should be able to answer the');
    L.Add('following questions without consulting the source code. If any');
    L.Add('answer is unclear, re-read the corresponding section.');
    L.Add('');
    L.Add('| # | Question | Section |');
    L.Add('|---|----------|---------|');
    L.Add('| 1 | What does this call-side module export? | §1 |');
    L.Add('| 2 | When should I use this client instead of a JSON client? | §2 |');
    L.Add('| 3 | Which C++ standard and compilers are supported? | §3 |');
    L.Add('| 4 | What is the wire format of a request and a response? | §4 |');
    L.Add('| 5 | What is the client startup sequence? | §5.1 |');
    L.Add('| 6 | How is the target App name configured? | §5.4 |');
    L.Add('| 7 | How is the timeout configured? | §5.3 |');
    L.Add('| 8 | Which C++ types are accepted? | §6.1 |');
    L.Add('| 9 | How do I compile the client with g++? | §7.2 |');
    L.Add('| 10 | How do I compile the client with MSVC? | §7.2 |');
    L.Add('| 11 | What is the shutdown order on the client side? | §7.6 |');
    L.Add('| 12 | How do I invoke a specific API? | §9 |');
    L.Add('| 13 | How do I handle a failed call? | §4.5, §9 |');
    L.Add('| 14 | What should I do if the client hangs forever? | §10.4 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('C++ call-side module.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §13. Resources
  // ---------------------------------------------------------------------------
  procedure EmitResources;
  begin
    L.Add('## 12. Reference Resources');
    L.Add('');
    L.Add('| Resource | Purpose |');
    L.Add('|----------|---------|');
    L.Add('| LingoFuse runtime distribution | Provides `LingoFuse.hpp`, `lf_io.hpp`, and the shared library |');
    L.Add('| ZNetV2 repository | Provides `z_ipc_*` binaries |');
    L.Add('| `pas_abi_service_generator_tool.pas` | Paired Pascal service-side generator |');
    L.Add('| `pas_abi_call_generator_tool.pas` | Paired Pascal call-side generator |');
    L.Add('| `py_abi_service_generator_tool.pas` | Paired Python service-side generator |');
    L.Add('| `py_abi_call_generator_tool.pas` | Paired Python call-side generator |');
    L.Add('| `cpp_abi_service_generator_tool.pas` | Paired C++ service-side generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `cpp_abi_call_generator_tool.pas`');
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
  TargetAppName := NormalizedUnit + '_abi';
  NsName := NormalizedUnit + '_abi';
  HppName := NormalizedUnit + '_abi_call.hpp';
  CppName := NormalizedUnit + '_abi_call.cpp';

  Log(PFormat('GenerateABICallCppReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABICallCppReadme: %d valid APIs', [Length(SupportedFuncs)]));

  L := Result;
  try
    EmitHeader;
    EmitOverview;
    EmitApplicationScope;
    EmitCompatibility;
    EmitWireProtocol;
    EmitRuntimeArchitecture;
    EmitTypeMapping;
    EmitDeployment;
    EmitTesting;
    EmitApiReference;
    EmitTroubleshooting;
    EmitSelfAssessment;
    EmitResources;
  finally
    // Result already owns L; nothing to free here.
  end;

  Log(PFormat('GenerateABICallCppReadme: %d lines generated', [L.Count]));
end;

end.
