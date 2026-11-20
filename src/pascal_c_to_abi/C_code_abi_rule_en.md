# C Declaration Writing Rules (ABI Tool Chain)

> *English translation of [C_code_abi_rule.md](C_code_abi_rule.md).*

**Purpose**: this is a **writing guide**, not a source-code commentary. Write according to this document and your declarations will be extracted and generated correctly; ignore it and your declarations will be **silently skipped** (no error, no warning, only one line of reason in the report).
**Contract**: this document is the **parsing contract**. Deviating from the contract causes declarations to be silently skipped, comments to be silently discarded, and parameter descriptions to be silently lost.

---

## 0. 30-second overview

### 0.1 What you may write

```c
/* Function prototypes at the top level of a header, ending with ; */
int add(int a, int b);
unsigned int get_count(void);
const char * get_error(int code);

/* Added in v10: CBytes binary payloads */
void send_bytes(const char * channel, CBytes data);
CBytes make_bytes(int n);
CBytes echo_bytes(CBytes data);

/* An extern "C" block is transparent; its contents are parsed normally */
extern "C" {
    int mul(int a, int b);
}
```

### 0.2 What you may not write

```c
/* All of these are silently skipped */
int helper(void) { return 42; }                  /* function definition (has a body) */
void set_cb(void (*cb)(int));                    /* function-pointer parameter */
double dist(struct Point p1, struct Point p2);   /* struct parameter */
int set_color(enum Color c);                     /* enum parameter */
_Bool is_even(int x);                            /* bool return */
void * allocate(int size);                       /* non-char pointer */
void fill(int * p);                              /* non-char pointer */
int fill_buffer(int buf[], int len);             /* non-byte array, array semantics lost */
void matrix(int m[][10], int rows);              /* multi-dimensional array */
int printf_like(const char * fmt, ...);          /* variadic */
int global_counter;                              /* global variable */
struct Point { int x; int y; };                  /* type definition */
#include <stdio.h>                               /* preprocessing */
```

### 0.3 Where the content goes

| What you write | Destination |
|------------|------|
| Signature (parameter names, types, return type) | Structured JSON (`Name`, `Params[i].Name`, `Params[i].Typ`, `ReturnType`) |
| The adjacent comment | The `Comment` field; the first non-empty, non-`@` paragraph → tool description (truncated to 200 characters) |
| `@param name desc` lines in the comment | `Params[i].Description` |
| `@return` in the comment | Kept only inside `Comment`, **not** placed into structured JSON |
| `Return value: ...` in the comment | Kept only inside `Comment`, **not** placed into structured JSON |

**The AI can actually see only two things**: `Comment` (tool description + parameter descriptions) and `ReturnType`. Nothing else goes into the JSON.

---

## 1. Location

### 1.1 Rule

It must be a **top-level function prototype** in the header file, ending with `;`.

- It must not have a function body (`{ ... }`).
- It must not be nested inside `struct` / `union` / `enum` / `typedef`.
- It must not be a global variable or a macro.

### 1.2 The structure a header must have

The tool chain scans the whole header. The header's first-line comment, the include guard and the function prototypes all take part in parsing.

**Recommended structure**:

```c
/* foo.h */
#ifndef FOO_H
#define FOO_H

#include <stddef.h>

/* Function prototypes */
int add(int a, int b);

#endif /* FOO_H */
```

**The header's first-line comment and the include guard determine the "unit name"** (see chapter 2). This is not optional — without them the generated Pascal unit name becomes `untitled.h`, and `untitled.h` is an **illegal Pascal unit name**.

### 1.3 Which locations are not accepted

| Location | Result | Fix |
|------|------|------|
| Inside a function body | Skipped | Move it to the top level |
| Inside `struct` / `union` / `enum` / `typedef` | Skipped | Move it to the top level |
| `#define` macro | Skipped | Change to a function prototype |
| Global variable | Skipped | Change to a getter/setter function |
| Function definition (with `{ ... }`) | Skipped | Remove the function body |
| Multi-dimensional array parameter | Whole declaration skipped | Change to a one-dimensional array or CBytes |

---

## 2. Unit name

### 2.1 Rule

**The unit name determines the generated Pascal unit name**. If the unit name is `untitled.h`, the Pascal generator emits `unit untitled.h;` — **that is illegal Pascal** and compilation fails.

So: **the header must let the tool chain extract a legal unit name**.

### 2.2 Extraction priority

Within the first 100 lines the tool chain extracts the unit name in this priority order:

1. **The `.h` / `.H` / `.c` / `.C` file name** (`/* foo.h */` → `foo`).
2. **The include-guard macro name** (`#ifndef FOO_H` → `FOO`).
3. **Fallback**: `untitled.h`.

**⚠️ `.hpp` / `.hxx` are not recognized as file-name extensions**. If the file is `foo.hpp` and there is no include guard, the unit name degrades to `untitled.h`.

### 2.3 Include-guard suffix stripping rules

The tool chain recognizes and strips the following suffixes (longest first):

```
_INCLUDED, _HXX, _HPP, _H__, _H_, _H
```

Then it strips leading and trailing underscores.

| Original macro name | After stripping |
|----------|--------|
| `FOO_H` | `FOO` |
| `FOO_H_` | `FOO` |
| `__FOO_H__` | `FOO` |
| `FOO_INCLUDED` | `FOO` |
| `FOO_HPP` | `FOO` |
| `FOO_HXX` | `FOO` |
| `MAX_SIZE` | `untitled.h` (not a guard) |

### 2.4 Recommended form

```c
/* foo.h */
#ifndef FOO_H
#define FOO_H

/* Function prototypes */
int add(int a, int b);

#endif /* FOO_H */
```

The unit name is extracted as `foo` (file name takes priority), and the Pascal unit name is `foo_abi_service_unit` — **legal**.

### 2.5 Forbidden forms

```c
/* 1.0.3.h */          // the file name starts with a digit, not a legal identifier
#ifndef 1_0_3_H       // the macro name is not a legal identifier
#define MAX_SIZE 1024  // MAX_SIZE is not a guard (no _H suffix)
```

The unit name degrades to `untitled.h`. When Pascal code is generated, `unit untitled.h;` fails to compile.

### 2.6 Emergency fix

If the header cannot provide a legal unit name any more, change it manually before generating:

```
change "untitled.h" to a legal identifier (e.g. "myunit")
```

The fix differs per generator entry point, but **the root cause is that the header lacks a legal file name or guard**. The best fix is **to provide the correct guard when you write the header**.

---

## 3. Preprocessing and blocks

### 3.1 Preprocessor directives

**Every line starting with `#` is skipped** — including `#include`, `#define`, `#if`, `#ifdef`, `#ifndef`, `#endif` and `#pragma`.

```c
#include <stdio.h>                       /* skipped */
#define MAX_SIZE 1024                    /* skipped */
#pragma once                             /* skipped */
#ifndef FOO_H                            /* skipped */
#define FOO_H                            /* skipped */
#endif                                   /* skipped */
```

**But the include-guard macro name is used to extract the unit name** (see chapter 2).

### 3.2 `extern "C"` blocks

`extern "C" { ... }` is **transparent**. The function prototypes inside are parsed normally.

```c
extern "C" {
    int mul(int a, int b);               /* extracted */
    int divi(int a, int b);              /* extracted */
}
```

**Recognition condition**: the token before `{` is not `)` and the statement does not contain `struct` / `enum` / `union` / `typedef`.

### 3.3 Type-definition blocks

The `{ ... }` blocks of `struct` / `union` / `enum` / `typedef` are **skipped as a whole**.

```c
struct Point { int x; int y; };          /* skipped as a whole */
enum Color { RED, GREEN, BLUE };         /* skipped as a whole */
typedef struct { int v; } TValue;        /* skipped as a whole */
```

### 3.4 Function bodies

If the token before `{ ... }` is `)`, this is a function definition and is **skipped as a whole**.

```c
int helper(void) { return 42; }          /* skipped as a whole */
```

### 3.5 Comments

Comments are skipped, but **a preceding comment is bound to the function prototype** (see chapter 9).

---

## 4. Parameter modifiers

### 4.1 Rule

| Modifier | Allowed? | Notes |
|--------|:----------:|------|
| (none) | ✅ | Pass by value |
| `const` | ✅ | Kept |
| `restrict` / `__restrict` / `__restrict__` | ✅ | **Silently stripped** (does not affect function) |
| `volatile` / `__volatile` / `__volatile__` | ✅ | Kept in the type text |
| `var` / `out` | ❌ | Whole declaration skipped (a defensive check; C has no such modifiers) |

### 4.2 Examples

```c
/* OK */
int add(int a, int b);
int mul(const int a, const int b);
int echo(const char * s);

/* All positional variants of const are recognized */
int f1(const char * s);                  /* const as a prefix */
int f2(char const * s);                  /* const as a suffix */
int f3(int * const p);                   /* const after the pointer (not recommended, see 5.4) */

/* restrict is stripped */
int memcpy_opt(void * restrict dst, const void * restrict src, size_t n);
/* equivalent to: int memcpy_opt(void * dst, const void * src, size_t n); */
/* but src is rejected because void * → Pointer, see 5.3 */
```

### 4.3 Modifiers shared by multiple parameters

C **has no** syntax for "a modifier shared by several parameters". Each parameter must be annotated separately:

```c
/* Correct */
int group_const(const int a, const int b, const int c);

/* Wrong (a C syntax error) */
int group_const(const int a, b, c);
```

### 4.4 Notes on `const` with multiple parameters

`const int * p` and `int * const p` have different meanings:

- `const int * p`: the pointed-to content is const, the pointer itself is mutable → type text `const int *` → contains `*` → `Pointer` → rejected.
- `int * const p`: the pointer itself is const, the pointed-to content is mutable → type text `int * const` → contains `*` → `Pointer` → rejected.

Both are rejected because they contain `*` and are not in the `char *` family. **`const` cannot rescue a pointer**.

---

## 5. Type rules

### 5.1 Allowed types (four families)

| Category | C types |
|------|--------|
| Signed integers | `signed char`, `short`, `short int`, `signed short`, `signed short int`, `int`, `signed`, `signed int`, `long`, `long int`, `signed long`, `signed long int`, `long long`, `long long int`, `signed long long`, `signed long long int`, `int8_t`, `int16_t`, `int32_t`, `int64_t` |
| Unsigned integers | `unsigned char`, `unsigned short`, `unsigned short int`, `unsigned int`, `unsigned`, `unsigned long`, `unsigned long int`, `unsigned long long`, `unsigned long long int`, `uint8_t`, `uint16_t`, `uint32_t`, `uint64_t` |
| Pointer-width integers | `size_t`, `uintptr_t`, `ssize_t`, `ptrdiff_t`, `intptr_t` |
| Floats | `float`, `double`, `long double` |
| Strings | `char *`, `const char *`, `char const *`, `const char * const`, `char const * const` (including variants without spaces) |
| Binary | **`CBytes` / `cbytes`** (including `const cbytes`, `cbytes *`, `const cbytes *`) |
| void (return) | `void` |

### 5.2 Cross-language mapping table

| C type you write | Pascal type | JSON description | Generated Pascal ABI | Generated C++ ABI |
|---------------|:-----------:|:---------:|:-----------------:|:--------------:|
| `signed char` / `int8_t` | `ShortInt` | `int64` | `ShortInt` | `std::int8_t` |
| `short` / `int16_t` | `SmallInt` | `int64` | `SmallInt` | `std::int16_t` |
| `int` / `int32_t` | `Integer` | `int64` | `Integer` | `std::int32_t` |
| `long` / `long int` | `LongInt` | `int64` | `LongInt` | `std::int32_t` |
| `long long` / `int64_t` | `Int64` | `int64` | `Int64` | `std::int64_t` |
| `unsigned char` / `uint8_t` | `Byte` | `int64` | `Byte` | `std::uint8_t` |
| `unsigned short` / `uint16_t` | `Word` | `int64` | `Word` | `std::uint16_t` |
| `unsigned int` / `uint32_t` | `Cardinal` | `int64` | `Cardinal` | `std::uint32_t` |
| `unsigned long` | `LongWord` | `int64` | `LongWord` | `std::uint32_t` |
| `unsigned long long` / `uint64_t` | `UInt64` | `int64` | `UInt64` | `std::uint64_t` |
| `size_t` / `uintptr_t` | `UInt64` | `int64` | `UInt64` | `std::uint64_t` |
| `ssize_t` / `ptrdiff_t` / `intptr_t` | `Int64` | `int64` | `Int64` | `std::int64_t` |
| `float` | `Single` | `double` | `Single` | `float` |
| `double` | `Double` | `double` | `Double` | `double` |
| `long double` | `Extended` | `double` | `Extended` | `double` (precision loss) |
| `char *` family | `string` | `string` | `string` | `std::string` |
| **`CBytes` / `cbytes`** | **`TBytes`** | **`TBytes`** | **Binary payload** | **`std::vector<std::uint8_t>`** |
| `void` (return) | — | — | Degraded to a procedure | Return type is `void` |
| Any other type containing `*` | `Pointer` | — | ❌ Rejected | ❌ Rejected |
| Any other type | — | — | ❌ Rejected | ❌ Rejected |

### 5.3 Forbidden types and reasons

Any one of these causes **the whole declaration to be skipped**.

| Category | Example | Why not | Alternative |
|------|------|------------|------|
| Boolean | `bool`, `_Bool` | Boolean representation differs across languages | `int` (0/1) or `unsigned char` |
| Wide characters | `wchar_t`, `char16_t`, `char32_t` | Representation differs across languages | `char *` or `CBytes` |
| Struct | `struct Point` | Cross-language layout differs | Split into several scalar parameters, or `CBytes` |
| Union | `union Value` | Cross-language layout differs | Split into several scalar parameters |
| Enum | `enum Color` | Cross-language enum representation differs | `int` |
| Custom typedef | `TMyHandle` | Not recognized | Expand to a concrete type |
| **Non-char pointers** | `void *`, `int *`, `const void *` | An address has no cross-process meaning | `uint64_t` (carrying the address) or `CBytes` |
| **Non-byte arrays** | `int buf[]`, `double vals[]` | Array semantics are ultimately lost | `CBytes` |
| **Multi-dimensional arrays** | `int m[][10]` | Cannot be serialized | `CBytes` or expand into multiple parameters |
| Function-pointer parameters | `void (*cb)(int)` | Cannot be serialized | `uint64_t` (carrying a handle) |
| Variadic | `...` | The number of parameters is unknown | Fixed parameters or `CBytes` |

### 5.4 The three layers of pointer traps (important)

On the C side, pointers go through **three filters**:

```
Fill_C parsing  →  Translate type mapping  →  Model normalization
   ✅                   partial mapping          ❌ rejected
```

**The only accepted pointer is the `char *` family**. Every other pointer (`void *`, `int *`, `struct X *` etc.) is mapped to `Pointer` and then rejected at the Model layer.

**This means**:

```c
/* Wrong — eventually skipped */
void * allocate(int size);
void   fill(void * dst, size_t n);
int    read(int * p);
void   use_ptr(struct Point * p);

/* Correct — carry the address in a uint64_t */
uint64_t allocate(int size);
void     fill(uint64_t dst, size_t n);
int      read(uint64_t p);
void     use_ptr(uint64_t p);

/* Preferred — carry binary data in CBytes */
CBytes allocate(int size);
void   fill(CBytes dst, size_t n);
CBytes read(CBytes p);
```

### 5.5 The boundary of the `char *` family

The complete list of the `char *` family:

```c
char *
char*
const char *
const char*
char const *
char const*
const char * const
const char* const
char const * const
char const* const
```

**Forms not on the list are mapped to `Pointer` and then rejected**:

```c
/* Rejected — not in the char * family list */
char * const p1;        // const after the pointer, not on the list
char * restrict p2;     // restrict is stripped, leaving char *, OK
int * p3;               // int is not char
void * p4;              // void is not char
```

### 5.6 The pointer/array misconception

In C, `char *` and `char []` parameters are often used interchangeably. In the tool chain:

- `char * s` → `string` (OK)
- `char s[]` → `string`? **No** — it takes the array path (see chapter 6).

**Recommendation**: express strings with `char *` and binary data with `CBytes`. **Do not** use `char []` parameters.

---

## 6. Array parameters

### 6.1 Rule

C array parameters have **two possible fates** in the tool chain:

| Form | Result | Reliable |
|------|------|:------:|
| `unsigned char buf[]` / `uint8_t buf[]` | → `CBytes` | ✅ Reliable |
| `unsigned char buf[16]` | → `CBytes` (length information lost) | ✅ Reliable |
| `int buf[]` | → `int` (**array semantics lost**) | ❌ Unreliable |
| `int buf[16]` | → `int` (**array semantics lost**) | ❌ Unreliable |
| `int m[][10]` | Whole declaration skipped | ❌ Rejected |

**Conclusion**: **only `unsigned char []` / `uint8_t []` / `CBytes` can reliably express arrays**. Arrays of any other type ultimately lose their array semantics.

### 6.2 Why `int buf[]` is unreliable

The tool chain's processing flow:

1. `Fill_C` stage: recognized as `param_typ='int'`, `param_array='[]'`.
2. `Translate` stage: `int` → `Integer`; `param_array` is preserved (because it is not `Byte`).
3. `Model` normalization stage: `Integer` → `int64` (or `integer`); **the `param_array` information is ignored at this layer**.
4. Generator stage: generates a single scalar parameter of type `int64`.

**Result**: `void fill(int buf[])` becomes `void fill(std::int64_t buf)` at the ABI layer — `buf` changes from an array into a single integer.

**This is the most dangerous silent trap** — the declaration looks legal, but the generated result does not match expectations at all.

### 6.3 Correct forms

```c
/* Wrong — array semantics lost */
void fill(int buf[]);
void write_block(int buf[16], int n);

/* Correct — use CBytes */
void fill(CBytes buf);
void write_block(CBytes buf, int n);

/* Correct — unsigned char [] also works */
void fill(unsigned char buf[]);
void write_block(unsigned char buf[16], int n);

/* Correct — use several scalar parameters */
void fill(int b0, int b1, int b2, int b3);
```

### 6.4 Multi-dimensional arrays

```c
/* whole declaration skipped */
void matrix(int m[][10], int rows);
```

**Alternatives**:

```c
/* flatten into a one-dimensional CBytes */
void matrix(CBytes m, int rows, int cols);
```

---

## 7. Function-pointer parameters

### 7.1 Rule

A function-pointer parameter causes **the whole declaration to be skipped**.

```c
/* whole declaration skipped */
void set_callback(void (*cb)(int));
void register_handler(int (*handler)(void *, int));
void use_op(double (*op)(double, double));
```

**Reason**: function pointers cannot be serialized. Across processes or languages a pointer means nothing.

### 7.2 Alternatives

**Option 1: integer handles**

```c
/* carry the handle in a uint64_t */
void set_callback(uint64_t cb_handle);
void register_handler(uint64_t handler_handle);
```

The caller maintains a local "handle → function" mapping, and the ABI layer only passes the handle.

**Option 2: string identity**

```c
/* identify the callback with a string */
void set_callback(const char * callback_id);
```

**Option 3: separate callback APIs**

Split the callback semantics into two independent APIs:

```c
/* register */
void register_handler(const char * handler_id);

/* invoke (internally calls the registered handler) */
int invoke_handler(const char * handler_id, CBytes data);
```

---

## 8. Variadic parameters

### 8.1 Rule

`...` causes **the whole declaration to be skipped**.

```c
/* whole declaration skipped */
int printf_like(const char * fmt, ...);
void log(const char * level, const char * fmt, ...);
```

**Reason**: the number and types of the parameters are unknown at compile time and cannot be serialized.

### 8.2 Alternatives

**Option 1: fixed parameters**

```c
/* fix it to a few parameters */
void log3(const char * level, const char * fmt, const char * a, const char * b);
```

**Option 2: pack into CBytes**

```c
/* carry the serialized arguments in CBytes */
void log(const char * level, const char * fmt, CBytes args);
```

**Option 3: array + count**

```c
/* use a fixed upper bound array + a count */
void log(const char * level, const char * fmt, const char ** args, int argc);
/* note: const char ** is rejected (not in the char * family); use CBytes or multiple parameters instead */
```

---

## 9. Comments

### 9.1 Binding rules

| Situation | Bound? |
|------|:----------:|
| The comment sits immediately above the declaration | ✅ |
| Comment → one or more blank lines → declaration | ✅ |
| Comment 1 → Comment 2 → declaration | ✅ (both are bound) |
| Declaration → trailing comment on the same line | ❌ |
| Comment → other non-whitespace token → declaration | ❌ (interrupted) |

```c
/* Wrong — a trailing comment is ignored */
int foo(void); /* this text is lost */

/* Correct — a preceding comment is bound */
/* this text is captured */
int bar(void);
```

### 9.2 Comment styles

All three styles are supported:

1. **`/* ... */`** — block comment.
2. **`// ...`** — line comment.
3. **`/** ... */`** — Doxygen-style block comment (recommended).

### 9.3 Normalization of multi-line comments

The tool chain normalizes multi-line block comments:

- The first line is kept as is.
- Subsequent lines that already carry a `*` prefix are normalized to ` * <content>`.
- Subsequent lines that already carry a `/` prefix (rare) are kept as is.
- Plain text lines get a ` * ` prefix.
- Blank lines stay blank (but consecutive `#10` entries are merged).

**Example**:

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
int add(int a, int b);
```

The normalized `Comment`:
```
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
```

Or, for a simpler form:

```c
/*
   Computes the sum.
   Returns an int.
*/
int add(int a, int b);
```

The normalized `Comment`:
```
/*
 * Computes the sum.
 * Returns an int.
 */
```

### 9.4 Tool-description extraction rules

The tool chain merges the comment into a **single-line tool description**, according to these rules:

1. Split by newline.
2. Skip blank lines.
3. Skip lines starting with `@` (Doxygen tags).
4. Strip leading `*` continuation markers (at most twice).
5. **Take only the first non-empty, non-`@` paragraph**.
6. Truncate to **200 characters**.

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

Result: `Computes the sum of two integers.`

**⚠️ Only the first paragraph is taken** — later `@param` and `Return value` lines do not enter the tool description, but **they do enter parameter-description extraction** (see chapter 10).

**Writing advice**: put the core information in the first paragraph and keep it within 200 characters.

---

## 10. Parameter descriptions

### 10.1 Start-of-line rule

A **parameter name must be at the start of the line** (or directly after a Doxygen tag) to be recognized as a parameter-description line.

```c
/**
 * Computes the sum.
 *
 * a: first addend
 * b: second addend
 *
 * This function is used in many places.
 */
int add(int a, int b);
```

**`a:` and `b:` are at the start of the line** (after ignoring the ` * ` prefix) and are recognized as parameter descriptions. `This function is used in many places.` does not start with a parameter name, so it is not absorbed.

### 10.2 Supported forms

```c
/* Form A: name + colon */
/**
 * a: first addend
 * b: second addend
 */

/* Form B: name + equals sign */
/**
 * a = first addend
 * b = second addend
 */

/* Form C: Doxygen @param */
/**
 * @param a first addend
 * @param b second addend
 */

/* Form D: name + whitespace */
/**
 * a  first addend
 * b  second addend
 */

/* Form E: Doxygen immediate */
/**
 * @a first addend
 * @b second addend
 */

/* Form F: Doxygen keyword variants */
/**
 * \arg a first addend
 * \parameter b second addend
 */
```

**Supported separators**: `:`, `=`, full-width `：`, full-width `＝`.

### 10.3 Case sensitivity

Parameter-name matching is **case-insensitive**.

```c
/**
 * SOURCE: source text
 */
int f(const char * Source);
/* Source.Description = "source text" */
```

### 10.4 Multi-line descriptions

A continuation line must be indented **deeper** than the parameter name (strictly greater).

```c
/**
 * Generates code.
 *
 * target: target language, pick one:
 *           pascal_service   generate Pascal service
 *           pascal_call      generate Pascal call
 *           python_service   generate Python service
 *         <unit> is the normalized UnitName.
 *
 * Return value: the generated code.
 */
int generate(const char * target);
```

`target.Description` =
```
target language, pick one:
           pascal_service   generate Pascal service
           pascal_call      generate Pascal call
           python_service   generate Python service
         <unit> is the normalized UnitName.
```

**⚠️ Strictly greater**: when a continuation line has the same indentation as the declaration line, it is **not** accumulated.

### 10.5 Common misjudgments and fixes

**Misjudgment 1: a natural-language sentence happens to start with a parameter name**

```c
/* Problem — "host can also be an IP address." is absorbed into the description of host */
/**
 * host: host name
 *
 * host can also be an IP address.
 */
int connect(const char * host);
```

**Fixes**:

```c
/* Fix 1: wrap in backticks */
/**
 * host: host name
 *
 * `host` can also be an IP address.
 */

/* Fix 2: increase the indentation (turn it into a continuation line) */
/**
 * host: host name
 *       can also be an IP address.
 */

/* Fix 3: reword the sentence */
/**
 * host: host name
 *
 * The parameter can also be an IP address.
 */
```

**Misjudgment 2: the parameter name appears mid-line**

It is not absorbed, so it is safe.

```c
/**
 * host: host name
 * port: port number
 *
 * This config controls the host and port used by the service.
 */
int connect(const char * host, int port);
```

---

## 11. Return values

### 11.1 Must be written in the signature

**The return type must be declared in the signature**. Writing it only in comments loses it.

```c
/* Wrong — no return type in the signature (impossible in C, but it illustrates the point) */
/* Note: in C every function must have a return type, so this rule is satisfied naturally on the C side */

/* Correct */
int add(int a, int b);
```

**Difference between the C side and the Pascal side**: C syntax requires every function to have a return type, so "lost return type" cannot happen on the C side. But `void` returns deserve special attention:

### 11.2 `void` returns

```c
/* generates a procedure (no return value) */
void log(const char * msg);
void send_bytes(const char * channel, CBytes data);
```

A `void` return is **degraded to a procedure** — the generated code has no return value.

### 11.3 `const` returns

```c
/* const return type — ResultMod='const' */
const char * get_name(void);
```

`const` shows up in two places:

1. `ResultDecl = 'const char *'` (the raw text is preserved).
2. `ResultMod = 'const'` (as a modifier).

**⚠️ Side effect**: when C code is generated, a double `const` can appear:

```c
/* input */
const char * get_name(void);

/* generated C code (may occur) */
const const char * get_name(void);
```

This double `const` is an error for some compilers. **If the target language is C, avoid writing `const` on the return type** — plain `char *` is enough.

### 11.4 Recommended form

```c
/**
 * Gets the error message.
 *
 * code: error code
 *
 * Return value: error description string.
 */
const char * get_error_message(int code);
```

But **if the target is C**, change it to:

```c
/**
 * Gets the error message.
 *
 * code: error code
 *
 * Return value: error description string.
 */
char * get_error_message(int code);
```

---

## 12. Complete examples

### 12.1 Everything accepted

```c
/* sample.h */
#ifndef SAMPLE_H
#define SAMPLE_H

#include <stddef.h>

/**
 * Computes the sum of two integers.
 *
 * a: first addend
 * b: second addend
 *
 * Return value: the sum of a and b.
 */
int add(int a, int b);

/**
 * Computes the product of two integers.
 *
 * @param a first multiplicand
 * @param b second multiplicand
 *
 * Return value: the product of a and b.
 */
int mul(const int a, const int b);

/**
 * Echoes a string.
 *
 * s: string to echo
 *
 * Return value: the same string.
 */
const char * echo(const char * s);

/**
 * Logs a message. No return value.
 *
 * msg: log content
 */
void log(const char * msg);

/**
 * Returns the configuration JSON.
 *
 * Return value: a JSON string.
 */
const char * get_config(void);

/* -- Added in v10: CBytes binary payloads -- */

/**
 * Sends a byte sequence to the given channel.
 *
 * channel: channel name
 * data:    byte sequence to send
 */
void send_bytes(const char * channel, CBytes data);

/**
 * Makes a byte sequence of the given length.
 *
 * n: length
 *
 * Return value: a CBytes of length n.
 */
CBytes make_bytes(int n);

/**
 * Echoes a byte sequence.
 *
 * data: input sequence
 *
 * Return value: the same sequence.
 */
CBytes echo_bytes(CBytes data);

/**
 * Computes the hash of a byte sequence.
 *
 * data: input sequence
 *
 * Return value: hash as a hex string.
 */
char * hash_bytes(CBytes data);

/**
 * Concatenates a byte sequence and a single byte.
 *
 * prefix: prefix
 * suffix: single-byte suffix
 *
 * Return value: concatenated CBytes.
 */
CBytes combine_bytes(CBytes prefix, unsigned char suffix);

#endif /* SAMPLE_H */
```

**Unit name**: `sample` (extracted from `sample.h` or `SAMPLE_H`). The Pascal unit name is `sample_abi_service_unit` — **legal**.

### 12.2 Everything skipped or broken

```c
/* bad.h */

/* function definition — skipped */
int helper(void) { return 42; }

/* boolean return — skipped */
_Bool is_even(int x);

/* struct parameter — skipped */
double dist(struct Point p1, struct Point p2);

/* enum parameter — skipped */
int set_color(enum Color c);

/* wchar_t — skipped */
int print_wide(wchar_t * s);

/* function-pointer parameter — skipped */
void set_callback(void (*cb)(int));

/* variadic — skipped */
int printf_like(const char * fmt, ...);

/* union parameter — skipped */
void set_value(union Value v);

/* non-char pointer — skipped */
void * allocate(int size);
void   use_ptr(int * p);

/* non-byte array — the declaration passes Fill_C, but array semantics are lost in the generation layer */
void fill_buffer(int buf[], int len);

/* multi-dimensional array — skipped */
void matrix(int m[][10], int rows);

/* global variable — skipped */
int global_counter;

/* initialized variable — skipped */
int initialized = 42;

/* struct definition — skipped */
struct Foo { int x; int y; };

/* no file name, no guard — the unit name degrades to untitled.h */
/* the generated Pascal code contains unit untitled.h; — compilation fails */
```

### 12.3 When no legal unit name is provided

```c
/* 1.0.3.h */            /* the file name starts with a digit, not a legal identifier */
#ifndef 1_0_3_H         /* the macro name is not a legal identifier */
#define MAX_SIZE 1024    /* MAX_SIZE is not a guard (no _H suffix) */

int add(int a, int b);
```

The unit name degrades to `untitled.h`. When Pascal code is generated, `unit untitled.h;` **fails to compile**.

**Fix**: add a legal guard on the first line of the header:

```c
/* myunit.h */          /* legal file name */
#ifndef MYUNIT_H        /* legal guard */
#define MYUNIT_H

int add(int a, int b);

#endif /* MYUNIT_H */
```

The unit name becomes `myunit` — legal.

---

## 13. Self-check list

```c
// 1. Is it a function prototype (ending with ;)? Not a definition (no { ... })?
// 2. Is it top-level? Not inside a function body / struct / union / enum / typedef?
// 3. No function-pointer parameters?
// 4. No variadic parameters (...)?
// 5. No multi-dimensional arrays?
// 6. Is every type on the whitelist?
// 7. Do pointers appear only in the char * family?
// 8. Do arrays appear only as unsigned char []?
// 9. Is the comment directly above the declaration, or separated only by blank lines?
// 10. Does every parameter description start at the beginning of a line?
// 11. Are continuation lines of multi-line descriptions indented deeper?
// 12. Does the first comment paragraph carry the core information within the first 200 characters?
// 13. Does the header have a legal file name or include guard (avoiding untitled.h)?
```

| # | Check | What to do if it fails |
|:-:|--------|----------------|
| 1 | Function prototype? | Remove the function body |
| 2 | Top-level? | Move it to the top level |
| 3 | No function pointers? | Carry the handle in a `uint64_t` |
| 4 | No variadic parameters? | Fixed parameters or `CBytes` |
| 5 | No multi-dimensional arrays? | Flatten into `CBytes` |
| 6 | Type on the whitelist? | Switch to integer / float / `char *` / `CBytes` |
| 7 | Pointers only in the `char *` family? | Switch to `char *`, `uint64_t` or `CBytes` |
| 8 | Arrays only as `unsigned char []`? | Switch to `unsigned char []` or `CBytes` |
| 9 | Comment above? | Move the comment above |
| 10 | Parameter name at the start of the line? | Move the name to the start of the line |
| 11 | Continuation lines indented deeper? | Increase the indentation |
| 12 | First paragraph short? | Trim the first paragraph |
| 13 | Legal unit name? | Add `foo.h` + a `FOO_H` guard |

---

## 14. Minimal templates

### 14.1 Scalar signature template

```c
/* my_unit.h */
#ifndef MY_UNIT_H
#define MY_UNIT_H

/**
 * <One sentence describing the function.>
 *
 * a: <description of a>
 * b: <description of b>
 *
 * Return value: <what is returned>.
 */
int my_func(int a, const char * b);

#endif /* MY_UNIT_H */
```

### 14.2 `CBytes` signature template

```c
/* my_bytes_unit.h */
#ifndef MY_BYTES_UNIT_H
#define MY_BYTES_UNIT_H

/**
 * <One sentence describing the function.>
 *
 * data: <description of the byte sequence>
 *
 * Return value: <description of the returned byte sequence>.
 */
CBytes transform_bytes(CBytes data);

#endif /* MY_BYTES_UNIT_H */
```

**Should do**:

- Write comments with `/** ... */`.
- Put parameter descriptions in one block, **with each parameter name starting at the beginning of a line**.
- Write the return type in the signature.
- Indent continuation lines deeper than the parameter names.
- Use `CBytes` to carry binary payloads.
- Use `char *` to carry strings.
- **The header must have a legal file name or an include guard** (to avoid `untitled.h`).

**Should not do**:

- Use function-pointer parameters, variadic parameters or multi-dimensional arrays.
- Use `bool`, `wchar_t`, struct, union, enum, non-char pointers or non-byte arrays.
- Rely on `@return` to provide the return type (even though C already requires a return type in the signature).
- Write illegal identifiers in the first line of the header or in the guard.
- Write `const` on a `char *` return type (to avoid a double `const`).
- Treat `int buf[]` as an array — it becomes a single scalar parameter at the generation layer.

---

## 15. Quick lookup table

| Symptom | Cause | Fix |
|------|------|----------|
| Declaration disappears from the JSON | Not a function prototype (has a body) | Remove `{ ... }` |
| Declaration disappears from the JSON | struct / enum / union / bool / wchar_t | Switch to integer / float / `char *` / `CBytes` |
| Declaration disappears from the JSON | Function-pointer parameter | Carry the handle in a `uint64_t` |
| Declaration disappears from the JSON | Variadic `...` | Fixed parameters or `CBytes` |
| Declaration disappears from the JSON | **Non-char pointer** | **Carry the address in a `uint64_t`, or use `CBytes`** |
| Declaration disappears from the JSON | **Multi-dimensional array** | **Use `CBytes`** |
| **An array parameter becomes a single scalar** | **The `int buf[]` array semantics are lost in the generation layer** | **Use `unsigned char []` or `CBytes`** |
| Parameter description missing | No `@param` / `name:` lines | Add parameter-description lines |
| Parameter description missing | The parameter has no name (`void f(int)`) | Name every parameter |
| Tool description empty | The comment has only `@param` / `@return` | Add a free-text paragraph |
| Tool description truncated | The first paragraph exceeds 200 characters | Trim the first paragraph |
| A trailing comment is ignored | The comment comes after the declaration | Move it above the declaration |
| **The generated Pascal unit name is `untitled.h`** | **The header lacks a legal file name and guard** | **Add `foo.h` + `FOO_H`** |
| **The generated C code has `const const`** | **`const` was written on the return type** | **Remove the `const` from the return type** |
| A duplicate-named function is renamed automatically | The tool chain de-duplicates automatically | Normal behavior (`foo` → `foo1`) |
| Source position is lost after a JSON round trip | Serialization does not include position information | Normal behavior |

---

## 16. Design principles

These rules are not arbitrary; they rest on clear semantic constraints:

1. **Function prototypes only.** The ABI tool chain cares only about functions callable across languages. Type definitions, variables and macros are compile-time concepts with no runtime meaning.

2. **Serializable types only.** The ABI layer must serialize data between languages. Only integers, floats, strings and byte sequences can be serialized. Other types have inconsistent representations across languages, so correct transport cannot be guaranteed.

3. **`char *` is the only reliable string representation.** A C string pointer has clear semantics (terminated by `\0`) and can be serialized as a string across languages. Other pointers (`int *`, `void *`) are in-process addresses with no cross-process meaning.

4. **`CBytes` is a first-class citizen for byte sequences.** Cross-language binary payloads are uniformly expressed as byte sequences. `unsigned char []` is recognized equivalently to `CBytes`; other array types (`int []` etc.) cannot guarantee consistent cross-language element representation and are degraded to scalars.

5. **Function pointers and variadic parameters cannot be serialized.** A function pointer is a code address, and a variadic parameter list has an unknown size. Neither can be expressed in a uniform data format.

6. **Structured comments.** Comments are the only way an AI can understand a declaration. The rules (start-of-line, indentation) exist so that comments can be parsed reliably, not to make life hard for the user.

7. **The unit name must be legal.** Generated Pascal code needs a legal unit name. `untitled.h` is a fallback, not the expected result. **A header must provide a legal file name or include guard when written**.

8. **Silent skipping.** The tool chain's design philosophy is "parse what can be parsed, skip what cannot" — one invalid declaration does not fail the whole header. But that also means errors are easy to overlook, which is why this document spells out the rules.

9. **The first paragraph is the tool description.** The tool description an AI receives is a single line of at most 200 characters. Putting the core information in the first paragraph is a courtesy to the AI reader.

10. **Unreliable array semantics are a known limitation.** C's `int buf[]` becomes a scalar `int` in the tool chain. This is not a bug but a direct consequence of the constraint "only byte arrays can be serialized across languages". **Array parameters must use `unsigned char []` or `CBytes`**.

---

## 17. Revision history

- **v10.0** — Rebuilt from the behavior of the ABI generators. Added support for `CBytes` / `cbytes` binary payloads. Added the complete cross-language type mapping table. Clarified that the `char *` family is the only reliable pointer type, that `unsigned char []` / `CBytes` are the only reliable array types, and that `int buf[]` loses its array semantics. Clarified that function pointers and variadic parameters must be rejected. Clarified the unit-name extraction rules and the severity of the `untitled.h` problem. Added the double-`const` trap for `const` return types. Fully rewritten in Chinese, aimed at writers rather than source-code readers.
- **v9.0** — Condensed version. Examples first.
- **v8.0** — Added array-suffix handling rules.
- **v7.0** — Added the unit-name extraction rules and the tool-description assembly rules.
- **v6.0** — Added guidance on return-value comments.
- **v5.0** — Added multi-line comment normalization rules.
- **v4.0** — Whitelist and blank-line rules.

**This document is the writing contract. Write according to it and declarations will be correctly extracted, normalized and generated; ignore it and declarations will be silently skipped, or the generated code will not match expectations.**
