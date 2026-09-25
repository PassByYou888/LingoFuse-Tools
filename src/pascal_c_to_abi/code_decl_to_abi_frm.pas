unit code_decl_to_abi_frm;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  LazHelpHTML, ComCtrls, Menus, AsyncProcess, ActnList, LCLIntf, PairSplitter,
  SynHighlighterCpp, SynHighlighterAny,
  lingofuse_helper, Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Parsing,
  Z.Expression, Z.ListEngine, Z.Notify, Z.UnicodeMixedLib, Z.Status,
  Z.MemoryStream, Z.Json, Z.HashList.Templet,
  SynEdit, SynHighlighterPas, SynEditMiscClasses,
  lingofuse_import, pas_abi_call_generator_tool, pas_abi_service_generator_tool,
  py_abi_call_generator_tool, py_abi_service_generator_tool,
  cpp_abi_call_generator_tool, cpp_abi_service_generator_tool, code_decl_to_abi_mcp_api_tool_provider_unit, cpp_abi_cmake_generator_tool,
  Z.Pascal_Func_Model, Z.Pascal_Func_Tool;

type

  { Tcode_decl_to_abi_form }

  Tcode_decl_to_abi_form = class(TForm)
    Bar_FinalSource: TPanel;
    Bar_ModelJson: TPanel;
    Bar_Source: TPanel;
    Bar_SourceJson: TPanel;
    Bar_Welcome: TPanel;
    Btn_BackToModelJson: TButton;
    Btn_FormatSource: TButton;
    Btn_GenerateSource: TButton;
    Btn_GotoSource: TButton;
    Btn_JsonToModel: TButton;
    Btn_JsonToSource: TButton;
    Btn_LoadEmptyUnit: TButton;
    Btn_LoadTestSample: TButton;
    Btn_ModelToJson: TButton;
    Btn_OpenCRules: TButton;
    Btn_OpenPascalRules: TButton;
    Btn_SourceToJson: TButton;
    Bvl_FinalSourceSpacer: TBevel;
    Bvl_ModelJsonSpacer1: TBevel;
    Bvl_ModelJsonSpacer2: TBevel;
    Bvl_SourceJsonSpacer1: TBevel;
    Bvl_SourceJsonSpacer2: TBevel;
    Bvl_SourceSpacer1: TBevel;
    Bvl_SourceSpacer2: TBevel;
    Bvl_SourceSpacer3: TBevel;
    Bvl_WelcomeSpacer1: TBevel;
    Cmb_LanguageSelector: TComboBox;
    Edit_CppCallCpp: TSynEdit;
    Edit_CMake_Call_Test: TSynEdit;
    Edit_CppCallHpp: TSynEdit;
    Edit_CMake_Service_Test: TSynEdit;
    Edit_CppCallReadme: TSynEdit;
    Edit_CMake: TSynEdit;
    Edit_CppServiceCpp: TSynEdit;
    Edit_CppServiceHpp: TSynEdit;
    Edit_CppServiceReadme: TSynEdit;
    Edit_ModelJson: TSynEdit;
    Edit_PasCallReadme: TSynEdit;
    Edit_PasCallSource: TSynEdit;
    Edit_PasServiceReadme: TSynEdit;
    Edit_PasServiceSource: TSynEdit;
    Edit_PyCallReadme: TSynEdit;
    Edit_PyCallSource: TSynEdit;
    Edit_PyServiceReadme: TSynEdit;
    Edit_PyServiceSource: TSynEdit;
    Edit_Source: TSynEdit;
    Edit_SourceJson: TSynEdit;






    { Highlighters }
    HL_Any: TSynAnySyn;
    HL_Cpp: TSynCppSyn;
    HL_Pascal: TSynFreePascalSyn;
    Lbl_FinalSourceHint: TLabel;
    Lbl_LanguageSelector: TLabel;
    Lbl_ModelJsonHint: TLabel;
    Lbl_SourceJsonHint: TLabel;
    Lbl_WelcomeHeader: TLabel;
    Memo_Welcome: TMemo;
    Page_FinalSource: TPageControl;
    Page_Main: TPageControl;
    Split_CppCall: TPairSplitter;
    Split_CppCall1: TPairSplitter;
    Split_CppCall_CppSide: TPairSplitterSide;
    Split_CppCall_CppSide1: TPairSplitterSide;
    Split_CppCall_HppSide: TPairSplitterSide;
    Split_CppCall_HppSide1: TPairSplitterSide;
    Split_CppService: TPairSplitter;
    Split_CppService_CppSide: TPairSplitterSide;
    Split_CppService_HppSide: TPairSplitterSide;
    CMake_TabSheet: TTabSheet;
    CMake_Test_TabSheet: TTabSheet;
    Tab_CppCall: TTabSheet;
    Tab_CppCallReadme: TTabSheet;
    Tab_CppService: TTabSheet;
    Tab_CppServiceReadme: TTabSheet;
    Tab_FinalSource: TTabSheet;
    Tab_ModelJson: TTabSheet;
    Tab_PasCall: TTabSheet;
    Tab_PasCallReadme: TTabSheet;
    Tab_PasService: TTabSheet;
    Tab_PasServiceReadme: TTabSheet;
    Tab_PyCall: TTabSheet;
    Tab_PyCallReadme: TTabSheet;
    Tab_PyService: TTabSheet;
    Tab_PyServiceReadme: TTabSheet;
    Tab_Source: TTabSheet;
    Tab_SourceJson: TTabSheet;
    Tab_Welcome: TTabSheet;

    { Timer }
    Timer_Progress: TTimer;

    { Event handlers }
    procedure JsonToPascalButtonClick(Sender: TObject);
    procedure JsonToModelButtonClick(Sender: TObject);
    procedure ModelToJsonButtonClick(Sender: TObject);
    procedure BackToModelJsonButtonClick(Sender: TObject);
    procedure empty_unit_Button1Click(Sender: TObject);
    procedure empty_unit_ButtonClick(Sender: TObject);
    procedure GenerateSourceButtonClick(Sender: TObject);
    procedure Open_c_rule_ButtonClick(Sender: TObject);
    procedure Open_pascal_rule_ButtonClick(Sender: TObject);
    procedure Sel_Lang_ComboBoxChange(Sender: TObject);
    procedure sel_lang_LabelClick(Sender: TObject);
    procedure source_2_json_nex_ButtonClick(Sender: TObject);
    procedure Formater_source_ButtonClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure sysTimerTimer(Sender: TObject);
    procedure to_source_ButtonClick(Sender: TObject);
  private
    current_language: TSourceLanguage;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Do_Init_Th;
    procedure Auto_Select_Language;
  end;

var
  code_decl_to_abi_form: Tcode_decl_to_abi_form;

implementation

{$R *.lfm}

procedure Tcode_decl_to_abi_form.JsonToPascalButtonClick(Sender: TObject);
var
  Report: TPascalStringList;
begin
  case current_language of
    TSourceLanguage.slPascal:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.Create do
      begin
        LoadFromJson(Edit_SourceJson.Text);
        Edit_Source.Text := decl_to_pascal(Report);
        Free;
      end;
    end;
    TSourceLanguage.slC:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.Create do
      begin
        LoadFromJson(Edit_SourceJson.Text);
        Edit_Source.Text := decl_to_c(Report);
        Free;
      end;
    end;
    else
    begin
      DoStatus('Unsupported source language.');
      exit;
    end;
  end;

  DoStatus('JSON -> Source completed.');
  DoStatus(Report.AsText);
  Page_Main.ActivePage := Tab_Source;
  DisposeObject(Report);
end;

procedure Tcode_decl_to_abi_form.JsonToModelButtonClick(Sender: TObject);
var
  func_tool: tpascal_func_decl_tool;
  func_model: TPascal_Func_Model;
  Report: TPascalStringList;
begin
  func_tool := tpascal_func_decl_tool.Create;
  func_tool.LoadFromJson(Edit_SourceJson.Text);

  Report := TPascalStringList.Create;

  func_model := TPascal_Func_Model.Create;
  func_model.Typ_Normalize_Func := tnf_ABI;
  func_model.LoadFromParser(func_tool, Report);
  Edit_ModelJson.Text := func_model.SaveToJson;

  DisposeObject(func_tool);

  DoStatus('JSON -> Model completed.');
  DoStatus(Report.AsText);
  Page_Main.ActivePage := Tab_ModelJson;
  DisposeObject(Report);
end;

procedure Tcode_decl_to_abi_form.ModelToJsonButtonClick(Sender: TObject);
var
  func_tool: tpascal_func_decl_tool;
  func_model: TPascal_Func_Model;
begin
  func_model := TPascal_Func_Model.Create;
  func_model.Typ_Normalize_Func := tnf_ABI;
  func_model.LoadFromJson(Edit_ModelJson.Text);

  func_tool := tpascal_func_decl_tool.Create;
  func_model.SaveToParser(func_tool);

  Edit_SourceJson.Text := func_tool.SaveToJson;

  DisposeObject(func_tool);
  DisposeObject(func_model);

  Page_Main.ActivePage := Tab_SourceJson;
end;

procedure Tcode_decl_to_abi_form.BackToModelJsonButtonClick(Sender: TObject);
begin
  Page_Main.ActivePage := Tab_ModelJson;
end;

procedure Tcode_decl_to_abi_form.empty_unit_Button1Click(Sender: TObject);
begin
  case current_language of
    TSourceLanguage.slPascal: Edit_Source.Text :=
        'unit ComplexTestUnit;'#13#10 + #13#10 + '{'#13#10 +
        '  A comprehensive Pascal unit used to exercise the parser'#13#10 +
        '  (Z.Pascal_Func_Tool). It covers a wide range of advanced and'#13#10 +
        '  edge-case syntax, verifying both the robustness and the'#13#10 +
        '  completeness of the parser.'#13#10 +
        '  Every declaration is syntactically valid; implementation'#13#10 +
        '  bodies are omitted since the unit is only used to validate'#13#10 +
        '  the interface section.'#13#10 +
        '}'#13#10 + #13#10 +
        '{$mode objfpc}{$H+}'#13#10 + '{$modeswitch advancedrecords}'#13#10 +
        '{$modeswitch typehelpers}'#13#10 + #13#10 + 'interface'#13#10 +
        #13#10 + 'uses'#13#10 + '  SysUtils, Classes, Generics.Collections, TypInfo,'#13#10 +
        '  Z.Core, Z.PascalStrings, Math;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Comment-style coverage (multiple formats)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '(* A top-level function with no parameters, returning an integer. *)'#13#10 +
        'function NoParamFunc: Integer;'#13#10 +
        #13#10 + '// Single-line comment; parameterless procedure.'#13#10 +
        'procedure NoParamProc;'#13#10 +
        #13#10 + '{'#13#10 + '  Multi-line block comment,'#13#10 +
        '  used to test comment extraction.'#13#10 + '}'#13#10 +
        'function MultiLineComment(a: Integer): Integer;'#13#10 +
        #13#10 + '(**'#13#10 + ' * Doxygen-style comment'#13#10 +
        ' * @param a First operand'#13#10 + ' * @param b Second operand'#13#10 +
        ' * @return Sum of the two operands'#13#10 + ' *)'#13#10 +
        'function Add(a, b: Integer): Integer;'#13#10 +
        #13#10 + '{ Comment adjacent to the function name }'#13#10 +
        'function Sub(a, b: Integer): Integer; // trailing comment should not bind'#13#10 +
        #13#10 + '(* Comment with a leading asterisk *)'#13#10 +
        '// Another comment; adjacent comments should be merged'#13#10 +
        'function Mul(a, b: Double): Double;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Basic parameter declarations'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// Single parameter'#13#10 +
        'function SingleParam(x: Integer): Boolean;'#13#10 +
        #13#10 + '// Multiple parameters of different types'#13#10 +
        'function MultipleParams(a: Integer; b: string; c: Double): string;'#13#10 +
        #13#10 + '// var parameter'#13#10 +
        'procedure ModifyVar(var Value: Integer);'#13#10 +
        #13#10 + '// const parameter'#13#10 +
        'procedure ReadOnlyConst(const Value: string);'#13#10 +
        #13#10 + '// out parameter'#13#10 +
        'procedure GetValue(out Result: Integer);'#13#10 +
        #13#10 + '// Mixed modifiers'#13#10 +
        'procedure MixedMods(const Input: string; var Output: Integer; out ErrorCode: Integer);'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Default values'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// Integer default value'#13#10 +
        'function WithDefaultInt(a: Integer = 42): Integer;'#13#10 +
        #13#10 + '// String default value (quoted)'#13#10 +
        'function WithDefaultString(s: string = '#39'default'#39'): string;'#13#10 +
        #13#10 + '// Boolean default value'#13#10 +
        'function WithDefaultBool(flag: Boolean = True): Boolean;'#13#10 +
        #13#10 + '// Floating-point default value'#13#10 +
        'function WithDefaultFloat(pi: Double = 3.14159): Double;'#13#10 +
        #13#10 + '// Constant-expression default value'#13#10 +
        'function WithDefaultConst(x: Integer = MaxBufferSize + 10): Integer;'#13#10 +
        #13#10 + '// Enum default value'#13#10 +
        'function WithDefaultEnum(c: TColor = clRed): TColor;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Grouped parameters (sharing modifier and type)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// const modifier, multiple parameters of the same type'#13#10 +
        'function GroupConst(const a, b, c: Integer): Integer;'#13#10 +
        #13#10 + '// var modifier, same type'#13#10 +
        'procedure GroupVar(var x, y, z: Double);'#13#10 +
        #13#10 + '// Mixed modifiers, same group with different types'#13#10 +
        '// (not legal in real Pascal; included to stress the parser)'#13#10 +
        #13#10 + '// Grouped parameters with default values'#13#10 +
        'function GroupDefault(const a, b: Integer = 0; const s: string = '#39#39'): Boolean;'#13#10 +
        #13#10 + '// More complex: multiple groups'#13#10 +
        'function ComplexGroups(var a, b: Integer; const c: string; out d: Double): Integer;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Complex parameter types'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// Dynamic array'#13#10 +
        'procedure ProcessArray(const Arr: array of Integer);'#13#10 +
        #13#10 + '// Static array'#13#10 +
        'procedure ProcessStaticArray(const Arr: array[0..9] of Integer);'#13#10 +
        #13#10 + '// Record type'#13#10 +
        'procedure ProcessRecord(const P: TPoint);'#13#10 +
        #13#10 + '// Class type'#13#10 +
        'procedure ProcessClass(const Obj: TObject);'#13#10 +
        #13#10 + '// Generic type'#13#10 +
        'procedure ProcessGenericList(const List: TGenericList<string>);'#13#10 +
        #13#10 + '// Procedural type (function pointer)'#13#10 +
        'type'#13#10 + '  TIntFunc = function(x: Integer): Integer;'#13#10 +
        #13#10 + '// Accepts a function pointer'#13#10 +
        'procedure UseFuncPtr(F: TIntFunc);'#13#10 +
        #13#10 + '// Inline procedural type as a parameter (reference to)'#13#10 +
        'procedure UseAnonymous(const F: reference to procedure);'#13#10 +
        #13#10 + '// Complex function type: with parameters and return value'#13#10 +
        'type'#13#10 + '  TBinaryOp = function(a, b: Double): Double;'#13#10 +
        #13#10 + 'procedure UseBinaryOp(Op: TBinaryOp);'#13#10 +
        #13#10 + '// Nested function type as a parameter'#13#10 +
        'procedure UseNestedFunc(F: function(x: Integer): function(y: Integer): Integer);'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  External declarations and calling conventions'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// cdecl calling convention'#13#10 +
        'function CdeclFunc(a: Integer): Integer; cdecl;'#13#10 +
        #13#10 + '// stdcall'#13#10 +
        'procedure StdcallProc(a: Integer; var b: Double); stdcall;'#13#10 +
        #13#10 + '// register'#13#10 +
        'function RegisterFunc(a, b: Integer): Integer; register;'#13#10 +
        #13#10 + '// external library name'#13#10 +
        'function ExternalLib(const Name: PChar): Boolean; cdecl; external '#39'my.dll'#39';'#13#10 +
        #13#10 + '// external + name alias'#13#10 +
        'procedure ExternalAlias; stdcall; external '#39'kernel32'#39' name '#39'GetCurrentProcess'#39';'#13#10 +
        #13#10 + '// external + index'#13#10 +
        'procedure ExternalIndex; stdcall; external '#39'user32'#39' index 10;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Overloads and inheritance modifiers'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// overload'#13#10 +
        'function OverloadTest(a: Integer): Integer; overload;'#13#10 +
        'function OverloadTest(a, b: Integer): Integer; overload;'#13#10 +
        'function OverloadTest(a: Double): Double; overload;'#13#10 +
        #13#10 + '// virtual / override / abstract'#13#10 +
        'type'#13#10 + '  TBase = class'#13#10 +
        '    procedure VirtualProc; virtual;'#13#10 +
        '    function AbstractFunc: Integer; virtual; abstract;'#13#10 +
        '  end;'#13#10 + #13#10 + '  TDerived = class(TBase)'#13#10 +
        '    procedure VirtualProc; override;'#13#10 +
        '    function AbstractFunc: Integer; override;'#13#10 +
        '  end;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Class methods, static methods, constructors'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  TMath = class'#13#10 +
        '  public'#13#10 +
        '    class function StaticAdd(a, b: Integer): Integer; static;'#13#10 +
        '    class procedure StaticProc; static;'#13#10 +
        '    constructor Create(a: Integer);'#13#10 +
        '    destructor Destroy; override;'#13#10 +
        '  end;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Generic methods (inside a generic class)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 +
        '  TGenericClass<T> = class'#13#10 +
        '    function GenericMethod<U>(a: T; b: U): T; // generic method'#13#10 +
        '    procedure ProcWithGenericParam(const List: TList<T>);'#13#10 +
        '  end;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Operator overloads (implicit / explicit)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  TMyRecord = record'#13#10 +
        '    Value: Integer;'#13#10 +
        '    class operator Implicit(a: Integer): TMyRecord;'#13#10 +
        '    class operator Explicit(a: Integer): TMyRecord;'#13#10 +
        '    class operator Add(a, b: TMyRecord): TMyRecord;'#13#10 +
        '  end;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Nested type as a parameter'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  TOuter = class'#13#10 +
        '  public type'#13#10 + '    TInner = record'#13#10 +
        '      X: Integer;'#13#10 + '    end;'#13#10 + '  end;'#13#10 +
        #13#10 + 'procedure UseNestedType(const P: TOuter.TInner);'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Complex default values (strings, arrays, ...)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// String default containing a quote'#13#10 +
        'function StringWithQuotes(s: string = '#39'He said: "Hello"'#39'): string;'#13#10 +
        #13#10 + '// Default value as an array constant is not supported by Pascal'#13#10 +
        #13#10 + '// Default value as an enum constant'#13#10 +
        'function EnumDefault(c: TColor = clBlue): TColor;'#13#10 +
        #13#10 + '// Default value as a set constant'#13#10 +
        'function SetDefault(s: TOptions = [optRead, optWrite]): TOptions;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Function return types (complex)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '// Returns an array'#13#10 +
        'function ReturnArray: TIntArray;'#13#10 +
        #13#10 + '// Returns a record'#13#10 +
        'function ReturnRecord: TPoint;'#13#10 +
        #13#10 + '// Returns a generic list'#13#10 +
        'function ReturnGenericList: TGenericList<string>;'#13#10 +
        #13#10 + '// Returns a function pointer'#13#10 +
        'function ReturnFuncPtr: TIntFunc;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Complex declarations with comments (comment binding test)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + '(*'#13#10 +
        '  A very complex function declaration with multiple parameter'#13#10 +
        '  groups, default values, var / const / out modifiers, and an'#13#10 +
        '  external directive. The comment must be extracted correctly'#13#10 +
        '  and attached to the declaration.'#13#10 + '*)'#13#10 +
        'function SuperComplex('#13#10 +
        '  const Name: string = '#39'default'#39';    // first parameter group, const'#13#10 +
        '  var Value: Integer = 42;           // second parameter group, var + default'#13#10 +
        '  out Flag: Boolean;                 // third parameter group, out'#13#10 +
        '  const Data: array of Byte          // fourth parameter group, array type'#13#10 +
        '): Integer; cdecl; external '#39'lib'#39' name '#39'SuperComplex'#39';'#13#10 +
        #13#10 + '{ Another declaration that takes a procedural type }'#13#10 +
        '{'#13#10 +
        '  This function accepts a binary operation as a parameter and'#13#10 +
        '  returns its application result.'#13#10 + '}'#13#10 +
        'function ApplyBinaryOp('#13#10 +
        '  const Op: TBinaryOp;        // procedural type parameter'#13#10 +
        '  const a, b: Double = 0.0    // default-value parameter group'#13#10 +
        '): Double; overload;'#13#10 +
        #13#10 + '// Another overload, taking an integer operation'#13#10 +
        'function ApplyBinaryOp('#13#10 +
        '  const Op: function(a, b: Integer): Integer;'#13#10 +
        '  const a, b: Integer = 0'#13#10 + '): Integer; overload;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Additional complex structures (classes, interfaces)'#13#10 +
        '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  IMyInterface = interface'#13#10 +
        '    procedure DoIt;'#13#10 + '  end;'#13#10 +
        #13#10 + '  TMyClass = class(TInterfacedObject, IMyInterface)'#13#10 +
        '  private'#13#10 + '    FData: TGenericList<TPoint>;'#13#10 +
        '  public'#13#10 + '    constructor Create;'#13#10 +
        '    procedure DoIt;'#13#10 +
        '    function GetItem(Index: Integer): TPoint;'#13#10 +
        '    property Items[Index: Integer]: TPoint read GetItem; default;'#13#10 +
        '  end;'#13#10 +
        #13#10 + 'implementation'#13#10 + #13#10 + 'end.'#13#10;

    TSourceLanguage.slC: Edit_Source.Text :=
        '/* ComplexTestUnit.h */'#13#10 + #13#10 +
        '#ifndef ComplexTestUnit_H'#13#10 + '#define ComplexTestUnit_H'#13#10 +
        '/* Generated from unit ComplexTestUnit.h */'#13#10 + #13#10 +
        '/* A top-level function with no parameters, returning an integer. */'#13#10 +
        'int NoParamFunc(void);'#13#10 +
        #13#10 + '/* Single-line comment; parameterless procedure. */'#13#10 +
        'void NoParamProc(void);'#13#10 +
        #13#10 + '/* Multi-line block comment,'#13#10 +
        '   used to test comment extraction. */'#13#10 +
        'int MultiLineComment(int a);'#13#10 +
        #13#10 + '/* *'#13#10 + ' * Doxygen-style comment'#13#10 +
        ' * @param a First operand'#13#10 + ' * @param b Second operand'#13#10 +
        ' * @return Sum of the two operands */'#13#10 +
        'int Add(int a, int b);'#13#10 +
        #13#10 + '/* Comment adjacent to the function name */'#13#10 +
        'int Sub(int a, int b);'#13#10 +
        #13#10 + '/* Another comment; adjacent comments should be merged */'#13#10 +
        'double Mul(double a, double b);'#13#10 +
        #13#10 + '/* Multiple parameters of different types */'#13#10 +
        'char * MultipleParams(int a, char * b, double c);'#13#10 +
        #13#10 + '/* const parameter */'#13#10 +
        'void ReadOnlyConst(const char * Value);'#13#10 +
        #13#10 + '/* Integer default value */'#13#10 +
        'int WithDefaultInt(int a);'#13#10 +
        #13#10 + '/* String default value (quoted) */'#13#10 +
        'char * WithDefaultString(char * s);'#13#10 +
        #13#10 + '/* Floating-point default value */'#13#10 +
        'double WithDefaultFloat(double pi);'#13#10 +
        #13#10 + '/* Constant-expression default value */'#13#10 +
        'int WithDefaultConst(int x);'#13#10 +
        #13#10 + '/* const modifier, multiple parameters of the same type */'#13#10 +
        'int GroupConst(const int a, const int b, const int c);'#13#10 +
        #13#10 + '/* cdecl calling convention */'#13#10 +
        'int CdeclFunc(int a);'#13#10 +
        #13#10 + '/* register */'#13#10 +
        'int RegisterFunc(int a, int b);'#13#10 +
        #13#10 + '/* external + name alias */'#13#10 +
        'void ExternalAlias(void);'#13#10 +
        #13#10 + '/* external + index */'#13#10 +
        'void ExternalIndex(void);'#13#10 +
        #13#10 + '/* overload */'#13#10 +
        'int OverloadTest(int a);'#13#10 +
        #13#10 + 'int OverloadTest(int a, int b);'#13#10 +
        'double OverloadTest(double a);'#13#10 +
        #13#10 + '/* String default containing a quote */'#13#10 +
        'char * StringWithQuotes(char * s);'#13#10 +
        #13#10 + '#endif /* ComplexTestUnit_H */'#13#10;

    else Edit_Source.Text := '';
  end;
end;

procedure Tcode_decl_to_abi_form.empty_unit_ButtonClick(Sender: TObject);
begin
  case current_language of
    TSourceLanguage.slPascal: Edit_Source.Text :=
        'unit untitled;' + #13#10 + #13#10 + 'interface' + #13#10 + #13#10 +
        '// Paste declarations here (Ctrl+V).' + #13#10 + #13#10 +
        'implementation' + #13#10 + #13#10 + 'end.' + #13#10;
    TSourceLanguage.slC: Edit_Source.Text :=
        '/* untitled.h */' + #13#10 +
        '#ifndef UNTITLED_H' + #13#10 +
        '#define UNTITLED_H' + #13#10 + #13#10 +
        '/* Paste prototypes here (Ctrl+V). */' +
        #13#10 + #13#10 + '#endif /* UNTITLED_H */' + #13#10;
    else Edit_Source.Text := ''
  end;
end;

procedure Tcode_decl_to_abi_form.GenerateSourceButtonClick(Sender: TObject);
var
  func_model: TPascal_Func_Model;
  l: TPascalStringList;
  app_dir, last_fn: TP_String;

  procedure SaveSynEditCode(edit: TSynEdit; fn: string);
  var
    tmp: TPascalStringList;
  begin
    tmp := TPascalStringList.Create;
    tmp.Assign(edit.Lines);
    last_fn := umlCombineFileName(app_dir.Text, fn);
    tmp.SaveToFile(last_fn);
    DoStatus('Save file "%s"', [last_fn.Text]);
    DisposeObject(tmp);
  end;

  procedure SaveCode(fn: string);
  begin
    last_fn := umlCombineFileName(app_dir.Text, fn);
    l.SaveToFile(last_fn);
    DoStatus('Save file "%s"', [last_fn.Text]);
  end;

begin
  func_model := TPascal_Func_Model.Create;
  func_model.LoadFromJson(Edit_ModelJson.Text);

  app_dir.Text := umlCombinePath(umlGetFilePath(ParamStr(0)), func_model.UnitName);
  umlCreateDirectory(app_dir.Text);

  if Edit_Source.Lines.Count > 0 then
  begin
    if current_language = TSourceLanguage.slC then
      SaveSynEditCode(Edit_Source, 'source.h')
    else
      SaveSynEditCode(Edit_Source, 'source.pas');
  end;

  if Edit_SourceJson.Lines.Count > 0 then
    SaveSynEditCode(Edit_SourceJson, 'source.json');

  if Edit_ModelJson.Lines.Count > 0 then
    SaveSynEditCode(Edit_ModelJson, 'source_model.json');

  { Pascal service code + README }
  l := GenerateABIServicePascalCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service_unit.pas');
    l.AssignTo(Edit_PasServiceSource.Lines);
    Edit_PasServiceSource.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABIServicePascalReadme(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service_pascal.md');
    l.AssignTo(Edit_PasServiceReadme.Lines);
    Edit_PasServiceReadme.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  { Pascal call code + README }
  l := GenerateABICallPascalCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call_unit.pas');
    l.AssignTo(Edit_PasCallSource.Lines);
    Edit_PasCallSource.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABICallPascalReadme(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call_pascal.md');
    l.AssignTo(Edit_PasCallReadme.Lines);
    Edit_PasCallReadme.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  { Python service code + README }
  l := GenerateABIServicePyCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service.py');
    l.AssignTo(Edit_PyServiceSource.Lines);
    Edit_PyServiceSource.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABIServicePyReadme(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service_python.md');
    l.AssignTo(Edit_PyServiceReadme.Lines);
    Edit_PyServiceReadme.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  { Python call code + README }
  l := GenerateABICallPyCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call.py');
    l.AssignTo(Edit_PyCallSource.Lines);
    Edit_PyCallSource.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABICallPyReadme(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call_python.md');
    l.AssignTo(Edit_PyCallReadme.Lines);
    Edit_PyCallReadme.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  { C++ service (.cpp + .hpp + README) }
  l := GenerateABIServiceCppCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service.cpp');
    l.AssignTo(Edit_CppServiceCpp.Lines);
    Edit_CppServiceCpp.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABIServiceHppCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service.hpp');
    l.AssignTo(Edit_CppServiceHpp.Lines);
    Edit_CppServiceHpp.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABIServiceCppReadme(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service_cpp.md');
    l.AssignTo(Edit_CppServiceReadme.Lines);
    Edit_CppServiceReadme.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  { C++ call (.cpp + .hpp + README) }
  l := GenerateABICallCppCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call.cpp');
    l.AssignTo(Edit_CppCallCpp.Lines);
    Edit_CppCallCpp.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABICallHppCode(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call.hpp');
    l.AssignTo(Edit_CppCallHpp.Lines);
    Edit_CppCallHpp.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABICallCppReadme(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call_cpp.md');
    l.AssignTo(Edit_CppCallReadme.Lines);
    Edit_CppCallReadme.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABICmakeScript(func_model);
  if l <> nil then
  begin
    SaveCode('CMakeLists.txt');
    l.AssignTo(Edit_CMake.Lines);
    Edit_CMake.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABIServiceTestProgram(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_service_main.cpp');
    l.AssignTo(Edit_CMake_Service_Test.Lines);
    Edit_CMake_Service_Test.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  l := GenerateABICallTestProgram(func_model);
  if l <> nil then
  begin
    SaveCode(func_model.UnitName + '_abi_call_main.cpp');
    l.AssignTo(Edit_CMake_Call_Test.Lines);
    Edit_CMake_Call_Test.Hint := last_fn.Text;
    disposeObjectAndNil(l);
  end;

  Page_Main.ActivePage := Tab_FinalSource;
  func_model.Free;
end;

procedure Tcode_decl_to_abi_form.Open_c_rule_ButtonClick(Sender: TObject);
var
  ph, fn: U_String;
begin
  ph := umlGetFilePath(ParamStr(0));
  fn := umlCombineFileName(ph, 'C_code_abi_rule.md');
  if umlFileExists(fn) then
    OpenDocument(fn.Text);
end;

procedure Tcode_decl_to_abi_form.Open_pascal_rule_ButtonClick(Sender: TObject);
var
  ph, fn: U_String;
begin
  ph := umlGetFilePath(ParamStr(0));
  fn := umlCombineFileName(ph, 'pascal_code_abi_rule.md');
  if umlFileExists(fn) then
    OpenDocument(fn.Text);
end;

procedure Tcode_decl_to_abi_form.Sel_Lang_ComboBoxChange(Sender: TObject);
begin
  case Cmb_LanguageSelector.ItemIndex of
    1: // Pascal
    begin
      Edit_Source.Highlighter := HL_Pascal;
      current_language := TSourceLanguage.slPascal;
    end;
    2: // C / C++
    begin
      Edit_Source.Highlighter := HL_Cpp;
      current_language := TSourceLanguage.slC;
    end;
    else
    begin
      Edit_Source.Highlighter := HL_Any;
      current_language := TSourceLanguage.slUnknown;
    end;
  end;
end;

procedure Tcode_decl_to_abi_form.sel_lang_LabelClick(Sender: TObject);
begin
  Auto_Select_Language;
end;

procedure Tcode_decl_to_abi_form.source_2_json_nex_ButtonClick(Sender: TObject);
begin
  case current_language of
    TSourceLanguage.slPascal:
    begin
      with tpascal_func_decl_tool.CreateFrom_Pascal_Code(Edit_Source.Text) do
      begin
        Edit_SourceJson.Text := SaveToJson();
        Free;
      end;
    end;
    TSourceLanguage.slC:
    begin
      with tpascal_func_decl_tool.CreateFrom_C_Code(Edit_Source.Text) do
      begin
        Edit_SourceJson.Text := SaveToJson();
        Free;
      end;
    end;
    else
    begin
      DoStatus('Unsupported source language.');
      exit;
    end;
  end;

  Page_Main.ActivePage := Tab_SourceJson;
  DoStatus('Source -> JSON completed.');
end;

procedure Tcode_decl_to_abi_form.Formater_source_ButtonClick(Sender: TObject);
var
  Report: TPascalStringList;
begin
  case current_language of
    TSourceLanguage.slPascal:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.CreateFrom_Pascal_Code(Edit_Source.Text) do
      begin
        Edit_Source.Text := decl_to_pascal(Report);
        Free;
      end;
    end;
    TSourceLanguage.slC:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.CreateFrom_C_Code(Edit_Source.Text) do
      begin
        Edit_Source.Text := decl_to_c(Report);
        Free;
      end;
    end;
    else
    begin
      DoStatus('Unsupported source language.');
      exit;
    end;
  end;

  DoStatus(Report.AsText);
  DoStatus('Source rebuilt: only top-level routines are kept.');
  DisposeObject(Report);
end;

procedure Tcode_decl_to_abi_form.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  Hide;
end;

procedure Tcode_decl_to_abi_form.sysTimerTimer(Sender: TObject);
begin
  Check_Soft_Thread_Synchronize;
  LF___.LF_Sync;
end;

procedure Tcode_decl_to_abi_form.to_source_ButtonClick(Sender: TObject);
begin
  Page_Main.ActivePage := Tab_Source;
end;

constructor Tcode_decl_to_abi_form.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  current_language := TSourceLanguage.slUnknown;

  Cmb_LanguageSelector.ItemIndex := 2;
  Sel_Lang_ComboBoxChange(Cmb_LanguageSelector);
  empty_unit_ButtonClick(Btn_LoadEmptyUnit);

  TCompute.RunM_NP(Do_Init_Th);
end;

destructor Tcode_decl_to_abi_form.Destroy;
begin
  inherited Destroy;
end;

procedure Tcode_decl_to_abi_form.Do_Init_Th;
begin
  LF_SetOptionEx('WaitConnect', 'True');
  LF_SetOptionEx('Overlap_Connection', 'True');
  code_decl_to_abi_mcp_api_tool_provider_unit.Execute_And_Reg_all();
end;

procedure Tcode_decl_to_abi_form.Auto_Select_Language;
begin
  current_language := DetectSourceLanguage(Edit_Source.Text);
  case current_language of
    slPascal: Cmb_LanguageSelector.ItemIndex := 1;
    slC: Cmb_LanguageSelector.ItemIndex := 2;
    else Cmb_LanguageSelector.ItemIndex := 0;
  end;
  Sel_Lang_ComboBoxChange(Cmb_LanguageSelector);
end;

end.
