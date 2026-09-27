# Pascal Declaration Rules for the code_decl_to_json_abi Toolchain

**Version**: 10.0 (example-first rewrite)
**Applies to**: `Z.Pascal_Func_Tool` → `Z.Pascal_Func_Model` → all generators
**Rule**: If you write it right, it is extracted. If you write it wrong, the declaration is **silently skipped** or its information is **silently lost**. No error, no warning.

---

## 0. The 60-Second Version

Write every declaration like this:

```pascal
unit MyUnit;

interface

(*
  Adds two integers and returns the sum.

  a: first addend
  b: second addend

  Return value: the sum of a and b as an Integer.
*)
function Add(a, b: Integer): Integer;

implementation

function Add(a, b: Integer): Integer;
begin
  Result := a + b;
end;

end.
```

That is the whole spec. The rest of this document explains **why** each line matters, with side-by-side ✅/❌ examples.

---

## 1. Position — Where the Declaration Lives

### 1.1 Only these two positions are extracted

```pascal
unit MyUnit;

interface                     // ✅ extract from here

function TopLevel: Integer;   // ✅ top-level function

procedure Log(const s: string);  // ✅ top-level procedure

implementation                // ❌ never extract from here

function Hidden: Integer;     // ❌ skipped
begin
  Result := 0;
end;

end.
```

### 1.2 Position matrix — one file, all cases

```pascal
unit PositionDemo;

interface

// ✅ EXTRACT — top-level function
function Add(a, b: Integer): Integer;

// ✅ EXTRACT — top-level procedure
procedure Log(const msg: string);

// ❌ SKIP — nested inside another function
procedure Outer;
  procedure Inner;   // nested, not top-level
  begin
  end;
begin
end;

// ❌ SKIP — class method
type
  TMyClass = class
    function Multiply(x, y: Integer): Integer;
  end;

// ❌ SKIP — record method
  TMyRecord = record
    procedure Init;
  end;

// ❌ SKIP — interface method
  IMyInterface = interface
    procedure DoIt;
  end;

implementation

// ❌ SKIP — implementation section
function InternalHelper: Integer;
begin
  Result := 0;
end;

end.
```

### 1.3 The four position rules

| Rule | Consequence if violated |
|------|-------------------------|
| Must be in the `interface` section | Whole declaration skipped |
| Must be top-level (not inside `class` / `record` / `interface` / nested function) | Whole declaration skipped |
| Must be a `function` or `procedure` | Type / var / const declarations are not functions |
| Methods do not count — move them to top level | Whole declaration skipped |

---

## 2. Parameter Modifiers — Which Ones Are Allowed

### 2.1 The modifier matrix

| Modifier | Verdict | Why |
|----------|:-------:|-----|
| *(nothing)* | ✅ | Value passing |
| `const` | ✅ | Read-only value passing |
| `in` | ✅ | Same as `const` |
| `var` | ❌ | Reference passing — not serializable |
| `out` | ❌ | Reference passing — not serializable |

### 2.2 Examples — pass vs skip

```pascal
// ✅ PASS — no modifier
function F1(x: Integer): Integer;

// ✅ PASS — const
function F2(const x: Integer): Integer;

// ✅ PASS — in (equivalent to const)
function F3(in x: Integer): Integer;

// ✅ PASS — mixed, all legal
function F4(const a: Integer; b: Integer; const c: string): string;

// ❌ SKIP — var
procedure F5(var x: Integer);

// ❌ SKIP — out
procedure F6(out x: Integer);

// ❌ SKIP — even one var/out kills the whole declaration
procedure F7(const a: Integer; var b: Integer);
```

### 2.3 How to rewrite `var` / `out`

```pascal
// ❌ before — var
procedure Modify(var x: Integer);

// ✅ after — const + return
function Modify(const x: Integer): Integer;
```

```pascal
// ❌ before — out
procedure GetValue(out x: Integer);

// ✅ after — return value
function GetValue: Integer;
```

```pascal
// ❌ before — multiple out
procedure GetPair(out a, b: Integer);

// ✅ after — JSON string
function GetPair: string;   // returns '{"a":..., "b":...}'
```

### 2.4 Modifier broadcast inside a group

```pascal
// ✅ const applies to all three
function F1(const a, b, c: Integer): Integer;

// ✅ const only to a; b is independent
function F2(const a: Integer; b: Integer): Integer;

// ❌ SKIP — cannot mix modifiers within one group
function F3(const a, var b: Integer): Integer;
```

---

## 3. Types — The Whitelist

### 3.1 Allowed types

```pascal
// ✅ integers — all become int64 in the model
function A1(x: Integer): Integer;
function A2(x: Int64): Int64;
function A3(x: Cardinal): Cardinal;
function A4(x: Longint): Longint;
function A5(x: DWord): DWord;
function A6(x: Word): Word;
function A7(x: SmallInt): SmallInt;
function A8(x: Byte): Byte;
function A9(x: UInt64): UInt64;
function A10(x: LongWord): LongWord;

// ✅ floats — all become double in the model
function B1(x: Double): Double;
function B2(x: Single): Single;
function B3(x: Extended): Extended;
function B4(x: Real): Real;

// ✅ strings — all become string in the model
function C1(x: string): string;
function C2(x: AnsiString): AnsiString;
function C3(x: UnicodeString): UnicodeString;
function C4(x: PChar): PChar;
function C5(x: PAnsiChar): PAnsiChar;
function C6(x: PWideChar): PWideChar;
function C7(x: TP_String): TP_String;
function C8(x: TPascalString): TPascalString;
function C9(x: TUPascalString): TUPascalString;
function C10(x: U_String): U_String;
```

### 3.2 Banned types — every one kills the whole declaration

```pascal
// ❌ Boolean
function D1(x: Integer): Boolean;

// ❌ Variant
function D2(x: Variant): Variant;

// ❌ array
function D3(const arr: array of Integer): Integer;
function D4(const arr: array[0..9] of Integer): Integer;

// ❌ record
function D5(const p: TPoint): Integer;

// ❌ class
function D6(const obj: TObject): Integer;

// ❌ interface
function D7(const itf: IInterface): Integer;

// ❌ enum
function D8(c: TColor): TColor;

// ❌ set
function D9(s: TOptions): TOptions;

// ❌ generic
function D10<T>(const list: TList<T>): Integer;

// ❌ pointer
function D11(const p: Pointer): Integer;
function D12(const p: PInteger): Integer;
function D13(const p: PByte): Integer;

// ❌ TDateTime
function D14(t: TDateTime): TDateTime;

// ❌ anonymous method
function D15(const f: reference to procedure): Integer;
```

### 3.3 Common rewrite patterns

```pascal
// ❌ Boolean → ✅ Integer (0 = false, 1 = true)
function IsEven(x: Integer): Boolean;   // SKIP
function IsEven(x: Integer): Integer;   // PASS — returns 0 or 1
```

```pascal
// ❌ array → ✅ JSON string
function Sum(const arr: array of Integer): Integer;   // SKIP
function Sum(const arr_json: string): Integer;        // PASS — pass '[1,2,3]'
```

```pascal
// ❌ record → ✅ JSON string
function Distance(const p: TPoint): Double;           // SKIP
function Distance(const p_json: string): Double;      // PASS — pass '{"x":1,"y":2}'
```

```pascal
// ❌ pointer → ✅ Int64 address
function GetBuffer(const p: Pointer): Integer;        // SKIP
function GetBuffer(const addr: Int64): Integer;       // PASS
```

```pascal
// ❌ TDateTime → ✅ Double (Unix timestamp) or string (ISO 8601)
function Timestamp: TDateTime;                        // SKIP
function Timestamp: Double;                           // PASS — Unix seconds
function TimestampIso: string;                        // PASS — '2026-09-24T12:00:00Z'
```

---

## 4. Comments — How to Write Them Safely

### 4.1 Recommended styles, in order

| Rank | Style | When to use |
|:----:|-------|-------------|
| **1** | `(* ... *)` | Default. `*)` almost never appears in natural text. |
| **2** | `// ...` | Single-line comments. Cannot be affected by braces. |
| **3** | `{ ... }` | Only when the text **contains no `}`**. |

### 4.2 The `{ }` trap — the biggest silent failure mode

If a `{ ... }` comment contains any `}` character, the entire comment becomes empty:

```pascal
// ❌ Comment LOST — the inner } closes the outer comment
{
  Returns the config JSON.
  Example: {"host":"localhost", "port":8080}.
}
function GetConfig: string;
// Comment = "" — everything gone!
```

**Three ways to fix it:**

```pascal
// ✅ Fix 1 — use (* ... *)
(*
  Returns the config JSON.
  Example: {"host":"localhost", "port":8080}.
*)
function GetConfig: string;
```

```pascal
// ✅ Fix 2 — use //
// Returns the config JSON.
// Example: {"host":"localhost", "port":8080}.
function GetConfig: string;
```

```pascal
// ✅ Fix 3 — replace inner } with full-width ｝
{
  Returns the config JSON.
  Example: ｛"host":"localhost", "port":8080｝.
}
function GetConfig: string;
```

### 4.3 Same trap, different symptom: `*)` inside `(* ... *)`

```pascal
// ❌ Comment cut short at the inner *)
(*
  This function reads a pointer.*)
function F: Integer;

// ✅ Fix — put a space between * and )
(*
  This function reads a pointer. *)
function F: Integer;
```

### 4.4 Where the comment must be

The comment must be **above** the declaration. Trailing comments are ignored.

```pascal
// ✅ Above
(* Adds two integers. *)
function Add(a, b: Integer): Integer;

// ❌ Below — not bound
function Add(a, b: Integer): Integer;
(* This comment is ignored. *)
```

### 4.5 Blank lines and multiple comments

```pascal
// ✅ Comment, then blank line, then declaration
(* Adds two integers. *)

function Add(a, b: Integer): Integer;

// ✅ Two consecutive comments — both are merged
(* Adds two integers. *)
(* Second line. *)
function Add(a, b: Integer): Integer;
// Comment = "Adds two integers.\nSecond line."
```

```pascal
// ⚠️ Blank line separates them — only the nearest is bound
(* First comment. *)

(* Second comment. *)

function Add(a, b: Integer): Integer;
// Comment = "Second comment." — the first is ignored
```

### 4.6 Diagnostic rule

- **Comment is empty** → look for `}` or `*)` inside the comment body.
- **Comment is garbage** → check the source file's encoding.

---

## 5. Parameter Descriptions — The Layout Rules

### 5.1 The one-sentence rule

**A parameter description must start with the parameter name at the start of a line.**

### 5.2 Accepted layouts

```pascal
// ✅ Colon
(*
  source: first addend
  lang:   second addend
*)
```

```pascal
// ✅ Equals
(*
  source = first addend
  lang   = second addend
*)
```

```pascal
// ✅ Doxygen
(*
  @param source first addend
  @param lang   second addend
*)
```

```pascal
// ✅ Space only
(*
  source  first addend
  lang    second addend
*)
```

```pascal
// ✅ Full-width colon (Chinese IME)
(*
  source：first addend
  lang：second addend
*)
```

### 5.3 What the description is captured from

Given a declaration `function Add(source, lang: Integer): Integer;`:

```pascal
(*
  Computes the sum of two integers.

  source: first addend
  lang:   second addend

  Return value: the sum of source and lang.
*)
```

Result:

| Parameter | Description |
|-----------|-------------|
| `source` | `first addend` |
| `lang` | `second addend` |

The `Return value:` line is **not** extracted as a parameter description.

### 5.4 Multi-line descriptions

Indented continuation lines become part of the same description.

```pascal
(*
  target: target language, pick one:
            pascal_service   generate Pascal service
            pascal_call      generate Pascal call
            python_service   generate Python service
          <unit> is the normalized UnitName.
*)
function Generate(target: string): string;
```

Result: `target`'s description = `"target language, pick one:\n            pascal_service   generate Pascal service\n            pascal_call      generate Pascal call\n            python_service   generate Python service\n          <unit> is the normalized UnitName."`

### 5.5 Case-insensitive matching

```pascal
(*
  SOURCE: source text
  LANG:   language name
*)
function F(Source: string; Lang: string): string;
// Source = "source text", Lang = "language name"
```

### 5.6 The "parameter name at line start" rule, in practice

**Safe — parameter name appears mid-sentence:**

```pascal
(*
  host: host name

  This config controls the host and port used by the service.
*)
function Connect(host: string; port: Integer): string;
```

Result: `host = "host name"`. The `host` and `port` inside the sentence are **not** mis-detected.

**Unsafe — sentence starts with a parameter name:**

```pascal
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string): string;
```

Result: `host = "host name host can also be an IP address."` — **polluted**.

**Four ways to fix it:**

```pascal
// Fix 1 — merge into the description line
(*
  host: host name (can also be an IP address)
*)
```

```pascal
// Fix 2 — wrap the leading name in backticks
(*
  host: host name

  `host` can also be an IP address.
*)
```

```pascal
// Fix 3 — use non-ASCII prose
(*
  host: host name

  主机名也可以是 IP 地址。
*)
```

```pascal
// Fix 4 — indent so it continues the previous block
(*
  host: host name
        can also be an IP address.
*)
```

### 5.7 Parameter descriptions may be scattered

This is legal, though keeping them together is cleaner:

```pascal
(*
  Function purpose.

  source: source text.

  Some unrelated note.

  lang: language name.
*)
function F(source, lang: string): string;
```

Both descriptions are extracted correctly.

---

## 6. Return Values — The Rules

### 6.1 The golden rule

**The return type must be declared in the signature.** The comment is only a supplement.

```pascal
// ✅ Return type is in the signature — ReturnType = "int64" in the model
(*
  Return value: the sum.
*)
function Add(a, b: Integer): Integer;
```

```pascal
// ❌ Return type is only in the comment — the declaration is a syntax error
(*
  @return the sum
*)
function Add(a, b: Integer);   // missing ": Integer"
```

### 6.2 What goes into the JSON

| Model field | Source | Extracted? |
|-------------|--------|:----------:|
| `Name` | declaration name | ✅ |
| `IsFunction` | `function` vs `procedure` | ✅ |
| `Params[i].Name` | parameter list | ✅ |
| `Params[i].Typ` | parameter type (raw) | ✅ |
| `Params[i].PascalType` | parameter type (normalized) | ✅ |
| `Params[i].Description` | `<name>: ...` in comment | ✅ |
| **`ReturnType`** | **`: T` in signature** | **✅** |
| `Comment` | whole comment as plain text | ✅ |

**There is no structured field for a return-value *description*.** The description lives only inside `Comment` as plain text.

### 6.3 Return-type normalization

| Signature type | Model value (typical mode) |
|----------------|:--------------------------:|
| `Integer`, `Int64`, `Cardinal`, ... | `int64` |
| `Double`, `Single`, `Extended`, ... | `double` |
| `string`, `AnsiString`, `PChar`, ... | `string` |

### 6.4 Correct return-value comment style

```pascal
(*
  Adds two integers.

  a: first addend
  b: second addend

  Return value: the sum as an Integer.
*)
function Add(a, b: Integer): Integer;
```

- `: Integer` — the only piece that goes into the model.
- `Return value: ...` — supplementary text that lives in `Comment`.

### 6.5 Do not use `@return` as a substitute for the signature

```pascal
// ❌ This will not work — @return does not feed ReturnType
(*
  @return the sum
*)
function Add(a, b: Integer): Integer;   // ReturnType is "int64" — fine here

// ❌ This is a syntax error
(*
  @return the sum
*)
function Add(a, b: Integer);            // no signature return type — SKIPPED
```

### 6.6 Procedures

Procedures have no `ReturnType`. Do not write `@return` in their comments.

```pascal
// ✅ Correct
(*
  Logs a message.

  msg: the message to log
*)
procedure Log(const msg: string);
```

```pascal
// ❌ Misleading, ignored anyway
(*
  @return nothing
*)
procedure Log(const msg: string);
```

---

## 7. Full Worked Examples

### 7.1 A fully compliant unit

```pascal
unit Calculator;

interface

(*
  Adds two integers and returns the sum.

  a: first addend
  b: second addend

  Return value: the sum as an Integer.
*)
function Add(a, b: Integer): Integer;

(*
  Multiplies two integers.

  @param a first multiplicand
  @param b second multiplicand

  Return value: the product as an Integer.
*)
function Mul(a, b: Integer): Integer;

(*
  Echoes a string.

  s: the input string

  Return value: the same string, unmodified.
*)
function Echo(const s: string): string;

(*
  Logs a message.

  msg: message text
*)
procedure Log(const msg: string);

implementation

function Add(a, b: Integer): Integer;
begin Result := a + b; end;

function Mul(a, b: Integer): Integer;
begin Result := a * b; end;

function Echo(const s: string): string;
begin Result := s; end;

procedure Log(const msg: string);
begin
  // implementation
end;

end.
```

### 7.2 Multi-line parameter description

```pascal
unit Codegen;

interface

(*
  Generates code for the given target.

  model_json: the model JSON produced by a previous step.

  target: the target language, pick one of:
            pascal_service     generate a Pascal service unit
            pascal_call        generate a Pascal call unit
            python_service     generate a Python service module
            python_call        generate a Python call module
          <unit> in the examples below is the normalized unit name.

  Return value: the generated source code as a string.
*)
function Generate(model_json: string; target: string): string;

implementation

end.
```

Extracted:

| Parameter | Description |
|-----------|-------------|
| `model_json` | `the model JSON produced by a previous step.` |
| `target` | `the target language, pick one of:\n            pascal_service     generate a Pascal service unit\n            pascal_call        generate a Pascal call unit\n            python_service     generate a Python service module\n            python_call        generate a Python call module\n          <unit> in the examples below is the normalized unit name.` |

### 7.3 A unit with everything wrong

```pascal
unit BadUnit;

interface

// ❌ SKIP — var parameter
procedure Modify(var x: Integer);

// ❌ SKIP — out parameter
procedure GetValue(out x: Integer);

// ❌ SKIP — Boolean return
function IsEven(x: Integer): Boolean;

// ❌ SKIP — array parameter
function Sum(const arr: array of Integer): Integer;

// ❌ SKIP — pointer parameter
function GetBuffer(const p: Pointer): Integer;

// ❌ COMMENT LOST — contains } inside { }
{
  Returns config JSON.
  Example: {"host":"localhost"}.
}
function GetConfig: string;

// ❌ DESCRIPTION POLLUTED — second sentence starts with "host"
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string): string;

implementation

end.
```

Each of these has a fix in the earlier sections.

---

## 8. Rewrite Cheat Sheet

| Wrong | Right |
|-------|-------|
| `procedure P(var x: Integer)` | `function P(const x: Integer): Integer` |
| `procedure P(out x: Integer)` | `function P: Integer` |
| `function F: Boolean` | `function F: Integer` (0/1) |
| `function F(a: TPoint)` | `function F(const a_json: string)` |
| `function F(a: array of Integer)` | `function F(const a_json: string)` |
| `function F(a: Pointer)` | `function F(const addr: Int64)` |
| `function F(a: TDateTime)` | `function F: Double` or `function F: string` |
| Class method `TClass.F` | Move to top level |
| Function in `implementation` | Move to `interface` |
| Trailing comment | Move comment above the declaration |
| `{ ... }` with `}` inside | Use `(* ... *)` or `//` |
| `(* ... *)` with `*)` inside | Put a space: `* )` |
| Return type only in comment | Declare `: T` in the signature |
| Parameter name mid-sentence | Name must be at line start for it to count |
| Sentence starting with a parameter name | Reformat (see §5.6) |

---

## 9. Self-Check Before You Commit

Run through these eight checks in order.

```pascal
// 1. Is the declaration inside `interface`?
// 2. Is it at the top level (not inside class / record / nested function)?
// 3. Are all parameters free of `var` and `out`?
// 4. Are all types in the whitelist (int / float / string only)?
// 5. Is the comment directly above the declaration?
// 6. Does the comment body contain any `}` (or `*)` inside `(* *)`)?
// 7. Is the return type declared in the signature (`: T`)?
// 8. Does every parameter description start at the beginning of a line?
```

If any answer is "no", fix it before generating.

---

## 10. Minimum Template

```pascal
unit <UnitName>;

interface

(*
  <one-line summary of what the function does>.

  <param1>: <description>
  <param2>: <description>

  Return value: <what the function returns>.
*)
function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;

implementation

function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;
begin
  // implementation
end;

end.
```

Fill in:

- `<UnitName>` — a valid Pascal identifier.
- `<name>` — a valid Pascal identifier.
- `<paramN>` — a valid Pascal identifier.
- `<typeN>` — an integer, float, or string type from §3.1.
- `<return type>` — the same.

---

## 11. Comments in the Unit Header vs. the Tool Description

The unit header (the big `(* ... *)` block at the top of the file) is **not** attached to any single function. It is not used for tool descriptions. Only the comment directly above each declaration matters.

```pascal
unit MyUnit;

(*
  This block is the unit header. It is NOT used as a tool description.
  It is only for humans reading the file.
*)

interface

(*
  This block is directly above Add, so it becomes Add's tool description.
*)
function Add(a, b: Integer): Integer;

implementation

end.
```

---

## 12. What "Silent Skip" Means in Practice

When a declaration is skipped, the toolchain continues without complaint. The only signal is a line in the report log (visible when `GenerateCode_LogEnabled = True` in the generator, or in the GUI's log panel).

If you generate five declarations and only four appear in the output, the fifth was skipped. Run through §8 to find the reason.

---

## 13. Version Notes

- **v10.0** — example-first rewrite. Every rule has a ✅/❌ code sample. Removed most diagrams and long prose. §8 is a single-page rewrite table.
- **v9.0** — first example-heavy edition. Added the "silent failure" mode explanations.
- **v8.0** — original. Aligned with `Fill_Pascal.inc` and `Translate_C_Typ_To_Pascal.inc`.
