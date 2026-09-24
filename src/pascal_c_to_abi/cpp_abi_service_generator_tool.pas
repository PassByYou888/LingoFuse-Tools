unit cpp_abi_service_generator_tool;


// cpp_abi_service_generator_tool - LingoFuse ABI Service Provider Generator
// for C++.
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces TWO self-contained C++ artefacts:
//
//   GenerateABIServiceHppCode  ->  <unit>_abi_service.hpp
//       The declaration header. Exposes:
//         extern const char* DEFAULT_APP_NAME;
//         extern const char* DEFAULT_APP_DESC;
//         constexpr std::uint8_t STATUS_OK / STATUS_ERROR;
//         internal_call_* / Callback_* / RegisterAllABIAPIs /
//         CreateAndRegisterABIApp declarations.
//       Include this header to reference the service from any other
//       translation unit.
//
//   GenerateABIServiceCppCode  ->  <unit>_abi_service.cpp
//       The implementation. Includes the .hpp above and provides:
//         DEFAULT_APP_NAME / DEFAULT_APP_DESC definitions,
//         internal_call_* stub bodies,
//         Callback_* cdecl bodies,
//         RegisterAllABIAPIs / CreateAndRegisterABIApp bodies.
//
// Wire protocol (both directions):
//   request  = [field1][field2]...[fieldN]
//   response = [status:uint8_t][payload]
//     status = 0x00 -> success; payload is the serialised result
//                      (functions) or empty (procedures).
//     status = 0xFF -> error; payload is a UTF-8 string message.
//
// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> int32_t
//   int64                         -> int64_t
//   cardinal / dword / longword   -> uint32_t
//   word                          -> uint16_t
//   smallint                      -> int16_t
//   byte                          -> uint8_t
//   uint64                        -> uint64_t
//   double / extended / real      -> double
//   single                        -> float
//   string / PChar family         -> std::string
//
// Robustness notes:
//   Callbacks are invoked on a C worker thread. Any exception that
//   escapes the callback body has undefined behaviour. Every generated
//   callback therefore:
//     1. Uses Safe_Write_Error() to report errors without throwing.
//     2. Uses Safe_Write_Scalar / Safe_Write_String / Safe_Write_Void
//        to commit the success response as a single LF_WriteBuffer call,
//        so a client can never observe a 0x00 status byte without the
//        matching payload.
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


  // GenerateABIServiceHppCode - generate the service declaration header.
  //
  // The returned list contains the lines of a .hpp file that declares
  // every symbol exposed by the service. The caller owns the list and
  // must release it with DisposeObject.

function GenerateABIServiceHppCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABIServiceCppCode - generate the service implementation file.
//
// The returned list contains the lines of a .cpp file that includes
// the matching .hpp and defines every symbol declared there. The
// caller owns the list and must release it with DisposeObject.

function GenerateABIServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABIServiceCppReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// ABI type mapping, and every exposed API of the generated C++ service.
// The document is written so that both human readers and AI assistants
// can learn the service's usage model from the README alone.
//
// The C++ service produces two files (.hpp + .cpp). This README
// describes the pair as a single unit.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABIServiceCppReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[cpp_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[cpp_abi_service_generator] %s', [PFormat(Fmt, Args)]);
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

function ABI_Type_To_Cpp_Default(const T: TP_String): TP_String;
begin
  if IsStringABIType(T) then
    Result := 'std::string{}'
  else if T.Same('double') or T.Same('extended') or T.Same('real') or T.Same('single') then
    Result := '0.0'
  else if ABI_Type_To_Cpp_Decl(T) <> '' then
    Result := '0'
  else
    Result := '0';
end;

function ABI_Type_To_Read_C_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then Result := 'LF_ReadInt32'
  else if T.Same('int64') then Result := 'LF_ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then Result := 'LF_ReadUInt32'
  else if T.Same('word') then Result := 'LF_ReadUInt16'
  else if T.Same('smallint') then Result := 'LF_ReadInt16'
  else if T.Same('byte') then Result := 'LF_ReadUInt8'
  else if T.Same('uint64') then Result := 'LF_ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then Result := 'LF_ReadDouble'
  else if T.Same('single') then Result := 'LF_ReadSingle'
  else
    Result := '';
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
// Comment description extraction
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
    // Locate end of the current logical line.
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
          // Strip leading '*' markers from block comment continuation.
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

    // Advance past CR/LF.
    i := j;
    while (i <= Comment.Len) and ((Comment[i] = #10) or (Comment[i] = #13)) do
      Inc(i);
  end;
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
// Build parameter / argument strings from a TParamArray
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

// -----------------------------------------------------------------------------
// Emit the shared safety helpers into the service .cpp.
//
// These functions MUST NOT let any C++ exception escape into the C stack.
// Callbacks registered with LF_RegisterCall run on a C worker thread, and
// an exception crossing the C ABI boundary is undefined behaviour.
//
// The success helpers assemble [status][payload] into a single memory
// buffer and commit it with one LF_WriteBuffer call, so the client can
// never observe a 0x00 status byte without the matching payload.
// -----------------------------------------------------------------------------

procedure EmitSafetyHelpers(Lines: TPascalStringList);
begin
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('// Internal safety helpers');
  Lines.Add('//');
  Lines.Add('// Callbacks registered with LF_RegisterCall run on a C worker thread.');
  Lines.Add('// An exception crossing the C ABI boundary is undefined behaviour, so');
  Lines.Add('// every helper below is noexcept and reports failure only by leaving');
  Lines.Add('// the output handle in a state the client can detect.');
  Lines.Add('//');
  Lines.Add('// The success helpers assemble [status][payload] into a single buffer');
  Lines.Add('// and commit it with one LF_WriteBuffer call, so the client can never');
  Lines.Add('// observe a 0x00 status followed by a truncated payload.');
  Lines.Add('// ---------------------------------------------------------------------------');
  Lines.Add('');
  Lines.Add('static void Safe_Write_Error(TDataHnd hnd, const std::string& msg) noexcept {');
  Lines.Add('    try {');
  Lines.Add('        LF_WriteUInt8(hnd, STATUS_ERROR);');
  Lines.Add('        lingofuse::io::write_string(hnd, msg);');
  Lines.Add('    } catch (...) {');
  Lines.Add('        // Nothing more we can do; the client will see a truncated reply.');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('template <typename T>');
  Lines.Add('static void Safe_Write_Scalar(TDataHnd hnd, T value) noexcept {');
  Lines.Add('    static_assert(std::is_arithmetic<T>::value,');
  Lines.Add('                  "Safe_Write_Scalar requires an arithmetic type");');
  Lines.Add('    try {');
  Lines.Add('        std::uint8_t buf[1 + sizeof(T)];');
  Lines.Add('        buf[0] = STATUS_OK;');
  Lines.Add('        std::memcpy(buf + 1, &value, sizeof(T));');
  Lines.Add('        LF_WriteBuffer(hnd, buf, static_cast<int64_t>(sizeof(buf)));');
  Lines.Add('    } catch (...) {');
  Lines.Add('        // Nothing more we can do.');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('static void Safe_Write_String(TDataHnd hnd, const std::string& value) noexcept {');
  Lines.Add('    try {');
  Lines.Add('        const std::size_t total = 1 + value.size() + 1;   // status + bytes + NUL');
  Lines.Add('        std::vector<std::uint8_t> buf(total);');
  Lines.Add('        buf[0] = STATUS_OK;');
  Lines.Add('        if (!value.empty()) {');
  Lines.Add('            std::memcpy(buf.data() + 1, value.data(), value.size());');
  Lines.Add('        }');
  Lines.Add('        buf[total - 1] = 0;');
  Lines.Add('        LF_WriteBuffer(hnd, buf.data(), static_cast<int64_t>(total));');
  Lines.Add('    } catch (...) {');
  Lines.Add('        // Nothing more we can do.');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('static void Safe_Write_Void(TDataHnd hnd) noexcept {');
  Lines.Add('    try {');
  Lines.Add('        std::uint8_t buf[1] = { STATUS_OK };');
  Lines.Add('        LF_WriteBuffer(hnd, buf, 1);');
  Lines.Add('    } catch (...) {');
  Lines.Add('        // Nothing more we can do.');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

// -----------------------------------------------------------------------------
// GenerateABIServiceHppCode
// -----------------------------------------------------------------------------

function GenerateABIServiceHppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, NsName: TP_String;
  ProtocolGuard: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  Params: TP_String;
  RetType: TP_String;
  f: TFunctionStructure;
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

  // The service header and the matching call header share the same
  // namespace and both need STATUS_OK / STATUS_ERROR. Wrapping the
  // constants in an include guard keyed by the namespace name lets a
  // single translation unit include both headers without a
  // redefinition error. Different units produce different namespaces
  // and therefore different guards, so they remain independent.
  ProtocolGuard := 'LINGOFUSE_ABI_WIRE_PROTOCOL_' + NsName + '_DEFINED';

  Log(PFormat('Generating C++ ABI service header for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty header.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    // -------------------------------------------------------------------------
    // 1. Header + include guard
    // -------------------------------------------------------------------------
    Lines.Add('#pragma once');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by cpp_abi_service_generator_tool.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (both directions):');
    Lines.Add('//   request  = [field1][field2]...[fieldN]');
    Lines.Add('//   response = [status:uint8_t][payload]');
    Lines.Add('//     status = 0x00 -> success; payload is the serialised result');
    Lines.Add('//                      (functions) or empty (procedures).');
    Lines.Add('//     status = 0xFF -> error; payload is a UTF-8 string message.');
    Lines.Add('//');
    Lines.Add('// This is the service declaration header. The matching definition');
    Lines.Add('// lives in the companion .cpp file produced by the same generator.');
    Lines.Add('// Include this header to reference the service constants, callbacks,');
    Lines.Add('// registration entry points, or to link against the service.');
    Lines.Add('//');
    Lines.Add('// This header may be included in the same translation unit as the');
    Lines.Add('// matching call header (<unit>_abi_call.hpp). The shared protocol');
    Lines.Add('// constants are guarded so that no redefinition occurs.');
    Lines.Add('//');
    Lines.Add('// SOURCE FILE ENCODING: UTF-8.');
    Lines.Add('// MSVC users: add /utf-8 to the compiler command line. Otherwise the');
    Lines.Add('// non-ASCII characters in the API description strings will be encoded');
    Lines.Add('// with the system codepage and may not match what the LingoFuse');
    Lines.Add('// registry expects (UTF-8).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <string>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 2. Application metadata (extern declarations)
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Application metadata');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('extern const char* DEFAULT_APP_NAME;');
    Lines.Add('extern const char* DEFAULT_APP_DESC;');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 3. Wire protocol constants (guarded)
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Wire protocol constants');
    Lines.Add('//');
    Lines.Add('// These constants are also emitted by the matching call header.');
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
    // 4. Internal call stub declarations
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Internal call stubs (definitions in the companion .cpp file).');
    Lines.Add('// Each stub mirrors one original routine. The user is expected to');
    Lines.Add('// replace the body in the .cpp file with a call to the real function.');
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

      InternalCallName := 'internal_call_' + ApiName;
      Params := BuildCppParamList(f.Params);
      RetType := ABI_Type_To_Cpp_Decl(f.ReturnType);

      if f.IsFunction then
        Lines.Add(RetType + ' ' + InternalCallName + '(' + Params + ');')
      else
        Lines.Add('void ' + InternalCallName + '(' + Params + ');');
    end;

    Lines.Add('');

    // -------------------------------------------------------------------------
    // 5. Callback declarations
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// cdecl callbacks (definitions in the companion .cpp file).');
    Lines.Add('// These are the functions registered with LF_RegisterCall.');
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

      CallbackName := 'Callback_' + ApiName;
      Lines.Add('void LF_CDECL ' + CallbackName + '(void* _Trigger, void* _In, void* _Out);');
    end;

    Lines.Add('');

    // -------------------------------------------------------------------------
    // 6. Registration entry point declarations
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Registration entry points (definitions in the companion .cpp file).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('// Returns the number of APIs that failed to register (0 = all OK).');
    Lines.Add('int RegisterAllABIAPIs(TAppHnd app);');
    Lines.Add('');
    Lines.Add('// Convenience: create the app and register every API on it.');
    Lines.Add('// The caller owns the returned handle and must call LF_FreeApp on it.');
    Lines.Add('TAppHnd CreateAndRegisterABIApp();');
    Lines.Add('');
    Lines.Add('} // namespace ' + NsName);
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for the service header.', [Lines.Count]));
  finally
    UsedApiNames.Free;
    // Lines is returned to the caller; not freed here.
  end;
end;

// -----------------------------------------------------------------------------
// GenerateABIServiceCppCode
// -----------------------------------------------------------------------------

function GenerateABIServiceCppCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, NsName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName: TP_String;
  Description: TP_String;
  Params, Args: TP_String;
  PName, PTyp, ReadFn, RetType, RetDefault: TP_String;
  f: TFunctionStructure;
  HasParams: boolean;
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
  AppName := NormalizedUnit + '_abi';
  NsName := NormalizedUnit + '_abi';

  Log(PFormat('Generating C++ ABI service implementation for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty implementation.');

  UsedApiNames := TPascalStringList.Create;
  Lines := TPascalStringList.Create;
  try
    // -------------------------------------------------------------------------
    // 1. Header + includes
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Auto-generated by cpp_abi_service_generator_tool.');
    Lines.Add('// Source model unit: ' + UnitName.Text + '.');
    Lines.Add('// Do not edit by hand unless you know what you are doing.');
    Lines.Add('//');
    Lines.Add('// Wire protocol (both directions):');
    Lines.Add('//   request  = [field1][field2]...[fieldN]');
    Lines.Add('//   response = [status:uint8_t][payload]');
    Lines.Add('//     status = 0x00 -> success; payload is the serialised result');
    Lines.Add('//                      (functions) or empty (procedures).');
    Lines.Add('//     status = 0xFF -> error; payload is a UTF-8 string message.');
    Lines.Add('//');
    Lines.Add('// This is the service implementation file. Include the companion');
    Lines.Add('// header to see the declarations and the wire protocol description.');
    Lines.Add('//');
    Lines.Add('// SOURCE FILE ENCODING: UTF-8.');
    Lines.Add('// MSVC users: add /utf-8 to the compiler command line. Otherwise the');
    Lines.Add('// non-ASCII characters in the API description strings will be encoded');
    Lines.Add('// with the system codepage and may not match what the LingoFuse');
    Lines.Add('// registry expects (UTF-8).');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('#include "' + NormalizedUnit + '_abi_service.hpp"');
    Lines.Add('');
    Lines.Add('#include "LingoFuse.hpp"');
    Lines.Add('#include "lf_io.hpp"');
    Lines.Add('');
    Lines.Add('#include <cstdint>');
    Lines.Add('#include <cstring>');
    Lines.Add('#include <stdexcept>');
    Lines.Add('#include <string>');
    Lines.Add('#include <type_traits>');
    Lines.Add('#include <vector>');
    Lines.Add('');
    Lines.Add('namespace ' + NsName + ' {');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 2. Safety helpers (must be emitted before the callbacks that use them)
    // -------------------------------------------------------------------------
    EmitSafetyHelpers(Lines);

    // -------------------------------------------------------------------------
    // 3. Application metadata definitions
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Application metadata');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('const char* DEFAULT_APP_NAME = ' + CppStrLit(AppName) + ';');
    Lines.Add('const char* DEFAULT_APP_DESC = ' + CppStrLit('ABI service for ' + UnitName) + ';');
    Lines.Add('');

    // -------------------------------------------------------------------------
    // 4. Internal call stubs
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Internal call stubs. Each stub mirrors one original routine.');
    Lines.Add('// Replace the body with a call to the real function, for example:');
    Lines.Add('//     return MyUnit::Add(a, b);');
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

      InternalCallName := 'internal_call_' + ApiName;

      Params := BuildCppParamList(f.Params);
      Args := BuildCppArgList(f.Params);

      RetType := ABI_Type_To_Cpp_Decl(f.ReturnType);
      RetDefault := ABI_Type_To_Cpp_Default(f.ReturnType);

      if f.IsFunction then
        Lines.Add(RetType + ' ' + InternalCallName + '(' + Params + ') {')
      else
        Lines.Add('void ' + InternalCallName + '(' + Params + ') {');

      Lines.Add('    // TODO: replace the body with a call to the real function.');
      if f.IsFunction then
        Lines.Add('    //     return MyUnit::' + f.Name.Text + '(' + Args + ');')
      else
        Lines.Add('    //     MyUnit::' + f.Name.Text + '(' + Args + ');');

      // Silence unused-parameter warnings for the stub body.
      for j := 0 to High(f.Params) do
      begin
        PName := MakeSafeCppParamName(f.Params[j].Name, j);
        Lines.Add('    (void)' + PName + ';');
      end;

      if f.IsFunction then
        Lines.Add('    return ' + RetDefault + ';');
      Lines.Add('}');
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // 5. cdecl callbacks
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// cdecl callbacks. These are registered with LF_RegisterCall.');
    Lines.Add('//');
    Lines.Add('// Wire format:');
    Lines.Add('//   request  = [field1][field2]...[fieldN]');
    Lines.Add('//   response = [status:uint8_t][payload]');
    Lines.Add('//     status = 0x00 success; 0xFF error followed by a UTF-8 message.');
    Lines.Add('//');
    Lines.Add('// Every callback:');
    Lines.Add('//   * never lets an exception escape into the C stack;');
    Lines.Add('//   * commits the success response as a single LF_WriteBuffer call');
    Lines.Add('//     (see Safe_Write_Scalar / Safe_Write_String / Safe_Write_Void).');
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

      CallbackName := 'Callback_' + ApiName;
      InternalCallName := 'internal_call_' + ApiName;
      HasParams := Length(f.Params) > 0;

      Lines.Add('void LF_CDECL ' + CallbackName + '(void* _Trigger, void* _In, void* _Out) {');
      Lines.Add('    (void)_Trigger;');
      Lines.Add('    (void)_In;');
      Lines.Add('    TDataHnd _out_h = static_cast<TDataHnd>(_Out);');
      Lines.Add('');

      // Declare _in_h only when there is at least one parameter to read;
      // otherwise the unused variable would trigger -Wunused-variable
      // under -Wall -Wextra -Werror.
      if HasParams then
      begin
        Lines.Add('    TDataHnd _in_h = static_cast<TDataHnd>(_In);');
        Lines.Add('');

        for j := 0 to High(f.Params) do
        begin
          PName := MakeSafeCppParamName(f.Params[j].Name, j);
          PTyp := ABI_Type_To_Cpp_Decl(f.Params[j].PascalType);

          if IsStringABIType(f.Params[j].PascalType) then
          begin
            Lines.Add('    std::string ' + PName + ';');
            Lines.Add('    try {');
            Lines.Add('        ' + PName + ' = lingofuse::io::read_string(_in_h);');
            Lines.Add('    } catch (const std::exception& _e) {');
            Lines.Add('        Safe_Write_Error(_out_h, std::string("read_string failed: ") + _e.what());');
            Lines.Add('        return;');
            Lines.Add('    }');
          end
          else
          begin
            ReadFn := ABI_Type_To_Read_C_Func(f.Params[j].PascalType);
            Lines.Add('    ' + PTyp + ' ' + PName + ' = 0;');
            Lines.Add('    if (' + ReadFn + '(_in_h, &' + PName + ') != 1) {');
            Lines.Add('        Safe_Write_Error(_out_h, "input truncated: ' + PName + '");');
            Lines.Add('        return;');
            Lines.Add('    }');
          end;
        end;

        Lines.Add('');
      end;

      Args := BuildCppArgList(f.Params);

      // -----------------------------------------------------------------
      // Invoke the internal stub, capturing any exception. The exception
      // handler is forced to return; nothing else runs.
      // -----------------------------------------------------------------
      if f.IsFunction then
      begin
        RetType := ABI_Type_To_Cpp_Decl(f.ReturnType);
        if IsStringABIType(f.ReturnType) then
          Lines.Add('    std::string _ret;')
        else
          Lines.Add('    ' + RetType + ' _ret = 0;');
      end;

      Lines.Add('    try {');
      if f.IsFunction then
        Lines.Add('        _ret = ' + InternalCallName + '(' + Args + ');')
      else
        Lines.Add('        ' + InternalCallName + '(' + Args + ');');
      Lines.Add('    }');
      Lines.Add('    catch (const std::exception& _e) {');
      Lines.Add('        Safe_Write_Error(_out_h, _e.what());');
      Lines.Add('        return;');
      Lines.Add('    }');
      Lines.Add('    catch (...) {');
      Lines.Add('        Safe_Write_Error(_out_h, "unknown exception");');
      Lines.Add('        return;');
      Lines.Add('    }');
      Lines.Add('');

      // -----------------------------------------------------------------
      // Success path: commit [status][payload] as one atomic buffer.
      // -----------------------------------------------------------------
      if f.IsFunction then
      begin
        if IsStringABIType(f.ReturnType) then
          Lines.Add('    Safe_Write_String(_out_h, _ret);')
        else
          Lines.Add('    Safe_Write_Scalar<' + RetType + '>(_out_h, _ret);');
      end
      else
        Lines.Add('    Safe_Write_Void(_out_h);');

      Lines.Add('}');
      Lines.Add('');
    end;

    // -------------------------------------------------------------------------
    // 6. Registration
    // -------------------------------------------------------------------------
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('// Registration');
    Lines.Add('// ---------------------------------------------------------------------------');
    Lines.Add('');
    Lines.Add('int RegisterAllABIAPIs(TAppHnd app) {');
    Lines.Add('    int _failed = 0;');

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

      CallbackName := 'Callback_' + ApiName;
      Description := GetFullDescription(f.Comment);
      if Description.Len = 0 then
        Description := 'ABI api for ' + f.Name;

      Lines.Add('    if (LF_RegisterCall(app, ' + CppStrLit(ApiName) + ', ' + CppStrLit(Description) + ', nullptr, ' + CallbackName + ') != 1) {');
      Lines.Add('        ++_failed;');
      Lines.Add('    }');
    end;

    Lines.Add('    return _failed;');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('TAppHnd CreateAndRegisterABIApp() {');
    Lines.Add('    TAppHnd app = LF_CreateApp(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    Lines.Add('    if (app != nullptr) {');
    Lines.Add('        // The failure count is intentionally ignored here. Callers');
    Lines.Add('        // that need to react to partial registration should call');
    Lines.Add('        // RegisterAllABIAPIs directly and inspect its return value.');
    Lines.Add('        RegisterAllABIAPIs(app);');
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
    // Lines is returned to the caller; not freed here.
  end;
end;

// =============================================================================
// SECTION 3 - README generator
// =============================================================================
//
// This section is self-contained. It depends only on the helpers already
// present in this unit (MakeApiName, ABI_Type_To_Cpp_Decl,
// ABI_Type_To_Cpp_Param_Decl, ABI_Type_To_Read_C_Func,
// MakeSafeCppParamName, CppStrLit, GetFullDescription,
// CollectSupportedFunctions) plus the standard Z-framework units already
// in scope.
//
// The README is organised into twelve sections:
//
//   §1  Overview
//   §2  Application scope
//   §3  Compatibility (C++ standard, compilers, platforms)
//   §4  Wire protocol
//   §5  Runtime architecture
//   §6  Type mapping
//   §7  Deployment
//   §8  Testing
//   §9  API reference
//   §10 Troubleshooting
//   §11 Self-assessment checklist
//   §12 Reference resources
//
// The document is written so that both human readers and AI assistants
// can learn the C++ service's usage model from the README alone.
// =============================================================================

// Returns the "wire size" column text for the ABI type table.
function CppReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
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

// Returns the "LF_Read function" column text for the ABI type table.
function CppReadmeReadFunc(const ABI_Type: TP_String): TP_String;
begin
  Result := ABI_Type_To_Read_C_Func(ABI_Type);
  if Result.Len = 0 then
    Result := '`io::read_string`';
end;

// Sanitise a description for use inside a Markdown table cell.
function CppReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// Sanitise a description for use as standalone paragraph text.
function CppReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

// Build the README for a given model.
function GenerateABIServiceCppReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName, NsName, HppName, CppName: TP_String;

// ---------------------------------------------------------------------------
// §1. Header
// ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - C++ ABI Service Provider');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `cpp_abi_service_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Service header**    : `' + HppName + '`');
    L.Add('> **Service impl**      : `' + CppName + '`');
    L.Add('> **Namespace**         : `' + NsName + '`');
    L.Add('> **Default App name**  : `' + AppName + '`');
    L.Add('> **Exposed APIs**      : ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> compile, deploy, or call this service without reading the source.');
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
    L.Add('This document describes the **C++ ABI service** that was generated');
    L.Add('from the Pascal unit `' + UnitName + '`. The service is a');
    L.Add('strongly-typed, binary-wire RPC endpoint built on top of LingoFuse.');
    L.Add('');
    L.Add('### 1.1 What is an ABI service?');
    L.Add('');
    L.Add('An ABI service is a LingoFuse endpoint that:');
    L.Add('');
    L.Add('- exposes one or more routines as remotely callable APIs;');
    L.Add('- uses a **compact binary wire protocol** in both directions;');
    L.Add('- binds every API to a **fixed, statically-typed signature**;');
    L.Add('- requires a **matching call-side client** to invoke. The call-side');
    L.Add('  client can be generated by the paired Pascal, Python, or C++');
    L.Add('  generator from the same model.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Discovery | Direct by App name on LingoFuse |');
    L.Add('| Client | Must be paired (generated from the same model) |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Implementation | C++17, no exceptions across the C ABI boundary |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Compile** the service pair (`.hpp` + `.cpp`) into your program.');
    L.Add('   See §7.');
    L.Add('2. **Implement** every `internal_call_*` function. See §7.2.');
    L.Add('3. **Start** the service and let it register the APIs. See §8.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + HppName + '` | Service declaration header. |');
    L.Add('| `' + CppName + '` | Service implementation file. |');
    L.Add('| `' + UnitName + '_abi_service_cpp.md` | This README. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use a C++ ABI service');
    L.Add('');
    L.Add('Use this generator when:');
    L.Add('');
    L.Add('- You have a **fixed set of C++ functions** with stable signatures.');
    L.Add('- Your callers are **known in advance** (you control both sides).');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- A C++ compute engine exposing primitives to a Python orchestrator.');
    L.Add('- A C++ service embedded inside a larger native application.');
    L.Add('- A high-frequency producer that pushes typed events to a client.');
    L.Add('- A native bridge between a Pascal host and a C++ library.');
    L.Add('');
    L.Add('### 2.2 When NOT to use a C++ ABI service');
    L.Add('');
    L.Add('- The API surface changes frequently: regenerate the whole chain.');
    L.Add('- Callers need to discover the API surface dynamically at runtime.');
    L.Add('- Parameters include complex types (classes, containers, variants).');
    L.Add('- The service must be reachable by arbitrary third-party clients.');
    L.Add('- The service must support multiple versions of a signature at once.');
    L.Add('');
    L.Add('### 2.3 Comparison with other RPC approaches');
    L.Add('');
    L.Add('| Approach | Typed | Binary | Self-describing | Paired client |');
    L.Add('|----------|:-----:|:------:|:---------------:|:-------------:|');
    L.Add('| This ABI service | yes | yes | no | yes (required) |');
    L.Add('| gRPC | yes | yes | yes (proto) | yes (generated) |');
    L.Add('| REST + JSON | no | no | yes | no |');
    L.Add('| Raw TCP sockets | no | yes | no | yes |');
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
    L.Add('library plus two headers (`LingoFuse.hpp`, `lf_io.hpp`).');
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
    L.Add('Callbacks execute on a LingoFuse worker thread, not the main');
    L.Add('thread. Every generated callback:');
    L.Add('');
    L.Add('- is declared `LF_CDECL` (i.e. `__cdecl` on Windows);');
    L.Add('- is wrapped in a `try/catch` so that no exception crosses the');
    L.Add('  C ABI boundary;');
    L.Add('- uses the `Safe_Write_*` helpers to commit its response as a');
    L.Add('  single `LF_WriteBuffer` call.');
    L.Add('');
    L.Add('**Do not call any blocking LingoFuse function inside a callback.**');
    L.Add('Doing so deadlocks the calling worker thread.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The ABI service uses a minimal, fixed binary wire format on both');
    L.Add('directions.');
    L.Add('');
    L.Add('### 4.1 Request');
    L.Add('');
    L.Add('```');
    L.Add('request = [field1][field2]...[fieldN]');
    L.Add('```');
    L.Add('');
    L.Add('Fields are serialised in the **exact order** in which they appear');
    L.Add('in the original Pascal declaration. There is no header, no length');
    L.Add('prefix, and no field tag: the receiver must know the signature to');
    L.Add('parse the payload.');
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
    L.Add('    participant C as Client');
    L.Add('    participant S as C++ service');
    L.Add('    C->>C: write fields (little-endian)');
    L.Add('    C->>S: LF_CallEx(payload)');
    L.Add('    S->>S: io::read_int32 / io::read_string / ...');
    L.Add('    S->>S: internal_call_xxx(a, b)');
    L.Add('    S->>S: Safe_Write_Scalar / Safe_Write_String / Safe_Write_Void');
    L.Add('    S-->>C: response');
    L.Add('    C->>C: read status + result');
    L.Add('```');
    L.Add('');
    L.Add('### 4.5 Error response example');
    L.Add('');
    L.Add('Bytes on the wire:');
    L.Add('');
    L.Add('```');
    L.Add('FF                                  <- status = 0xFF');
    L.Add('72 65 61 64 20 66 61 69 6C 65 64    <- "read failed" (UTF-8)');
    L.Add('00                                  <- NUL terminator');
    L.Add('```');
    L.Add('');
    L.Add('The call side raises `EABI_RemoteError` with the decoded message.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §6. Runtime architecture
  // ---------------------------------------------------------------------------
  procedure EmitRuntimeArchitecture;
  begin
    L.Add('## 5. Runtime Architecture');
    L.Add('');
    L.Add('```mermaid');
    L.Add('flowchart TD');
    L.Add('    subgraph CppService["C++ service process"]');
    L.Add('        P_APP["CreateAndRegisterABIApp()<br/>creates the App and registers every API"]');
    L.Add('        P_SVC["LF_PrepareService(&#39;ipc:&lt;unit&gt;_abi&#39;)"]');
    L.Add('        P_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, app)"]');
    L.Add('        P_RUN["LF_PrepareDone()"]');
    L.Add('        P_CBK["LF_CDECL callbacks"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["Client process (external)"]');
    L.Add('        C_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, nullptr)"]');
    L.Add('        C_RUN["LF_PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;ApiName&gt;(args)"]');
    L.Add('    end');
    L.Add('');
    L.Add('    P_APP --> P_SVC --> P_CLI --> P_RUN');
    L.Add('    P_RUN --> P_CBK');
    L.Add('    C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "LF_CallEx over IPC" .-> P_CBK');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (C++ service)');
    L.Add('');
    L.Add('1. `LF_ResetPrepare();`');
    L.Add('2. `LF_PrepareService("ipc:<unit>_abi", "ipc:<unit>_abi");`');
    L.Add('3. `TAppHnd app = ' + NsName + '::CreateAndRegisterABIApp();`');
    L.Add('4. `LF_PrepareClient("ipc:<unit>_abi", app);`');
    L.Add('5. `if (LF_PrepareDone() != 1) { /* handle failure */ }`');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The client serialises the parameters and calls `LF_CallEx`.');
    L.Add('2. LingoFuse routes the payload to the matching `LF_CDECL`');
    L.Add('   callback.');
    L.Add('3. The callback deserialises the parameters with `io::read_*`.');
    L.Add('4. It calls the namespace-level `internal_call_<Api>` function.');
    L.Add('5. The function runs the real C++ body.');
    L.Add('6. The callback commits `STATUS_OK` + payload in one');
    L.Add('   `LF_WriteBuffer` call (see `Safe_Write_*`).');
    L.Add('7. On any exception, the callback commits `STATUS_ERROR` + a');
    L.Add('   UTF-8 error message.');
    L.Add('');
    L.Add('### 5.3 Threading notes');
    L.Add('');
    L.Add('- Callbacks execute on a LingoFuse worker thread.');
    L.Add('- Never let a C++ exception escape into the C ABI boundary.');
    L.Add('- Do not block the callback for long periods: it holds a worker');
    L.Add('  thread from the LingoFuse pool.');
    L.Add('- Do not call `LF_Call` / `LF_Notify` from inside a callback.');
    L.Add('- If you need to touch a UI or main-thread state, marshal the work');
    L.Add('  to the main thread yourself.');
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
    L.Add('Every parameter and return type of every exposed API must be in');
    L.Add('this table. Any other type causes the **entire routine** to be');
    L.Add('silently dropped during generation.');
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
    L.Add('When a routine is called, its parameters appear as:');
    L.Add('');
    L.Add('- scalar types -> passed by value;');
    L.Add('- string types -> passed as `const std::string&`.');
    L.Add('');
    L.Add('### 6.2 Unsupported types');
    L.Add('');
    L.Add('Anything not in §6.1 causes the **entire routine** to be silently');
    L.Add('dropped during generation. Common examples:');
    L.Add('');
    L.Add('- `bool`');
    L.Add('- `std::vector`, `std::map`, `std::unordered_map`, `std::array`');
    L.Add('- Custom classes and structs');
    L.Add('- `std::optional`, `std::variant`, `std::any`');
    L.Add('- `std::chrono::*`');
    L.Add('- Pointers, function pointers');
    L.Add('');
    L.Add('**Workaround**: serialise complex values into a `std::string` first');
    L.Add('(JSON or a custom format), then pass the string across the ABI');
    L.Add('boundary. On the call side, deserialise the string back into the');
    L.Add('rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The ABI wire format uses little-endian for all integers and');
    L.Add('floats. Every platform listed in §3.3 is little-endian, so the');
    L.Add('generated code never performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('String parameters and return values are written and read by the');
    L.Add('`lingofuse::io` helpers, which always append a single `\\0` byte');
    L.Add('after the UTF-8 payload. `io::read_string` scans forward until it');
    L.Add('finds that byte. A mismatch (missing NUL) causes the reader to');
    L.Add('consume the rest of the payload.');
    L.Add('');
    L.Add('**Recommendation**: always use the provided helpers. Do not');
    L.Add('hand-roll the string encoding.');
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
    L.Add('my_abi_service/');
    L.Add('  ' + HppName + '            <- generated (declaration)');
    L.Add('  ' + CppName + '            <- generated (implementation)');
    L.Add('  main.cpp                                    <- your service entry point');
    L.Add('  LingoFuse.hpp                               <- from the LingoFuse runtime');
    L.Add('  lf_io.hpp                                   <- from the LingoFuse runtime');
    L.Add('  LingoFuse64.dll                             <- Windows');
    L.Add('  liblingofuse.so                             <- Linux');
    L.Add('  liblingofuse.dylib                          <- macOS');
    L.Add('```');
    L.Add('');
    L.Add('### 7.2 Implementing the internal_call_* stubs');
    L.Add('');
    L.Add('Every exposed API has a matching stub in the generated `.cpp` file:');
    L.Add('');
    L.Add('```cpp');
    L.Add('<RetType> internal_call_<Api>(<params>) {');
    L.Add('    // TODO: replace the body with a call to the real function.');
    L.Add('    //     return MyEngine::<real_func>(<args>);');
    L.Add('    return <default>;');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('Replace the placeholder body. The signature is already correct:');
    L.Add('keep the parameter names and the return type.');
    L.Add('');
    L.Add('### 7.3 Build commands');
    L.Add('');
    L.Add('**Linux / macOS (g++):**');
    L.Add('');
    L.Add('```bash');
    L.Add('g++ -std=c++17 -O2 -I. \\');
    L.Add('    main.cpp ' + CppName + ' \\');
    L.Add('    -L. -lLingoFuse -Wl,-rpath,. \\');
    L.Add('    -o ' + NormalizedUnit + '_service');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (MSVC):**');
    L.Add('');
    L.Add('```bat');
    L.Add('cl /std:c++17 /EHsc /utf-8 /I. main.cpp ' + CppName + ' ^');
    L.Add('   /link /LIBPATH:. LingoFuse.lib /OUT:' + NormalizedUnit + '_service.exe');
    L.Add('```');
    L.Add('');
    L.Add('**Windows (MinGW-w64):**');
    L.Add('');
    L.Add('```bat');
    L.Add('g++ -std=c++17 -O2 -I. main.cpp ' + CppName + ' ^');
    L.Add('    -L. -lLingoFuse -o ' + NormalizedUnit + '_service.exe');
    L.Add('```');
    L.Add('');
    L.Add('### 7.4 Setting the runtime library path');
    L.Add('');
    L.Add('**Linux / macOS:**');
    L.Add('');
    L.Add('```bash');
    L.Add('LD_LIBRARY_PATH=. ./' + NormalizedUnit + '_service    # Linux');
    L.Add('DYLD_LIBRARY_PATH=. ./' + NormalizedUnit + '_service  # macOS');
    L.Add('```');
    L.Add('');
    L.Add('**Windows:** place `LingoFuse64.dll` and `z_ipc_*.dll` next to the');
    L.Add('executable, or add their directory to `PATH`.');
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
    L.Add('The recommended shutdown sequence is:');
    L.Add('');
    L.Add('1. `LF_ExitMainThread();`');
    L.Add('2. `LF_FreeApp(app);`');
    L.Add('3. `LF_Shutdown();`');
    L.Add('');
    L.Add('Do not skip any step.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §9. Testing
  // ---------------------------------------------------------------------------
  procedure EmitTesting;
  begin
    L.Add('## 8. Testing');
    L.Add('');
    L.Add('The program below is a complete, copy-paste-ready test harness.');
    L.Add('Save it as `main.cpp` next to the generated pair and compile as');
    L.Add('described in §7.3.');
    L.Add('');
    L.Add('### 8.1 Test program (`main.cpp`)');
    L.Add('');
    L.Add('```cpp');
    L.Add('// main.cpp - test entry point for the generated C++ ABI service.');
    L.Add('//');
    L.Add('// Build:');
    L.Add('//   g++ -std=c++17 -O2 -I. main.cpp ' + CppName + ' \\');
    L.Add('//       -L. -lLingoFuse -Wl,-rpath,. \\');
    L.Add('//       -o ' + NormalizedUnit + '_service');
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
    L.Add('    std::printf("=== %s service ===\\n",');
    L.Add('                ' + NsName + '::DEFAULT_APP_NAME);');
    L.Add('');
    L.Add('    LF_ResetPrepare();');
    L.Add('    LF_PrepareService("ipc:' + AppName + '", "ipc:' + AppName + '");');
    L.Add('');
    L.Add('    TAppHnd app = ' + NsName + '::CreateAndRegisterABIApp();');
    L.Add('    if (app == nullptr) {');
    L.Add('        std::fprintf(stderr, "[FATAL] CreateAndRegisterABIApp failed\\n");');
    L.Add('        return 1;');
    L.Add('    }');
    L.Add('');
    L.Add('    if (LF_PrepareClient("ipc:' + AppName + '", app) == -1) {');
    L.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareClient failed\\n");');
    L.Add('        LF_FreeApp(app);');
    L.Add('        return 1;');
    L.Add('    }');
    L.Add('');
    L.Add('    if (LF_PrepareDone() != 1) {');
    L.Add('        std::fprintf(stderr, "[FATAL] LF_PrepareDone failed\\n");');
    L.Add('        LF_ExitMainThread();');
    L.Add('        LF_FreeApp(app);');
    L.Add('        LF_Shutdown();');
    L.Add('        return 1;');
    L.Add('    }');
    L.Add('');
    L.Add('    std::printf("[OK] Service ready. Press Enter to shut down.\\n");');
    L.Add('    std::getchar();');
    L.Add('');
    L.Add('    LF_ExitMainThread();');
    L.Add('    LF_FreeApp(app);');
    L.Add('    LF_Shutdown();');
    L.Add('    std::printf("[OK] Shutdown complete.\\n");');
    L.Add('    return 0;');
    L.Add('}');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Running the test');
    L.Add('');
    L.Add('```bash');
    L.Add('./' + NormalizedUnit + '_service');
    L.Add('```');
    L.Add('');
    L.Add('Expected output:');
    L.Add('');
    L.Add('```');
    L.Add('=== ' + AppName + ' service ===');
    L.Add('[OK] Service ready. Press Enter to shut down.');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path, make a call with a deliberately');
    L.Add('truncated payload (for example, pass an empty string where a');
    L.Add('non-empty value is expected). The callback responds with');
    L.Add('`STATUS_ERROR` and the client raises `EABI_RemoteError`.');
    L.Add('');
    L.Add('### 8.4 Unit-level testing');
    L.Add('');
    L.Add('To exercise a callback without a full LingoFuse deployment, call');
    L.Add('the callback function directly with synthetic handles:');
    L.Add('');
    L.Add('```cpp');
    L.Add('TDataHnd in  = LF_CreateData("' + AppName + '");');
    L.Add('TDataHnd out = LF_CreateData("' + AppName + '");');
    L.Add('// ... write fields into in with LF_WriteXxx ...');
    L.Add(NsName + '::Callback_<ApiName>_<ApiName>(nullptr, in, out);');
    L.Add('// ... read the response with LF_ReadXxx ...');
    L.Add('LF_FreeData(in);');
    L.Add('LF_FreeData(out);');
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
    PName, PTyp: TP_String;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this service exposes no APIs.**');
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

    L.Add('Total APIs: **' + umlIntToStr(Length(SupportedFuncs)).Text + '**.');
    L.Add('');
    L.Add('Every API is exposed as a LingoFuse Call API with the same name.');
    L.Add('The `LF_CDECL` callback is registered automatically by');
    L.Add('`' + NsName + '::RegisterAllABIAPIs`.');
    L.Add('');

    // ---- Summary table ---------------------------------------------------
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');

    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      ShortDesc := CppReadmeTableCell(GetFullDescription(Func.Comment));
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
      FuncDesc := CppReadmeParagraph(GetFullDescription(Func.Comment));

      // Reconstruct the internal_call_* signature.
      ParamDecl := '';
      for jj := 0 to High(Func.Params) do
      begin
        PName := MakeSafeCppParamName(Func.Params[jj].Name, jj);
        PTyp := ABI_Type_To_Cpp_Param_Decl(Func.Params[jj].PascalType);
        if jj > 0 then
          ParamDecl := ParamDecl + ', ';
        ParamDecl := ParamDecl + PTyp + ' ' + PName;
      end;

      if Func.IsFunction then
      begin
        RetDecl := ABI_Type_To_Cpp_Decl(Func.ReturnType);
        L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
        L.Add('');
        L.Add('- **Registered API name**: `' + ApiNm + '`');
        L.Add('- **Kind**: function; returns `' + RetDecl + '`');
        L.Add('- **Internal stub**: `' + RetDecl + ' internal_call_' + ApiNm + '(' + ParamDecl + ');`');
      end
      else
      begin
        L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
        L.Add('');
        L.Add('- **Registered API name**: `' + ApiNm + '`');
        L.Add('- **Kind**: procedure');
        L.Add('- **Internal stub**: `void internal_call_' + ApiNm + '(' + ParamDecl + ');`');
      end;
      L.Add('- **Raises**: nothing; failures are encoded as `STATUS_ERROR`.');
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
            Func.Params[jj].PascalType + '`' + ' | ' + CppReadmeWireSizeText(Func.Params[jj].PascalType) + ' |';
          L.Add(RowStr);
        end;
        L.Add('');
      end;

      // Request layout
      L.Add('#### Request layout');
      L.Add('');
      L.Add('```');
      if Length(Func.Params) = 0 then
        L.Add('(empty payload)')
      else
      begin
        RowStr := '';
        for jj := 0 to High(Func.Params) do
        begin
          PName := MakeSafeCppParamName(Func.Params[jj].Name, jj);
          if RowStr <> '' then
            RowStr := RowStr + ' ';
          RowStr := RowStr + '[' + PName + ': ' + Func.Params[jj].PascalType + ']';
        end;
        L.Add(RowStr);
      end;
      L.Add('```');
      L.Add('');

      // Success response layout
      L.Add('#### Success response layout');
      L.Add('');
      L.Add('```');
      if Func.IsFunction then
        L.Add('[STATUS_OK] [result: ' + ABI_Type_To_Cpp_Decl(Func.ReturnType) + ']')
      else
        L.Add('[STATUS_OK]');
      L.Add('```');
      L.Add('');

      // Error response
      L.Add('#### Error response');
      L.Add('');
      L.Add('`STATUS_ERROR` (0xFF) followed by a UTF-8 message terminated by');
      L.Add('`\\0`. The call side raises `EABI_RemoteError` with the decoded');
      L.Add('message.');
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
    L.Add('| `undefined reference to LF_*` | LingoFuse library not linked | Add `-lLingoFuse` and the correct `-L<path>`. |');
    L.Add('| Runtime `cannot open shared object file` | Library not on the loader path | `export LD_LIBRARY_PATH=.` (Linux) or copy the DLL next to the exe (Windows). |');
    L.Add('| `LF_PrepareDone` returns 0 | Main thread already active in this process | Reuse the existing runtime, or call `LF_Shutdown` first. |');
    L.Add('| Client `LF_PrepareDone` returns 0 | Server not running | Start the server before the client. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | App name mismatch | Check `DEFAULT_APP_NAME` on the server and the client target. |');
    L.Add('| `EABI_RemoteError: "input truncated"` | Fewer fields than expected | Verify the client writes every parameter. |');
    L.Add('| `EABI_RemoteError: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| String parameters read as empty | Missing NUL terminator | Use `io::write_string` on the writer side. |');
    L.Add('| Callback never fires | `internal_call_*` stub not filled | Search for `TODO` in the `.cpp` file. |');
    L.Add('| Callback crashes the process | Exception escaping the C ABI | The generated wrapper is `noexcept`; check that no exception escapes. |');
    L.Add('| UI update crashes the service | Worker thread touching UI | Marshal UI updates to the main thread yourself. |');
    L.Add('| MSVC warns about non-ASCII characters | Missing `/utf-8` | Add `/utf-8` to the compiler command. |');
    L.Add('');
    L.Add('### 10.2 Verifying a running service');
    L.Add('');
    L.Add('Before making a call:');
    L.Add('');
    L.Add('```cpp');
    L.Add('if (LF_CheckMainThread() == 0) {');
    L.Add('    std::fprintf(stderr, "Main thread is not running\\n");');
    L.Add('}');
    L.Add('if (LF_CheckApp("' + AppName + '") == 0) {');
    L.Add('    std::fprintf(stderr, "Service App not registered\\n");');
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
    L.Add('std::printf("\\n");');
    L.Add('```');
    L.Add('');
    L.Add('### 10.4 Enabling verbose logging');
    L.Add('');
    L.Add('In `main.cpp`, before the service starts:');
    L.Add('');
    L.Add('```cpp');
    L.Add('LF_SetOption("ConsoleOutput", "True");');
    L.Add('LF_SetOption("Quiet", "False");');
    L.Add('```');
    L.Add('');
    L.Add('LingoFuse then prints connection events and per-call diagnostics to');
    L.Add('standard output.');
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
    L.Add('| 1 | What does the C++ ABI service expose? | §1 |');
    L.Add('| 2 | When should I choose ABI instead of a JSON-based RPC? | §2 |');
    L.Add('| 3 | Which C++ standard and compilers are supported? | §3 |');
    L.Add('| 4 | What are the two bytes that frame every response? | §4.2 |');
    L.Add('| 5 | Which function do I call to create the App? | §5.1 |');
    L.Add('| 6 | What happens if a parameter type is not in the whitelist? | §6.2 |');
    L.Add('| 7 | How do I implement an internal_call_* stub? | §7.2 |');
    L.Add('| 8 | How do I compile the service with g++? | §7.3 |');
    L.Add('| 9 | How do I compile the service with MSVC? | §7.3 |');
    L.Add('| 10 | What is the shutdown order? | §7.6 |');
    L.Add('| 11 | How do I write a minimal test harness? | §8 |');
    L.Add('| 12 | How do I invoke a specific API from the call side? | §9 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('C++ ABI service.');
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
    L.Add('| `cpp_abi_call_generator_tool.pas` | Paired C++ call-side generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `cpp_abi_service_generator_tool.pas`');
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
  AppName := NormalizedUnit + '_abi';
  NsName := NormalizedUnit + '_abi';
  HppName := NormalizedUnit + '_abi_service.hpp';
  CppName := NormalizedUnit + '_abi_service.cpp';

  Log(PFormat('GenerateABIServiceCppReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABIServiceCppReadme: %d valid APIs', [Length(SupportedFuncs)]));

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

  Log(PFormat('GenerateABIServiceCppReadme: %d lines generated', [L.Count]));
end;

end.
