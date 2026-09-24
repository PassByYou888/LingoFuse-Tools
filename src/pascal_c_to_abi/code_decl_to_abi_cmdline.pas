unit code_decl_to_abi_cmdline;

(*
  code_decl_to_abi_cmdline

  Command-line front end for the code_decl_to_abi generator.

  This unit is fully independent from the GUI and from LingoFuse. It
  performs the same parsing and code generation work as the graphical
  tool, but it never creates a form and never touches the UI thread. It
  is intended to be called at the very start of the host program, before
  the LCL application object is created.

  Typical usage inside the host program (code_decl_to_abi.lpr):

      begin
        if not Process_CommandLine then
        begin
          exitCode := CommandLine_ExitCode;
          exit;
        end;

        RequireDerivedFormResource := True;
        Application.Scaled := True;
        Application.MainFormOnTaskbar := True;
        Application.Initialize;
        Application.CreateForm(Tcode_decl_to_abi_form, code_decl_to_abi_form);
        Application.Run;
      end.

  Process_CommandLine returns True when the process has no command-line
  arguments at all, indicating that the caller should continue with the
  normal GUI startup. It returns False when a command-line action has
  been handled; the host program should then exit with the code stored
  in CommandLine_ExitCode.

  CONSOLE HANDLING
  ----------------

  The host project is built as a CONSOLE-subsystem application (via the
  {$apptype console} directive). This is required so that the parent
  shell waits for our output before printing its next prompt; a GUI-
  subsystem build would let the parent shell return immediately and
  would interleave the shell prompt with our help text.

  Two console behaviours are handled by this unit:

      - No command-line arguments. The console window that a console-
        subsystem build allocates at startup is hidden before returning
        True. The LCL application then runs exactly as a normal GUI
        application; double-clicking the executable does not leave an
        empty console window on screen.

      - At least one command-line argument. The console is kept visible.
        A custom DoStatus hook routes every message straight to standard
        output, bypassing the queue-based mechanism of Z.Status that
        requires a running main loop. When the requested work is done
        the function flushes stdout and returns False so that the host
        program exits normally with the code in CommandLine_ExitCode.

  All status output goes through DoStatus. No direct WriteLn is used by
  this unit's logic; only the console hook (private to this unit)
  writes to standard output.

  Supported command-line forms:

      code_decl_to_abi --help
      code_decl_to_abi <input_file> <output_file>
      code_decl_to_abi --call <input_file> <output_file>

  The source language is detected from the input file extension. The
  target language is detected from the output file extension. The
  direction (service or call) is controlled by the --call flag; the
  default is service.

  Every successful run produces the generated code file plus a
  companion Markdown README describing the artefact. When the target
  is C++, two files are produced (a header and an implementation), and
  the README describes the pair as a single unit.
*)

interface

uses
  SysUtils;

(*
  Exit code produced by the last Process_CommandLine call. The host
  program should pass this value to the process exit code (Delphi mode:
  exitCode := CommandLine_ExitCode; exit;).
*)
var
  CommandLine_ExitCode: Integer = 0;

(*
  Inspect the process command line.

  Return value:
    True   no command-line arguments were supplied; the caller should
           continue with the normal GUI startup.
    False  a command-line action was performed; the caller should exit
           with the code stored in CommandLine_ExitCode.
*)
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
  pas_abi_service_generator_tool,
  pas_abi_call_generator_tool,
  py_abi_service_generator_tool,
  py_abi_call_generator_tool,
  cpp_abi_service_generator_tool,
  cpp_abi_call_generator_tool;

const
  EXIT_OK           = 0;
  EXIT_BAD_ARGS     = 1;
  EXIT_PARSE_FAILED = 2;
  EXIT_GEN_FAILED   = 3;
  EXIT_IO_ERROR     = 4;

type
  TSourceLang = (slPascal, slC, slUnknown);
  TTargetLang = (tlPascal, tlPython, tlCpp, tlUnknown);
  TTargetMode = (tmService, tmCall);

(* ------------------------------------------------------------------------ *)
(* Console output hook                                                        *)
(* ------------------------------------------------------------------------ *)

(*
  DoStatus hook used in command-line mode. Every message is written to
  standard output immediately. Because the host project is built as a
  console-subsystem application, WriteLn reaches the same console the
  parent shell is already waiting on; no AttachConsole or AllocConsole
  is needed.
*)
procedure CmdLine_DoStatus_Hook(Text_: SystemString; const ID: Integer);
begin
  WriteLn(Text_);
end;

(* ------------------------------------------------------------------------ *)
(* Help text                                                                  *)
(* ------------------------------------------------------------------------ *)

procedure Print_Help;
begin
  DoStatus('code_decl_to_abi - LF-ABI interface code generator');
  DoStatus('');
  DoStatus('USAGE');
  DoStatus('  code_decl_to_abi                          Launch the GUI.');
  DoStatus('  code_decl_to_abi --help                   Show this help text.');
  DoStatus('  code_decl_to_abi <input> <output>         Generate the SERVICE side.');
  DoStatus('  code_decl_to_abi --call <input> <output>  Generate the CALL side.');
  DoStatus('');
  DoStatus('SOURCE LANGUAGE (detected from the input file extension)');
  DoStatus('  .pas .pp .p                   Pascal unit');
  DoStatus('  .h .hpp .hh .c .cpp .cc .cxx  C header');
  DoStatus('');
  DoStatus('TARGET LANGUAGE (detected from the output file extension)');
  DoStatus('  .pas .pp .p                   Pascal ABI unit');
  DoStatus('  .py                           Python ABI module');
  DoStatus('  .hpp .hh .h                   C++ ABI header');
  DoStatus('  .cpp .cc .cxx .c              C++ ABI implementation');
  DoStatus('');
  DoStatus('TARGET DIRECTION (selected by the --call flag)');
  DoStatus('  (default)                     Service side: exposes the routines.');
  DoStatus('  --call                        Call side: invokes the routines.');
  DoStatus('');
  DoStatus('C++ PAIRING');
  DoStatus('  When the target is C++, two files are written together: the');
  DoStatus('  header and the implementation. Naming either one causes the');
  DoStatus('  other to be written next to it under the same base name.');
  DoStatus('');
  DoStatus('README');
  DoStatus('  A Markdown user guide is written next to the generated code');
  DoStatus('  file. Its name is the output base name plus "_readme.md".');
  DoStatus('');
  DoStatus('EXAMPLES');
  DoStatus('  code_decl_to_abi calculator.pas calculator_service.pas');
  DoStatus('  code_decl_to_abi --call calculator.pas calculator_call.pas');
  DoStatus('  code_decl_to_abi ComplexTestUnit.h calculator_service.py');
  DoStatus('  code_decl_to_abi --call ComplexTestUnit.h calculator_call.py');
  DoStatus('  code_decl_to_abi ComplexTestUnit.h calculator_service.hpp');
  DoStatus('  code_decl_to_abi --call ComplexTestUnit.h calculator_call.hpp');
  DoStatus('');
  DoStatus('EXIT CODES');
  DoStatus('  0  Conversion succeeded.');
  DoStatus('  1  Missing or invalid arguments.');
  DoStatus('  2  Source parsing failed.');
  DoStatus('  3  Code generation failed.');
  DoStatus('  4  File I/O error.');
end;

(* ------------------------------------------------------------------------ *)
(* File name helpers                                                          *)
(* ------------------------------------------------------------------------ *)

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

function Detect_Target_Lang(const FileName: string): TTargetLang;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  if (Ext = '.pas') or (Ext = '.pp') or (Ext = '.p') then
    Result := tlPascal
  else if Ext = '.py' then
    Result := tlPython
  else if (Ext = '.hpp') or (Ext = '.hh') or (Ext = '.h')
       or (Ext = '.cpp') or (Ext = '.cc') or (Ext = '.cxx') or (Ext = '.c') then
    Result := tlCpp
  else
    Result := tlUnknown;
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

function Companion_Readme_Path(const OutputFile: string): string;
var
  Dir, Base: string;
begin
  Dir := ExtractFileDir(OutputFile);
  Base := ChangeFileExt(ExtractFileName(OutputFile), '');
  Result := IncludeTrailingPathDelimiter(Dir) + Base + '_readme.md';
end;

procedure Cpp_Paths_From_Output(const OutputFile: string; out HppPath, CppPath: string);
var
  Dir, Base: string;
begin
  Dir := ExtractFileDir(OutputFile);
  Base := ChangeFileExt(ExtractFileName(OutputFile), '');
  HppPath := IncludeTrailingPathDelimiter(Dir) + Base + '.hpp';
  CppPath := IncludeTrailingPathDelimiter(Dir) + Base + '.cpp';
end;

(* ------------------------------------------------------------------------ *)
(* Conversion                                                                 *)
(* ------------------------------------------------------------------------ *)

function Generate_Pascal(const Model: TPascal_Func_Model;
  const Mode: TTargetMode;
  const OutputFile: string): Integer;
var
  CodeList, ReadmeList: TPascalStringList;
  ReadmePath: string;
begin
  Result := EXIT_OK;

  if Mode = tmService then
    CodeList := GenerateABIServicePascalCode(Model)
  else
    CodeList := GenerateABICallPascalCode(Model);

  try
    if (CodeList = nil) or (not Write_Text_List(OutputFile, CodeList)) then
    begin
      DoStatus('Error: cannot write "%s".', [OutputFile]);
      Exit(EXIT_GEN_FAILED);
    end;
    DoStatus('Wrote  : %s', [OutputFile]);
  finally
    CodeList.Free;
    CodeList := nil;
  end;

  if Mode = tmService then
    ReadmeList := GenerateABIServicePascalReadme(Model)
  else
    ReadmeList := GenerateABICallPascalReadme(Model);

  if ReadmeList <> nil then
  begin
    try
      ReadmePath := Companion_Readme_Path(OutputFile);
      if Write_Text_List(ReadmePath, ReadmeList) then
        DoStatus('Wrote  : %s', [ReadmePath]);
    finally
      ReadmeList.Free;
      ReadmeList := nil;
    end;
  end;
end;

function Generate_Python(const Model: TPascal_Func_Model;
  const Mode: TTargetMode;
  const OutputFile: string): Integer;
var
  CodeList, ReadmeList: TPascalStringList;
  ReadmePath: string;
begin
  Result := EXIT_OK;

  if Mode = tmService then
    CodeList := GenerateABIServicePyCode(Model)
  else
    CodeList := GenerateABICallPyCode(Model);

  try
    if (CodeList = nil) or (not Write_Text_List(OutputFile, CodeList)) then
    begin
      DoStatus('Error: cannot write "%s".', [OutputFile]);
      Exit(EXIT_GEN_FAILED);
    end;
    DoStatus('Wrote  : %s', [OutputFile]);
  finally
    CodeList.Free;
    CodeList := nil;
  end;

  if Mode = tmService then
    ReadmeList := GenerateABIServicePyReadme(Model)
  else
    ReadmeList := GenerateABICallPyReadme(Model);

  if ReadmeList <> nil then
  begin
    try
      ReadmePath := Companion_Readme_Path(OutputFile);
      if Write_Text_List(ReadmePath, ReadmeList) then
        DoStatus('Wrote  : %s', [ReadmePath]);
    finally
      ReadmeList.Free;
      ReadmeList := nil;
    end;
  end;
end;

function Generate_Cpp(const Model: TPascal_Func_Model;
  const Mode: TTargetMode;
  const OutputFile: string): Integer;
var
  CodeList, ReadmeList: TPascalStringList;
  HppPath, CppPath, ReadmePath: string;
begin
  Result := EXIT_OK;

  Cpp_Paths_From_Output(OutputFile, HppPath, CppPath);

  if Mode = tmService then
    CodeList := GenerateABIServiceHppCode(Model)
  else
    CodeList := GenerateABICallHppCode(Model);

  try
    if (CodeList = nil) or (not Write_Text_List(HppPath, CodeList)) then
    begin
      DoStatus('Error: cannot write "%s".', [HppPath]);
      Exit(EXIT_GEN_FAILED);
    end;
    DoStatus('Wrote  : %s', [HppPath]);
  finally
    CodeList.Free;
    CodeList := nil;
  end;

  if Mode = tmService then
    CodeList := GenerateABIServiceCppCode(Model)
  else
    CodeList := GenerateABICallCppCode(Model);

  try
    if (CodeList = nil) or (not Write_Text_List(CppPath, CodeList)) then
    begin
      DoStatus('Error: cannot write "%s".', [CppPath]);
      Exit(EXIT_GEN_FAILED);
    end;
    DoStatus('Wrote  : %s', [CppPath]);
  finally
    CodeList.Free;
    CodeList := nil;
  end;

  if Mode = tmService then
    ReadmeList := GenerateABIServiceCppReadme(Model)
  else
    ReadmeList := GenerateABICallCppReadme(Model);

  if ReadmeList <> nil then
  begin
    try
      ReadmePath := Companion_Readme_Path(HppPath);
      if Write_Text_List(ReadmePath, ReadmeList) then
        DoStatus('Wrote  : %s', [ReadmePath]);
    finally
      ReadmeList.Free;
      ReadmeList := nil;
    end;
  end;
end;

function Execute_Conversion(const InputFile, OutputFile: string;
  const Mode: TTargetMode): Integer;
var
  SrcLang: TSourceLang;
  TgtLang: TTargetLang;
  SourceText: string;
  Tool: tpascal_func_decl_tool;
  Model: TPascal_Func_Model;
  Report: TPascalStringList;
begin
  SrcLang := Detect_Source_Lang(InputFile);
  TgtLang := Detect_Target_Lang(OutputFile);

  if SrcLang = slUnknown then
  begin
    DoStatus('Error: cannot detect the source language from "%s".', [InputFile]);
    DoStatus('Supported input extensions: .pas .pp .p .h .hpp .hh .c .cpp .cc .cxx');
    Exit(EXIT_BAD_ARGS);
  end;

  if TgtLang = tlUnknown then
  begin
    DoStatus('Error: cannot detect the target language from "%s".', [OutputFile]);
    DoStatus('Supported output extensions: .pas .pp .p .py .hpp .hh .h .cpp .cc .cxx .c');
    Exit(EXIT_BAD_ARGS);
  end;

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
  DoStatus('Output : %s', [OutputFile]);
  if Mode = tmService then
    DoStatus('Mode   : service')
  else
    DoStatus('Mode   : call');

  Tool := nil;
  Model := nil;
  Report := nil;
  try
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

    case TgtLang of
      tlPascal:
        Result := Generate_Pascal(Model, Mode, OutputFile);
      tlPython:
        Result := Generate_Python(Model, Mode, OutputFile);
      tlCpp:
        Result := Generate_Cpp(Model, Mode, OutputFile);
      else
        Result := EXIT_GEN_FAILED;
    end;

  finally
    if Report <> nil then
      Report.Free;
    if Model <> nil then
      Model.Free;
    if Tool <> nil then
      Tool.Free;
  end;
end;

(* ------------------------------------------------------------------------ *)
(* Entry point                                                                *)
(* ------------------------------------------------------------------------ *)

function Process_CommandLine: Boolean;
var
  Arg1, Arg2: string;
  Code: Integer;
  Mode: TTargetMode;
  ArgStart, ArgCount: Integer;
begin
  (* No arguments: hide the console window allocated by the console-
     subsystem build and let the caller start the GUI normally. *)
  if ParamCount <= 0 then
  begin
    Result := True;
    Exit;
  end;

  (* Command-line mode. Route every DoStatus message straight to the
     console so that no main loop is required. *)
  OnDoStatusHook := @CmdLine_DoStatus_Hook;

  CommandLine_ExitCode := EXIT_OK;
  Mode := tmService;
  ArgStart := 1;

  try
    try
      Arg1 := ParamStr(ArgStart);

      (* Help. Only recognised as the first argument. *)
      if (Arg1 = '--help') or (Arg1 = '-h') or (Arg1 = '-?') or (Arg1 = '/?') then
      begin
        Print_Help;
        CommandLine_ExitCode := EXIT_OK;
        Result := False;
        Exit;
      end;

      (* Direction flag. Only recognised as the first argument. *)
      if (Arg1 = '--call') or (Arg1 = '-c') then
      begin
        Mode := tmCall;
        Inc(ArgStart);
      end;

      ArgCount := ParamCount - (ArgStart - 1);
      if ArgCount < 2 then
      begin
        DoStatus('Error: expected <input_file> <output_file>.');
        DoStatus('Run "code_decl_to_abi --help" for usage.');
        CommandLine_ExitCode := EXIT_BAD_ARGS;
        Result := False;
        Exit;
      end;

      Arg1 := ParamStr(ArgStart);
      Arg2 := ParamStr(ArgStart + 1);

      Code := Execute_Conversion(Arg1, Arg2, Mode);
      CommandLine_ExitCode := Code;

      if Code = EXIT_OK then
        DoStatus('Done.')
      else
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
    (* Flush stdout so the parent shell sees every line before the
       process exits. *)
    Flush(Output);
  end;
end;

end.
