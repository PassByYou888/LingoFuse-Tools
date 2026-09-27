# Pascal Declaration Rules for the ABI Toolchain

**Version**: 9.0
**Audience**: AI assistants and engineers writing Pascal declarations consumed by the `Z.Pascal_Func_Tool` → `Z.Pascal_Func_Model` → generator chain.
**Contract**: This document is the parsing contract. Deviating from it causes a declaration to be silently skipped, a comment to be silently dropped, or a parameter description to be silently lost.

---

## 0. Thirty-Second Reference

### 0.1 What can I write?

```pascal
// EXTRACTED (top-level, in interface section)
function Add(a, b: Integer): Integer;
procedure Log(const msg: string);
function Echo(const s: string): string;
```

```pascal
// SKIPPED (silent — no error, no warning)
procedure Modify(var x: Integer);              // var
procedure Fill(out y: Integer);                // out
function  IsEven(x: Integer): Boolean;         // Boolean not in whitelist
function  Sum(const a: array of Integer): Integer;  // array
function  Get(p: Pointer): Integer;            // Pointer
function  Wrap<T>(x: T): Integer;              // generic

type
  TFoo = class
    function Bar: Integer;                     // nested in class
  end;

implementation
function Helper: Integer;                      // in implementation section
```

### 0.2 What is useful?

| What you want the AI to know | Where to write it |
|------------------------------|-------------------|
| Function purpose | First line(s) of the comment |
| Parameter meaning | A block of `name: description` lines |
| Return semantics | `Return value: ...` line in the comment |
| Structured return type | **Signature only** — `function F: Integer` |

The AI sees exactly two things:
- **`Comment`** — the adjacent comment, plain text (max 200 chars for the tool description).
- **`ReturnType`** — normalized from the signature (`: T`).

Nothing else from the comment enters structured JSON. Only the signature does.

---

## 1. Position

### 1.1 Rule

Must be a top-level declaration in the **`interface`** section.

### 1.2 Examples

```pascal
unit MyUnit;

interface

// EXTRACTED
function Add(a, b: Integer): Integer;
procedure Log(const msg: string);

type
  TFoo = class
    function Nested: Integer;     // SKIPPED — nested in class
  end;

  TBar = record
    procedure Nested;             // SKIPPED — nested in record
  end;

  IBaz = interface
    procedure Nested;             // SKIPPED — nested in interface
  end;

implementation

function Hidden: Integer;         // SKIPPED — implementation section
begin
  Result := 0;
end;

end.
```

---

## 2. Parameter Modifiers

### 2.1 Rule

| Modifier | Allowed? |
|----------|:--------:|
| (blank)  | ✅ |
| `const`  | ✅ |
| `in`     | ✅ |
| `var`    | ❌ whole declaration skipped |
| `out`    | ❌ whole declaration skipped |

### 2.2 Examples

```pascal
// OK
function Add(a, b: Integer): Integer;
function Mul(const a, b: Integer): Integer;
function Echo(const s: string): string;

// SKIPPED — reference passing cannot be serialized
procedure Modify(var x: Integer);
procedure Fill(out y: Integer);
```

### 2.3 Fix for `var` / `out`

Return the value instead of writing through a reference.

```pascal
// WRONG
procedure Increment(var x: Integer);

// RIGHT
function Increment(const x: Integer): Integer;
```

---

## 3. Type Whitelist

### 3.1 Allowed types

| Family | Types |
|--------|-------|
| Integer | `Integer`, `Int64`, `Cardinal`, `LongInt`, `DWord`, `Word`, `SmallInt`, `Byte`, `UInt64`, `LongWord` |
| Float | `Double`, `Single`, `Extended`, `Real` |
| String | `string`, `AnsiString`, `UnicodeString`, `PChar`, `PAnsiChar`, `PWideChar`, `TP_String`, `TPascalString`, `TUPascalString`, `U_String` |

### 3.2 Forbidden types

Any of these skip the **entire** declaration.

| Category | Example |
|----------|---------|
| Boolean | `Boolean`, `WordBool`, `LongBool` |
| Variant | `Variant`, `OleVariant` |
| Array | `array of X`, `array[0..N] of X` |
| Record | `TPoint`, `TRect`, custom `record` |
| Class | `TObject`, `TStringList`, custom `class` |
| Interface | `IInterface`, custom `interface` |
| Enum | `TColor`, custom `enum` |
| Set | `set of X` |
| Generic | `TList<X>`, `TGenericList<X>` |
| Date/time | `TDateTime`, `TDate`, `TTime` |
| Pointer | `Pointer`, `PInteger`, `PByte` |
| Event | `TNotifyEvent` |
| Anonymous method | `reference to procedure` |

### 3.3 Examples

```pascal
// OK
function Add(a, b: Integer): Integer;
function Sqrt(x: Double): Double;
function Echo(const s: string): string;

// SKIPPED
function IsEven(x: Integer): Boolean;                // Boolean
function Sum(const a: array of Integer): Integer;    // array
function GetBuffer(const p: Pointer): Integer;       // Pointer
function Now2: TDateTime;                            // TDateTime
function Wrap<T>(x: T): Integer;                     // generic
```

### 3.4 Pointer workaround

Carry the address as `Int64` if you genuinely need to pass a pointer.

```pascal
// WRONG
function ReadAddr(const p: Pointer): Int64;

// RIGHT
function ReadAddr(const addr: Int64): Int64;
```

---

## 4. Comments

### 4.1 Binding rules

| Situation | Bound? |
|-----------|:------:|
| Comment directly above declaration | ✅ |
| Comment → blank line → declaration | ✅ |
| Comment1 → Comment2 → declaration | ✅ (both) |
| Declaration → trailing comment | ❌ |

```pascal
// WRONG — trailing comment is ignored
function Foo: Integer; // this text is lost

// RIGHT — preceding comment is bound
// this text is captured
function Bar: Integer;
```

### 4.2 Comment style — safest first

1. **`(* ... *)`** — safest; `*)` is rare in natural text and JSON.
2. **`// ...`** — ends at end of line; immune to braces.
3. **`{ ... }`** — only when the body contains no `}`.

### 4.3 The `}` trap

A `{ ... }` comment body containing `}` is truncated at the first `}`. The declaration's `Comment` field becomes empty.

```pascal
// BROKEN — Comment is lost
{
  Returns the config JSON.
  Example: {"host": "localhost", "port": 8080}
}
function GetConfig: string;
```

```pascal
// FIXED
(*
  Returns the config JSON.
  Example: {"host": "localhost", "port": 8080}
*)
function GetConfig: string;
```

Same problem applies to `(* ... *)` containing the sequence `*)`.

| Comment body contains | Result |
|-----------------------|--------|
| `{ ... }` with `}` | Comment lost |
| `{ ... }` with fullwidth `｝` | OK |
| `(* ... *)` with `}` | OK |
| `(* ... *)` with `*)` | Comment truncated |

### 4.4 Tool description extraction

The generator collects the comment into a **single-line tool description**:

1. Split by newline.
2. Skip empty lines.
3. Skip lines starting with `@` (Doxygen tags).
4. Strip leading `*` continuation markers.
5. Join with spaces.
6. Truncate to **200 characters**.

```pascal
(*
  Computes the sum of two integers.

  a: first addend
  b: second addend

  @return the sum          <- skipped (@ line)

  Return value: the sum of a and b.
*)
function Add(a, b: Integer): Integer;
```

Result:
```
Computes the sum of two integers. a: first addend b: second addend Return value: the sum of a and b.
```

Keep the **first 200 characters** meaningful. Anything past that is cut.

---

## 5. Parameter Descriptions

### 5.1 Rule

Inside the comment, the parser recognizes a **parameter declaration line** only when the parameter name is at the **start of the line** (or directly after a Doxygen tag).

### 5.2 Accepted forms

```pascal
// Form A: name + colon
(*
  a: first addend
  b: second addend
*)
function Add(a, b: Integer): Integer;

// Form B: name + equals
(*
  a = first addend
  b = second addend
*)

// Form C: Doxygen @param
(*
  @param a first addend
  @param b second addend
*)

// Form D: name + whitespace
(*
  a  first addend
  b  second addend
*)

// Form E: multi-line with indented continuation
(*
  target: pick one:
            pascal_service
            pascal_call
          the rest of the description.
*)
```

### 5.3 Case sensitivity

Parameter name matching is **case-insensitive**.

```pascal
(*
  SOURCE: source text
*)
function F(Source: string);
// Source.Description = "source text"
```

### 5.4 Multi-line parameter descriptions

Continuation lines must be **indented deeper** than the parameter name.

```pascal
(*
  Generates code.

  target: target language, pick one:
            pascal_service   generate Pascal service
            pascal_call      generate Pascal call
            python_service   generate Python service
          <unit> is the normalized UnitName.

  Return value: the generated code.
*)
function Generate(target: string): string;
```

`target.Description` =
```
target language, pick one:
            pascal_service   generate Pascal service
            pascal_call      generate Pascal call
            python_service   generate Python service
          <unit> is the normalized UnitName.
```

Indentation and newlines are preserved verbatim.

### 5.5 Lines that accidentally look like a parameter

A line is only a parameter declaration if the parameter name is **at the start**. If a natural-language sentence starts with a parameter name, it may be wrongly absorbed.

```pascal
// SUBTLE PROBLEM
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string);
// host.Description becomes:
// "host name host can also be an IP address."
```

Fix: rewrite the sentence, or wrap the name, or deepen the indent.

```pascal
// FIXED — wrap the name
(*
  host: host name

  `host` can also be an IP address.
*)

// FIXED — deepen the indent (becomes continuation)
(*
  host: host name
        can also be an IP address.
*)
```

If the parameter name appears in the middle of a line, it is **ignored**. Only the line start matters.

```pascal
// SAFE — no pollution
(*
  host: host name
  port: port number

  This config controls the host and port used by the service.
*)
```

---

## 6. Return Values

### 6.1 What enters JSON, what doesn't

| JSON field | Source | Contains return info? |
|-----------|--------|:---------------------:|
| `Name` | Function name | No |
| `IsFunction` | `function` / `procedure` | No |
| `Params[i].Name` | Signature | No |
| `Params[i].Typ` | Signature | No |
| `Params[i].Description` | Comment | No |
| **`ReturnType`** | **Signature `: T`** | **Yes** |
| `Comment` | Adjacent comment | Only if you write it |

### 6.2 Hard rule

**Return type must be declared in the signature**. Writing it only in the comment loses it.

```pascal
// WRONG — no signature return type
(*
  @return the sum
*)
function Add(a, b: Integer);
// Result: skipped, "missing ':' or return type"

// RIGHT
(*
  Return value: the sum of a and b.
*)
function Add(a, b: Integer): Integer;
// ReturnType = "int64" (or "integer" in tnf_ABI mode)
```

### 6.3 Return type normalization

| Signature type | `tnf_Json` mode | `tnf_ABI` mode |
|----------------|:---------------:|:--------------:|
| Any integer | `int64` | original lowercase |
| Any float | `double` | original lowercase |
| Any string | `string` | original lowercase |

The JSON never carries the original type name in `tnf_Json` mode. The comment carries the human-readable description.

### 6.4 Recommended comment shape

```pascal
(*
  Computes the sum of two integers.

  a: first addend
  b: second addend

  Return value: the sum of a and b as an Integer.
*)
function Add(a, b: Integer): Integer;
```

| Line | Purpose | In structured JSON? |
|------|---------|:-------------------:|
| `: Integer` | Structured return type | ✅ |
| `Return value: ...` | Human / LLM-readable semantics | ❌ — comment only |

### 6.5 Procedures

`procedure` has no return type. Do not write a return-value line.

```pascal
// OK
(*
  Logs a message.

  msg: log content
*)
procedure Log(const msg: string);

// WRONG — @return is ignored for procedures
(*
  @return nothing
*)
procedure Log2(const msg: string);
```

---

## 7. Complete Examples

### 7.1 Every declaration extracted

```pascal
unit SampleUnit;

interface

(*
  Computes the sum of two integers.

  a: first addend
  b: second addend

  Return value: the sum of a and b.
*)
function Add(a, b: Integer): Integer;

(*
  Computes the product of two integers.

  @param a first multiplicand
  @param b second multiplicand

  Return value: the product of a and b.
*)
function Mul(a, b: Integer): Integer;

(*
  Echoes a string.

  s: string to echo

  Return value: the same string.
*)
function Echo(const s: string): string;

(*
  Logs a message. No return value.

  msg: log content
*)
procedure Log(const msg: string);

(*
  Returns the configuration JSON.

  Return value: a JSON string.
*)
function GetConfig: string;

implementation

end.
```

### 7.2 Every declaration skipped or broken

```pascal
unit BadUnit;

interface

procedure Modify(var x: Integer);                 // var
procedure Fill(out y: Integer);                   // out
function  IsEven(x: Integer): Boolean;            // Boolean
function  Sum(const a: array of Integer): Integer;// array
function  Wrap<T>(x: T): Integer;                 // generic
function  Get(p: Pointer): Integer;               // Pointer
function  Now2: TDateTime;                        // TDateTime

{
  Returns the config JSON.
  Example: {"host": "localhost"}                   // contains }
}
function GetConfig: string;
// Comment lost (empty string in JSON)

(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string);
// host.Description polluted

implementation

function Helper: Integer;                          // in implementation
begin
  Result := 0;
end;

end.
```

---

## 8. Self-Check (run through this list)

```pascal
// 1. In the interface section?
// 2. Top-level (not inside a class / record / interface / function)?
// 3. No var / out parameter?
// 4. Every type in the whitelist?
// 5. Comment directly above, or above one blank line?
// 6. If { }, does the body contain }?  If yes, switch to (* ... *).
// 7. Is the return type written in the signature (`: T`)?
// 8. Does every parameter description start at the line start?
```

| # | Check | Action if failed |
|:-:|-------|------------------|
| 1 | Interface section? | Move up |
| 2 | Top-level? | Move to top-level |
| 3 | No `var` / `out`? | Use `const` + return value |
| 4 | Whitelisted types? | Use integer / float / string |
| 5 | Comment above? | Move comment above |
| 6 | No `}` inside `{ }`? | Switch to `(* ... *)` |
| 7 | Return type in signature? | Add `: T` |
| 8 | Param name at line start? | Move name to line start |

---

## 9. Minimal Template

```pascal
unit MyUnit;

interface

(*
  <One sentence describing the function.>

  a: <description of a>
  b: <description of b>

  Return value: <what is returned>.
*)
function MyFunc(a: Integer; b: string): Integer;

implementation

function MyFunc(a: Integer; b: string): Integer;
begin
  Result := 0;
end;

end.
```

**Do**:

- Use `(* ... *)` for the comment.
- Put the parameter descriptions in a block.
- Declare the return type in the signature.
- Start each parameter name at the line start.

**Don't**:

- Use `var` / `out`.
- Use `Boolean`, arrays, records, classes, pointers, `TDateTime`.
- Rely on `@return` to supply the return type.
- Put `}` inside a `{ }` comment.

---

## 10. Quick Lookup Table

| Symptom | Cause | Fix |
|---------|-------|-----|
| Declaration missing from JSON | Not top-level / not in interface | Move it |
| Declaration missing | `var` / `out` parameter | Use `const` + return |
| Declaration missing | Type not whitelisted | Switch to integer / float / string |
| Declaration missing | Missing `: T` on function | Add the return type |
| `Comment` is `""` | `{ }` comment contains `}` | Switch to `(* ... *)` |
| Return type unknown to LLM | Written only in comment | Add `: T` to the signature |
| Parameter description missing | Name not at line start | Move the name to the line start |
| Parameter description polluted | Line starts with the parameter name but is not a declaration | Rewrite the sentence or deepen the indent |
| Multi-line description truncated | Continuation lines not indented deeper | Indent them deeper than the name |
| Tool description truncated | Comment longer than 200 chars | Move critical info to the first 200 chars |

---

## 11. Design Assumptions (for reference)

1. **Top-level only.** Classes, records, interfaces, and implementation sections are ignored.
2. **Value types only.** Reference-passing (`var` / `out`) cannot be serialized.
3. **Structured comments only.** The comment must be adjacent; `{ }` must not contain `}`.
4. **Structured parameters.** Names come from the signature; descriptions come from the comment; names must be at line starts.
5. **Structured return.** Type comes from the signature; description lives in the comment.
6. **Silent skip.** Anything that violates the contract is silently dropped and noted in the `Report`.

---

## 12. Revision

- **v9.0** — Condensed from v8.0. Example-first. English throughout. Same parsing contract, less prose.
- **v8.0** — Indent-aware parameter-description state machine; line-start constraint; block-comment prefix handling.
- **v7.0** — Added data-flow diagram, `ReturnType` normalization, tool-description concatenation rules.
- **v6.0** — Added return-value comment guidance.
- **v5.0** — Added the `{ }` closing-brace trap.
- **v4.0** — Whitelist and blank-line rules.