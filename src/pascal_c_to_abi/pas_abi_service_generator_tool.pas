unit pas_abi_service_generator_tool;


// pas_abi_service_generator_tool - LingoFuse ABI Service Provider Generator

// This unit consumes a TPascal_Func_Model (built with Typ_Normalize_Func =
// tnf_ABI) and produces a complete Pascal unit that can be compiled into a
// LingoFuse ABI service provider, plus a Markdown README that documents
// the generated service for both human engineers and AI assistants.

// The generated unit exposes:
//   const DEFAULT_APP_NAME, DEFAULT_APP_DESC;
//   procedure RegisterAllABIAPIs(App: TAppHnd___);
//   function  CreateAndRegisterABIApp: TAppHnd___;

// Wire protocol (both directions):
//   request  = [field1][field2]...[fieldN]
//   response = [status:UInt8][payload]
//     status = 0x00 -> success; payload is the serialised result (functions)
//                      or empty (procedures).
//     status = 0xFF -> error; payload is a LF_WriteString UTF-8 message.

// Type mapping (from Normalize_ABI_Type in Z.Pascal_Func_Model):
//   integer / longint             -> LF_WriteInt32  / LF_ReadInt32
//   int64                         -> LF_WriteInt64  / LF_ReadInt64
//   cardinal / dword / longword   -> LF_WriteUInt32 / LF_ReadUInt32
//   word                          -> LF_WriteUInt16 / LF_ReadUInt16
//   smallint                      -> LF_WriteInt16  / LF_ReadInt16
//   byte                          -> LF_WriteUInt8  / LF_ReadUInt8
//   uint64                        -> LF_WriteUInt64 / LF_ReadUInt64
//   double / extended / real      -> LF_WriteDouble / LF_ReadDouble
//   single                        -> LF_WriteSingle / LF_ReadSingle
//   string / PChar family         -> LF_WriteString / LF_ReadString

// Generated unit layout:
//   unit <unitname>_abi_service_unit;
//   interface
//     const  DEFAULT_APP_NAME, DEFAULT_APP_DESC;
//     procedure RegisterAllABIAPIs(App: TAppHnd___);
//     function  CreateAndRegisterABIApp: TAppHnd___;
//   implementation
//     {$Region 'internal_call_'}
//     {$Region 'callback_'}
//     {$Region 'registration_'}

// The user is expected to:
//   1. Add the original unit that holds the real functions to the
//      implementation uses clause of the generated unit.
//   2. Fill in each internal_call_<api> stub with a call to the real
//      function. If the body must run on the main thread, uncomment the
//      synchronised variant that is provided inside the block comments.
//   3. In the host program, follow the standard LingoFuse service setup:
//        LF_ResetPrepare;
//        LF_PrepareService('<endpoint>', '<endpoint>');
//        App := CreateAndRegisterABIApp;
//        LF_PrepareClient('<endpoint>', App);
//        if LF_PrepareDone <> 1 then Halt(1);
//        // run...
//        LF_ExitMainThread;
//        LF_FreeApp(App);
//        LF_Shutdown;

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


  // GenerateABIServicePascalCode - main entry point.

  // Model must be built with Typ_Normalize_Func = tnf_ABI. The returned list
  // is owned by the caller and must be released with DisposeObject.

function GenerateABIServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;

// GenerateABIServicePascalReadme - generate the user-facing README.
//
// The returned list contains the lines of a Markdown document that
// explains deployment, testing, compatibility, the wire protocol,
// the ABI type mapping, and every exposed API. The document is
// written so that both human readers and AI assistants can learn
// the service's usage model from the README alone.
//
// The caller owns the returned list and must release it with
// DisposeObject.

function GenerateABIServicePascalReadme(Model: TPascal_Func_Model): TPascalStringList;

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
    DoStatus('[pas_abi_service_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[pas_abi_service_generator] %s', [PFormat(Fmt, Args)]);
end;

// -----------------------------------------------------------------------------
// ABI type mapping
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

function ABI_Type_Default(const T: TP_String): TP_String;
begin
  if T.Same('integer') or T.Same('int64') or T.Same('cardinal') or T.Same('longint') or T.Same('dword') or T.Same('word') or
    T.Same('smallint') or T.Same('byte') or T.Same('uint64') or T.Same('longword') then
    Result := '0'
  else if T.Same('double') or T.Same('single') or T.Same('extended') or T.Same('real') then
    Result := '0.0'
  else if T.Same('string') or T.Same('ansistring') or T.Same('unicodestring') or T.Same('tpascalstring') or T.Same('tupascalstring') or
    T.Same('tp_string') or T.Same('pchar') or T.Same('pansichar') or T.Same('pwidechar') then
    Result := #39#39
  else
    Result := '0';
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

function MakeCallbackName(const FuncName: TP_String): TP_String;
begin
  Result := 'Callback_' + MakeApiName(FuncName);
end;

function MakeInternalCallName(const ApiName: TP_String): TP_String;
begin
  Result := 'internal_call_' + ApiName;
end;


// Produce a Pascal string literal from a TP_String. Uses the Z.Parsing
// helper, which correctly handles embedded single quotes and line breaks.

function PascalStrLit(const S: TP_String): TP_String;
begin
  Result := TTextParsing.Translate_Text_To_Pascal_Decl(S);
end;

// -----------------------------------------------------------------------------
// Comment description extraction

// Operates on UTF-16 TP_String directly. Strips comment markers, Doxygen
// tag lines, and continuation '*' markers. Only the first non-empty,
// non-Doxygen line is returned, capped at 200 characters.

// The result is later used ONLY as a string literal argument to
// LF_RegisterCallEx, never as a comment, so any embedded characters are
// safe with respect to comment nesting.
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

function BuildCallArgList(const Params: TParamArray): TP_String;
var
  i: integer;
  n: TP_String;
begin
  Result := '';
  for i := 0 to High(Params) do
  begin
    if Params[i].Name.Len = 0 then
      n := 'p' + umlIntToStr(i)
    else
      n := Params[i].Name;
    if i > 0 then
      Result := Result + ', ';
    Result := Result + n;
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

function GenerateABIServicePascalCode(Model: TPascal_Func_Model): TPascalStringList;
var
  i, j: integer;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;
  UsedApiNames: TPascalStringList;
  ApiName, CallbackName, InternalCallName, tmp: TP_String;
  RetDecl: TP_String;
  Description: TP_String;
  ParamDecl, CallArgs: TP_String;

  HeaderLines, InterfaceLines, interface_internal_func, UsesLines: TPascalStringList;
  InternalCallLines, CallbackLines, RegistrationLines: TPascalStringList;
  ResultLines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateABIServicePascalCode: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateABIServicePascalCode: UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);
  AppName := NormalizedUnit + '_abi';

  Log(PFormat('Generating ABI service code for unit "%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  if Length(SupportedFuncs) = 0 then
    Log('No supported routines; generating an empty skeleton.');

  HeaderLines := TPascalStringList.Create;
  InterfaceLines := TPascalStringList.Create;
  interface_internal_func := TPascalStringList.Create;
  UsesLines := TPascalStringList.Create;
  InternalCallLines := TPascalStringList.Create;
  CallbackLines := TPascalStringList.Create;
  RegistrationLines := TPascalStringList.Create;
  UsedApiNames := TPascalStringList.Create;
  ResultLines := nil;

  try
    // -------------------------------------------------------------------------
    // 1. Unit header
    // -------------------------------------------------------------------------
    HeaderLines.Add('unit ' + NormalizedUnit + '_abi_service_unit;');
    HeaderLines.Add('');
    HeaderLines.Add('// Auto-generated by pas_abi_service_generator_tool.');
    HeaderLines.Add('// Source model unit: ' + UnitName.Text + '.');
    HeaderLines.Add('// Do not edit by hand unless you know what you are doing.');
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
    // 2. Interface section
    //
    // Z.Core is included so that the optional synchronised body of each
    // internal_call_* stub (which uses TCompute.Sync) compiles as soon as
    // the user uncomments it.
    // -------------------------------------------------------------------------
    InterfaceLines.Add('uses');
    InterfaceLines.Add('  SysUtils, Classes,');
    InterfaceLines.Add('  Z.Core,');
    InterfaceLines.Add('  lingofuse_import;');
    InterfaceLines.Add('');
    InterfaceLines.Add('const');
    InterfaceLines.Add('  DEFAULT_APP_NAME: string = ' + PascalStrLit(AppName) + ';');
    InterfaceLines.Add('  DEFAULT_APP_DESC: string = ' + PascalStrLit('ABI service for ' + UnitName) + ';');
    InterfaceLines.Add('');
    InterfaceLines.Add('var');
    InterfaceLines.Add('  DEBUG_LOG: boolean = True;');
    InterfaceLines.Add('');
    InterfaceLines.Add('// Register every generated Call API on the given LingoFuse app handle.');
    InterfaceLines.Add('procedure RegisterAllABIAPIs(App: TAppHnd___);');
    InterfaceLines.Add('');
    InterfaceLines.Add('// Create a new LingoFuse app and register every generated Call API.');
    InterfaceLines.Add('// The caller owns the returned handle and must call LF_FreeApp on it.');
    InterfaceLines.Add('function CreateAndRegisterABIApp: TAppHnd___;');
    InterfaceLines.Add('');

    // -------------------------------------------------------------------------
    // 3. Implementation uses (kept as a hint block for the user)
    // -------------------------------------------------------------------------
    UsesLines.Add('// ---------------------------------------------------------------------');
    UsesLines.Add('// TODO: add the unit that holds the real implementations, for example:');
    UsesLines.Add('//   uses MyUnit;');
    UsesLines.Add('// If the original declarations came from a C header, provide your own');
    UsesLines.Add('// Pascal wrappers in a unit and add it to the clause above.');
    UsesLines.Add('// ---------------------------------------------------------------------');
    UsesLines.Add('');

    // -------------------------------------------------------------------------
    // 4. internal_call_<api> stubs
    //
    // Each stub is emitted as:
    //
    //   function internal_call_<api>(<params>): <ret>;
    //   (*
    //   {$IFDEF FPC}
    //     procedure Do_Sync___();
    //     begin
    //       // Result := <RealFunc>(<args>);
    //     end;
    //   {$ELSE FPC}
    //   var temp_: <ret>;
    //   {$ENDIF FPC}
    //   *)
    //   begin
    //     Result := <default>;
    //     // Result := <RealFunc>(<args>);
    //   (*
    //   {$IFDEF FPC}
    //     TCompute.Sync(Do_Sync___);
    //   {$ELSE FPC}
    //     TCompute.Sync(procedure()
    //     begin
    //       // temp_ := <RealFunc>(<args>);
    //     end);
    //     Result := temp_;
    //   {$ENDIF FPC}
    //   *)
    //   end;
    //
    // The synchronised variant is commented out so it does not alter the
    // default worker-thread execution path. Users who need main-thread
    // execution uncomment both block comments and the two `//` lines.
    // -------------------------------------------------------------------------
    InternalCallLines.Add('{$Region ''internal_call_''}');
    InternalCallLines.Add('// ---------------------------------------------------------------------');
    InternalCallLines.Add('// Internal call stubs. Each stub mirrors one original routine.');
    InternalCallLines.Add('//');
    InternalCallLines.Add('// The default body runs on a LingoFuse worker thread. To marshal the');
    InternalCallLines.Add('// body onto the main thread, uncomment the two block comments and');
    InternalCallLines.Add('// the `//` lines they contain.');
    InternalCallLines.Add('//');
    InternalCallLines.Add('// Replace each TODO comment with a call to the real function, for');
    InternalCallLines.Add('// example:  Result := MyUnit.Add(a, b);');
    InternalCallLines.Add('// ---------------------------------------------------------------------');
    InternalCallLines.Add('');

    interface_internal_func.Add('// ---------------------------------------------------------------------');
    interface_internal_func.Add('// Internal call declarations.');
    interface_internal_func.Add('// ---------------------------------------------------------------------');

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

        InternalCallName := MakeInternalCallName(ApiName);
        ParamDecl := BuildTypedParamDecl(Params);
        CallArgs := BuildCallArgList(Params);
        RetDecl := ABI_Type_To_Pascal_Decl(ReturnType);

        // Signature declaration.
        if IsFunction then
          tmp := 'function ' + InternalCallName + '(' + ParamDecl + '): ' + RetDecl + ';'
        else
          tmp := 'procedure ' + InternalCallName + '(' + ParamDecl + ');';
        InternalCallLines.Add(tmp);
        interface_internal_func.Add(tmp);

        // Block comment 1: synchronised helper declaration + temp_ variable.
        InternalCallLines.Add('(*');
        InternalCallLines.Add('{$IFDEF FPC}');
        InternalCallLines.Add('  procedure Do_Sync___();');
        InternalCallLines.Add('  begin');
        if IsFunction then
          InternalCallLines.Add('    // Result := ' + Name.Text + '(' + CallArgs.Text + ');')
        else
          InternalCallLines.Add('    // ' + Name.Text + '(' + CallArgs.Text + ');');
        InternalCallLines.Add('  end;');
        InternalCallLines.Add('{$ELSE FPC}');
        if IsFunction then
          InternalCallLines.Add('var temp_: ' + RetDecl + ';')
        else
          InternalCallLines.Add('  // (no temp_ needed for procedures)');
        InternalCallLines.Add('{$ENDIF FPC}');
        InternalCallLines.Add('*)');

        // Body.
        InternalCallLines.Add('begin');
        if IsFunction then
          InternalCallLines.Add('  Result := ' + ABI_Type_Default(ReturnType) + ';');
        if IsFunction then
          InternalCallLines.Add('  // Result := ' + Name.Text + '(' + CallArgs.Text + ');')
        else
          InternalCallLines.Add('  // ' + Name.Text + '(' + CallArgs.Text + ');');

        // Block comment 2: synchronised invocation.
        InternalCallLines.Add('(*');
        InternalCallLines.Add('{$IFDEF FPC}');
        InternalCallLines.Add('  TCompute.Sync(Do_Sync___);');
        InternalCallLines.Add('{$ELSE FPC}');
        InternalCallLines.Add('  TCompute.Sync(procedure()');
        InternalCallLines.Add('  begin');
        if IsFunction then
          InternalCallLines.Add('    // temp_ := ' + Name.Text + '(' + CallArgs.Text + ');')
        else
          InternalCallLines.Add('    // ' + Name.Text + '(' + CallArgs.Text + ');');
        InternalCallLines.Add('  end);');
        if IsFunction then
          InternalCallLines.Add('  Result := temp_;');
        InternalCallLines.Add('{$ENDIF FPC}');
        InternalCallLines.Add('*)');

        InternalCallLines.Add('end;');
        InternalCallLines.Add('');
      end;
    end;

    InternalCallLines.Add('{$EndRegion ''internal_call_''}');
    InternalCallLines.Add('');

    // -------------------------------------------------------------------------
    // 5. cdecl callbacks
    // -------------------------------------------------------------------------
    CallbackLines.Add('{$Region ''callback_''}');
    CallbackLines.Add('// ---------------------------------------------------------------------');
    CallbackLines.Add('// cdecl callbacks. Registered with LF_RegisterCallEx.');
    CallbackLines.Add('// Wire format (see unit header):');
    CallbackLines.Add('//   request  = [field1][field2]...[fieldN]');
    CallbackLines.Add('//   response = [status:UInt8][payload]');
    CallbackLines.Add('//     status = 0x00 success; 0xFF error followed by an LF_WriteString');
    CallbackLines.Add('//     encoded UTF-8 message.');
    CallbackLines.Add('// ---------------------------------------------------------------------');
    CallbackLines.Add('');

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

        CallbackName := MakeCallbackName(Name) + '_' + ApiName;
        InternalCallName := MakeInternalCallName(ApiName);
        CallArgs := BuildCallArgList(Params);

        CallbackLines.Add('// ---- ' + Name.Text + ' (API: ' + ApiName.Text + ') ----');
        CallbackLines.Add('procedure ' + CallbackName + '(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;');

        if (Length(Params) > 0) or IsFunction then
          CallbackLines.Add('var');
        for j := 0 to High(Params) do
        begin
          if Params[j].Name.Len = 0 then
            CallbackLines.Add('  p' + umlIntToStr(j).Text + ': ' + ABI_Type_To_Pascal_Decl(Params[j].PascalType) + ';')
          else
            CallbackLines.Add('  ' + Params[j].Name.Text + ': ' + ABI_Type_To_Pascal_Decl(Params[j].PascalType) + ';');
        end;

        if IsFunction then
          CallbackLines.Add('  ret: ' + ABI_Type_To_Pascal_Decl(ReturnType) + ';');
        CallbackLines.Add('begin');

        // Deserialise parameters.
        for j := 0 to High(Params) do
        begin
          if Params[j].Name.Len = 0 then
            CallbackLines.Add('  if not ' + ABI_Type_To_Read_Func(Params[j].PascalType) + '(_In___, p' + umlIntToStr(j).Text + ') then')
          else
            CallbackLines.Add('  if not ' + ABI_Type_To_Read_Func(Params[j].PascalType) + '(_In___, ' + Params[j].Name.Text + ') then');
          CallbackLines.Add('  begin');
          CallbackLines.Add('    LF_WriteUInt8(_Out___, $FF);');
          CallbackLines.Add('    LF_WriteString(_Out___, ''input truncated'');');
          CallbackLines.Add('    Exit;');
          CallbackLines.Add('  end;');
        end;

        if Length(Params) > 0 then
          CallbackLines.Add('');

        // Invoke the stub and serialise the result.
        CallbackLines.Add('  try');
        if IsFunction then
          CallbackLines.Add('    ret := ' + InternalCallName + '(' + CallArgs.Text + ');')
        else
          CallbackLines.Add('    ' + InternalCallName + '(' + CallArgs.Text + ');');
        CallbackLines.Add('  except');
        CallbackLines.Add('    on E: Exception do');
        CallbackLines.Add('    begin');
        CallbackLines.Add('      LF_WriteUInt8(_Out___, $FF);');
        CallbackLines.Add('      LF_WriteString(_Out___, E.Message);');
        CallbackLines.Add('      Exit;');
        CallbackLines.Add('    end;');
        CallbackLines.Add('  end;');
        CallbackLines.Add('');
        CallbackLines.Add('  LF_WriteUInt8(_Out___, $00);');
        if IsFunction then
          CallbackLines.Add('  ' + ABI_Type_To_Write_Func(ReturnType) + '(_Out___, ret);');
        CallbackLines.Add('end;');
        CallbackLines.Add('');
      end;
    end;

    CallbackLines.Add('{$EndRegion ''callback_''}');
    CallbackLines.Add('');

    // -------------------------------------------------------------------------
    // 6. Registration
    // -------------------------------------------------------------------------
    RegistrationLines.Add('{$Region ''registration_''}');
    RegistrationLines.Add('procedure RegisterAllABIAPIs(App: TAppHnd___);');
    RegistrationLines.Add('begin');

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

        CallbackName := MakeCallbackName(Name) + '_' + ApiName;
        Description := GetFullDescription(Comment);
        if Description.Len = 0 then
          Description := 'ABI api for ' + Name;

        RegistrationLines.Add('  LF_RegisterCallEx(App, ' + PascalStrLit(ApiName) + ', ' + PascalStrLit(Description) + ', nil, @' + CallbackName + ');');
      end;
    end;

    RegistrationLines.Add('end;');
    RegistrationLines.Add('');
    RegistrationLines.Add('function CreateAndRegisterABIApp: TAppHnd___;');
    RegistrationLines.Add('begin');
    RegistrationLines.Add('  Result := LF_CreateAppEx(DEFAULT_APP_NAME, DEFAULT_APP_DESC);');
    RegistrationLines.Add('  if Result <> nil then');
    RegistrationLines.Add('    RegisterAllABIAPIs(Result);');
    RegistrationLines.Add('end;');
    RegistrationLines.Add('{$EndRegion ''registration_''}');
    RegistrationLines.Add('');

    // -------------------------------------------------------------------------
    // 7. Assemble
    // -------------------------------------------------------------------------
    ResultLines := TPascalStringList.Create;
    ResultLines.AddStrings(HeaderLines);
    ResultLines.AddStrings(InterfaceLines);
    ResultLines.Add('');
    ResultLines.AddStrings(interface_internal_func);
    ResultLines.Add('');
    ResultLines.Add('implementation');
    ResultLines.Add('');
    ResultLines.AddStrings(UsesLines);
    ResultLines.AddStrings(InternalCallLines);
    ResultLines.AddStrings(CallbackLines);
    ResultLines.AddStrings(RegistrationLines);
    ResultLines.Add('end.');

    Result := ResultLines;
    Log(PFormat('Generated %d lines, %d supported routines.', [ResultLines.Count, Length(SupportedFuncs)]));

  finally
    HeaderLines.Free;
    InterfaceLines.Free;
    interface_internal_func.Free;
    UsesLines.Free;
    InternalCallLines.Free;
    CallbackLines.Free;
    RegistrationLines.Free;
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
// ABI_Type_To_Write_Func, CollectSupportedFunctions, GetFullDescription)
// plus the standard Z-framework units already in scope.
//
// The README is organised into twelve sections:
//
//   §1  Overview
//   §2  Application scope
//   §3  Compatibility (Delphi + FPC; FPC cross-platform)
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
// can learn the service's usage model from the README alone.
// =============================================================================

// Returns the "wire size" column text for the ABI type table.
function ReadmeWireSizeText(const ABI_Type: TP_String): TP_String;
begin
  if ABI_Type.Same('byte') then
    Result := '1 byte'
  else if ABI_Type.Same('word') or ABI_Type.Same('smallint') then
    Result := '2 bytes'
  else if ABI_Type.Same('cardinal') or ABI_Type.Same('dword') or
    ABI_Type.Same('longword') or ABI_Type.Same('integer') or
    ABI_Type.Same('longint') or ABI_Type.Same('single') then
    Result := '4 bytes'
  else if ABI_Type.Same('int64') or ABI_Type.Same('uint64') or
    ABI_Type.Same('double') or ABI_Type.Same('extended') or
    ABI_Type.Same('real') then
    Result := '8 bytes'
  else if ABI_Type.Same('string') or ABI_Type.Same('ansistring') or
    ABI_Type.Same('unicodestring') or ABI_Type.Same('tpascalstring') or
    ABI_Type.Same('tupascalstring') or ABI_Type.Same('tp_string') or
    ABI_Type.Same('pchar') or ABI_Type.Same('pansichar') or
    ABI_Type.Same('pwidechar') then
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
function GenerateABIServicePascalReadme(Model: TPascal_Func_Model): TPascalStringList;
var
  L: TPascalStringList;
  SupportedFuncs: TArryFunctionStructure;
  UnitName, NormalizedUnit, AppName: TP_String;

  // ---------------------------------------------------------------------------
  // §1. Header
  // ---------------------------------------------------------------------------
  procedure EmitHeader;
  begin
    L.Add('# ' + UnitName + ' - Pascal ABI Service Provider');
    L.Add('');
    L.Add('> **Auto-generated**. Produced by `pas_abi_service_generator_tool.pas`;');
    L.Add('> this file stays in sync with the generated code.');
    L.Add('>');
    L.Add('> **Source unit**       : `' + UnitName + '`');
    L.Add('> **Service file**      : `' + UnitName + '_abi_service_unit.pas`');
    L.Add('> **Default App name**  : `' + AppName + '`');
    L.Add('> **Exposed APIs**      : ' + umlIntToStr(Length(SupportedFuncs)).Text);
    L.Add('>');
    L.Add('> **Audience**: human engineers and AI assistants who need to');
    L.Add('> deploy, test, or call this service without reading the source.');
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
    L.Add('This document describes the **ABI service** that was generated from');
    L.Add('the Pascal unit `' + UnitName + '`. The service is a strongly-typed,');
    L.Add('binary-wire RPC endpoint built on top of LingoFuse.');
    L.Add('');
    L.Add('### 1.1 What is an ABI service?');
    L.Add('');
    L.Add('An ABI service is a LingoFuse endpoint that:');
    L.Add('');
    L.Add('- exposes one or more Pascal routines as remotely callable APIs;');
    L.Add('- uses a **compact binary wire protocol** in both directions;');
    L.Add('- binds every API to a **fixed, statically-typed signature**;');
    L.Add('- requires a **matching call-side client** to invoke. The call-side');
    L.Add('  client can be generated by the paired Pascal, Python, or C++');
    L.Add('  generator from the same model.');
    L.Add('');
    L.Add('### 1.2 Design principles');
    L.Add('');
    L.Add('An ABI service is designed around four properties:');
    L.Add('');
    L.Add('| Property | Value |');
    L.Add('|----------|-------|');
    L.Add('| Parameter encoding | Binary, position-based |');
    L.Add('| Type system | Fixed, statically-known ABI types |');
    L.Add('| Discovery | Direct by App name on LingoFuse |');
    L.Add('| Client | Must be paired (generated from the same model) |');
    L.Add('| Overhead | Low: no JSON encode/decode on the hot path |');
    L.Add('| Ideal for | High-frequency, typed, low-latency RPC |');
    L.Add('');
    L.Add('### 1.3 Three-step quick start');
    L.Add('');
    L.Add('1. **Compile** the service unit into your server program. See §7.');
    L.Add('2. **Generate and compile** the matching call-side unit. See §7.1.');
    L.Add('3. **Call** the APIs from the call side. See §8 and §9.');
    L.Add('');
    L.Add('### 1.4 Files produced by this generator');
    L.Add('');
    L.Add('| File | Purpose |');
    L.Add('|------|---------|');
    L.Add('| `' + UnitName + '_abi_service_unit.pas` | The service unit (compile into your server program). |');
    L.Add('| `' + UnitName + '_abi_service_pascal.md` | This README. |');
    L.Add('');
  end;

  // ---------------------------------------------------------------------------
  // §3. Application scope
  // ---------------------------------------------------------------------------
  procedure EmitApplicationScope;
  begin
    L.Add('## 2. Application Scope');
    L.Add('');
    L.Add('### 2.1 When to use an ABI service');
    L.Add('');
    L.Add('Use this generator when:');
    L.Add('');
    L.Add('- You have a **fixed set of Pascal routines** with stable signatures.');
    L.Add('- Your callers are **known in advance** (you control both sides).');
    L.Add('- You need **high throughput** with low per-call overhead.');
    L.Add('- The parameters fit the ABI type whitelist (§6).');
    L.Add('- You want to **avoid JSON serialisation** on the hot path.');
    L.Add('');
    L.Add('Typical use cases:');
    L.Add('');
    L.Add('- Real-time data pipelines.');
    L.Add('- Local IPC between processes on the same machine.');
    L.Add('- Internal micro-services in a controlled deployment.');
    L.Add('- C++ or Python clients calling into a Pascal core engine.');
    L.Add('- Engine-to-engine calls inside a LingoFuse mesh.');
    L.Add('');
    L.Add('### 2.2 When NOT to use an ABI service');
    L.Add('');
    L.Add('- The API surface changes frequently: regenerate the whole chain.');
    L.Add('- Callers need to discover the API surface dynamically at runtime.');
    L.Add('- Parameters include complex types (records, variants, collections).');
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
    L.Add('FPC is a cross-platform compiler. This service works on every');
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
    L.Add('By default, each `internal_call_*` stub body runs on a LingoFuse');
    L.Add('worker thread. If the body must run on the main thread (for');
    L.Add('example, to touch UI controls), uncomment the synchronised variant');
    L.Add('inside the block comments of that stub. The variant is provided');
    L.Add('ready to use and relies on `TCompute.Sync` from `Z.Core`, which');
    L.Add('is already imported by the generated unit.');
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
    L.Add('    participant C as Client');
    L.Add('    participant S as Server');
    L.Add('    C->>C: WriteXxx(a)');
    L.Add('    C->>C: WriteXxx(b)');
    L.Add('    C->>S: LF_CallEx(payload)');
    L.Add('    S->>S: ReadXxx(a)');
    L.Add('    S->>S: ReadXxx(b)');
    L.Add('    S->>S: internal_call_xxx(a, b)');
    L.Add('    S->>S: WriteUInt8(0x00)');
    L.Add('    S->>S: WriteXxx(result)');
    L.Add('    S-->>C: response');
    L.Add('    C->>C: ReadUInt8 -> 0x00');
    L.Add('    C->>C: ReadXxx -> result');
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
    L.Add('Callers should catch the corresponding exception and inspect the');
    L.Add('decoded message.');
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
    L.Add('    subgraph Server["Server process"]');
    L.Add('        S_APP["CreateAndRegisterABIApp()<br/>creates the App and registers every API"]');
    L.Add('        S_SVC["LF_PrepareService(&#39;ipc:&lt;unit&gt;_abi&#39;)"]');
    L.Add('        S_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, app)"]');
    L.Add('        S_RUN["LF_PrepareDone()"]');
    L.Add('    end');
    L.Add('');
    L.Add('    subgraph Client["Client process"]');
    L.Add('        C_CLI["LF_PrepareClient(&#39;ipc:&lt;unit&gt;_abi&#39;, nil)"]');
    L.Add('        C_RUN["LF_PrepareDone()"]');
    L.Add('        C_CALL["Call &lt;unit&gt;_abi_call_unit.Add(3, 4)"]');
    L.Add('    end');
    L.Add('');
    L.Add('    S_APP --> S_SVC');
    L.Add('    S_SVC --> S_CLI');
    L.Add('    S_CLI --> S_RUN');
    L.Add('    C_CLI --> C_RUN');
    L.Add('    C_RUN --> C_CALL');
    L.Add('    C_CALL -. "LF_CallEx over IPC" .-> S_RUN');
    L.Add('```');
    L.Add('');
    L.Add('### 5.1 Startup sequence');
    L.Add('');
    L.Add('**Server process:**');
    L.Add('');
    L.Add('1. `LF_ResetPrepare`');
    L.Add('2. `LF_PrepareService(ipc:<unit>_abi, ipc:<unit>_abi)`');
    L.Add('3. `App := CreateAndRegisterABIApp`');
    L.Add('4. `LF_PrepareClient(ipc:<unit>_abi, App)`');
    L.Add('5. `LF_PrepareDone`');
    L.Add('');
    L.Add('**Client process:**');
    L.Add('');
    L.Add('1. `LF_ResetPrepare`');
    L.Add('2. `LF_PrepareClient(ipc:<unit>_abi, nil)`');
    L.Add('3. `LF_PrepareDone`');
    L.Add('');
    L.Add('### 5.2 Invocation sequence');
    L.Add('');
    L.Add('1. The client calls a typed function, e.g.');
    L.Add('   `<unit>_abi_call_unit.Add(3, 4)`.');
    L.Add('2. The call unit serialises the parameters and calls `LF_CallEx`.');
    L.Add('3. LingoFuse routes the payload to the server callback.');
    L.Add('4. The callback deserialises the parameters and calls');
    L.Add('   `internal_call_<Api>`.');
    L.Add('5. The stub runs the real body (by default on a worker thread;');
    L.Add('   on the main thread if the synchronised variant is enabled).');
    L.Add('6. The result is serialised with a `0x00` status prefix and returned.');
    L.Add('7. The call unit parses the response and returns the value.');
    L.Add('');
    L.Add('### 5.3 Threading notes');
    L.Add('');
    L.Add('- Callbacks execute on a background worker thread by default. Do');
    L.Add('  not touch UI controls directly.');
    L.Add('- Do not call any blocking LingoFuse function inside a callback.');
    L.Add('- Do not block the callback for long periods: it holds a worker');
    L.Add('  thread from the LingoFuse pool.');
    L.Add('- If the body must run on the main thread, uncomment the');
    L.Add('  synchronised variant inside the corresponding `internal_call_*`');
    L.Add('  stub. See §3.5.');
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
    L.Add('Anything not in §6.1 causes the **entire routine** to be silently');
    L.Add('dropped during generation. Common examples:');
    L.Add('');
    L.Add('- `Boolean`, `WordBool`, `LongBool`');
    L.Add('- `Variant`, `OleVariant`');
    L.Add('- Arrays, records, classes, interfaces');
    L.Add('- Enumerations, sets, generics');
    L.Add('- Pointers, function pointers');
    L.Add('- `Currency`, `Comp`, `TDateTime`');
    L.Add('- `WideString` (on some FPC builds)');
    L.Add('');
    L.Add('**Workaround**: serialise complex values into a `string` first');
    L.Add('(JSON or a custom binary format), then pass the string across the');
    L.Add('ABI boundary. On the call side, deserialise the string back into');
    L.Add('the rich type.');
    L.Add('');
    L.Add('### 6.3 Byte order and stability');
    L.Add('');
    L.Add('The ABI wire format uses little-endian for all integers and');
    L.Add('floats. Every platform listed in §3.2 is little-endian, so the');
    L.Add('generated code never performs byte swapping.');
    L.Add('');
    L.Add('### 6.4 Strings and the NUL terminator');
    L.Add('');
    L.Add('`LF_WriteString` always appends a single `#0` byte after the');
    L.Add('UTF-8 payload. `LF_ReadString` scans forward until it finds that');
    L.Add('`#0` byte. A mismatch (missing NUL) causes the reader to consume');
    L.Add('the rest of the payload.');
    L.Add('');
    L.Add('**Recommendation**: always use `LF_WriteString` / `LF_ReadString`');
    L.Add('on both sides. Do not hand-roll the string encoding.');
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
    L.Add('Place the generated service unit and the call-side unit in your');
    L.Add('project directory, together with the LingoFuse runtime.');
    L.Add('');
    L.Add('```');
    L.Add('my_abi_service/');
    L.Add('  ' + UnitName + '_abi_service_unit.pas      <- generated (described here)');
    L.Add('  ' + UnitName + '_abi_call_unit.pas         <- generated by pas_abi_call_generator_tool');
    L.Add('  ' + UnitName + '_server.lpr                <- your server entry point');
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
    L.Add('### 7.2 FPC build');
    L.Add('');
    L.Add('Compile the server:');
    L.Add('');
    L.Add('```bash');
    L.Add('fpc -FuZNetV2 -FuZNetV2/ZCore ' + UnitName + '_server.lpr');
    L.Add('```');
    L.Add('');
    L.Add('Compile the client (after generating the call-side unit):');
    L.Add('');
    L.Add('```bash');
    L.Add('fpc -FuZNetV2 -FuZNetV2/ZCore ' + UnitName + '_client.lpr');
    L.Add('```');
    L.Add('');
    L.Add('Both commands must include **both** `-Fu` paths. Missing either');
    L.Add('one causes "Can''t find unit Z.Core" or "Can''t find unit');
    L.Add('lingofuse_import".');
    L.Add('');
    L.Add('### 7.3 Delphi build');
    L.Add('');
    L.Add('1. Add both `.pas` files to your Delphi project.');
    L.Add('2. Add `ZNetV2` and `ZNetV2\\ZCore` to **Project Options -> Unit');
    L.Add('   Directories**.');
    L.Add('3. Set the linker search path to include the directory that holds');
    L.Add('   `LingoFuse64.dll`.');
    L.Add('4. Build.');
    L.Add('');
    L.Add('The generated unit already uses `{$DEFINE FPC_DELPHI_MODE}`, so no');
    L.Add('source changes are required.');
    L.Add('');
    L.Add('### 7.4 Startup order');
    L.Add('');
    L.Add('The server must be running before the client calls');
    L.Add('`LF_PrepareDone`. If both are launched from the same script, add a');
    L.Add('short delay:');
    L.Add('');
    L.Add('```bash');
    L.Add('./server &');
    L.Add('sleep 1');
    L.Add('./client');
    L.Add('```');
    L.Add('');
    L.Add('Or poll for readiness on the client side:');
    L.Add('');
    L.Add('```pascal');
    L.Add('while not LF_CheckAppEx(''' + AppName + ''') do');
    L.Add('  TThread.Sleep(100);');
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
    L.Add('The recommended shutdown sequence is:');
    L.Add('');
    L.Add('1. `LF_ExitMainThread`');
    L.Add('2. `LF_FreeApp(App)`');
    L.Add('3. `LF_Shutdown`');
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
    L.Add('The two programs below form a complete, copy-paste-ready test');
    L.Add('harness for the generated service. Save them next to the generated');
    L.Add('unit and compile with FPC or Delphi.');
    L.Add('');
    L.Add('### 8.1 Server program (`' + UnitName + '_server.lpr`)');
    L.Add('');
    L.Add('```pascal');
    L.Add('program ' + UnitName + '_server;');
    L.Add('');
    L.Add('{$mode objfpc}{$H+}');
    L.Add('{$CODEPAGE UTF8}');
    L.Add('');
    L.Add('uses');
    L.Add('  {$IFDEF UNIX}');
    L.Add('  cthreads,');
    L.Add('  {$ENDIF}');
    L.Add('  {$IFDEF MSWINDOWS}');
    L.Add('  Windows,');
    L.Add('  {$ENDIF}');
    L.Add('  SysUtils, Classes,');
    L.Add('  Z.Core,');
    L.Add('  lingofuse_import,');
    L.Add('  ' + UnitName + '_abi_service_unit;');
    L.Add('');
    L.Add('var');
    L.Add('  App: TAppHnd___;');
    L.Add('');
    L.Add('begin');
    L.Add('  WriteLn(''=== ' + UnitName + ' ABI service ==='');');
    L.Add('');
    L.Add('  LF_ResetPrepare;');
    L.Add('  LF_PrepareService(''ipc:' + AppName + ''', ''ipc:' + AppName + ''');');
    L.Add('');
    L.Add('  App := CreateAndRegisterABIApp;');
    L.Add('  if App = nil then');
    L.Add('  begin');
    L.Add('    WriteLn(''[FATAL] CreateAndRegisterABIApp returned nil'');');
    L.Add('    Halt(1);');
    L.Add('  end;');
    L.Add('');
    L.Add('  if LF_PrepareClient(''ipc:' + AppName + ''', App) = -1 then');
    L.Add('  begin');
    L.Add('    WriteLn(''[FATAL] LF_PrepareClient failed'');');
    L.Add('    Halt(1);');
    L.Add('  end;');
    L.Add('');
    L.Add('  if LF_PrepareDone <> 1 then');
    L.Add('  begin');
    L.Add('    WriteLn(''[FATAL] LF_PrepareDone failed'');');
    L.Add('    Halt(1);');
    L.Add('  end;');
    L.Add('');
    L.Add('  WriteLn(''[OK] Service ready. Press Enter to shut down.'');');
    L.Add('  ReadLn;');
    L.Add('');
    L.Add('  LF_ExitMainThread;');
    L.Add('  LF_FreeApp(App);');
    L.Add('  LF_Shutdown;');
    L.Add('end.');
    L.Add('```');
    L.Add('');
    L.Add('### 8.2 Client program (`' + UnitName + '_client.lpr`)');
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
    L.Add('  ' + UnitName + '_abi_call_unit;    // <- generated by pas_abi_call_generator_tool');
    L.Add('');
    L.Add('begin');
    L.Add('  WriteLn(''=== ' + UnitName + ' ABI client ==='');');
    L.Add('');
    L.Add('  LF_ResetPrepare;');
    L.Add('  LF_PrepareClient(''ipc:' + AppName + ''', nil);');
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
    L.Add('### 8.3 Running the test');
    L.Add('');
    L.Add('Open two terminals.');
    L.Add('');
    L.Add('**Terminal 1:**');
    L.Add('');
    L.Add('```bash');
    L.Add('./' + UnitName + '_server');
    L.Add('```');
    L.Add('');
    L.Add('Wait for `[OK] Service ready`.');
    L.Add('');
    L.Add('**Terminal 2:**');
    L.Add('');
    L.Add('```bash');
    L.Add('./' + UnitName + '_client');
    L.Add('```');
    L.Add('');
    L.Add('### 8.4 Verifying failure paths');
    L.Add('');
    L.Add('To exercise the error path, make a call with a deliberately');
    L.Add('truncated payload (for example, pass an empty string where a');
    L.Add('non-empty value is expected). The server returns `0xFF` and the');
    L.Add('client raises `EABI_RemoteError`.');
    L.Add('');
    L.Add('### 8.5 Unit-level testing');
    L.Add('');
    L.Add('To test the service without a full LingoFuse deployment, call the');
    L.Add('generated callbacks directly:');
    L.Add('');
    L.Add('```pascal');
    L.Add('var');
    L.Add('  In_, Out_: TDataHnd___;');
    L.Add('  Bytes: TBytes;');
    L.Add('begin');
    L.Add('  In_ := LF_CreateDataEx(''<ApiName>'');');
    L.Add('  // ... write parameters with LF_WriteXxx ...');
    L.Add('  Out_ := LF_CreateDataEx(''<ApiName>'');');
    L.Add('  Callback_<ApiName>_<ApiName>(nil, In_, Out_);');
    L.Add('  // ... read the response with LF_ReadXxx ...');
    L.Add('  LF_FreeData(In_);');
    L.Add('  LF_FreeData(Out_);');
    L.Add('end;');
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
    LayoutStr: TP_String;
    DeclLine: TP_String;
    PName: TP_String;
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

    // ---- Summary table ---------------------------------------------------
    L.Add('### 9.1 Summary');
    L.Add('');
    L.Add('| # | API name | Kind | Params | Return | Description |');
    L.Add('|---|----------|------|--------|--------|-------------|');

    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      ShortDesc := ReadmeTableCell(GetFullDescription(Func.Comment));
      if ShortDesc.Len > 60 then
        ShortDesc := ShortDesc.GetString(1, 61) + '...';

      if Func.IsFunction then
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | function | ' +
          umlIntToStr(Length(Func.Params)).Text + ' | `' +
          ABI_Type_To_Pascal_Decl(Func.ReturnType) + '` | ' + ShortDesc + ' |'
      else
        RowStr := '| ' + umlIntToStr(ii + 1).Text + ' | `' + ApiNm + '` | procedure | ' +
          umlIntToStr(Length(Func.Params)).Text + ' | - | ' + ShortDesc + ' |';
      L.Add(RowStr);
    end;

    L.Add('');

    // ---- Per-API details -------------------------------------------------
    for ii := 0 to High(SupportedFuncs) do
    begin
      Func := SupportedFuncs[ii];
      ApiNm := MakeApiName(Func.Name);
      FuncDesc := ReadmeParagraph(GetFullDescription(Func.Comment));

      // Build the reconstructed declaration line.
      if Func.IsFunction then
        DeclLine := 'function ' + Func.Name.Text + '('
      else
        DeclLine := 'procedure ' + Func.Name.Text + '(';
      for jj := 0 to High(Func.Params) do
      begin
        if jj > 0 then
          DeclLine := DeclLine + '; ';
        DeclLine := DeclLine + Func.Params[jj].Name.Text + ': ' +
          ABI_Type_To_Pascal_Decl(Func.Params[jj].PascalType);
      end;
      DeclLine := DeclLine + ')';
      if Func.IsFunction then
        DeclLine := DeclLine + ': ' + ABI_Type_To_Pascal_Decl(Func.ReturnType);
      DeclLine := DeclLine + ';';

      L.Add('### 9.' + umlIntToStr(ii + 2).Text + ' `' + ApiNm + '`');
      L.Add('');
      L.Add('- **Original declaration**: `' + DeclLine + '`');
      L.Add('- **Exposed API name**: `' + ApiNm + '`');
      if Func.IsFunction then
        L.Add('- **Kind**: function; returns `' +
          ABI_Type_To_Pascal_Decl(Func.ReturnType) + '`')
      else
        L.Add('- **Kind**: procedure');
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
          RowStr := '| ' + umlIntToStr(jj + 1).Text +
            ' | `' + PName + '`' +
            ' | `' + ABI_Type_To_Pascal_Decl(Func.Params[jj].PascalType) + '`' +
            ' | `' + Func.Params[jj].PascalType + '`' +
            ' | `' + ABI_Type_To_Write_Func(Func.Params[jj].PascalType) + '`' +
            ' | ' + ReadmeWireSizeText(Func.Params[jj].PascalType) +
            ' |';
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
        LayoutStr := '';
        for jj := 0 to High(Func.Params) do
        begin
          if LayoutStr <> '' then
            LayoutStr := LayoutStr + ' ';
          LayoutStr := LayoutStr + '[' + Func.Params[jj].Name.Text +
            ': ' + Func.Params[jj].PascalType + ']';
        end;
        L.Add(LayoutStr);
      end;
      L.Add('```');
      L.Add('');

      // Success response layout
      L.Add('#### Success response layout');
      L.Add('');
      L.Add('```');
      if Func.IsFunction then
        L.Add('[0x00] [result: ' + ABI_Type_To_Pascal_Decl(Func.ReturnType) + ']')
      else
        L.Add('[0x00]');
      L.Add('```');
      L.Add('');

      // Error response
      L.Add('#### Error response');
      L.Add('');
      L.Add('`0xFF` followed by a UTF-8 message terminated by `#0`. The call');
      L.Add('side raises `EABI_RemoteError` with the decoded message.');
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
    L.Add('| Client `LF_PrepareDone` returns 0 | Server not running | Start the server before the client. |');
    L.Add('| `EABI_RemoteError: nil (timeout)` | App name mismatch | Check `ABI_TargetApp` on the call side and `DEFAULT_APP_NAME` on the server. |');
    L.Add('| `EABI_RemoteError: "input truncated"` | Fewer fields than expected | Verify the call side writes every parameter. |');
    L.Add('| `EABI_RemoteError: <garbled bytes>` | Encoding mismatch | Ensure both sides use the same type table (§6). |');
    L.Add('| Return value is a wrong number | Byte-order mismatch | All supported platforms are little-endian; check for manual byte swaps. |');
    L.Add('| String parameters read as empty | Missing NUL terminator | Use `LF_WriteString` on the writer side. |');
    L.Add('| Callback never fires | `internal_call_*` stub not filled | Search for `TODO` in the service unit. |');
    L.Add('| High concurrency causes timeouts | Blocking call inside a callback | Move blocking work to a background thread. |');
    L.Add('| `EABI_RemoteError` on every call | ABI type not in the whitelist | See §6.1; unsupported routines are silently dropped during generation. |');
    L.Add('| UI update crashes the server | Stub body touching UI on a worker thread | Uncomment the synchronised variant of that stub. |');
    L.Add('');
    L.Add('### 10.2 Verifying a running service');
    L.Add('');
    L.Add('From the client process, before making a call:');
    L.Add('');
    L.Add('```pascal');
    L.Add('if LF_CheckMainThread = 0 then');
    L.Add('  WriteLn(''Main thread is not running'');');
    L.Add('');
    L.Add('if not LF_CheckAppEx(''' + AppName + ''') then');
    L.Add('  WriteLn(''Service App not registered'');');
    L.Add('```');
    L.Add('');
    L.Add('### 10.3 Inspecting the raw payload');
    L.Add('');
    L.Add('To print the raw bytes of a response for debugging:');
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
    L.Add('### 10.4 Enabling verbose logging');
    L.Add('');
    L.Add('In the service unit, set:');
    L.Add('');
    L.Add('```pascal');
    L.Add('DEBUG_LOG := True;');
    L.Add('```');
    L.Add('');
    L.Add('The callback wrappers then print the request status, the');
    L.Add('deserialised parameters, and the result to the console.');
    L.Add('');
    L.Add('### 10.5 Enabling main-thread execution for a specific stub');
    L.Add('');
    L.Add('Open the generated service unit and locate the `internal_call_*`');
    L.Add('stub. Uncomment the two block comments and the `//` lines inside');
    L.Add('them:');
    L.Add('');
    L.Add('```pascal');
    L.Add('(*  <- remove this line');
    L.Add('{$IFDEF FPC}');
    L.Add('  procedure Do_Sync___();');
    L.Add('  begin');
    L.Add('    Result := RealFunction(a, b);    // <- uncomment');
    L.Add('  end;');
    L.Add('{$ELSE FPC}');
    L.Add('var temp_: Integer;');
    L.Add('{$ENDIF FPC}');
    L.Add('*)  <- remove this line');
    L.Add('begin');
    L.Add('  Result := 0;');
    L.Add('  Result := RealFunction(a, b);      // <- uncomment');
    L.Add('(*  <- remove this line');
    L.Add('{$IFDEF FPC}');
    L.Add('  TCompute.Sync(Do_Sync___);');
    L.Add('{$ELSE FPC}');
    L.Add('  TCompute.Sync(procedure()');
    L.Add('  begin');
    L.Add('    temp_ := RealFunction(a, b);     // <- uncomment');
    L.Add('  end);');
    L.Add('  Result := temp_;');
    L.Add('{$ENDIF FPC}');
    L.Add('*)  <- remove this line');
    L.Add('end;');
    L.Add('```');
    L.Add('');
    L.Add('`Z.Core` is already imported by the generated unit, so no extra');
    L.Add('`uses` change is required.');
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
    L.Add('| 1 | What does the ABI service expose? | §1 |');
    L.Add('| 2 | When should I choose ABI instead of a JSON-based RPC? | §2 |');
    L.Add('| 3 | Which compilers and platforms are supported? | §3 |');
    L.Add('| 4 | What are the two bytes that frame every response? | §4.2 |');
    L.Add('| 5 | Which function do I call to create the App? | §5.1 |');
    L.Add('| 6 | What happens if a parameter type is not in the whitelist? | §6.2 |');
    L.Add('| 7 | Where do I place the DLLs at runtime? | §7.5 |');
    L.Add('| 8 | How do I compile the server with FPC? | §7.2 |');
    L.Add('| 9 | What is the shutdown order? | §7.6 |');
    L.Add('| 10 | How do I write a minimal test harness? | §8 |');
    L.Add('| 11 | How do I invoke a specific API from the call side? | §9 |');
    L.Add('| 12 | How do I make a stub run on the main thread? | §3.5, §10.5 |');
    L.Add('');
    L.Add('If you can answer all of the above, you are ready to use this');
    L.Add('service.');
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
    L.Add('| `pas_abi_call_generator_tool.pas` | Paired Pascal call-side generator |');
    L.Add('| `py_abi_call_generator_tool.pas` | Python call-side generator |');
    L.Add('| `cpp_abi_call_generator_tool.pas` | C++ call-side generator |');
    L.Add('| `pascal_code_abi_rule.md` | Recommended source-declaration style |');
    L.Add('| `C_code_abi_rule.md` | C header source-declaration style |');
    L.Add('');
    L.Add('---');
    L.Add('');
    L.Add('End of document. Generated by `pas_abi_service_generator_tool.pas`');
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

  Log(PFormat('GenerateABIServicePascalReadme: unit="%s"', [UnitName.Text]));

  SupportedFuncs := CollectSupportedFunctions(Model);
  Log(PFormat('GenerateABIServicePascalReadme: %d valid APIs',
    [Length(SupportedFuncs)]));

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

  Log(PFormat('GenerateABIServicePascalReadme: %d lines generated',
    [L.Count]));
end;

end.
