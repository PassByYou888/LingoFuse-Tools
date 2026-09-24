(*
 *******************************************************************************
 * code_decl_to_mcp_samples.inc
 *
 * Test samples used by the "Test Sample" button of the main form.
 *
 * This file is included from code_decl_to_mcp_frm.pas via {$I}. It provides
 * two builder functions:
 *
 *   BuildPascalTestSample : returns a rich Pascal unit that exercises the
 *                           parser with a wide variety of syntax forms.
 *
 *   BuildCTestSample      : returns a rich C header that exercises the C
 *                           parser with a wide variety of prototype forms.
 *
 * Both samples are meant to be pasted into the Source editor. They are
 * purely declarative; they contain no implementation bodies.
 *
 * All content is English. The samples are structured as a series of
 * TPascalStringList blocks so the intent of each section is obvious and
 * future edits stay local.
 * ****************************************************************************
*)

  { --------------------------------------------------------------------------- }
  { Pascal test sample                                                          }
  { --------------------------------------------------------------------------- }

function BuildPascalTestSample: TP_String;
var
  L: TPascalStringList;

  procedure Add(const S: string);
  begin
    L.Add(S);
  end;

begin
  L := TPascalStringList.Create;
  try
    { -- Unit header --------------------------------------------------- }
    Add('unit ComplexTestUnit;');
    Add('');
    Add('{');
    Add('  A complex unit used to test the parser (Z.Pascal_Func_Tool).');
    Add('  It covers many advanced and edge-case syntax forms to exercise');
    Add('  the robustness of the parser. All declarations are syntactically');
    Add('  valid; implementation bodies are omitted.');
    Add('}');
    Add('');
    Add('{$mode objfpc}{$H+}');
    Add('{$modeswitch advancedrecords}');
    Add('{$modeswitch typehelpers}');
    Add('');
    Add('interface');
    Add('');
    Add('uses');
    Add('  SysUtils, Classes, Generics.Collections, TypInfo,');
    Add('  Z.Core, Z.PascalStrings, Math;');
    Add('');

    { -- Comment style tests ------------------------------------------- }
    Add('{ =================================================================');
    Add('  Comment style tests (multiple formats)');
    Add('  ================================================================= }');
    Add('');
    Add('(* A top-level function with no parameter, returning an integer. *)');
    Add('function NoParamFunc: Integer;');
    Add('');
    Add('// Single-line comment, no parameter.');
    Add('procedure NoParamProc;');
    Add('');
    Add('{');
    Add('  Multi-line comment block, tests comment extraction.');
    Add('}');
    Add('function MultiLineComment(a: Integer): Integer;');
    Add('');
    Add('(**');
    Add(' * Doxygen-style comment.');
    Add(' * @param a First parameter.');
    Add(' * @param b Second parameter.');
    Add(' * @return Sum of the two parameters.');
    Add(' *)');
    Add('function Add(a, b: Integer): Integer;');
    Add('');
    Add('{ Comment immediately before the function. }');
    Add('function Sub(a, b: Integer): Integer; // trailing comment must not bind');
    Add('');
    Add('(* Comment with an asterisk prefix *)');
    Add('// Another comment; consecutive comments should merge.');
    Add('function Mul(a, b: Double): Double;');
    Add('');

    { -- Basic parameter declarations ---------------------------------- }
    Add('{ =================================================================');
    Add('  Basic parameter declarations');
    Add('  ================================================================= }');
    Add('');
    Add('// Single parameter.');
    Add('function SingleParam(x: Integer): Boolean;');
    Add('');
    Add('// Multiple parameters of different types.');
    Add('function MultipleParams(a: Integer; b: string; c: Double): string;');
    Add('');
    Add('// var parameter.');
    Add('procedure ModifyVar(var Value: Integer);');
    Add('');
    Add('// const parameter.');
    Add('procedure ReadOnlyConst(const Value: string);');
    Add('');
    Add('// out parameter.');
    Add('procedure GetValue(out Result: Integer);');
    Add('');
    Add('// Mixed modifiers.');
    Add('procedure MixedMods(const Input: string; var Output: Integer; out ErrorCode: Integer);');
    Add('');

    { -- Default values ------------------------------------------------ }
    Add('{ =================================================================');
    Add('  Default values');
    Add('  ================================================================= }');
    Add('');
    Add('// Integer default value.');
    Add('function WithDefaultInt(a: Integer = 42): Integer;');
    Add('');
    Add('// String default value (quoted).');
    Add('function WithDefaultString(s: string = ''default''): string;');
    Add('');
    Add('// Boolean default value.');
    Add('function WithDefaultBool(flag: Boolean = True): Boolean;');
    Add('');
    Add('// Floating-point default value.');
    Add('function WithDefaultFloat(pi: Double = 3.14159): Double;');
    Add('');
    Add('// Constant expression default value.');
    Add('function WithDefaultConst(x: Integer = MaxBufferSize + 10): Integer;');
    Add('');
    Add('// Enumeration default value.');
    Add('function WithDefaultEnum(c: TColor = clRed): TColor;');
    Add('');

    { -- Parameter groups sharing modifier and type -------------------- }
    Add('{ =================================================================');
    Add('  Parameter groups sharing modifier and type');
    Add('  ================================================================= }');
    Add('');
    Add('// const modifier, several parameters of the same type.');
    Add('function GroupConst(const a, b, c: Integer): Integer;');
    Add('');
    Add('// var modifier, several parameters of the same type.');
    Add('procedure GroupVar(var x, y, z: Double);');
    Add('');
    Add('// Group with a default value on the last parameter.');
    Add('function GroupDefault(const a, b: Integer = 0; const s: string = ''''): Boolean;');
    Add('');
    Add('// Several groups together.');
    Add('function ComplexGroups(var a, b: Integer; const c: string; out d: Double): Integer;');
    Add('');

    { -- Complex parameter types --------------------------------------- }
    Add('{ =================================================================');
    Add('  Complex parameter types');
    Add('  ================================================================= }');
    Add('');
    Add('// Dynamic array.');
    Add('procedure ProcessArray(const Arr: array of Integer);');
    Add('');
    Add('// Static array.');
    Add('procedure ProcessStaticArray(const Arr: array[0..9] of Integer);');
    Add('');
    Add('// Record type.');
    Add('procedure ProcessRecord(const P: TPoint);');
    Add('');
    Add('// Class type.');
    Add('procedure ProcessClass(const Obj: TObject);');
    Add('');
    Add('// Generic type.');
    Add('procedure ProcessGenericList(const List: TGenericList<string>);');
    Add('');
    Add('// Procedural type (function pointer).');
    Add('type');
    Add('  TIntFunc = function(x: Integer): Integer;');
    Add('');
    Add('// Accepts a procedural type.');
    Add('procedure UseFuncPtr(F: TIntFunc);');
    Add('');
    Add('// Anonymous procedural type as parameter.');
    Add('procedure UseAnonymous(const F: reference to procedure);');
    Add('');
    Add('// Complex function type with parameter and return value.');
    Add('type');
    Add('  TBinaryOp = function(a, b: Double): Double;');
    Add('');
    Add('procedure UseBinaryOp(Op: TBinaryOp);');
    Add('');
    Add('// Nested function type as parameter.');
    Add('procedure UseNestedFunc(F: function(x: Integer): function(y: Integer): Integer);');
    Add('');

    { -- Calling conventions and external declarations ----------------- }
    Add('{ =================================================================');
    Add('  Calling conventions and external declarations');
    Add('  ================================================================= }');
    Add('');
    Add('// cdecl calling convention.');
    Add('function CdeclFunc(a: Integer): Integer; cdecl;');
    Add('');
    Add('// stdcall.');
    Add('procedure StdcallProc(a: Integer; var b: Double); stdcall;');
    Add('');
    Add('// register.');
    Add('function RegisterFunc(a, b: Integer): Integer; register;');
    Add('');
    Add('// external with library name.');
    Add('function ExternalLib(const Name: PChar): Boolean; cdecl; external ''my.dll'';');
    Add('');
    Add('// external with name alias.');
    Add('procedure ExternalAlias; stdcall; external ''kernel32'' name ''GetCurrentProcess'';');
    Add('');
    Add('// external with index.');
    Add('procedure ExternalIndex; stdcall; external ''user32'' index 10;');
    Add('');

    { -- Overload and inheritance modifiers ---------------------------- }
    Add('{ =================================================================');
    Add('  Overload and inheritance modifiers');
    Add('  ================================================================= }');
    Add('');
    Add('// overload.');
    Add('function OverloadTest(a: Integer): Integer; overload;');
    Add('function OverloadTest(a, b: Integer): Integer; overload;');
    Add('function OverloadTest(a: Double): Double; overload;');
    Add('');
    Add('// virtual / override / abstract.');
    Add('type');
    Add('  TBase = class');
    Add('    procedure VirtualProc; virtual;');
    Add('    function AbstractFunc: Integer; virtual; abstract;');
    Add('  end;');
    Add('');
    Add('  TDerived = class(TBase)');
    Add('    procedure VirtualProc; override;');
    Add('    function AbstractFunc: Integer; override;');
    Add('  end;');
    Add('');

    { -- Class methods, static methods, constructors ------------------- }
    Add('{ =================================================================');
    Add('  Class methods, static methods, constructors');
    Add('  ================================================================= }');
    Add('');
    Add('type');
    Add('  TMath = class');
    Add('  public');
    Add('    class function StaticAdd(a, b: Integer): Integer; static;');
    Add('    class procedure StaticProc; static;');
    Add('    constructor Create(a: Integer);');
    Add('    destructor Destroy; override;');
    Add('  end;');
    Add('');

    { -- Generic methods inside a generic class ------------------------ }
    Add('{ =================================================================');
    Add('  Generic methods inside a generic class');
    Add('  ================================================================= }');
    Add('');
    Add('type');
    Add('  TGenericClass<T> = class');
    Add('    function GenericMethod<U>(a: T; b: U): T;');
    Add('    procedure ProcWithGenericParam(const List: TList<T>);');
    Add('  end;');
    Add('');

    { -- Operator overloads -------------------------------------------- }
    Add('{ =================================================================');
    Add('  Operator overloads (implicit, explicit)');
    Add('  ================================================================= }');
    Add('');
    Add('type');
    Add('  TMyRecord = record');
    Add('    Value: Integer;');
    Add('    class operator Implicit(a: Integer): TMyRecord;');
    Add('    class operator Explicit(a: Integer): TMyRecord;');
    Add('    class operator Add(a, b: TMyRecord): TMyRecord;');
    Add('  end;');
    Add('');

    { -- Nested type as parameter -------------------------------------- }
    Add('{ =================================================================');
    Add('  Nested type as parameter');
    Add('  ================================================================= }');
    Add('');
    Add('type');
    Add('  TOuter = class');
    Add('  public type');
    Add('    TInner = record');
    Add('      X: Integer;');
    Add('    end;');
    Add('  end;');
    Add('');
    Add('procedure UseNestedType(const P: TOuter.TInner);');
    Add('');

    { -- Complex default values ---------------------------------------- }
    Add('{ =================================================================');
    Add('  Complex default values');
    Add('  ================================================================= }');
    Add('');
    Add('// String default value containing a quote.');
    Add('function StringWithQuotes(s: string = ''He said: "Hello"''): string;');
    Add('');
    Add('// Enumeration constant as default value.');
    Add('function EnumDefault(c: TColor = clBlue): TColor;');
    Add('');
    Add('// Set constant as default value.');
    Add('function SetDefault(s: TOptions = [optRead, optWrite]): TOptions;');
    Add('');

    { -- Complex return types ------------------------------------------ }
    Add('{ =================================================================');
    Add('  Complex return types');
    Add('  ================================================================= }');
    Add('');
    Add('// Returns an array.');
    Add('function ReturnArray: TIntArray;');
    Add('');
    Add('// Returns a record.');
    Add('function ReturnRecord: TPoint;');
    Add('');
    Add('// Returns a generic list.');
    Add('function ReturnGenericList: TGenericList<string>;');
    Add('');
    Add('// Returns a function pointer.');
    Add('function ReturnFuncPtr: TIntFunc;');
    Add('');

    { -- Complex declarations with comments ---------------------------- }
    Add('{ =================================================================');
    Add('  Complex declarations with comments');
    Add('  ================================================================= }');
    Add('');
    Add('(*');
    Add('  A very complex declaration with several parameter groups,');
    Add('  default values, var/const/out modifiers, and external linkage.');
    Add('  The comment must be extracted correctly.');
    Add('*)');
    Add('function SuperComplex(');
    Add('  const Name: string = ''default'';    // first group, const');
    Add('  var Value: Integer = 42;            // second group, var with default');
    Add('  out Flag: Boolean;                  // third group, out');
    Add('  const Data: array of Byte           // fourth group, array');
    Add('): Integer; cdecl; external ''lib'' name ''SuperComplex'';');
    Add('');
    Add('{ Another declaration that uses a procedural type as parameter }');
    Add('{');
    Add('  Accepts a binary operation and returns the applied result.');
    Add('}');
    Add('function ApplyBinaryOp(');
    Add('  const Op: TBinaryOp;        // procedural type parameter');
    Add('  const a, b: Double = 0.0    // default value group');
    Add('): Double; overload;');
    Add('');
    Add('// Another overload that accepts an integer operation.');
    Add('function ApplyBinaryOp(');
    Add('  const Op: function(a, b: Integer): Integer;');
    Add('  const a, b: Integer = 0');
    Add('): Integer; overload;');
    Add('');

    { -- Additional complex structures --------------------------------- }
    Add('{ =================================================================');
    Add('  Additional complex structures (class, interface)');
    Add('  ================================================================= }');
    Add('');
    Add('type');
    Add('  IMyInterface = interface');
    Add('    procedure DoIt;');
    Add('  end;');
    Add('');
    Add('  TMyClass = class(TInterfacedObject, IMyInterface)');
    Add('  private');
    Add('    FData: TGenericList<TPoint>;');
    Add('  public');
    Add('    constructor Create;');
    Add('    procedure DoIt;');
    Add('    function GetItem(Index: Integer): TPoint;');
    Add('    property Items[Index: Integer]: TPoint read GetItem; default;');
    Add('  end;');
    Add('');
    Add('implementation');
    Add('');
    Add('end.');

    Result := L.AsText;
  finally
    DisposeObject(L);
  end;
end;

{ --------------------------------------------------------------------------- }
{ C test sample                                                               }
{ --------------------------------------------------------------------------- }

function BuildCTestSample: TP_String;
var
  L: TPascalStringList;

  procedure Add(const S: string);
  begin
    L.Add(S);
  end;

begin
  L := TPascalStringList.Create;
  try
    { -- Header guard -------------------------------------------------- }
    Add('/* ComplexTestUnit.h */');
    Add('');
    Add('#ifndef ComplexTestUnit_H');
    Add('#define ComplexTestUnit_H');
    Add('/* Generated from unit ComplexTestUnit.h */');
    Add('');

    { -- Comment style tests ------------------------------------------- }
    Add('/* A top-level function with no parameter, returning an integer. */');
    Add('int NoParamFunc(void);');
    Add('');
    Add('/* Single-line comment, no parameter. */');
    Add('void NoParamProc(void);');
    Add('');
    Add('/* Multi-line comment block.');
    Add('   Tests comment extraction. */');
    Add('int MultiLineComment(int a);');
    Add('');
    Add('/*');
    Add(' * Doxygen-style comment.');
    Add(' * @param a First parameter.');
    Add(' * @param b Second parameter.');
    Add(' * @return Sum of the two parameters.');
    Add(' */');
    Add('int Add(int a, int b);');
    Add('');
    Add('/* Comment immediately before the function. */');
    Add('int Sub(int a, int b);');
    Add('');
    Add('/* Another comment; consecutive comments should merge. */');
    Add('double Mul(double a, double b);');
    Add('');

    { -- Basic declarations -------------------------------------------- }
    Add('/* Multiple parameters of different types. */');
    Add('char * MultipleParams(int a, char * b, double c);');
    Add('');
    Add('/* const parameter. */');
    Add('void ReadOnlyConst(const char * Value);');
    Add('');
    Add('/* Integer default value (already bound by the caller). */');
    Add('int WithDefaultInt(int a);');
    Add('');
    Add('/* String default value (quoted by the caller). */');
    Add('char * WithDefaultString(char * s);');
    Add('');
    Add('/* Floating-point default value. */');
    Add('double WithDefaultFloat(double pi);');
    Add('');
    Add('/* Constant expression default value. */');
    Add('int WithDefaultConst(int x);');
    Add('');
    Add('/* const modifier, several parameters of the same type. */');
    Add('int GroupConst(const int a, const int b, const int c);');
    Add('');

    { -- Calling conventions ------------------------------------------- }
    Add('/* cdecl calling convention. */');
    Add('int CdeclFunc(int a);');
    Add('');
    Add('/* register. */');
    Add('int RegisterFunc(int a, int b);');
    Add('');
    Add('/* external with name alias. */');
    Add('void ExternalAlias(void);');
    Add('');
    Add('/* external with index. */');
    Add('void ExternalIndex(void);');
    Add('');

    { -- Overloads ----------------------------------------------------- }
    Add('/* overload. */');
    Add('int OverloadTest(int a);');
    Add('int OverloadTest(int a, int b);');
    Add('double OverloadTest(double a);');
    Add('');

    { -- Quoted default value ------------------------------------------ }
    Add('/* String default value containing quotes. */');
    Add('char * StringWithQuotes(char * s);');
    Add('');

    { -- Header guard end ---------------------------------------------- }
    Add('#endif /* ComplexTestUnit_H */');

    Result := L.AsText;
  finally
    DisposeObject(L);
  end;
end;
