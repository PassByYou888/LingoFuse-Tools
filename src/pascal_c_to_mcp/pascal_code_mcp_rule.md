# Pascal Declaration Rules (for the Z.Pascal_Func_Tool Toolchain)

**Version**: 8.0
**Last updated**: 2026-09-20
**Applies to**: `Z.Pascal_Func_Tool` → `Z.Pascal_Func_Model` → `pas_mcp_generator_tool` full pipeline
**Status**: This document IS the parsing contract. Any deviation causes declarations to be **silently skipped** or information to be **silently lost**.

---

> ## **Why you must write detailed comments**
>
> **The more thoroughly you describe a function — its purpose, every parameter, and its return value — the more accurately an AI agent will call it.**
>
> The agent never reads your Pascal source. It reads only the `description` string in the tool's JSON schema, which is assembled from your adjacent comment. Short or vague comments produce vague descriptions, and a vague description means the agent will stall, call the wrong tool, or pass wrong arguments.
>
> **One unambiguous sentence per parameter is worth ten lines of source code you never write.**
>
> See §4.6 for exactly how your comment is assembled into the tool description, and §5 for how the parameter descriptions are extracted.

---

## Revision summary

| ID | Change | Section |
|:--:|--------|---------|
| V8-1 | **Major**: `ExtractParamDescriptions` is now an indentation-aware state machine (v3.0 behaviour) | §5.2 |
| V8-2 | **Major**: Parameter descriptions no longer need to be stacked together — multi-line indentation continuation is supported | §5.4 |
| V8-3 | **Major**: The "same-name pollution" issue in v7.0 §5.6.8 is solved by the *line-start anchor* rule | §5.6.8 |
| V8-4 | **Major**: Iron rule #8 rewritten as "parameter block structure" | §0 |
| V8-5 | **New**: block-comment `*` prefix handling (C→Pascal path) | §4.7 |
| V8-6 | **New**: human-misreading scenarios | §11 |
| V8-7 | **Fix**: recommended comment styles, updated for C→Pascal conversion products | §4.3 |
| V8-8 | **Fix**: trigger table adds `{ * }` prefix case | §4.5.3 |
| V8-9 | **Fix**: return-value comment section | §5.6 |
| V8-10 | **Fix**: Mermaid diagram rendering (English subgraph IDs) | global |
| V8-11 | **Fix**: forbidden-type list adds `Pointer` and empty-parameter notes | §3.3 |
| V8-12 | **Fix**: position examples add nested-function case | §1.3 |

---

## 0. Thirty-second overview

**Eight iron rules**:

1. **Location**: `interface` section, top level.
2. **Keyword**: `function` or `procedure`.
3. **Modifier**: only `const`, `in`, or blank. `var` / `out` forbidden.
4. **Type**: parameter and return types must be in the whitelist.
5. **Comment**: immediately above the declaration (blank lines allowed).
6. **Comment body**: if using `{ }` style, must not contain `}`. Prefer `(* ... *)`.
7. **Return value**: must be declared in the signature as `: T`. `@return` in comments does not go to JSON.
8. **Parameter block**: parameter name must be at *line start* (or immediately after a Doxygen marker); indented continuation lines become that parameter's description.

**Violations 1–4 = declaration skipped entirely. Violations 5–6 = comment lost. Violation 7 = return type missing, declaration skipped. Violation 8 = that parameter's description lost.**

**And always remember**: the agent only sees your comment (via the generated `description`). **Write it as if the reader has never seen your code, because that reader is an AI.**

---

## 1. Where declarations must live

### 1.1 Extracted vs skipped

| Location | Result |
|----------|--------|
| `interface` section, top level | **Extracted** |
| Inside `class` / `record` / `interface` types in `interface` | Skipped |
| Anywhere in `implementation` | Skipped |
| Nested inside another routine | Skipped |
| Inside a `type` block | Skipped |

### 1.2 Examples

```pascal
unit MyUnit;

interface

// OK: top-level function
function Add(a, b: Integer): Integer;

// OK: top-level procedure
procedure Log(const msg: string);

// SKIP: nested inside another routine
procedure Outer;
  procedure Inner;   // nested, skipped
  begin
  end;
begin
end;

type
  TMyClass = class
    // SKIP: class method
    function Multiply(x, y: Integer): Integer;
  end;

  TMyRecord = record
    // SKIP: record method
    procedure DoSomething;
  end;

  IMyInterface = interface
    // SKIP: interface method
    procedure DoIt;
  end;

implementation

// SKIP: not in interface section
function InternalHelper: Boolean;
begin
  Result := True;
end;

end.
```

---

## 2. Parameter modifiers

### 2.1 Whitelist

| Modifier | Allowed | Notes |
|----------|:-------:|-------|
| (none) | Yes | Default value passing |
| `const` | Yes | Read-only value passing |
| `in` | Yes | Read-only value passing (Delphi 2009+, FPC) |
| `var` | **No** | **Whole declaration skipped** |
| `out` | **No** | **Whole declaration skipped** |

### 2.2 Why `var` / `out` are forbidden

`var` / `out` are reference passing and cannot be mapped to JSON Schema value types. The toolchain assumes every parameter is serializable.

**Fix**: use `const` + a return value.

```pascal
// WRONG — reference passing, whole declaration skipped
procedure Modify(var x: Integer);

// RIGHT — value passing + return value
function Modify(const x: Integer): Integer;
```

### 2.3 Group broadcast

```pascal
// const applies to all three: a, b, c
const a, b, c: Integer;

// const applies only to a
const a: Integer; b: Integer;
```

---

## 3. Type whitelist

### 3.1 Allowed types

| Family | Types |
|--------|-------|
| Integer | `Integer`, `Int64`, `Cardinal`, `LongInt`, `DWord`, `Word`, `SmallInt`, `Byte`, `UInt64`, `LongWord` |
| Float | `Double`, `Single`, `Extended`, `Real` |
| String | `string`, `AnsiString`, `UnicodeString`, `PChar`, `PAnsiChar`, `PWideChar`, `TP_String`, `TPascalString`, `TUPascalString`, `U_String` |

### 3.2 Normalization table

| Raw type | `tnf_Json` mode | `tnf_ABI` mode | JSON Schema type |
|----------|:---------------:|:--------------:|:----------------:|
| Any integer | `int64` | lowercase original (e.g. `integer`) | `integer` |
| Any float | `double` | lowercase original (e.g. `double`) | `number` |
| Any string | `string` | lowercase original (e.g. `string`) | `string` |

### 3.3 Forbidden types (whole declaration skipped)

| Category | Examples |
|----------|----------|
| Boolean | `Boolean` |
| Variant | `Variant` |
| Array | `array of X`, `array[0..N] of X` |
| Record / struct | `TPoint`, `TRect`, custom record |
| Date / time | `TDateTime` |
| Class | `TObject`, `TStringList`, custom class |
| Interface | `IInterface`, custom interface |
| Enum | `TColor`, custom enum |
| Set | `set of X` |
| Generic | `TList<X>`, `TGenericList<X>` |
| Event | `TNotifyEvent` |
| **Untyped pointer** | **`Pointer`, `PInteger`, `PByte`** |
| Anonymous method | `reference to procedure` |
| **Untyped parameter** | Anonymous parameters with no type |

> **Note on `Pointer`**: even though it has a C-side mapping (`void *`), it is **rejected on the Pascal side**. `Pointer` carries no size or semantics and cannot be safely serialized. If you must pass an address, use `Int64`.

### 3.4 Examples

```pascal
// PASS
function Add(a, b: Integer): Integer;
function Sqrt(x: Double): Double;
function Echo(const s: string): string;

// SKIP: Boolean return
function IsEven(x: Integer): Boolean;

// SKIP: array parameter
function Total(const arr: array of Integer): Integer;

// SKIP: generic method
function GetItem<T>(const list: TList<T>): Integer;

// SKIP: Pointer parameter
function GetBuffer(const p: Pointer): Integer;
```

---

## 4. Comment binding

### 4.1 Binding rules

| Pattern | Bound? |
|---------|:------:|
| Comment → declaration (adjacent) | Yes |
| Comment → blank line → declaration | Yes |
| Comment1 → comment2 → declaration | Both bound |
| Comment1 → blank → comment2 → declaration | Comment2 bound |
| Declaration → trailing comment | **No** |

### 4.2 Examples

```pascal
// WRONG — trailing comment is ignored
function Foo: Integer; // this comment is NOT bound

// RIGHT — preceding comment is bound
// This comment IS bound.
function Bar: Integer;
```

### 4.3 Comment style recommendation

**Preference order**:

| Priority | Style | Reason |
|:--------:|-------|--------|
| 1 | `(* ... *)` | `*)` is rare in natural language and JSON — safest |
| 2 | `// ...` | Ends at end of line — never affected by braces |
| 3 | `{ ... }` | **Only when the body contains no `}`** |

**Recommended default**: `(* ... *)`.

### 4.4 Example: safely using all three

```pascal
(*
  Computes the sum of two integers.

  source: first addend
  lang:   second addend

  Return value: the sum as an Integer.
*)
function Add(source, lang: Integer): Integer;

// Echo the input string.
// s: input string
// Return value: the input string unchanged.
function Echo(const s: string): string;

{ TODO: deprecate this function in v9. }
procedure OldProc;
```

### 4.5 Fatal trap: `}` inside `{ ... }` kills the whole comment

**Trigger**: the body of a `{ ... }` comment contains a `}` character.
**Result**: the declaration's `Comment` field becomes empty.

#### 4.5.1 Mechanism

```
Source:  { parse { "ok": true } ... }   ← text contains nested braces
         ↓
TTextParsing (tsPascal) treats `{` … `}` as non-nested
         ↓
The comment token is cut at the first `}`
         ↓
ExtractPrecedingComments sees only an isolated `}` and breaks
         ↓
Comment field: ""  (empty)
```

#### 4.5.2 Diagnosis

> **Comment empty = structural problem, check for `}`. Comment garbled = encoding problem, check the code page.**

#### 4.5.3 Trigger table

| Body content | Triggers? |
|--------------|:---------:|
| No `}` | No |
| Single `}` | **Yes** |
| Full-width `｝` (U+FF5D) | No |
| `}` inside `(* ... *)` | No |
| `*)` inside `(* ... *)` | **Yes** |
| `}` inside `// ...` | No |
| `{ * ... }` produced by C→Pascal conversion, containing `}` | **Yes** |

#### 4.5.4 Fix

**Preferred — switch to `(* ... *)`**:

```pascal
(*
  Returns the configuration JSON.
  The body is a JSON object with `host` and `port` fields.
*)
function GetConfig: string;
```

**Alternative — use `//`**:

```pascal
// Returns the configuration JSON.
// The body is a JSON object with `host` and `port` fields.
function GetConfig: string;
```

### 4.6 How the tool description is assembled

`pas_mcp_generator_tool` calls `GetFullDescription(Comment)` to build the tool's `description`. It behaves as follows:

| Step | Behaviour |
|:----:|-----------|
| 1 | Split `Comment` on `#10` / `#13` |
| 2 | Skip **empty** lines |
| 3 | Skip lines starting with `@` (Doxygen tags) |
| 4 | Strip leading `*` / `**` (block-comment continuation markers) |
| 5 | Join remaining lines with a single space |
| 6 | Truncate to **200 characters** |

**Consequences**:

- Multi-line comment → single-line description.
- `@param` / `@return` lines are **skipped**.
- The `{ }` / `(* *)` / `//` markers are already stripped.
- **The 200-character limit is hard**.

**Concrete example**:

```pascal
(*
  Computes the sum of two integers.
  source: first addend
  lang:   second addend

  @return the sum

  Return value: the sum as an Integer.
*)
function Add(source, lang: Integer): Integer;
```

Resulting description:

```
"Computes the sum of two integers. source: first addend lang:   second addend Return value: the sum as an Integer."
```

(The `@return the sum` line is skipped.)

**Best practice**:

- First line: a one-sentence summary of what the function does.
- Middle lines: one parameter per line.
- Last lines: return value description starting with `Return value:`.
- Keep it short. **Put the most important information in the first 200 characters.**

### 4.7 Block-comment `*` prefix (C→Pascal path)

When the input is a C header, `Translate_C_Typ_To_Pascal` converts each C comment to a Pascal `{ ... }` where every line after the first carries a ` * ` prefix:

```
{ @param a first addend
 * @param b second addend }
```

`Z.Pascal_Func_Model` (v3.0) strips this prefix automatically:

| Raw line | After stripping (used for parsing) |
|----------|-------------------------------------|
| `' @param a first addend'` | unchanged (no `*`) |
| `' * @param b second addend'` | `' @param b second addend'` |
| `' *         continuation'` | `'         continuation'` (indent preserved) |

**Rule**:

- Stripping triggers **only when the first non-blank character is `*`**.
- The remaining characters (including their own indentation) are preserved.
- Indentation is measured **after** stripping.

**What this means for you**:

- Writing Pascal by hand → no ` * ` prefix, follow §4.3.
- Passing a C header → the prefix is added by the toolchain and stripped automatically. Do nothing.

---

## 5. Parameter and return value descriptions

### 5.1 Data flow

```
Source code
    ├── TTextParsing
    │       ├── ttComment tokens (adjacent to declaration)
    │       └── Function signature
    │
    ├── ExtractParamDescriptions  →  Params[i].Description
    ├── GetFullDescription        →  tool description (200-char max)
    └── Signature                 →  ReturnType, Params[i].Name, Params[i].PascalType
```

### 5.2 Parameter description extraction (indentation-aware state machine)

`ExtractParamDescriptions` (v3.0):

| Step | Behaviour |
|:----:|-----------|
| 1 | `CleanComment`: strip markers, unify line endings to LF |
| 2 | Split into lines on `#10` |
| 3 | `GetContentLine`: strip leading `*` prefix (C→Pascal path) |
| 4 | Maintain state: `CurrentParam`, `CurrentDesc`, `ParamIndent` |
| 5 | **Blank line** → terminate current block |
| 6 | **Recognised as a parameter declaration** (line-start name or Doxygen form) → terminate current block, start new one |
| 7 | **Indent > ParamIndent** → append to current description (raw indentation preserved) |
| 8 | **Anything else** → terminate current block |

**Parameter-declaration recognition**:

| Form | Syntax | Example |
|:----:|--------|---------|
| A | `name ...` at line start | `source: source text` |
| B | `@name ...` / `\name ...` | `@source source text` |
| C | `@param name ...` / `\arg name ...` / `@parameter name ...` | `@param source source text` |

**Key constraint**: the parameter name must be at *line start* (or immediately after a Doxygen marker). A name appearing mid-sentence is never mistaken for a parameter declaration.

**Multi-line continuation**: after a parameter block starts, any line with **deeper indentation** is appended to that parameter's description (raw indentation and line breaks preserved).

**Example**:

```pascal
(*
  Generates code for the given target.

  target: target language, pick one:
            pascal_service   generate a Pascal service unit
            pascal_call      generate a Pascal call unit
            python_service   generate a Python service module
          <unit> is the normalized UnitName.
*)
function Generate(target: string): string;
```

Extracted description for `target`:

```
"target language, pick one:\n            pascal_service   generate a Pascal service unit\n            pascal_call      generate a Pascal call unit\n            python_service   generate a Python service module\n          <unit> is the normalized UnitName."
```

**Separator stripping** (after the parameter name, at start of description):

| Character | Unicode |
|:---------:|:-------:|
| `:` | U+003A |
| `=` | U+003D |
| `：` | U+FF1A |
| `＝` | U+FF1D |

### 5.3 Accepted parameter description formats

```pascal
// Format A — colon
(*
  Adds two integers.

  source: first addend
  lang:   second addend
*)
function Add(source, lang: Integer): Integer;

// Format B — equals
(*
  Adds two integers.

  source = first addend
  lang   = second addend
*)
function Add(source, lang: Integer): Integer;

// Format C — Doxygen
(*
  Adds two integers.

  @param source first addend
  @param lang   second addend
*)
function Add(source, lang: Integer): Integer;

// Format D — whitespace
(*
  Adds two integers.

  source  first addend
  lang    second addend
*)
function Add(source, lang: Integer): Integer;

// Format E — multi-line indentation continuation
(*
  Generates code for the target.

  target: target language, pick one:
            pascal_service
            pascal_call
            python_service
          <unit> is the normalized UnitName.
*)
function Generate(target: string): string;
```

### 5.4 Parameter description blocks need NOT be stacked

Parameter description blocks are processed independently. Different parameters' blocks may appear at different places in the comment.

**Legal**:

```pascal
(*
  Function purpose.

  source: source text.

  Some free-form description in between.

  lang: language name.
*)
```

**Recommended** (for readability and predictable tool-description assembly):

```pascal
(*
  Function purpose.

  source: source text.
  lang:   language name.

  Return value: a string.
*)
```

**Rules of thumb**:

1. **Function purpose** in 1–2 lines at the top.
2. **Parameter blocks** in the middle, one line per parameter.
3. **Return value description** at the bottom, starting with `Return value:`.
4. **Multi-line parameter descriptions** → use indentation continuation.

### 5.5 Parameter name matching

| Rule | Detail |
|------|--------|
| Case | **Insensitive** (`Source` matches `source`) |
| Anchor | Must be at **line start** (or after a Doxygen marker) |
| Multi-line | Deeper-indented following lines accumulate |
| One per block | Each parameter block corresponds to exactly one parameter |

### 5.6 Return value comments

> **Common misconception**: `@return` is not extracted. The only structured source of return type info is the signature's `: T`.

#### 5.6.1 What enters JSON and what does not

| JSON field | Source | Carries return value info? |
|------------|--------|:--------------------------:|
| `Name` | Function name | No |
| `IsFunction` | `function` / `procedure` | No |
| `Params[i].Name` | Parameter list | No |
| `Params[i].Typ` | Raw parameter type | No |
| `Params[i].PascalType` | Normalized parameter type | No |
| `Params[i].Description` | Comment `name: ...` | No |
| **`ReturnType`** | **Signature `: T`** | **Yes — the only structured source** |
| `Comment` | Full comment text | Text only, not structured |

**Three conclusions**:

1. `ReturnType` is the only structured return information — from `: T` in the signature.
2. Nothing in the comment enters a structured field.
3. For semantic description of the return value, the agent must read `Comment` as plain text.

#### 5.6.2 `ReturnType` normalization

| Signature type | `tnf_Json` mode | `tnf_ABI` mode |
|----------------|:---------------:|:--------------:|
| Any integer | `int64` | lowercase original (e.g. `integer`) |
| Any float | `double` | lowercase original (e.g. `double`) |
| Any string | `string` | lowercase original (e.g. `string`) |

The toolchain assumes the caller does not need to distinguish `Integer` from `Int64` — everything is sent as a 64-bit integer.

#### 5.6.3 Why return comments are not extracted

| Approach | Pros | Cons |
|----------|------|------|
| Add a `ReturnDescription` field | Complete info | Touches `TFunctionStructure`, `LoadFromParser`, `SaveToJson` |
| Don't extract (current) | Simple | Agent reads return semantics from `Comment` text |
| Put return description in `Comment` | Simple | Agent must parse free text |

Current choice: **the third option**. Return descriptions live in `Comment` as plain text. This is exactly why you should write the return value clearly — it is the agent's only source for return-value semantics.

#### 5.6.4 Correct return-value comment

```pascal
(*
  Computes the sum of two integers.

  source: first addend
  lang:   second addend

  Return value: the sum of `source` and `lang` as an Integer.
*)
function Add(source, lang: Integer): Integer;
```

| Element | Effect |
|---------|--------|
| `: Integer` | Only structured return info → normalized to `int64` |
| `Return value: ...` | Human/agent-readable supplementary text — stays in `Comment` only |
| `Integer` inside the description text | **Not** mistaken for a parameter name (mid-sentence, not line start) |

#### 5.6.5 Correction to older documentation

Older versions suggested `Return value:` might be misparsed as a parameter. **It will not.** The extractor requires the parameter name at line start. `Return value` is at line start but it is not a parameter name, so it is skipped. `Integer` appears mid-sentence, so it is not a candidate.

#### 5.6.6 Counterexamples

```pascal
// WRONG — relies on @return for return info
(*
  @return the sum
*)
function Add(source, lang: Integer): Integer;
// Extracted ReturnType = "int64"; "@return the sum" enters no structured field.

// WRONG — @return on a procedure
(*
  @return nothing
*)
procedure Log(const msg: string);
// Procedure has no ReturnType field. @return is ignored entirely.

// WRONG — return type not in whitelist
(*
  Return value: a boolean.
*)
function IsEven(x: Integer): Boolean;
// Boolean is not in the whitelist. Whole declaration is skipped.
```

#### 5.6.7 Recommended template

```pascal
(*
  <one-sentence purpose>.

  <param1>: <description of param1>
  <param2>: <description of param2>

  Return value: <semantic description of the returned value>.
*)
function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;
```

**Rules**:

- Parameter blocks in the middle.
- Return value block at the bottom, starting with `Return value:`.
- Do not use `<paramname>:` format inside the return description — readers will be confused.

#### 5.6.8 Same-name risk — corrected for v3.0

> The problem described in v7.0 no longer exists in v3.0 because of the **line-start anchor** rule.

**Safe example**:

```pascal
(*
  Reads configuration.

  host: host name
  port: port number

  The JSON payload is a key-value object with host and port fields.
  Note that host is the host name and port is the port number.
*)
function GetConfig(host: string; port: Integer): string;
```

Analysis:

- `host: host name` → line starts with `host` → parsed. Description: `host name`.
- `port: port number` → line starts with `port` → parsed. Description: `port number`.
- `The JSON payload ...` → line starts with `The` → skipped.
- `Note that host is the host name and port is the port number.` → line starts with `Note` → skipped. `host` and `port` in the middle are **not mistaken** for parameter declarations.

**Remaining edge case**: a line that **starts with the parameter name** but is not a declaration line can still pollute that parameter's description.

```pascal
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string);
// host description becomes:
//   "host name host can also be an IP address."
// (polluted)
```

**Four ways to avoid it**:

1. Merge into the parameter description line:
   ```pascal
   (*
     host: host name (can also be an IP address)
   *)
   ```

2. Quote the leading parameter name:
   ```pascal
   (*
     host: host name

     `host` can also be an IP address.
   *)
   ```

3. Use a different word at line start:
   ```pascal
   (*
     host: host name

     This parameter can also be an IP address.
   *)
   ```

4. Deeper indent (make it a continuation of the parameter block):
   ```pascal
   (*
     host: host name
           can also be an IP address.
   *)
   ```

#### 5.6.9 Relationship with Doxygen `@return`

| Syntax | Extracted? |
|--------|:----------:|
| `@return the sum` | No structured field (line starts with `@`, skipped) |
| `\return the sum` | No structured field (same reason) |
| `Return value: the sum` | No structured field, but stays in `Comment` |

**Conclusion**:

- `@return` / `\return` are safe (never mistaken for parameters) but are not extracted.
- `Return value:` is the recommended form — it stays in `Comment` for the agent to read.
- Do not use `返回值: xxx` (bare `xxx:`) style — it looks like a parameter.

---

## 6. Complete examples

### 6.1 Everything correct

```pascal
unit SampleUnit;

interface

(*
  Computes the sum of two integers.

  source: first addend
  lang:   second addend

  Return value: the sum as an Integer.
*)
function Add(source, lang: Integer): Integer;

(*
  Computes the product of two integers.

  @param source first multiplicand
  @param lang   second multiplicand

  Return value: the product as an Integer.
*)
function Mul(source, lang: Integer): Integer;

(*
  Echo the input string.

  s: string to echo.

  Return value: the input string unchanged.
*)
function Echo(const s: string): string;

(*
  Logs a message.

  msg: log content.
*)
procedure Log(const msg: string);

(*
  Returns the configuration JSON.

  Return value: a string containing a JSON object.
*)
function GetConfig: string;

implementation

end.
```

### 6.2 Multi-line parameter description

```pascal
unit MultiLineDemo;

interface

(*
  Generates code for the given target.

  model_json: the model JSON produced by abi_decl_to_json.
  target: target language, pick one:
            pascal_service   generate a Pascal service unit
            pascal_call      generate a Pascal call unit
            python_service   generate a Python service module
            python_call      generate a Python call module
          <unit> is the normalized UnitName.

  Return value: a string containing the generated code.
*)
function abi_generate_to_text(model_json: string; target: string): string;

implementation

end.
```

Extracted:

| Parameter | Description |
|-----------|-------------|
| `model_json` | `the model JSON produced by abi_decl_to_json.` |
| `target` | `target language, pick one:\n            pascal_service   generate a Pascal service unit\n            pascal_call      generate a Pascal call unit\n            python_service   generate a Python service module\n            python_call      generate a Python call module\n          <unit> is the normalized UnitName.` |

### 6.3 Examples of things to avoid

```pascal
unit BadUnit;

interface

// SKIP: parameter has var
procedure Modify(var x: Integer);

// SKIP: returns Boolean
function IsEven(x: Integer): Boolean;

// SKIP: array parameter
function Sum(const arr: array of Integer): Integer;

// SKIP: generic method
function GetItem<T>(const list: TList<T>): Integer;

// SKIP: Pointer parameter
function GetBuffer(const p: Pointer): Integer;

// COMMENT LOST: curly-brace comment contains a closing brace
{
  Returns the configuration JSON.
  Example: a JSON object with host and port fields.
}
function GetConfig: string;

// PARAM DESCRIPTION POLLUTED: line starts with the parameter name
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string): Boolean;

implementation

end.
```

---

## 7. Common mistakes and their fixes

| Wrong | Result | Right |
|-------|--------|-------|
| `procedure P(var x: Integer)` | Whole declaration skipped | `function P(const x: Integer): Integer` |
| `procedure P(out x: Integer)` | Whole declaration skipped | `function P: Integer` |
| `function F: Boolean` | Whole declaration skipped | `function F: Integer` (0/1) |
| `function F(a: TPoint)` | Whole declaration skipped | Use two `Double` parameters |
| `function F(a: array of Integer)` | Whole declaration skipped | Use a JSON string or multiple calls |
| `function F(a: Pointer)` | Whole declaration skipped | Use `Int64` carrying the address |
| Class method | Skipped | Move to top level |
| `implementation` section function | Skipped | Move to `interface` |
| Trailing comment `function F; // ...` | Comment ignored | Move comment above |
| `{ ... }` containing `}` | Whole comment lost | Use `(* ... *)` |
| `(* ... *)` containing `*)` | Comment cut at `*)` | Put a space between `*` and `)` |
| Relying on `@return` for return info | Not extracted | Declare `: T` in the signature |
| `@return` on a `procedure` | Ignored | Do not use it on procedures |
| `返回值: xxx` in a comment | Confusing to readers | Use `Return value:` |
| Parameter name mid-sentence | **Safe** (line-start anchor) | No fix needed |
| Line starting with parameter name but not a declaration | **May pollute that parameter** | Reword the line, quote the name, or indent it |
| Parameter descriptions scattered | **Safe in v3.0** | No fix needed |
| Multi-line parameter description | **Accumulates in v3.0** | No fix needed |

---

## 8. Self-check before you save the file

| # | Check | Action if failing |
|:-:|-------|-------------------|
| 1 | Declaration in `interface`? | Move it |
| 2 | At top level? | Move it |
| 3 | No `var` / `out` parameters? | Use `const` + return value |
| 4 | All types in the whitelist? | Use integer / float / string |
| 5 | Comment directly above? | Move the comment |
| 6 | No `}` inside `{ ... }`? | Switch to `(* ... *)` |
| 7 | Return type declared as `: T`? | Add `: T` — do not rely on `@return` |
| 8 | Parameter names at line start? | Move them to line start |

---

## 9. Minimum parseable template

```
unit <UnitName>;

interface

(*
  <one-sentence purpose>.

  <param1>: <description of param1>
  <param2>: <description of param2>

  Return value: <semantic description>.
*)
function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;

implementation

function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;
begin
  // implementation
end;

end.
```

**Fill-in rules**:

| Placeholder | Allowed values |
|-------------|----------------|
| `<UnitName>` | Any valid Pascal identifier |
| `<name>` | Any valid Pascal identifier |
| `<paramN>` | Any valid Pascal identifier |
| `<typeN>` | See §3 |
| `<return type>` | See §3 |

**Reminders**:

- The template uses `(* ... *)` so `}` inside the comment is safe.
- The return type must be in the signature (`: T`). The comment's return description is only for the agent's semantic understanding.
- Parameter names must be at **line start**. Subsequent indented lines are absorbed into that parameter's description.

---

## 10. Design principles

### 10.1 Toolchain assumptions

- **Top-level only**: class methods, nested routines, and `implementation`-section declarations are skipped.
- **Value types only**: `var`, `out`, arrays, records, classes, generics, enums, and untyped pointers are skipped.
- **Structured comments**: comments must be adjacent to the declaration; no nested braces; no closing brace inside `{ }`.
- **Structured parameters**: names from the signature, descriptions from the comment; names must be at line start; indented continuation is supported.
- **Structured return**: type from the signature; description from the comment text; description does not enter JSON.
- **Silent skip**: no exceptions; skips are recorded in the `Report`; parsing continues.

### 10.2 Six rules for the author

1. **Read the whitelist before you write** (§3). Parameter and return types must be in it.
2. **Self-check after you write** (§8). Interface? Top level? Any `var` / `out`?
3. **Use `(* ... *)` when in doubt** (§4.5).
4. **Declare the return type in the signature** (§5.6). `function F: T`, not `@return`.
5. **Put parameter names at line start** (§5.2).
6. **Write detailed comments**. The comment is what the agent sees. Detailed in, precise out.

### 10.3 What changed across versions

| Item | v4.0 | v5.0 | v6.0 | v7.0 | v8.0 |
|------|:----:|:----:|:----:|:----:|:----:|
| Blank lines allowed in comment | Yes | Yes | Yes | Yes | Yes |
| Type whitelist | Yes | Yes | Yes | Yes | Yes |
| `{ }` containing `}` trap | No | Yes | Yes | Yes | Yes |
| Return value comment guidance | No | No | Yes | Yes | Yes |
| Data-flow table | No | No | No | Yes | Yes |
| `ReturnType` normalization | No | No | No | Yes | Yes |
| Parameter stacking rule | No | No | Yes | Yes | Yes |
| Tool description assembly rules | No | No | No | Yes | Yes |
| Comment style recommendation | No | No | No | Yes | Yes |
| Same-name pollution risk | No | No | No | Yes | **Yes** |
| **Parameter description state machine** | No | No | No | No | **Yes** |
| **Multi-line description accumulation** | No | No | No | No | **Yes** |
| **Line-start anchor** | No | No | No | No | **Yes** |
| **Block-comment prefix handling** | No | No | No | No | **Yes** |
| **Human-misreading scenarios** | No | No | No | No | **Yes** |
| Iron rules | 3 | 4 | 5 | 6 | **8** |
| Self-check items | 5 | 6 | 7 | 8 | **8** |

---

## 11. Common misreadings

### 11.1 "Parameter descriptions must be stacked together"

**Reality**: they may be scattered. Each parameter block is processed independently.

```pascal
// Legal — source and lang are both extracted correctly.
(*
  Purpose.

  source: source text.

  Some free-form description.

  lang: language name.
*)
```

**Recommendation**: still stack them, for readability and predictable tool-description assembly.

### 11.2 "I cannot mention a parameter name in the prose"

**Reality**: line-start anchor means mid-sentence names are safe.

```pascal
(*
  host: host name

  This config controls the host used by the service.
*)
```

`host` description = `"host name"`. The `host` in the second line is not mistaken for a declaration.

**Edge case**: a line starting with the parameter name but not a declaration line. See §5.6.8.

### 11.3 "Multi-line parameter descriptions are truncated"

**Reality**: v3.0 accumulates indented continuation lines into the current description.

```pascal
(*
  target: target language, pick one:
            pascal_service
            pascal_call
          <unit> is the normalized UnitName.
*)
```

`target` description contains all three continuation lines.

### 11.4 "`{ ... }` is forbidden"

**Reality**: `{ ... }` is fine, as long as the body contains no `}`. The C→Pascal conversion product `{ * ... }` is generated by the toolchain and is handled automatically.

```pascal
{ Short note. }                                  // OK
{ Nested { brace } in body }                     // Broken — comment lost
(* Anything with braces is fine: { "k": 1 } *)   // OK
```

### 11.5 "Return value descriptions are extracted into JSON"

**Reality**: only the signature's `: T` enters JSON. Comments stay in `Comment` as text.

```pascal
(*
  @return the sum
*)
function Add(a, b: Integer): Integer;
// JSON: ReturnType="int64". "@return the sum" is not in any structured field.
// The agent reads `Comment` for the semantic meaning.
```

**Recommendation**: write the return description anyway. The agent reads `Comment`.

### 11.6 "I can omit the return type and let the comment describe it"

**Reality**: no. `Fill_Pascal` requires `: T` on every `function`. Missing `: T` → error → whole declaration skipped.

```pascal
// WRONG — parser error, declaration skipped
function Add(a, b: Integer);
```

### 11.7 "`in` is forbidden like `var`"

**Reality**: `in` is allowed and treated like `const`.

```pascal
function F(in x: Integer): Integer;   // OK
```

### 11.8 "Parameter names are case-sensitive"

**Reality**: matching is case-insensitive.

```pascal
(*
  SOURCE: source text
*)
function F(Source: string);
// Description of `Source` = "source text".
```

### 11.9 "Comments must be immediately adjacent"

**Reality**: blank lines and multiple comment blocks are allowed. All adjacent comments are collected.

```pascal
// part 1

// part 2

function F: Integer;
// Comment = "part 1\npart 2"
```

### 11.10 "C→Pascal conversion loses parameter descriptions"

**Reality**: the ` * ` prefix is handled automatically. Doxygen-style C comments survive intact.

```c
/**
 * @param a first addend
 * @param b second addend
 */
int add(int a, int b);
```

After conversion:

- `a` description = `"first addend"`
- `b` description = `"second addend"`

---

## 12. Revision history

- **v8.0 (2026-09-20)** — English rebuild, condensed prose, expanded examples, added "why detailed comments matter" banner. Structural changes from v7.0 preserved as-is.
- **v7.0 (2026-09-20)** — Added §5.6.1 data flow, §5.6.2 normalization, §5.6.8 same-name risk, §4.6 tool description assembly, §4.3 style recommendation, expanded iron rules to 8.
- **v6.0 (2026-09-20)** — Added §5.6 return-value comment guidance.
- **v5.0 (2026-09-20)** — Added §4.5 `}` trap.
- **v4.0 (2026-09-10)** — Rewrite. Blank line rules, type whitelist clarified.
- **v3.0 (2026-09-02)** — Instance-driven rewrite.
- **Earlier** — Initial.

---

**This document is the parsing contract. Any deviation means declarations will be silently skipped, comments silently lost, return descriptions silently ignored, or parameter descriptions silently dropped.**

**If `Comment` is empty — look for `}`.**
**If a parameter description is missing — check that the name is at line start.**
**If a parameter description looks wrong — check for a non-declaration line that starts with the parameter name.**
**And above all: write detailed comments. The agent sees only your comment, not your code.**