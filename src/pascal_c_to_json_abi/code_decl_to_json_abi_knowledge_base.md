# code_decl_to_json_abi Complete Knowledge Base (v3)

> **Purpose** — This document is the **single authoritative reference** for the
> `code_decl_to_json_abi` toolchain. After reading it, an AI agent or a human
> engineer should be able to **develop, use, and maintain** the project
> **without opening any other source file**, including the underlying libraries
> (`Z.Core`, `Z.Pascal_Func_Model`, `Z.Pascal_Func_Tool`, `Z.Json`,
> `lingofuse_import`, the LCL/SynEdit UI, and the seven code generators).
>
> **Promise** — Every statement has been verified against the current source.
> Anything that cannot be determined from the source is explicitly called out in
> the Honest Uncertainty List (Chapter 20).
>
> **Version** — v3. This supersedes v2 and reflects a **fundamental interface
> simplification**: the MCP API has been reduced from 24 tools to **exactly 3
> tools**. Everything else — the eight generators, the nineteen artifacts, the
> wire protocol, the type system — remains, but is now reachable through a
> single Generate / List / Get triple.
>
> **Scope** — `code_decl_to_json_abi.lpr`, `code_decl_to_abi_json_frm.pas`,
> `code_decl_to_json_abi_cmdline.pas`,
> `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`,
> `code_decl_to_json_abi_mcp_api` (declaration),
> `http_cmake_generator_tool.pas`, and the seven language generators
> (`http_pas_abi_*`, `http_py_abi_*`, `http_js_abi_*`, `http_cpp_abi_*`).
> Everything the reader needs to know about these files is in this document.
>
> **Document language** — English. All identifiers, wire formats, and code
> snippets preserve their original spelling.

---

## Table of Contents

**Part I — Orientation**
- [Chapter 0  One-Page Summary](#chapter-0--one-page-summary)
- [Chapter 1  What This Project Is (and Is Not)](#chapter-1--what-this-project-is-and-is-not)
- [Chapter 2  Repository Layout and Build Model](#chapter-2--repository-layout-and-build-model)

**Part II — The Pipeline**
- [Chapter 3  Input Languages — Pascal and C](#chapter-3--input-languages--pascal-and-c)
- [Chapter 4  The Two Intermediate Representations (LV0 / LV1)](#chapter-4--the-two-intermediate-representations-lv0--lv1)
- [Chapter 5  The Type System — Whitelist and Mapping](#chapter-5--the-type-system--whitelist-and-mapping)

**Part III — Generators and Artifacts**
- [Chapter 6  The Eight Generators](#chapter-6--the-eight-generators)
- [Chapter 7  The Nineteen Artifacts — Complete Inventory](#chapter-7--the-nineteen-artifacts--complete-inventory)
- [Chapter 8  Artifact Naming Rules](#chapter-8--artifact-naming-rules)

**Part IV — Wire Protocol**
- [Chapter 9  HTTP/JSON Wire Protocol](#chapter-9--httpjson-wire-protocol)
- [Chapter 10  Error Codes and Exception Types](#chapter-10--error-codes-and-exception-types)

**Part V — The Three Frontends**
- [Chapter 11  GUI Frontend](#chapter-11--gui-frontend)
- [Chapter 12  CLI Frontend](#chapter-12--cli-frontend)
- [Chapter 13  MCP Frontend — The Three Tools](#chapter-13--mcp-frontend--the-three-tools)

**Part VI — Bootstrap → AI-Fill Architecture**
- [Chapter 14  Why the MCP Layer Is a Thin Veneer](#chapter-14--why-the-mcp-layer-is-a-thin-veneer)
- [Chapter 15  The Three `internal_call_*` Implementations](#chapter-15--the-three-internal_call_-implementations)
- [Chapter 16  The UI Operation Pattern](#chapter-16--the-ui-operation-pattern)

**Part VII — Use and Maintenance**
- [Chapter 17  Complete Worked Examples](#chapter-17--complete-worked-examples)
- [Chapter 18  Common Pitfalls and Anti-Patterns](#chapter-18--common-pitfalls-and-anti-patterns)
- [Chapter 19  Modification Guide](#chapter-19--modification-guide)
- [Chapter 20  Honest Uncertainty List](#chapter-20--honest-uncertainty-list)
- [Appendix A — Underlying Library Quick Reference](#appendix-a--underlying-library-quick-reference)
- [Appendix B — File Name Naming Cheat Sheet](#appendix-b--file-name-naming-cheat-sheet)

---

# Part I — Orientation

## Chapter 0  One-Page Summary

### 0.1 What This Project Is

`code_decl_to_json_abi` is a **cross-language code generator**. It accepts a
single Pascal unit or C header as input and produces **LingoFuse HTTP/JSON
service-side and call-side code** for four target languages:

| Target language | Service | Call | Extra |
|-----------------|:-------:|:----:|-------|
| Pascal          | ✅      | ✅   | —     |
| Python          | ✅      | ✅   | —     |
| C++             | ✅      | ✅   | CMake build script + C++ test driver |
| JavaScript      | ❌      | ✅   | Self-contained HTML test page |

Plus a CMake build script (`CMakeLists.txt`) and a C++ test driver
(`test_main___.cpp`) that build and exercise the C++ artifacts.

**Total per unit: 19 artifacts, each with a Markdown companion.**

### 0.2 The Three Frontends

All three drive the same GUI form. There is **no parallel implementation** of
the generation logic.

| Frontend | Trigger | Audience |
|----------|---------|----------|
| GUI | Launch with no arguments | Human engineers |
| CLI | Launch with ≥1 argument | Build scripts, CI |
| MCP | Automatic, after the GUI starts | AI agents, remote tools |

### 0.3 The Three MCP Tools

The MCP API is **exactly three tools**:

| # | Tool | Purpose |
|:-:|------|---------|
| 1 | `CodeDeclToJsonAbi_Generate(Source, Language)` | Parse + generate all 19 artifacts, return a file manifest |
| 2 | `CodeDeclToJsonAbi_ListFiles()` | Return the list of produced file names |
| 3 | `CodeDeclToJsonAbi_GetFile(FileName)` | Return the full text of one file by name |

### 0.4 The Two-Step Workflow

```
Step 1:  Generate(Source, "pascal" | "c")   → {"status":"ok","count":19,"files":[...]}
Step 2:  ListFiles()                        → {"status":"ok","count":19,"files":[...]}
         GetFile("CMakeLists.txt")          → {"status":"ok","name":"...","text":"..."}
```

There is no Step 3. There are no intermediate-inspection tools.

### 0.5 The Eight Rules You Must Not Forget

1. **`Language` accepts only `"pascal"` or `"c"`**. `"python"`, `"cpp"`,
   `"csharp"`, and `"javascript"` are **target** languages, not **source**
   languages. Passing any of them returns an error.
2. **`Generate` produces every target in one shot**. There is no per-target
   call. To obtain a Python service, call `Generate`, then `GetFile` on a
   Python-named file.
3. **`ListFiles` and `GetFile` are pure readers**. They never re-run any
   generator. To refresh, call `Generate` again.
4. **One `Generate` per source text**. Calling it again replaces the session.
5. **Service and Call halves must come from the same source text**.
6. **Types outside the three ABI families cause the entire routine to be
   silently dropped** (see Chapter 5).
7. **`int64` / `uint64` lose precision on the JS client**, because JS `Number`
   is IEEE-754 double (see §5.6).
8. **`bridge.py` must be running** for any generated Call artifact to work.

---

## Chapter 1  What This Project Is (and Is Not)

### 1.1 What It Is

**A generator, not a runtime.** The project produces source files; it does not
run them. Once generated, the artifacts are independent of the project.

**A unified frontend, not four independent generators.** The four target
languages share the same parser, the same model, the same type system, and the
same wire protocol. The differences are purely syntactic.

**A GUI-first tool with two remote controls.** The GUI is the reference
implementation. The CLI and the MCP layer reproduce the GUI's behavior by
simulating its button clicks and editor writes.

### 1.2 What It Is Not

**Not a language server.** It parses declarations, not full programs. It
extracts function signatures, not implementation bodies.

**Not a build system.** It generates a CMake script for C++, but does not run
CMake. It generates a Python module, but does not install it.

**Not a runtime.** The generated artifacts depend on `lingofuse_import` (Pascal
/ Python / C++ / JS binding), `lf_http_bridge_client` (C++ / Pascal call side),
and the LingoFuse HTTP bridge (`bridge.py`). None of those are produced by this
project.

**Not a code formatter.** The `FormatSource` button rewrites declarations by
re-emitting them from the parser, but the goal is normalization, not
aesthetically reformatting arbitrary Pascal.

### 1.3 The Design Philosophy — "One Model, One Truth"

```
                ┌──────────────────────┐
                │  TPascal_Func_Model  │
                │     (the model)      │
                └──────────┬───────────┘
                           │
        ┌──────────┬───────┼───────┬──────────┐
        ▼          ▼       ▼       ▼          ▼
   Pascal gen  Python gen  C++ gen  JS gen  CMake gen
        │          │       │       │          │
        ▼          ▼       ▼       ▼          ▼
    code+md    code+md  code+md  code+md   cmake+cpp
```

The **model** is the single source of truth. Code and documentation are both
generated from it, so they cannot drift apart. Every generator reads the same
`TPascal_Func_Model` instance and produces only one kind of output. There is no
"the documentation says X but the code does Y" failure mode.

---

## Chapter 2  Repository Layout and Build Model

### 2.1 Source File Map

| File | Role |
|------|------|
| `code_decl_to_json_abi.lpr` | Program entry. Decides GUI vs CLI. |
| `code_decl_to_abi_json_frm.pas` | The GUI form. Owns all editors and button handlers. |
| `code_decl_to_abi_json_frm.lfm` | GUI layout resource. |
| `code_decl_to_json_abi_cmdline.pas` | CLI frontend. Independent of the GUI. |
| `code_decl_to_json_abi_mcp_api.pas` | **Declaration unit**. The three MCP tools' signatures and docstrings. |
| `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` | **Provider unit**. Registered Call APIs, callbacks, and the `internal_call_*` bodies. |
| `http_pas_abi_service_generator_tool.pas` | Pascal service generator. |
| `http_pas_abi_call_generator_tool.pas` | Pascal call generator. |
| `http_js_abi_call_generator_tool.pas` | JavaScript call generator + HTML test page. |
| `http_py_abi_service_generator_tool.pas` | Python service generator. |
| `http_py_abi_call_generator_tool.pas` | Python call generator. |
| `http_cpp_abi_service_generator_tool.pas` | C++ service generator. |
| `http_cpp_abi_call_generator_tool.pas` | C++ call generator. |
| `http_cmake_generator_tool.pas` | CMake script + C++ test driver generator. |

### 2.2 External Dependencies

The project links against the Z framework. You do not need to read their source
to maintain this project, but you do need to know their public API. A quick
reference is provided in [Appendix A](#appendix-a--underlying-library-quick-reference).

| Library | Used for |
|---------|----------|
| `Z.Core` | `TCore_Object`, `TCompute`, `TBigList`, `TAtomVar`, `TCritical` |
| `Z.PascalStrings` / `Z.UPascalStrings` | `TPascalString`, `TUPascalString`, string utilities |
| `Z.Pascal_Func_Tool` | `tpascal_func_decl_tool` — the Pascal / C parser |
| `Z.Pascal_Func_Model` | `TPascal_Func_Model` — the LV1 model |
| `Z.Json` | `TZ_JsonObject`, `TZ_JsonArray`, `TZ_JsonString` |
| `Z.UnicodeMixedLib` | `umlCombinePath`, `umlGetFilePath`, file system helpers |
| `Z.Status` | `DoStatus` logging |
| `lingofuse_import` | C ABI binding for LingoFuse: `LF_CreateAppEx`, `LF_RegisterCallEx`, `LF_CallEx`, `LF_CreateDataEx`, ... |
| `LCL` / `SynEdit` | GUI widgets only. Never touched by the CLI. |

### 2.3 Build Model

Two compiler targets are supported:

| Compiler | Notes |
|----------|-------|
| **Free Pascal 3.2+** | Primary. Uses `{$mode delphi}` in the provider unit and `{$mode objfpc}` in the CLI/LPR. |
| **Delphi 11+** | Compatible with the generated artifacts and the provider unit. The GUI form is LCL, so the GUI itself is FPC-only. |

**A typical FPC build**:

```bash
fpc -Fu<workspace>/ZNetV2/ZCore \
    -Fu<workspace>/ZNetV2 \
    code_decl_to_json_abi.lpr
```

The `-Fu` paths must include both `ZCore` and `ZNetV2`. The former provides the
Z framework; the latter provides `lingofuse_import.pas` and the required
`z_ipc_*.dll` runtime.

**Runtime files that must be next to the executable**:

- `LingoFuse64.dll` (Windows) or `liblingofuse.so` (Linux) or
  `liblingofuse.dylib` (macOS)
- `z_ipc_64.dll` (Windows) or `libz_ipc_64.so` (Linux)

### 2.4 Application Type

The LPR file uses `{$apptype console}`. This means the executable always has a
console attached even when launched as a GUI. In GUI mode the console is left
alone; in CLI mode it becomes the output channel.

**Consequence for MCP**: when the GUI runs, an empty console window may appear.
This is expected and harmless. It can be hidden by launching with `start /b` on
Windows, or by running the executable with its stdout redirected to a file.

---

# Part II — The Pipeline

## Chapter 3  Input Languages — Pascal and C

### 3.1 What the Parser Accepts

The parser (`tpascal_func_decl_tool`) accepts **top-level declarations** of
these forms.

**Pascal**:

```pascal
function Name(a: Integer; b: string): Boolean;
procedure Name(a: Integer);
function Name(a: Integer = 42; b: string = 'x'): Int64;
function Name(const a: string; var b: Integer; out c: Double): Integer;
function Name(a: Integer): Int64; cdecl;
function Name(a: Integer): Int64; external 'lib' name 'real_name';
```

**C**:

```c
int  name(int a, const char * b);
void name(void);
double name(double x, int n);
```

### 3.2 What the Parser Rejects

**Pascal side**:

| Rejected construct | Reason |
|--------------------|--------|
| Class methods | Not top-level |
| Nested functions | Not top-level |
| Local variables | Not a declaration |
| Type declarations (`type T = ...`) | Not a function |
| Const / var declarations | Not a function |
| Property declarations | Not a function |
| Statements inside `implementation` | Not a declaration |

**C side**:

| Rejected construct | Reason |
|--------------------|--------|
| Function definitions (`{ ... }`) | Only prototypes are accepted |
| `typedef` / `struct` / `enum` blocks | Not a function prototype |
| Global variable declarations | Not a function |
| Function-pointer parameters | Unsupported ABI |
| Preprocessor conditionals that hide the prototype | The parser sees only what the preprocessor would emit — but this tool does **not** run `cpp`; it parses raw text, so `#if 0 ... #endif` blocks may confuse it |

**Safe approach**: feed the parser a header that has already been preprocessed,
or a header with no `#if` guards around the prototypes.

### 3.3 Comment Handling — The Critical Rule

The parser extracts the **nearest non-empty comment immediately preceding** the
declaration. The comment becomes the tool's `description` in the model.

**What qualifies as "immediately preceding"**:

```pascal
// This comment is captured
function Foo: Integer;    // ✅ comment captured

// Comment

function Foo: Integer;    // ❌ blank line separates them — comment lost
```

**Accepted comment styles**:

| Style | Example |
|-------|---------|
| Pascal brace | `{ ... }` |
| Pascal paren-star | `(* ... *)` |
| Line | `// ...` |
| Doxygen | `/// ...` or `//! ...` |
| Block | `/* ... */` |

**The comment is the tool description**. After generation, this comment becomes
the string that an AI agent reads when deciding whether to call the tool. The
quality of the comment determines the quality of the agent.

**Rules for writing effective comments**:

1. **First sentence is the tool's role**. Example:
   `"Adds two integers and returns the sum."`
2. **Say whether there is a prerequisite or a follow-up**. Example:
   `"Step 1 of a three-tool workflow: call SetSourceCode first."`
3. **Front-load the critical info** — the C++ generator truncates
   descriptions at 200 characters (see §6.7).
4. **List parameter meaning explicitly** if the parameter names are not
   self-explanatory.

See Chapter 17 for worked examples.

### 3.4 Source Language Auto-Detection (GUI Only)

The GUI has a `LanguageSelectorComboBox` and a `LanguageHintClick` handler that
call `DetectSourceLanguage`. The CLI does **not** auto-detect; it uses the file
extension to decide:

| Extension | Source language |
|-----------|:---------------:|
| `.pas`, `.pp`, `.p` | `pascal` |
| `.h`, `.hpp`, `.hh`, `.c`, `.cpp`, `.cc`, `.cxx` | `c` |

The MCP tool requires the language to be passed explicitly, because there is no
file name to inspect.

---

## Chapter 4  The Two Intermediate Representations (LV0 / LV1)

### 4.1 Purpose

The pipeline has two intermediate JSON shapes:

```
Source text
    │  (parse)
    ▼
LV0 JSON           — the raw parser output
    │  (normalize)
    ▼
LV1 JSON           — the model; consumed by all generators
```

Both are exposed in the GUI as editors. **They are not exposed as MCP tools.**
The MCP layer treats them as opaque: `Generate` runs both steps internally.

### 4.2 LV0 — Raw Parser Output

`LV0` is produced by `tpascal_func_decl_tool.SaveToJson`. It contains
**syntactic** metadata: source text positions, raw type spellings, and
modifiers.

**You will never need to read or write LV0 by hand**. Its only consumers are:

- The normalizer (LV0 → LV1).
- The `FormatSource` button (LV0 → source text).
- The `decl_to_pascal` and `decl_to_c` reconstructors.

### 4.3 LV1 — The Model

`LV1` is produced by `TPascal_Func_Model.SaveToJson`. It is the **only**
intermediate that the generators see.

**Shape**:

```json
{
  "UnitName": "MyUnit",
  "Functions": [
    {
      "Name": "Add",
      "IsFunction": true,
      "Comment": "Adds two integers and returns the sum.",
      "ReturnType": "int64",
      "Params": [
        {
          "Name": "a",
          "Typ": "Integer",
          "PascalType": "int64",
          "Description": "First operand"
        },
        {
          "Name": "b",
          "Typ": "Integer",
          "PascalType": "int64",
          "Description": "Second operand"
        }
      ]
    }
  ]
}
```

**Field reference**:

| Field | Type | Meaning |
|-------|------|---------|
| `UnitName` | string | Parsed unit name. Drives every artifact's file name. |
| `Functions` | array | One entry per top-level routine. |
| `Functions[].Name` | string | Routine name. |
| `Functions[].IsFunction` | bool | `true` for `function`, `false` for `procedure`. |
| `Functions[].Comment` | string | Extracted comment. Used in tool descriptions. |
| `Functions[].ReturnType` | string | Normalized return type (`int64` / `double` / `string`). Empty for procedures. |
| `Functions[].Params` | array | One entry per parameter. |
| `Params[].Name` | string | Parameter name. |
| `Params[].Typ` | string | Original type spelling from the source text. |
| `Params[].PascalType` | string | Normalized type. **This is what the generators dispatch on.** |
| `Params[].Description` | string | Extracted per-parameter description, if any. |

**Key point for maintainers**: every generator uses `PascalType` (not `Typ`) to
decide the target type. If you add a new source type spelling, you must teach
the normalizer to map it to one of the three ABI families. See Chapter 5.

### 4.4 When LV1 Is Enough

You can bypass the parser entirely by feeding LV1 directly (via the GUI's
`SetModelJson` path, or the CLI's model-JSON input if you add one). This is
useful when:

- You want to generate code from a schema that does not exist in Pascal or C.
- You have already cached an LV1 model from a previous run.
- You want to hand-edit the model to test a specific generator behavior.

The MCP layer no longer exposes this path, but the underlying GUI still supports
it. See Chapter 19 §19.4 for how to re-enable it if needed.

---

## Chapter 5  The Type System — Whitelist and Mapping

### 5.1 The Three ABI Families

The toolchain supports **exactly three** type families. Anything else causes the
**entire routine** to be dropped.

**String family**:

```
string, AnsiString, UnicodeString, WideString,
PChar, PAnsiChar, PWideChar,
TP_String, TPascalString, TUPascalString, U_String
```

**Float family**:

```
Double, Single, Extended, Real
```

**Integer family**:

```
Integer, LongInt, Int64, Cardinal, DWord, LongWord,
UInt64, Word, SmallInt, Byte, ShortInt
```

### 5.2 Normalization Table

| Source Pascal type | Normalized `PascalType` |
|--------------------|------------------------|
| `Integer`, `LongInt`, `Cardinal`, `DWord`, `LongWord`, `Int64`, `UInt64`, `Word`, `SmallInt`, `Byte`, `ShortInt` | `int64` |
| `Single`, `Double`, `Extended`, `Real` | `double` |
| `string`, `AnsiString`, `UnicodeString`, `WideString`, `PChar`, `PAnsiChar`, `PWideChar`, `TP_String`, `TPascalString`, `TUPascalString`, `U_String` | `string` |
| **Anything else** | *(routine dropped)* |

### 5.3 Target Language Mapping

Every generator maps the normalized family to the target language's native type.

| Family | Pascal | Python | C++ | JavaScript |
|--------|--------|--------|-----|------------|
| `int64` | `Int64` | `int` | `std::int64_t` | `number` |
| `double` | `Double` | `float` | `double` | `number` |
| `string` | `string` | `str` | `std::string` (return) / `const std::string&` (parameter) | `string` |

**Key consequences of the mapping**:

- **Pascal preserves the family name, not the width**. A source `Byte`
  becomes `Int64` in the generated Pascal service unit. If you need width
  preservation, add a new family — but this is a schema change, not a bug fix.
- **C++ narrows all floats to `double`**. `Single` becomes `double`.
- **JavaScript has no `int64`**. Every integer is a `number`, i.e. an IEEE-754
  double. Values above `2^53 − 1` lose precision. See §5.6.

### 5.4 The JSON Wire Type

Only two JSON wire types are used: `number` and `string`.

| Family | JSON wire type |
|--------|:--------------:|
| `int64` | `number` |
| `double` | `number` |
| `string` | `string` |

**A JSON client cannot distinguish `int64` from `double`** by looking at the
wire bytes. The distinction lives only in the LV1 model and in the generated
code.

### 5.5 Unsupported Type Categories

The following are the most common unsupported categories, with workarounds:

| Category | Example | Workaround |
|----------|---------|------------|
| Boolean | `flag: Boolean` | Use `Integer` (0 / 1) or `string` (`"true"` / `"false"`). |
| Variant | `v: Variant` | Encode to JSON and pass as `string`. |
| Arrays | `items: array of Integer` | Encode to JSON and pass as `string`. |
| Records | `p: TPoint` | Encode to JSON and pass as `string`. |
| Classes | `obj: TObject` | Not supported at all. |
| Interfaces | `i: IInterface` | Not supported at all. |
| Enums | `c: TColor` | Use `Integer` (the ordinal value). |
| Sets | `s: TOptions` | Use `Integer` (bit mask). |
| Generics | `list: TList<Integer>` | Encode to JSON and pass as `string`. |
| Pointers | `p: PInteger` | Not supported at all. |
| Function pointers | `cb: TCallback` | Not supported at all. |
| `Currency` | `price: Currency` | Convert to `Double`. |
| `Comp` | `n: Comp` | Convert to `Int64`. |
| `TDateTime` | `t: TDateTime` | Convert to `Double` (Unix timestamp) or `string` (ISO 8601). |

**Why silent drop and not error?** Because a source unit may legitimately
contain auxiliary types that the user never intended to expose as tools. The
generator logs the drop when `GenerateCode_LogEnabled = True`, but the MCP path
does not forward those logs. If a routine is missing from the output, check the
GUI's log panel.

### 5.6 Numeric Precision — The int64 Problem

| Platform | Integer representation | Max exact integer |
|----------|------------------------|-------------------|
| Pascal | `Int64` | ±9.22 × 10^18 |
| Python | `int` (unbounded) | Unlimited |
| C++ | `std::int64_t` | ±9.22 × 10^18 |
| JavaScript | IEEE-754 double (53-bit mantissa) | ±9.0 × 10^15 |
| JSON wire (any parser) | Depends on parser | Depends on parser |

**The problem**: a value that fits in `int64` on the server may not fit in a
JS `Number` on the client. `2^53 + 1 = 9007199254740993` is **not** exactly
representable and will be silently rounded to `9007199254740992`.

**Workaround**: when a value may exceed `2^53`, have the server return it as a
`string` (decimal representation) and let the client parse it with a bignum
library.

**This affects the JS call generator specifically**. Pascal / Python / C++
call generators do not lose precision.

### 5.7 Type Mapping Consistency Rule

If you change the type whitelist, you must change **all eight** of the
following at once, or the toolchain will produce inconsistent output:

1. `Normalize_ABI_Type` in `Z.Pascal_Func_Model`.
2. `IsSupportedABIType` in every generator (Pascal service, Pascal call, Python
   service, Python call, C++ service, C++ call, JS call, CMake).
3. `ABI_Type_To_Pascal_Decl` in each generator.
4. `ABI_Type_To_Py_Annotation` / `ABI_Type_To_CSharp_Decl` / `ABI_Type_To_Cpp_Decl`
   as applicable.
5. `ABI_Type_To_Json_Wire_Type` in each generator.
6. `ABI_Type_To_Json_Default` in each service generator.
7. `ABI_Type_To_Json_Write_Expr` in each service generator.
8. The corresponding `*_readme` generator's type table.

A bug fix in one and not the others is the single most common source of
inconsistent artifact generation.

---

# Part III — Generators and Artifacts

## Chapter 6  The Eight Generators

### 6.1 Overview

| # | Generator unit | Produces |
|:-:|----------------|----------|
| 1 | `http_pas_abi_service_generator_tool` | Pascal service code + README |
| 2 | `http_pas_abi_call_generator_tool` | Pascal call code + README |
| 3 | `http_js_abi_call_generator_tool` | JS call code + README + HTML test page |
| 4 | `http_py_abi_service_generator_tool` | Python service code + README |
| 5 | `http_py_abi_call_generator_tool` | Python call code + README |
| 6 | `http_cpp_abi_service_generator_tool` | C++ service header + impl + README |
| 7 | `http_cpp_abi_call_generator_tool` | C++ call header + impl + README |
| 8 | `http_cmake_generator_tool` | `CMakeLists.txt` + `test_main___.cpp` |

### 6.2 Common Contract (Generators 1–7)

Each generator exposes two functions:

```pascal
function GenerateXxxCode  (Model: TPascal_Func_Model): TPascalStringList;
function GenerateXxxReadme(Model: TPascal_Func_Model): TPascalStringList;
```

The `GenerateCMakeScript` and `GenerateTestMainCpp` functions follow the same
signature.

**Shared contract**:

| Item | Convention |
|------|-----------|
| Input | A `TPascal_Func_Model` instance with `Typ_Normalize_Func = tnf_ABI` |
| Output | A `TPascalStringList` (line list). The caller must `DisposeObject` it. |
| Empty model | `Model = nil` or `Model.UnitName` empty → returns `nil` |
| Unsupported routines | Silently dropped. Logged only if `GenerateCode_LogEnabled` is `True`. |
| Overloads | Same-name overloads receive an `_1`, `_2`, … suffix in source order. |
| Exception policy | Generators do not raise. On internal error, they return `nil` or a skeleton. |

### 6.3 Generator 1 — Pascal Service

**Output files**:

- `<U>_http_json_service_unit.pas`
- `<U>_http_json_service_pascal.md`

**Generated code structure**:

- `interface` section declares `HTTP_SERVICE_APP_NAME`, `HTTP_SERVICE_APP_DESC`,
  `RegisterAllHTTPJsonAPIs`, `CreateAndRegisterHTTPJsonApp`, and one
  `internal_call_<Name>` stub per supported routine.
- `implementation` section defines the stubs (with `TODO` bodies), the `cdecl`
  callbacks, and the registration logic.
- Helper functions `_Json_Get_Int64_ByIndex`, `_Json_Get_Int64_ByName`,
  `_Json_Get_Double_ByIndex`, `_Json_Get_Double_ByName`,
  `_Json_Get_String_ByIndex`, `_Json_Get_String_ByName` are emitted to
  encapsulate argument extraction.

**The `internal_call_*` stub** — the only place a human fills in:

```pascal
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
begin
  // TODO: call the real function, for example:
  //   Result := Add(a, b);
  Result := 0;
end;
```

The `internal_call_<Name>_<ApiName>` name is preserved by the generator. **Do
not rename it**; if you regenerate the unit, your edit will be lost. The
intended workflow is to keep your business logic in a separate unit and just
have the stub call into it.

### 6.4 Generator 2 — Pascal Call

**Output files**:

- `<U>_http_json_call_unit.pas`
- `<U>_http_json_call_pascal.md`

**Generated code structure**:

- `interface` section declares one typed free function per supported routine.
- A unit-level `HTTP_CALL_BASE_URL` variable (default
  `'http://127.0.0.1:8081/<U>'`).
- An `EHTTPCallError` exception class.
- Each function builds a JSON request, calls `LFHttpPost`, unwraps the response,
  and returns the result or raises.

**Depends on**: `lf_http_bridge_client.pas`.

### 6.5 Generator 3 — JavaScript Call

**Output files**:

- `<U>_http_json_call.js`
- `<U>_http_json_call_js.md`
- `<U>_http_json_call_test.html`

**Generated code structure**:

- An IIFE that attaches itself to `window.<UnitName>Api` (or
  `globalThis.<UnitName>Api` when `window` is unavailable).
- A `LFHttpCallError` class.
- One async function per supported routine.

**The HTML test page**:

- **No external script tags**. All logic is inline.
- No arrow functions, no `async` / `await`, no `let` / `const`. Uses only
  `var`, `function`, `Promise`, `fetch`, and `JSON`.
- Renders one interactive card per routine.
- Works from both `file://` and `http://` protocols (subject to CORS rules; see
  §18.4).

### 6.6 Generator 4 — Python Service

**Output files**:

- `<U>_http_json_service.py`
- `<U>_http_json_service_python.md`

**Generated code structure**:

- Module docstring.
- Progressive-symbol-resolution imports (see §6.6.1).
- `HTTP_SERVICE_APP_NAME` / `HTTP_SERVICE_APP_DESC` / `HTTP_SERVICE_ENDPOINT`
  constants.
- Helper functions `_read_request`, `_extract_args`, `_write_success`,
  `_write_error`, `_make_call_adapter`.
- One `internal_call_<Name>` stub per routine.
- `register_all_http_json_apis(app)`.
- `main()` — the entry point when run as a script.

#### 6.6.1 Progressive Symbol Resolution

Different `py-lingofuse` installations expose the same symbols from different
submodule paths. Instead of hard-coding one path, the generated module
resolves each symbol against a list of candidate paths, from the most public to
the most internal. If every candidate fails, the module prints a diagnostic
listing the missing symbol and every attempted path, then exits.

The candidate root can be overridden with the `LINGOFUSE_MODULE` environment
variable.

#### 6.6.2 The `internal_call_*` Stub

```python
def internal_call_Add(a: int, b: int) -> int:
    """
    Adds two integers and returns the sum.

    TODO: replace the body with a call to the real implementation.
    Suggested call: Add(a, b)
    """
    # TODO: implement this stub.
    return 0
```

**Do not rename** the stub; regenerate-safe.

### 6.7 Generator 5 — Python Call

**Output files**:

- `<U>_http_json_call.py`
- `<U>_http_json_call_python.md`

**Generated code structure**:

- Module docstring.
- `import requests` (with a clear `ImportError` message if missing).
- `HTTP_CALL_BASE_URL` / `HTTP_CALL_TIMEOUT` / `DEBUG_LOG` module constants.
- `HTTPCallError` exception class.
- `_call_api(api_name, args)` — the single transport function.
- One typed free function per supported routine.

**Depends on**: the `requests` package. **No other third-party dependency**.

### 6.8 Generator 6 — C++ Service

**Output files**:

- `<U>_http_json_service.hpp`
- `<U>_http_json_service.cpp`
- `<U>_http_json_service_cpp.md`

**Generated code structure**:

- Header: namespace, config globals, `HTTPCallError` class declaration, API
  stub declarations, `run_service()` declaration.
- Implementation: stub bodies (with `TODO` markers), `cdecl` callbacks,
  registration function, and a ready-to-run `main()`.
- The `main()` function constructs a `lingofuse::LibraryLoader` as its first
  statement. Without it, `LF_CreateApp` returns `NULL` and the service throws
  `lingofuse::Error`.

**The `internal_call_*` stub**:

```cpp
std::int64_t internal_call_Add(std::int64_t a, std::int64_t b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b);
    return 0;
}
```

### 6.9 Generator 7 — C++ Call

**Output files**:

- `<U>_http_json_call.hpp`
- `<U>_http_json_call.cpp`
- `<U>_http_json_call_cpp.md`

**Generated code structure**:

- Header: namespace, `HTTPCallError` class, one free function declaration per
  routine.
- Implementation: config globals, the error class body, an internal `_invoke`
  helper, and one function per routine.

**Transport**: delegates to `lingofuse::bridge::httpCall`, provided by
`lf_http_bridge_client.hpp`.

### 6.10 Generator 8 — CMake

**Output files**:

- `CMakeLists.txt` (fixed name)
- `test_main___.cpp` (fixed name)

**`CMakeLists.txt` key facts**:

| Aspect | Value |
|--------|-------|
| Minimum version | 3.15 |
| Project languages | `C CXX` (both required) |
| C++ standard | 17, required |
| Cache variable | `LINGOFUSE_CPP_LIB_DIR` |
| Service target | `<U>_http_json_service` |
| Call test target | `<U>_http_json_call_test` |
| Windows link libs | `ws2_32` |
| macOS link libs | `Threads::Threads` |
| Linux link libs | `Threads::Threads` + `${CMAKE_DL_LIBS}` |
| Warnings | `/W4 /permissive-` on MSVC; `-Wall -Wextra` elsewhere |
| Runtime DLL staging | **none** |

**`test_main___.cpp`** is a driver that:

1. Constructs a `lingofuse::LibraryLoader`.
2. Prepares a client connection to `ipc:<U>_http_json`.
3. Sets `HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<U>"`.
4. Calls every wrapper function with default arguments.
5. Prints `OK` or `FAILED: <reason>`.
6. Returns 0 on total success, 1 otherwise.

### 6.11 Description Truncation

Only the C++ generator truncates the tool description, at **200 characters**.
Pascal, Python, and JavaScript preserve the full description.

**Implication**: if a description is longer than 200 characters, only the first
200 characters reach the C++ agent. The first 200 characters must carry the
critical information (see §3.3).

---

## Chapter 7  The Nineteen Artifacts — Complete Inventory

### 7.1 Full Table

| # | File | Generator | Purpose |
|:-:|------|:---------:|---------|
| 1 | `<U>_http_json_service_unit.pas` | 1 | Pascal service |
| 2 | `<U>_http_json_service_pascal.md` | 1 | Pascal service README |
| 3 | `<U>_http_json_call_unit.pas` | 2 | Pascal call |
| 4 | `<U>_http_json_call_pascal.md` | 2 | Pascal call README |
| 5 | `<U>_http_json_call.js` | 3 | JS client |
| 6 | `<U>_http_json_call_js.md` | 3 | JS README |
| 7 | `<U>_http_json_call_test.html` | 3 | JS HTML test page |
| 8 | `<U>_http_json_service.py` | 4 | Python service |
| 9 | `<U>_http_json_service_python.md` | 4 | Python service README |
| 10 | `<U>_http_json_call.py` | 5 | Python call |
| 11 | `<U>_http_json_call_python.md` | 5 | Python call README |
| 12 | `<U>_http_json_service.hpp` | 6 | C++ service header |
| 13 | `<U>_http_json_service.cpp` | 6 | C++ service impl |
| 14 | `<U>_http_json_service_cpp.md` | 6 | C++ service README |
| 15 | `<U>_http_json_call.hpp` | 7 | C++ call header |
| 16 | `<U>_http_json_call.cpp` | 7 | C++ call impl |
| 17 | `<U>_http_json_call_cpp.md` | 7 | C++ call README |
| 18 | `CMakeLists.txt` | 8 | CMake build script |
| 19 | `test_main___.cpp` | 8 | C++ test driver |

### 7.2 What `<U>` Is

`<U>` is the **normalized unit name**, produced by `MakeApiName(UnitName)`:

- Space and tab → `_`
- `.` → `_`
- `/` → `_`
- `\` → `_`
- `@` → `_`
- `:` → `_`
- `#` → `_`
- `?` → `_`
- `&` → `_`
- `=` → `_`
- `+` → `_`
- `-` → `_`
- Leading digit → prepend `_`

**Example**: a Pascal unit declared as `unit My.Calculator;` produces
`<U> = "My_Calculator"`, and the Pascal service file becomes
`My_Calculator_http_json_service_unit.pas`.

### 7.3 File Locations

| Frontend | Where files are written |
|----------|-------------------------|
| GUI | `<exe dir>/<U>/` (one subdirectory per unit) |
| CLI | The output file's directory |
| MCP | `<exe dir>/<U>/` (same as GUI) |

**Fixed-name files** (17 CMake files) are **overwritten** if two units are
generated into the same directory. The intended layout is **one directory per
unit**.

### 7.4 The Bridge Is Not Generated

`bridge.py` is a **separate program** shipped with the LingoFuse Python
package. It is not produced by this toolchain. For the generated Call
artifacts to work, `bridge.py` must be running and reachable at the URL in
`HTTP_CALL_BASE_URL`. See Chapter 9.

---

## Chapter 8  Artifact Naming Rules

### 8.1 The Master Formula

```
<U>_http_json_<side>.<ext>

Where:
  <U>     = normalized unit name (see §7.2)
  side    = "service" or "call"
  ext     = "pas" | "py" | "hpp" | "cpp" | "js" | "html" | "md"
```

### 8.2 Exceptions

| File | Why it does not follow the formula |
|------|------------------------------------|
| `CMakeLists.txt` | CMake looks for this exact name. Cannot be renamed. |
| `test_main___.cpp` | Referenced by that exact name inside the generated `CMakeLists.txt`. |

### 8.3 The README Suffix Convention

Each README's name ends with `_<language>.md`:

| Language | Suffix |
|----------|--------|
| Pascal | `_pascal.md` |
| JavaScript | `_js.md` |
| Python | `_python.md` |
| C++ | `_cpp.md` |

The suffix tells you which language's README it is; the name is otherwise the
same base as the code file.

### 8.4 The `_test.html` Suffix

The JS test page is always named `<U>_http_json_call_test.html`. There is no
corresponding entry in the generator's file manifest for `<U>_http_json_call.js`
because the JS generator produces three files, and all three are listed.

---

# Part IV — Wire Protocol

## Chapter 9  HTTP/JSON Wire Protocol

### 9.1 URL Composition

```
HTTP_CALL_BASE_URL + "/" + <api-name>
```

The default value of `HTTP_CALL_BASE_URL` in every generated Call artifact is:

```
http://127.0.0.1:8081/<U>
```

`<api-name>` is the **sanitized** routine name, produced by
`MakeApiName(FuncName)`. It matches the identifier used in the tool
registration.

### 9.2 The Bridge's Role

The bridge (`bridge.py`) is an **HTTP forwarder**. It receives an HTTP POST
from a Call artifact, converts it into a LingoFuse Call, forwards it to the
service, and converts the result back into an HTTP response.

The Call artifact **never talks to the service directly**. Every call goes
through the bridge.

### 9.3 Request — Call → Bridge

The Call artifact sends a LingoFuse call to the bridge's well-known App:

```
LF_Call("__lf_http_bridge__", <bridge-request-json>)
```

Where `<bridge-request-json>` is:

```json
{
  "url":     "http://.../<api>",
  "method":  "POST",
  "headers": { "Content-Type": "application/json; charset=utf-8" },
  "body":    { "args": [v1, v2, ...] },
  "timeout": 25.0
}
```

### 9.4 Request — Bridge → Service

The bridge sends a plain HTTP POST to `<url>` with the body from
`<bridge-request-json>.body`:

```http
POST /<app>/<api> HTTP/1.1
Content-Type: application/json; charset=utf-8
Content-Length: ...
```

```json
{"args": [v1, v2, ...]}
```

### 9.5 Response — Service → Bridge

The service responds with a JSON object:

```json
{"code": 0, "result": <value>}
{"code": -1, "error": "<message>"}
```

### 9.6 Response — Bridge → Call

The bridge wraps the service response in an envelope:

```json
{
  "status_code": 200,
  "headers": { ... },
  "body": {"code": 0, "result": <value>}
}
```

### 9.7 Argument Semantics

Two forms are accepted.

**Positional form (recommended)**:

```json
{"args": [v1, v2, v3]}
```

Array element `i` maps to parameter `i`. Missing arguments receive the type's
default (`0` for `int64`, `0.0` for `double`, `""` for `string`).

**Named form**:

```json
{"param1": v1, "param2": v2}
```

Matches parameter names **exactly** (case-sensitive). Only takes effect when
`"args"` is absent. If both forms are present, `"args"` wins.

**The toolchain-generated call artifacts always use the positional form**. Named
form is supported for hand-written clients.

### 9.8 Encoding Rules

- **Charset**: UTF-8, no BOM.
- **JSON**: standard. The bridge serializes with `ensure_ascii=False`, so
  non-ASCII characters appear as literal UTF-8 bytes.
- **String termination**: LingoFuse strings carry a trailing `\0` on the
  LingoFuse wire, but the bridge strips it before forwarding to HTTP.

### 9.9 HTTP Method

The bridge accepts **`POST` only**. Other methods return HTTP 405.

### 9.10 The `bridge` Timeout

`bridge.py` uses `timeout: 25.0` (seconds) by default. This is **shorter than**
the LingoFuse Call timeout (`HTTP_CALL_TIMEOUT_MS = 60000` in the C++ call
generator), so the bridge times out first if the target is unreachable.

**Rule of thumb**: the LingoFuse Call timeout must be **larger than** the HTTP
timeout, so that the HTTP layer has a chance to return a proper error before
the outer LingoFuse call gives up.

---

## Chapter 10  Error Codes and Exception Types

### 10.1 Error Codes

Every service / bridge error is `{"code": <int>, "error": "<string>"}`. The
`code` field uses the following values:

| Code | Meaning | Typical HTTP status |
|:----:|---------|:-------------------:|
| `0` | Success. Never reported as an error. | 200 |
| `-1` | Remote call failed (service-side exception, network failure, timeout). | 200 or 0 |
| `-2` | Request shape error (malformed URL path, un-serializable body). | 400 |
| `-3` | Bridge precheck failed (the bridge's local cache has not yet seen the API). | 200 |

### 10.2 The `-3` Case

The bridge caches the API list from a LingoFuse broadcast. After a service
starts, the broadcast takes up to ~3 seconds to propagate. If a call arrives
before the broadcast, the bridge returns `-3`.

**Fixes**:

1. Start the bridge with `--no-precheck`.
2. Wait ≥3 seconds after the service starts before calling.
3. Catch `-3` and retry.

### 10.3 Exception Types by Target

| Target | Exception class | Fields |
|--------|-----------------|--------|
| Pascal | `EHTTPCallError` | `.Message` (inherited from `Exception`) |
| Python | `HTTPCallError` | `.code`, `.http_status` |
| C++ | `HTTPCallError` | `.code`, `.http_status` |
| JavaScript | `LFHttpCallError` | `.code`, `.httpStatus` |

All four classes carry a message string. All four are thrown only by the
generated Call artifacts, never by the generated Service artifacts.

### 10.4 Toolchain Error JSON (MCP Layer)

The MCP layer returns different shapes on success and on failure:

- **Success**: `{"status": "ok", ...}`
- **Failure**: `{"status": "error", "error": "<message>"}` or
  `{"error": "<message>"}` (depending on the tool)

See Chapter 13 for the exact shape of each tool.

### 10.5 Common Error Messages

| Message | Origin |
|---------|--------|
| `Unsupported language. Use pascal or c.` | `Generate` when `Language` is not `pascal` / `c` |
| `Form not available` | Any tool when the GUI form is not created |
| `File not found. Call ListFiles first to get valid names.` | `GetFile` when `FileName` is not in the list |
| `Generation failed: <reason>` | `Generate` when a button handler raises |
| `LF_PrepareClient returned -1` | LingoFuse startup |
| `LF_PrepareDone returned 0` | LingoFuse startup, if `PrepareDone` was already called in the same process |
| `no found app("<name>")` | LingoFuse routing |
| `3029 function header doesn't match` | FPC overload conflict |
| `Illegal expression` / `Syntax error, ";" expected` | FPC inline-var misuse |
| `Cannot determine link language` | CMake, when `project()` declares only `CXX` |

---

# Part V — The Three Frontends

## Chapter 11  GUI Frontend

### 11.1 Startup

Launch with **zero** arguments. The LPR calls `Application.Initialize`, creates
the form, and enters the event loop.

### 11.2 The Five Tabs

| Tab | Purpose |
|-----|---------|
| 1. Welcome | Introduction and rule-document links |
| 2. Source Code | Paste / edit the source text |
| 3. Source ↔ JSON | LV0 intermediate (editable) |
| 4. JSON ↔ Model | LV1 intermediate (editable) |
| 5. Final Source | Generated artifacts (view only) |

### 11.3 Key Buttons

| Button | Handler | Effect |
|--------|---------|--------|
| Select Language | `LanguageSelectorChange` | Sets highlighter and `CurrentSourceLanguage` |
| Auto-Detect | `LanguageHintClick` | Calls `DetectSourceLanguage` on the current source |
| Empty Unit | `InsertEmptyUnitClick` | Inserts a minimal skeleton |
| Test Unit | `InsertTestUnitClick` | Inserts a rich syntax sample |
| Format | `FormatSourceClick` | Re-emits only top-level declarations |
| Source → JSON | `ParseSourceToJsonClick` | Runs the parser |
| JSON → Model | `NormalizeJsonToModelClick` | Runs the normalizer |
| Generate Source | `GenerateAllSourcesClick` | Runs all 8 generators and writes 19 files to disk |
| Back to Model | `BackToModelJsonClick` | Switches to the Model JSON tab |

### 11.4 Form Fields (Maintained List)

**Editors** (all `TSynEdit`):

| Field | Content |
|-------|---------|
| `SourceCodeEditor` | Source text |
| `SourceJsonEditor` | LV0 JSON |
| `ModelJsonEditor` | LV1 JSON |
| `PascalServiceCodeEditor`, `PascalServiceReadmeEditor` | Pascal service artifacts |
| `PascalCallCodeEditor`, `PascalCallReadmeEditor` | Pascal call artifacts |
| `JavaScriptCallCodeEditor`, `JavaScriptCallReadmeEditor`, `JavaScriptTestHtmlEditor` | JS artifacts |
| `PythonServiceCodeEditor`, `PythonServiceReadmeEditor` | Python service artifacts |
| `PythonCallCodeEditor`, `PythonCallReadmeEditor` | Python call artifacts |
| `CppServiceHeaderEditor`, `CppServiceImplEditor`, `CppServiceReadmeEditor` | C++ service artifacts |
| `CppCallHeaderEditor`, `CppCallImplEditor`, `CppCallReadmeEditor` | C++ call artifacts |
| `CMakeEditor`, `CMake_TestMain_Editor` | CMake artifacts (displayed in GUI) |

**Controls**:

| Field | Purpose |
|-------|---------|
| `LanguageSelectorComboBox` | `ItemIndex`: 0 = unknown, 1 = Pascal, 2 = C |
| `MainPageControl` | The tab control |
| `FinalSourcePageControl` | The child tab control inside the Final Source tab |
| `final_source_file_ListView` | **List of produced files** (name + full path) |
| `final_Source_edit` | Shows the currently-selected file |
| `StatusRefreshTimer` | Drives `Check_Soft_Thread_Synchronize` and `LF_Sync` |

**Session caches** (not visible; used by the MCP layer):

| Field | Populated by |
|-------|--------------|
| `FSessionCMakeScript` | `GenerateAllSourcesClick`, CMake step |
| `FSessionTestMainCpp` | `GenerateAllSourcesClick`, CMake step |

### 11.5 The `final_source_file_ListView` Structure

The list view is the source of truth for the MCP layer's `ListFiles` and
`GetFile`.

**Column model**:

| Field | Content |
|-------|---------|
| `Caption` | **The file name** (e.g. `My_Calculator_http_json_service_unit.pas`) |
| `SubItems[0]` | **The full path** to the file on disk |

**Populated by**: `GenerateAllSourcesClick`, via its internal `Emit` helper.
Each `Emit` call appends one entry.

**Read by**: the MCP layer's `ListFiles` (returns `Caption` values) and
`GetFile` (matches `Caption`, reads the file at `SubItems[0]`).

**The list is cleared** at the start of every `GenerateAllSourcesClick`.

### 11.6 MCP Auto-Start

In `Tcode_decl_to_abi_json_form.Create`:

```pascal
TCompute.RunM_NP(StartMcpService);
```

This runs on a background worker thread. `StartMcpService` calls
`LF_SetOptionEx`, then `Execute_And_Reg_all`. The MCP tools are registered as
soon as the beacon is reachable.

### 11.7 Log Panel

The GUI has a status log. It is populated by `DoStatus`. The log grows without
a bound by default; the GUI clears it when the line count exceeds 5000.

---

## Chapter 12  CLI Frontend

### 12.1 Trigger

Launch with **at least one** argument.

### 12.2 Early Exit

The LPR file calls `Process_CommandLine` **before** `Application.Initialize`.
If the function returns `False`, the LPR exits with `CommandLine_ExitCode`.
The LCL is never initialized, so no window appears.

### 12.3 Arguments

```
code_decl_to_json_abi --help                            → help text, exit 0
code_decl_to_json_abi <input> <output>                  → service side
code_decl_to_json_abi --call <input> <output>           → call side
```

- `<input>` is a file path. Source language is detected from the extension.
- `<output>` is a file path. Target language is detected from the extension.

### 12.4 Target Language Detection

| Output extension | Target |
|------------------|--------|
| `.pas`, `.pp`, `.p` | Pascal |
| `.py` | Python |
| `.hpp`, `.hh`, `.h` | C++ header (auto-pairs `.cpp`) |
| `.cpp`, `.cc`, `.cxx`, `.c` | C++ impl (auto-pairs `.hpp`) |
| `.js` | JavaScript (call side only) |

**JavaScript is call-side only**. Naming `.js` as output without `--call` is an
argument error.

### 12.5 What the CLI Writes

For a **non-C++ target**: one code file + one README, next to the output file.

For a **C++ target**: `.hpp` + `.cpp` + README, plus `CMakeLists.txt` and
`test_main___.cpp` in the same directory.

For **JavaScript**: `.js` + README + `_test.html`, next to the output file.

### 12.6 Exit Codes

| Code | Meaning |
|:----:|---------|
| 0 | Success |
| 1 | Missing or invalid arguments |
| 2 | Source parsing failed |
| 3 | Code generation failed |
| 4 | File I/O error |

### 12.7 Console Output

The CLI is a **console-subsystem** build (`{$apptype console}`). All
`DoStatus` messages go to stdout. The `--help` output is a fixed block of text
that covers all four target languages and both directions.

### 12.8 No GUI Involvement

The CLI **does not create the form**. It uses its own `tpascal_func_decl_tool`
and `TPascal_Func_Model` instances. Consequences:

- The CLI does **not** share state with the GUI or MCP path.
- The CLI **cannot** read the GUI's `final_source_file_ListView`.
- The CLI returns output files directly; there is no separate "list files" step.

---

## Chapter 13  MCP Frontend — The Three Tools

### 13.1 Why the Layer Was Reduced to Three Tools

The previous iteration exposed 24 tools. That was a **remote-control surface**,
not an agent-facing API. Agents had to understand:

- Which 2 of the 24 tools were input tools.
- Which 1 was the generation tool.
- Which of the remaining 21 readers they needed.

This was a **discoverability problem**: the agent's first move was always
wrong, and the correction required a full regeneration cycle (Chapter 17 of v2).

The three-tool design solves it:

- **One** tool per verb: Generate, List, Get.
- The **Generate** tool produces **everything** in one shot.
- The **List** / **Get** tools are pure readers.

### 13.2 The Three Tools — Reference

#### 13.2.1 `CodeDeclToJsonAbi_Generate`

**Signature**: `function(Source: string; Language: string): string`

**Input**:

| Parameter | Type | Notes |
|-----------|------|-------|
| `Source` | string | Full source text |
| `Language` | string | `"pascal"` or `"c"`, case-insensitive |

**Behavior**:

1. Validate `Language`.
2. Select the source language in the GUI.
3. Write `Source` into the source editor.
4. Trigger the parse → normalize → generate button chain.
5. Read the resulting file list from the ListView.
6. Cache the CMake artifacts in the form's session caches.

**Success return**:

```json
{
  "status": "ok",
  "unit_name": "MyUnit",
  "count": 19,
  "files": [
    "MyUnit_http_json_service_unit.pas",
    "MyUnit_http_json_service_pascal.md",
    "MyUnit_http_json_call_unit.pas",
    "MyUnit_http_json_call_pascal.md",
    "MyUnit_http_json_call.js",
    "MyUnit_http_json_call_js.md",
    "MyUnit_http_json_call_test.html",
    "MyUnit_http_json_service.py",
    "MyUnit_http_json_service_python.md",
    "MyUnit_http_json_call.py",
    "MyUnit_http_json_call_python.md",
    "MyUnit_http_json_service.hpp",
    "MyUnit_http_json_service.cpp",
    "MyUnit_http_json_service_cpp.md",
    "MyUnit_http_json_call.hpp",
    "MyUnit_http_json_call.cpp",
    "MyUnit_http_json_call_cpp.md",
    "CMakeLists.txt",
    "test_main___.cpp"
  ]
}
```

**Failure return**:

```json
{"error": "<message>"}
```

Common messages:

- `Unsupported language. Use pascal or c.`
- `Form not available`
- `Generation failed: <reason>`

**Notes**:

- **Every successful call replaces the session**. A previous `Generate` for a
  different source text is discarded.
- **Every successful call writes 19 files to disk**, under
  `<exe dir>/<normalized unit name>/`.
- **`Generate` may be called many times**. Each call re-parses and refreshes.

#### 13.2.2 `CodeDeclToJsonAbi_ListFiles`

**Signature**: `function(): string`

**Behavior**:

1. Walk the GUI's `final_source_file_ListView.Items`.
2. Collect each item's `Caption`.

**Success return**:

```json
{
  "status": "ok",
  "count": 19,
  "files": ["<name 1>", "<name 2>", ...]
}
```

**Empty return** (if `Generate` has not been called):

```json
{"status": "ok", "count": 0, "files": []}
```

**Notes**:

- **Pure reader**. Does not re-run any generator.
- **Pure reader**. Does not mutate the session.
- File names are the **`Caption` values**, not full paths. Full paths are
  internal to the GUI.

#### 13.2.3 `CodeDeclToJsonAbi_GetFile`

**Signature**: `function(FileName: string): string`

**Input**:

| Parameter | Type | Notes |
|-----------|------|-------|
| `FileName` | string | Must be a value returned by a previous `ListFiles` call |

**Behavior**:

1. Walk the GUI's `final_source_file_ListView.Items`.
2. Match `FileName` against each item's `Caption`.
3. Read the file at the matching item's `SubItems[0]` as UTF-8.
4. Return the text.

**Success return**:

```json
{
  "status": "ok",
  "name": "<FileName>",
  "text": "<full artifact text>"
}
```

**Failure return**:

```json
{
  "status": "error",
  "name": "<FileName>",
  "error": "<message>"
}
```

Common failure messages:

- `Form not available`
- `File not found. Call ListFiles first to get valid names.`

**Notes**:

- **Reads the file from disk**. If the disk copy is stale but the ListView is
  current, the disk copy is returned. This is fine because `Generate` writes
  disk and list in the same operation.
- **`FileName` is case-sensitive**. `CMakeLists.txt` works; `cmakelists.txt`
  does not.
- **The `text` field may be empty** for a genuinely empty file. An empty `text`
  is not an error; check `status` to distinguish.

### 13.3 The Three-Tool Workflow

```
┌──────────────────────────────────────────────────────────────┐
│  1.  Generate(Source, "pascal")                              │
│      → {"status":"ok","count":19,"files":[...]}              │
├──────────────────────────────────────────────────────────────┤
│  2.  ListFiles()                                             │
│      → {"status":"ok","count":19,"files":[...]}              │
├──────────────────────────────────────────────────────────────┤
│  3.  GetFile("MyUnit_http_json_service.py")                  │
│      → {"status":"ok","name":"...","text":"..."}             │
│                                                              │
│      GetFile("MyUnit_http_json_service_python.md")           │
│      GetFile("MyUnit_http_json_call.js")                     │
│      GetFile("MyUnit_http_json_call_test.html")              │
│      GetFile("CMakeLists.txt")                               │
│      GetFile("test_main___.cpp")                             │
│      ... (any number of GetFile calls)                       │
└──────────────────────────────────────────────────────────────┘
```

### 13.4 Naming Rule Cheat Sheet (for Agents)

Every language-specific file follows:

```
<UnitName>_http_json_<side>.<ext>
```

Where:

- `<UnitName>` is whatever `Generate` returned in `unit_name`.
- `<side>` is `service` or `call`.
- `<ext>` is one of `pas`, `py`, `hpp`, `cpp`, `js`, `html`, `md`.

The two **fixed-name** files are:

- `CMakeLists.txt`
- `test_main___.cpp`

**Never invent a file name that does not match the rule.** If unsure, call
`ListFiles` first.

### 13.5 Why the Tool Descriptions Are Long

The description of each of the three tools is a **single string** that runs
several hundred characters. This is deliberate:

- The AI's first read of the tool list is the only chance to correct its
  default behavior.
- The description front-loads the **role** ("Step 1 of 2"), the
  **prerequisite** ("None" or "Generate must have succeeded first"), and the
  **output shape** (the exact JSON).
- A WRONG/RIGHT table is included for the two most common errors
  (`Language='python'`, reading before generating).

**Do not shorten these descriptions.** See Chapter 17 of the v2 knowledge base
for the incident that motivated this.

### 13.6 Registration Flow

`Execute_And_Reg_all` performs the entire MCP startup:

1. `RegisterAPIs` — creates the LingoFuse App and issues **3** `LF_RegisterCallEx` calls.
2. `LF_PrepareClientEx("ipc:agent", App)` — connects to the LingoFuse endpoint.
3. `LF_PrepareDone` — waits for the client to be ready.
4. `RegisterTools` — registers the **3** tool schemas with
   `agent_main_app.register_agent`.

**Return value**: `True` if all 3 tools registered; `False` otherwise.

**The 3 tool schemas are registered in this order**:

1. `CodeDeclToJsonAbi_Generate` (with `Source` and `Language` parameters)
2. `CodeDeclToJsonAbi_ListFiles` (no parameters)
3. `CodeDeclToJsonAbi_GetFile` (with `FileName` parameter)

---

# Part VI — Bootstrap → AI-Fill Architecture

## Chapter 14  Why the MCP Layer Is a Thin Veneer

### 14.1 The Problem

The MCP tool bodies could theoretically re-implement the entire generation
pipeline. They do not. They **delegate to the GUI**.

### 14.2 The Chain of Custody

```
MCP client
    │  LingoFuse Call
    ▼
Callback_CodeDeclToJsonAbi_Generate (cdecl, worker thread)
    │  internal_call_CodeDeclToJsonAbi_Generate
    ▼
internal_call_CodeDeclToJsonAbi_Generate
    │  TCompute.Sync(Do_Sync___)
    ▼
Do_Sync___ (runs on the MAIN thread)
    │  code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;
    │  code_decl_to_abi_json_form.ParseSourceToJsonClick(...);
    │  code_decl_to_abi_json_form.NormalizeJsonToModelClick(...);
    │  code_decl_to_abi_json_form.GenerateAllSourcesClick(...);
    │  read code_decl_to_abi_json_form.final_source_file_ListView
    ▼
TCompute.Sync returns
    │  internal_call_* returns the JSON string
    ▼
Callback_* writes the string to the output DataHandle
    ▼
LingoFuse returns to the MCP client
```

Every arrow is written once. Adding a new tool is a mechanical operation:
copy an existing `internal_call_*` pair, rename it, point it at a different
form field, and add the schema to `RegisterTools`.

### 14.3 The Consequences

1. **The GUI is the single source of truth.** If the GUI does not show a value,
   the MCP tool cannot return it.
2. **Button-click handlers are the MCP implementations.** The MCP layer is a
   remote control.
3. **Thread-safety is inherited.** `TCompute.Sync` marshals the body onto the
   main thread, where the LCL is safe to touch. No critical sections are
   needed.
4. **The MCP layer never reads disk for the code artifacts.** It reads the
   ListView and the ListView-referenced files. This is why the ListView must
   be up-to-date.

### 14.4 What the AI-Fill Pattern Can and Cannot Do

**Can**:

- Read any GUI editor's text.
- Click any button.
- Write to any editor.
- Read the ListView.

**Cannot**:

- Add new state to the form. State must exist as an editor or a control.
- Access the CLI's state. The CLI is a separate process.
- Bypass `TCompute.Sync`. Every UI touch must be on the main thread.

---

## Chapter 15  The Three `internal_call_*` Implementations

### 15.1 The `TCompute.Sync` Wrapper

Every `internal_call_*` follows the same shape:

```pascal
function internal_call_Xxx(...): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  var
    // local variables
  begin
    // the UI-touching body
    Result := ...;
  end;
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
{$IFDEF FPC}
  TCompute.Sync(Do_Sync___);
{$ELSE FPC}
  TCompute.Sync(procedure()
  begin
    // the UI-touching body
    temp_ := ...;
  end);
  Result := temp_;
{$ENDIF FPC}
end;
```

**Why this shape**:

- `TCompute.Sync` is a **blocking** synchronizer: it schedules the nested
  procedure on the main thread and waits for it to finish.
- The nested procedure must capture its result via the **enclosing function's
  `Result`** (FPC) or via a **local variable** (Delphi), because anonymous
  procedures cannot return values.
- The `{$IFDEF FPC}` split exists because FPC's `is nested` procedures and
  Delphi's `reference to` procedures have different capture semantics.

### 15.2 `internal_call_CodeDeclToJsonAbi_Generate`

**Signature**: `function(Source: string; Language: string): string`

**Body** (FPC branch shown; the Delphi branch is equivalent):

```pascal
procedure Do_Sync___();
var
  lang: string;
  i, count: integer;
  resp, modelJo: TZ_JsonObject;
  fileArr: TZ_JsonArray;
begin
  if code_decl_to_abi_json_form = nil then
  begin
    Result := '{"error":"Form not available"}';
    Exit;
  end;

  // ---- Step 1: select source language ----
  lang := LowerCase(Trim(Language));
  if lang = 'pascal' then
  begin
    code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 1;
    code_decl_to_abi_json_form.LanguageSelectorChange(
      code_decl_to_abi_json_form.LanguageSelectorComboBox);
  end
  else if lang = 'c' then
  begin
    code_decl_to_abi_json_form.LanguageSelectorComboBox.ItemIndex := 2;
    code_decl_to_abi_json_form.LanguageSelectorChange(
      code_decl_to_abi_json_form.LanguageSelectorComboBox);
  end
  else
  begin
    Result := '{"error":"Unsupported language. Use ''pascal'' or ''c''."}';
    Exit;
  end;

  // ---- Step 2: push source text into the editor ----
  code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;

  // ---- Steps 3..5: parse -> normalize -> generate ----
  try
    code_decl_to_abi_json_form.ParseSourceToJsonClick(
      code_decl_to_abi_json_form.ParseSourceToJsonButton);
    code_decl_to_abi_json_form.NormalizeJsonToModelClick(
      code_decl_to_abi_json_form.NormalizeJsonToModelButton);
    code_decl_to_abi_json_form.GenerateAllSourcesClick(
      code_decl_to_abi_json_form.GenerateAllSourcesButton);
  except
    on E: Exception do
    begin
      Result := '{"error":"' + EscapeJsonString('Generation failed: ' + E.Message) + '"}';
      Exit;
    end;
  end;

  // ---- Read the produced file list from the ListView ----
  count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;

  resp := TZ_JsonObject.Create;
  try
    resp.S['status'] := 'ok';
    resp.I['count'] := count;

    // Try to read unit_name out of the model JSON the form just produced.
    modelJo := TZ_JsonObject.Create;
    try
      if modelJo.ParseText(code_decl_to_abi_json_form.ModelJsonEditor.Text) then
        resp.S['unit_name'] := modelJo.S['UnitName']
      else
        resp.S['unit_name'] := '';
    finally
      modelJo.Free;
    end;

    fileArr := resp.A['files'];
    for i := 0 to count - 1 do
      fileArr.Add(code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption);

    Result := resp.ToJSONString(False);
  finally
    resp.Free;
  end;
end;
```

**Key points**:

- **Language validation is performed first**. Invalid language short-circuits
  the entire body.
- **The three button handlers are called in order**: parse, normalize,
  generate.
- **The result is read from the ListView**, not from a form-level file manifest.
  This is deliberate: the ListView is populated by the generation step itself,
  so it is always consistent with the disk state.
- **`unit_name` is extracted from the model JSON** in the form's
  `ModelJsonEditor`. If the generation produced a model, the field is present.
- **The response JSON is produced via `TZ_JsonObject.ToJSONString(False)`**. The
  `False` argument means "not formatted".

### 15.3 `internal_call_CodeDeclToJsonAbi_ListFiles`

**Signature**: `function(): string`

**Body**:

```pascal
procedure Do_Sync___();
var
  i, count: integer;
  resp: TZ_JsonObject;
  fileArr: TZ_JsonArray;
begin
  if code_decl_to_abi_json_form = nil then
  begin
    Result := '{"status":"error","count":0,"files":[]}';
    Exit;
  end;

  count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;

  resp := TZ_JsonObject.Create;
  try
    resp.S['status'] := 'ok';
    resp.I['count'] := count;
    fileArr := resp.A['files'];
    for i := 0 to count - 1 do
      fileArr.Add(code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption);
    Result := resp.ToJSONString(False);
  finally
    resp.Free;
  end;
end;
```

**Key points**:

- **Pure reader**. No generation, no disk I/O.
- **Walks the ListView and reads each item's `Caption`**.
- **Returns the empty list if the form is missing or the list is empty**. This
  is not an error; it just means `Generate` has not run yet.

### 15.4 `internal_call_CodeDeclToJsonAbi_GetFile`

**Signature**: `function(FileName: string): string`

**Body**:

```pascal
procedure Do_Sync___();
var
  i: integer;
  found: boolean;
  filePath, textContent: string;
  resp: TZ_JsonObject;
  fs: TFileStream;
  bytes: TBytes;
begin
  if code_decl_to_abi_json_form = nil then
  begin
    resp := TZ_JsonObject.Create;
    try
      resp.S['status'] := 'error';
      resp.S['name'] := FileName;
      resp.S['error'] := 'Form not available';
      Result := resp.ToJSONString(False);
    finally
      resp.Free;
    end;
    Exit;
  end;

  // ---- Locate the entry in the ListView ----
  found := False;
  filePath := '';
  for i := 0 to code_decl_to_abi_json_form.final_source_file_ListView.Items.Count - 1 do
    if code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption = FileName then
    begin
      if code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems.Count > 0 then
        filePath := code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems[0];
      found := True;
      Break;
    end;

  resp := TZ_JsonObject.Create;
  try
    resp.S['name'] := FileName;

    if not found then
    begin
      resp.S['status'] := 'error';
      resp.S['error'] := 'File not found. Call ListFiles first to get valid names.';
      Result := resp.ToJSONString(False);
      Exit;
    end;

    // ---- Read the file content as UTF-8 ----
    textContent := '';
    if FileExists(filePath) then
    begin
      fs := TFileStream.Create(filePath, fmOpenRead or fmShareDenyNone);
      try
        if fs.Size > 0 then
        begin
          SetLength(bytes, fs.Size);
          fs.ReadBuffer(bytes[0], fs.Size);
          textContent := TEncoding.UTF8.GetString(bytes);
        end;
      finally
        fs.Free;
      end;
    end;

    resp.S['status'] := 'ok';
    resp.S['text'] := textContent;
    Result := resp.ToJSONString(False);
  finally
    resp.Free;
  end;
end;
```

**Key points**:

- **Matches by `Caption` (the file name)**, not by `SubItems[0]` (the full
  path). This ensures the caller-supplied name is the visible name, not a
  path.
- **Reads the file at `SubItems[0]`**. Uses `TFileStream` and
  `TEncoding.UTF8.GetString`. This produces a Unicode string that
  `TZ_JsonObject.ToJSONString` will then JSON-escape correctly.
- **File not found is a normal error case**, not an exception. The caller is
  expected to have received the file name from `ListFiles`.
- **Do not rely on the selected item**. The implementation walks the list
  itself; the current selection is irrelevant.

---

## Chapter 16  The UI Operation Pattern

### 16.1 The Rules

1. **Every UI touch must be inside `Do_Sync___` (or the anonymous procedure).**
   The body runs on the main thread; the outer function runs on a worker
   thread.
2. **Never call a UI method directly from the worker thread.** The LCL is not
   thread-safe.
3. **Never modify the form from a callback.** The callback runs on a
   LingoFuse worker thread.
4. **Do not use `TThread.Queue` or `Synchronize` directly**. Use
   `TCompute.Sync`; it is the pattern every other tool follows.
5. **Do not cache UI state in local variables across calls.** The form is
   shared; another agent call may have overwritten the state.

### 16.2 Reading a GUI Value

```pascal
value := code_decl_to_abi_json_form.SomeEditor.Lines.Text;
```

**Notes**:

- `SomeEditor` is a `TSynEdit`. Its `.Lines` is a `TStrings`.
- Reading `.Lines.Text` returns the entire content as a single string with
  `#13#10` line separators (or `#10` on Unix).
- For a `TMemo`, the same pattern applies.

### 16.3 Writing a GUI Value

```pascal
code_decl_to_abi_json_form.SomeEditor.Text := newValue;
```

**Notes**:

- `Text` is a property that accepts a single string. The editor splits it on
  line separators.
- Write `Text`, not `Lines.Add`. `Text :=` replaces the entire content.

### 16.4 Triggering a Button Handler

```pascal
code_decl_to_abi_json_form.SomeButtonClick(
  code_decl_to_abi_json_form.SomeButton);
```

**Notes**:

- The handler takes a `Sender: TObject` parameter. Pass the button itself.
- Do not call `SomeButton.Click`. That would work in principle but is less
  reliable than calling the handler directly.
- Handlers are not re-entrant. If the handler is already running on the main
  thread, calling it again from `Do_Sync___` would deadlock. In practice this
  cannot happen because `Do_Sync___` runs on the main thread and the handler
  is synchronous.

### 16.5 Switching Tabs

```pascal
code_decl_to_abi_json_form.MainPageControl.ActivePage :=
  code_decl_to_abi_json_form.SomeTabSheet;
```

**Notes**:

- The form has two tab controls: `MainPageControl` (outer) and
  `FinalSourcePageControl` (inner, inside the "Final Source" tab).
- To show a specific artifact editor, set both.
- To show a top-level tab (source, model JSON), set `MainPageControl` only.

### 16.6 Reading the ListView

```pascal
count := code_decl_to_abi_json_form.final_source_file_ListView.Items.Count;
for i := 0 to count - 1 do
begin
  name := code_decl_to_abi_json_form.final_source_file_ListView.Items[i].Caption;
  path := code_decl_to_abi_json_form.final_source_file_ListView.Items[i].SubItems[0];
end;
```

**Notes**:

- `Items[i]` is a `TListItem`.
- `Caption` is the file name.
- `SubItems[0]` is the full path.
- The list is empty until `GenerateAllSourcesClick` runs.

### 16.7 Building JSON Responses

Use `TZ_JsonObject`:

```pascal
resp := TZ_JsonObject.Create;
try
  resp.S['status'] := 'ok';
  resp.I['count'] := 42;
  fileArr := resp.A['files'];
  fileArr.Add('some_name.txt');
  Result := resp.ToJSONString(False);
finally
  resp.Free;
end;
```

**Notes**:

- `S[name]` = string field.
- `I[name]` = integer field.
- `L[name]` = int64 field.
- `F[name]` = double field.
- `B[name]` = boolean field.
- `A[name]` = sub-array; returns a `TZ_JsonArray`.
- `O[name]` = sub-object; returns a `TZ_JsonObject`.
- `ToJSONString(False)` = compact output.
- `ToJSONString(True)` = pretty-printed output.
- **Always pass `False` for wire responses**; the extra whitespace is wasted
  bandwidth.

### 16.8 Escaping JSON Strings Manually

For the rare case where a string must be embedded in a hand-built JSON
response, the provider unit defines a helper `_EscapeJsonString`. **Prefer
building the response with `TZ_JsonObject`**, which handles escaping
automatically.

---

# Part VII — Use and Maintenance

## Chapter 17  Complete Worked Examples

### 17.1 Example — Pascal Source to Python Service

**Input** (`Calculator.pas`):

```pascal
unit Calculator;

interface

// Adds two integers and returns the sum.
function Add(a, b: Integer): Integer;

// Subtracts b from a.
function Sub(a, b: Integer): Integer;

implementation

function Add(a, b: Integer): Integer;
begin
  Result := a + b;
end;

function Sub(a, b: Integer): Integer;
begin
  Result := a - b;
end;

end.
```

**MCP call sequence**:

```json
// 1. Generate
{
  "tool": "CodeDeclToJsonAbi_Generate",
  "arguments": {
    "Source": "unit Calculator;\n\ninterface\n\n// Adds two integers and returns the sum.\nfunction Add(a, b: Integer): Integer;\n\n// Subtracts b from a.\nfunction Sub(a, b: Integer): Integer;\n\nimplementation\n\nfunction Add(a, b: Integer): Integer;\nbegin\n  Result := a + b;\nend;\n\nfunction Sub(a, b: Integer): Integer;\nbegin\n  Result := a - b;\nend;\n\nend.",
    "Language": "pascal"
  }
}
// Response:
// {
//   "status": "ok",
//   "unit_name": "Calculator",
//   "count": 19,
//   "files": ["Calculator_http_json_service_unit.pas", ..., "test_main___.cpp"]
// }
```

```json
// 2. ListFiles
{ "tool": "CodeDeclToJsonAbi_ListFiles", "arguments": {} }
// Response:
// {
//   "status": "ok",
//   "count": 19,
//   "files": ["Calculator_http_json_service_unit.pas", ...]
// }
```

```json
// 3. GetFile
{
  "tool": "CodeDeclToJsonAbi_GetFile",
  "arguments": { "FileName": "Calculator_http_json_service.py" }
}
// Response:
// {
//   "status": "ok",
//   "name": "Calculator_http_json_service.py",
//   "text": "..."
// }
```

**Post-conditions**:

- 19 files under `<exe dir>/Calculator/`.
- The ListView shows all 19 entries.
- Every subsequent `GetFile` returns the current content.

### 17.2 Example — C Header to C++ Call with CMake

**Input** (`Math.h`):

```c
/* Math.h */
#ifndef MATH_H
#define MATH_H

/* Returns the square of x. */
int square(int x);

/* Returns the square root of x. */
double sqrt_of(double x);

#endif
```

**MCP call sequence**:

```json
// 1. Generate
{
  "tool": "CodeDeclToJsonAbi_Generate",
  "arguments": {
    "Source": "/* Math.h */\n#ifndef MATH_H\n#define MATH_H\n\n/* Returns the square of x. */\nint square(int x);\n\n/* Returns the square root of x. */\ndouble sqrt_of(double x);\n\n#endif\n",
    "Language": "c"
  }
}
// Response includes "unit_name": "Math"

// 2. GetFile for the C++ call pair and CMake
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Math_http_json_call.hpp" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Math_http_json_call.cpp" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Math_http_json_call_cpp.md" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "CMakeLists.txt" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "test_main___.cpp" } }
```

**Build**:

```bash
# Place all five files plus the .hpp/.cpp pair in one directory.
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

**Run the service and the test**:

```bash
# Terminal 1: start the bridge
python3 bridge.py --endpoint ipc:Math_http_json --no-precheck

# Terminal 2: start the service
./build/Math_http_json_service

# Terminal 3: run the test
./build/Math_http_json_call_test
```

### 17.3 Example — One Source, All Targets

```json
// 1. Generate the source once
{
  "tool": "CodeDeclToJsonAbi_Generate",
  "arguments": { "Source": "unit Multi; ...", "Language": "pascal" }
}

// 2. Read any target from the same session
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_service_unit.pas" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_call_unit.pas" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_service.py" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_call.py" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_service.hpp" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_service.cpp" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_call.hpp" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_call.cpp" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_call.js" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "Multi_http_json_call_test.html" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "CMakeLists.txt" } }
{ "tool": "CodeDeclToJsonAbi_GetFile", "arguments": { "FileName": "test_main___.cpp" } }
```

**No need to call `Generate` again.** All 19 files come from the single
session.

### 17.4 Example — CLI Batch Generation

```bash
# Pascal service
code_decl_to_json_abi.exe calculator.pas calculator_service.pas

# Pascal call
code_decl_to_json_abi.exe --call calculator.pas calculator_call.pas

# Python service from C header
code_decl_to_json_abi.exe math.h math_service.py

# C++ call pair with CMake
code_decl_to_json_abi.exe --call math.h math_call.hpp
# → writes math_call.hpp, math_call.cpp, math_call_readme.md,
#   CMakeLists.txt, test_main___.cpp

# JavaScript call
code_decl_to_json_abi.exe --call math.h math_call.js
# → writes math_call.js, math_call_readme.md, math_call_test.html
```

### 17.5 Example — GUI Manual Workflow

1. Open the GUI.
2. Tab **Source Code**: paste the source.
3. Select the language in the dropdown (or click **Auto-Detect**).
4. Click **Source → JSON**.
5. Click **JSON → Model**.
6. Click **Generate Source**.
7. Tab **Final Source**: browse the artifacts. They are also on disk under
   `<exe dir>/<UnitName>/`.

---

## Chapter 18  Common Pitfalls and Anti-Patterns

### 18.1 Input-Stage Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 1 | `Generate(src, "python")` | `{"error":"Unsupported language. Use pascal or c."}` | Pass `"pascal"` or `"c"` |
| 2 | `Generate(src, "cpp")` | Same error | Pass `"c"` |
| 3 | `Generate(src, "csharp")` | Same error | Pass `"c"` |
| 4 | Empty `Source` | `Generate` succeeds but `count = 0` | Check the source text |
| 5 | Source that does not parse | `{"error":"Generation failed: ..."}` | Check the parser logs |

### 18.2 Generation-Stage Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 6 | Call `ListFiles` before `Generate` | `{"status":"ok","count":0,"files":[]}` | Call `Generate` first |
| 7 | Call `GetFile` before `Generate` | `{"status":"error","name":"...","error":"File not found..."}` | Call `Generate` first |
| 8 | Expect `Generate` to only produce one target | All 19 files are produced | Read the ones you need |
| 9 | Re-call `Generate` with the same source | Session is replaced; disk is overwritten | Fine, but avoid unnecessary calls |
| 10 | Expect no disk writes | 19 files are written to `<exe dir>/<U>/` | Non-issue; disk state mirrors memory |

### 18.3 Read-Stage Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 11 | Use a wrong file name | `{"status":"error",...}` | Use `ListFiles` first |
| 12 | Use a case-mismatched file name | Same error | Match exactly |
| 13 | Expect `GetFile` to re-run generation | Pure reader | Re-call `Generate` |
| 14 | Ignore the `text` field and read something else | N/A | Read `text` |
| 15 | Assume `text` is truncated at some limit | Not truncated | — |

### 18.4 Type-Stage Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 16 | `Boolean` parameter | Routine dropped silently | Use `Integer` (0/1) or `string` |
| 17 | `array of X` parameter | Routine dropped silently | Serialize to JSON `string` |
| 18 | `record` parameter | Routine dropped silently | Serialize to JSON `string` |
| 19 | `TDateTime` parameter | Routine dropped silently | Use `Double` (Unix timestamp) or `string` |
| 20 | Expect `int64` to be exact in JS | Precision loss > 2^53 | Return strings |

### 18.5 Wire-Protocol Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 21 | GET instead of POST | HTTP 405 | Use POST |
| 22 | Forget `Content-Type` | The bridge may reject | Always set `application/json` |
| 23 | Encode with `ensure_ascii=True` | Non-ASCII characters are `\uXXXX` escaped | Use `ensure_ascii=False` |
| 24 | Manually strip the trailing `\0` from LingoFuse strings | N/A | The bridge does it; do not duplicate |
| 25 | Assume `-3` means the service is down | It means the precheck cache missed | Retry, or use `--no-precheck` |

### 18.6 CMake-Stage Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 26 | `project(name CXX)` | `Cannot determine link language` | Use `project(name C CXX)` |
| 27 | Forget `-DLINGOFUSE_CPP_LIB_DIR` | Configure error | Pass it explicitly or fill it in cmake-gui |
| 28 | Generate two units into one directory | `CMakeLists.txt` and `test_main___.cpp` are overwritten | One directory per unit |
| 29 | Expect the CMake script to stage DLLs | Linker cannot find LingoFuse | Stage DLLs manually or set `PATH` |
| 30 | Delete `test_main___.cpp` before building | Linker error | Keep all five fixed-name files together |

### 18.7 MCP-Specific Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 31 | Access the form from the worker thread | Crash or undefined behavior | Use `TCompute.Sync` |
| 32 | Modify the ListView directly | Not thread-safe | Only read it inside `Do_Sync___` |
| 33 | Assume the ListView reflects the disk | Both are written in the same operation | — |
| 34 | Assume the selection reflects the currently-shown file | The selection is irrelevant | Walk the list yourself |
| 35 | Rename a tool | Breaks external callers | Never rename |
| 36 | Change the tool schema's parameter names | Breaks external callers | Never rename parameters |

### 18.8 Session-Stage Pitfalls

| # | Anti-pattern | Consequence | Correct |
|:-:|--------------|-------------|---------|
| 37 | Run multiple `Generate` calls concurrently | Undefined state | Serialize |
| 38 | Expect state to survive process exit | In-memory | Re-`Generate` |
| 39 | Forget to close the GUI | The MCP endpoint disappears | Keep the GUI running |
| 40 | Kill the GUI during a `Generate` call | The Call hangs; eventually times out | Never kill during a call |

---

## Chapter 19  Modification Guide

### 19.1 Adding a New Target Language

A new target language requires **four coordinated edits**:

1. **A new generator unit** — copy an existing one (e.g.
   `http_py_abi_call_generator_tool.pas`) and rename it. Implement
   `GenerateXxxCode` and `GenerateXxxReadme`.
2. **The GUI form** — add the necessary editors and tab sheet. Register them
   in the `.lfm`.
3. **`GenerateAllSourcesClick`** — add a call to your new generator in the
   `Emit` list. See Chapter 16 of the v2 knowledge base for the pattern.
4. **The provider unit** — add the corresponding tool. **This is the only
   step that touches the MCP layer**, and it is purely mechanical.

The v3 interface reduces to **three tools**, so adding a new target does
**not** require adding new MCP tools. `Generate` will still produce the new
artifact as part of its 19-file (or N-file) batch. `ListFiles` and `GetFile`
work automatically.

### 19.2 Adding a New Type Family

Adding a new ABI family is a **schema change**. It requires:

1. **`Z.Pascal_Func_Model`** — extend `Normalize_ABI_Type` to map the new
   source types to a new normalized family name.
2. **All seven language generators** — extend `IsSupportedABIType`,
   `ABI_Type_To_Pascal_Decl`, `ABI_Type_To_<Target>_Decl`, and the JSON
   helpers.
3. **All seven README generators** — extend the type table in §6.
4. **The CMake generator** — extend `ABI_Type_Is_Supported` in the C++ test
   driver generator if the new family is used in a C++ test.

**Do not add a new family for a single project.** Use the existing three
families, and encode complex values as strings.

### 19.3 Changing the MCP Tool Descriptions

The three tool descriptions are the **single most important user-facing text**
in the project. They appear in the AI's tool list and are the AI's only chance
to correct its default behavior.

**Rules**:

1. **Never shorten a description.** Long is fine.
2. **Always put the role ("Step 1 of 2"), the prerequisite, and the output
   shape in the first 200 characters.**
3. **Always include a WRONG/RIGHT table** for the most common error.
4. **Never change the tool name or parameter names** without coordinating with
   every caller.

### 19.4 Re-Exposing the Intermediate Readers (If Needed)

The v3 MCP layer does not expose the LV0 / LV1 intermediate readers. If you
need to expose them (for example, to build an offline LV1 cache), add two new
`internal_call_*` functions that read
`code_decl_to_abi_json_form.SourceJsonEditor.Text` and
`code_decl_to_abi_json_form.ModelJsonEditor.Text`, respectively. Then add the
corresponding tool schemas to `RegisterTools`. This is a purely additive change
and does not disturb the three existing tools.

### 19.5 Adding a New GUI Artifact Editor

If you add a new artifact (for example, a new target language's README) and
want it visible in the GUI:

1. Add a `TSynEdit` to the form.
2. Add a `TTabSheet` to `FinalSourcePageControl`.
3. Add the editor and the tab sheet to the `.lfm`.
4. In the generator's `Emit` call inside `GenerateAllSourcesClick`, add a
   line that assigns the generator's output to the new editor.

The new artifact becomes visible in the GUI **and** is written to disk **and**
is available via `ListFiles` / `GetFile`. No MCP-side change is needed.

### 19.6 Changing the Unit Normalization Rules

If you change `MakeApiName`, you must change it in **all** of:

- `Z.Pascal_Func_Model` (the model's `UnitName` field is normalized here).
- The four `http_*_abi_*_generator_tool` units.
- `http_cmake_generator_tool`.
- `code_decl_to_json_abi_cmdline` (for CLI-side file naming).
- `code_decl_to_json_abi_mcp_api_tool_provider_unit` (for MCP-side file naming).

The unit normalization affects **every artifact's file name**. A divergence
between the GUI and the MCP layer would produce files with different names in
the two paths. **Do not change this rule casually**.

### 19.7 Changing the CMake Script

The CMake script is generated by `http_cmake_generator_tool.pas`. The
following are **contractual** and must not change without updating the
corresponding documentation and the test driver:

- The project language list (`C CXX`).
- The cache variable name (`LINGOFUSE_CPP_LIB_DIR`).
- The service target name (`<U>_http_json_service`).
- The call test target name (`<U>_http_json_call_test`).
- The expected source file names.

### 19.8 Adding a New Test to the C++ Driver

The C++ test driver (`test_main___.cpp`) is generated by
`GenerateTestMainCpp`. To add a new test category:

1. Add a new function to `EmitTestCall` (or a sibling).
2. Update the `main()` template to call it.
3. Update `http_cmake_generator_tool`'s README section.

The driver is **always** regenerated when `Generate` runs. Manual edits to a
previously-generated `test_main___.cpp` are lost on the next `Generate`.

### 19.9 Version Compatibility

The toolchain has three version-sensitive components:

- **The LingoFuse C ABI** (`lingofuse_import.pas`). The toolchain depends on a
  stable subset; changes to `LF_CreateAppEx`, `LF_RegisterCallEx`,
  `LF_CreateDataEx`, `LF_ReadStringBytes`, `LF_WriteStringBytes`, `LF_CallEx`
  must be coordinated.
- **The Z framework** (`Z.Core`, `Z.Pascal_Func_Model`,
  `Z.Pascal_Func_Tool`, `Z.Json`). The toolchain depends on stable public
  APIs. Internal changes to those libraries do not affect the toolchain.
- **The generated artifacts' dependencies**. The generated Python, JavaScript,
  and C++ artifacts depend on `requests`, `fetch`, and `lf_http_bridge_client.hpp`
  respectively. Major version changes may require regenerating the artifacts.

---

## Chapter 20  Honest Uncertainty List

The following items **cannot be determined from the current source**. When
working on these, inspect the source directly or ask a human.

1. **Whether `GenerateAllSourcesClick` catches exceptions internally.**
   - The button handler is not wrapped in `try/except` in the source.
   - The MCP `Generate` body wraps the call in `try/except` and converts
     exceptions into `{"error": "Generation failed: ..."}`. But an exception
     raised **inside** the handler may leave the form in a partially-updated
     state.

2. **Whether every edge syntax in the test unit sample parses.**
   - The `InsertTestUnitClick` handler contains a stress-test sample.
   - Treat it as a parser test, not a generator test.

3. **Whether the generated HTML test page works under `file://`.**
   - The HTML is self-contained.
   - CORS behavior under `file://` depends on the browser.
   - **Recommendation**: serve the page over `http://` if calls fail.

4. **Whether the CMake script's `test_main___.cpp` reference is always
   satisfiable.**
   - The script expects the file in the same directory.
   - `GenerateAllSourcesClick` writes it unconditionally.
   - The CLI's `Generate_Cpp` also writes it.
   - **Recommendation**: keep the three fixed-name files together.

5. **The exact scope of `FSessionCMakeScript` / `FSessionTestMainCpp`.**
   - Cleared by `Generate` (at the beginning of the run).
   - Populated by the CMake step of `Generate`.
   - **Uncertain**: whether they are cleared by any other code path.

6. **Whether `TZ_JsonString.ToJSONString` emits a BOM.**
   - The bridge strips BOMs from inputs. The generator's outputs are
     UTF-8 without a BOM in practice.
   - **Uncertain**: whether this is guaranteed across all Z framework versions.

7. **The concrete value of `SysTimer` in the GUI.**
   - **Uncertain**: the interval.
   - **Speculation**: 100–500 ms.

8. **Whether the bridge strips the LingoFuse trailing `\0` for every call.**
   - Documented as yes.
   - **Recommendation**: do not rely on the `\0` in HTTP payloads.

9. **Whether `TCompute.Sync` can deadlock if called from the main thread.**
   - The generated MCP bodies call it from a LingoFuse worker thread.
   - **Uncertain**: what happens if the same body is invoked from the main
     thread.
   - **Recommendation**: never call the MCP tools from the GUI's main thread.

10. **Whether all three tool callbacks are registered correctly in every
    build configuration.**
    - The provider unit registers exactly three tools in `RegisterAPIs`.
    - **Uncertain**: whether a compilation flag can drop one of them.

11. **Whether the CMake generator's C++ test driver handles all three type
    families correctly.**
    - The driver emits default arguments for every family.
    - **Uncertain**: whether the C++ call wrapper accepts `std::string()`
      (an empty string) for a `const std::string&` parameter without
      ambiguity.

12. **Whether `MakeApiName`'s handling of `-` is intentional or defensive.**
    - The source replaces `-` with `_`.
    - **Speculation**: defensive; Pascal function names cannot contain `-`.

13. **Whether the `_test.html` page's inline JavaScript is fully safe from
    accidental HTML parsing.**
    - The generator sanitizes `</`, `<!--`, and `-->` sequences in inline
      script.
    - **Uncertain**: whether any other sequence can break out.

14. **The exact behavior of `TCompute.Sync` when the target thread has exited.**
    - **Uncertain**: whether it blocks forever or raises.
    - **Recommendation**: never call `Generate` after the GUI has been
      destroyed.

15. **Whether `LF_CheckApiEx(BEACON_APP, REGISTER_API)` has a 3-second cache.**
    - Documented in the LingoFuse KB.
    - **Uncertain**: whether this specific cache affects the MCP startup.

16. **Whether the CMake script's DLL staging is left to the user in all
    build configurations.**
    - The script does not stage DLLs.
    - **Recommendation**: copy DLLs manually or set `PATH` / `LD_LIBRARY_PATH`.

17. **Whether the CLI and the MCP layer agree on file naming in every edge
    case.**
    - Both use `MakeApiName`.
    - **Uncertain**: whether the CLI's `MakeApiName` matches the GUI's
      `MakeApiName` exactly.

18. **Whether the provider unit's `Try/Except` envelope catches all
    exceptions.**
    - It catches `Exception` (the base class).
    - **Uncertain**: what happens for `EAbort` (FPC) or other non-`Exception`
      exceptions.

19. **Whether the JS generator emits a usable `fetch` call under all
    browsers.**
    - Modern browsers support `fetch`.
    - **Uncertain**: legacy browsers (IE 11) do not.
    - **Recommendation**: test in the target browser.

20. **Whether `GenerateAllSourcesClick` writes the intermediate `source.pas` /
    `source.h` files to disk in every configuration.**
    - The GUI saves them for traceability.
    - **Uncertain**: whether the MCP path skips this.
    - **Speculation**: the MCP path uses the same handler, so the same files
      are written.

---

# Appendix A — Underlying Library Quick Reference

This appendix summarizes the parts of the Z framework and LingoFuse that this
project depends on. You do not need to read their source.

## A.1 `TZ_JsonObject` (from `Z.Json`)

**Construction**: `jo := TZ_JsonObject.Create;` — always free with `jo.Free`.

**Parsing**:

| Call | Effect |
|------|--------|
| `jo.ParseText(S)` | Parse `S` as JSON. Returns `True` on success. |
| `jo.Parae(bytes)` | Parse `bytes` (UTF-8) as JSON. Returns `True` on success. |

**Accessors** (read/write):

| Accessor | Type |
|----------|------|
| `jo.S['name']` | `string` |
| `jo.I['name']` | `Integer` |
| `jo.L['name']` | `Int64` |
| `jo.F['name']` | `Double` |
| `jo.B['name']` | `Boolean` |
| `jo.A['name']` | `TZ_JsonArray` (sub-array) |
| `jo.O['name']` | `TZ_JsonObject` (sub-object) |

**Existence**:

| Call | Effect |
|------|--------|
| `jo.Exists(name)` | `True` if the field is present |
| `jo.IndexOf(name)` | Field index, or `-1` |
| `jo.Count` | Number of fields |

**Serialization**:

| Call | Effect |
|------|--------|
| `jo.ToBytes` | UTF-8 byte array |
| `jo.ToJSONString(False)` | Compact string |
| `jo.ToJSONString(True)` | Pretty-printed string |

**Clearing**: `jo.Clear` — resets to an empty object.

## A.2 `TZ_JsonArray`

**Access**: `arr := jo.A['name']` — do not free; owned by `jo`.

**Operations**:

| Call | Effect |
|------|--------|
| `arr.Add('string')` | Append a string |
| `arr.Add(Int64(...))` | Append an integer |
| `arr.AddF(Double(...))` | Append a float |
| `arr.S[i]` / `arr.L[i]` / `arr.F[i]` | Read the i-th element |
| `arr.Count` | Number of elements |
| `arr.Clear` | Remove all |

## A.3 `TCompute` (from `Z.Core`)

**The one function this project uses**:

```pascal
TCompute.Sync(procedure begin ... end);   // Delphi
TCompute.Sync(Do_Sync___);                // FPC (nested procedure)
```

**Semantics**: schedules the procedure on the main thread, blocks the caller
until the procedure finishes.

**Error handling**: exceptions raised inside the procedure propagate to the
caller.

## A.4 `LF_*` (from `lingofuse_import`)

The subset this project uses:

| Function | Effect |
|----------|--------|
| `LF_CreateAppEx(name, desc)` | Create a LingoFuse App. Returns `TAppHnd___` or `nil`. |
| `LF_FreeApp(app)` | Destroy an App. |
| `LF_RegisterCallEx(app, api, desc, trigger, callback)` | Register a Call API. |
| `LF_CreateDataEx(api)` | Create a data handle for the given API name. |
| `LF_FreeData(hnd)` | Destroy a data handle. |
| `LF_ReadStringBytes(hnd)` | Read the handle's content as UTF-8 bytes. |
| `LF_WriteStringBytes(hnd, bytes)` | Write bytes to the handle (appends a trailing `\0`). |
| `LF_GetSize(hnd)` | Size of the handle's content. |
| `LF_CallEx(app, data, timeout)` | Call `app` with `data`. Returns a response handle or `nil`. |
| `LF_PrepareClientEx(endpoint, app)` | Prepare a client to `endpoint`. |
| `LF_PrepareDone()` | Finalize the connection. Returns `1` on first call, `0` thereafter. |
| `LF_CheckMainThreadEx()` | `True` if the LingoFuse main thread is running. |
| `LF_CheckApiEx(app, api)` | `True` if the API is registered. |
| `LF_SetOptionEx(name, value)` | Set a global option. |
| `LF_ExitMainThread()` | Stop the LingoFuse main loop. |
| `LF_Shutdown()` | Release all LingoFuse resources. |

**Callback signature** (for `LF_RegisterCallEx`):

```pascal
procedure MyCallback(_Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
```

- `_Trigger___` is the user-supplied trigger pointer (usually `nil`).
- `_In___` is the input handle. **Read only**.
- `_Out___` is the output handle. **Write only**.
- **Never free `_In___` or `_Out___`**; they are owned by the framework.
- **Never call blocking LF functions** inside the callback.

## A.5 `TFileStream` (from `Classes`)

```pascal
fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
try
  SetLength(bytes, fs.Size);
  fs.ReadBuffer(bytes[0], fs.Size);
finally
  fs.Free;
end;
```

**Note**: `bytes` must be pre-sized. A zero-size file yields an empty array.

## A.6 `TEncoding.UTF8` (from `SysUtils`)

```pascal
// bytes → string
textContent := TEncoding.UTF8.GetString(bytes);

// string → bytes
bytes := TEncoding.UTF8.GetBytes(textContent);
```

## A.7 `TPascal_Func_Model` (from `Z.Pascal_Func_Model`)

Used only inside the generator units, not by the MCP layer. Public API:

| Method | Effect |
|--------|--------|
| `Create` | Construct an empty model |
| `LoadFromParser(Tool, Report)` | Fill from an LV0 parser tool |
| `LoadFromJson(S)` | Fill from an LV1 JSON string |
| `SaveToJson` | Produce LV1 JSON |
| `Funcs.Count` | Number of functions |
| `Funcs[i]` | `TFunctionStructure` for function `i` |
| `UnitName` | The parsed unit name |

## A.8 `tpascal_func_decl_tool` (from `Z.Pascal_Func_Tool`)

Used only inside the CLI and the GUI's parse button handler. Public API:

| Method | Effect |
|--------|--------|
| `CreateFrom_Pascal_Code(S)` | Construct and parse a Pascal unit |
| `CreateFrom_C_Code(S)` | Construct and parse a C header |
| `SaveToJson` | Produce LV0 JSON |
| `decl_to_pascal(Report)` | Re-emit top-level declarations as Pascal |
| `decl_to_c(Report)` | Re-emit top-level declarations as C |
| `ParseSuccess` | `True` if the parse succeeded |

---

# Appendix B — File Name Naming Cheat Sheet

## B.1 Language-Specific Artifacts

```
<UnitName>_http_json_<side>.<ext>

side ∈ {service, call}
ext  ∈ {pas, py, hpp, cpp, js, html, md}
```

**Examples**:

| Unit | Side | Extension | Full name |
|------|:----:|:---------:|-----------|
| `Calc` | service | `py` | `Calc_http_json_service.py` |
| `Calc` | call | `js` | `Calc_http_json_call.js` |
| `Calc` | call | `hpp` | `Calc_http_json_call.hpp` |
| `Calc` | call | `md` | `Calc_http_json_call_cpp.md` |
| `My_Unit` | service | `md` | `My_Unit_http_json_service_pascal.md` |

## B.2 Fixed-Name Artifacts

| File | Written by |
|------|-----------|
| `CMakeLists.txt` | CMake generator |
| `test_main___.cpp` | CMake generator |

## B.3 README Suffixes

| Target | Suffix |
|--------|--------|
| Pascal | `_pascal.md` |
| JavaScript | `_js.md` |
| Python | `_python.md` |
| C++ | `_cpp.md` |

## B.4 The `_test.html` File

Fixed name pattern: `<UnitName>_http_json_call_test.html`.

## B.5 The Complete List (for reference)

```
<U>_http_json_service_unit.pas
<U>_http_json_service_pascal.md
<U>_http_json_call_unit.pas
<U>_http_json_call_pascal.md
<U>_http_json_call.js
<U>_http_json_call_js.md
<U>_http_json_call_test.html
<U>_http_json_service.py
<U>_http_json_service_python.md
<U>_http_json_call.py
<U>_http_json_call_python.md
<U>_http_json_service.hpp
<U>_http_json_service.cpp
<U>_http_json_service_cpp.md
<U>_http_json_call.hpp
<U>_http_json_call.cpp
<U>_http_json_call_cpp.md
CMakeLists.txt
test_main___.cpp
```

Total: 19 files.

---

**Document version**: v3
**Document role**: single authoritative reference for `code_decl_to_json_abi`.
**If a discrepancy with the source is found, the source prevails.**
