unit code_decl_to_json_abi_cmdline;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  SysUtils;

var
  CommandLine_ExitCode: Integer = 0;

function Process_CommandLine: Boolean;

implementation

uses
  Classes,
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  Z.Core,
  Z.PascalStrings,
  Z.UPascalStrings,
  Z.Status,
  Z.ListEngine,
  Z.UnicodeMixedLib,
  Z.Pascal_Func_Model,
  Z.Pascal_Func_Tool,
  code_decl_to_json_abi_registry;

const
  EXIT_OK           = 0;
  EXIT_BAD_ARGS     = 1;
  EXIT_PARSE_FAILED = 2;
  EXIT_GEN_FAILED   = 3;
  EXIT_IO_ERROR     = 4;

type
  TSourceLang = (slPascal, slC, slUnknown);
  TTargetMode = (tmService, tmCall);

procedure CmdLine_DoStatus_Hook(Text_: SystemString; const ID: Integer);
begin
  WriteLn(Text_);
end;

procedure Print_Help;
var
  callOnly, serviceOnly, separateBoth, completeSet: string;
begin
  DoStatus('code_decl_to_json_abi - HTTP/JSON interface code generator');
  DoStatus('');
  DoStatus('USAGE');
  DoStatus('  code_decl_to_json_abi                                Launch the GUI.');
  DoStatus('  code_decl_to_json_abi --help                         Show this help text.');
  DoStatus('  code_decl_to_json_abi --list-languages               List registered languages.');
  DoStatus('  code_decl_to_json_abi <input> <output>               Generate the SERVICE side.');
  DoStatus('  code_decl_to_json_abi --call <input> <output>        Generate the CALL side.');
  DoStatus('  code_decl_to_json_abi --lang <id> <input> <output>   Force the target language.');
  DoStatus('');
  DoStatus('INPUT (source language detected from the extension)');
  DoStatus('  .pas .pp .p                   Pascal unit');
  DoStatus('  .h .hpp .hh .c .cpp .cc .cxx  C header');
  DoStatus('');
  DoStatus('OUTPUT (target language detected from the extension or --lang)');
  DoStatus('');
  DoStatus('  Format: [language] side-capability ext-list artifact-kinds (total)');
  DoStatus('');

  if (CodeGenRegistry <> nil) and (CodeGenRegistry.GetLanguageCount > 0) then
  begin
    DoStatus(CodeGenRegistry.GetRegisteredLanguageSummary);
    DoStatus('');
    DoStatus('  Extensions (non-fixed-name artifacts): %s',
      [CodeGenRegistry.GetAllExtensions(' ')]);
  end
  else
  begin
    DoStatus('  [pascal      ] service+call      .pas             ' +
      'service-code x1, call-code x1, test-code x2  (4 total)');
    DoStatus('  [javascript  ] call-only         .js              ' +
      'call-code x1  (1 total)');
    DoStatus('  [cpp         ] service+call      .hpp, .cpp       ' +
      'service-header x1, service-code x1, call-header x1, ' +
      'call-code x1, build-script x1, build-main x1  (6 total)');
  end;

  DoStatus('');
  DoStatus('TARGET DIRECTION (selected by the --call flag)');
  DoStatus('  (default)                     Service side: exposes the routines.');
  DoStatus('  --call                        Call side: invokes the routines.');
  DoStatus('');
  DoStatus('LANGUAGE-SPECIFIC NOTES');

  if (CodeGenRegistry <> nil) and (CodeGenRegistry.GetLanguageCount > 0) then
  begin
    callOnly     := CodeGenRegistry.GetCallOnlyLanguages;
    serviceOnly  := CodeGenRegistry.GetServiceOnlyLanguages;
    separateBoth := CodeGenRegistry.GetSeparateBothLanguages;
    completeSet  := CodeGenRegistry.GetCompleteSetLanguages;
    if callOnly <> '' then
      DoStatus('  --call required:    %s', [callOnly]);
    if serviceOnly <> '' then
      DoStatus('  no --call allowed:  %s', [serviceOnly]);
    if separateBoth <> '' then
      DoStatus('  service+call:       %s (--call optional)', [separateBoth]);
    if completeSet <> '' then
      DoStatus('  complete set:       %s (--call ignored)', [completeSet]);
  end
  else
  begin
    DoStatus('  JavaScript  Call-side only.');
    DoStatus('  C#          Complete set (--call is ignored).');
  end;

  DoStatus('');
  DoStatus('ARTIFACT KINDS');
  DoStatus('  service-code    service-side source code (main entry)');
  DoStatus('  service-header  service-side header file');
  DoStatus('  service-readme  service-side documentation');
  DoStatus('  call-code       call-side source code (main entry)');
  DoStatus('  call-header     call-side header file');
  DoStatus('  call-readme     call-side documentation');
  DoStatus('  call-html       call-side HTML test page (JS/TS)');
  DoStatus('  test-code       test program source');
  DoStatus('  test-readme     test program documentation');
  DoStatus('  build-script    build script (CMakeLists.txt / *.ps1)');
  DoStatus('  build-main      build main file (test_main___.cpp)');
  DoStatus('');
  DoStatus('FILE NAMING');
  DoStatus('  The output file name you supply is used only to choose the');
  DoStatus('  destination directory. The actual file names come from the');
  DoStatus('  generator registry: each artefact is written as');
  DoStatus('      <UnitName><suffix>     (e.g. calculator_http_json_service.py)');
  DoStatus('  or, for build-support artefacts, exactly');
  DoStatus('      <suffix>               (e.g. CMakeLists.txt).');
  DoStatus('');
  DoStatus('EXAMPLES');
  DoStatus('  code_decl_to_json_abi calculator.pas output/');
  DoStatus('  code_decl_to_json_abi --call calculator.pas output/');
  DoStatus('  code_decl_to_json_abi --lang python calculator.pas output/');
  DoStatus('  code_decl_to_json_abi --call --lang ts calculator.pas output/');
  DoStatus('  code_decl_to_json_abi ComplexTestUnit.h build/');
  DoStatus('  code_decl_to_json_abi --call ComplexTestUnit.h build/');
  DoStatus('');
  DoStatus('EXIT CODES');
  DoStatus('  0  Conversion succeeded.');
  DoStatus('  1  Missing or invalid arguments.');
  DoStatus('  2  Source parsing failed.');
  DoStatus('  3  Code generation failed.');
  DoStatus('  4  File I/O error.');
end;

procedure Print_Languages;
begin
  if (CodeGenRegistry = nil) or (CodeGenRegistry.GetLanguageCount = 0) then
  begin
    DoStatus('Registry is empty or not loaded.');
    DoStatus('Fallback languages (hardcoded): pascal, python, cpp, javascript, csharp');
    Exit;
  end;

  DoStatus('Registered languages (%d):', [CodeGenRegistry.GetLanguageCount]);
  DoStatus('');
  DoStatus(CodeGenRegistry.GetRegisteredLanguageDetail);
end;

function Detect_Source_Lang(const FileName: string): TSourceLang;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  if (Ext = '.pas') or (Ext = '.pp') or (Ext = '.p') then
    Result := slPascal
  else if (Ext = '.h') or (Ext = '.hpp') or (Ext = '.hh')
       or (Ext = '.c') or (Ext = '.cpp') or (Ext = '.cc') or (Ext = '.cxx') then
    Result := slC
  else
    Result := slUnknown;
end;

function Detect_Target_Lang_ID(const FileName: string): TP_String;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '' then
  begin
    Result := '';
    Exit;
  end;

  if CodeGenRegistry <> nil then
  begin
    Result := CodeGenRegistry.FindLanguageByExtension(Ext);
    if Result.Len > 0 then
      Exit;
  end;

  if (Ext = '.pas') or (Ext = '.pp') or (Ext = '.p') then
    Result := 'pascal'
  else if Ext = '.py' then
    Result := 'python'
  else if (Ext = '.hpp') or (Ext = '.hh') or (Ext = '.h')
       or (Ext = '.cpp') or (Ext = '.cc') or (Ext = '.cxx') or (Ext = '.c') then
    Result := 'cpp'
  else if Ext = '.js' then
    Result := 'javascript'
  else if Ext = '.cs' then
    Result := 'csharp'
  else
    Result := '';
end;

function Read_Text_File(const FileName: string): string;
var
  fs: TFileStream;
  bytes: TBytes;
begin
  if not umlFileExists(FileName) then
    raise Exception.CreateFmt('Input file not found: %s', [FileName]);
  fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if fs.Size <= 0 then
    begin
      Result := '';
      Exit;
    end;
    SetLength(bytes, fs.Size);
    fs.ReadBuffer(bytes[0], fs.Size);
  finally
    fs.Free;
  end;
  Result := TEncoding.UTF8.GetString(bytes);
end;

function Write_Text_List(const FileName: string; L: TPascalStringList): Boolean;
var
  Dir: string;
begin
  Result := False;
  if L = nil then
    Exit;
  Dir := ExtractFileDir(FileName);
  if (Dir <> '') and (not umlDirectoryExists(Dir)) then
    umlCreateDirectory(Dir);
  try
    L.SaveToFile(FileName);
    Result := True;
  except
    Result := False;
  end;
end;

function JoinPath(const Dir, Name: string): string;
begin
  if Dir = '' then
    Result := Name
  else
    Result := IncludeTrailingPathDelimiter(Dir) + Name;
end;

function Resolve_Output_Directory(const OutputArg: string): string;
var
  Dir: string;
  Base: string;
begin
  Dir  := ExtractFileDir(OutputArg);
  Base := ExtractFileName(OutputArg);

  if Dir <> '' then
  begin
    Result := Dir;
    Exit;
  end;

  if ExtractFileExt(Base) = '' then
  begin
    Result := Base;
    Exit;
  end;

  Result := '';
end;

function Execute_Conversion(const InputFile, OutputArg: string;
  const Mode: TTargetMode; const ForceLang: TP_String): Integer;
var
  SrcLang: TSourceLang;
  TgtLangID: TP_String;
  SourceText: string;
  Tool: tpascal_func_decl_tool;
  Model: TPascal_Func_Model;
  Report: TPascalStringList;
  OutDir, UnitName: string;
  i: Integer;
  Entry: PCodeGenEntry;
  Text: TPascalStringList;
  SkipSideCheck: Boolean;
  LangInfo: TLanguageInfo;
  HasServiceCap, HasCallCap: Boolean;
  FullPath: string;
begin
  Result := EXIT_OK;
  Tool := nil;
  Model := nil;
  Report := nil;

  try
    SrcLang := Detect_Source_Lang(InputFile);
    if SrcLang = slUnknown then
    begin
      DoStatus('Error: cannot detect the source language from "%s".', [InputFile]);
      DoStatus('Supported input extensions: .pas .pp .p .h .hpp .hh .c .cpp .cc .cxx');
      Exit(EXIT_BAD_ARGS);
    end;

    if ForceLang.Len > 0 then
    begin
      if (CodeGenRegistry = nil) or (not CodeGenRegistry.HasLanguage(ForceLang)) then
      begin
        DoStatus('Error: language "%s" (from --lang) is not registered.',
          [ForceLang.Text]);
        if CodeGenRegistry <> nil then
          DoStatus('Registered languages: %s',
            [CodeGenRegistry.GetAllLanguageIDs(', ')]);
        Exit(EXIT_BAD_ARGS);
      end;
      TgtLangID := ForceLang;
    end
    else
    begin
      TgtLangID := Detect_Target_Lang_ID(OutputArg);
      if TgtLangID.Len = 0 then
      begin
        DoStatus('Error: cannot detect the target language from "%s".', [OutputArg]);
        if (CodeGenRegistry <> nil) and (CodeGenRegistry.Count > 0) then
        begin
          DoStatus('Supported output extensions: %s',
            [CodeGenRegistry.GetAllExtensions(' ')]);
          DoStatus('Use --lang <id> to force a language, or --list-languages for details.');
        end
        else
          DoStatus('Supported output extensions: .pas .pp .p .py .hpp .hh .h .cpp .cc .cxx .c .js .cs');
        Exit(EXIT_BAD_ARGS);
      end;
    end;

    if (CodeGenRegistry = nil) or (CodeGenRegistry.Count = 0) then
    begin
      DoStatus('Error: generator registry is empty; no generators are available.');
      Exit(EXIT_GEN_FAILED);
    end;

    LangInfo := CodeGenRegistry.GetLanguageInfo(TgtLangID);
    HasServiceCap := LangInfo.HasService or LangInfo.HasBoth;
    HasCallCap := LangInfo.HasCall or LangInfo.HasBoth;
    SkipSideCheck := LangInfo.HasBoth and (not LangInfo.HasService) and (not LangInfo.HasCall);

    if not SkipSideCheck then
    begin
      if (Mode = tmCall) and (not HasCallCap) then
      begin
        DoStatus('Error: language "%s" has no call-side generator.', [TgtLangID.Text]);
        DoStatus('Omit --call to generate the service side.');
        Exit(EXIT_BAD_ARGS);
      end;
      if (Mode = tmService) and (not HasServiceCap) then
      begin
        DoStatus('Error: language "%s" has no service-side generator.', [TgtLangID.Text]);
        DoStatus('Re-run with --call to generate the call side.');
        Exit(EXIT_BAD_ARGS);
      end;
    end
    else
      DoStatus('Note   : language "%s" always produces the full set; --call is ignored.',
        [TgtLangID.Text]);

    try
      SourceText := Read_Text_File(InputFile);
    except
      on E: Exception do
      begin
        DoStatus('Error: cannot read "%s": %s', [InputFile, E.Message]);
        Exit(EXIT_IO_ERROR);
      end;
    end;

    DoStatus('Reading: %s (%d chars)', [InputFile, Length(SourceText)]);
    DoStatus('Output : %s', [OutputArg]);
    DoStatus('Target : %s', [TgtLangID.Text]);
    if SkipSideCheck then
      DoStatus('Mode   : both (forced by target language)')
    else if Mode = tmService then
      DoStatus('Mode   : service')
    else
      DoStatus('Mode   : call');

    try
      if SrcLang = slPascal then
        Tool := tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceText)
      else
        Tool := tpascal_func_decl_tool.CreateFrom_C_Code(SourceText);
    except
      on E: Exception do
      begin
        DoStatus('Error: parse failed: %s', [E.Message]);
        Exit(EXIT_PARSE_FAILED);
      end;
    end;

    if (Tool = nil) or (not Tool.ParseSuccess) then
    begin
      DoStatus('Error: the parser did not accept the source text.');
      Exit(EXIT_PARSE_FAILED);
    end;

    Model := TPascal_Func_Model.Create;
    Model.Typ_Normalize_Func := tnf_ABI;
    Report := TPascalStringList.Create;
    Model.LoadFromParser(Tool, Report);

    if Model.FuncCount <= 0 then
    begin
      DoStatus('Error: no usable declarations were found in the source file.');
      DoStatus(Report.Text);
      Exit(EXIT_PARSE_FAILED);
    end;

    DoStatus('Unit   : %s', [Model.UnitName.Text]);
    DoStatus('Funcs  : %d', [Model.FuncCount]);

    OutDir := Resolve_Output_Directory(OutputArg);
    if OutDir <> '' then
      DoStatus('Dir    : %s', [OutDir]);

    UnitName := Model.UnitName.Text;
    if UnitName = '' then
    begin
      DoStatus('Error: Model.UnitName is empty. Cannot derive artefact names.');
      Exit(EXIT_GEN_FAILED);
    end;

    Result := EXIT_OK;
    for i := 0 to CodeGenRegistry.Count - 1 do
    begin
      Entry := CodeGenRegistry[i];
      if not Entry^.LanguageID.Same(TgtLangID) then
        Continue;
      if (not SkipSideCheck) and
         (not Side_Matches_Requested(Entry^.Side, Mode = tmCall)) then
        Continue;

      try
        Text := Entry^.Func(Model);
      except
        Text := nil;
      end;

      if Text = nil then
        Continue;
      try
        if Entry^.FixedName then
          FullPath := JoinPath(OutDir, Entry^.Suffix.Text)
        else
          FullPath := JoinPath(OutDir, UnitName + Entry^.Suffix.Text);

        if Write_Text_List(FullPath, Text) then
          DoStatus('Wrote  : %s', [FullPath])
        else
        begin
          DoStatus('Error  : cannot write "%s".', [FullPath]);
          Result := EXIT_GEN_FAILED;
        end;
      finally
        Text.Free;
      end;
    end;

    if Result = EXIT_OK then
      DoStatus('Done.');

  finally
    if Report <> nil then
      Report.Free;
    if Model <> nil then
      Model.Free;
    if Tool <> nil then
      Tool.Free;
  end;
end;

function Process_CommandLine: Boolean;
var
  Arg: string;
  Code: Integer;
  Mode: TTargetMode;
  ForceLang: TP_String;
  Pos, ArgCount: Integer;
begin
  if ParamCount <= 0 then
  begin
    Result := True;
    Exit;
  end;

  OnDoStatusHook := @CmdLine_DoStatus_Hook;

  CommandLine_ExitCode := EXIT_OK;
  Mode := tmService;
  ForceLang := '';
  Pos := 1;

  try
    try
      if Pos <= ParamCount then
      begin
        Arg := ParamStr(Pos);
        if (Arg = '--help') or (Arg = '-h') or (Arg = '-?') or (Arg = '/?') then
        begin
          Print_Help;
          CommandLine_ExitCode := EXIT_OK;
          Result := False;
          Exit;
        end;
        if (Arg = '--list-languages') or (Arg = '-ll') then
        begin
          Print_Languages;
          CommandLine_ExitCode := EXIT_OK;
          Result := False;
          Exit;
        end;
      end;

      while Pos <= ParamCount do
      begin
        Arg := ParamStr(Pos);

        if (Arg = '--call') or (Arg = '-c') then
        begin
          Mode := tmCall;
          Inc(Pos);
        end
        else if (Arg = '--lang') or (Arg = '-l') then
        begin
          if Pos >= ParamCount then
          begin
            DoStatus('Error: --lang requires a language identifier.');
            CommandLine_ExitCode := EXIT_BAD_ARGS;
            Result := False;
            Exit;
          end;
          ForceLang := ParamStr(Pos + 1);
          Inc(Pos, 2);
        end
        else
          Break;
      end;

      ArgCount := ParamCount - Pos + 1;
      if ArgCount < 2 then
      begin
        DoStatus('Error: expected <input_file> <output_file>.');
        DoStatus('Run "code_decl_to_json_abi --help" for usage.');
        CommandLine_ExitCode := EXIT_BAD_ARGS;
        Result := False;
        Exit;
      end;

      Code := Execute_Conversion(ParamStr(Pos), ParamStr(Pos + 1), Mode, ForceLang);
      CommandLine_ExitCode := Code;

      if Code <> EXIT_OK then
        DoStatus('Failed.');

      Result := False;

    except
      on E: Exception do
      begin
        DoStatus('Unexpected error: %s', [E.Message]);
        CommandLine_ExitCode := EXIT_BAD_ARGS;
        Result := False;
      end;
    end;
  finally
    Flush(Output);
  end;
end;

end.
