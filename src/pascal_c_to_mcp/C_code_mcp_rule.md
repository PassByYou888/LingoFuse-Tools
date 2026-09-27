# C Declaration Rules (for the Z.Pascal_Func_Tool Toolchain)

**Version**: 2.0
**Last updated**: 2026-09-20
**Applies to**: `Fill_C` → `Translate_C_Typ_To_Pascal` → `Z.Pascal_Func_Model` → `pas_mcp_generator_tool` full pipeline
**Status**: This document IS the C parsing contract. Any deviation causes declarations to be **silently skipped** or information to be **silently lost**.

---

> ## **Why you must write detailed comments**
>
> **The more thoroughly you describe a function — its purpose, every parameter, and its return value — the more accurately an AI agent will call it.**
>
> The agent never reads your C header. It reads only the `description` string in the tool's JSON schema, which is assembled from your adjacent comment. Short or vague comments produce vague descriptions, and a vague description means the agent will stall, call the wrong tool, or pass wrong arguments.
>
> **One clear sentence per parameter is worth ten lines of C you never write.**
>
> See §5.6 for exactly how your comment is assembled into the tool description, and §5.5 for how parameter descriptions survive the C→Pascal conversion.

---

## Revision summary

| ID | Change | Section |
|:--:|--------|---------|
| V2-1 | **Major**: `Pointer` is rejected downstream — C-side acceptance does not mean Pascal-side acceptance | §3.2, §3.3 |
| V2-2 | **Major**: return types are further normalized in `Z.Pascal_Func_Model` | §3.5 |
| V2-3 | **Major**: the C→Pascal conversion product carries a ` * ` prefix on every line after the first; the Model layer strips it | §5.5 |
| V2-4 | **Major**: `@param` / `@return` lines are skipped during tool-description assembly | §5.6 |
| V2-5 | **New**: human-misreading scenarios | §11 |
| V2-6 | **Fix**: Mermaid rendering (English subgraph IDs) | global |
| V2-7 | **Fix**: forbidden types add the "why `void *` is rejected anyway" note | §3.3 |
| V2-8 | **Fix**: multidimensional arrays — root cause | §4.4 |
| V2-9 | **Fix**: positive example outputs clarified at the JSON layer | §7.1 |
| V2-10 | **Fix**: minimum template explicitly uses Doxygen `/** */` | §10 |
| V2-11 | **New**: alignment with the Pascal rule v8.0 | §12 |
| V2-12 | **Fix**: full-width punctuation replaced | global |
| V2-13 | **Fix**: multi-line comment normalization interacts with the Model-layer strip | §5.3 |

---

## 0. Thirty-second overview

**Five iron rules**:

| # | Rule | Detail |
|:-:|------|--------|
| 1 | **Form** | Top-level function prototype ending with `;` |
| 2 | **Location** | Not inside `{ ... }` bodies, not inside type definitions |
| 3 | **Parameters** | No function pointers (`(*name)(...)`) |
| 4 | **Types** | All types must be in the C whitelist **AND** their Pascal-mapped types must be in the Pascal whitelist |
| 5 | **Comment** | Adjacent above (blank lines allowed) |

**One violation = the entire declaration is skipped**, not partially ignored.

> **Difference from v1.0**: v1.0's rule 4 only mentioned the C whitelist. v2.0 adds the cross-layer constraint — `void *` maps to `Pointer` on the C side, but `Pointer` is **not** in the Pascal whitelist, so it is still rejected by `Z.Pascal_Func_Model`. See §3.3.

**And always remember**: the agent only sees your comment. **Write it as if the reader has never seen your code, because that reader is an AI.**

---

## 1. Where declarations must live

### 1.1 Extracted vs skipped

| Location | Result | Example |
|----------|:------:|---------|
| Top-level function prototype | **Extracted** | `int add(int a, int b);` |
| Inside `extern "C" { ... }` | **Extracted** (transparent block) | `extern "C" { int foo(void); }` |
| Preprocessor directives | Skipped | `#include <stdio.h>` |
| `struct` / `enum` / `union` / `typedef` blocks | Skipped | `struct Point { int x; };` |
| Global variable | Skipped | `int global_var;` |
| Initialized variable | Skipped | `int x = 42;` |
| Function definition with `{ ... }` | Skipped | `int f() { return 1; }` |
| Prototype with a function-pointer parameter | Skipped | `void set_cb(void (*cb)(int));` |

### 1.2 Position examples

```c
/* test.h - position example */
#ifndef TEST_H
#define TEST_H

#include <stdio.h>              /* SKIP: preprocessor */
#define MAX_SIZE 1024           /* SKIP: preprocessor */

/* EXTRACT: top-level function prototype */
int add(int a, int b);

/* SKIP: function definition with body */
int sub(int a, int b) {
    return a - b;
}

/* SKIP: struct definition */
struct Point {
    int x;
    int y;
};

/* SKIP: global variable */
int global_counter;

/* SKIP: initialized variable */
int initialized = 42;

/* EXTRACT: prototype inside extern "C" block */
extern "C" {
    int mul(int a, int b);
}

#endif /* TEST_H */
```

---

## 2. Parameter modifiers

### 2.1 Whitelist

| Modifier | Allowed | Handling |
|----------|:-------:|----------|
| (none) | Yes | Default value passing |
| `const` | Yes | **Kept**; moved in front of the type |
| `restrict` / `__restrict` / `__restrict__` | Yes | **Silently stripped**; base type kept |
| `volatile` | Yes | Filtered out of return types; kept in parameter type text |
| `var` (Pascal-only) | **No** | **Whole declaration skipped** |
| `out` (Pascal-only) | **No** | **Whole declaration skipped** |

### 2.2 Three ways to write `const` — all recognised

```c
int foo(const char * s);   /* prefix form      → param_mod = "const" */
int foo(char const * s);   /* suffix form      → param_mod = "const" */
int bar(int * const p);    /* pointer-post     → param_mod = "const" */
```

All three result in `param_mod = "const"`.

### 2.3 `restrict` is stripped

`restrict` is a compiler optimization hint and does not change prototype semantics. Passing it through would pollute the type string and break downstream mapping.

```c
/* Input */
int memcpy_opt(void * restrict dst, const void * restrict src, size_t n);

/* Type after stripping */
/*   dst: void *   src: const void *   n: UInt64 */
```

> **Caution**: `void *` → `Pointer` is still rejected on the Pascal side (see §3.3).

### 2.4 Why `var` / `out` are forbidden

`var` / `out` are Pascal reference-passing syntax. They do not exist in C. The toolchain checks for them defensively and skips the entire declaration if found.

**Fix**: use `const` plus a return value.

```c
/* WRONG (Pascal-only syntax, will be skipped if present) */
void modify(var int x);

/* RIGHT */
int modify(int x);
```

---

## 3. Type whitelist

### 3.1 Allowed C types

| Family | Types |
|--------|-------|
| Signed integers | `signed char`, `short`, `int`, `long`, `long long`, `int8_t`, `int16_t`, `int32_t`, `int64_t` |
| Unsigned integers | `unsigned char`, `unsigned short`, `unsigned int`, `unsigned long`, `unsigned long long`, `uint8_t`, `uint16_t`, `uint32_t`, `uint64_t` |
| Pointer-width integers | `size_t`, `uintptr_t`, `ssize_t`, `ptrdiff_t`, `intptr_t` |
| Floating point | `float`, `double`, `long double` |
| Strings | `char *`, `const char *`, `char const *` |
| Void | `void` (return type only) |

### 3.2 C → Pascal → JSON mapping

| C type | Pascal (tnf_Json) | Pascal (tnf_ABI) | JSON Schema | Cross-layer |
|--------|:-----------------:|:----------------:|:-----------:|:-----------:|
| `signed char` / `int8_t` | `int64` | `shortint` | `integer` | OK |
| `short` / `int16_t` | `int64` | `smallint` | `integer` | OK |
| `int` / `int32_t` | `int64` | `integer` | `integer` | OK |
| `long` | `int64` | `longint` | `integer` | OK |
| `long long` / `int64_t` | `int64` | `int64` | `integer` | OK |
| `unsigned char` / `uint8_t` | `int64` | `byte` | `integer` | OK |
| `unsigned short` / `uint16_t` | `int64` | `word` | `integer` | OK |
| `unsigned int` / `uint32_t` | `int64` | `cardinal` | `integer` | OK |
| `unsigned long` | `int64` | `longword` | `integer` | OK |
| `unsigned long long` / `uint64_t` | `int64` | `uint64` | `integer` | OK |
| `size_t` / `uintptr_t` | `int64` | `uint64` | `integer` | OK |
| `ssize_t` / `ptrdiff_t` / `intptr_t` | `int64` | `int64` | `integer` | OK |
| `float` | `double` | `single` | `number` | OK |
| `double` | `double` | `double` | `number` | OK |
| `long double` | `double` | `extended` | `number` | OK |
| `char *` / `const char *` / `char const *` | `string` | `string` | `string` | OK |
| **Any other `T *` (including `void *`)** | **(maps to `Pointer`)** | **(maps to `Pointer`)** | — | **REJECTED** |
| `void` (return) | downgraded to procedure | downgraded to procedure | — | OK |

> **v2.0 key point**: any pointer (`void *`, `int *`, `const void *`, ...) is mapped to `Pointer` during C→Pascal translation, but **`Pointer` is not in the Pascal whitelist** (see §3.3). A declaration with a pointer parameter is **eventually skipped by `Z.Pascal_Func_Model`**.

### 3.3 Forbidden types (whole declaration skipped)

| Category | Examples |
|----------|----------|
| Custom structs | `struct Point`, `Point` |
| Unions | `union Value` |
| Enums | `enum Color`, `Color` |
| Booleans | `bool`, `_Bool` |
| Wide chars | `wchar_t`, `char16_t`, `char32_t` |
| Custom typedefs | Any unmapped alias |
| Variadic | `...` |
| Function pointer parameters | `void (*cb)(int)` |
| **Any pointer** | **`void *`, `int *`, `const void *`** |

> **v2.0 key point: why `void *` is rejected anyway**
>
> 1. **C side (`Fill_C`) accepts** `void *` as a parameter type.
> 2. **`Translate_C_Typ_To_Pascal` maps** `void *` → `Pointer`.
> 3. **`Z.Pascal_Func_Model.LoadFromParser` sees `Pointer`** which is **not in the Pascal whitelist**, and skips the entire declaration.
>
> **Conclusion**: `void *` parameters are eventually rejected — just further downstream. **C-side acceptance does not imply Pascal-side acceptance.** If you must pass an address, use `uint64_t` / `int64_t`.

### 3.4 Boundary examples

```c
/* PASS */
int add(int a, int b);
unsigned int get_unsigned(void);
long long get_longlong(void);
float get_float(void);
double get_double(void);
const char * get_error_message(int code);
int arr_param(int buf[], int len);

/* SKIP: Boolean */
_Bool is_even(int x);

/* SKIP: struct parameter */
double distance(struct Point p1, struct Point p2);

/* SKIP: enum parameter */
int set_color(enum Color c);

/* SKIP: wide char */
int print_wide(wchar_t * s);

/* SKIP: function pointer */
void set_callback(void (*cb)(int));

/* SKIP: variadic */
int printf_like(const char * fmt, ...);

/* SKIP: union parameter */
void set_value(union Value v);

/* SKIP: pointer parameters */
void * void_ptr_return(int size);
void restrict_param(void * p);
void int_ptr_param(int * p);
```

### 3.5 Return type normalization (two stages)

| Stage | Location | Input | Output |
|:-----:|----------|-------|--------|
| Stage 1 | `Translate_C_Typ_To_Pascal` | C type (e.g. `unsigned int`) | Pascal type (e.g. `Cardinal`) |
| Stage 2 | `Z.Pascal_Func_Model.Do_Normalize_Type` | Pascal type | Normalized (`int64` / `double` / `string`) |

**Example**:

```c
unsigned int get_unsigned(void);
```

| Stage | Result |
|:-----:|--------|
| `Fill_C` | `ResultDecl = "unsigned int"` |
| `Translate_C_Typ_To_Pascal` | `ResultDecl = "Cardinal"` |
| `LoadFromParser` (tnf_Json) | `ReturnType = "int64"` |
| `LoadFromParser` (tnf_ABI) | `ReturnType = "cardinal"` |

**Consequences for the user**:

- The JSON never shows the original C type — only `int64` / `double` / `string`.
- If you need the original type, read it from `Comment` or the source.
- The toolchain assumes the caller does not distinguish `unsigned int` from `int` — everything is sent as a 64-bit integer.

---

## 4. Array suffix rules

### 4.1 Recognition

```
void fill_buffer(int buf[], int len)
    ↓
param_name  = "buf"
param_typ   = "int"
param_array = "[]"
```

### 4.2 Supported forms

| Input | `param_array` |
|-------|:-------------:|
| `int buf[]` | `[]` |
| `int buf[10]` | `[10]` |
| `int buf[N]` | `[N]` |
| `int buf` | `''` (no suffix) |

### 4.3 Downstream output comparison

```c
void fill_buffer(int buf[], int len);
```

- `decl_to_c` output: `void fill_buffer(int buf[], int len);`
- `decl_to_pascal` output: `procedure fill_buffer(buf: array of Integer; len: Integer);`

> **Caution**: `array of Integer` is **rejected by the Model layer** (arrays are not in the Pascal whitelist). Array parameters are only usable with `decl_to_c`.

### 4.4 Multidimensional arrays

**Not supported.** `int arr[][]` is skipped.

**Root cause**: `ExtractArraySuffix` handles only a **single-level** `[...]` suffix.

1. The segment is scanned backwards and hits the first `]`.
2. It finds the matching `[`.
3. **It continues backwards and hits another `]`.**
4. `ParseParamSegment` cannot determine the parameter-name position when two array suffixes are present.
5. The segment is judged illegal; the whole declaration is skipped.

**Workaround**: use `int * arr` or a single-level `int arr[N]`.

---

## 5. Comment binding

### 5.1 Binding rules

| Pattern | Bound? |
|---------|:------:|
| `/* ... */` directly above | Yes |
| `//` single-line directly above | Yes |
| Doxygen `/** ... */` above | Yes (` * ` prefix stripped) |
| Multi-line comment above | Yes (normalized) |
| Comment1 → comment2 → declaration | Both bound |
| Declaration → trailing comment | **No** |
| No comment | Allowed; `Comment` is empty |

### 5.2 Examples

```c
// WRONG — trailing comment is ignored
int add(int a, int b); /* this comment is NOT bound */

// RIGHT — preceding comment is bound
/* This comment IS bound. */
int add(int a, int b);
```

### 5.3 Multi-line comment normalization

**Input**:

```c
/* This is a comment
that spans multiple
lines */
int foo(void);
```

**Metadata `Comment`** (Pascal style, every line after the first carries a ` * ` prefix):

```
{ This is a comment
 * that spans multiple
 * lines }
```

**Interaction with the Model-layer strip (v2.0)**:

`Z.Pascal_Func_Model.ExtractParamDescriptions` automatically strips the leading ` * ` prefix:

| Raw line | After stripping | Handling |
|----------|-----------------|----------|
| `' @param a first addend'` | unchanged | recognised as parameter `a` |
| `' * @param b second addend'` | `' @param b second addend'` | recognised as parameter `b` |
| `' *         continuation'` | `'         continuation'` | indented continuation of the previous parameter |

**User perspective**: write normal Doxygen comments in C. The Model layer handles the ` * ` prefix. You do not need to do anything.

### 5.4 Doxygen style

**Input**:

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 */
int add(int a, int b);
```

**Metadata `Comment`**:

```
{ Computes the sum of two integers.
 * @param a first addend
 * @param b second addend }
```

### 5.5 Cross-layer lifecycle (v2.0)

Full path of a C comment from source to JSON:

| Stage | Operation | Output form |
|:-----:|-----------|-------------|
| `Fill_C` | Extract C comment + normalize multi-line | C style, every line after the first carries ` * ` |
| `Translate_C_Typ_To_Pascal` | C style → Pascal style | Pascal `{ ... }`, every line after the first carries ` * ` |
| `CleanComment` | Strip comment markers + unify to LF | Plain text; the ` * ` prefix is preserved as content |
| `ExtractParamDescriptions.GetContentLine` | **Strip the leading ` * ` prefix** | Lines used for recognition |
| `GetFullDescription` | Skip blank lines and lines starting with `@`; strip `*`; join with space | Single-line tool description |

### 5.6 How the tool description is assembled (v2.0)

`pas_mcp_generator_tool.GetFullDescription(Comment)` behaves as follows:

| Step | Behaviour |
|:----:|-----------|
| 1 | Split `Comment` on `#10` / `#13` |
| 2 | Skip **empty lines** |
| 3 | Skip lines starting with `@` (Doxygen tags) |
| 4 | Strip leading `*` / `**` (block-comment continuation markers) |
| 5 | Join remaining lines with a single space |
| 6 | Truncate to **200 characters** |

**Example**:

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 * Return value: an Integer representing the sum.
 */
int add(int a, int b);
```

Resulting tool description:

```
"Computes the sum of two integers. Return value: an Integer representing the sum."
```

(The `@param a first addend`, `@param b second addend`, and `@return the sum` lines are **skipped**.)

**Consequences for C header authors**:

- `@param` / `@return` lines do not enter the tool description — they only feed parameter extraction (`Params[i].Description`).
- Parameter descriptions live in `Params[i].Description`, not in the tool description.
- The tool description contains only free-form text (function purpose, return semantics, etc.).
- **The 200-character limit is hard**. Put the most important information first.

**Best practice**:

- First line: a one-sentence summary of what the function does.
- Middle lines: `@param name description` for each parameter.
- Last lines: a free-text sentence about the return value, starting with `Return value:`.

---

## 6. Unit name extraction

### 6.1 Priority

1. Filename in a `*.h` / `*.c` comment — extract the leading identifier.
2. Include guard macro name from `#ifndef` / `#ifdef` / (guard-shaped) `#define`.
3. Fallback: `untitled.h`.

### 6.2 Examples

| Header starts with | Unit name | Result |
|--------------------|-----------|:------:|
| `/* foo.h ... */` | `foo` | OK |
| `// bar.c` | `bar` | OK |
| `#ifndef FOO_H` | `FOO` | OK |
| `#ifndef __FOO_H__` | `FOO` | OK |
| `#ifndef FOO_HPP` | `FOO` | OK |
| `#ifndef FOO_INCLUDED` | `FOO` | OK |
| `#define MAX_SIZE 1024` | `untitled.h` (not guard-shaped) | Fallback |
| `/* 1.0.3.h */` | `untitled.h` (invalid identifier) | Fallback |
| Empty | `untitled.h` | Fallback |

### 6.3 Guard suffix stripping

Supported guard suffixes (longest match first):

- `_INCLUDED`
- `_HXX` / `_HPP`
- `_H__` / `_H_` / `_H`

Leading and trailing underscores are also stripped.

---

## 7. Complete examples

### 7.1 Positive example (all pass)

```c
/* sample.h - positive example */
#ifndef SAMPLE_H
#define SAMPLE_H

#include <stddef.h>

/* Computes the sum of two integers. */
int add(int a, int b);

/*
 * Unsigned integer example.
 */
unsigned int get_unsigned(void);

/* 64-bit signed integer. */
long long get_longlong(void);

/* Single precision float. */
float get_float(void);

/* Double precision float. */
double get_double(void);

/**
 * Gets an error message.
 * @param code error code
 * @return error description string
 */
const char * get_error_message(int code);

/* Array parameter example. */
void fill_buffer(int buf[], int len);

#endif /* SAMPLE_H */
```

**Parsing results**:

| Declaration | C side | Pascal side | JSON side |
|-------------|:------:|:-----------:|:---------:|
| `int add(int a, int b)` | Extracted | Extracted | Extracted (`ReturnType="int64"`) |
| `unsigned int get_unsigned(void)` | Extracted | Extracted | Extracted (`ReturnType="int64"`) |
| `long long get_longlong(void)` | Extracted | Extracted | Extracted (`ReturnType="int64"`) |
| `float get_float(void)` | Extracted | Extracted | Extracted (`ReturnType="double"`) |
| `double get_double(void)` | Extracted | Extracted | Extracted (`ReturnType="double"`) |
| `const char * get_error_message(int code)` | Extracted | Extracted | Extracted (`ReturnType="string"`, `ResultMod="const"`) |
| `void fill_buffer(int buf[], int len)` | Extracted | Extracted | **Skipped** (`buf` type is `array of Integer`, not in the Pascal whitelist) |

> **v2.0 key point**: **C-side acceptance does not imply Pascal-side acceptance, which does not imply JSON-side acceptance.** Array parameters are accepted on the C side but rejected on the JSON side.

### 7.2 Negative example (all skipped)

```c
/* bad.h - negative example */

/* SKIP: function definition with body */
int internal_helper(void) {
    return 42;
}

/* SKIP: boolean return */
_Bool is_even(int x);

/* SKIP: struct parameter */
double distance(struct Point p1, struct Point p2);

/* SKIP: enum parameter */
int set_color(enum Color c);

/* SKIP: wide char */
int print_wide(wchar_t * s);

/* SKIP: function pointer parameter */
void set_callback(void (*cb)(int));

/* SKIP: variadic */
int printf_like(const char * fmt, ...);

/* SKIP: union parameter */
void set_value(union Value v);

/* SKIP: pointer parameters */
void * void_ptr_return(int size);
void restrict_param(void * p);

/* SKIP: global variable */
int global_counter;

/* SKIP: initialized variable */
int initialized = 42;

/* SKIP: struct definition */
struct Foo {
    int x;
    int y;
};
```

All skipped; the `Report` lists the reason for each.

---

## 8. Common mistakes and their fixes

| Wrong | Result | Right |
|-------|:------:|-------|
| `int f() { ... }` | Skipped (function definition) | `int f(void);` |
| `int f(int a, ...)` | Skipped (variadic) | Use fixed parameters |
| `void set_cb(void (*cb)(int))` | Skipped (function pointer) | Use an integer handle |
| `int f(struct Point p)` | Skipped (struct) | Split into `int x, int y` |
| `int f(enum Color c)` | Skipped (enum) | Pass the enum value as `int` |
| `_Bool f(int x)` | Skipped (boolean) | Return `int` (0 or 1) |
| `int f(wchar_t * s)` | Skipped (wide char) | Use `char *` |
| **`void * f(int x)`** | **Skipped (pointer)** | **Use `uint64_t` to carry the address** |
| **`int f(int * p)`** | **Skipped (pointer)** | **Use an int array or split into value parameters** |
| `int global_var;` | Skipped (variable) | Move into a function |
| `int x = 42;` | Skipped (initialized variable) | Move into a function |
| Declaration inside `{ ... }` | Skipped | Move to top level |
| **`int arr[][]`** | **Skipped (multidimensional array)** | **Use `int * arr` or `int arr[N]`** |
| Comment separated from declaration by another declaration | Comment not bound | Keep the comment adjacent |
| Trailing comment `int f(); // ...` | Ignored | Move comment above |
| Header name `1.0.3.h` | Unit name falls back to `untitled.h` | Use a proper `foo.h` or a guard |
| **Relying on `@return` for return info** | **Not extracted** | **The text stays in `Comment` only** |
| **`@return` on a `void` function** | **Ignored** | **Do not use it on `void`** |

---

## 9. Self-check before you save the file

| # | Check | Action if failing |
|:-:|-------|-------------------|
| 1 | Ends with `;` (prototype, not definition)? | Remove any `{ ... }` body |
| 2 | At top level (not inside a function body or type)? | Move to top level |
| 3 | No function-pointer parameters? | Use an integer handle |
| 4 | All types in the whitelist? | Use integer / float / string (no pointers) |
| 5 | Comment directly above? | Move the comment (blank lines are allowed) |

---

## 10. Minimum parseable template

Copy and fill in the placeholders:

```c
/* <filename>.h */
#ifndef <GUARD>
#define <GUARD>

/**
 * <natural-language description of the function>.
 * @param <param1> <description of param1>
 * @param <param2> <description of param2>
 * @return <description of return value>
 */
<return type> <function name>(<param1 type> <param1 name>, <param2 type> <param2 name>);

#endif /* <GUARD> */
```

**Fill-in rules**:

| Placeholder | Allowed values |
|-------------|----------------|
| `<GUARD>` | e.g. `FOO_H` / `FOO_HPP` / `FOO_INCLUDED` |
| `<function name>` | Any valid C identifier (not a reserved word) |
| `<paramN name>` | Any valid C identifier (not a reserved word) |
| `<paramN type>` | See §3 (no pointers) |
| `<return type>` | See §3 (`void` allowed) |

**The template uses Doxygen `/** */` comments** for three reasons:

1. Aligns with Pascal rule v8.0 (both use ` * ` prefixed continuation lines).
2. The Model layer strips the ` * ` prefix automatically — no need to worry.
3. Doxygen is the C ecosystem standard.

**Reminders**:

- The return type must be in the signature (`<return type> <function name>`). The comment's `@return` is only for the agent's semantic understanding.
- Parameter names are required (C allows anonymous parameters, but the Pascal side skips them).
- **Write detailed comments.** The agent sees the tool description, which is assembled from your comment. More detail in, more accurate calls out.

---

## 11. Common misreadings

### 11.1 "`void *` is accepted on the C side, so it must work everywhere"

**Reality**: three stages.

1. `Fill_C` accepts `void *`.
2. `Translate_C_Typ_To_Pascal` maps it to `Pointer`.
3. `Z.Pascal_Func_Model` sees `Pointer`, which is not in the whitelist, and skips the whole declaration.

```c
// Written:
void * allocate(int size);

// Report:
// Skipped: "allocate" - Reason: Parameter "p" has unsupported type "Pointer"
```

**Fix**: use `uint64_t` to carry the address.

```c
uint64_t allocate(int size);
```

### 11.2 "Array parameters work throughout the toolchain"

**Reality**: array parameters are only valid in `Fill_C` and `decl_to_c`. At the `Z.Pascal_Func_Model` stage, `array of Integer` is not in the whitelist and the whole declaration is skipped.

```c
void fill_buffer(int buf[], int len);
```

- C side: extracted.
- Pascal side: extracted.
- **JSON side**: skipped.

**Fixes**:

- If you only need C output (`decl_to_c`), keep the array.
- If you need JSON output (MCP tool), split the array into multiple value parameters, or carry it as a JSON string.

### 11.3 "`@param` lines go into the tool description"

**Reality**: `@param` / `@return` lines are **skipped** by `GetFullDescription` (see §5.6). They only feed parameter descriptions (`Params[i].Description`).

```c
/**
 * @param code error code
 * @return error description
 */
const char * get_error_message(int code);
```

Result:

- `Params[0].Description = "error code"`.
- tool description = `""` (empty — only `@param` and `@return` lines).

**Fix**: add a free-form sentence.

```c
/**
 * Gets an error message.
 * @param code error code
 * @return error description
 */
const char * get_error_message(int code);
```

tool description = `"Gets an error message."`

### 11.4 "The ` * ` prefix pollutes parameter descriptions"

**Reality**: `Z.Pascal_Func_Model` strips the leading ` * ` automatically.

```c
/**
 * Function purpose.
 * @param a first addend
 * @param b second addend
 */
int add(int a, int b);
```

- `a` description = `"first addend"` (no ` * ` prefix).
- `b` description = `"second addend"` (no ` * ` prefix).

### 11.5 "The return type can be omitted"

**Reality**: the C prototype must declare the return type explicitly. C syntax allows omitting it (implicit `int`), but `Fill_C` treats a prototype without a return type as not-a-function (the preceding token is not an identifier) and skips the whole declaration.

```c
// WRONG — skipped
add(int a, int b);

// RIGHT
int add(int a, int b);
```

### 11.6 "`const` is a strong restriction"

**Reality**: `const` is fully allowed. All three positions (prefix, suffix, pointer-post) are recognised.

```c
int f(const char * s);
int f(char const * s);
int f(int * const p);
```

All three mark `param_mod = "const"`; the parameter name and type are extracted normally.

### 11.7 "`extern \"C\"` needs special handling"

**Reality**: `extern "C" { ... }` is a **transparent block**. Prototypes inside it are handled as ordinary top-level functions. No special syntax is needed.

```c
extern "C" {
    int add(int a, int b);
    int sub(int a, int b);
}
```

`add` and `sub` are both extracted normally.

### 11.8 "A blank line breaks the comment binding"

**Reality**: blank lines are allowed. The toolchain scans backwards from the declaration, skips blank lines, and binds the first non-empty comment block.

```c
/* This is the comment. */

int add(int a, int b);
```

`Comment = "This is the comment."`.

**But**: two comment blocks separated by a blank line are **not merged**. Only the closest one is bound.

```c
/* First comment. */

/* Second comment. */

int add(int a, int b);
```

`Comment = "Second comment."`.

### 11.9 "`#define` might be treated as a function"

**Reality**: `#define` is completely skipped — never treated as a function, never as a parameter.

```c
#define MAX_SIZE 1024
#define SQUARE(x) ((x) * (x))
```

Both are skipped. Even `SQUARE(x)` looks like a function call; the whole `#define` line is recognised as a preprocessor directive.

### 11.10 "The header name does not affect parsing"

**Reality**: the header name affects unit-name extraction (see §6). If the name is non-standard (`1.0.3.h`), the unit name falls back to `untitled.h` or the guard name.

```c
/* 1.0.3.h */
#ifndef VERSION_H
#define VERSION_H
int get_version(void);
#endif
```

- Unit name from `1.0.3.h` fails (starts with a digit).
- Unit name from `VERSION_H` succeeds → `VERSION`.

**Recommendation**: use a proper `foo.h` name.

---

## 12. Alignment with the Pascal rule (v8.0)

C declarations and Pascal declarations share the same metadata structure (`tfunc_decl`) and the same downstream model (`Z.Pascal_Func_Model`). The two rule sets are complementary:

| Dimension | C rule (this document) | Pascal rule v8.0 |
|-----------|:----------------------:|:----------------:|
| Input | `.h` header | `.pas` source |
| Extract target | Top-level function prototype | `interface`-section top-level function/procedure |
| Comment style | `/* */`, `//`, `/** */` | `(* ... *)`, `//`, `{ ... }` |
| Comment prefix | ` * ` from the second line onwards | Same (toolchain product) |
| Type whitelist | C types | Pascal types |
| Cross-layer rejection | `void *` → `Pointer` → rejected | `Pointer` rejected directly |
| Array parameters | Single-level `[]` supported | Not supported at the Model layer |
| Return-value description | `@return` stays in `Comment` | `Return value:` stays in `Comment` |

**Interop advice**:

- **Output C code only**: use this rule. Array and pointer parameters are usable (`decl_to_c` supports them).
- **Output Pascal code only**: use the Pascal rule. Array and pointer parameters are not usable.
- **Output JSON (MCP tool)**: both rules apply. **Avoid pointer and array parameters.**

---

## 13. Design principles

### 13.1 Parser assumptions

- **Prototype only**: function definitions, type definitions, global variables, and preprocessor lines are skipped.
- **Mappable types only**: structs, unions, enums, booleans, wide chars, function pointers, variadics, and pointers are skipped.
- **Silent skip**: no exception; the reason is recorded in the `Report`; parsing continues.

### 13.2 Three rules for the author

1. **Read the whitelist before you write** (§3).
2. **Self-check after you write** (§9).
3. **Check the `Report` after you run it**.

### 13.3 Symmetry between C and Pascal

| Dimension | Pascal side | C side |
|-----------|-------------|--------|
| Input | `.pas` source | `.h` header |
| Extract target | `interface`-section top-level routines | Top-level function prototypes |
| Comment style | `(* ... *)`, `//`, `{ ... }` | `/* ... */`, `//`, `/** ... */` |
| Strings | Single quotes | Double quotes |
| Keyword check | `Pascal_Keyword` | `IsCReservedWord` |
| Return-value `const` | — | `ResultMod` field |
| Array parameters | `array of X` | `param_array` suffix |
| Uniqueness constraint | — | `restrict` is stripped |
| **Pointer parameters** | **Forbidden** | **Forbidden (after mapping)** |

### 13.4 Key design decisions

| Decision | Reason |
|----------|--------|
| Metadata is stored in Pascal style as the canonical form | `decl_to_pascal` outputs it verbatim; `decl_to_c` re-converts |
| Comments are normalized to Pascal `{ ... }` | Single style simplifies downstream code |
| Types are mapped by width + sign | C → Pascal → C round-trip fidelity |
| `restrict` is stripped | No semantic loss; avoids downstream mapping failure |
| Array suffix is stored separately | Base type stays a simple identifier for symmetric code generation |
| Function-pointer parameters are skipped entirely | Cannot be expressed as JSON Schema value types |
| Silent skip rather than exception | Matches the Pascal side for consistent toolchain behaviour |
| **Pointers are rejected at the Model layer** | **Safe serialization requires value types** |

---

## 14. Revision history

- **v2.0 (2026-09-20)** — English rebuild with more examples and fewer diagrams. Structural updates from the Chinese v2.0 preserved.
- **v1.0 (2026-09-12)** — Initial release.

---

**This document is the parsing contract. Any deviation means declarations will be silently skipped, comments silently lost, or parameter descriptions silently ignored.**

**If a declaration is skipped — look for pointers, arrays, or function pointers.**
**If `Comment` is empty — check for another declaration between the comment and the signature.**
**If a parameter description looks wrong — check that the parameter name is at line start.**
**And above all: write detailed comments. The agent sees only your comment, not your code.**