# Pascal Declaration Writing Rules (ABI Tool Chain)

> *English translation of [pascal_code_abi_rule.md](pascal_code_abi_rule.md).*

**Purpose**: this is a **writing guide**, not a source-code commentary. Write according to this document and your declarations will be extracted and generated correctly; ignore it and your declarations will be **silently skipped** (no error, no warning, only one line of reason in the report).
**Contract**: this document is the **parsing contract**. Deviating from the contract causes declarations to be silently skipped, comments to be silently discarded, and parameter descriptions to be silently lost.

---

## 0. 30-second overview

### 0.1 What you may write

```pascal
// Top-level declarations in the interface section
function Add(a, b: Integer): Integer;
procedure Log(const msg: string);
function Echo(const s: string): string;

// Added in v10: TBytes binary payloads
procedure SendBytes(const Channel: string; const Data: TBytes);
function MakeBytes(const n: Integer): TBytes;
function EchoBytes(const Data: TBytes): TBytes;
```

### 0.2 What you may not write

```pascal
// All of these are silently skipped
procedure Modify(var x: Integer);                  // var modifier
procedure Fill(out y: Integer);                    // out modifier
procedure ProcessBytesMutable(var Data: TBytes);   // TBytes with var modifier
function  IsEven(x: Integer): Boolean;             // Boolean is not on the whitelist
function  Sum(const a: array of Integer): Integer; // non-byte dynamic array
function  Get(p: Pointer): Integer;                // Pointer is ultimately rejected
function  Wrap<T>(x: T): Integer;                  // generic
function  Now2: TDateTime;                         // TDateTime
function  GetConfig: TConfig;                      // record / class / enum / set

type
  TFoo = class
    function Bar: Integer;                          // nested inside a class
  end;

implementation
function Helper: Integer;                           // located in the implementation section
```

### 0.3 Where the content goes

| What you write | Destination |
|------------|------|
| Signature (parameter names, types, return type) | Structured JSON (`Name`, `Params[i].Name`, `Params[i].Typ`, `ReturnType`) |
| The adjacent comment | The `Comment` field; the first non-empty, non-`@` paragraph → tool description (truncated to 200 characters) |
| `name: desc` lines in the comment | `Params[i].Description` |
| `@param` / `@return` in the comment | Kept only inside `Comment`, **not** placed into structured JSON |
| `Return value: ...` in the comment | Kept only inside `Comment`, **not** placed into structured JSON |

**The AI can actually see only two things**: `Comment` (tool description + parameter descriptions) and `ReturnType`. Nothing else goes into the JSON.

---

## 1. Location

### 1.1 Rule

The declaration must be a **top-level** declaration in the **`interface` section**.

- Declarations in the `implementation` section are **not extracted**.
- Declarations nested inside a `class`, `record` or `interface` are **not extracted** (they are parsed but ultimately filtered out).
- The unit must contain the complete `unit` / `interface` / `implementation` / `end.` structure; if any of these is missing, the whole unit is treated as a parse failure.

### 1.2 Which locations are not accepted

| Location | Result | Fix |
|------|------|------|
| `implementation` section | Skipped | Move it into the `interface` section |
| Inside a `class` | Skipped | Move it to the top level |
| Inside a `record` | Skipped | Move it to the top level |
| Inside an `interface` (type) | Skipped | Move it to the top level |
| Inside a nested function/procedure | Skipped | Move it to the top level |
| Unit without `interface` / `implementation` / `end.` | The whole unit fails | Complete the structure |

### 1.3 Example

```pascal
unit MyUnit;

interface

// ✅ Extracted
function Add(a, b: Integer): Integer;
procedure Log(const msg: string);

type
  TFoo = class
    function Nested: Integer;     // ❌ Nested inside a class
  end;

  TBar = record
    procedure Nested;             // ❌ Nested inside a record
  end;

implementation

function Hidden: Integer;         // ❌ Located in the implementation section
begin
  Result := 0;
end;

end.
```

---

## 2. Parameter modifiers

### 2.1 Rule

| Modifier | Allowed? |
|--------|:----------:|
| (none) | ✅ |
| `const` | ✅ |
| `in` | ✅ |
| `var` | ❌ The whole declaration is skipped |
| `out` | ❌ The whole declaration is skipped |

**Additional note on `TBytes`**: a `TBytes` parameter may use `const` (recommended), but **must not** use `var` / `out` — pass-by-reference cannot be serialized.

### 2.2 Why `var` / `out` do not work

The ABI layer is cross-process / cross-language, and `var` / `out` write back to the caller through a reference. Across processes a "reference" means nothing — the callee modifies a copy inside its own process, which cannot be sent back to the caller.

### 2.3 How to fix it

Return the value instead of writing it back through a reference.

```pascal
// Wrong
procedure Increment(var x: Integer);
procedure AppendByte(var Data: TBytes; const b: Byte);

// Correct
function Increment(const x: Integer): Integer;
function AppendByte(const Data: TBytes; const b: Byte): TBytes;
```

### 2.4 Multiple parameters sharing a modifier

```pascal
function GroupConst(const a, b, c: Integer): Integer;
// Equivalent to three independent const parameters: a, b and c are all const + Integer
```

```pascal
procedure Swap(var a, b: Integer);
// Both parameters are var → the whole declaration is skipped
```

---

## 3. Type rules

### 3.1 Allowed types (three families)

| Category | Types |
|------|------|
| Integer | `Integer`, `Int64`, `Cardinal`, `LongInt`, `DWord`, `Word`, `SmallInt`, `Byte`, `UInt64`, `LongWord` |
| Float | `Double`, `Single`, `Extended`, `Real` |
| String | `string`, `AnsiString`, `UnicodeString`, `PChar`, `PAnsiChar`, `PWideChar`, `TP_String`, `TPascalString`, `TUPascalString`, `U_String` |
| **Binary** (added in v10) | **`TBytes`**, **`array of Byte`** (the two are equivalent) |

### 3.2 Cross-language mapping table

How the Pascal type you write ends up in the JSON description, the Pascal ABI code and the C++ ABI code:

| Type you write | JSON description | Generated Pascal ABI | Generated C++ ABI |
|------------|:---------:|:-----------------:|:--------------:|
| `Integer` | `int64` | `Integer` | `std::int32_t` |
| `Int64` | `int64` | `Int64` | `std::int64_t` |
| `Cardinal` | `int64` | `Cardinal` | `std::uint32_t` |
| `LongInt` | `int64` | `LongInt` | `std::int32_t` |
| `DWord` | `int64` | `DWord` | `std::uint32_t` |
| `Word` | `int64` | `Word` | `std::uint16_t` |
| `SmallInt` | `int64` | `SmallInt` | `std::int16_t` |
| `Byte` | `int64` | `Byte` | `std::uint8_t` |
| `UInt64` | `int64` | `UInt64` | `std::uint64_t` |
| `LongWord` | `int64` | `LongWord` | `std::uint32_t` |
| `Single` | `double` | `Single` | `float` |
| `Double` | `double` | `Double` | `double` |
| `Extended` | `double` | `Extended` | `double` (precision loss) |
| `Real` | `double` | `Real` | `double` (precision loss) |
| String family (all) | `string` | `string` | `std::string` |
| **`TBytes` / `array of Byte`** | **`TBytes`** | **Binary payload** (handled automatically by the tool chain) | **`std::vector<std::uint8_t>`** |

### 3.3 Forbidden types and reasons

Any one of these causes **the whole declaration to be skipped**.

| Category | Example | Why not | Alternative |
|------|------|------------|------|
| Boolean | `Boolean`, `WordBool`, `LongBool` | Boolean representation differs across languages | `Integer` (0/1) or `Byte` |
| Variant | `Variant`, `OleVariant` | Cannot be serialized | Split into concrete types |
| Non-byte dynamic arrays | `array of Integer`, `array of string` | Only byte sequences are supported | Serialize into `TBytes` |
| Static arrays | `array[0..N] of X` | Cannot be serialized | Use `TBytes` |
| Records | `TPoint`, `TRect`, custom `record` | Cross-language structure differs | Split into several scalar parameters, or use `TBytes` |
| Classes | `TObject`, `TStringList` | Cannot be serialized | Split into several scalar parameters |
| Interfaces | `IInterface` | Cannot be serialized | Split into several scalar parameters |
| Enums | `TColor` | Cross-language enum representation differs | `Integer` |
| Sets | `set of X` | Cannot be serialized | `Integer` bit mask |
| Generics | `TList<X>`, `TGenericList<X>` | Cannot be serialized | Split into several scalar parameters |
| Date/time | `TDateTime`, `TDate`, `TTime` | Cross-language time representation differs | `Int64` (Unix timestamp) or `string` (ISO 8601) |
| Pointers | `Pointer`, `PInteger`, `PByte` | An address has no cross-process meaning | `Int64` (carrying the address) or `TBytes` |
| Events | `TNotifyEvent` | Cannot be serialized | Split into scalar callback parameters |
| Anonymous methods | `reference to procedure` | Cannot be serialized | Split into scalar callback parameters |

### 3.4 Pointers: why not, and what to use instead

`Pointer` is **rejected at the final generation stage**. The declaration can be parsed, but the whole declaration is dropped when ABI code is generated.

**Reason**: a pointer is an in-process address; it has no meaning across processes or languages.

**Alternatives**:

```pascal
// Wrong — eventually skipped
function ReadAddr(const p: Pointer): Int64;

// Correct — carry the address in an Int64
function ReadAddr(const addr: Int64): Int64;

// Preferred — carry binary data in TBytes
function ReadBuffer: TBytes;
```

### 3.5 Common pitfalls

**Pitfall 1: `Integer` is 32-bit on the C++ side**

```pascal
function GetCount: Integer;
// On the C++ side this is std::int32_t, not 64-bit!
```

**If you need a 64-bit integer, use `Int64`.**

**Pitfall 2: `Extended` / `Real` degrade to `double` on the C++ side**

```pascal
function Compute(x: Extended): Extended;
// The C++ side is double, with precision loss
```

**If you need high precision, use `Double` or accept the degradation.**

**Pitfall 3: the JSON description writes `int64` for every integer type, but the actual ABI code is not necessarily 64-bit**

The JSON description uniformly expresses integer types as `int64` as a semantic label for the AI; the actual generated ABI code maps according to the table above. **If you need strict 64-bit, write `Int64`**.

---

## 4. Comments

### 4.1 Binding rules

| Situation | Bound? |
|------|:----------:|
| The comment sits immediately above the declaration | ✅ |
| Comment → one or more blank lines → declaration | ✅ |
| Comment 1 → Comment 2 → declaration | ✅ (both are bound, joined with newlines) |
| Declaration → trailing comment on the same line | ❌ |
| Comment → other non-whitespace token → declaration | ❌ (interrupted) |

```pascal
// Wrong — a trailing comment is ignored
function Foo: Integer; // this text is lost

// Correct — a preceding comment is bound
// this text is captured
function Bar: Integer;

// Correct — multiple blank lines may sit between comment and declaration
(* this text is captured *)


function Baz: Integer;
```

### 4.2 Comment styles — ordered by safety

1. **`(* ... *)`** — safest. The `*)` sequence rarely appears in body text, so conflicts are unlikely.
2. **`// ...`** — ends at the end of the line, unaffected by braces.
3. **`{ ... }`** — use only when the body text contains no `}`.

### 4.3 The `}` trap

If the body of a `{ ... }` comment contains `}`, the comment is truncated **at the first `}`**. **The comment is lost or incomplete**.

```pascal
// Wrong — Comment is truncated right after "host":
{
  Returns the configuration JSON.
  Example: {"host": "localhost", "port": 8080}
}
function GetConfig: string;
```

```pascal
// Fixed
(*
  Returns the configuration JSON.
  Example: {"host": "localhost", "port": 8080}
*)
function GetConfig: string;
```

| Comment body contains | Result |
|--------------|------|
| `}` inside `{ ... }` | Comment truncated |
| Full-width `｝` inside `{ ... }` | OK |
| `}` inside `(* ... *)` | OK |
| `*)` inside `(* ... *)` | Comment truncated |

### 4.4 Tool-description extraction rules

The tool chain merges the comment into a **single-line tool description**, according to these rules:

1. Split by newline.
2. Skip blank lines.
3. Skip lines starting with `@` (Doxygen tags).
4. Strip leading `*` continuation markers (at most twice).
5. **Take only the first non-empty, non-`@` paragraph**.
6. Truncate to **200 characters**.

```pascal
(*
  Computes the sum of two integers.

  a: the first addend
  b: the second addend

  @return the sum of the two numbers          <- skipped (@ line)

  Return value: the sum of a and b.
*)
function Add(a, b: Integer): Integer;
```

Result: `Computes the sum of two integers.`

**⚠️ Only the first paragraph is taken** — later parameter descriptions and the `Return value` line do not enter the tool description, but **they do enter parameter-description extraction** (see chapter 5).

**Writing advice**: put the core information in the first paragraph and keep it within 200 characters.

### 4.5 Merging multiple comments

```pascal
(* first line *)

(* second line *)
function F: Integer;
```

Both comments are bound and joined with a newline into `first line\nsecond line` as the `Comment`.

---

## 5. Parameter descriptions

### 5.1 Start-of-line rule

A **parameter name must be at the start of the line** (or directly after a Doxygen tag) to be recognized as a parameter-description line.

```pascal
(*
  host: host name                  <- ✅ recognized as the description of host
  port: port number                <- ✅ recognized as the description of port

  This configuration controls host and port.   <- the line does not start with a parameter name, so it is not absorbed
*)
function Connect(host: string; port: Integer);
```

### 5.2 Supported forms

```pascal
// Form A: name + colon
(*
  a: the first addend
  b: the second addend
*)

// Form B: name + equals sign
(*
  a = the first addend
  b = the second addend
*)

// Form C: Doxygen @param
(*
  @param a the first addend
  @param b the second addend
*)

// Form D: name + whitespace
(*
  a  the first addend
  b  the second addend
*)

// Form E: Doxygen immediate
(*
  @a the first addend
  @b the second addend
*)
```

### 5.3 Case sensitivity

Parameter-name matching is **case-insensitive**.

```pascal
(*
  SOURCE: source text
*)
function F(Source: string);
// Source.Description = "source text"
```

### 5.4 Multi-line descriptions

A continuation line must be indented **deeper** than the parameter name (strictly greater).

```pascal
(*
  Generates code.

  target: target language, choose one:
            pascal_service   generate the Pascal service side
            pascal_call      generate the Pascal client
            python_service   generate the Python service side
          <unit> is the normalized UnitName.

  Return value: the generated code.
*)
function Generate(target: string): string;
```

`target.Description` =
```
target language, choose one:
            pascal_service   generate the Pascal service side
            pascal_call      generate the Pascal client
            python_service   generate the Python service side
          <unit> is the normalized UnitName.
```

**⚠️ Strictly greater**: when a continuation line has the same indentation as the declaration line, it is **not** accumulated.

```pascal
(*
  target: description
  continuation line         <- same indentation, not accumulated
*)
```

```pascal
(*
  target: description
    continuation line       <- deeper indentation, accumulated
*)
```

### 5.5 Common misjudgments and fixes

**Misjudgment 1: a natural-language sentence happens to start with a parameter name**

```pascal
// Problem — "host can also be an IP address." is absorbed into the description of host
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string);
```

**Fixes**:

```pascal
// Fix 1: wrap in backticks
(*
  host: host name

  `host` can also be an IP address.
*)

// Fix 2: increase the indentation (turn it into a continuation line)
(*
  host: host name
        can also be an IP address.
*)

// Fix 3: reword the sentence
(*
  host: host name

  This parameter can also be an IP address.
*)
```

**Misjudgment 2: the parameter name appears mid-line**

It is not absorbed, so it is safe.

```pascal
(*
  host: host name
  port: port number

  This configuration controls the host and port the service uses.   <- safe, the line does not start with a parameter name
*)
```

---

## 6. Return values

### 6.1 Must be written in the signature

**The return type must be declared in the signature**. Writing it only in comments loses it.

```pascal
// Wrong — the signature has no return type, parse fails
(*
  @return the sum of the two numbers
*)
function Add(a, b: Integer);

// Correct
(*
  Return value: the sum of a and b.
*)
function Add(a, b: Integer): Integer;
```

### 6.2 Type normalization

| Signature type | JSON description | Generated Pascal ABI | Generated C++ ABI |
|----------|:---------:|:-----------------:|:--------------:|
| Any integer | `int64` | Original type | Mapped by type width |
| Any float | `double` | Original type | `float` / `double` |
| Any string | `string` | `string` | `std::string` |
| **`TBytes`** | **`TBytes`** | **Binary payload** | **`std::vector<std::uint8_t>`** |

### 6.3 `procedure` must not have a return value

`procedure` has no return value. Do not write a `Return value` line, and do not write `@return`.

```pascal
// Correct
(*
  Records a log entry.

  msg: log content
*)
procedure Log(const msg: string);

// Wrong — @return is ignored
(*
  @return nothing
*)
procedure Log2(const msg: string);
```

### 6.4 Recommended comment structure

```pascal
(*
  Computes the sum of two integers.

  a: the first addend
  b: the second addend

  Return value: the sum of a and b, of type Integer.
*)
function Add(a, b: Integer): Integer;
```

| Line | Purpose | Enters structured JSON? |
|----|------|:-----------------:|
| `: Integer` | Structured return type | ✅ |
| `Return value: ...` | Human / LLM-readable semantics | ❌ — comment only |

---

## 7. `TBytes` binary payloads (added in v10)

### 7.1 When to use `TBytes`

| Scenario | Recommended type |
|------|---------|
| Text data (JSON, XML, logs) | `string` |
| Binary data (images, archives, serialized data) | `TBytes` |
| Encrypted data | `TBytes` |
| Byte sequences of arbitrary length | `TBytes` |

**Principle**: if the semantics of the data is "a byte sequence", use `TBytes`; if it is "text", use `string`.

### 7.2 Allowed forms

```pascal
// Parameter
procedure SendBytes(const Data: TBytes);
procedure SendBytesArray(const Data: array of Byte);   // equivalent to TBytes

// Return value
function MakeBytes(const n: Integer): TBytes;
function MakeBytesArray: array of Byte;                // equivalent to TBytes

// Mixed
function TransformBytes(const Data: TBytes): TBytes;
function HashBytes(const Data: TBytes): string;
function CombineBytes(const Prefix: TBytes; Suffix: Byte): TBytes;
```

`TBytes` and `array of Byte` are **completely equivalent** in the tool chain — they are normalized to the same type. Writing `TBytes` is recommended (it is clearer).

### 7.3 Forbidden forms

```pascal
// ❌ TBytes with var / out modifiers
procedure ProcessBytesMutable(var Data: TBytes);
procedure FillBytes(out Data: TBytes);

// ❌ Non-byte dynamic arrays
function Sum(const a: array of Integer): Integer;
function Join(const a: array of string): string;
function Points(const a: array of TPoint): Integer;

// ❌ Static arrays
function ReadAll(const a: array[0..255] of Byte): Integer;

// ❌ Pointer
function ReadRaw(const p: Pointer): TBytes;
```

### 7.4 Memory management (from the user's perspective)

- **As a parameter** (`const Data: TBytes`): **passed by value**. The callee receives a copy of the data and may use it freely without affecting the caller.
- **As a return value** (`function F: TBytes`): **owned by the caller**. The callee returns a `TBytes`; the caller receives an ordinary `TBytes` whose reference count is managed automatically.
- **Cross-process transport**: the tool chain performs serialization/deserialization automatically; **the user does not need to care**.

### 7.5 Complete example

```pascal
(*
  Sends a byte sequence to the specified channel.

  Channel: channel name
  Data:    the byte sequence to send
*)
procedure SendBytes(const Channel: string; const Data: TBytes);

(*
  Generates a byte sequence of the specified length.

  n: length

  Return value: a TBytes of length n.
*)
function MakeBytes(const n: Integer): TBytes;

(*
  Echoes a byte sequence.

  Data: input sequence

  Return value: a sequence identical to the input.
*)
function EchoBytes(const Data: TBytes): TBytes;

(*
  Computes the hash of a byte sequence.

  Data: input sequence

  Return value: the hash as a hexadecimal string.
*)
function HashBytes(const Data: TBytes): string;

(*
  Appends one byte sequence after another byte sequence.

  Prefix: prefix
  Suffix: single-byte suffix

  Return value: the concatenated TBytes.
*)
function CombineBytes(const Prefix: TBytes; Suffix: Byte): TBytes;
```

---

## 8. Complete examples

### 8.1 Everything accepted

```pascal
unit SampleUnit;

interface

(*
  Computes the sum of two integers.

  a: the first addend
  b: the second addend

  Return value: the sum of a and b.
*)
function Add(a, b: Integer): Integer;

(*
  Computes the product of two integers.

  @param a the first multiplier
  @param b the second multiplier

  Return value: the product of a and b.
*)
function Mul(a, b: Integer): Integer;

(*
  Echoes a string.

  s: the string to echo

  Return value: returns the input unchanged.
*)
function Echo(const s: string): string;

(*
  Records a log entry; no return value.

  msg: log content
*)
procedure Log(const msg: string);

(*
  Returns the configuration JSON.

  Return value: a JSON string.
*)
function GetConfig: string;

(* -- Added in v10: TBytes binary payloads -- *)

(*
  Sends a byte sequence to the specified channel.

  Channel: channel name
  Data:    the byte sequence to send
*)
procedure SendBytes(const Channel: string; const Data: TBytes);

(*
  Generates a byte sequence of the specified length.

  n: length

  Return value: a TBytes of length n.
*)
function MakeBytes(const n: Integer): TBytes;

(*
  Echoes a byte sequence.

  Data: input sequence

  Return value: a sequence identical to the input.
*)
function EchoBytes(const Data: TBytes): TBytes;

(*
  Computes the hash of a byte sequence.

  Data: input sequence

  Return value: the hash as a hexadecimal string.
*)
function HashBytes(const Data: TBytes): string;

(*
  Appends one byte sequence after another byte sequence.

  Prefix: prefix
  Suffix: single-byte suffix

  Return value: the concatenated TBytes.
*)
function CombineBytes(const Prefix: TBytes; Suffix: Byte): TBytes;

implementation

end.
```

### 8.2 Everything skipped or broken

```pascal
unit BadUnit;

interface

procedure Modify(var x: Integer);                  // var
procedure Fill(out y: Integer);                    // out
function  IsEven(x: Integer): Boolean;             // Boolean
function  Sum(const a: array of Integer): Integer; // non-byte array
function  Wrap<T>(x: T): Integer;                  // generic
function  Get(p: Pointer): Integer;                // Pointer
function  Now2: TDateTime;                         // TDateTime
procedure ProcessBytesMutable(var Data: TBytes);   // TBytes with var

{
  Returns the configuration JSON.
  Example: {"host": "localhost"}                   // contains }, so Comment is truncated
}
function GetConfig: string;

(*
  host: host name

  host can also be an IP address.                  // host.Description is polluted
*)
function Connect(host: string);

implementation

function Helper: Integer;                          // located in implementation
begin
  Result := 0;
end;

end.
```

---

## 9. Self-check list

```pascal
// 1. Is it in the interface section?
// 2. Is it top-level (not inside class / record / interface / function)?
// 3. No var / out parameters? (TBytes counts too)
// 4. Is every type on the whitelist? (including TBytes / array of Byte)
// 5. Is the comment directly above the declaration, or separated only by blank lines?
// 6. If using { }, does the body contain }? If so, switch to (* ... *).
// 7. Does a function have a : T return type? Does a procedure have no : ?
// 8. Does every parameter description start at the beginning of a line?
// 9. Are continuation lines of multi-line descriptions indented deeper?
// 10. Does the first comment paragraph carry the core information within the first 200 characters?
```

| # | Check | What to do if it fails |
|:-:|--------|----------------|
| 1 | In the interface section? | Move it up |
| 2 | Top-level? | Move it to the top level |
| 3 | No `var` / `out`? | Use `const` + a return value |
| 4 | Type on the whitelist? | Switch to integer / float / string / `TBytes` |
| 5 | Comment above? | Move the comment above |
| 6 | No `}` inside `{ }`? | Switch to `(* ... *)` |
| 7 | `function` has `: T`? | Add the return type |
| 8 | Parameter name at the start of the line? | Move the name to the start of the line |
| 9 | Continuation lines indented deeper? | Increase the indentation |
| 10 | First paragraph short? | Trim the first paragraph |

---

## 10. Minimal templates

### 10.1 Scalar signature template

```pascal
unit MyUnit;

interface

(*
  <one sentence describing what the function does.>

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

### 10.2 `TBytes` signature template

```pascal
unit MyBytesUnit;

interface

(*
  <one sentence describing what the function does.>

  Data: <description of the input byte sequence>

  Return value: <description of the returned byte sequence>.
*)
function TransformBytes(const Data: TBytes): TBytes;

implementation

function TransformBytes(const Data: TBytes): TBytes;
begin
  // Example: return the input unchanged
  Result := Data;
end;

end.
```

**Should do**:

- Write comments with `(* ... *)`.
- Put parameter descriptions in one block, **with each parameter name starting at the beginning of a line**.
- Write the return type in the signature (`function F: Integer` / `function F: TBytes`).
- Indent continuation lines deeper than the parameter names.
- Use `TBytes` to carry binary payloads.
- Write `Int64` when you need a 64-bit integer, not `Integer`.

**Should not do**:

- Use `var` / `out` (including `var Data: TBytes`).
- Use `Boolean`, non-byte dynamic arrays, records, classes, pointers, `TDateTime`.
- Rely on `@return` to provide the return type.
- Write `}` inside a `{ }` comment.
- Treat `TBytes` as `array of Integer` — only byte arrays are supported.
- Declare functions that need to be exported in the `implementation` section.

---

## 11. Quick lookup table

| Symptom | Cause | Fix |
|------|------|----------|
| Declaration disappears from the JSON | Not top-level / not in the interface section | Move it |
| Declaration disappears from the JSON | `var` / `out` parameter | Use `const` + a return value |
| Declaration disappears from the JSON | Type not on the whitelist | Switch to integer / float / string / `TBytes` |
| Declaration disappears from the JSON | `function` missing `: T` | Add the return type |
| Declaration disappears from the JSON | Generic / enum / record / class / pointer / `TDateTime` | Switch to a whitelisted type |
| Declaration disappears from the JSON | `var` on `TBytes` | Change to `const Data: TBytes` and return a new `TBytes` |
| Declaration disappears from the JSON | Function in the `implementation` section | Move it to the `interface` section |
| Declaration disappears from the JSON | Nested inside class / record / interface | Move it to the top level |
| `Comment` truncated | `}` inside a `{ }` comment | Switch to `(* ... *)` |
| `Comment` empty | A non-whitespace token sits between comment and declaration | Remove the intervening token |
| Tool description empty | The comment has only `@param` / `@return` lines | Add a free-text paragraph |
| Tool description truncated | The first paragraph exceeds 200 characters | Trim the first paragraph |
| LLM does not know the return type | It is written only in the comment | Add `: T` to the signature |
| Parameter description missing | The name is not at the start of the line | Move the name to the start of the line |
| Parameter description polluted | A natural-language sentence happens to start with the parameter name | Reword the sentence / wrap in backticks / increase indentation |
| Multi-line description truncated | Continuation lines are not indented deeper than the parameter name | Increase the continuation indentation |
| **`TBytes` parameter skipped** | **Misused `array of Integer` / `array of string`** | **Change to `TBytes` or `array of Byte`** |
| **`TBytes` return skipped** | **The signature says `array of Integer` etc.** | **Change to `function F: TBytes`** |
| **`Pointer` parameter skipped** | **`Pointer` is not on the final generation whitelist** | **Use `Int64` to carry the address, or use `TBytes`** |
| **`Integer` is 32-bit on the C++ side** | **The C++ generator maps by 32-bit width** | **If you need 64-bit, use `Int64`** |
| **`Extended` / `Real` precision loss** | **Degraded to `double` on the C++ side** | **Use `Double`, or accept the precision loss** |
| A duplicate-named function is renamed automatically | The tool chain de-duplicates automatically | Normal behavior (`Foo` → `Foo1`) |
| Source position is lost after a JSON round trip | Serialization does not include position information | Normal behavior |

---

## 12. Design principles

These rules are not arbitrary; they rest on clear semantic constraints:

1. **Top-level only.** The ABI tool chain cares only about the unit's public interface. Declarations inside a class / record / interface are internal implementation, and the implementation section is unit-private — neither has any cross-language export meaning.

2. **Value types only.** Cross-process / cross-language communication can only pass values. `var` / `out` rely on in-process references, which mean nothing across processes.

3. **Serializable types only.** The ABI layer must serialize data between languages. Only integers, floats, strings and byte sequences can be serialized. Other types (boolean, enum, record, class, pointer, time) have inconsistent representations across languages, so correct transport cannot be guaranteed.

4. **`TBytes` is a first-class citizen for byte sequences.** Cross-language binary payloads are uniformly expressed as byte sequences. `array of Byte` is equivalent to `TBytes`; other dynamic arrays are not supported, because the cross-language representation of the element type cannot be guaranteed to be consistent.

5. **Structured comments.** Comments are the only way an AI can understand a declaration. The rules (start-of-line, indentation, the `}` trap) exist so that comments can be parsed reliably, not to make life hard for the user.

6. **Return types come from the signature.** Signatures are structured, comments are unstructured. Structured information wins — the return type must be in the signature, and comments only provide a human-readable description.

7. **Silent skipping.** The tool chain's design philosophy is "parse what can be parsed, skip what cannot" — one invalid declaration does not fail the whole unit. But that also means errors are easy to overlook, which is why this document spells out the rules.

8. **The first paragraph is the tool description.** The tool description an AI receives is a single line of at most 200 characters. Putting the core information in the first paragraph is a courtesy to the AI reader.

---

## 13. Revision history

- **v10.0** — Rebuilt from the behavior of the ABI generators. Added whitelist support for `TBytes` / `array of Byte`. Added the complete cross-language type mapping table. Clarified that `Pointer` is ultimately rejected, that `Integer` is 32-bit on the C++ side, and that `Extended`/`Real` degrade to `double` on the C++ side. Added the parameter/return-value semantics and memory-management notes for `TBytes`. Clarified that the tool description takes only the first paragraph. Fully rewritten in Chinese, aimed at writers rather than source-code readers.
- **v9.0** — Condensed version. Examples first.
- **v8.0** — Added indentation-aware parameter-description rules.
- **v7.0** — Added return-type normalization and tool-description assembly rules.
- **v6.0** — Added guidance on return-value comments.
- **v5.0** — Added the `{ }` closing-brace trap.
- **v4.0** — Whitelist and blank-line rules.

**This document is the writing contract. Write according to it and declarations will be correctly extracted, normalized and generated; ignore it and declarations will be silently skipped.**
