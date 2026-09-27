# C Declaration Rules for the ABI Toolchain

**Version**: 3.0
**Audience**: AI assistants and engineers writing C headers consumed by `Fill_C` → `Translate_C_Typ_To_Pascal` → `Z.Pascal_Func_Model` → the generator chain.
**Contract**: This document is the parsing contract. Deviating from it causes a declaration to be silently skipped, or a comment to be silently dropped, or a parameter description to be silently lost.

---

## 0. Thirty-Second Reference

### 0.1 What can I write?

```c
/* EXTRACTED: top-level function prototypes ending with ; */
int add(int a, int b);
unsigned int get_count(void);
const char * get_error(int code);

/* EXTRACTED: prototypes inside an extern "C" block (transparent) */
extern "C" {
    int mul(int a, int b);
}
```

```c
/* SKIPPED (silent — no error, no warning) */
int helper(void) { return 42; }          /* function definition */
void set_cb(void (*cb)(int));            /* function pointer parameter */
double dist(struct Point p1, struct Point p2);  /* struct parameter */
int set_color(enum Color c);             /* enum parameter */
_Bool is_even(int x);                    /* bool return */
void * allocate(int size);               /* pointer (rejected downstream) */
int fill(int arr[][10]);                 /* multi-dimensional array */
int printf_like(const char *fmt, ...);   /* variadic */
int global_counter;                      /* global variable */
int initialized = 42;                    /* initialized variable */
struct Point { int x; int y; };          /* type definition */
#include <stdio.h>                       /* preprocessor */
```

### 0.2 What is useful?

| What you want the AI to know | Where to write it |
|------------------------------|-------------------|
| Function purpose | Free-text line(s) in the comment |
| Parameter meaning | `@param name description` lines |
| Return semantics | `@return description` line (comment only) |
| Structured return type | **Signature only** |

The AI sees exactly two things:
- **`Comment`** — the adjacent comment, plain text (max 200 chars for the tool description).
- **`ReturnType`** — normalized from the signature.

`@param` and `@return` lines are stripped from the tool description; they only feed `Params[i].Description`. Free-text lines (no `@`) are what ends up in the tool description.

---

## 1. Position

### 1.1 Rule

Must be a **top-level function prototype ending with `;`**, not a definition, not inside a type block, not a variable.

### 1.2 Examples

```c
/* test.h */

#include <stdio.h>                       /* SKIP: preprocessor */
#define MAX_SIZE 1024                    /* SKIP: preprocessor */

/* EXTRACT: top-level prototype */
int add(int a, int b);

/* SKIP: function definition with body */
int sub(int a, int b) {
    return a - b;
}

/* SKIP: struct definition */
struct Point { int x; int y; };

/* SKIP: enum definition */
enum Color { RED, GREEN, BLUE };

/* SKIP: global variable */
int global_counter;

/* SKIP: initialized variable */
int initialized = 42;

/* EXTRACT: prototype inside extern "C" (transparent block) */
extern "C" {
    int mul(int a, int b);
    int divi(int a, int b);
}
```

---

## 2. Parameter Modifiers

### 2.1 Rule

| Modifier | Allowed? | Effect |
|----------|:--------:|--------|
| (blank) | ✅ | value passing |
| `const` | ✅ | kept, prefixed to the type |
| `restrict` / `__restrict` / `__restrict__` | ✅ | **silently stripped** |
| `volatile` | ✅ | kept in the type text |
| `var` / `out` | ❌ | whole declaration skipped (defensive check) |

### 2.2 Examples

```c
/* OK */
int add(int a, int b);
int mul(const int a, const int b);
int echo(const char * s);

/* const in prefix, suffix, and pointer-post forms — all recognized */
int f1(const char * s);
int f2(char const * s);
int f3(int * const p);

/* restrict is stripped before type mapping */
int memcpy_opt(void * restrict dst, const void * restrict src, size_t n);

/* SKIPPED — defensive check for Pascal-only modifiers in a C file */
int bad(var x);
```

### 2.3 Pointer caveat

After `restrict` is stripped, `void *` still maps to `Pointer`, which is **rejected by the Pascal-side whitelist**. See §3.3.

---

## 3. Type Whitelist

### 3.1 Allowed types

| Family | Types |
|--------|-------|
| Signed integers | `signed char`, `short`, `int`, `long`, `long long`, `int8_t`, `int16_t`, `int32_t`, `int64_t` |
| Unsigned integers | `unsigned char`, `unsigned short`, `unsigned int`, `unsigned long`, `unsigned long long`, `uint8_t`, `uint16_t`, `uint32_t`, `uint64_t` |
| Pointer-width integers | `size_t`, `uintptr_t`, `ssize_t`, `ptrdiff_t`, `intptr_t` |
| Floating point | `float`, `double`, `long double` |
| Strings | `char *`, `const char *`, `char const *` |
| Void | `void` (return type only) |

### 3.2 C-to-Pascal mapping

| C type | `tnf_Json` | `tnf_ABI` | JSON Schema |
|--------|:----------:|:---------:|:-----------:|
| `signed char` / `int8_t` | `int64` | `shortint` | `integer` |
| `short` / `int16_t` | `int64` | `smallint` | `integer` |
| `int` / `int32_t` | `int64` | `integer` | `integer` |
| `long` / `long long` / `int64_t` | `int64` | `longint` / `int64` | `integer` |
| `unsigned char` / `uint8_t` | `int64` | `byte` | `integer` |
| `unsigned short` / `uint16_t` | `int64` | `word` | `integer` |
| `unsigned int` / `uint32_t` | `int64` | `cardinal` | `integer` |
| `unsigned long` | `int64` | `longword` | `integer` |
| `unsigned long long` / `uint64_t` | `int64` | `uint64` | `integer` |
| `size_t` / `uintptr_t` | `int64` | `uint64` | `integer` |
| `ssize_t` / `ptrdiff_t` / `intptr_t` | `int64` | `int64` | `integer` |
| `float` | `double` | `single` | `number` |
| `double` | `double` | `double` | `number` |
| `long double` | `double` | `extended` | `number` |
| `char *` / `const char *` | `string` | `string` | `string` |
| `void` (return) | dropped → procedure | dropped → procedure | — |
| **Any other `T *`** | maps to `Pointer` | maps to `Pointer` | **REJECTED** |

### 3.3 Forbidden types

These cause the whole declaration to be skipped.

| Category | Example |
|----------|---------|
| Struct / union | `struct Point`, `union Value` |
| Enum | `enum Color` |
| Boolean | `bool`, `_Bool` |
| Wide character | `wchar_t`, `char16_t`, `char32_t` |
| Unmapped typedef | any custom alias |
| Variadic | `...` |
| Function pointer parameter | `void (*cb)(int)` |
| **Any pointer** | `void *`, `int *`, `const void *` |

### 3.4 The pointer trap

`void *` walks through three layers before it dies:

```
C source      Fill_C accepts  →  Translate maps to Pointer  →  Model rejects
```

C accepts it, Pascal accepts the mapping, the Model silently drops the declaration. **C-side acceptance ≠ Pascal-side acceptance**.

```c
/* WRONG — silently dropped downstream */
void * allocate(int size);
void   fill(void * dst, size_t n);
int    read(int * p);

/* RIGHT — carry the address as an integer */
uint64_t allocate(int size);
void     fill(uint64_t dst, size_t n);
int      read(uint64_t p);
```

### 3.5 Array parameters

Single-level array suffixes (`[]`, `[N]`, `[N]`) are captured into `param_array` and survive `Fill_C` and `decl_to_c`. Multi-dimensional arrays (`int arr[][]`) are rejected at `Fill_C`.

```c
/* EXTRACTED — single-level suffix */
void fill_buffer(int buf[], int len);
void write_block(int buf[16], int n);

/* SKIPPED — multi-dimensional array */
void matrix(int m[][10], int rows);
```

**Downstream note**: even single-level array parameters are rejected by `Z.Pascal_Func_Model` because `array of Integer` is not on the Pascal whitelist. Array parameters are useful only if you generate C (`decl_to_c`), not if you generate Pascal or JSON.

---

## 4. Comments

### 4.1 Binding rules

| Situation | Bound? |
|-----------|:------:|
| Comment directly above declaration | ✅ |
| Comment → blank line → declaration | ✅ |
| Comment1 → Comment2 → declaration | ✅ (both) |
| Declaration → trailing comment | ❌ |

```c
/* WRONG — trailing comment is ignored */
int foo(void); /* this text is lost */

/* RIGHT — preceding comment is bound */
/* this text is captured */
int bar(void);
```

### 4.2 Comment styles

1. **Doxygen `/** ... */`** — recommended. ` * ` continuation prefixes are stripped automatically.
2. **Plain `/* ... */`** — OK.
3. **`// ...`** — OK for single lines.

### 4.3 Doxygen continuation prefixes are stripped

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
int add(int a, int b);
```

The ` * ` prefix on each line is automatically removed before parameter-description extraction. The `Comment` metadata stores each line with a ` * ` prefix; the Model layer strips them.

### 4.4 Tool description extraction

The generator collects the comment into a **single-line tool description**:

1. Split by newline.
2. Skip empty lines.
3. **Skip lines starting with `@`** (Doxygen tag lines).
4. Strip leading `*` continuation markers.
5. Join with spaces.
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

Result:
```
Computes the sum of two integers. Return value: an Integer representing the sum.
```

The `@param` and `@return` lines are stripped from the tool description. They still feed `Params[i].Description`.

### 4.5 Practical shape

```c
/**
 * <One sentence describing the function.>
 *
 * @param a <description of a>
 * @param b <description of b>
 * @return <description of the return value>
 */
int my_func(int a, int b);
```

| Line | Feeds | Reaches tool description? |
|------|-------|:------------------------:|
| First sentence (no `@`) | Tool description | ✅ |
| `@param ...` | `Params[i].Description` | ❌ |
| `@return ...` | Only `Comment` | ❌ |

---

## 5. Unit Name Extraction

### 5.1 Priority order

1. **`.h` / `.c` filename** inside the first 100 lines (e.g. `/* foo.h */` → `foo`).
2. **Include guard name** from `#ifndef` / `#ifdef` / `#define` (`FOO_H` → `FOO`).
3. **Fallback**: `untitled.h`.

### 5.2 Guard suffix stripping

Recognized suffixes (longest first): `_INCLUDED`, `_HXX`, `_HPP`, `_H__`, `_H_`, `_H`. Leading and trailing underscores are also stripped.

### 5.3 Examples

| Header | Unit name |
|--------|-----------|
| `/* foo.h */` + `#ifndef FOO_H` | `foo` |
| `#ifndef FOO_H` | `FOO` |
| `#ifndef __FOO_H__` | `FOO` |
| `#ifndef FOO_INCLUDED` | `FOO` |
| `#define MAX_SIZE 1024` (not a guard) | `untitled.h` |
| `/* 1.0.3.h */` (invalid identifier) | `untitled.h` |

Prefer `foo.h` and a matching `FOO_H` guard. Avoid numeric-prefixed filenames.

---

## 6. Complete Examples

### 6.1 Every declaration extracted

```c
/* sample.h */
#ifndef SAMPLE_H
#define SAMPLE_H

#include <stddef.h>

/** Computes the sum of two integers. */
int add(int a, int b);

/** Unsigned integer example. */
unsigned int get_unsigned(void);

/** 64-bit signed integer. */
long long get_longlong(void);

/** Single precision float. */
float get_float(void);

/** Double precision float. */
double get_double(void);

/**
 * Gets an error message.
 * @param code error code
 * @return error description string
 */
const char * get_error_message(int code);

#endif /* SAMPLE_H */
```

### 6.2 Every declaration skipped or broken

```c
/* bad.h */

/** SKIP: function definition with body. */
int internal_helper(void) { return 42; }

/** SKIP: boolean return. */
_Bool is_even(int x);

/** SKIP: struct parameter. */
double distance(struct Point p1, struct Point p2);

/** SKIP: enum parameter. */
int set_color(enum Color c);

/** SKIP: wide char. */
int print_wide(wchar_t * s);

/** SKIP: function pointer parameter. */
void set_callback(void (*cb)(int));

/** SKIP: variadic. */
int printf_like(const char * fmt, ...);

/** SKIP: union parameter. */
void set_value(union Value v);

/** SKIP: pointer parameter — maps to Pointer, rejected by the Model. */
void * allocate(int size);
void   use_ptr(int * p);

/** SKIP: multi-dimensional array. */
void matrix(int m[][10], int rows);

/** SKIP: global variable. */
int global_counter;

/** SKIP: initialized variable. */
int initialized = 42;

/** SKIP: struct definition. */
struct Foo { int x; int y; };
```

---

## 7. Self-Check

```c
// 1. Ends with a semicolon (prototype, not definition)?
// 2. Top-level (not inside a function body, struct, or typedef)?
// 3. No function-pointer parameter?
// 4. Every type in the whitelist (no pointers, no structs, no enums, no bool)?
// 5. Comment directly above (blank lines allowed)?
```

| # | Check | Action if failed |
|:-:|-------|------------------|
| 1 | Prototype (ends with `;`)? | Remove the body |
| 2 | Top-level? | Move out of function / type block |
| 3 | No function pointer? | Use an integer handle |
| 4 | Whitelisted types only? | Use integer / float / string (no pointers) |
| 5 | Comment directly above? | Move the comment above |

---

## 8. Minimal Template

```c
/* my_unit.h */
#ifndef MY_UNIT_H
#define MY_UNIT_H

/**
 * <One sentence describing the function.>
 *
 * @param a <description of a>
 * @param b <description of b>
 * @return <description of the return value>
 */
int my_func(int a, int b);

#endif /* MY_UNIT_H */
```

**Do**:

- Use `/** ... */` Doxygen comments.
- Put `@param` and `@return` on their own lines.
- Declare the return type in the signature.
- Use only integer / float / string types.

**Don't**:

- Use `void *`, `int *`, or any pointer.
- Use `struct`, `enum`, `union`, `bool`, `wchar_t`.
- Use function pointers or variadic (`...`).
- Write multi-dimensional arrays.
- Put a function body after the prototype.

---

## 9. Quick Lookup Table

| Symptom | Cause | Fix |
|---------|-------|-----|
| Declaration missing from JSON | Not a prototype, or has a body | Remove `{ ... }` |
| Declaration missing | Struct / enum / union / bool / wide char | Switch to integer / float / string |
| Declaration missing | Function pointer parameter | Use an integer handle |
| Declaration missing | Variadic `...` | Use fixed parameters |
| Declaration missing | **Pointer parameter** | **Use `uint64_t` to carry the address** |
| Declaration missing | Multi-dimensional array | Use single-level `[]` or an integer handle |
| Parameter description missing | No `@param` line | Add `@param name description` |
| Parameter description missing | Parameter has no name | Name every parameter |
| Tool description empty | Only `@param` / `@return` lines | Add a free-text first line |
| Unit name is `untitled.h` | Filename or guard invalid | Rename to `foo.h` with `FOO_H` |
| Trailing comment ignored | Comment is after the declaration | Move it above |

---

## 10. Design Notes

The chain has six hard assumptions:

1. **Prototypes only.** Definitions, type blocks, variables, and preprocessor lines are ignored.
2. **Mappable types only.** Every parameter and return type must map to the Pascal whitelist.
3. **Single-level arrays only.** Multi-dimensional arrays are rejected at `Fill_C`.
4. **Function pointers excluded.** A function pointer cannot be represented as a JSON value type.
5. **Pointers excluded downstream.** `void *` reaches `Pointer`, which is not on the Pascal whitelist.
6. **Silent skip.** Anything that violates the contract is dropped with a note in the `Report`; no exception is raised.

---

## 11. Revision

- **v3.0** — Condensed from v2.0. Example-first. Every rule demonstrated in code.
- **v2.0** — Cross-layer pointer rejection; two-stage type normalization; tool-description concatenation; common reading-mistake scenarios.
- **v1.0** — First version aligned with `Fill_C.inc` and `Translate_C_Typ_To_Pascal.inc`.

**This document is the parsing contract. Any deviation causes a declaration to be silently skipped, a comment to be silently dropped, or a parameter description to be silently lost.**