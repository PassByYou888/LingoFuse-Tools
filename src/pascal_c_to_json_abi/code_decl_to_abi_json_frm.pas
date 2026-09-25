unit code_decl_to_abi_json_frm;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  LazHelpHTML, ComCtrls, Menus, AsyncProcess, ActnList, LCLIntf, PairSplitter,
  SynHighlighterCpp, SynHighlighterAny, SynEdit, SynHighlighterPas,
  SynEditMiscClasses,
  lingofuse_helper, lingofuse_import,
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Parsing, Z.Expression,
  Z.ListEngine, Z.Notify, Z.UnicodeMixedLib, Z.Status, Z.MemoryStream,
  Z.Json, Z.HashList.Templet,
  Z.Pascal_Func_Model, Z.Pascal_Func_Tool,
  http_pas_abi_service_generator_tool,
  http_pas_abi_call_generator_tool,
  http_js_abi_call_generator_tool,
  http_py_abi_service_generator_tool,
  http_py_abi_call_generator_tool,
  http_cpp_abi_service_generator_tool,
  http_cpp_abi_call_generator_tool,
  code_decl_to_json_abi_mcp_api_tool_provider_unit, http_cmake_generator_tool;

type

  { Tcode_decl_to_abi_json_form }

  Tcode_decl_to_abi_json_form = class(TForm)
    BackToModelJsonButton: TButton;
    CMake_TestMain_Editor: TSynEdit;
    CppCallHeaderEditor: TSynEdit;
    CppCallHeaderSide: TPairSplitterSide;
    CppCallImplEditor: TSynEdit;
    CppCallImplSide: TPairSplitterSide;
    CppCallReadmeEditor: TSynEdit;
    CMakeEditor: TSynEdit;
    CppCallSplitter: TPairSplitter;
    CppServiceHeaderEditor: TSynEdit;
    CppServiceHeaderSide: TPairSplitterSide;
    CppServiceImplEditor: TSynEdit;
    CppServiceImplSide: TPairSplitterSide;
    CppServiceReadmeEditor: TSynEdit;
    CppServiceSplitter: TPairSplitter;
    DenormalizeModelToJsonButton: TButton;
    FinalSourceHintLabel: TLabel;
    FinalSourcePageControl: TPageControl;
    FinalSourceSpacerBevel: TBevel;
    FinalSourceTabSheet: TTabSheet;
    FinalSourceToolbarPanel: TPanel;
    FormatSourceButton: TButton;
    GenerateAllSourcesButton: TButton;
    GoToSourceButton: TButton;
    HttpCppCallReadmeTabSheet: TTabSheet;
    HttpCppCallTabSheet: TTabSheet;
    HttpCppServiceReadmeTabSheet: TTabSheet;
    HttpCppServiceTabSheet: TTabSheet;
    HttpJavaScriptCallTabSheet: TTabSheet;
    HttpJavaScriptTestTabSheet: TTabSheet;
    HttpPascalCallSplitter: TPairSplitter;
    HttpPascalCallTabSheet: TTabSheet;
    HttpPascalServiceSplitter: TPairSplitter;
    HttpPascalServiceTabSheet: TTabSheet;
    HttpPythonCallTabSheet: TTabSheet;
    HttpPythonServiceTabSheet: TTabSheet;
    InsertEmptyUnitButton: TButton;
    InsertTestUnitButton: TButton;
    JavaScriptCallCodeEditor: TSynEdit;
    JavaScriptCallReadmeEditor: TSynEdit;
    JavaScriptCallSplitter: TPairSplitter;
    JavaScriptCodeSide: TPairSplitterSide;
    JavaScriptReadmeSide: TPairSplitterSide;
    JavaScriptTestHtmlEditor: TSynEdit;
    LanguageSelectorComboBox: TComboBox;
    MainPageControl: TPageControl;
    ModelJsonEditor: TSynEdit;
    ModelJsonHintLabel: TLabel;
    ModelJsonSpacerBevel1: TBevel;
    ModelJsonSpacerBevel2: TBevel;
    ModelJsonTabSheet: TTabSheet;
    ModelJsonToolbarPanel: TPanel;
    NormalizeJsonToModelButton: TButton;
    OpenCRuleButton: TButton;
    OpenPascalRuleButton: TButton;
    PairSplitter1: TPairSplitter;
    PairSplitterSide1: TPairSplitterSide;
    PairSplitterSide2: TPairSplitterSide;
    ParseSourceToJsonButton: TButton;
    PascalCallCodeEditor: TSynEdit;
    PascalCallCodeSide: TPairSplitterSide;
    PascalCallReadmeEditor: TSynEdit;
    PascalCallReadmeSide: TPairSplitterSide;
    PascalServiceCodeEditor: TSynEdit;
    PascalServiceCodeSide: TPairSplitterSide;
    PascalServiceReadmeEditor: TSynEdit;
    PascalServiceReadmeSide: TPairSplitterSide;
    PythonCallCodeEditor: TSynEdit;
    PythonCallCodeSide: TPairSplitterSide;
    PythonCallReadmeEditor: TSynEdit;
    PythonCallReadmeSide: TPairSplitterSide;
    PythonCallSplitter: TPairSplitter;
    PythonServiceCodeEditor: TSynEdit;
    PythonServiceCodeSide: TPairSplitterSide;
    PythonServiceReadmeEditor: TSynEdit;
    PythonServiceReadmeSide: TPairSplitterSide;
    PythonServiceSplitter: TPairSplitter;
    RebuildCodeFromJsonButton: TButton;
    SelectLanguageLabel: TLabel;
    SourceCodeEditor: TSynEdit;
    SourceCodeTabSheet: TTabSheet;
    SourceJsonEditor: TSynEdit;
    SourceJsonHintLabel: TLabel;
    SourceJsonSpacerBevel1: TBevel;
    SourceJsonSpacerBevel2: TBevel;
    SourceJsonTabSheet: TTabSheet;
    SourceJsonToolbarPanel: TPanel;
    SourceToolbarPanel: TPanel;
    SourceToolbarSpacerBevel1: TBevel;
    SourceToolbarSpacerBevel2: TBevel;
    SourceToolbarSpacerBevel3: TBevel;

    (* ---- Misc ---- *)
    StatusRefreshTimer: TTimer;
    PascalSyntaxHighlighter: TSynFreePascalSyn;
    AnySyntaxHighlighter: TSynAnySyn;
    CppSyntaxHighlighter: TSynCppSyn;
    HttpCMakeTabSheet: TTabSheet;
    WelcomeHintLabel: TLabel;
    WelcomeTabSheet: TTabSheet;
    WelcomeTextMemo: TMemo;
    WelcomeToolbarPanel: TPanel;
    WelcomeToolbarSpacerBevel: TBevel;

    procedure RebuildCodeFromJsonClick(Sender: TObject);
    procedure NormalizeJsonToModelClick(Sender: TObject);
    procedure DenormalizeModelToJsonClick(Sender: TObject);
    procedure BackToModelJsonClick(Sender: TObject);
    procedure InsertTestUnitClick(Sender: TObject);
    procedure InsertEmptyUnitClick(Sender: TObject);
    procedure GenerateAllSourcesClick(Sender: TObject);
    procedure OpenCRuleClick(Sender: TObject);
    procedure OpenPascalRuleClick(Sender: TObject);
    procedure LanguageSelectorChange(Sender: TObject);
    procedure LanguageHintClick(Sender: TObject);
    procedure ParseSourceToJsonClick(Sender: TObject);
    procedure FormatSourceClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure StatusRefreshTimerTick(Sender: TObject);
    procedure GoToSourceClick(Sender: TObject);
  private
    CurrentSourceLanguage: TSourceLanguage;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure StartMcpService;
    procedure AutoDetectSourceLanguage;
  end;

var
  code_decl_to_abi_json_form: Tcode_decl_to_abi_json_form;

implementation

{$R *.lfm}

type
  (* A generator is a free function that consumes a TPascal_Func_Model
     and returns a TPascalStringList of the produced text lines, or nil
     when the model is unusable. All HTTP/JSON generators follow this
     contract, which lets the batch-emit step below stay fully data
     driven: one table entry per artifact. *)
  TSourceGeneratorFunc = function(Model: TPascal_Func_Model): TPascalStringList;

(* ============================================================================
 * JSON -> source code rebuild
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.RebuildCodeFromJsonClick(Sender: TObject);
var
  Report: TPascalStringList;
begin
  case CurrentSourceLanguage of
    TSourceLanguage.slPascal:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.Create do
      begin
        LoadFromJson(SourceJsonEditor.Text);
        SourceCodeEditor.Text := decl_to_pascal(Report);
        Free;
      end;
    end;
    TSourceLanguage.slC:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.Create do
      begin
        LoadFromJson(SourceJsonEditor.Text);
        SourceCodeEditor.Text := decl_to_c(Report);
        Free;
      end;
    end;
    else
    begin
      DoStatus('Unsupported language.');
      exit;
    end;
  end;

  DoStatus('Rebuilt source code from JSON.');
  DoStatus(Report.AsText);
  MainPageControl.ActivePage := SourceCodeTabSheet;
  DisposeObject(Report);
end;

(* ============================================================================
 * LV0 JSON -> LV1 Model JSON
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.NormalizeJsonToModelClick(Sender: TObject);
var
  func_tool: tpascal_func_decl_tool;
  func_model: TPascal_Func_Model;
  Report: TPascalStringList;
begin
  func_tool := tpascal_func_decl_tool.Create;
  func_tool.LoadFromJson(SourceJsonEditor.Text);

  Report := TPascalStringList.Create;

  func_model := TPascal_Func_Model.Create;
  func_model.Typ_Normalize_Func := tnf_Json;
  func_model.LoadFromParser(func_tool, Report);
  ModelJsonEditor.Text := func_model.SaveToJson;

  DisposeObject(func_tool);

  DoStatus('Normalized LV0 JSON into LV1 Model JSON.');
  DoStatus(Report.AsText);
  MainPageControl.ActivePage := ModelJsonTabSheet;
  DisposeObject(Report);
end;

(* ============================================================================
 * LV1 Model JSON -> LV0 JSON (reverse)
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.DenormalizeModelToJsonClick(Sender: TObject);
var
  func_tool: tpascal_func_decl_tool;
  func_model: TPascal_Func_Model;
begin
  func_model := TPascal_Func_Model.Create;
  func_model.Typ_Normalize_Func := tnf_Json;
  func_model.LoadFromJson(ModelJsonEditor.Text);

  func_tool := tpascal_func_decl_tool.Create;
  func_model.SaveToParser(func_tool);

  SourceJsonEditor.Text := func_tool.SaveToJson;

  DisposeObject(func_tool);
  DisposeObject(func_model);

  MainPageControl.ActivePage := SourceJsonTabSheet;
end;

procedure Tcode_decl_to_abi_json_form.BackToModelJsonClick(Sender: TObject);
begin
  MainPageControl.ActivePage := ModelJsonTabSheet;
end;

(* ============================================================================
 * Test unit: complex sample covering many syntax variants
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.InsertTestUnitClick(Sender: TObject);
begin
  case CurrentSourceLanguage of
    TSourceLanguage.slPascal: SourceCodeEditor.Text :=
        'unit ComplexTestUnit;'#13#10 + #13#10 + '{'#13#10 + '  A complex unit used to exercise the parser (Z.Pascal_Func_Tool).'#13#10 +
        '  It contains a wide range of advanced and edge-case syntax'#13#10 + '  constructs, to validate parser robustness and completeness.'#13#10 +
        '  All declarations are syntactically correct; implementations'#13#10 + '  are omitted (interface-only test).'#13#10 +
        '}'#13#10 + #13#10 + '{$mode objfpc}{$H+}'#13#10 + '{$modeswitch advancedrecords}'#13#10 + '{$modeswitch typehelpers}'#13#10 +
        #13#10 + 'interface'#13#10 + #13#10 + 'uses'#13#10 + '  SysUtils, Classes, Generics.Collections, TypInfo,'#13#10 +
        '  Z.Core, Z.PascalStrings, Math;'#13#10 + #13#10 + '{ ==========================================================================='#13#10 +
        '  Comment style tests (multiple formats)'#13#10 + '  =========================================================================== }'#13#10 +
        #13#10 + '(* Top-level function, no parameters, returns Integer *)'#13#10 + 'function NoParamFunc: Integer;'#13#10 + #13#10 +
        '// Single-line comment, parameterless procedure'#13#10 + 'procedure NoParamProc;'#13#10 + #13#10 + '{'#13#10 +
        '  Multi-line comment block,'#13#10 + '  tests comment extraction.'#13#10 + '}'#13#10 +
        'function MultiLineComment(a: Integer): Integer;'#13#10 + #13#10 + '(**'#13#10 + ' * Doxygen-style comment'#13#10 +
        ' * @param a First parameter'#13#10 + ' * @param b Second parameter'#13#10 + ' * @return Sum of a and b'#13#10 +
        ' *)'#13#10 + 'function Add(a, b: Integer): Integer;'#13#10 + #13#10 + '{ Comment right before the function name }'#13#10 +
        'function Sub(a, b: Integer): Integer; // Trailing comment must not be bound'#13#10 + #13#10 + '(* Comment with star prefix *)'#13#10 +
        '// Another comment; two consecutive lines should be merged'#13#10 + 'function Mul(a, b: Double): Double;'#13#10 + #13#10 +
        '{ ==========================================================================='#13#10 + '  Basic parameter declarations'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// Single parameter'#13#10 +
        'function SingleParam(x: Integer): Boolean;'#13#10 + #13#10 + '// Multiple parameters, different types'#13#10 +
        'function MultipleParams(a: Integer; b: string; c: Double): string;'#13#10 + #13#10 + '// var parameter'#13#10 +
        'procedure ModifyVar(var Value: Integer);'#13#10 + #13#10 + '// const parameter'#13#10 + 'procedure ReadOnlyConst(const Value: string);'#13#10 +
        #13#10 + '// out parameter'#13#10 + 'procedure GetValue(out Result: Integer);'#13#10 + #13#10 + '// Mixed modifiers'#13#10 +
        'procedure MixedMods(const Input: string; var Output: Integer; out ErrorCode: Integer);'#13#10 + #13#10 +
        '{ ==========================================================================='#13#10 + '  Default values'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// Integer default'#13#10 +
        'function WithDefaultInt(a: Integer = 42): Integer;'#13#10 + #13#10 + '// String default (quoted)'#13#10 +
        'function WithDefaultString(s: string = '#39'default'#39'): string;'#13#10 + #13#10 + '// Boolean default'#13#10 +
        'function WithDefaultBool(flag: Boolean = True): Boolean;'#13#10 + #13#10 + '// Floating-point default'#13#10 +
        'function WithDefaultFloat(pi: Double = 3.14159): Double;'#13#10 + #13#10 + '// Constant-expression default'#13#10 +
        'function WithDefaultConst(x: Integer = MaxBufferSize + 10): Integer;'#13#10 + #13#10 + '// Enum default'#13#10 +
        'function WithDefaultEnum(c: TColor = clRed): TColor;'#13#10 + #13#10 + '{ ==========================================================================='#13#10 +
        '  Grouped parameters (shared modifier and type)'#13#10 + '  =========================================================================== }'#13#10 +
        #13#10 + '// const modifier, multiple same-type parameters'#13#10 + 'function GroupConst(const a, b, c: Integer): Integer;'#13#10 +
        #13#10 + '// var modifier, same type'#13#10 + 'procedure GroupVar(var x, y, z: Double);'#13#10 + #13#10 +
        '// Same group with default values'#13#10 + 'function GroupDefault(const a, b: Integer = 0; const s: string = '#39#39'): Boolean;'#13#10 +
        #13#10 + '// More complex: multiple groups'#13#10 + 'function ComplexGroups(var a, b: Integer; const c: string; out d: Double): Integer;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 + '  Complex type parameters'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// Dynamic array'#13#10 +
        'procedure ProcessArray(const Arr: array of Integer);'#13#10 + #13#10 + '// Static array'#13#10 +
        'procedure ProcessStaticArray(const Arr: array[0..9] of Integer);'#13#10 + #13#10 + '// Record type'#13#10 +
        'procedure ProcessRecord(const P: TPoint);'#13#10 + #13#10 + '// Class type'#13#10 + 'procedure ProcessClass(const Obj: TObject);'#13#10 +
        #13#10 + '// Generic type'#13#10 + 'procedure ProcessGenericList(const List: TGenericList<string>);'#13#10 + #13#10 +
        '// Function-pointer type (procedural type in Pascal)'#13#10 + 'type'#13#10 + '  TIntFunc = function(x: Integer): Integer;'#13#10 +
        #13#10 + '// Accepts a function pointer'#13#10 + 'procedure UseFuncPtr(F: TIntFunc);'#13#10 + #13#10 +
        '// Inline function type as a parameter (reference to)'#13#10 + 'procedure UseAnonymous(const F: reference to procedure);'#13#10 +
        #13#10 + '// Complex function type: parameters and return value'#13#10 + 'type'#13#10 + '  TBinaryOp = function(a, b: Double): Double;'#13#10 +
        #13#10 + 'procedure UseBinaryOp(Op: TBinaryOp);'#13#10 + #13#10 + '// Nested function type (function returning a function)'#13#10 +
        'procedure UseNestedFunc(F: function(x: Integer): function(y: Integer): Integer);'#13#10 + #13#10 +
        '{ ==========================================================================='#13#10 + '  External declarations and calling conventions'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// cdecl calling convention'#13#10 +
        'function CdeclFunc(a: Integer): Integer; cdecl;'#13#10 + #13#10 + '// stdcall'#13#10 + 'procedure StdcallProc(a: Integer; var b: Double); stdcall;'#13#10 +
        #13#10 + '// register'#13#10 + 'function RegisterFunc(a, b: Integer): Integer; register;'#13#10 + #13#10 +
        '// external library name'#13#10 + 'function ExternalLib(const Name: PChar): Boolean; cdecl; external '#39'my.dll'#39';'#13#10 +
        #13#10 + '// external + name alias'#13#10 + 'procedure ExternalAlias; stdcall; external '#39'kernel32'#39' name '#39'GetCurrentProcess'#39';'#13#10 +
        #13#10 + '// external + index'#13#10 + 'procedure ExternalIndex; stdcall; external '#39'user32'#39' index 10;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 + '  Overload and inheritance modifiers'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// overload'#13#10 +
        'function OverloadTest(a: Integer): Integer; overload;'#13#10 + 'function OverloadTest(a, b: Integer): Integer; overload;'#13#10 +
        'function OverloadTest(a: Double): Double; overload;'#13#10 + #13#10 + '// virtual / override / abstract'#13#10 +
        'type'#13#10 + '  TBase = class'#13#10 + '    procedure VirtualProc; virtual;'#13#10 +
        '    function AbstractFunc: Integer; virtual; abstract;'#13#10 + '  end;'#13#10 + #13#10 + '  TDerived = class(TBase)'#13#10 +
        '    procedure VirtualProc; override;'#13#10 + '    function AbstractFunc: Integer; override;'#13#10 + '  end;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 + '  Class methods, static methods, constructors, etc.'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + 'type'#13#10 +
        '  TMath = class'#13#10 + '  public'#13#10 + '    class function StaticAdd(a, b: Integer): Integer; static;'#13#10 +
        '    class procedure StaticProc; static;'#13#10 + '    constructor Create(a: Integer);'#13#10 + '    destructor Destroy; override;'#13#10 +
        '  end;'#13#10 + #13#10 + '{ ==========================================================================='#13#10 +
        '  Generic methods (inside a generic class)'#13#10 + '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  TGenericClass<T> = class'#13#10 + '    function GenericMethod<U>(a: T; b: U): T;'#13#10 +
        '    procedure ProcWithGenericParam(const List: TList<T>);'#13#10 + '  end;'#13#10 + #13#10 +
        '{ ==========================================================================='#13#10 + '  Operator overloads (implicit, explicit)'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + 'type'#13#10 +
        '  TMyRecord = record'#13#10 + '    Value: Integer;'#13#10 + '    class operator Implicit(a: Integer): TMyRecord;'#13#10 +
        '    class operator Explicit(a: Integer): TMyRecord;'#13#10 + '    class operator Add(a, b: TMyRecord): TMyRecord;'#13#10 +
        '  end;'#13#10 + #13#10 + '{ ==========================================================================='#13#10 +
        '  Nested type as parameter'#13#10 + '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  TOuter = class'#13#10 + '  public type'#13#10 + '    TInner = record'#13#10 +
        '      X: Integer;'#13#10 + '    end;'#13#10 + '  end;'#13#10 + #13#10 + 'procedure UseNestedType(const P: TOuter.TInner);'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 + '  Complex default values (strings, arrays, etc.)'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// String default containing quotes'#13#10 +
        'function StringWithQuotes(s: string = '#39'He said: "Hello"'#39'): string;'#13#10 + #13#10 + '// Enum constant default'#13#10 +
        'function EnumDefault(c: TColor = clBlue): TColor;'#13#10 + #13#10 + '// Set constant default'#13#10 +
        'function SetDefault(s: TOptions = [optRead, optWrite]): TOptions;'#13#10 + #13#10 +
        '{ ==========================================================================='#13#10 + '  Complex return types'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '// Returns an array'#13#10 +
        'function ReturnArray: TIntArray;'#13#10 + #13#10 + '// Returns a record'#13#10 + 'function ReturnRecord: TPoint;'#13#10 +
        #13#10 + '// Returns a generic list'#13#10 + 'function ReturnGenericList: TGenericList<string>;'#13#10 + #13#10 +
        '// Returns a function pointer'#13#10 + 'function ReturnFuncPtr: TIntFunc;'#13#10 + #13#10 +
        '{ ==========================================================================='#13#10 + '  Complex declarations with comments (comment-binding test)'#13#10 +
        '  =========================================================================== }'#13#10 + #13#10 + '(*'#13#10 +
        '  A very complex function declaration with multiple parameter'#13#10 + '  groups, defaults, var/const/out, and external directives.'#13#10 +
        '  The comment must be extracted and attached to this function.'#13#10 + '*)'#13#10 + 'function SuperComplex('#13#10 +
        '  const Name: string = '#39'default'#39';    // First group, const modifier'#13#10 +
        '  var Value: Integer = 42;           // Second group, var modifier with default'#13#10 +
        '  out Flag: Boolean;                 // Third group, out modifier'#13#10 + '  const Data: array of Byte          // Fourth group, array type'#13#10 +
        '): Integer; cdecl; external '#39'lib'#39' name '#39'SuperComplex'#39';'#13#10 + #13#10 + '{ Another declaration with a function-type parameter }'#13#10 +
        '{'#13#10 + '  A function that takes a binary-op function as a parameter and'#13#10 + '  returns the result of applying it.'#13#10 +
        '}'#13#10 + 'function ApplyBinaryOp('#13#10 + '  const Op: TBinaryOp;        // Function-type parameter'#13#10 +
        '  const a, b: Double = 0.0    // Default-value parameter group'#13#10 + '): Double; overload;'#13#10 + #13#10 +
        '// Another overload that takes an integer operation'#13#10 + 'function ApplyBinaryOp('#13#10 +
        '  const Op: function(a, b: Integer): Integer;'#13#10 + '  const a, b: Integer = 0'#13#10 + '): Integer; overload;'#13#10 +
        #13#10 + '{ ==========================================================================='#13#10 +
        '  Some additional complex structures (classes, interfaces)'#13#10 + '  =========================================================================== }'#13#10 +
        #13#10 + 'type'#13#10 + '  IMyInterface = interface'#13#10 + '    procedure DoIt;'#13#10 + '  end;'#13#10 +
        #13#10 + '  TMyClass = class(TInterfacedObject, IMyInterface)'#13#10 + '  private'#13#10 + '    FData: TGenericList<TPoint>;'#13#10 +
        '  public'#13#10 + '    constructor Create;'#13#10 + '    procedure DoIt;'#13#10 + '    function GetItem(Index: Integer): TPoint;'#13#10 +
        '    property Items[Index: Integer]: TPoint read GetItem; default;'#13#10 + '  end;'#13#10 + #13#10 + 'implementation'#13#10 + #13#10 + 'end.'#13#10;

    TSourceLanguage.slC: SourceCodeEditor.Text :=
        '/* ComplexTestUnit.h */'#13#10 + #13#10 + '#ifndef ComplexTestUnit_H'#13#10 + '#define ComplexTestUnit_H'#13#10 +
        '/* Generated from unit ComplexTestUnit.h */'#13#10 + #13#10 + '/* Top-level function, no parameters, returns Integer */'#13#10 +
        'int NoParamFunc(void);'#13#10 + #13#10 + '/* Single-line comment, parameterless procedure */'#13#10 + 'void NoParamProc(void);'#13#10 +
        #13#10 + '/* Multi-line comment block,'#13#10 + '   tests comment extraction. */'#13#10 + 'int MultiLineComment(int a);'#13#10 +
        #13#10 + '/* *'#13#10 + ' * Doxygen-style comment'#13#10 + ' * @param a First parameter'#13#10 +
        ' * @param b Second parameter'#13#10 + ' * @return Sum of a and b */'#13#10 + 'int Add(int a, int b);'#13#10 + #13#10 +
        '/* Comment right before the function name */'#13#10 + 'int Sub(int a, int b);'#13#10 + #13#10 +
        '/* Another comment; consecutive lines merge */'#13#10 + 'double Mul(double a, double b);'#13#10 + #13#10 +
        '/* Multiple parameters, different types */'#13#10 + 'char * MultipleParams(int a, char * b, double c);'#13#10 + #13#10 +
        '/* const parameter */'#13#10 + 'void ReadOnlyConst(const char * Value);'#13#10 + #13#10 + '/* Integer default */'#13#10 +
        'int WithDefaultInt(int a);'#13#10 + #13#10 + '/* String default (quoted) */'#13#10 + 'char * WithDefaultString(char * s);'#13#10 +
        #13#10 + '/* Floating-point default */'#13#10 + 'double WithDefaultFloat(double pi);'#13#10 + #13#10 +
        '/* Constant-expression default */'#13#10 + 'int WithDefaultConst(int x);'#13#10 + #13#10 + '/* const modifier, multiple same-type parameters */'#13#10 +
        'int GroupConst(const int a, const int b, const int c);'#13#10 + #13#10 + '/* cdecl calling convention */'#13#10 +
        'int CdeclFunc(int a);'#13#10 + #13#10 + '/* register */'#13#10 + 'int RegisterFunc(int a, int b);'#13#10 + #13#10 +
        '/* external + name alias */'#13#10 + 'void ExternalAlias(void);'#13#10 + #13#10 + '/* external + index */'#13#10 +
        'void ExternalIndex(void);'#13#10 + #13#10 + '/* overload */'#13#10 + 'int OverloadTest(int a);'#13#10 + #13#10 +
        'int OverloadTest(int a, int b);'#13#10 + 'double OverloadTest(double a);'#13#10 + #13#10 + '/* String default containing quotes */'#13#10 +
        'char * StringWithQuotes(char * s);'#13#10 + #13#10 + '#endif /* ComplexTestUnit_H */'#13#10;

    else SourceCodeEditor.Text := '';
  end;
end;

(* ============================================================================
 * Empty unit: insert a minimal skeleton template
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.InsertEmptyUnitClick(Sender: TObject);
begin
  case CurrentSourceLanguage of
    TSourceLanguage.slPascal: SourceCodeEditor.Text :=
        'unit untitled;' + #13#10 + #13#10 + 'interface' + #13#10 + #13#10 + '// Paste declarations here.' + #13#10 + #13#10 +
        'implementation' + #13#10 + #13#10 + 'end.' + #13#10;
    TSourceLanguage.slC: SourceCodeEditor.Text :=
        '/* untitled.h */' + #13#10 + '#ifndef UNTITLED_H' + #13#10 + '#define UNTITLED_H' + #13#10 + #13#10 +
        '/* Paste prototypes here. */' + #13#10 + #13#10 + '#endif /* UNTITLED_H */' + #13#10;
    else SourceCodeEditor.Text := '';
  end;
end;

(* ============================================================================
 * Core: LV1 Model JSON -> full set of HTTP/JSON target artifacts
 *
 * Workflow:
 *   1. Parse the LV1 Model JSON into a TPascal_Func_Model.
 *   2. Create a per-unit output directory next to the executable.
 *   3. Dump the three in-editor sources (source.pas/h, source.json,
 *      source_model.json) for traceability.
 *   4. Run every generator through a single data-driven emit helper:
 *      for each (generator, filename-suffix, target editor) triple,
 *      invoke the generator, write the result to disk, and mirror the
 *      text into the corresponding TSynEdit.
 *   5. Switch to the "Final source" tab.
 *
 * The whole generator fan-out is expressed as one flat list of Emit()
 * calls, so adding or removing an artifact is a one-line change.
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.GenerateAllSourcesClick(Sender: TObject);
var
  func_model: TPascal_Func_Model;
  unit_name, app_dir: TP_String;

(* Persist the current content of an editor to disk, if non-empty. *)
  procedure SaveEditorSnapshot(editor: TSynEdit; const file_name: string);
  var
    tmp: TPascalStringList;
  begin
    if editor.Lines.Count = 0 then
      exit;
    tmp := TPascalStringList.Create;
    try
      tmp.Assign(editor.Lines);
      tmp.SaveToFile(umlCombineFileName(app_dir.Text, file_name));
      DoStatus('Saved: %s', [file_name]);
    finally
      tmp.Free;
    end;
  end;

  (* Run a generator, persist its output under
       <app_dir>/<unit_name><suffix>,
     and mirror the text into the target editor. Nil results mean the
     generator refused the model and are silently skipped. *)
  procedure Emit(gen: TSourceGeneratorFunc; const suffix: TP_String; editor: TSynEdit);
  var
    Text: TPascalStringList;
    full_name: TP_String;
  begin
    Text := gen(func_model);
    if Text = nil then
      exit;
    try
      if suffix.Same('CMakeLists.txt', 'test_main___.cpp') then
        full_name := umlCombineFileName(app_dir.Text, suffix)
      else
        full_name := umlCombineFileName(app_dir.Text, unit_name + suffix);

      Text.SaveToFile(full_name);
      DoStatus('Saved: %s', [full_name.Text]);
      Text.AssignTo(editor.Lines);
      editor.Hint := full_name.Text;
    finally
      DisposeObject(Text);
    end;
  end;

begin
  func_model := TPascal_Func_Model.Create;
  try
    func_model.LoadFromJson(ModelJsonEditor.Text);
    if func_model.FuncCount <= 0 then
    begin
      DoStatus('No functions found in the model.');
      exit;
    end;

    unit_name := func_model.UnitName;
    app_dir.Text := umlCombinePath(umlGetFilePath(ParamStr(0)), unit_name);
    umlCreateDirectory(app_dir.Text);

    DoStatus('Generating all artifacts for unit "%s" into "%s".',
      [unit_name.Text, app_dir.Text]);

    (* ---- Snapshot the three in-editor inputs ---- *)
    if CurrentSourceLanguage = TSourceLanguage.slC then
      SaveEditorSnapshot(SourceCodeEditor, 'source.h')
    else
      SaveEditorSnapshot(SourceCodeEditor, 'source.pas');
    SaveEditorSnapshot(SourceJsonEditor, 'source.json');
    SaveEditorSnapshot(ModelJsonEditor, 'source_model.json');

    (* ---- Pascal service / call ---- *)
    Emit(GenerateHTTPServicePascalCode,
      '_http_json_service_unit.pas', PascalServiceCodeEditor);
    Emit(GenerateHTTPServicePascalReadme,
      '_http_json_service_pascal.md', PascalServiceReadmeEditor);
    Emit(GenerateHTTPCallPascalCode,
      '_http_json_call_unit.pas', PascalCallCodeEditor);
    Emit(GenerateHTTPCallPascalReadme,
      '_http_json_call_pascal.md', PascalCallReadmeEditor);

    (* ---- JavaScript call (client library + HTML test page) ---- *)
    Emit(GenerateHTTPCallJsCode,
      '_http_json_call.js', JavaScriptCallCodeEditor);
    Emit(GenerateHTTPCallJsReadme,
      '_http_json_call_js.md', JavaScriptCallReadmeEditor);
    Emit(GenerateHTTPCallJsHtmlCode,
      '_http_json_call_test.html', JavaScriptTestHtmlEditor);

    (* ---- Python service / call ---- *)
    Emit(GenerateHTTPServicePythonCode,
      '_http_json_service.py', PythonServiceCodeEditor);
    Emit(GenerateHTTPServicePythonReadme,
      '_http_json_service_python.md', PythonServiceReadmeEditor);
    Emit(GenerateHTTPCallPythonCode,
      '_http_json_call.py', PythonCallCodeEditor);
    Emit(GenerateHTTPCallPythonReadme,
      '_http_json_call_python.md', PythonCallReadmeEditor);

    (* ---- C++ service (.cpp + .hpp + README) ---- *)
    Emit(GenerateHTTPServiceCppCode,
      '_http_json_service.cpp', CppServiceImplEditor);
    Emit(GenerateHTTPServiceCppHeader,
      '_http_json_service.hpp', CppServiceHeaderEditor);
    Emit(GenerateHTTPServiceCppReadme,
      '_http_json_service_cpp.md', CppServiceReadmeEditor);

    (* ---- C++ call (.cpp + .hpp + README) ---- *)
    Emit(GenerateHTTPCallCppCode,
      '_http_json_call.cpp', CppCallImplEditor);
    Emit(GenerateHTTPCallCppHeader,
      '_http_json_call.hpp', CppCallHeaderEditor);
    Emit(GenerateHTTPCallCppReadme,
      '_http_json_call_cpp.md', CppCallReadmeEditor);

    Emit(GenerateCMakeScript,
      'CMakeLists.txt', CMakeEditor);
    Emit(GenerateTestMainCpp,
      'test_main___.cpp', CMake_TestMain_Editor);

    DoStatus('All artifacts generated for unit "%s".', [unit_name.Text]);
    MainPageControl.ActivePage := FinalSourceTabSheet;
  finally
    func_model.Free;
  end;
end;

(* ============================================================================
 * Open the Pascal / C prototype rule documents
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.OpenCRuleClick(Sender: TObject);
var
  ph, fn: U_String;
begin
  ph := umlGetFilePath(ParamStr(0));
  fn := umlCombineFileName(ph, 'C_code_abi_rule.md');
  if umlFileExists(fn) then
    OpenDocument(fn.Text);
end;

procedure Tcode_decl_to_abi_json_form.OpenPascalRuleClick(Sender: TObject);
var
  ph, fn: U_String;
begin
  ph := umlGetFilePath(ParamStr(0));
  fn := umlCombineFileName(ph, 'pascal_code_abi_rule.md');
  if umlFileExists(fn) then
    OpenDocument(fn.Text);
end;

(* ============================================================================
 * Language selection
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.LanguageSelectorChange(Sender: TObject);
begin
  case LanguageSelectorComboBox.ItemIndex of
    1: (* Pascal *)
    begin
      SourceCodeEditor.Highlighter := PascalSyntaxHighlighter;
      CurrentSourceLanguage := TSourceLanguage.slPascal;
    end;
    2: (* C *)
    begin
      SourceCodeEditor.Highlighter := CppSyntaxHighlighter;
      CurrentSourceLanguage := TSourceLanguage.slC;
    end;
    else
    begin
      SourceCodeEditor.Highlighter := AnySyntaxHighlighter;
      CurrentSourceLanguage := TSourceLanguage.slUnknown;
    end;
  end;
end;

procedure Tcode_decl_to_abi_json_form.LanguageHintClick(Sender: TObject);
begin
  AutoDetectSourceLanguage;
end;

(* ============================================================================
 * Source -> LV0 JSON
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.ParseSourceToJsonClick(Sender: TObject);
begin
  case CurrentSourceLanguage of
    TSourceLanguage.slPascal:
    begin
      with tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceCodeEditor.Text) do
      begin
        SourceJsonEditor.Text := SaveToJson();
        Free;
      end;
    end;
    TSourceLanguage.slC:
    begin
      with tpascal_func_decl_tool.CreateFrom_C_Code(SourceCodeEditor.Text) do
      begin
        SourceJsonEditor.Text := SaveToJson();
        Free;
      end;
    end;
    else
    begin
      DoStatus('Unsupported language.');
      exit;
    end;
  end;

  MainPageControl.ActivePage := SourceJsonTabSheet;
  DoStatus('Parsed source into JSON.');
end;

(* ============================================================================
 * Format source: keep only top-level functions, rebuild minimal declarations
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.FormatSourceClick(Sender: TObject);
var
  Report: TPascalStringList;
begin
  case CurrentSourceLanguage of
    TSourceLanguage.slPascal:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceCodeEditor.Text) do
      begin
        SourceCodeEditor.Text := decl_to_pascal(Report);
        Free;
      end;
    end;
    TSourceLanguage.slC:
    begin
      Report := TPascalStringList.Create;
      with tpascal_func_decl_tool.CreateFrom_C_Code(SourceCodeEditor.Text) do
      begin
        SourceCodeEditor.Text := decl_to_c(Report);
        Free;
      end;
    end;
    else
    begin
      DoStatus('Unsupported language.');
      exit;
    end;
  end;

  DoStatus(Report.AsText);
  DoStatus('All code rebuilt: only top-level functions preserved.');
  DisposeObject(Report);
end;

procedure Tcode_decl_to_abi_json_form.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  Hide;
end;

(* ============================================================================
 * Timer tick: drain the Z.Status log queue and drive the LingoFuse sync queue
 *
 * NOTE: this tool is a pure code generator; it does not register any
 *       LingoFuse service. The LF___.LF_Sync call is retained so that any
 *       other unit which does mount a LingoFuse service keeps its sync
 *       queue drained while this form is running.
 * ============================================================================ *)
procedure Tcode_decl_to_abi_json_form.StatusRefreshTimerTick(Sender: TObject);
begin
  Check_Soft_Thread_Synchronize;
  LF___.LF_Sync;
end;

procedure Tcode_decl_to_abi_json_form.GoToSourceClick(Sender: TObject);
begin
  MainPageControl.ActivePage := SourceCodeTabSheet;
end;

(* ============================================================================
 * Lifecycle
 *
 * This tool is a pure code generator; it does not start any LingoFuse
 * service of its own.
 *   - Create no longer calls TCompute.RunC_NP(Do_Init_Th)
 *   - Destroy no longer calls free_pascal_agent_service()
 *   - No LF_SetOptionEx / LF___.LF_Shutdown from here
 * ============================================================================ *)
constructor Tcode_decl_to_abi_json_form.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  CurrentSourceLanguage := TSourceLanguage.slUnknown;

  LanguageSelectorComboBox.ItemIndex := 2;
  LanguageSelectorChange(LanguageSelectorComboBox);
  InsertEmptyUnitClick(InsertEmptyUnitButton);

  TCompute.RunM_NP(StartMcpService);
end;

destructor Tcode_decl_to_abi_json_form.Destroy;
begin
  LF_Shutdown;
  inherited Destroy;
end;

procedure Tcode_decl_to_abi_json_form.StartMcpService;
begin
  LF_SetOptionEx('WaitConnect', 'True');
  LF_SetOptionEx('Overlap_Connection', 'True');
  code_decl_to_json_abi_mcp_api_tool_provider_unit.Execute_And_Reg_all();
end;

procedure Tcode_decl_to_abi_json_form.AutoDetectSourceLanguage;
begin
  CurrentSourceLanguage := DetectSourceLanguage(SourceCodeEditor.Text);
  case CurrentSourceLanguage of
    slPascal: LanguageSelectorComboBox.ItemIndex := 1;
    slC: LanguageSelectorComboBox.ItemIndex := 2;
    else LanguageSelectorComboBox.ItemIndex := 0;
  end;
  LanguageSelectorChange(LanguageSelectorComboBox);
end;

end.
