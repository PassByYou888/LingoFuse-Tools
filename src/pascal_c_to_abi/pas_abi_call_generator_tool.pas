unit pas_abi_call_generator_tool;


// pas_abi_call_generator_tool - LingoFuse ABI Call-Side Generator
//
// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces a companion Pascal unit that provides typed free
// functions for calling the corresponding ABI service, plus a Markdown
// README that documents the call-side unit for both human engineers and
// AI assistants.
//
// The generated unit:
//   - Declares a runtime-configurable target app name and timeout.
//   - Declares an EABI_RemoteError exception class.
//   - Provides one free function per supported routine, mirroring the
//     signature of the original declaration. Each function:
//       1. Serialises its arguments into a DataHnd using LF_WriteXxx.
//       2. Calls LF_CallEx and reads back the response.
//       3. Interprets the one-byte status prefix written by the service:
//            0x00 -> success; reads and returns the payload.
//            0xFF -> raises EABI_RemoteError with the UTF-8 message.
//
// Wire protocol (matches pas_abi_service_generator_tool):
//   request  = [field1][field2]...[fieldN]
//   response = [status:UInt8][payload]
//     status = 0x00 -> success
//     status = 0xFF -> error followed by an LF_WriteString UTF-8 message
//
// Deployment notes:
//   The generated unit does NOT call LF_PrepareClient / LF_PrepareDone /
//   LF_Shutdown. The host program is responsible for wiring up LingoFuse
//   before calling any generated function. A typical host program:
//
//       LF_ResetPrepare;
//       LF_PrepareClient('ipc:my_unit_abi', nil);
//       if LF_PrepareDone <> 1 then Halt(1);
//       try
//         WriteLn(Add(3, 4));
//       finally
//         LF_ExitMainThread;
//         LF_Shutdown;
//       end;
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


  // GenerateABICallPascalCode - main entry point.
  //
  // Model must be built with Typ_Normalize_Func = tnf_ABI. The returned list
  // is owned by the caller and must be released with DisposeObject.

function GenerateABICallPascalCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABICallPascalReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol, the
// call-side type mapping, and every exported free function. The document
// is written so that both human readers and AI assistants can learn the
// call-side unit's usage model from the README alone.
//
// The caller owns the returned list and must release it with DisposeObject.

function GenerateABICallPascalReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[pas_abi_call_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_call_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type mapping (mirrors pas_abi_service_generator_tool)
// -----------------------------------------------------------------------------

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
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar') then
    Result := 'string'
  else
    Result := '';
end;

function ABI_Type_To_Write_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'LF_WriteInt32'
  else if T.Same('int64') then
    Result := 'LF_WriteInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'LF_WriteUInt32'
  else if T.Same('word') then
    Result := 'LF_WriteUInt16'
  else if T.Same('smallint') then
    Result := 'LF_WriteInt16'
  else if T.Same('byte') then
    Result := 'LF_WriteUInt8'
  else if T.Same('uint64') then
    Result := 'LF_WriteUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'LF_WriteDouble'
  else if T.Same('single') then
    Result := 'LF_WriteSingle'
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar') then
    Result := 'LF_WriteString'
  else
    Result := '';
end;

function ABI_Type_To_Read_Func(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('longint') then
    Result := 'LF_ReadInt32'
  else if T.Same('int64') then
    Result := 'LF_ReadInt64'
  else if T.Same('cardinal') or T.Same('dword') or T.Same('longword') then
    Result := 'LF_ReadUInt32'
  else if T.Same('word') then
    Result := 'LF_ReadUInt16'
  else if T.Same('smallint') then
    Result := 'LF_ReadInt16'
  else if T.Same('byte') then
    Result := 'LF_ReadUInt8'
  else if T.Same('uint64') then
    Result := 'LF_ReadUInt64'
  else if T.Same('double') or T.Same('extended') or T.Same('real') then
    Result := 'LF_ReadDouble'
  else if T.Same('single') then
    Result := 'LF_ReadSingle'
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar') then
    Result := 'LF_ReadString'
  else
    Result := '';
end;

function IsSupportedABIType(const T: TP_String): boolean;
begin
  Result := ABI_Type_To_Pascal_Decl(T) <> '';
end;

// -----------------------------------------------------------------------------
// Identifier helpers
// -----------------------------------------------------------------------------

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

// -----------------------------------------------------------------------------
// Parameter helpers
// -----------------------------------------------------------------------------

function BuildTypedParamDecl(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
  decl: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;

    decl := ABI_Type_To_Pascal_Decl(Params[i].PascalType);
    if i > 0 then
      Result := Result + '; ';
    Result := Result + n + ': ' + decl;
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
// Main entry point - code generator
// -----------------------------------------------------------------------------

function GenerateABICallPascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName: TP_String;
  ParamDecl, RetDecl: TP_String;

  HeaderLines, InterfaceConstLines, InterfaceDeclLines: TPascalStringList;
  ImplLines: TPascalStringList;
  ResultLines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABICallPascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABICallPascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  TargetAppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating ABI call code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceConstLines := TPascalStringList.Create;
  InterfaceDeclLines := TPascalStringList.Create;
  ImplLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // -------------------------------------------------------------------------
    // 1. Unit header
    // -------------------------------------------------------------------------
    HeaderLines.Add('unit ' + NormalizedUnit + '_abi_call_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('// Auto-generated by pas_abi_call_generator_tool.');
    HeaderLines.Add('// Source model unit: ' + UnitName.Text + '.');
    HeaderLines.Add('// Do not edit by hand unless you know what you are doing.');
    HeaderLines.Add('//');
    HeaderLines.Add('// Wire format:');
    HeaderLines.Add('//   request  = [field1][field2]...[fieldN]');
    HeaderLines.Add('//   response = [status:UInt8][payload]');
    HeaderLines.Add('//     status = 0x00 -> success; payload is the serialised result.');
    HeaderLines.Add('//     status = 0xFF -> error; payload is a UTF-8 message.');
    HeaderLines.Add('');
    HeaderLines.Add('{$ifdef FPC}');
    HeaderLines.Add('  {$mode delphi}{$H+}');
    HeaderLines.Add('  {$MODESWITCH NestedProcVars}');
    HeaderLines.Add('  {$modeswitch advancedrecords}');
    HeaderLines.Add('  {$CODEPAGE UTF8}');
    HeaderLines.Add('{$endif}');
    HeaderLines.Add('{$R-}{$I-}{$Q-}{$B-}');
    HeaderLines.Add('');
    HeaderLines.Add('interface');
    HeaderLines.Add('');

    // -------------------------------------------------------------------------
    // 2. Interface: uses, const, type, var
    // -------------------------------------------------------------------------
    InterfaceConstLines.Add('uses');
    InterfaceConstLines.Add('  SysUtils, Classes,');
    InterfaceConstLines.Add('  lingofuse_import;');
    InterfaceConstLines.Add('');

    // -------------------------------------------------------------------------
    // 3. Typed free function declarations
    // -------------------------------------------------------------------------
    InterfaceDeclLines.Add('// ---------------------------------------------------------------------');
    InterfaceDeclLines.Add('// Typed remote call declarations');
    InterfaceDeclLines.Add('// ---------------------------------------------------------------------');
    InterfaceDeclLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        ParamDecl := BuildTypedParamDecl(Params);
        if IsFunction then
        begin
          RetDecl := ABI_Type_To_Pascal_Decl(ReturnType);
          InterfaceDeclLines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetDecl + ';');
        end
        else
          InterfaceDeclLines.Add('procedure ' + ApiName + '(' + ParamDecl + ');');
      end;
    end;

    InterfaceDeclLines.Add('');

    // -------------------------------------------------------------------------
    // 4. Implementation: per-function bodies
    // -------------------------------------------------------------------------
    ImplLines.Add('{$Region ''typed_call_''}');
    ImplLines.Add('// ---------------------------------------------------------------------');
    ImplLines.Add('// Typed remote call bodies');
    ImplLines.Add('// ---------------------------------------------------------------------');
    ImplLines.Add('');

    UsedApiNames.Clear;
    for i := 0 to High(SupportedFuncs) do
    begin
      with SupportedFuncs[i] do
      begin
        ApiName := MakeApiName(Name);
        if UsedApiNames.IndexOf(ApiName) >= 0 then
        begin
          j := 1;
          while UsedApiNames.IndexOf(ApiName + '_' + umlIntToStr(j).Text) >= 0 do
            Inc(j);
          ApiName := ApiName + '_' + umlIntToStr(j).Text;
        end;
        UsedApiNames.Add(ApiName);

        ParamDecl := BuildTypedParamDecl(Params);

        // Signature.
        if IsFunction then
        begin
          RetDecl := ABI_Type_To_Pascal_Decl(ReturnType);
          ImplLines.Add('function ' + ApiName + '(' + ParamDecl + '): ' + RetDecl + ';');
        end
        else
          ImplLines.Add('procedure ' + ApiName + '(' + ParamDecl + ');');

        ImplLines.Add('var');
        ImplLines.Add('  _Data, _Res: TDataHnd___;');
        ImplLines.Add('  _Status: uint8;');
        ImplLines.Add('  _ErrMsg: string;');
        ImplLines.Add('begin');

        // Create data handle.
        ImplLines.Add('  _Data := LF_CreateDataEx(' + #39 + ApiName.Text + #39 + ');');
        ImplLines.Add('  if _Data = nil then');
        ImplLines.Add('    raise EABI_RemoteError.Create(' + #39 + 'LF_CreateDataEx returned nil for API "' + ApiName.Text + '"' + #39 + ');');
        ImplLines.Add('');
        ImplLines.Add('  try');

        // Serialise parameters.
        for j := 0 to High(Params) do
        begin
          if Params[j].Name.Len = 0 then
            ImplLines.Add('    ' + ABI_Type_To_Write_Func(Params[j].PascalType) + '(_Data, p' + umlIntToStr(j).Text + ');')
          else
            ImplLines.Add('    ' + ABI_Type_To_Write_Func(Params[j].PascalType) + '(_Data, ' + Params[j].Name.Text + ');');
        end;

        if Length(Params) > 0 then
          ImplLines.Add('');

        // Call.
        ImplLines.Add('    _Res := LF_CallEx(ABI_TargetApp, _Data, ABI_Timeout);');
        ImplLines.Add('    if _Res = nil then');
        ImplLines.Add('      raise EABI_RemoteError.Create(' + #39 + 'ABI call "' + ApiName.Text + '" returned nil (timeout or target not found)' + #39 + ');');
        ImplLines.Add('');
        ImplLines.Add('    try');
        ImplLines.Add('      if LF_GetSize(_Res) <= 0 then');
        ImplLines.Add('        raise EABI_RemoteError.Create(' + #39 + 'ABI call "' + ApiName.Text + '" returned empty response' + #39 + ');');
        ImplLines.Add('');
        ImplLines.Add('      LF_SetPos(_Res, 0);');
        ImplLines.Add('      if not LF_ReadUInt8(_Res, _Status) then');
        ImplLines.Add('        raise EABI_RemoteError.Create(' + #39 + 'ABI call "' + ApiName.Text + '": response truncated (status byte)' + #39 + ');');
        ImplLines.Add('');
        ImplLines.Add('      if _Status <> 0 then');
        ImplLines.Add('      begin');
        ImplLines.Add('        LF_ReadString(_Res, _ErrMsg);');
        ImplLines.Add('        raise EABI_RemoteError.CreateFmt(' + #39 + 'ABI call "' + ApiName.Text + '" failed: %s' + #39 + ', [_ErrMsg]);');
        ImplLines.Add('      end;');

        // Deserialise result for functions.
        if IsFunction then
        begin
          ImplLines.Add('');
          ImplLines.Add('      if not ' + ABI_Type_To_Read_Func(ReturnType) + '(_Res, Result) then');
          ImplLines.Add('        raise EABI_RemoteError.Create(' + #39 + 'ABI call "' + ApiName.Text + '": response truncated (result)' + #39 + ');');
        end;

        ImplLines.Add('    finally');
        ImplLines.Add('      LF_FreeData(_Res);');
        ImplLines.Add('    end;');
        ImplLines.Add('  finally');
        ImplLines.Add('    LF_FreeData(_Data);');
        ImplLines.Add('  end;');
        ImplLines.Add('end;');
        ImplLines.Add('');
      end;
    end;

    ImplLines.Add('{$EndRegion ''typed_call_''}');
    ImplLines.Add('');

    // -------------------------------------------------------------------------
    // 5. Assemble
    // -------------------------------------------------------------------------
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);

    // Interface uses + const + type + var.
    ResultLines.AddStrings(InterfaceConstLines);

    ResultLines.Add('');
    ResultLines.Add('type');
    ResultLines.Add('  // Raised when a remote ABI call fails: timeout, empty response,');
    ResultLines.Add('  // or the service returned a 0xFF error status.');
    ResultLines.Add('  EABI_RemoteError = class(Exception);');
    ResultLines.Add('');
    ResultLines.Add('var');
    ResultLines.Add('  // Target LingoFuse application name. Must match DEFAULT_APP_NAME on');
    ResultLines.Add('  // the service side.');
    ResultLines.Add('  ABI_TargetApp: string = ' + #39 + TargetAppName.Text + #39 + ';');
    ResultLines.Add('  // Per-call timeout in milliseconds.');
    ResultLines.Add('  ABI_Timeout: uint64 = 5000;');
    ResultLines.Add('');

    ResultLines.AddStrings(InterfaceDeclLines);
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(ImplLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.', [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    InterfaceConstLines.Free;
    InterfaceDeclLines.Free;
    ImplLines.Free;
    UsedApiNames.Free;
    // ResultLines is returned to the caller; not freed here.
  end;
end;

// =============================================================================
// SECTION 2 - README generator
// =============================================================================
//
// This section is self-contained. It depends only on the helpers already
// present in this unit (MakeApiName, ABI_Type_To_Pascal_Decl,
// ABI_Type_To_Write_Func, ABI_Type_To_Read_Func, CollectSupportedFunctions)
// plus the standard Z-framework units already in scope.
//
// The README is organised into twelve sections:
//
//   §1  Overview
//   §2  Application scope
//   §3  Compatibility (Delphi + FPC; FPC cross-platform)
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
// can learn the call-side unit's usage model from the README alone.
// =============================================================================

// Returns the "wire size" column text for the ABI type table.
function ReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
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
function ReadmeTableCell(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar('|', '/');
  Result := Result.ReplaceChar(#13#10, ' ');
  Result := Result.TrimChar(#32#9);
  if Result.Len = 0 then
    Result := '(no description)';
end;

// Sanitise a description for use as standalone paragraph text.
function ReadmeParagraph(const S: TP_String): TP_String;
begin
  Result := S.ReplaceChar(#13, ' ');
  Result := Result.ReplaceChar(#10, ' ');
  Result := Result.TrimChar(#32#9);
end;

// Build the README for a given model.
function GenerateABICallPascalReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, TargetAppName: TP_String;

// ---------------------------------------------------------------------------
// §1. Header
// ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - Pascal ABI Call Client');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `pas_abi_call_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Call-side file**    : `' + UnitName + '_abi_call_unit.pas`');
    L.Add('> **Target App name**   : `' + TargetAppName + '`');
    L.Add('> **Exported functions**: ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> compile, deploy, or call this unit without reading the source.');
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
    L.Add('This document describes the **call-side client unit** that was');
    L.Add('generated from the Pascal unit `' + UnitName + '`. The unit is a');
    L.Add('strongly-typed wrapper around LingoFuse that talks to a matching');
    L.Add('ABI service over a compact binary wire protocol.');
    L.Add('');
    L.Add('### 1.1 What is a call-side client?');
    L.Add('');
    L.Add('A call-side client is a Pascal unit that:');
    L.Add('');
    L.Add('- exports one **free function** per API of the matching service;');
    L.Add('- each free function mirrors the signature of the original routine;');
    L.Add('- serialises its arguments with `LF_WriteXxx`, sends them through');
    L.Add('  `LF_CallEx`, and decodes the response with `LF_ReadXxx`;');
    L.Add('- raises `EABI_RemoteError` on timeout, empty response, or when the');
    L.Add('  service returns a `0xFF` error status.');
    L.Add('');
    L.Add('The unit is a **client**: it never registers APIs of its own, never');
    L.Add('calls `LF_PrepareService`, and never touches the LingoFuse main');
    L.Add('thread setup beyond what the host program provides.');
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
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Compile** the call-side unit into your client program. See §7.');
    L.Add('2. **Start the matching service** (built with the paired service');
    L.Add('   generator) and connect. See §5.');
    L.Add('3. **Call** the exported free functions. See §8 and §9.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + UnitName + '_abi_call_unit.pas` | The call-side unit (compile into your client program). |');
    L.Add('| `' + UnitName + '_abi_call_pascal.md` | This README. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use this call-side unit');
    L.Add('');
    L.Add('Use this unit when:');
    L.Add('');
    L.Add('- You need to call a **specific, known ABI service**.');
    L.Add('- The service\''s signature is **stable** and known at build time.');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- A Pascal client calling a Pascal ABI service.');
    L.Add('- A Pascal front-end calling a compute engine in another process.');
    L.Add('- A pipeline stage consuming a downstream ABI service.');
    L.Add('');
    L.Add('### 2.2 When NOT to use this call-side unit');
    L.Add('');
    L.Add('- You need to discover the API surface at runtime.');
    L.Add('- The target service\''s signature changes without a rebuild.');
    L.Add('- Parameters include complex types (records, variants, collections).');
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
    L.Add('### 3.1 Compiler support');
    L.Add('');
    L.Add('| Compiler | Minimum version | Notes |');
    L.Add('|----------|-----------------|-------|');
    L.Add('| Free Pascal (FPC) | 3.2.0 | Preferred; tested on 3.2.2. |');
    L.Add('| Delphi | 10.4 (Sydney) | Also works with 11 and 12. |');
    L.Add('');
    L.Add('The generated unit uses `{$DEFINE FPC_DELPHI_MODE}`, so the same');
    L.Add('source compiles under both compilers without modification.');
    L.Add('');
    L.Add('### 3.2 FPC cross-platform support');
    L.Add('');
    L.Add('FPC is a cross-platform compiler. This client works on every');
    L.Add('platform where the LingoFuse runtime is available.');
    L.Add('');
    L.Add('| Platform | Architecture | Status |');
    L.Add('|----------|-------------|--------|');
    L.Add('| Windows | x86_64 | Primary target |');
    L.Add('| Windows | i386 | Supported |');
    L.Add('| Linux | x86_64 | Supported |');
    L.Add('| Linux | aarch64 | Supported |');
    L.Add('| macOS | x86_64 | Supported |');
    L.Add('| macOS | aarch64 (Apple Silicon) | Supported |');
    L.Add('| FreeBSD | x86_64 | Community-tested |');
    L.Add('');
    L.Add('**Byte order note**: the ABI wire format is little-endian. Every');
    L.Add('platform listed above is little-endian, so the generated code never');
    L.Add('performs byte swapping. Big-endian platforms (PowerPC, MIPS-BE,');
    L.Add('s390x) are **not supported**.');
    L.Add('');
    L.Add('### 3.3 Runtime dependencies');
    L.Add('');
    L.Add('| Dependency | Where to get it |');
    L.Add('|------------|----------------|');
    L.Add('| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse runtime distribution |');
    L.Add('| `lingofuse_import.pas` | LingoFuse-pasAgent source tree |');
    L.Add('| `Z.Core` unit | ZNetV2/ZCore |');
    L.Add('| `z_ipc_*.dll` / `libz_ipc_*.so` | ZNetV2 binary distribution |');
    L.Add('');
    L.Add('### 3.4 Character encoding');
    L.Add('');
    L.Add('- **Source files**: UTF-8, no BOM required.');
    L.Add('- **String payloads**: UTF-8 followed by a single `#0` terminator.');
    L.Add('- **FPC**: always add `{$CODEPAGE UTF8}` when the source contains');
    L.Add('  non-ASCII literals.');
    L.Add('- **Delphi**: add `{$HIGHCHARUNICODE ON}` if you need Unicode');
    L.Add('  literals in the source.');
    L.Add('');
    L.Add('### 3.5 Threading model');
    L.Add('');
    L.Add('Every exported free function is thread-safe with respect to');
    L.Add('LingoFuse. Different threads may call different free functions in');
    L.Add('parallel. `LF_CallEx` performs its own internal synchronisation and');
    L.Add('blocks the calling thread until the response arrives or the');
    L.Add('timeout expires.');
    L.Add('');
    L.Add('**Do not call an exported free function from inside a LingoFuse');
    L.Add('callback.** Doing so deadlocks the calling worker thread. If you');
    L.Add('need to call a remote service from inside a callback, offload the');
    L.Add('call to a separate worker thread.');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §5. Wire protocol
  // ---------------------------------------------------------------------------
  procedure EmitWireProtocol;
  begin
    L.Add('## 4. Wire Protocol');
    L.Add('');
    L.Add('The call-side unit speaks the same wire format as the matching');
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
    L.Add('response = [status:UInt8][payload]');
    L.Add('```');
    L.Add('');
    L.Add('The first byte is a status code:');
    L.Add('');
    L.Add('| Status | Meaning | Payload |');
    L.Add('|--------|---------|---------|');
    L.Add('| `0x00` | Success | Serialised result (functions) or empty (procedures). |');
    L.Add('| `0xFF` | Error   | UTF-8 message, terminated by `#0`. |');
    L.Add('');
    L.Add('The exported free functions decode this automatically:');
    L.Add('');
    L.Add('- `0x00` -> returns the deserialised result (or returns normally for');
    L.Add('  procedures).');
    L.Add('- `0xFF` -> raises `EABI_RemoteError` with the decoded message.');
    L.Add('');
    L.Add('### 4.3 Encoding rules');
    L.Add('');
    L.Add('| Rule | Value |');
    L.Add('|------|-------|');
    L.Add('| Byte order | Little-endian |');
    L.Add('| Integer | Fixed-width, little-endian |');
    L.Add('| Float | IEEE 754, little-endian |');
    L.Add('| String | UTF-8 bytes terminated by a single `#0` |');
    L.Add('| Boolean | Not supported |');
    L.Add('| Record / array | Not supported |');
    L.Add('');
    L.Add('### 4.4 Call sequence');
    L.Add('');
    L.Add('```mermaid');
    L.Add('sequenceDiagram');
    L.Add('    participant C as Call-side unit');
    L.Add('    participant S as Service');
    L.Add('    C->>C: WriteXxx(a)');
    L.Add('    C->>C: WriteXxx(b)');
    L.Add('    C->>S: LF_CallEx(payload)');
    L.Add('    S-->>C: [status][payload]');
    L.Add('    C->>C: ReadUInt8 -> status');
    L.Add('    alt status == 0x00');
    L.Add('        C->>C: ReadXxx -> result');
    L.Add('    else status == 0xFF');
    L.Add('        C->>C: ReadString -> error');
    L.Add('        C->>C: raise EABI_RemoteError');
    L.Add('    end');
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
    L.Add('The call-side unit raises `EABI_RemoteError` with the decoded');
    L.Add('message. Callers should wrap their calls in a `try-except` block.');
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
    L.Add('    subgraph Client["Client process (this unit)"]');
    L.Add('        C_PREP["LF_ResetPrepare()"]');
    L.Add('        C_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, nil)"]');
    L.Add('        C_RUN["LF_PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;ApiName&gt;(args)"]');
    L.Add('        C_CATCH["try / except EABI_RemoteError"]');
    L.Add('        C_OFF["LF_ExitMainThread() + LF_Shutdown()"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Service["Service process (external)"]');
    L.Add('        S_RUN["ABI service running<br/>App = &lt;unit&gt;_abi"]');
    L.Add('    end');
    L.Add('');
    L.Add('    C_PREP --> C_CLI --> C_RUN --> C_CALL');
    L.Add('    C_CALL -. "LF_CallEx over IPC" .-> S_RUN');
    L.Add('    S_RUN -. "response" .-> C_CATCH');
    L.Add('    C_CATCH --> C_OFF');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence (client)');
    L.Add('');
    L.Add('1. `LF_ResetPrepare`');
    L.Add('2. `LF_PrepareClient(''ipc:<unit>_abi'', nil)`');
    L.Add('   (pass `nil` because the client does not expose any APIs)');
    L.Add('3. `LF_PrepareDone`');
    L.Add('');
    L.Add('The service process must be running before step 3 completes.');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The caller invokes an exported free function, e.g.');
    L.Add('   `<ApiName>(a, b)`.');
    L.Add('2. The free function creates a `TDataHnd` via `LF_CreateDataEx`.');
    L.Add('3. It writes every argument with the matching `LF_WriteXxx`.');
    L.Add('4. It calls `LF_CallEx(ABI_TargetApp, _Data, ABI_Timeout)`.');
    L.Add('5. LingoFuse routes the payload to the service and waits for the');
    L.Add('   response (blocking).');
    L.Add('6. On `nil` response: raises `EABI_RemoteError`.');
    L.Add('7. On empty response: raises `EABI_RemoteError`.');
    L.Add('8. It reads the status byte.');
    L.Add('9. On `0xFF`: reads the UTF-8 message and raises `EABI_RemoteError`.');
    L.Add('10. On `0x00`: reads the result with `LF_ReadXxx` and returns it.');
    L.Add('');
    L.Add('### 5.3 Timeout');
    L.Add('');
    L.Add('The timeout is controlled by the module-level variable');
    L.Add('`ABI_Timeout` (default `5000` ms). Change it before making calls:');
    L.Add('');
    L.Add('```pascal');
    L.Add('ABI_Timeout := 30000;  // 30 seconds');
    L.Add('```');
    L.Add('');
    L.Add('### 5.4 Target application name');
    L.Add('');
    L.Add('The target service is identified by the module-level variable');
    L.Add('`ABI_TargetApp` (default `' + TargetAppName + '`). Change it to');
    L.Add('point at a differently-named service:');
    L.Add('');
    L.Add('```pascal');
    L.Add('ABI_TargetApp := ''my_other_service_abi'';');
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
    L.Add('The call-side unit accepts the same type set as the matching');
    L.Add('service. Every exported free function\''s parameters and return');
    L.Add('type are drawn from this table.');
    L.Add('');
    L.Add('| ABI type | Pascal type | Encoder | Decoder | Wire size |');
    L.Add('|----------|-------------|---------|---------|-----------|');
    L.Add('| `integer` | `Integer` | `LF_WriteInt32` | `LF_ReadInt32` | 4 bytes |');
    L.Add('| `longint` | `LongInt` | `LF_WriteInt32` | `LF_ReadInt32` | 4 bytes |');
    L.Add('| `int64` | `Int64` | `LF_WriteInt64` | `LF_ReadInt64` | 8 bytes |');
    L.Add('| `cardinal` | `Cardinal` | `LF_WriteUInt32` | `LF_ReadUInt32` | 4 bytes |');
    L.Add('| `dword` | `DWord` | `LF_WriteUInt32` | `LF_ReadUInt32` | 4 bytes |');
    L.Add('| `longword` | `LongWord` | `LF_WriteUInt32` | `LF_ReadUInt32` | 4 bytes |');
    L.Add('| `word` | `Word` | `LF_WriteUInt16` | `LF_ReadUInt16` | 2 bytes |');
    L.Add('| `smallint` | `SmallInt` | `LF_WriteInt16` | `LF_ReadInt16` | 2 bytes |');
    L.Add('| `byte` | `Byte` | `LF_WriteUInt8` | `LF_ReadUInt8` | 1 byte |');
    L.Add('| `uint64` | `UInt64` | `LF_WriteUInt64` | `LF_ReadUInt64` | 8 bytes |');
    L.Add('| `double` | `Double` | `LF_WriteDouble` | `LF_ReadDouble` | 8 bytes |');
    L.Add('| `single` | `Single` | `LF_WriteSingle` | `LF_ReadSingle` | 4 bytes |');
    L.Add('| `extended` | `Extended` | `LF_WriteDouble` | `LF_ReadDouble` | 8 bytes |');
    L.Add('| `real` | `Real` | `LF_WriteDouble` | `LF_ReadDouble` | 8 bytes |');
    L.Add('| `string` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `ansistring` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `unicodestring` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `tpascalstring` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `tupascalstring` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `tp_string` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `pchar` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `pansichar` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('| `pwidechar` | `string` | `LF_WriteString` | `LF_ReadString` | variable + NUL |');
    L.Add('');
    L.Add('### 6.2 Unsupported types');
    L.Add('');
    L.Add('Anything not in §6.1 cannot appear in an exported function\''s');
    L.Add('signature. If the original routine used a complex type, the');
    L.Add('matching free function is **not generated at all**.');
    L.Add('');
    L.Add('Common examples of unsupported types:');
    L.Add('');
    L.Add('- `Boolean`, `WordBool`, `LongBool`');
    L.Add('- `Variant`, `OleVariant`');
    L.Add('- Arrays, records, classes, interfaces');
    L.Add('- Enumerations, sets, generics');
    L.Add('- Pointers, function pointers');
    L.Add('- `Currency`, `Comp`, `TDateTime`');
    L.Add('');
    L.Add('**Workaround**: serialise the complex value into a `string` first');
    L.Add('(JSON or a custom binary format) on the caller side, then call a');
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
    L.Add('The exported free functions use `LF_WriteString` and');
    L.Add('`LF_ReadString` for string parameters and return values.');
    L.Add('`LF_WriteString` always appends a single `#0` byte. `LF_ReadString`');
    L.Add('scans forward until it finds that byte.');
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
    L.Add('Place the generated call-side unit in your client project');
    L.Add('directory, together with the LingoFuse runtime.');
    L.Add('');
    L.Add('```');
    L.Add('my_abi_client/');
    L.Add('  ' + UnitName + '_abi_call_unit.pas         <- generated (described here)');
    L.Add('  ' + UnitName + '_client.lpr                <- your client entry point');
    L.Add('  ZNetV2/');
    L.Add('    ZCore/');
    L.Add('      Z.Core.pas');
    L.Add('    lingofuse_import.pas');
    L.Add('    lingofuse_helper.pas');
    L.Add('    z_ipc_64.dll                              <- Windows');
    L.Add('    libz_ipc_64.so                            <- Linux');
    L.Add('  LingoFuse64.dll                             <- Windows');
    L.Add('  liblingofuse.so                             <- Linux');
    L.Add('  liblingofuse.dylib                          <- macOS');
    L.Add('```');
    L.Add('');
    L.Add('The matching service process must be running independently and');
    L.Add('must expose the App name `' + TargetAppName + '`.');
    L.Add('');
    L.Add('### 7.2 FPC build');
    L.Add('');
    L.Add('```bash');
    L.Add('fpc -FuZNetV2 -FuZNetV2/ZCore ' + UnitName + '_client.lpr');
    L.Add('```');
    L.Add('');
    L.Add('Both `-Fu` paths are required. Missing either one causes "Can''t');
    L.Add('find unit Z.Core" or "Can''t find unit lingofuse_import".');
    L.Add('');
    L.Add('### 7.3 Delphi build');
    L.Add('');
    L.Add('1. Add the `.pas` file to your Delphi project.');
    L.Add('2. Add `ZNetV2` and `ZNetV2\\ZCore` to **Project Options -> Unit');
    L.Add('   Directories**.');
    L.Add('3. Set the linker search path to include the directory that holds');
    L.Add('   `LingoFuse64.dll`.');
    L.Add('4. Build.');
    L.Add('');
    L.Add('### 7.4 Startup order');
    L.Add('');
    L.Add('The service must be running before the client calls');
    L.Add('`LF_PrepareDone`. If the client starts first, retry or poll:');
    L.Add('');
    L.Add('```pascal');
    L.Add('while not LF_CheckAppEx(ABI_TargetApp) do');
    L.Add('  TThread.Sleep(100);');
    L.Add('```');
    L.Add('');
    L.Add('### 7.5 Runtime files');
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
    L.Add('1. `LF_ExitMainThread`');
    L.Add('2. `LF_Shutdown`');
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
    L.Add('Save it next to the generated unit and compile with FPC or Delphi.');
    L.Add('');
    L.Add('### 8.1 Client program (`' + UnitName + '_client.lpr`)');
    L.Add('');
    L.Add('```pascal');
    L.Add('program ' + UnitName + '_client;');
    L.Add('');
    L.Add('{$mode objfpc}{$H+}');
    L.Add('{$CODEPAGE UTF8}');
    L.Add('');
    L.Add('uses');
    L.Add('  {$IFDEF UNIX}');
    L.Add('  cthreads,');
    L.Add('  {$ENDIF}');
    L.Add('  SysUtils, Classes,');
    L.Add('  Z.Core,');
    L.Add('  lingofuse_import,');
    L.Add('  ' + UnitName + '_abi_call_unit;');
    L.Add('');
    L.Add('begin');
    L.Add('  WriteLn(''=== ' + UnitName + ' ABI client ==='');');
    L.Add('');
    L.Add('  LF_ResetPrepare;');
    L.Add('  LF_PrepareClient(''ipc:' + TargetAppName + ''', nil);');
    L.Add('');
    L.Add('  if LF_PrepareDone <> 1 then');
    L.Add('  begin');
    L.Add('    WriteLn(''[FATAL] LF_PrepareDone failed'');');
    L.Add('    Halt(1);');
    L.Add('  end;');
    L.Add('');
    L.Add('  try');
    L.Add('    // Replace with actual calls to the generated functions.');
    L.Add('    // Example:');
    L.Add('    //   WriteLn(''Add(3, 4) = '', Add(3, 4));');
    L.Add('  except');
    L.Add('    on E: EABI_RemoteError do');
    L.Add('      WriteLn(''[ERROR] '', E.Message);');
    L.Add('  end;');
    L.Add('');
    L.Add('  LF_ExitMainThread;');
    L.Add('  LF_Shutdown;');
    L.Add('end.');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Running the test');
    L.Add('');
    L.Add('Make sure the matching service process is running first. Then:');
    L.Add('');
    L.Add('```bash');
    L.Add('./' + UnitName + '_client');
    L.Add('```');
    L.Add('');
    L.Add('### 8.3 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path:');
    L.Add('');
    L.Add('1. Stop the service process.');
    L.Add('2. Run the client again.');
    L.Add('3. The free function raises `EABI_RemoteError` with a timeout or');
    L.Add('   "target not found" message.');
    L.Add('');
    L.Add('### 8.4 Testing before the service exists');
    L.Add('');
    L.Add('To test the call-side unit without a running service, use the');
    L.Add('in-process callback path directly:');
    L.Add('');
    L.Add('```pascal');
    L.Add('// Register the matching callback on a local App, then call');
    L.Add('// LF_LocalCall instead of LF_CallEx. This exercises the same');
    L.Add('// serialisation / deserialisation logic.');
    L.Add('```');
    L.Add('');
    L.Add('For unit-level testing of the serialisation code, use');
    L.Add('`LF_WriteXxx` / `LF_ReadXxx` directly against a `TDataHnd`');
    L.Add('created with `LF_CreateDataEx`.');
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
    DeclLine: TP_String;
    CallExpr: TP_String;
    PName: TP_String;
  begin
    L.Add('## 9. API Reference');
    L.Add('');

    if Length(SupportedFuncs) = 0 then
    begin
      L.Add('> **WARNING: this call-side unit exports no functions.**');
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
    L.Add('Every function is a **free function** declared in the');
    L.Add('`interface` section of the generated unit. Call them directly from');
    L.Add('your client code.');
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
      ShortDesc := ReadmeTableCell(ReadmeParagraph(TP_String(Func.Comment)));
      if ShortDesc.Len > 60 then
        ShortDesc := ShortDesc.GetString(1, 61) + '...';

      if Func.IsFunction then
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | function | ' + umlIntToStr(Length(Func.Params)).Text +
          ' | `' + ABI_Type_To_Pascal_Decl(Func.ReturnType) + '` | ' + ShortDesc + ' |'
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
      FuncDesc := ReadmeParagraph(TP_String(Func.Comment));

      // Build the reconstructed declaration line.
      if Func.IsFunction then
        DeclLine := 'function ' + ApiNm + '('
      else
        DeclLine := 'procedure ' + ApiNm + '(';
      for jj := 0 to High(Func.Params) do
      begin
        if jj > 0 then
          DeclLine := DeclLine + '; ';
        DeclLine := DeclLine + Func.Params[jj].Name.Text + ': ' + ABI_Type_To_Pascal_Decl(Func.Params[jj].PascalType);
      end;
      DeclLine := DeclLine + ')';
      if Func.IsFunction then
        DeclLine := DeclLine + ': ' + ABI_Type_To_Pascal_Decl(Func.ReturnType);
      DeclLine := DeclLine + ';';

      // Build a call expression for the example.
      CallExpr := ApiNm + '(';
      for jj := 0 to High(Func.Params) do
      begin
        if jj > 0 then
          CallExpr := CallExpr + ', ';
        if Func.Params[jj].PascalType.Same('string') or Func.Params[jj].PascalType.Same('ansistring') or
          Func.Params[jj].PascalType.Same('unicodestring') or Func.Params[jj].PascalType.Same('tpascalstring') or
          Func.Params[jj].PascalType.Same('tupascalstring') or Func.Params[jj].PascalType.Same('tp_string') or
          Func.Params[jj].PascalType.Same('pchar') or Func.Params[jj].PascalType.Same('pansichar') or Func.Params[jj].PascalType.Same('pwidechar') then
          CallExpr := CallExpr + '''hello'''
        else if Func.Params[jj].PascalType.Same('double') or Func.Params[jj].PascalType.Same('single') or
          Func.Params[jj].PascalType.Same('extended') or Func.Params[jj].PascalType.Same('real') then
          CallExpr := CallExpr + '0.0'
        else
          CallExpr := CallExpr + '0';
      end;
      CallExpr := CallExpr + ')';

      L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
      L.Add('');
      L.Add('- **Declaration**: `' + DeclLine + '`');
      if Func.IsFunction then
        L.Add('- **Kind**: function; returns `' + ABI_Type_To_Pascal_Decl(Func.ReturnType) + '`')
      else
        L.Add('- **Kind**: procedure');
      L.Add('- **Raises**: `EABI_RemoteError` on timeout, empty response, or `0xFF` status');
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
        L.Add('| # | Name | Pascal type | ABI type | Encoder | Wire size |');
        L.Add('|---|------|-------------|----------|---------|-----------|');
        for jj := 0 to High(Func.Params) do
        begin
          PName := Func.Params[jj].Name.Text;
          if PName = '' then
            PName := '<unnamed>';
          RowStr := '| ' + umlIntToStr(jj + 1).Text + ' | `' + PName + '`' + ' | `' + ABI_Type_To_Pascal_Decl(Func.Params[jj].PascalType) +
            '`' + ' | `' + Func.Params[jj].PascalType + '`' + ' | `' + ABI_Type_To_Write_Func(Func.Params[jj].PascalType) +
            '`' + ' | ' + ReadmeWireSizeText(Func.Params[jj].PascalType) + ' |';
          L.Add(RowStr);
        end;
        L.Add('');
      end;

      // Call example
      L.Add('#### Call example');
      L.Add('');
      L.Add('```pascal');
      L.Add('try');
      if Func.IsFunction then
        L.Add('  var result := ' + CallExpr + ';')
      else
        L.Add('  ' + CallExpr + ';');
      L.Add('except');
      L.Add('  on E: EABI_RemoteError do');
      L.Add('    WriteLn(''Call failed: '', E.Message);');
      L.Add('end;');
      L.Add('```');
      L.Add('');
      L.Add('(FPC 3.2 in `{$mode objfpc}` does not allow inline `var` in a');
      L.Add('`begin` block; declare `result` at the top of the enclosing');
      L.Add('procedure.)');
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
    L.Add('| `LF_PrepareDone` returns 0 | Service not running | Start the service before the client, or poll `LF_CheckAppEx`. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | App name mismatch | Check `ABI_TargetApp` and the service\''s `DEFAULT_APP_NAME`. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | Timeout too short | Increase `ABI_Timeout`. |');
    L.Add('| `EABI_RemoteError: "input truncated"` | Service rejected the request | Verify the client and service were generated from the same model. |');
    L.Add('| `EABI_RemoteError: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| `EABI_RemoteError` on every call | Service App not registered | Verify the service is running and registered. |');
    L.Add('| Deadlock inside a callback | Calling a free function inside a LingoFuse callback | Offload the call to a separate worker thread. |');
    L.Add('| `LF_CreateDataEx returned nil` | Out of memory or LingoFuse not initialised | Verify `LF_PrepareDone` was called. |');
    L.Add('| Client hangs forever | Timeout set to 0 | Set `ABI_Timeout` to a positive value. |');
    L.Add('');
    L.Add('### 10.2 Verifying the service is reachable');
    L.Add('');
    L.Add('Before making a call:');
    L.Add('');
    L.Add('```pascal');
    L.Add('if LF_CheckMainThread = 0 then');
    L.Add('  WriteLn(''Main thread is not running'');');
    L.Add('');
    L.Add('if not LF_CheckAppEx(ABI_TargetApp) then');
    L.Add('  WriteLn(''Target service is not registered'');');
    L.Add('```');
    L.Add('');
    L.Add('### 10.3 Inspecting the raw request and response');
    L.Add('');
    L.Add('To dump the raw bytes of a `TDataHnd` for debugging:');
    L.Add('');
    L.Add('```pascal');
    L.Add('var');
    L.Add('  p: PByte;');
    L.Add('  sz, i: NativeInt;');
    L.Add('begin');
    L.Add('  sz := LF_GetSize(Res);');
    L.Add('  p := PByte(LF_GetBuffer(Res));');
    L.Add('  for i := 0 to sz - 1 do');
    L.Add('  begin');
    L.Add('    Write(IntToHex(p^, 2), '' '');');
    L.Add('    Inc(p);');
    L.Add('  end;');
    L.Add('  WriteLn;');
    L.Add('end;');
    L.Add('```');
    L.Add('');
    L.Add('### 10.4 Adjusting the timeout');
    L.Add('');
    L.Add('Increase `ABI_Timeout` when calling a slow service:');
    L.Add('');
    L.Add('```pascal');
    L.Add('ABI_Timeout := 30000;  // 30 seconds');
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
    L.Add('| 1 | What does this call-side unit export? | §1 |');
    L.Add('| 2 | When should I use this client instead of a JSON client? | §2 |');
    L.Add('| 3 | Which compilers and platforms are supported? | §3 |');
    L.Add('| 4 | What is the wire format of a request and a response? | §4 |');
    L.Add('| 5 | What is the client startup sequence? | §5.1 |');
    L.Add('| 6 | How is the target App name configured? | §5.4 |');
    L.Add('| 7 | How is the timeout configured? | §5.3 |');
    L.Add('| 8 | Which Pascal types are accepted? | §6.1 |');
    L.Add('| 9 | Where do I place the DLLs at runtime? | §7.5 |');
    L.Add('| 10 | How do I compile the client with FPC? | §7.2 |');
    L.Add('| 11 | What is the shutdown order on the client side? | §7.6 |');
    L.Add('| 12 | How do I invoke a specific API? | §9 |');
    L.Add('| 13 | How do I handle a failed call? | §4.5, §9 |');
    L.Add('| 14 | What should I do if the client hangs forever? | §10.4 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('call-side unit.');
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
    L.Add('| ZNetV2 repository | LingoFuse runtime bindings |');
    L.Add('| ZNetV2/ZCore | Core infrastructure units |');
    L.Add('| `lingofuse_import.pas` | Low-level C ABI declarations |');
    L.Add('| `pas_abi_service_generator_tool.pas` | Paired service-side generator |');
    L.Add('| `py_abi_call_generator_tool.pas` | Python call-side generator |');
    L.Add('| `cpp_abi_call_generator_tool.pas` | C++ call-side generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `pas_abi_call_generator_tool.pas`');
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

  Log(PFormat('GenerateABICallPascalReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABICallPascalReadme: %d valid APIs', [Length(SupportedFuncs)]));

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

  Log(PFormat('GenerateABICallPascalReadme: %d lines generated', [L.Count]));
end;

end.
