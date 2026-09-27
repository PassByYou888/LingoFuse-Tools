# C Declaration Rules for the code_decl_to_json_abi Toolchain

**Version**: 4.0 (example-first rewrite)
**Applies to**: `Fill_C` → `Translate_C_Typ_To_Pascal` → `Z.Pascal_Func_Model` → all generators
**Rule**: If you write it right, it is extracted. If you write it wrong, the whole declaration is **silently skipped** or its information is **silently lost**. No error, no warning.

---

## 0. The 60-Second Version

Write every prototype like this:

```c
/* my_module.h */
#ifndef MY_MODULE_H
#define MY_MODULE_H

/**
 * Adds two integers and returns the sum.
 * @param a first addend
 * @param b second addend
 * @return the sum of a and b
 */
int add(int a, int b);

#endif /* MY_MODULE_H */
```

That is the whole spec. The rest of this document explains **why** each line matters, with side-by-side ✅/❌ examples.

---

## 1. Position — Where the Prototype Lives

### 1.1 Only these positions are extracted

```c
/* position_demo.h */
#ifndef POSITION_DEMO_H
#define POSITION_DEMO_H

#include <stdio.h>            /* ❌ SKIP — preprocessor */
#define MAX_SIZE 1024         /* ❌ SKIP — preprocessor */

/* ✅ EXTRACT — top-level function prototype */
int add(int a, int b);

/* ❌ SKIP — function definition with body */
int sub(int a, int b) {
    return a - b;
}

/* ❌ SKIP — struct definition */
struct Point {
    int x;
    int y;
};

/* ❌ SKIP — global variable */
int global_counter;

/* ❌ SKIP — initialized variable */
int initialized = 42;

/* ✅ EXTRACT — prototype inside extern "C" block */
extern "C" {
    int mul(int a, int b);
}

#endif /* POSITION_DEMO_H */
```

### 1.2 Position matrix — one table

| Position | Verdict | Example |
|----------|:-------:|---------|
| Top-level prototype | ✅ EXTRACT | `int add(int a, int b);` |
| Inside `extern "C" { ... }` | ✅ EXTRACT | `extern "C" { int foo(void); }` |
| Preprocessor line | ❌ SKIP | `#include <stdio.h>` |
| `struct` / `enum` / `union` / `typedef` block | ❌ SKIP | `struct Point { int x; };` |
| Global variable | ❌ SKIP | `int global_var;` |
| Variable with initializer | ❌ SKIP | `int x = 42;` |
| Function definition with `{ ... }` body | ❌ SKIP | `int f() { return 1; }` |
| Function-pointer parameter | ❌ SKIP | `void set_cb(void (*cb)(int));` |

### 1.3 The four position rules

| Rule | Consequence if violated |
|------|-------------------------|
| Must end with `;` (prototype, not definition) | Whole declaration skipped |
| Must be top-level (not inside a function body / type definition) | Whole declaration skipped |
| Must be a function prototype (not a variable, macro, or type) | Whole declaration skipped |
| `extern "C"` is a transparent block — inner content is scanned as top-level | (No rule to violate) |

---

## 2. Parameter Modifiers — Which Ones Are Allowed

### 2.1 The modifier matrix

| Modifier | Verdict | What happens |
|----------|:-------:|--------------|
| *(nothing)* | ✅ | Value passing |
| `const` | ✅ | **Kept** — prefixed to the type |
| `restrict` / `__restrict` / `__restrict__` | ✅ | **Stripped silently** |
| `volatile` | ✅ | Kept in the parameter's type text; filtered from return type |
| `var` (Pascal syntax) | ❌ | Whole declaration skipped (defensive check) |
| `out` (Pascal syntax) | ❌ | Whole declaration skipped (defensive check) |

### 2.2 `const` in three positions — all recognized

```c
/* ✅ Prefix form */
int foo(const char * s);

/* ✅ Suffix form (equivalent) */
int foo(char const * s);

/* ✅ Pointer-post form */
int bar(int * const p);
```

All three are marked as `const` in `param_mod`.

### 2.3 `restrict` is silently stripped

```c
/* Input */
void * memcpy_opt(void * restrict dst, const void * restrict src, size_t n);

/* After stripping */
/* dst: void *              src: const void *          n: uint64 */
```

**Why strip**: `restrict` is an optimization hint, not part of the prototype's semantics. Passing it downstream would pollute the type text and break later mapping.

> ⚠️ Note: even after stripping, `void *` becomes `Pointer`, which is **still rejected** by the model layer. See §3.4.

### 2.4 Modifier examples — pass vs skip

```c
// ✅ PASS — no modifier
int f1(int x);

// ✅ PASS — const kept
int f2(const int x);

// ✅ PASS — restrict stripped (but pointer still rejected at model layer)
int f3(int * restrict p);

// ✅ PASS — string pointer + const
int f4(const char * s);

// ✅ PASS — pointer-post const
int f5(int * const p);

// ✅ PASS — volatile kept in parameter type
int f6(volatile int x);

// ❌ SKIP — defensive check catches Pascal-only syntax
int f7(var int x);
int f8(out int y);
```

---

## 3. Types — The Whitelist

### 3.1 Allowed types

```c
/* ✅ integers — all become int64 in the model */
int          a1(int x);
signed char  a2(signed char x);
short        a3(short x);
long         a4(long x);
long long    a5(long long x);
int8_t       a6(int8_t x);
int16_t      a7(int16_t x);
int32_t      a8(int32_t x);
int64_t      a9(int64_t x);

unsigned char      b1(unsigned char x);
unsigned short     b2(unsigned short x);
unsigned int       b3(unsigned int x);
unsigned long      b4(unsigned long x);
unsigned long long b5(unsigned long long x);
uint8_t            b6(uint8_t x);
uint16_t           b7(uint16_t x);
uint32_t           b8(uint32_t x);
uint64_t           b9(uint64_t x);

size_t     c1(size_t x);
uintptr_t  c2(uintptr_t x);
ssize_t    c3(ssize_t x);
ptrdiff_t  c4(ptrdiff_t x);
intptr_t   c5(intptr_t x);

/* ✅ floats — all become double in the model */
float       d1(float x);
double      d2(double x);
long double d3(long double x);

/* ✅ strings — all become string in the model */
char *             e1(char * s);
const char *       e2(const char * s);
char const *       e3(char const * s);

/* ✅ void return — becomes a procedure */
void f1(void);
```

### 3.2 Banned types — every one kills the whole declaration

```c
/* ❌ Boolean */
_Bool is_even(int x);

/* ❌ struct */
double distance(struct Point p1, struct Point p2);

/* ❌ union */
void set_value(union Value v);

/* ❌ enum */
int set_color(enum Color c);

/* ❌ wide character */
int print_wide(wchar_t * s);

/* ❌ custom typedef (unmapped alias) */
int foo(MyCustomType x);

/* ❌ variadic */
int printf_like(const char * fmt, ...);

/* ❌ function pointer */
void set_callback(void (*cb)(int));

/* ❌ pointer — see §3.4 */
void * allocate(int size);
void int_ptr_param(int * p);
void restrict_param(void * restrict p);
```

### 3.3 Common rewrite patterns

```c
// ❌ Boolean → ✅ int (0 = false, 1 = true)
_Bool is_even(int x);          // SKIP
int   is_even(int x);          // PASS — returns 0 or 1
```

```c
// ❌ struct → ✅ separate scalar parameters or a JSON string
double distance(struct Point p1, struct Point p2);   // SKIP
double distance(int x1, int y1, int x2, int y2);     // PASS
double distance(const char * points_json);           // PASS — pass '[[1,2],[3,4]]'
```

```c
// ❌ enum → ✅ int (pass the ordinal)
int set_color(enum Color c);   // SKIP
int set_color(int c);          // PASS
```

```c
// ❌ wide char → ✅ char *
int print_wide(wchar_t * s);   // SKIP
int print_utf8(char * s);      // PASS
```

```c
// ❌ variadic → ✅ fixed parameters
int printf_like(const char * fmt, ...);              // SKIP
int log_message(const char * fmt, const char * arg); // PASS
```

```c
// ❌ pointer → ✅ uint64_t address
void * allocate(int size);     // SKIP
uint64_t allocate(int size);   // PASS
```

```c
// ❌ pointer parameter → ✅ int array or separate values
int sum(int * arr, int n);     // SKIP
int sum(int a, int b, int c);  // PASS
int sum(const char * arr_json);// PASS — pass '[1,2,3]'
```

### 3.4 🔴 The `void *` trap — "C accepts it, the model does not"

`void *` parameters go through **three stages**, and the third stage rejects them:

```c
/* How you might write it */
void * allocate(int size);
```

| Stage | Result |
|:-----:|:-------|
| `Fill_C` | ✅ Accepts the prototype |
| `Translate_C_Typ_To_Pascal` | `void *` → `Pointer` |
| `Z.Pascal_Func_Model` | ❌ `Pointer` is **not** in the whitelist → **whole declaration skipped** |

**What the Report shows**:

```
Skipped: "allocate" - Reason: Parameter "p" has unsupported type "Pointer"
```

**The correct rewrite**:

```c
/* ✅ Correct — carry the address as uint64_t */
uint64_t allocate(int size);
```

**Every pointer form is affected**:

```c
void * allocate(int size);                    // ❌ SKIP
void int_ptr_param(int * p);                  // ❌ SKIP
void restrict_param(void * restrict p);       // ❌ SKIP
const void * get_data(void);                  // ❌ SKIP
```

### 3.5 Type mapping — C to Pascal, in one table

| C type | Model value (typical mode) | Model value (ABI mode) | JSON Schema | Verdict |
|--------|:--------------------------:|:----------------------:|:-----------:|:-------:|
| `signed char` / `int8_t` | `int64` | `shortint` | `integer` | ✅ |
| `short` / `int16_t` | `int64` | `smallint` | `integer` | ✅ |
| `int` / `int32_t` | `int64` | `integer` | `integer` | ✅ |
| `long` | `int64` | `longint` | `integer` | ✅ |
| `long long` / `int64_t` | `int64` | `int64` | `integer` | ✅ |
| `unsigned char` / `uint8_t` | `int64` | `byte` | `integer` | ✅ |
| `unsigned short` / `uint16_t` | `int64` | `word` | `integer` | ✅ |
| `unsigned int` / `uint32_t` | `int64` | `cardinal` | `integer` | ✅ |
| `unsigned long` | `int64` | `longword` | `integer` | ✅ |
| `unsigned long long` / `uint64_t` | `int64` | `uint64` | `integer` | ✅ |
| `size_t` / `uintptr_t` | `int64` | `uint64` | `integer` | ✅ |
| `ssize_t` / `ptrdiff_t` / `intptr_t` | `int64` | `int64` | `integer` | ✅ |
| `float` | `double` | `single` | `number` | ✅ |
| `double` | `double` | `double` | `number` | ✅ |
| `long double` | `double` | `extended` | `number` | ✅ |
| `char *` / `const char *` / `char const *` | `string` | `string` | `string` | ✅ |
| Any other `T *` (including `void *`) | `Pointer` | `Pointer` | — | ❌ **REJECTED** |
| `void` (return type) | demotes to procedure | demotes to procedure | — | ✅ |

---

## 4. Array Suffixes — Single Layer Only

### 4.1 Array suffix recognition

```c
/* Input */
void fill_buffer(int buf[], int len);

/* How it is split internally */
/* param_name  = buf       */
/* param_typ   = int       */
/* param_array = []        */
```

| Input | `param_array` |
|-------|:-------------:|
| `int buf[]` | `[]` |
| `int buf[10]` | `[10]` |
| `int buf[N]` | `[N]` |
| `int buf` | *(no suffix)* |

### 4.2 🔴 Arrays are C-only — they do not survive the model layer

An array parameter is valid in `Fill_C` and in `decl_to_c`, but becomes `array of Integer` after translation, which the model layer **rejects**.

```c
void fill_buffer(int buf[], int len);
```

| Stage | Result |
|:-----:|:------:|
| `Fill_C` | ✅ Extracted |
| `Translate_C_Typ_To_Pascal` | ✅ Extracted (`array of Integer`) |
| `Z.Pascal_Func_Model` | ❌ **Skipped** |

**Rule of thumb**:
- **Only C output needed** (`decl_to_c`): array parameters are fine.
- **JSON output needed** (MCP tool): rewrite as scalar parameters or a JSON string.

### 4.3 Multi-dimensional arrays — not supported

```c
void matrix(int m[10][20]);   // ❌ SKIP
void matrix2(int m[][]);      // ❌ SKIP
```

**Why**: the array-suffix extractor handles a single `[...]` layer. Two nested suffixes leave the parser unable to find the parameter name.

**Workarounds**: single-layer array, or a JSON string.

### 4.4 Array examples

```c
/* ✅ PASS — but only reaches the C side */
void fill_buffer(int buf[], int len);

/* ✅ PASS — but only reaches the C side */
void copy_10(int dst[10], int src[10]);

/* ❌ SKIP — multi-dimensional */
void matrix(int m[10][20]);
```

---

## 5. Comments — How to Write Them

### 5.1 Three accepted styles

```c
/* ✅ Single-line // */
// Computes the sum of two integers.
int add(int a, int b);
```

```c
/* ✅ Block /* */
/* Computes the sum of two integers. */
int add(int a, int b);
```

```c
/* ✅ Doxygen (recommended) */
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
int add(int a, int b);
```

All three are bound to the declaration. Use whichever is most natural — but see §5.8 for why Doxygen is preferred.

### 5.2 Binding rules — one table

| Situation | Bound? | Comment |
|-----------|:------:|---------|
| Comment immediately above | ✅ | Standard |
| Blank line, then comment above | ✅ | Blank line is skipped |
| Comment 1 → Comment 2 → declaration | ✅ | Both merged |
| Comment 1 → blank → Comment 2 → declaration | ✅ only Comment 2 | Comment 1 is ignored |
| Trailing comment (after declaration) | ❌ | Ignored |

### 5.3 Blank line handling

```c
/* ✅ The comment is bound — the blank line is skipped */
/* This is the comment. */

int add(int a, int b);
```

```c
/* ⚠️ Only the nearest comment is bound */
/* First comment. */

/* Second comment. */

int add(int a, int b);
/* Comment = "Second comment." */
```

### 5.4 Trailing comment — ignored

```c
/* ❌ Trailing comment is NOT bound */
int add(int a, int b);  // This comment is IGNORED
/* Comment = "" */
```

### 5.5 Multi-line comments — normalized automatically

```c
/* Input */
/* This is a comment
   that spans multiple
   lines */
int foo(void);
```

Internally becomes (Pascal style, second line onward carries a ` * ` prefix):

```
{ This is a comment
 * that spans multiple
 * lines }
```

**You do not need to worry about the ` * ` prefix** — the model layer strips it automatically.

### 5.6 Doxygen — `@param` goes to the parameter description

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
int add(int a, int b);
```

| Content | Where it goes |
|---------|---------------|
| `Computes the sum of two integers.` | tool description |
| `@param a first addend` | `Params[0].Description = "first addend"` |
| `@param b second addend` | `Params[1].Description = "second addend"` |
| `@return the sum` | **Skipped** — does not enter the tool description |

Resulting tool description: `"Computes the sum of two integers."`

### 5.7 🔴 The most common mistake: only `@param` lines, no free text

```c
/* ❌ Produces an EMPTY tool description */
/**
 * @param code error code
 * @return error description
 */
const char * get_error_message(int code);
```

Result:
- `Params[0].Description = "error code"` — fine.
- tool description = `""` — **empty**.

**Why**: `GetFullDescription` skips any line starting with `@`. If every line starts with `@`, the resulting description is empty.

**Fix** — add one line of free text:

```c
/* ✅ Produces a non-empty description */
/**
 * Gets an error message.
 * @param code error code
 * @return error description
 */
const char * get_error_message(int code);
```

tool description = `"Gets an error message."`

### 5.8 `@param` / `@return` — one-line reference

| Line style | Feeds the tool description? | Feeds the parameter description? |
|------------|:---------------------------:|:--------------------------------:|
| Plain text (no `@`) | ✅ | ❌ |
| `@param name ...` | ❌ (skipped) | ✅ for that parameter |
| `@return ...` | ❌ (skipped) | ❌ (no return-description field exists) |
| `Return value: ...` | ✅ (kept) | ❌ |

**Rule of thumb**:
- **The tool description** should include one or two lines of free text describing the purpose.
- **Parameter descriptions** should use `@param name description`.
- **Return value description** has no structured field. If you write it in the comment (e.g. `Return value: ...`), it stays in the `Comment` text but does not enter any structured field.

### 5.9 Return value — the golden rule

**The return type must be declared in the prototype.** The comment is only a supplement.

```c
/* ✅ Correct — return type in the signature */
/**
 * Adds two integers.
 * @return the sum
 */
int add(int a, int b);
/* Model: ReturnType = "int64" */
```

```c
/* ❌ A prototype with no return type is a syntax error */
/**
 * @return the sum
 */
add(int a, int b);   /* missing "int" */
```

**The model has no field for the return-value description.** If the return value has important semantics, put them in the comment's free text.

---

## 6. Unit Name Extraction

### 6.1 The three priorities

```c
/* Priority 1: a .h / .c filename in the header */
/* foo.h */
#ifndef FOO_H
#define FOO_H
...
/* → unit name = "foo" */

/* Priority 2: a #ifndef / #ifdef guard macro */
#ifndef BAR_H
#define BAR_H
...
/* → unit name = "BAR" */

/* Priority 3: fallback */
/* → unit name = "untitled.h" */
```

### 6.2 Extraction examples — one table

| Header content | Result | Verdict |
|----------------|--------|:-------:|
| `/* foo.h */` | `foo` | ✅ |
| `// bar.c` | `bar` | ✅ |
| `#ifndef FOO_H` | `FOO` | ✅ |
| `#ifndef __FOO_H__` | `FOO` | ✅ |
| `#ifndef FOO_HPP` | `FOO` | ✅ |
| `#ifndef FOO_INCLUDED` | `FOO` | ✅ |
| `#ifndef FOO_HXX` | `FOO` | ✅ |
| `#define MAX_SIZE 1024` | `untitled.h` | ⚠️ not a guard name |
| `/* 1.0.3.h */` | `untitled.h` | ⚠️ starts with a digit |
| *(empty file)* | `untitled.h` | ⚠️ fallback |

### 6.3 Guard suffix stripping

The following suffixes are stripped (longest first):

- `_INCLUDED`
- `_HXX`, `_HPP`
- `_H__`, `_H_`, `_H`

Surrounding underscores are also stripped.

| Input | Result |
|-------|--------|
| `FOO_INCLUDED` | `FOO` |
| `__FOO_H__` | `FOO` |
| `FOO_HPP` | `FOO` |
| `MY_MODULE_H` | `MY_MODULE` |

### 6.4 Practical naming advice

- **Prefer** `foo.h`, `calculator.h`, `my_module.h`.
- **Avoid** `1.0.3.h`, `v2.h`, filenames starting with digits.
- **Always add an include guard** with a name that ends in `_H` / `_HPP` / `_INCLUDED`.

---

## 7. Full Worked Examples

### 7.1 A fully compliant header

```c
/* calculator.h */
#ifndef CALCULATOR_H
#define CALCULATOR_H

#include <stddef.h>

/**
 * Adds two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum as an int
 */
int add(int a, int b);

/**
 * Multiplies two integers.
 * @param a first multiplicand
 * @param b second multiplicand
 * @return the product as an int
 */
int mul(int a, int b);

/**
 * Returns the size of a buffer.
 * @return the size in bytes
 */
size_t buffer_size(void);

/**
 * Gets an error message for the given code.
 * @param code the error code
 * @return the message string
 */
const char * get_error_message(int code);

/**
 * Logs a message.
 * @param msg the message to log
 */
void log_message(const char * msg);

#endif /* CALCULATOR_H */
```

Parsing result:

| Declaration | C stage | Pascal stage | JSON stage |
|-------------|:-------:|:------------:|:----------:|
| `int add(int a, int b)` | ✅ | ✅ | ✅ |
| `int mul(int a, int b)` | ✅ | ✅ | ✅ |
| `size_t buffer_size(void)` | ✅ | ✅ | ✅ |
| `const char * get_error_message(int code)` | ✅ | ✅ | ✅ |
| `void log_message(const char * msg)` | ✅ | ✅ | ✅ |

### 7.2 A header with everything wrong

```c
/* bad.h */

/* ❌ SKIP — function definition */
int internal_helper(void) {
    return 42;
}

/* ❌ SKIP — Boolean return */
_Bool is_even(int x);

/* ❌ SKIP — struct parameter */
double distance(struct Point p1, struct Point p2);

/* ❌ SKIP — enum parameter */
int set_color(enum Color c);

/* ❌ SKIP — wide char */
int print_wide(wchar_t * s);

/* ❌ SKIP — function pointer parameter */
void set_callback(void (*cb)(int));

/* ❌ SKIP — variadic */
int printf_like(const char * fmt, ...);

/* ❌ SKIP — union parameter */
void set_value(union Value v);

/* ❌ SKIP — pointer parameter */
void * allocate(int size);
void int_ptr_param(int * p);

/* ❌ SKIP — global variable */
int global_counter;

/* ❌ SKIP — initialized variable */
int initialized = 42;

/* ❌ SKIP — struct definition */
struct Foo {
    int x;
    int y;
};
```

Every declaration here fails. The Report lists each one with a reason.

### 7.3 A header with subtle issues

```c
/* subtle.h */
#ifndef SUBTLE_H
#define SUBTLE_H

/* ⚠️ Array parameter — passes C, rejected by the model layer */
void fill_buffer(int buf[], int len);

/* ⚠️ Only @param lines, no free text — the tool description will be empty */
/**
 * @param code error code
 * @return error description
 */
const char * get_error_message(int code);

/* ⚠️ Multi-dimensional array — SKIP */
void matrix(int m[10][20]);

/* ⚠️ Pointer as address — needs rewriting */
uint64_t allocate_ok(int size);   /* ✅ correct */
void *    allocate_bad(int size); /* ❌ skipped */

#endif /* SUBTLE_H */
```

---

## 8. Rewrite Cheat Sheet

| Wrong | Right |
|-------|-------|
| `int f() { ... }` | `int f(void);` (prototype) |
| `int f(int a, ...)` | `int f(int a, int b)` (fixed arity) |
| `void set_cb(void (*cb)(int))` | `void set_cb(uint64_t handle)` |
| `int f(struct Point p)` | `int f(int x, int y)` |
| `int f(enum Color c)` | `int f(int c)` |
| `_Bool f(int x)` | `int f(int x)` (0/1) |
| `int f(wchar_t * s)` | `int f(char * s)` |
| `void * f(int x)` | `uint64_t f(int x)` |
| `int f(int * p)` | `int f(int a, int b, int c)` or `int f(const char * json)` |
| `int global_var;` | Move inside a function |
| `int x = 42;` | Move inside a function |
| Declaration inside `{ ... }` | Move to top level |
| `int arr[][]` | `int arr[N]` (single layer) |
| Comment followed by blank + another comment | Keep them adjacent, or merge into one |
| Trailing comment `int f(); // x` | Move the comment above the prototype |
| Filename `1.0.3.h` | Rename to `my_module.h` |
| Only `@param` lines, no free text | Add one line of plain description |
| `@return` as the sole return-info source | Declare the return type in the signature |
| `@return` on a `void` function | Delete it — it is ignored |

---

## 9. Self-Check Before You Commit

Run through these five checks in order.

```c
// 1. Does the declaration end with `;` (prototype, not definition)?
// 2. Is it at the top level (not inside a function body / type definition)?
// 3. Are all parameters free of function pointers?
// 4. Are all types in the whitelist (int / float / string only, no pointers)?
// 5. Is the comment directly above the declaration?
```

If any answer is "no", fix it before generating.

---

## 10. Minimum Template

```c
/* <filename>.h */
#ifndef <GUARD>
#define <GUARD>

/**
 * <one-line summary of what the function does>.
 * @param <param1> <description of param1>
 * @param <param2> <description of param2>
 * @return <description of the return value>
 */
<return type> <function name>(<param1 type> <param1 name>,
                              <param2 type> <param2 name>);

#endif /* <GUARD> */
```

Fill in:

- `<GUARD>` — a valid guard name such as `FOO_H` / `FOO_HPP` / `FOO_INCLUDED`.
- `<function name>` — a valid C identifier (not a reserved word).
- `<paramN name>` — a valid C identifier (not a reserved word).
- `<paramN type>` — an integer, float, or string type from §3.1. **No pointers.**
- `<return type>` — the same. `void` is allowed.

**Three reminders**:

1. **The return type must be written in the signature**; `@return` in the comment is only for human readers.
2. **Parameter names must be present**. C allows unnamed parameters, but the model layer skips parameters without a name.
3. **Do not use pointers** — even `char *` is only accepted for strings; any other pointer is rejected.

---

## 11. Common Misreadings and Their Fixes

### 11.1 "C accepts `void *` — so the model will too."

**Wrong.** `void *` is accepted by `Fill_C`, mapped to `Pointer`, then **rejected** by the model layer.

```c
void * allocate(int size);   // ❌ SKIP
uint64_t allocate(int size); // ✅ PASS
```

### 11.2 "The array-suffix section must mean arrays are first-class."

**Wrong.** Arrays are valid only in the C stages. The model layer rejects them.

```c
void fill_buffer(int buf[], int len);   // ❌ SKIP at the model layer
```

### 11.3 "`@param` lines go into the tool description."

**Wrong.** `@param` lines go into the parameter's `Description` field; they are **skipped** in the tool description.

```c
/* ❌ Tool description will be empty */
/**
 * @param code error code
 * @return error description
 */
const char * f(int code);
```

```c
/* ✅ Tool description is non-empty */
/**
 * Gets an error message.
 * @param code error code
 * @return error description
 */
const char * f(int code);
```

### 11.4 "The ` * ` prefix will pollute parameter descriptions."

**Wrong.** The model layer strips the ` * ` prefix automatically. Parameter descriptions arrive clean.

### 11.5 "The return type can be inferred from `@return`."

**Wrong.** The return type must be declared in the prototype. A prototype with no return type is a syntax error and is skipped.

### 11.6 "`const` will block extraction."

**Wrong.** `const` is kept. All three syntactic positions (prefix, suffix, pointer-post) are recognized.

### 11.7 "`extern "C"` needs special syntax."

**Wrong.** `extern "C" { ... }` is a transparent block. Prototypes inside it are treated exactly like top-level prototypes.

### 11.8 "A blank line breaks the comment binding."

**Partially wrong.** A blank line between the comment and the declaration does not break the binding. But a blank line between two comments means only the second is bound.

```c
/* First comment. */

/* Second comment. */

int add(int a, int b);
/* Comment = "Second comment." */
```

### 11.9 "`#define` macros look like functions, so they should be extracted."

**Wrong.** Preprocessor lines are skipped entirely.

```c
#define SQUARE(x) ((x) * (x))   /* ❌ SKIP */
```

### 11.10 "The header file name does not matter."

**Wrong.** The header file name is used to derive the unit name. A filename that starts with a digit (`1.0.3.h`) falls back to the include guard.

```c
/* calculator.h → unit name "calculator" */
/* 1.0.3.h     → falls back to the guard, or "untitled.h" */
```

---

## 12. Relationship to the Pascal Side

Both rules documents target the same underlying model (`Z.Pascal_Func_Model`). They are complementary.

| Dimension | C side (this document) | Pascal side |
|-----------|:----------------------:|:-----------:|
| Input | `.h` header | `.pas` source |
| Extracted from | Top-level prototypes | Top-level `interface` functions/procedures |
| Comment styles | `/* */`, `//`, `/** */` | `(* *)`, `//`, `{ }` |
| Multi-line prefix | ` * ` on second line onward | Same (toolchain output) |
| Type whitelist | C types (int / float / string) | Pascal types (int / float / string) |
| Cross-layer rejection | `void *` → `Pointer` → rejected | `Pointer` rejected directly |
| Array parameters | Single-layer `[]` — C only | Model layer rejects `array of X` |
| Return value description | Stays in `Comment` | Stays in `Comment` |

**Practical guidance**:

- **C output only**: use C rules; arrays and pointers are fine.
- **Pascal output only**: use Pascal rules; no arrays, no pointers.
- **JSON output (MCP tools)**: use both; avoid pointers and arrays.

---

## 13. Version Notes

- **v4.0** — example-first rewrite. Every rule has a ✅/❌ code sample. Diagrams removed. §8 is a single-page rewrite table.
- **v3.0** — first example-heavy edition. Added the "three-stage rejection" walkthrough.
- **v2.0** — original. Aligned with `Fill_C.inc` and `Translate_C_Typ_To_Pascal.inc`.
