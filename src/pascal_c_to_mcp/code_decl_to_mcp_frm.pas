unit code_decl_to_mcp_frm;

{*******************************************************************************
 * code_decl_to_mcp_frm - Main form of the MCP interface code generator.
 *
 * This unit implements the GUI for the "Pascal / C -> MCP Tool Provider"
 * generator. The UI is a five-step wizard:
 *
 *   Step 1  Welcome         : brief introduction.
 *   Step 2  Source          : edit the Pascal / C source code.
 *   Step 3  Source <-> JSON : LV0 JSON (raw parse result).
 *   Step 4  Model  <-> JSON : LV1 model JSON (normalized metadata).
 *   Step 5  Final Output    : generated Pascal / Python / C++ code and
 *                             their README files.
 *
 * The form owns a TTimer that:
 *   - drains the LingoFuse status queue;
 *   - drives the user-space synchronisation tool;
 *   - drives the LingoFuse sync queue.
 *
 * All status output goes through a DoStatus hook that appends to LogMemo,
 * which is capped at 5000 lines to prevent unbounded growth.
 *
 * Naming conventions
 * ------------------
 *   * Class name : TCodeDeclToMcpForm
 *   * Variable   : CodeDeclToMcpForm
 *   * All widget identifiers use PascalCase and are self-describing.
 *
 * Dependencies
 * ------------
 *   * lingofuse_import / lingofuse_helper       - LingoFuse runtime.
 *   * pas_mcp_generator_tool /
 *     py_mcp_generator_tool /
 *     cpp_mcp_generator_tool                    - Code and README generators.
 *   * Z.Pascal_Func_Tool / Z.Pascal_Func_Model - Parsing and modeling.
 *   * Z.Parsing                                - Language detection.
 * ****************************************************************************}

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  LazHelpHTML, ComCtrls, Menus, AsyncProcess, ActnList,
  LCLIntf, PairSplitter,
  SynHighlighterCpp, SynHighlighterAny,
  SynEdit, SynHighlighterPas, SynEditMiscClasses,
  lingofuse_helper, lingofuse_import,
  Z.Core, Z.PascalStrings, Z.UPascalStrings,
  Z.Parsing, Z.Expression, Z.ListEngine, Z.Notify, Z.UnicodeMixedLib, Z.Status,
  Z.MemoryStream, Z.Json, Z.HashList.Templet,
  pas_mcp_generator_tool, py_mcp_generator_tool, cpp_mcp_generator_tool,
  code_decl_to_mcp_api_tool_provider_unit, cmake_for_cpp_mcp_generator_tool, csharp_mcp_generator_tool,
  Z.Pascal_Func_Model, Z.Pascal_Func_Tool;

type

  { TCodeDeclToMcpForm - Main application form.
    See the unit header for the full workflow description. }
  TCodeDeclToMcpForm = class(TForm)
    BackToJsonFromModelButton: TButton;
    BackToModelButton: TButton;
    BuildModelFromJsonButton: TButton;
    EmptyUnitButtonSpacer: TBevel;
    FinalSourceHintLabel: TLabel;
    FinalSourceSpacer: TBevel;
    FinalSourceTab: TTabSheet;
    FinalSourceToolbarPanel: TPanel;
    final_Source_edit: TSynEdit;
    final_source_file_ListView: TListView;
    Final_source_left_PairSplitterSide: TPairSplitterSide;
    Final_source_PairSplitter: TPairSplitter;
    Final_source_right_PairSplitterSide: TPairSplitterSide;
    FormatButtonSpacer: TBevel;
    FormatSourceButton: TButton;
    GenerateAllCodeButton: TButton;
    GoToSourceButton: TButton;
    LanguageSelectorComboBox: TComboBox;
    LanguageSelectorLabel: TLabel;
    LanguageSelectorSpacer: TBevel;
    LoadTestSampleButton: TButton;
    MainPageControl: TPageControl;
    ModelJsonEdit: TSynEdit;
    ModelJsonHintLabel: TLabel;
    ModelJsonSpacer1: TBevel;
    ModelJsonSpacer2: TBevel;
    ModelJsonTab: TTabSheet;
    ModelJsonToolbarPanel: TPanel;
    NewEmptyUnitButton: TButton;
    ParseToJsonButton: TButton;
    RebuildSourceFromJsonButton: TButton;
    SourceEdit: TSynEdit;
    SourceJsonEdit: TSynEdit;
    SourceJsonHintLabel: TLabel;
    SourceJsonSpacer1: TBevel;
    SourceJsonSpacer2: TBevel;
    SourceJsonTab: TTabSheet;
    SourceJsonToolbarPanel: TPanel;
    SourceTab: TTabSheet;
    SourceToolbarPanel: TPanel;
    SysTimer: TTimer;
    FreePascalHighlighter: TSynFreePascalSyn;
    SynCppHighlighter: TSynCppSyn;
    TestSampleButtonSpacer: TBevel;
    WelcomeEdit: TSynEdit;
    WelcomeNextButtonSpacer: TBevel;
    WelcomeTab: TTabSheet;
    WelcomeTitleLabel: TLabel;
    WelcomeToolbarPanel: TPanel;
    procedure final_source_file_ListViewSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure GoToSourceButtonClick(Sender: TObject);
    procedure FormatSourceButtonClick(Sender: TObject);
    procedure ParseToJsonButtonClick(Sender: TObject);
    procedure NewEmptyUnitButtonClick(Sender: TObject);
    procedure LoadTestSampleButtonClick(Sender: TObject);
    procedure LanguageSelectorLabelClick(Sender: TObject);
    procedure LanguageSelectorComboBoxChange(Sender: TObject);
    procedure RebuildSourceFromJsonButtonClick(Sender: TObject);
    procedure BuildModelFromJsonButtonClick(Sender: TObject);
    procedure BackToJsonFromModelButtonClick(Sender: TObject);
    procedure GenerateAllCodeButtonClick(Sender: TObject);
    procedure BackToModelButtonClick(Sender: TObject);
    procedure SysTimerTick(Sender: TObject);
  private
    { Text shown in WelcomeEdit at construction time, saved for reset. }
    FBackupWelcomeText: TP_String;

    { Currently selected source language. Updated by AutoSelectLanguage. }
    FCurrentLanguage: TSourceLanguage;

    { Output directory for the current unit. Set by SaveContextFiles. }
    FUnitOutputDir: TP_String;

    { -- Helpers for the code generation step -------------------------- }

    { Save a TSynEdit's content to a file inside FUnitOutputDir. }
    procedure SaveEditorToFile(Editor: TSynEdit; const FileName: string; var SavedPath: TP_String);

    { Save a TPascalStringList to a file inside FUnitOutputDir. }
    procedure SaveListToFile(List: TPascalStringList; const FileName: string; var SavedPath: TP_String);

    { Save context files (source, LV0 JSON, LV1 JSON). }
    procedure SaveContextFiles;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Begin_MCP_Service;

    { Detect language from SourceEdit.Text and update the combo box. }
    procedure AutoSelectLanguage;

    { -- Actions triggered from the UI --------------------------------- }

    { Step 2: rebuild SourceEdit from the LV0 JSON. }
    procedure RebuildSourceFromLv0Json;

    { Step 2: parse SourceEdit into LV0 JSON. }
    procedure ParseSourceToLv0Json;

    { Step 3: convert LV0 JSON into LV1 model JSON. }
    procedure BuildLv1ModelFromLv0Json;

    { Step 4: convert LV1 model JSON back to LV0 JSON. }
    procedure BackToLv0JsonFromModel;

    { Step 4: generate all code and README, save to disk. }
    procedure GenerateAllArtifacts;

    { Format SourceEdit in place (keep only supported top-level decls). }
    procedure FormatSourceInPlace;

    { Load an empty skeleton matching the current language. }
    procedure LoadEmptySkeleton;

    { Load a rich test sample matching the current language. }
    procedure LoadTestSample;
  end;

var
  CodeDeclToMcpForm: TCodeDeclToMcpForm;

implementation

{$R *.lfm}

{$I code_decl_to_mcp_samples.inc}

{ =========================================================================== }
{ Construction and destruction                                                 }
{ =========================================================================== }

constructor TCodeDeclToMcpForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FCurrentLanguage := TSourceLanguage.slUnknown;
  FBackupWelcomeText := WelcomeEdit.Text;

  LanguageSelectorComboBox.ItemIndex := 2;
  LanguageSelectorComboBoxChange(LanguageSelectorComboBox);
  NewEmptyUnitButtonClick(NewEmptyUnitButton);

  TCompute.RunM_NP(Begin_MCP_Service);
end;

destructor TCodeDeclToMcpForm.Destroy;
begin
  inherited Destroy;
end;

procedure TCodeDeclToMcpForm.Begin_MCP_Service;
begin
  LF_SetOptionEx('WaitConnect', 'True');
  LF_SetOptionEx('Overlap_Connection', 'True');
  code_decl_to_mcp_api_tool_provider_unit.Execute_And_Reg_all;
end;

{ =========================================================================== }
{ Event handlers                                                               }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  Hide;
end;

procedure TCodeDeclToMcpForm.final_source_file_ListViewSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
  begin
    final_Source_edit.Lines.LoadFromFile(Item.SubItems[0]);
    if umlMultipleMatch('*.pas;*.pp;*.lpr;*.dpr', Item.Caption) then
      final_Source_edit.Highlighter := self.FreePascalHighlighter
    else if umlMultipleMatch('*.cpp;*.c;*.hpp;*.h', Item.Caption) then
      final_Source_edit.Highlighter := self.SynCppHighlighter
    else
      final_Source_edit.Highlighter := nil;
  end
  else
  begin
    final_Source_edit.Text := '';
    final_Source_edit.Highlighter := nil;
  end;
end;

procedure TCodeDeclToMcpForm.GoToSourceButtonClick(Sender: TObject);
begin
  MainPageControl.ActivePage := SourceTab;
end;

procedure TCodeDeclToMcpForm.FormatSourceButtonClick(Sender: TObject);
begin
  FormatSourceInPlace;
end;

procedure TCodeDeclToMcpForm.ParseToJsonButtonClick(Sender: TObject);
begin
  ParseSourceToLv0Json;
end;

procedure TCodeDeclToMcpForm.NewEmptyUnitButtonClick(Sender: TObject);
begin
  LoadEmptySkeleton;
end;

procedure TCodeDeclToMcpForm.LoadTestSampleButtonClick(Sender: TObject);
begin
  LoadTestSample;
end;

procedure TCodeDeclToMcpForm.LanguageSelectorLabelClick(Sender: TObject);
begin
  AutoSelectLanguage;
end;

procedure TCodeDeclToMcpForm.LanguageSelectorComboBoxChange(Sender: TObject);
begin
  { Keep the highlighter and the cached language in sync with the combo. }
  case LanguageSelectorComboBox.ItemIndex of
    1: begin
      SourceEdit.Highlighter := FreePascalHighlighter;
      FCurrentLanguage := TSourceLanguage.slPascal;
    end;
    2: begin
      SourceEdit.Highlighter := SynCppHighlighter;
      FCurrentLanguage := TSourceLanguage.slC;
    end;
    else
    begin
      SourceEdit.Highlighter := nil;
      FCurrentLanguage := TSourceLanguage.slUnknown;
    end;
  end;
end;

procedure TCodeDeclToMcpForm.RebuildSourceFromJsonButtonClick(Sender: TObject);
begin
  RebuildSourceFromLv0Json;
end;

procedure TCodeDeclToMcpForm.BuildModelFromJsonButtonClick(Sender: TObject);
begin
  BuildLv1ModelFromLv0Json;
end;

procedure TCodeDeclToMcpForm.BackToJsonFromModelButtonClick(Sender: TObject);
begin
  BackToLv0JsonFromModel;
end;

procedure TCodeDeclToMcpForm.GenerateAllCodeButtonClick(Sender: TObject);
begin
  GenerateAllArtifacts;
end;

procedure TCodeDeclToMcpForm.BackToModelButtonClick(Sender: TObject);
begin
  MainPageControl.ActivePage := ModelJsonTab;
end;

procedure TCodeDeclToMcpForm.SysTimerTick(Sender: TObject);
begin
  Check_Soft_Thread_Synchronize;
  LF___.LF_Sync;
end;

{ =========================================================================== }
{ Language selection                                                           }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.AutoSelectLanguage;
begin
  FCurrentLanguage := DetectSourceLanguage(SourceEdit.Text);

  case FCurrentLanguage of
    slPascal: LanguageSelectorComboBox.ItemIndex := 1;
    slC: LanguageSelectorComboBox.ItemIndex := 2;
    else
      LanguageSelectorComboBox.ItemIndex := 0;
  end;

  { Manually fire the combo handler to refresh the highlighter. }
  LanguageSelectorComboBoxChange(LanguageSelectorComboBox);
end;

{ =========================================================================== }
{ Source <-> LV0 JSON                                                          }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.RebuildSourceFromLv0Json;
var
  Report: TPascalStringList;
begin
  case FCurrentLanguage of
    TSourceLanguage.slPascal:
    begin
      Report := TPascalStringList.Create;
      try
        with tpascal_func_decl_tool.Create do
        begin
          try
            LoadFromJson(SourceJsonEdit.Text);
            SourceEdit.Text := decl_to_pascal(Report);
          finally
            Free;
          end;
        end;
      finally
        DisposeObject(Report);
      end;
    end;

    TSourceLanguage.slC:
    begin
      Report := TPascalStringList.Create;
      try
        with tpascal_func_decl_tool.Create do
        begin
          try
            LoadFromJson(SourceJsonEdit.Text);
            SourceEdit.Text := decl_to_c(Report);
          finally
            Free;
          end;
        end;
      finally
        DisposeObject(Report);
      end;
    end;
    else
    begin
      DoStatus('Unsupported language.');
      Exit;
    end;
  end;

  DoStatus('Source code rebuilt from JSON.');
  DoStatus(Report.AsText);
  MainPageControl.ActivePage := SourceTab;
end;

procedure TCodeDeclToMcpForm.ParseSourceToLv0Json;
begin
  case FCurrentLanguage of
    TSourceLanguage.slPascal:
      with tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceEdit.Text) do
      begin
        try
          SourceJsonEdit.Text := SaveToJson();
        finally
          Free;
        end;
      end;

    TSourceLanguage.slC:
      with tpascal_func_decl_tool.CreateFrom_C_Code(SourceEdit.Text) do
      begin
        try
          SourceJsonEdit.Text := SaveToJson();
        finally
          Free;
        end;
      end;
    else
    begin
      DoStatus('Unsupported language.');
      Exit;
    end;
  end;

  MainPageControl.ActivePage := SourceJsonTab;
  DoStatus('LV0 JSON built (source -> JSON).');
end;

{ =========================================================================== }
{ LV0 JSON <-> LV1 model JSON                                                  }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.BuildLv1ModelFromLv0Json;
var
  FuncTool: tpascal_func_decl_tool;
  FuncModel: TPascal_Func_Model;
  Report: TPascalStringList;
begin
  FuncTool := tpascal_func_decl_tool.Create;
  try
    FuncTool.LoadFromJson(SourceJsonEdit.Text);

    Report := TPascalStringList.Create;
    try
      FuncModel := TPascal_Func_Model.Create;
      try
        FuncModel.LoadFromParser(FuncTool, Report);
        ModelJsonEdit.Text := FuncModel.SaveToJson;
      finally
        DisposeObject(FuncModel);
      end;

      DoStatus('LV1 model JSON built (JSON -> model).');
      DoStatus(Report.AsText);
    finally
      DisposeObject(Report);
    end;
  finally
    DisposeObject(FuncTool);
  end;

  MainPageControl.ActivePage := ModelJsonTab;
end;

procedure TCodeDeclToMcpForm.BackToLv0JsonFromModel;
var
  FuncTool: tpascal_func_decl_tool;
  FuncModel: TPascal_Func_Model;
begin
  FuncModel := TPascal_Func_Model.Create;
  try
    FuncModel.LoadFromJson(ModelJsonEdit.Text);

    FuncTool := tpascal_func_decl_tool.Create;
    try
      FuncModel.SaveToParser(FuncTool);
      SourceJsonEdit.Text := FuncTool.SaveToJson;
    finally
      DisposeObject(FuncTool);
    end;
  finally
    DisposeObject(FuncModel);
  end;

  MainPageControl.ActivePage := SourceJsonTab;
end;

{ =========================================================================== }
{ Source formatting                                                            }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.FormatSourceInPlace;
var
  Report: TPascalStringList;
begin
  case FCurrentLanguage of
    TSourceLanguage.slPascal:
    begin
      Report := TPascalStringList.Create;
      try
        with tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceEdit.Text) do
        begin
          try
            SourceEdit.Text := decl_to_pascal(Report);
          finally
            Free;
          end;
        end;
      finally
        DisposeObject(Report);
      end;
    end;

    TSourceLanguage.slC:
    begin
      Report := TPascalStringList.Create;
      try
        with tpascal_func_decl_tool.CreateFrom_C_Code(SourceEdit.Text) do
        begin
          try
            SourceEdit.Text := decl_to_c(Report);
          finally
            Free;
          end;
        end;
      finally
        DisposeObject(Report);
      end;
    end;
    else
    begin
      DoStatus('Unsupported language.');
      Exit;
    end;
  end;

  DoStatus(Report.AsText);
  DoStatus('Source rebuilt: only top-level declarations are kept.');
end;

{ =========================================================================== }
{ Empty skeleton and test sample                                               }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.LoadEmptySkeleton;
begin
  case FCurrentLanguage of
    TSourceLanguage.slPascal:
      SourceEdit.Text :=
        'unit untitled;' + #13#10 + #13#10 + 'interface' + #13#10 + #13#10 + '// Paste your function declarations here.' +
        #13#10 + #13#10 + 'implementation' + #13#10 + #13#10 + 'end.' + #13#10;

    TSourceLanguage.slC:
      SourceEdit.Text :=
        '/* untitled.h */' + #13#10 + '#ifndef UNTITLED_H' + #13#10 + '#define UNTITLED_H' + #13#10 + #13#10 +
        '/* Paste your function prototypes here. */' + #13#10 + #13#10 + '#endif /* UNTITLED_H */' + #13#10;
    else
      SourceEdit.Text := '';
  end;
end;

procedure TCodeDeclToMcpForm.LoadTestSample;
begin
  { The full sample text is provided by code_decl_to_mcp_samples.inc.
    It is split out purely to keep this unit readable; the sample
    content is not interpreted by the editor. }
  case FCurrentLanguage of
    TSourceLanguage.slPascal: SourceEdit.Text := BuildPascalTestSample;
    TSourceLanguage.slC: SourceEdit.Text := BuildCTestSample;
    else
      SourceEdit.Text := '';
  end;
end;

{ =========================================================================== }
{ Output helpers                                                               }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.SaveEditorToFile(Editor: TSynEdit; const FileName: string; var SavedPath: TP_String);
var
  Temp: TPascalStringList;
begin
  Temp := TPascalStringList.Create;
  try
    Temp.Assign(Editor.Lines);
    SavedPath := umlCombineFileName(FUnitOutputDir.Text, FileName);
    Temp.SaveToFile(SavedPath);
    DoStatus('Saved file: %s', [SavedPath.Text]);

  with final_source_file_ListView.Items.Add do
  begin
    Caption := FileName;
    SubItems.Add(SavedPath);
    ImageIndex := -1;
    StateIndex := -1;
  end;
finally
    DisposeObject(Temp);
  end;
end;

procedure TCodeDeclToMcpForm.SaveListToFile(List: TPascalStringList; const FileName: string; var SavedPath: TP_String);
begin
  SavedPath := umlCombineFileName(FUnitOutputDir.Text, FileName);
  List.SaveToFile(SavedPath);
  DoStatus('Saved file: %s', [SavedPath.Text]);
  with final_source_file_ListView.Items.Add do
  begin
    Caption := FileName;
    SubItems.Add(SavedPath);
    ImageIndex := -1;
    StateIndex := -1;
  end;
end;

procedure TCodeDeclToMcpForm.SaveContextFiles;
var
  SavedPath: TP_String;
begin
  if SourceEdit.Lines.Count > 0 then
  begin
    if FCurrentLanguage = TSourceLanguage.slC then
      SaveEditorToFile(SourceEdit, 'source.h', SavedPath)
    else
      SaveEditorToFile(SourceEdit, 'source.pas', SavedPath);
  end;

  if SourceJsonEdit.Lines.Count > 0 then
    SaveEditorToFile(SourceJsonEdit, 'source.json', SavedPath);

  if ModelJsonEdit.Lines.Count > 0 then
    SaveEditorToFile(ModelJsonEdit, 'source_model.json', SavedPath);
end;

{ =========================================================================== }
{ Generate all artifacts                                                       }
{ =========================================================================== }

procedure TCodeDeclToMcpForm.GenerateAllArtifacts;
var
  FuncModel: TPascal_Func_Model;
  L: TPascalStringList;
  SavedPath: TP_String;
  UnitName: TP_String;
begin
  MainPageControl.ActivePage := FinalSourceTab;
  final_source_file_ListView.Items.Clear;
  final_Source_edit.Text := '';

  { -- 1. Build the model from the LV1 JSON. ------------------------- }
  FuncModel := TPascal_Func_Model.Create;
  try
    FuncModel.LoadFromJson(ModelJsonEdit.Text);
    UnitName := FuncModel.UnitName;

    { -- 2. Prepare the output directory. ---------------------------- }
    FUnitOutputDir.Text := umlCombinePath(umlGetFilePath(ParamStr(0)), UnitName);
    umlCreateDirectory(FUnitOutputDir.Text);
    DoStatus('Output directory: %s', [FUnitOutputDir.Text]);

    { -- 3. Save the context files (source, LV0, LV1). -------------- }
    SaveContextFiles;

    { -- 4. Pascal code + README. ----------------------------------- }
    L := GeneratePascalCode(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_unit.pas', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    L := GeneratePascalReadme(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_pascal.md', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 5. Python code + README. ----------------------------------- }
    L := GeneratePythonCode(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider.py', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    L := GeneratePythonReadme(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_python.md', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 6. C++ header + implementation + README. ------------------- }
    L := GenerateHPPCode(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider.hpp', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    L := GenerateCPPCode(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider.cpp', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    L := GenerateCPPReadme(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_cpp.md', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 6b. CMake build script. ------------------------------------ }
    { Produces a standalone CMakeLists.txt placed next to the generated
      .hpp / .cpp / .md files. The script:
        - builds <unit>_tool_provider_test.cpp together with
          <unit>_tool_provider.cpp,
        - locates and links against the LingoFuse runtime library,
        - makes both Debug and Release builds land in build/bin,
        - on Windows, copies the runtime DLLs next to the executable,
        - on Unix, sets RPATH so no LD_LIBRARY_PATH is required.

      The resulting script requires no manual editing when the default
      layout (all generated files and the LingoFuse runtime in one
      directory) is used. }
    L := GenerateCMakeLists(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, 'CMakeLists.txt', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 6c. C++ test program. -------------------------------------- }
    { Produces a runnable test main that:
        - prints the effective provider configuration,
        - calls Execute_And_Reg_all() to create the App, register every
          supported API, connect to the IPC endpoint, and advertise
          every API to the beacon as an MCP tool,
        - waits for the user to press Enter,
        - then performs an orderly LF_ExitMainThread / LF_Shutdown.

      The file is compiled together with the generated provider
      implementation by the CMakeLists.txt produced above. }
    L := GenerateCPPTestMain(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_test.cpp', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 6d. C# provider class. ------------------------------------- }
    { Produces the C# provider class file. It contains:
        - the metadata constants (App name, endpoint, beacon app, ...),
        - one InternalCall_<name> stub per supported Pascal routine,
        - one Callback_<name> per supported Pascal routine,
        - RegisterAPIs / RegisterTools / Execute_And_Reg_all / ShutdownClean.

      The file deliberately contains NO Main method: the test entry point
      is emitted separately below so that the provider class can be
      reused by any .NET host application.

      The class targets .NET 8.0 and depends only on the `LingoFuse`
      .NET binding assembly. See the companion C# README for the binding
      sourcing policy. }
    L := GenerateCSharpCode(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider.cs', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 6e. C# test program. --------------------------------------- }
    { Produces the single Main entry point for the .NET console project
      that hosts the provider class above. The test program:
        - prints the effective configuration,
        - calls Execute_And_Reg_all() to create the App, register every
          supported API, connect to the IPC endpoint, and advertise
          every API to the beacon as an MCP tool,
        - waits for the user to press Enter,
        - then performs the orderly teardown:
              NetworkEvents.Clear
              Framework.ExitMainThread
              AppHandle.Dispose
              Framework.Shutdown.

      The two .cs files must be placed in the same .NET project. Only
      this test file defines Main, so no CS0017 duplicate-entry-point
      error can occur. }
    L := GenerateCSharpTestProgram(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_test.cs', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 6f. C# README. --------------------------------------------- }
    { Produces a detailed English Markdown guide. It documents:
        - the fixed 4-step startup order
              beacon -> provider -> mcp_api_tool -> agent
        - the runtime architecture diagram and end-to-end data flow,
        - .NET SDK prerequisites and the LingoFuse .NET binding sourcing
          policy (NuGet vs. v3 fallback),
        - the project layout and a minimal .csproj template,
        - build, run, and troubleshooting instructions,
        - a per-tool reference with JSON input/output examples,
        - portability and deployment recipes (Docker, NSSM, systemd). }
    L := GenerateCSharpReadme(FuncModel);
    try
      if L <> nil then
      begin
        SaveListToFile(L, UnitName + '_tool_provider_csharp.md', SavedPath);
      end;
    finally
      DisposeObjectAndNil(L);
    end;

    { -- 7. Switch to the final output page. ------------------------- }
    MainPageControl.ActivePage := FinalSourceTab;
    DoStatus('All artifacts generated.');
  finally
    DisposeObject(FuncModel);
  end;
end;

end.
