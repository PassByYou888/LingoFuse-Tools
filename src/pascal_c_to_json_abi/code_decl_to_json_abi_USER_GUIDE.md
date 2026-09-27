# code_decl_to_json_abi User Guide (v3)

> This document describes **how to use** `code_decl_to_json_abi`, covering:
>
> - Graphical User Interface (GUI) operation
> - Command-Line Interface (CLI) operation
> - Remote invocation from an agent (MCP / LingoFuse)
> - **Programmatic interface** (embedding the generator in your own tools)
>
> **The single most important rule at runtime**: the **bridge must always be
> running**. Every generated artifact that performs a call ultimately depends
> on it. See Chapter 2.
>
> **The single most important rule after generation**: **read the generated
> `.md` files**. The real interface code, test programs, and build scripts —
> including the C++ CMake script — live inside them. See Chapter 3.
>
> **New in v3**: the MCP API has been reduced from 24 tools to **exactly
> three**:
>
> - `CodeDeclToJsonAbi_Generate(Source, Language)`
> - `CodeDeclToJsonAbi_ListFiles()`
> - `CodeDeclToJsonAbi_GetFile(FileName)`
>
> A single `Generate` call now produces **every target language** — Pascal,
> Python, C++, C#, JavaScript — plus the CMake build script and the C++
> test driver. The 3-tool shape removes the discoverability problem of the
> previous 24-tool API and lets an agent complete a full generation cycle
> in two calls.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [⚠️ Global Prerequisite: The Bridge Must Always Be Running](#2-️-global-prerequisite-the-bridge-must-always-be-running)
3. [⚠️ Read This First: The Generated Markdown Is The Real Deliverable](#3-️-read-this-first-the-generated-markdown-is-the-real-deliverable)
4. [Environment Preparation](#4-environment-preparation)
5. [GUI Operation Guide](#5-gui-operation-guide)
6. [Command-Line Guide](#6-command-line-guide)
7. [Agent (MCP-API) Guide — The Three Tools](#7-agent-mcp-api-guide--the-three-tools)
8. [How the MCP Tool Provider Unit Is Built](#8-how-the-mcp-tool-provider-unit-is-built)
9. [Programmatic Interface](#9-programmatic-interface)
10. [Artifact Inventory](#10-artifact-inventory)
11. [JSON Safety and Stability](#11-json-safety-and-stability)
12. [Language Support: Today and Tomorrow](#12-language-support-today-and-tomorrow)
13. [Frequently Asked Questions](#13-frequently-asked-questions)

---

## 1. Project Overview

`code_decl_to_json_abi` is a **prototype-declaration → HTTP/JSON interface
code generator**.

Give it a Pascal unit or a C header, and it will:

1. Parse out every top-level function/procedure declaration;
2. Normalize them into an intermediate model (the LV1 Model);
3. Generate a complete set of **HTTP POST + JSON** interface code covering
   every supported language and both directions, **26 files in total**:
   - 18 code / README artifacts;
   - 7 C# artifacts (service code, call code, both test drivers, and their
     READMEs);
   - 1 CMake build script (`CMakeLists.txt`);
   - 1 C++ test driver (`test_main___.cpp`).

### Supported source languages

Only two source languages are accepted:

- **Pascal** (`.pas` / `.pp` / `.p`)
- **C** (`.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx`)

### Supported target languages

| Target | Service (exposes the API) | Call (invokes the API) | Extra |
|--------|---------------------------|------------------------|-------|
| Pascal | ✅ `<unit>_http_json_service_unit.pas` | ✅ `<unit>_http_json_call_unit.pas` | — |
| Python | ✅ `<unit>_http_json_service.py` | ✅ `<unit>_http_json_call.py` | — |
| C++ | ✅ `.hpp` + `.cpp` (two files) | ✅ `.hpp` + `.cpp` (two files) | CMake script + C++ test driver |
| C# | ✅ `<unit>_http_json_service.cs` | ✅ `<unit>_http_json_call.cs` | Service test + call test + test README |
| JavaScript | ❌ (no service side) | ✅ `.js` + bundled test page `.html` | — |
| Per-target companion | ✅ Markdown README | ✅ Markdown README | — |

**One-sentence summary**: you write one Pascal unit or one C header; the tool
lays out every cross-language, cross-process HTTP/JSON interface you need —
including the CMake build script for the C++ side and the full test suite for
the C# side.

---

## 2. ⚠️ Global Prerequisite: The Bridge Must Always Be Running

> **This is the most important runtime prerequisite. Read this chapter before
> anything else.**

### 2.1 What the bridge is

**`bridge.py` (or a compiled `bridge.exe`) is the HTTP↔RPC forwarding tool
provided by LingoFuse.**

Its only job is: **translate an HTTP request into a LingoFuse internal call,
and translate the return value back into an HTTP response.**

```
HTTP client  ──HTTP POST──▶  bridge.py / bridge.exe  ──LF_Call──▶  service
HTTP client  ◀─HTTP resp──   bridge.py / bridge.exe  ◀─LF ret───   service
```

### 2.2 Why it must always be running

**Every call-side artifact** this tool generates (Pascal / Python / C++ / C# /
JavaScript) and the **bundled HTML test page** do **not** talk to the service
directly. They all go through the bridge:

- **Pascal call side**: uses `LFHttpPost` internally to reach the bridge over
  LingoFuse.
- **Python call side**: uses `requests.post(...)` against the bridge's HTTP
  endpoint.
- **C++ call side**: reaches the bridge through the LingoFuse C ABI.
- **C# call side**: reaches the bridge through the LingoFuse .NET binding.
- **JavaScript call side**: uses `fetch(...)` to POST directly to the bridge's
  HTTP endpoint.
- **HTML test page**: same as the JavaScript client.
- **C++ test driver** (`test_main___.cpp`): same as the C++ call side — it goes
  through `lingofuse::bridge::httpCall`.
- **C# test drivers**: same as the C# call side.

**As long as the bridge is not running, all of the above call sides and test
pages will fail immediately.** Typical symptoms:

- `EHTTPCallError: ... Network error` (Pascal)
- `HTTPCallError: Network error` (Python)
- `HTTPCallError: ... (code=-1, http_status=0)` (C++)
- `HTTPCallError: ... (code=-1, http_status=0)` (C#)
- `Failed to fetch` / CORS errors (JS / browser)
- `Connection refused` (manual `curl` test)

### 2.3 Bridge lifecycle rules

| Rule | Description |
|------|-------------|
| **Must be started separately** | The bridge is an independent process. It runs **separately** from your call side and your service. |
| **Must stay resident** | As long as you intend to call the interface or run the test page, the bridge **must stay up**. |
| **Do not share a terminal** | Start the bridge in its **own terminal**. Do not squeeze it into the same terminal as the call side or the service. |
| **Must be ready before the call side** | Recommended startup order: **service → bridge → call side**. |
| **Restart to recover** | If the bridge crashes or is killed, just re-run it; the call side does not need to be restarted. |

### 2.4 Recommended three-process layout

```
Terminal 1 (service):       start the generated service (Pascal / Python / C++ / C#)
Terminal 2 (bridge):        python3 bridge.py --endpoint <same endpoint as the service> --port 8081 --no-precheck
Terminal 3 (caller / page): start the generated call side, or double-click the HTML test page
```

**The bridge must stay in the foreground in Terminal 2.** Only after you see
it print the HTTP listening log may you begin invoking.

### 2.5 Common misunderstandings

- ❌ "Once the code is generated, I can call it directly." → No — the bridge
  must be running.
- ❌ "I only generate code inside the GUI, so I don't need the bridge." → **The
  GUI generation step genuinely does not need the bridge**, but the moment you
  **run** the generated code or open the test page, you do.
- ❌ "The bridge and the service are an either/or choice." → **Both must be
  running simultaneously.**
- ❌ "The bridge only needs to run once, then I can close it." → Closing the
  bridge closes the entire HTTP↔RPC path.

> **Memorize one sentence: the bridge (`bridge.py` / `bridge.exe`) is a
> forwarder and must always be running.**

---

## 3. ⚠️ Read This First: The Generated Markdown Is The Real Deliverable

> **This is the most important post-generation rule. It changes how you
> consume everything the tool produces.**

Every generated code artifact is paired with a companion **Markdown
document**. That `.md` is not a "nice-to-have" — **it is where the real,
runnable interface material lives.** When `code_decl_to_json_abi` produces,
say, a C++ service, it writes:

- `<Unit>_http_json_service.hpp` + `<Unit>_http_json_service.cpp` — the
  generated C++ skeleton.
- `<Unit>_http_json_service_cpp.md` — **the companion document, and the real
  deliverable.**
- `CMakeLists.txt` + `test_main___.cpp` — the CMake build script and the test
  driver that the `.md`'s CMake section references by name.

### 3.1 What every generated `.md` contains

Each `<Unit>_http_json_<lang>.md` file contains, at minimum:

1. **A complete, copy-pasteable test program.**
   - **Pascal**: a full `.lpr` program you can compile as-is, with the exact
     `fpc -Fu<...>` command lines (search paths for `lingofuse_import.pas`,
     `Z.Core`, and the generated unit).
   - **Python**: the generated module already contains
     `if __name__ == "__main__":`, so the "test program" **is** the module
     itself; the `.md` tells you which environment variables and `PYTHONPATH`
     to set.
   - **C++**: a full `main.cpp`, plus **a CMake script and raw compiler
     invocations (g++, clang++, MSVC)**. The CMake target names, include
     directories, source files, link libraries, and required C++ standard are
     all spelled out. The `.md`'s CMake section references `CMakeLists.txt`
     and `test_main___.cpp` — both of which are already generated alongside
     the `.hpp`/`.cpp` pair.
   - **C#**: two test programs (a service driver and a call driver) plus a
     test README, all designed to be copied into a `dotnet new console`
     project.
   - **JavaScript**: a self-contained HTML test page alongside the `.js`,
     plus instructions on how to serve it.

2. **The full interface reference for that artifact.**
   - Every API the artifact exposes.
   - Its typed signature in the target language.
   - The **request layout** and **success response layout** on the wire.
   - A **call example** per API.

3. **The build instructions for that specific language.**
   - **C++ CMake script** — target names, sources, includes, libraries,
     standard. The README shows the exact
     `cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=...` invocation.
   - **Pascal** — `lazbuild` project steps and `fpc -Fu<...>` command lines.
   - **Python** — `pip install` / `PYTHONPATH` setup for cmd, PowerShell, and
     bash.
   - **C#** — `dotnet new console` / `dotnet add reference` / `dotnet run`
     steps.
   - **JavaScript** — how to open the test page, and how to include the `.js`
     in your own page.

4. **The deployment section.**
   - Which directories the runtime expects (`LingoFuse64.dll` /
     `liblingofuse.so` / `liblingofuse.dylib`, `z_ipc_*`).
   - Startup order: **service → bridge → caller**.
   - Shutdown order.
   - Environment variables that must be set on each OS.

5. **The troubleshooting table for that artifact.**
   - Symptom → cause → fix, tuned to the specific target language.

> **Rule of thumb**: whenever you finish generating code, **open the `.md`
> first**.

### 3.2 Why the Markdown is generated alongside the code

The `.md` and the code are generated from **the same `TPascal_Func_Model`** in
the same pass. This guarantees:

- **They never drift apart.**
- **The `.md` always describes the current code.**
- **You can hand the `.md` to another engineer (or to an agent) and they can
  reproduce your build.**

### 3.3 What you will typically not find in the `.md`

- **Business logic.** The `internal_call_<Api>` stubs are deliberately left
  empty; you fill them in.
- **A ready-made CMake project for your entire application.** The `.md` gives
  you the CMake script for the generated artifact; wiring it into a larger
  project is your choice.
- **Credentials or deployment secrets.**

### 3.4 How to find the `.md` files

| Entry | Where to look |
|-------|---------------|
| **GUI** | Each sub-tab of the **Final Source** page shows **two editors**: the code, and the companion `.md`. Both are also on disk under `<exe dir>/<UnitName>/`. |
| **CLI** | Next to `<base>.<ext>`, the tool also writes `<base>_readme.md`. |
| **MCP** | After `Generate`, call `ListFiles` to see every `.md`, then `GetFile` to read the one you need. |

### 3.5 Practical consequence for this guide

Because the `.md` files carry the language-specific details, this user guide
does **not** try to reproduce every build command for every language. Instead:

- Chapters 5–7 cover the **three frontends** and how to drive them.
- Chapter 8 covers the **bootstrap → AI-fill architecture** of the MCP
  provider unit.
- Chapter 9 covers the **programmatic interface**.
- Chapters 10–11 cover the **artifact inventory, wire format, and JSON
  safety** — the cross-language invariants.
- **For any language-specific build, test, or CMake question, the answer is
  in the generated `.md`, not here.**

---

## 4. Environment Preparation

### 4.1 Running the tool directly

Run `code_decl_to_json_abi` from its executable directory. The program will
look for the following files next to itself:

- `pascal_code_abi_rule.md` (Pascal prototype rules)
- `C_code_abi_rule.md` (C prototype rules)

Missing them does not block usage; it merely makes the GUI's "rule document"
buttons inert.

### 4.2 Dependencies for the generation phase

- **The generation phase (GUI / CLI) has no extra dependencies.** The tool
  itself does not go online, and it does not use the bridge.
- **Running the generated code / test page** is when the bridge and the
  service come into play.

### 4.3 Dependencies for the runtime phase

| Component | Purpose | Required? |
|-----------|---------|:---------:|
| **Service** (compiled from the generated `*_service_*` code) | Provides the business logic | ✅ Required |
| **Bridge** (`bridge.py` or `bridge.exe`) | HTTP ↔ RPC forwarding | ✅ **Must always be running** |
| **Call side** (compiled from the generated `*_call_*` code, or the HTML test page) | Issues calls | On demand |
| **CMake ≥ 3.15** (for C++ targets only) | Builds the generated C++ pair | On demand |
| **.NET 8 SDK** (for C# targets only) | Builds the generated C# project | On demand |

### 4.4 Dependencies for C++ targets

The CMake script produced by the toolchain requires:

- **CMake 3.15** or later.
- A C **and** C++ compiler (the project declares `project(<name> C CXX)`).
- The LingoFuse C++ distribution directory, supplied as
  `LINGOFUSE_CPP_LIB_DIR`. It must contain `LingoFuse.h`, `LingoFuse.c`,
  `LingoFuse.hpp`, `lf_io.hpp`, `lf_http_bridge_client.hpp`, and `json.hpp`.

### 4.5 Dependencies for C# targets

The generated C# artifacts require:

- **.NET 8.0** or later.
- The **LingoFuse .NET binding** (`LingoFuse.dll`).
- The **LingoFuse native library** (`LingoFuse64.dll` / `liblingofuse.so` /
  `liblingofuse.dylib`) and `z_ipc_*`.

### 4.6 Agent mode

Agent mode requires the LingoFuse runtime:

- `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`
- `z_ipc_*.dll` / `libz_ipc_*.so`
- A Beacon service (`agent_main_app`) must be online

If you only use the local GUI / CLI, none of these runtime dependencies are
needed.

---

## 5. GUI Operation Guide

### 5.1 Launching the GUI

**Run the executable with no command-line arguments.** The GUI opens directly.

The GUI has 5 top-level tabs, advancing left to right:

```
[1. Welcome] → [2. Source Code] → [3. Source ↔ JSON] → [4. JSON ↔ Model] → [5. Final Source]
```

Each tab has a row of "previous / next" buttons at the top, and a bottom
panel showing the live `DoStatus` log.

At startup, the form also silently starts the **MCP service** on a background
thread (see Chapter 7).

### 5.2 Page 1 — Welcome

- Shows the tool's overall description, architecture diagram, and workflow.
- Right-side buttons:
  - **Pascal rule doc** — opens `pascal_code_abi_rule.md`.
  - **C rule doc** — opens `C_code_abi_rule.md`.
- **Next: Enter source code** — jumps to Page 2.

### 5.3 Page 2 — Source Code

This page is where you **input the code**.

**Top toolbar**:

| Control | Purpose |
|---------|---------|
| **Select Language label** | Click to auto-detect the source language. |
| **Language Selector dropdown** | `Auto-detect` / `Pascal` / `C`, manual choice. |
| **Format** | Keep only top-level functions; rebuild a minimal declaration. |
| **Empty unit** | Insert a minimal skeleton (Pascal or C). |
| **Test unit** | Insert a complex sample covering many syntax forms (recommended for a first run). |
| **Next: Pascal/C → JSON** | Parse the current source, produce LV0 JSON, jump to Page 3. |

**Steps**:

1. Paste your Pascal unit or C header into the editor.
2. If you are unsure of the language, click **Select Language** to let the
   tool detect it.
3. If the syntax highlighting looks wrong, pick the language manually from
   the dropdown.
4. Click **Next: Pascal/C → JSON**.

### 5.4 Page 3 — Source ↔ JSON

This page displays the **raw parser output (LV0)**.

| Button | Purpose |
|--------|---------|
| **Back: rebuild code from JSON** | Rebuild source code from the current JSON, write it back to Page 2. |
| **Next: JSON ↔ Model** | Normalize LV0 into LV1 Model, jump to Page 4. |

You may **manually correct the JSON here** — for example, if the parser
misclassifies a type, edit the string in the JSON directly and click **Next**
to continue.

### 5.5 Page 4 — JSON ↔ Model

This page displays the **normalized model JSON (LV1)**.

| Button | Purpose |
|--------|---------|
| **Back: JSON ↔ Model** | Reverse-restore LV1 to LV0, write back to Page 3. |
| **Next: generate source** | Generate all 26 artifacts, jump to Page 5. |

**Tip**: the model JSON automatically drops unsupported types (`Boolean`,
`Variant`, arrays, records, classes, interfaces, enums, sets, pointers,
`Currency`, `TDateTime`, etc.). If a function does not appear in the final
artifacts, it almost always has an unsupported ABI type in its parameters or
return value.

### 5.6 Page 5 — Final Source

This page has **9 sub-tabs**, each showing **two editors** (code + companion
`.md`):

| Sub-tab | Content |
|---------|---------|
| Pascal Service | Pascal service code + README |
| Pascal Call | Pascal call code + README |
| JavaScript Call | JS client code + README |
| JavaScript Test HTML | Self-contained HTML test page |
| Python Service | Python service code + README |
| Python Call | Python call code + README |
| C# Service | C# service code + README |
| C# Call | C# call code + README |
| C# Test | Service test driver + call test driver + test README |
| C++ Service | C++ service `.hpp` + `.cpp` + README |
| C++ Call | C++ call `.hpp` + `.cpp` + README |
| **CMake** | **`CMakeLists.txt` + `test_main___.cpp`** |

> **Open the `.md` sub-tab first.** See Chapter 3. The `.md` is where the
> build commands, CMake scripts, and test programs live.

**Files have already been written to disk**: during generation, all 26 files
are automatically written to the `<UnitName>/` subdirectory of the
executable's directory.

Top button:

- **Back: Model JSON** — return to Page 4 to keep adjusting the model.

### 5.7 The CMake sub-tab

The CMake sub-tab shows the two fixed-name artifacts:

- `CMakeLists.txt` — the CMake build script.
- `test_main___.cpp` — the C++ call test driver.

These are written to `<exe dir>/<UnitName>/` and are the exact files that the
C++ README's "Building – CMake" section references. **Copy them out of this
tab (or from the disk directory) along with the `.hpp`/`.cpp` pair**, and the
CMake project is complete.

### 5.8 The C# Test sub-tab

The C# Test sub-tab shows the three C# test artifacts:

- `<Unit>_http_json_service_main_test___.cs` — the service-side test program.
- `<Unit>_http_json_call_main_test___.cs` — the call-side test program.
- `<Unit>_http_json_test_csharp.md` — the test README.

Both test programs are designed to be copied into a `dotnet new console`
project as `Program.cs`, alongside the corresponding service or call module.

### 5.9 Log panel

The bottom panel is the live `DoStatus` log. It shows which file was just
saved, any dropped routines during normalization, and any errors from the
generators. It clears itself when it exceeds 5000 lines.

---

## 6. Command-Line Guide

### 6.1 Trigger condition

Command-line mode **only triggers when at least one argument is passed**. No
arguments = GUI.

The program is built for the console subsystem, therefore:

- Double-click = launch GUI (the system may pop up an extra empty console
  window; closing the main window ends it).
- Command-line run = all `DoStatus` messages go straight to stdout, and
  normal completion returns via exit codes.

### 6.2 Syntax

```
code_decl_to_json_abi --help
code_decl_to_json_abi <input_file> <output_file>
code_decl_to_json_abi --call <input_file> <output_file>
```

| Argument | Description |
|----------|-------------|
| `--help` / `-h` / `-?` / `/?` | Print help and exit. **Recognized only as the 1st argument.** |
| `--call` / `-c` | Generate the call side. **Recognized only as the 1st argument**; default is the service side. |
| `<input_file>` | The input source file. Language is determined by **extension**. |
| `<output_file>` | The output file. Target language is determined by **extension**. |

### 6.3 Input extension → source language

| Extension | Source language |
|-----------|-----------------|
| `.pas` / `.pp` / `.p` | Pascal |
| `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` | C |

### 6.4 Output extension → target language

| Extension | Target language | Supported sides |
|-----------|-----------------|-----------------|
| `.pas` / `.pp` / `.p` | Pascal | Service + Call |
| `.py` | Python | Service + Call |
| `.hpp` / `.hh` / `.h` / `.cpp` / `.cc` / `.cxx` / `.c` | C++ (`.hpp` + `.cpp` two files + CMake) | Service + Call |
| `.cs` | C# (service code + call code + test programs + READMEs) | Service + Call + Test |
| `.js` | JavaScript | **Call side only** |

**JavaScript is call-side only**: specifying a `.js` output without passing
`--call` exits immediately with an argument error.

### 6.5 What each run produces

Taking the base name of `<output>` (extension removed), the tool writes to
the **same directory**:

- **Code files**: `<base>.xxx` (single file for Pascal / Python / JS / C#;
  C++ produces `<base>.hpp` + `<base>.cpp`).
- **Companion README**: `<base>_readme.md` — **the real deliverable** (see
  Chapter 3).
- **JS-specific**: additionally produces `<base>_test.html` (self-contained
  test page).
- **C#-specific**: additionally produces the two test programs and the test
  README.
- **C++-specific**: additionally produces `CMakeLists.txt` and
  `test_main___.cpp` (**fixed names, no base prefix**).

> **Note on the C++ fixed names**: `CMakeLists.txt` and `test_main___.cpp`
> are the exact names the C++ README references. Generating two different
> units into the same directory will overwrite the previous CMake files.
> **One directory per unit.**

### 6.6 Examples

**Service: Pascal → Pascal**

```
code_decl_to_json_abi calculator.pas calculator_service.pas
```

Artifacts:

```
calculator_service.pas
calculator_service_readme.md
```

**Call: Pascal → Pascal**

```
code_decl_to_json_abi --call calculator.pas calculator_call.pas
```

**Service: C → Python**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.py
```

**Call: C → Python**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.py
```

**Service: C → C++ (`.hpp` + `.cpp` + CMake)**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.hpp
```

Artifacts:

```
calculator_service.hpp
calculator_service.cpp
calculator_service_readme.md
CMakeLists.txt
test_main___.cpp
```

**Service: C → C# (project + tests)**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_project.cs
```

Artifacts (all written to the output file's directory):

```
ComplexTestUnit_http_json_service.cs
ComplexTestUnit_http_json_service_csharp.md
ComplexTestUnit_http_json_call.cs
ComplexTestUnit_http_json_call_csharp.md
ComplexTestUnit_http_json_service_main_test___.cs
ComplexTestUnit_http_json_call_main_test___.cs
ComplexTestUnit_http_json_test_csharp.md
```

**Call: C → JavaScript (`.js` + `.html`)**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.js
```

Artifacts:

```
calculator_call.js
calculator_call_readme.md
calculator_call_test.html
```

### 6.7 Exit codes

| Exit code | Meaning |
|:---------:|---------|
| `0` | Conversion succeeded. |
| `1` | Missing or invalid argument. |
| `2` | Source parsing failed (`ParseSuccess=False`, or no usable declarations found). |
| `3` | Code generation failed (a generator returned `nil`). |
| `4` | File I/O error (read or write failed). |

### 6.8 Output messages

In command-line mode, all intermediate messages go to stdout, for example:

```
Reading: ComplexTestUnit.h (1234 chars)
Output : calculator_service.hpp
Mode   : service
Unit   : ComplexTestUnit
Funcs  : 28
Wrote  : calculator_service.hpp
Wrote  : calculator_service.cpp
Wrote  : calculator_service_readme.md
Wrote  : CMakeLists.txt
Wrote  : test_main___.cpp
Done.
```

On error, it prints `Failed.` and returns a non-zero exit code. **Do not
parse the wording**; depend on the exit code.

### 6.9 ⚠️ The CLI does not start the bridge

**The CLI is only responsible for generating code. It does not start the
bridge, and it does not start the service.**

To actually run an end-to-end call, you must manually:

1. Compile / run the generated service (see the generated `<base>_readme.md`
   for build commands);
2. **Start `bridge.py` (or `bridge.exe`) separately and keep it running**;
3. Then run the call side or open the HTML test page.

### 6.10 ⚠️ The CLI delivers the `.md` alongside the code — read it

For every generated artifact, the CLI writes a `<base>_readme.md`. **Read it
before you try to build anything.** The `.md` contains:

- The exact compile command for the target language.
- **The C++ CMake script**, when applicable.
- A complete test program.
- The tool reference for that artifact.
- The deployment and troubleshooting sections.

### 6.11 Building the generated C++

When the CLI produces a C++ target, the CMake support files land next to the
`.hpp`/`.cpp` pair. The typical workflow is:

```bash
# Put the .hpp/.cpp pair, CMakeLists.txt, and test_main___.cpp in one directory.
cd that_directory

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The CMake project builds **two executables**:

- `<Unit>_http_json_service` — the service executable.
- `<Unit>_http_json_call_test` — the call test driver.

The CMake script **does not stage the runtime DLLs**. Copy
`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` and `z_ipc_*`
next to the executables (or add their directory to `PATH` /
`LD_LIBRARY_PATH`).

### 6.12 Building the generated C#

The CLI's `.cs` output produces a complete C# project. The workflow is:

```bash
# Put the seven C# files in one directory.

dotnet new console -o my_service
cd my_service
cp ../ComplexTestUnit_http_json_service.cs .
cp ../ComplexTestUnit_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

---

## 7. Agent (MCP-API) Guide — The Three Tools

### 7.1 Trigger condition

**After the GUI starts**, the tool automatically launches the MCP service on a
background thread:

1. Creates a LingoFuse App (default name `code_decl_to_json_abi_mcp_api`).
2. Connects to the LingoFuse endpoint (default `ipc:agent`).
3. Registers all **3 tools** via the Beacon (default App `agent_main_app`,
   API `register_agent`).

So for an agent to call this tool, the following must hold:

- This tool's GUI **is running**;
- The Beacon (e.g. `pascal_agent_service`) **is running**;
- The two LingoFuse endpoints match (default `ipc:agent`).

> **Note**: the MCP service and the bridge **are two different things**.
>
> - The MCP service: lets an agent invoke this tool's 3 APIs (to generate
>   code).
> - The bridge: lets every runtime call side reach the service.
>
> **They do not substitute for each other.** The agent does not need the
> bridge to generate code; but the moment the generated code runs, **the
> bridge must still be up**.

### 7.2 The three tools

| # | Tool | Purpose |
|:-:|------|---------|
| 1 | `CodeDeclToJsonAbi_Generate(Source, Language)` | **Step 1**: parse the source text, generate all 26 artifacts, return a manifest with every file name. |
| 2 | `CodeDeclToJsonAbi_ListFiles()` | **Step 2a**: return the list of produced file names. |
| 3 | `CodeDeclToJsonAbi_GetFile(FileName)` | **Step 2b**: return the full text of one file by name. |

### 7.3 The three-tool workflow

```
┌──────────────────────────────────────────────────────────────┐
│  1.  CodeDeclToJsonAbi_Generate(Source, Language)            │
│      → {"status":"ok","unit_name":"...","count":26,          │
│         "files":[...]}                                       │
├──────────────────────────────────────────────────────────────┤
│  2.  CodeDeclToJsonAbi_ListFiles()                           │
│      → {"status":"ok","count":26,"files":[...]}              │
├──────────────────────────────────────────────────────────────┤
│  3.  CodeDeclToJsonAbi_GetFile("Calculator_http_json_        │
│                                service_unit.pas")            │
│      → {"status":"ok","name":"...","text":"..."}             │
│                                                              │
│      (Repeat GetFile for as many files as you need.          │
│       No need to call Generate again.)                       │
└──────────────────────────────────────────────────────────────┘
```

### 7.4 Tool 1 — `CodeDeclToJsonAbi_Generate`

**Signature**: `function(Source: string; Language: string): string`

**Parameters**:

| Parameter | Type | Notes |
|-----------|------|-------|
| `Source` | string | The full source text |
| `Language` | string | `"pascal"` or `"c"`, case-insensitive |

**Language rule (the #1 mistake)**:

- `"pascal"` means **the source text is a Pascal unit**.
- `"c"` means **the source text is a C header**.
- `"python"`, `"cpp"`, `"csharp"`, `"javascript"` are **target** languages,
  **not** source languages. Passing any of them returns:
  `{"error":"Unsupported language. Use ''pascal'' or ''c''."}`

**Success return**:

```json
{
  "status": "ok",
  "unit_name": "Calculator",
  "count": 26,
  "files": [
    "Calculator_http_json_service_unit.pas",
    "Calculator_http_json_service_pascal.md",
    "Calculator_http_json_call_unit.pas",
    "Calculator_http_json_call_pascal.md",
    "Calculator_http_json_call.js",
    "Calculator_http_json_call_js.md",
    "Calculator_http_json_call_test.html",
    "Calculator_http_json_service.py",
    "Calculator_http_json_service_python.md",
    "Calculator_http_json_call.py",
    "Calculator_http_json_call_python.md",
    "Calculator_http_json_service.cs",
    "Calculator_http_json_service_csharp.md",
    "Calculator_http_json_call.cs",
    "Calculator_http_json_call_csharp.md",
    "Calculator_http_json_service_main_test___.cs",
    "Calculator_http_json_call_main_test___.cs",
    "Calculator_http_json_test_csharp.md",
    "Calculator_http_json_service.hpp",
    "Calculator_http_json_service.cpp",
    "Calculator_http_json_service_cpp.md",
    "Calculator_http_json_call.hpp",
    "Calculator_http_json_call.cpp",
    "Calculator_http_json_call_cpp.md",
    "CMakeLists.txt",
    "test_main___.cpp"
  ]
}
```

**Failure return**: `{"error":"<message>"}`.

**Failure scenarios**:

- `Unsupported language. Use ''pascal'' or ''c''.`
- `Form not available`
- `Generation failed: <reason>`

**Notes**:

- Every successful call **replaces the session**. Calling `Generate` again
  with a different source text discards everything from the previous call.
- Every successful call **writes 26 files to disk**, under
  `<exe dir>/<normalized unit name>/`.
- **One call produces every target.** There is no per-target `Generate`.

### 7.5 Tool 2 — `CodeDeclToJsonAbi_ListFiles`

**Signature**: `function(): string`

**Success return**:

```json
{
  "status": "ok",
  "count": 26,
  "files": ["<name 1>", "<name 2>", ...]
}
```

**Empty return** (if `Generate` has not been called):

```json
{"status": "ok", "count": 0, "files": []}
```

**Notes**:

- **Pure reader.** Does not re-run any generator, does not mutate the
  session.
- File names are the **names**, not full paths. Use a name from this list as
  the argument to `GetFile`.

### 7.6 Tool 3 — `CodeDeclToJsonAbi_GetFile`

**Signature**: `function(FileName: string): string`

**Parameters**:

| Parameter | Type | Notes |
|-----------|------|-------|
| `FileName` | string | Must be a value returned by a previous `ListFiles` call |

**Success return**:

```json
{
  "status": "ok",
  "name": "<FileName>",
  "text": "<full artifact text>"
}
```

The `text` field contains the **entire artifact**, never truncated. Multi-line
content is embedded as a JSON string with standard JSON escaping.

**Failure return**:

```json
{
  "status": "error",
  "name": "<FileName>",
  "error": "<message>"
}
```

**Failure scenarios**:

- `Form not available`
- `File not found. Call ListFiles first to get valid names.`

**Notes**:

- **Pure reader.** Does not re-run any generator, does not mutate the
  session.
- **`FileName` is case-sensitive.** `CMakeLists.txt` works;
  `cmakelists.txt` does not.
- **The `text` field may be empty** for a genuinely empty file. Check
  `status` to distinguish between empty and error.

### 7.7 Recommended call sequences

**Minimum flow (one target, one file)**:

```
1. CodeDeclToJsonAbi_Generate(Source="...", Language="pascal")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_unit.pas")
```

**Full C++ build-prep flow**:

```
1. CodeDeclToJsonAbi_Generate(<source>, "c")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.hpp")
4. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.cpp")
5. CodeDeclToJsonAbi_GetFile("<U>_http_json_service_cpp.md")   ← ⚠️ read this first
6. CodeDeclToJsonAbi_GetFile("CMakeLists.txt")
7. CodeDeclToJsonAbi_GetFile("test_main___.cpp")
```

Step 5 returns the `.md`. **The `.md` is where the CMake invocation, the
include directories, and the link libraries are.** An agent that intends to
actually build the artifact should read the `.md` before doing anything else.

**Full C# build-prep flow**:

```
1. CodeDeclToJsonAbi_Generate(<source>, "c")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.cs")
4. CodeDeclToJsonAbi_GetFile("<U>_http_json_service_csharp.md")   ← ⚠️ read this
5. CodeDeclToJsonAbi_GetFile("<U>_http_json_call.cs")
6. CodeDeclToJsonAbi_GetFile("<U>_http_json_call_csharp.md")      ← ⚠️ read this
7. CodeDeclToJsonAbi_GetFile("<U>_http_json_service_main_test___.cs")
8. CodeDeclToJsonAbi_GetFile("<U>_http_json_call_main_test___.cs")
9. CodeDeclToJsonAbi_GetFile("<U>_http_json_test_csharp.md")      ← ⚠️ read this
```

**Agent self-reference flow (an agent that wants to inspect what it produced)**:

```
1. CodeDeclToJsonAbi_Generate(<source>, "pascal")
2. CodeDeclToJsonAbi_ListFiles()          ← see every file name
3. CodeDeclToJsonAbi_GetFile(<any name>)  ← read any artifact
```

### 7.8 Agent-mode notes

1. **The source language only accepts `"pascal"` or `"c"`**; any other value
   is rejected.
2. **One `Generate` produces every target.** To obtain a Python service, read
   the Python-named file — do not call `Generate` again.
3. **`Generate` is idempotent across calls.** Repeated calls with the same
   source produce the same 26 files, overwriting the previous disk content.
4. **Order matters**: `Generate` first, then `ListFiles` / `GetFile`.
   Reversing the order fails.
5. **`ListFiles` and `GetFile` are pure readers.** Do not call `Generate`
   between them unless you want to change the session.
6. **The GUI must be alive.** The MCP service is attached at GUI startup;
   closing the GUI takes all 3 tools offline.
7. **Generating code with an agent ≠ running the code.** To actually run the
   generated code, **you must still manually start the bridge and keep it
   running**.
8. **Point agents at the `.md` files.** After a successful `Generate`, every
   `.md` file returned by `ListFiles` is the real deliverable. **That `.md`
   is where the build commands, CMake scripts, and test programs live.**
9. **For C++ targets, always fetch all five artifacts**: the header, the
   implementation, the CMake script, the test driver, and the README.
   Fetching only the `.hpp`/`.cpp` pair leaves the build incomplete.
10. **For C# targets, always fetch all seven artifacts**: the service code
    and README, the call code and README, both test programs, and the test
    README.

### 7.9 Example agent interaction

```
# 1. Feed the source and generate everything
CodeDeclToJsonAbi_Generate(
    Source   = "<contents of calculator.pas>",
    Language = "pascal")
→ {"status":"ok","unit_name":"Calculator","count":26,"files":[...]}

# 2. See what was produced
CodeDeclToJsonAbi_ListFiles()
→ {"status":"ok","count":26,"files":[...]}

# 3. Read the artifacts you need — no second Generate required
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_unit.pas")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_pascal.md")   ← ⚠️ the .md
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call.js")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call_test.html")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service.py")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_python.md")   ← ⚠️ the .md
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service.hpp")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service.cpp")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_cpp.md")      ← ⚠️ the .md
CodeDeclToJsonAbi_GetFile("CMakeLists.txt")
CodeDeclToJsonAbi_GetFile("test_main___.cpp")
```

The agent can then either forward the artifacts to a user or, if the
environment permits, execute the build and run instructions directly from the
`.md`.

---

## 8. How the MCP Tool Provider Unit Is Built

This chapter documents the **bootstrap → AI-fill architecture** that produces
`code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`. Every statement here
is about the **tooling that writes the tool provider**, not about the tool
provider itself.

### 8.1 The Three-Stage Build

The tool provider unit is not written by hand. It is produced in three stages:

```
Stage 1: Bootstrap script
    ↓ emits a structurally complete Pascal unit
    ↓ with 3 callback shells, 3 internal-call stubs, 3 tool schemas
    ↓ and the full registration scaffolding
    code_decl_to_json_abi_mcp_api_tool_provider_unit.pas

Stage 2: AI fill-in
    ↓ fills the body of each internal_call_* function
    ↓ with the UI-synchronization logic

Stage 3: Compile + run
    ↓ the unit is compiled into the GUI executable
    ↓ at GUI startup, the MCP service registers all 3 tools
```

### 8.2 What the Bootstrap Script Writes

For each of the 3 tools, the bootstrap script writes:

1. **A `function` declaration in the `interface` section** — the external
   signature.
2. **A `procedure Callback_...` forward declaration** — the cdecl callback
   that LingoFuse will invoke.
3. **The full body of `procedure Callback_...`** — including:
   - Reading the input `TDataHnd___` as UTF-8 bytes.
   - Parsing the bytes as JSON.
   - Extracting named parameters.
   - **Calling the corresponding `internal_call_*` function** (this call is
     already written; the AI does not touch it).
   - Writing the return string back to the output `TDataHnd___`.
   - A `try/except` envelope that converts any exception into
     `{"error": "..."}`.
4. **A shell for `function internal_call_...`** — the FPC/Delphi `{$IFDEF}`
   split, the `TCompute.Sync` wrapper, and a **body that the AI must fill
   in**.
5. **A tool schema registration** in `RegisterTools` — the tool's `name`,
   `description`, `target_app`, `target_api`, and JSON `parameters` schema.

The bootstrap script also writes the entire registration scaffolding in
`RegisterAPIs` (3 `LF_RegisterCallEx` calls) and `Execute_And_Reg_all` (the
App creation, the endpoint connection, and the beacon handshake).

### 8.3 What the AI Fills In

The AI fills exactly one thing per tool: **the body inside `Do_Sync___` (FPC)
or the anonymous procedure (Delphi)**.

**Tool 1 — `Generate`**:

1. Null-check the form.
2. Validate the `Language` argument (`pascal` / `c` only).
3. Select the language in the combo box.
4. Write the source text into the source editor.
5. Call the parse / normalize / generate button-click handlers in order.
6. Read the resulting file list from the ListView.
7. Read the unit name from the model JSON.
8. Build the file manifest JSON and return it.

**Tool 2 — `ListFiles`**:

1. Null-check the form.
2. Walk the ListView.
3. Return the file names.

**Tool 3 — `GetFile`**:

1. Null-check the form.
2. Match `FileName` against the ListView entries.
3. Read the file at the matched entry's `SubItems[0]` as UTF-8.
4. Return the text.

The AI never writes:

- The `TCompute.Sync` wrapper.
- The callback envelope.
- The exception handling.
- The LingoFuse registration code.
- The tool schema.

### 8.4 Why the UI-Synchronization Pattern

The critical design decision: **the AI does not write new state management
logic**. Every MCP tool body delegates to the GUI form. The chain of custody
is:

```
MCP client
    ↓ calls CodeDeclToJsonAbi_Generate (LingoFuse Call)
Callback_CodeDeclToJsonAbi_Generate (cdecl, worker thread)
    ↓ calls internal_call_...
internal_call_CodeDeclToJsonAbi_Generate
    ↓ TCompute.Sync(Do_Sync___)
Do_Sync___ (runs on the MAIN thread)
    ↓ writes code_decl_to_abi_json_form.SourceCodeEditor.Text
    ↓ calls code_decl_to_abi_json_form.ParseSourceToJsonClick
    ↓ calls code_decl_to_abi_json_form.NormalizeJsonToModelClick
    ↓ calls code_decl_to_abi_json_form.GenerateAllSourcesClick
    ↓ reads code_decl_to_abi_json_form.final_source_file_ListView
    ↓ returns to TCompute.Sync
TCompute.Sync returns
    ↓ internal_call_* returns the JSON string
Callback_* writes the string to the output DataHandle
    ↓ LingoFuse returns to the MCP client
```

Every arrow in that chain is **written once** by the bootstrap script, except
the UI touches inside `Do_Sync___` that each tool needs.

**Consequences of this design**:

1. **The GUI is the single source of truth.** There is no parallel state.
2. **Adding a new MCP tool is a purely mechanical operation.** Copy an
   existing `internal_call_*` pair, rename it, point it at a different form
   field or button click, and add the tool schema to `RegisterTools`.
3. **The GUI's button-click handlers are effectively the MCP tool
   implementations.** The MCP layer is a thin remote-control veneer.
4. **Thread-safety is inherited, not reinvented.** `TCompute.Sync` marshals
   the body onto the main thread.
5. **No new state fields.** If an MCP tool needs a value, that value must
   already exist as a form editor or form field.

### 8.5 Why the Layer Was Reduced to Three Tools

The previous iteration exposed 24 tools. That was a **remote-control surface**,
not an agent-facing API. Agents had to understand:

- Which 2 of the 24 tools were input tools.
- Which 1 was the generation tool.
- Which of the remaining 21 readers they needed.

This was a **discoverability problem**: the agent's first move was always
wrong, and the correction required a full regeneration cycle.

The three-tool design solves it:

- **One** tool per verb: Generate, List, Get.
- The **Generate** tool produces **everything** in one shot.
- The **List** / **Get** tools are pure readers.

### 8.6 Adding a New Tool — the Mechanical Recipe

To add a fourth tool:

1. **Choose the pattern** that matches what the tool does (setter, reader,
   driver, cache reader).
2. **In the bootstrap script's tool table**, add a new entry with:
   - The tool name.
   - A description string.
   - The parameter list.
   - The pattern identifier.
3. **Re-run the bootstrap script.** It regenerates the unit with the new
   callback, the new stub, and the new tool schema.
4. **Fill in the AI body** following the chosen pattern.
5. **Update the GUI** if the tool needs a new editor or a new tab.
6. **Rebuild the GUI executable.**

The tool then appears in the beacon's tool list automatically. No other file
needs to change.

### 8.7 What the AI Must Not Do

- **Do not add new state fields to the form** for the sake of an MCP tool.
- **Do not call UI methods from the worker thread.** Every UI touch must be
  inside `Do_Sync___`.
- **Do not bypass the callback envelope.** Let exceptions propagate; the
  envelope converts them into `{"error": "..."}`.
- **Do not renumber or rename the tools.** Tool names are stable identifiers
  that external callers depend on.
- **Do not modify the tool schemas** without updating the AI-filled bodies in
  lockstep.

---

## 9. Programmatic Interface

The tool can also be driven from another program. This section describes the
**public API surface** — the same functions the CLI, GUI, and MCP provider
call internally.

### 9.1 Where the API Lives

| Unit | Exports |
|------|---------|
| `http_pas_abi_service_generator_tool` | `GenerateHTTPServicePascalCode` / `GenerateHTTPServicePascalReadme` |
| `http_pas_abi_call_generator_tool` | `GenerateHTTPCallPascalCode` / `GenerateHTTPCallPascalReadme` |
| `http_py_abi_service_generator_tool` | `GenerateHTTPServicePythonCode` / `GenerateHTTPServicePythonReadme` |
| `http_py_abi_call_generator_tool` | `GenerateHTTPCallPythonCode` / `GenerateHTTPCallPythonReadme` |
| `http_csharp_abi_service_generator_tool` | `GenerateHTTPServiceCsharpCode` / `GenerateHTTPServiceCsharpReadme` |
| `http_csharp_abi_call_generator_tool` | `GenerateHTTPCallCsharpCode` / `GenerateHTTPCallCsharpReadme` |
| `http_csharp_abi_test_generator_tool` | `GenerateHTTPServiceCsharpTestCode` / `GenerateHTTPCallCsharpTestCode` / `GenerateHTTPCsharpTestReadme` |
| `http_cpp_abi_service_generator_tool` | `GenerateHTTPServiceCppHeader` / `GenerateHTTPServiceCppCode` / `GenerateHTTPServiceCppReadme` |
| `http_cpp_abi_call_generator_tool` | `GenerateHTTPCallCppHeader` / `GenerateHTTPCallCppCode` / `GenerateHTTPCallCppReadme` |
| `http_js_abi_call_generator_tool` | `GenerateHTTPCallJsCode` / `GenerateHTTPCallJsReadme` / `GenerateHTTPCallJsHtmlCode` |
| `http_cmake_generator_tool` | `GenerateCMakeScript` / `GenerateTestMainCpp` |

Each code function returns a `TPascalStringList` that the caller must dispose.

### 9.2 Model Building

The generators consume a `TPascal_Func_Model`. To build one from source text:

```pascal
var
  Parser: tpascal_func_decl_tool;
  Model: TPascal_Func_Model;
  Report: TPascalStringList;
begin
  Parser := tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceText);
  try
    Report := TPascalStringList.Create;
    try
      Model := TPascal_Func_Model.Create;
      try
        Model.Typ_Normalize_Func := tnf_ABI;   // required by the ABI generators
        Model.LoadFromParser(Parser, Report);
        // Model is now ready for the generator functions.
      finally
        Model.Free;
      end;
    finally
      Report.Free;
    end;
  finally
    Parser.Free;
  end;
end;
```

For a C header, substitute `CreateFrom_C_Code`.

### 9.3 Minimum Viable Embedding

```pascal
var
  Parser: tpascal_func_decl_tool;
  Model: TPascal_Func_Model;
  Code, Readme: TPascalStringList;
  CmakeScript, TestMain: TPascalStringList;
begin
  Parser := tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceText);
  try
    Model := TPascal_Func_Model.Create;
    try
      Model.Typ_Normalize_Func := tnf_ABI;
      Model.LoadFromParser(Parser, nil);      // nil report = silent

      Code := GenerateHTTPServicePascalCode(Model);
      try
        if Code <> nil then
          Code.SaveToFile('MyUnit_http_json_service_unit.pas');
      finally
        Code.Free;
      end;

      Readme := GenerateHTTPServicePascalReadme(Model);
      try
        if Readme <> nil then
          Readme.SaveToFile('MyUnit_http_json_service_pascal.md');
      finally
        Readme.Free;
      end;

      // If the target is C++, also emit the CMake pair:
      CmakeScript := GenerateCMakeScript(Model);
      try
        if CmakeScript <> nil then
          CmakeScript.SaveToFile('CMakeLists.txt');
      finally
        CmakeScript.Free;
      end;

      TestMain := GenerateTestMainCpp(Model);
      try
        if TestMain <> nil then
          TestMain.SaveToFile('test_main___.cpp');
      finally
        TestMain.Free;
      end;
    finally
      Model.Free;
    end;
  finally
    Parser.Free;
  end;
end;
```

### 9.4 Contract Summary

| Function family | Input | Output | Notes |
|-----------------|-------|--------|-------|
| `Generate*Code` / `Generate*Readme` | `TPascal_Func_Model` (must be `tnf_ABI`) | `TPascalStringList` or `nil` | Caller disposes; `nil` on empty model |
| `GenerateCMakeScript` / `GenerateTestMainCpp` | `TPascal_Func_Model` | `TPascalStringList` or `nil` | Caller disposes; fixed-name output files |
| `tpascal_func_decl_tool.CreateFrom_*` | source text | parser instance | Caller disposes |
| `TPascal_Func_Model.LoadFromParser` | parser + optional report | — | Applies the type-family filters |

### 9.5 ⚠️ The `.md` Generator Is Part of the API

Every `Generate*Code` function has a **companion `Generate*Readme`
function**. If you call only the code function and not the README function,
you produce a `.pas` / `.py` / `.hpp` / `.cs` without its build instructions.
**Always call both.** The generated code and its `.md` are designed to be
produced together.

### 9.6 Registering Custom Generators with the Tool Itself

If you are extending the tool and want your generator to appear in the CLI,
GUI, or MCP frontends, you must register it in three places:

1. `code_decl_to_json_abi.lpr` — `uses` clause, so the unit's
   `initialization` runs.
2. `code_decl_to_abi_json_frm.pas` — `implementation uses`, so the GUI can
   call it.
3. `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` — `RegisterAPIs`,
   `RegisterTools`, and the appropriate `internal_call_*` function, so agents
   can reach it.

For the third point, follow the mechanical recipe in Chapter 8.6.

---

## 10. Artifact Inventory

### 10.1 What Each Artifact Is For

| Extension / name | Purpose | Needs the bridge at runtime? |
|------------------|---------|:----------------------------:|
| `*_http_json_service_unit.pas` | Pascal service: registers APIs, listens for RPC, converts LingoFuse calls into JSON. | ❌ (the service does not go through the bridge) |
| `*_http_json_call_unit.pas` | Pascal call side: turns a local function call into an HTTP POST to `bridge.py`. | ✅ **Required** |
| `*_http_json_service.py` | Python service. | ❌ |
| `*_http_json_call.py` | Python call side. | ✅ **Required** |
| `*_http_json_service.hpp` / `.cpp` | C++ service (`.hpp` declarations + `.cpp` implementation). | ❌ |
| `*_http_json_call.hpp` / `.cpp` | C++ call side. | ✅ **Required** |
| `*_http_json_service.cs` | C# service module. | ❌ |
| `*_http_json_call.cs` | C# call side. | ✅ **Required** |
| `*_http_json_service_main_test___.cs` | C# service test driver. | ❌ (local test) |
| `*_http_json_call_main_test___.cs` | C# call test driver. | ✅ **Required** |
| `*_http_json_call.js` | Browser JS client (IIFE, attached to `window.<UnitName>Api`). | ✅ **Required** |
| `*_http_json_call_test.html` | Self-contained HTML test page; double-click to test. | ✅ **Required** |
| `CMakeLists.txt` | CMake build script for the C++ pair + C++ test driver. | — |
| `test_main___.cpp` | C++ call test driver referenced by the CMake script. | ✅ **Required** (when executed) |
| `*_readme.md` | **Per-artifact companion documentation. The real deliverable.** Contains wire protocol, type mapping, deployment, testing, API reference, and language-specific build scripts (including the C++ CMake script). | — |

> **Note**: **The service itself does not go through the bridge.** The bridge
> only serves the "call → service" direction.

### 10.2 File Locations

- **GUI / MCP**: artifacts are written to the `<UnitName>/` subdirectory of
  the executable's directory.
- **CLI**: artifacts are written to the output file's directory.

### 10.3 The Two CMake Artifacts Are Unit-Level

`CMakeLists.txt` and `test_main___.cpp` use **fixed names** (no unit prefix).
Generating two different units into the same directory will overwrite the
previous CMake files. **Use one directory per unit.**

### 10.4 The Complete File List (26 files)

For a source unit whose parsed name is `<U>`:

```
 1.  <U>_http_json_service_unit.pas
 2.  <U>_http_json_service_pascal.md
 3.  <U>_http_json_call_unit.pas
 4.  <U>_http_json_call_pascal.md
 5.  <U>_http_json_call.js
 6.  <U>_http_json_call_js.md
 7.  <U>_http_json_call_test.html
 8.  <U>_http_json_service.py
 9.  <U>_http_json_service_python.md
10.  <U>_http_json_call.py
11.  <U>_http_json_call_python.md
12.  <U>_http_json_service.cs
13.  <U>_http_json_service_csharp.md
14.  <U>_http_json_call.cs
15.  <U>_http_json_call_csharp.md
16.  <U>_http_json_service_main_test___.cs
17.  <U>_http_json_call_main_test___.cs
18.  <U>_http_json_test_csharp.md
19.  <U>_http_json_service.hpp
20.  <U>_http_json_service.cpp
21.  <U>_http_json_service_cpp.md
22.  <U>_http_json_call.hpp
23.  <U>_http_json_call.cpp
24.  <U>_http_json_call_cpp.md
25.  CMakeLists.txt
26.  test_main___.cpp
```

### 10.5 The Bridge Is a Forwarder, and Must Always Be Running

**Every generated call side (Pascal / Python / C++ / C# / JavaScript) talks
to the backend through the bridge:**

```
caller ──HTTP POST──▶ bridge.py / bridge.exe ──LF_Call──▶ service
caller ◀─HTTP resp──  bridge.py / bridge.exe ◀─LF ret───  service
```

**When starting the bridge, specify an endpoint that matches the service,
e.g.:**

```
python3 bridge.py --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

**Important rules, once more for emphasis:**

- **The bridge is a forwarder and must always be running.** Closing the
  bridge closes the whole path.
- The bridge may run as `bridge.py` or be compiled into `bridge.exe` — both
  behave identically.
- The bridge should run in its **own terminal**, in the foreground. Only
  after you see the HTTP listening log should you start the call side.
- After a crash or kill, restarting the bridge is enough to recover; the
  call side does not need to be restarted.

### 10.6 Where the CMake Script Looks for the LingoFuse C++ Library

The CMake script requires a directory that contains:

- `LingoFuse.h`
- `LingoFuse.c`
- `LingoFuse.hpp`
- `lf_io.hpp`
- `lf_http_bridge_client.hpp`
- `json.hpp`

Supply the directory at configure time via
`-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf`, or via the cmake-gui field labeled
**"LingoFuse C++ library directory"**.

---

## 11. JSON Safety and Stability

Because every generated call side ultimately speaks JSON over HTTP, **JSON is
the safety and stability boundary of the entire pipeline**. The following
points are guaranteed by the toolchain:

1. **UTF-8 everywhere.** Requests and responses are always UTF-8; the bridge
   serializes with `ensure_ascii=False`, so non-ASCII payloads (Chinese,
   emoji, and other multi-byte content) are carried as literal UTF-8 rather
   than being re-encoded as `\uXXXX` escapes.

2. **NUL-terminator policy is explicit.** LingoFuse strings are NUL-terminated
   on the wire. The bridge **strips the trailing NUL** before forwarding to
   HTTP clients, and the generated call sides never emit a stray NUL into
   JSON.

3. **The bridge is binary-safe.** If a payload cannot be parsed as JSON at
   all, the bridge forwards it verbatim rather than corrupting it.

4. **Deterministic unwrapping.** The bridge wraps every service response in a
   stable envelope (`{"status_code": ..., "headers": ..., "body": ...}`).
   The generated call sides unwrap `body` and check `body.code`; code `0`
   returns `body.result`, any other code raises the language-appropriate
   exception.

5. **No silent precision loss on the wire.** Large integers are transmitted
   as JSON numbers by default, which is safe for Python and for C++ (via
   `std::int64_t` on the service side). It is **not** safe for the JavaScript
   client, whose `Number` is IEEE-754 double. For `int64` / `uint64`
   interfaces intended for browser consumption, **the recommended pattern is
   to have the service return the value as a string**. The generated READMEs
   call this out explicitly.

6. **Stable error schema.** Every failure surfaces either as
   `{"error":"<message>"}` (tool-level) or as
   `{"code": -N, "error": "<message>"}` (service/bridge level). Call sides
   translate these into language-specific exceptions: `EHTTPCallError`
   (Pascal), `HTTPCallError` (Python / C++ / C#), `LFHttpCallError`
   (JavaScript).

The practical upshot: **as long as the bridge is running and the endpoint
strings match on both sides, JSON payloads produced by one language's call
side are consumed correctly by any other language's service side, and vice
versa.**

---

## 12. Language Support: Today and Tomorrow

### 12.1 Excellent Interface Support for Strongly-Typed Languages

For **Pascal, C++, C#, and Python**, the generated interfaces are first-class,
not merely stubs:

- **Pascal**: the generated service unit registers cdecl callbacks with
  LingoFuse directly and uses `Z.Json` for serialization. The generated call
  unit uses `LFHttpPost` from `lf_http_bridge_client` and exposes each API as
  a **typed free function**.
- **C++**: the generated service produces a clean `.hpp`/`.cpp` pair with a
  namespace, typed function signatures, `LF_CDECL`-compatible callbacks, and
  JSON I/O helpers. The generated call side exposes a **typed free function
  per API** and carries a rich set of tunables. **The generated `.md`
  contains the CMake script and every compiler invocation you need**, and the
  CMake pair is emitted alongside the code.
- **C#**: the generated service and call modules use the official LingoFuse
  .NET binding. The service exposes a `Service.RegisterAPIs` entry point and
  a stub per routine. The call side exposes one typed synchronous and one
  typed asynchronous function per API. **Two test programs and a test README
  are emitted alongside**, and they are designed to be copied into a
  `dotnet new console` project.
- **Python**: the generated service module exposes a
  `register_all_http_json_apis(app)` entry point with typed internal stubs;
  the generated call module exposes **one typed Python function per API** and
  a unified internal `_call_api()` dispatcher.

In all four languages, the type families (integer / float / string) map to
the language's natural primitives, JSON serialization is handled internally,
and the only thing the developer has to do is fill in the
`internal_call_<Api>` stub body.

### 12.2 Excellent Support for Full-Stack Languages (JavaScript Today; TypeScript and PHP on the Roadmap)

- **JavaScript (available today)**: the generated `.js` is a
  **self-contained IIFE**, attaches itself to `window.<Unit>Api` (or
  `globalThis.<Unit>Api`), uses only `fetch` / `Promise` / `async-await`, and
  has **no third-party dependencies**. A **self-contained HTML test page** is
  bundled alongside.
- **TypeScript (roadmap)**: a natural next step that will reuse most of the
  JS backend and add `.d.ts`-style declaration output.
- **PHP (roadmap)**: a separate backend that will plug into the same CLI /
  GUI / MCP dispatch, exposing each API as a typed PHP function using the
  same HTTP/JSON wire protocol.

### 12.3 The System Is Designed for Unbounded Extension

Adding a new target language is a **mechanical process**, not an
architectural change. The steps are:

1. Create two generator units: `<lang>_abi_service_generator_tool.pas` and
   `<lang>_abi_call_generator_tool.pas`.
2. Provide a type mapping table from the three ABI families to the target
   language's native types.
3. Register the new units in the main program, the CLI dispatcher, the GUI
   form, and the MCP tool provider.
4. Update the CLI's `Detect_Target_Lang` and help text.
5. Update the MCP `regCount` assertion (currently `3`) and the tool schema
   table.

**There is no architectural ceiling on the number of supported target
languages.** Every language with (a) an HTTP client, (b) a JSON library, and
(c) a runtime that can speak the wire protocol is a candidate.

**The user-facing contract does not change when a language is added**: the
same CLI flags, the same GUI workflow, and the same 3 MCP tools continue to
work.

---

## 13. Frequently Asked Questions

### Q1: Why is a function I passed in missing from the generated result?

Check three things:

1. **Is the function top-level** (in the `interface` section, not nested
   inside a `class` / `record`)? Nested declarations are skipped.
2. **Are its parameters and return type in the supported set?** Only the
   integer family, float family, and string family are accepted.
3. **Is the function name non-empty?**

### Q2: Why does the model JSON have fewer functions than the source file?

Same as above. During normalization, any function with unsupported types is
dropped wholesale.

### Q3: What happens if the CLI is asked to output `.js` without `--call`?

It exits immediately with an argument error, exit code `1`. JavaScript is a
call-side-only target.

### Q4: I see no output at all after running the CLI.

In CLI mode, this tool writes all `DoStatus` messages to stdout. If you are
running from inside an IDE or have redirected stdout, you may not see them.
Run it directly in a terminal.

### Q5: The "rule document" buttons in the GUI do nothing.

The executable directory is missing `pascal_code_abi_rule.md` or
`C_code_abi_rule.md`. Put those two files next to the executable.

### Q6: An agent call returns `{"error":"Form not available"}`.

The GUI is not running. The MCP service is a GUI-lifetime service; after the
GUI closes, all tools become unavailable.

### Q7: An agent call returns `{"error":"Beacon not available ..."}`.

The Beacon service (default `agent_main_app`) is not online, or its endpoint
differs from this tool's endpoint. Check both sides' `--endpoint` arguments.

### Q8: What does `Language="python"` do?

It returns
`{"error":"Unsupported language. Use ''pascal'' or ''c''."}`.

`"python"`, `"cpp"`, `"csharp"`, and `"javascript"` are **target** languages.
To produce a Python service, pass `"pascal"` or `"c"` as `Language`, then
call `GetFile` on the Python-named file from the manifest.

### Q9: Does calling `Generate` multiple times pollute the result?

No. Every `Generate` re-runs every generator from scratch, overwriting the
previous session and the previous disk content.

### Q10: Can I generate only one target language?

**No.** `Generate` produces every target in one shot. If you only want one
of them, pick it out of the manifest with `GetFile`; the other files on disk
can simply be ignored.

### Q11: Running the generated call side or HTML test page gives `Network error` / `Failed to fetch` / `Connection refused`.

**99% of the time, the bridge is not running (or was up and got closed).**

Troubleshooting steps:

1. **Confirm the bridge is actually running**: check its terminal for live
   log output.
2. **Confirm the bridge's endpoint matches the service**.
3. **Confirm the bridge's port matches the caller's expectation**: default
   `8081`.
4. **Restart the bridge**.

> Once again: **the bridge (`bridge.py` / `bridge.exe`) is a forwarder and
> must always be running.**

### Q12: The service is up — why can I still not reach it?

The service, the bridge, and the caller are **three independent processes**,
and all three are required:

```
service process (must be online)
     ▲
     │ LF_Call
bridge process (must be online, foreground, always running)
     ▲
     │ HTTP POST
caller process (started on demand)
```

- Only the service, no bridge → the caller reports `Network error`.
- Only the bridge, no service → the bridge reports API not available /
  timeout.
- All three up but not started in order → restart in the order
  "service → bridge → caller".

### Q13: Where do I find the CMake script for the generated C++?

There are **three** equivalent ways:

1. On disk: the file `CMakeLists.txt`, written next to the generated
   `.hpp`/`.cpp` pair.
2. In the GUI: the **CMake** sub-tab of the Final Source page.
3. Via MCP: `ListFiles` shows it, then `GetFile("CMakeLists.txt")`.

The companion file `test_main___.cpp` is available by the same three routes.

### Q14: How do I build the generated C++?

Put the `.hpp`, `.cpp`, `CMakeLists.txt`, and `test_main___.cpp` in one
directory, then:

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The CMake project builds two executables: `<Unit>_http_json_service` and
`<Unit>_http_json_call_test`.

### Q15: Does the CMake script stage the LingoFuse DLLs?

No. Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` and
`z_ipc_*` next to the executables, or add their directory to `PATH` /
`LD_LIBRARY_PATH`.

### Q16: Where do I find the test program for the generated Pascal?

**In the generated `<Unit>_http_json_service_pascal.md` (or
`_call_pascal.md`).** It contains a complete `.lpr` file and the exact
`fpc -Fu<...>` command line to build it.

### Q17: How do I build the generated Python service?

**Read the `<Unit>_http_json_service_python.md`.** It tells you which
`PYTHONPATH` or `pip install` is needed, and it relies on the generated
module's own `if __name__ == "__main__":` block as the test program.

### Q18: How do I build the generated C# service?

**Read the `<Unit>_http_json_service_csharp.md` and the
`<Unit>_http_json_test_csharp.md`.** The typical flow is:

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

For the call side, use `<Unit>_http_json_call.cs` and
`<Unit>_http_json_call_main_test___.cs` instead.

### Q19: How does the MCP tool provider unit get built? Do I have to write it by hand?

No. It is produced by a **three-stage build**:

1. **Bootstrap script** — emits the structurally complete unit: callbacks,
   error envelopes, tool schemas, LingoFuse registration, and function
   shells.
2. **AI fill-in** — fills the body of each `internal_call_*` function with
   the UI-synchronization logic.
3. **Compile** — the unit is compiled into the GUI executable.

The AI's contribution is a handful of UI touches per tool; everything else
is mechanical.

### Q20: Why was the MCP tool count reduced from 24 to 3?

Because 24 tools was a **remote-control surface**, not an agent-facing API.
The agent's first move was always wrong, and the correction required a full
regeneration cycle. The 3-tool design gives the agent one tool per verb:

- `Generate` — produce every target in one call.
- `ListFiles` — see what was produced.
- `GetFile` — read what you need.

The agent's first attempt at the three-tool workflow succeeds. That is the
entire point.

### Q21: Why does the guide keep telling me to read the `.md`?

Because **the `.md` is the real deliverable.** The code file is the
skeleton; the `.md` is the manual that tells you how to build, test, and
deploy that skeleton. Whenever you are about to compile, run, or debug a
generated artifact, **the answer is in its `.md`, not in this user guide.**

---

## Appendix: One-Sentence Summary of the Usage Modes

- **GUI**: five tabs, click left to right; when something goes wrong, step
  back and fix it. Open the `.md` sub-tab before trying to build. The
  **CMake** sub-tab holds the two CMake artifacts.
- **CLI**: `code_decl_to_json_abi [--call] input output`; extension picks
  the language, exit code tells success or failure. Read `<base>_readme.md`
  before building. For C++ targets, look for `CMakeLists.txt` and
  `test_main___.cpp` in the same directory.
- **Agent**: `Generate` → `ListFiles` → `GetFile`. Three tools, two steps,
  one session. Read the `.md` files for build instructions.
- **Programmatic**: call the `Generate*Code` and `Generate*Readme` functions
  directly; for C++, also call `GenerateCMakeScript` and
  `GenerateTestMainCpp`; for C#, also call
  `GenerateHTTPServiceCsharpTestCode`, `GenerateHTTPCallCsharpTestCode`, and
  `GenerateHTTPCsharpTestReadme`.

**The one rule you must never forget at runtime**: **the bridge
(`bridge.py` or `bridge.exe`) is a forwarder and must always be running.**

**The one rule you must never forget after generation**: **read the
generated `.md` files. The test code, the build scripts (including the C++
CMake script), and the interface reference all live there.**

---

*Document version: v3*
*Document role: user-facing guide for code_decl_to_json_abi. For the deeper
architectural reference, see code_decl_to_json_abi_knowledge_base.md.*
