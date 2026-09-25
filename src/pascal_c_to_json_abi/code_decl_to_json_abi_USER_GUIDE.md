# code_decl_to_json_abi User Guide (v2)

> This document describes **how to use** `code_decl_to_json_abi`, covering:
> - Graphical User Interface (GUI) operation
> - Command-Line Interface (CLI) operation
> - Remote invocation from an agent (MCP / LingoFuse), including the **bootstrap → AI-fill architecture** of the tool provider unit
> - **Programmatic interface** (embedding the generator in your own tools)
>
> **The single most important rule at runtime**: the **bridge must always be running**. Every artifact this tool generates that performs a call ultimately depends on it. See Chapter 2.
>
> **The single most important rule after generation**: **read the generated `.md` files.** The real interface code, test programs, and build scripts — including the C++ CMake script — live inside them. See Chapter 3.
>
> **New in v2**: full coverage of the **CMake sub-toolchain** (`CMakeLists.txt` + `test_main___.cpp`) and the **bootstrap → AI-fill architecture** of the MCP tool provider unit. The MCP tool count has grown from 22 to **24**.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [⚠️ Global Prerequisite: The Bridge Must Always Be Running](#2-️-global-prerequisite-the-bridge-must-always-be-running)
3. [⚠️ Read This First: The Generated Markdown Is The Real Deliverable](#3-️-read-this-first-the-generated-markdown-is-the-real-deliverable)
4. [Environment Preparation](#4-environment-preparation)
5. [GUI Operation Guide](#5-gui-operation-guide)
6. [Command-Line Guide](#6-command-line-guide)
7. [Agent (MCP-API) Guide](#7-agent-mcp-api-guide)
8. [How the MCP Tool Provider Unit Is Built](#8-how-the-mcp-tool-provider-unit-is-built)
9. [Programmatic Interface](#9-programmatic-interface)
10. [Artifact Inventory](#10-artifact-inventory)
11. [JSON Safety and Stability](#11-json-safety-and-stability)
12. [Language Support: Today and Tomorrow](#12-language-support-today-and-tomorrow)
13. [Frequently Asked Questions](#13-frequently-asked-questions)

---

## 1. Project Overview

`code_decl_to_json_abi` is a **prototype-declaration → HTTP/JSON interface code generator**.

Give it a Pascal unit or a C header, and it will:

1. Parse out every top-level function/procedure declaration;
2. Normalize them into an intermediate model (Model);
3. Generate a complete set of **HTTP POST + JSON** interface code covering multiple language directions, **19 files in total** (17 code/README artifacts, plus 2 CMake build artifacts for C++).

### Supported source languages

Only two source languages are accepted:

- **Pascal** (`.pas` / `.pp` / `.p`)
- **C** (`.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx`)

### Supported target languages

| Target | Service (exposes the API) | Call (invokes the API) | CMake support |
|--------|---------------------------|------------------------|:-------------:|
| Pascal | ✅ `<unit>_http_json_service_unit.pas` | ✅ `<unit>_http_json_call_unit.pas` | — |
| Python | ✅ `<unit>_http_json_service.py` | ✅ `<unit>_http_json_call.py` | — |
| C++ | ✅ `.hpp` + `.cpp` (two files) | ✅ `.hpp` + `.cpp` (two files) | ✅ `CMakeLists.txt` + `test_main___.cpp` |
| JavaScript | ❌ (no service side) | ✅ `.js` + bundled test page `.html` | — |
| Per-target companion | ✅ Markdown README | ✅ Markdown README | — |

**One-sentence summary**: you write a Pascal/C "declaration", and the tool lays out all the cross-language, cross-process HTTP/JSON interfaces for you — including the CMake build script for the C++ side.

---

## 2. ⚠️ Global Prerequisite: The Bridge Must Always Be Running

> **This is the most important runtime prerequisite. Read this chapter before anything else.**

### 2.1 What the bridge is

**`bridge.py` (or a compiled `bridge.exe`) is the HTTP↔RPC forwarding tool provided by LingoFuse.**

Its only job is: **translate an HTTP request into a LingoFuse internal call, and translate the return value back into an HTTP response.**

```
HTTP client  ──HTTP POST──▶  bridge.py / bridge.exe  ──LF_Call──▶  service
HTTP client  ◀─HTTP resp──   bridge.py / bridge.exe  ◀─LF ret───   service
```

### 2.2 Why it must always be running

**Every call-side artifact** this tool generates (Pascal / Python / C++ / JavaScript) and the **bundled HTML test page** do **not** talk to the service directly. They all go through the bridge:

- **Pascal call side**: uses `LFHttpPost` internally to reach the bridge over LingoFuse.
- **Python call side**: uses `requests.post(...)` against the bridge's HTTP endpoint.
- **C++ call side**: reaches the bridge through the LingoFuse C ABI.
- **JavaScript call side**: uses `fetch(...)` to POST directly to the bridge's HTTP endpoint.
- **HTML test page**: same as JavaScript.
- **C++ test driver** (`test_main___.cpp`): same as the C++ call side — it goes through `lingofuse::bridge::httpCall`.

**As long as the bridge is not running, all of the above call sides and test pages will fail immediately.** Typical symptoms:

- `EHTTPCallError: ... Network error` (Pascal)
- `HTTPCallError: Network error` (Python)
- `HTTPCallError: ... (code=-1, http_status=0)` (C++)
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
Terminal 1 (service):      start the generated service (Pascal / Python / C++)
Terminal 2 (bridge):       python3 bridge.py --endpoint <same endpoint as the service> --port 8081 --no-precheck
Terminal 3 (caller / page): start the generated call side, or double-click the HTML test page
```

**The bridge must stay in the foreground in Terminal 2.** Only after you see it print the HTTP listening log may you begin invoking.

### 2.5 Common misunderstandings

- ❌ "Once the code is generated, I can call it directly." → No — the bridge must be running.
- ❌ "I only generate code inside the GUI, so I don't need the bridge." → **The GUI generation step genuinely does not need the bridge**, but the moment you **run** the generated code or open the test page, you do.
- ❌ "The bridge and the service are an either/or choice." → **Both must be running simultaneously.**
- ❌ "The bridge only needs to run once, then I can close it." → Closing the bridge closes the entire HTTP↔RPC path.

> **Memorize one sentence: the bridge (`bridge.py` / `bridge.exe`) is a forwarder and must always be running.**

---

## 3. ⚠️ Read This First: The Generated Markdown Is The Real Deliverable

> **This is the most important post-generation rule. It changes how you consume everything the tool produces.**

Every generated code artifact is paired with a companion **Markdown document**. That `.md` is not a "nice-to-have" — **it is where the real, runnable interface material lives.** When `code_decl_to_json_abi` produces, say, a C++ service, it writes:

- `<Unit>_http_json_service.hpp` + `<Unit>_http_json_service.cpp` — the generated C++ skeleton.
- `<Unit>_http_json_service_cpp.md` — **the companion document, and the real deliverable.**
- `CMakeLists.txt` + `test_main___.cpp` — the CMake build script and the test driver that the `.md`'s CMake section references by name.

### 3.1 What every generated `.md` contains

Each `<Unit>_http_json_<lang>.md` file contains, at minimum:

1. **A complete, copy-pasteable test program.**
   - **Pascal**: a full `.lpr` program you can compile as-is, with the exact `fpc -Fu<...>` command lines (search paths for `lingofuse_import.pas`, `Z.Core`, and the generated unit).
   - **Python**: the generated module already contains `if __name__ == "__main__":`, so the "test program" **is** the module itself; the `.md` tells you which environment variables and `PYTHONPATH` to set.
   - **C++**: a full `main.cpp`, plus **a CMake script and a raw compiler invocation (g++, clang++, MSVC)**. The CMake target names, include directories, source files, link libraries, and required C++ standard are all spelled out. The `.md`'s CMake section references `CMakeLists.txt` and `test_main___.cpp` — both of which are already generated alongside the `.hpp`/`.cpp` pair.
   - **JavaScript**: a self-contained HTML test page alongside the `.js`, plus instructions on how to serve it.

2. **The full interface reference for that artifact.**
   - Every API the artifact exposes.
   - Its typed signature in the target language.
   - The **request layout** and **success response layout** on the wire.
   - A **call example** per API.

3. **The build instructions for that specific language.**
   - **C++ CMake script** — target names, sources, includes, libraries, standard. The README shows the exact `cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=...` invocation.
   - **Pascal** — `lazbuild` project steps and `fpc -Fu<...>` command lines.
   - **Python** — `pip install` / `PYTHONPATH` setup for cmd, PowerShell, and bash.
   - **JavaScript** — how to open the test page, and how to include the `.js` in your own page.

4. **The deployment section.**
   - Which directories the runtime expects (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`, `z_ipc_*`).
   - Startup order: **service → bridge → caller**.
   - Shutdown order.
   - Environment variables that must be set on each OS.

5. **The troubleshooting table for that artifact.**
   - Symptom → cause → fix, tuned to the specific target language.

> **Rule of thumb**: whenever you finish generating code, **open the `.md` first**.

### 3.2 Why the Markdown is generated alongside the code

The `.md` and the code are generated from **the same `TPascal_Func_Model`** in the same pass. This guarantees:

- **They never drift apart.**
- **The `.md` always describes the current code.**
- **You can hand the `.md` to another engineer (or to an agent) and they can reproduce your build.**

### 3.3 What you will typically not find in the `.md`

- **Business logic.** The `internal_call_<Api>` stubs are deliberately left empty; you fill them in.
- **A ready-made CMake project for your entire application.** The `.md` gives you the CMake script for the generated artifact; wiring it into a larger project is your choice.
- **Credentials or deployment secrets.**

### 3.4 How to find the `.md` files

| Entry | Where to look |
|-------|---------------|
| **GUI** | Each sub-tab of the **Final Source** page shows **two editors**: the code, and the companion `.md`. Both are also on disk under `<exe dir>/<UnitName>/`. |
| **CLI** | Next to `<base>.<ext>`, the tool also writes `<base>_readme.md`. |
| **MCP** | Every `GetLastXxxReadme` tool returns the full `.md` text. |

### 3.5 Practical consequence for this guide

Because the `.md` files carry the language-specific details, this user guide does **not** try to reproduce every build command for every language. Instead:

- Chapters 5–7 cover the **three frontends** and how to drive them.
- Chapter 8 covers the **bootstrap → AI-fill architecture** of the MCP provider unit.
- Chapter 9 covers the **programmatic interface**.
- Chapters 10–11 cover the **artifact inventory, wire format, and JSON safety** — the cross-language invariants.
- **For any language-specific build, test, or CMake question, the answer is in the generated `.md`, not here.**

---

## 4. Environment Preparation

### 4.1 Running the tool directly

Run `code_decl_to_json_abi` from its executable directory. The program will look for the following files next to itself:

- `pascal_code_abi_rule.md` (Pascal prototype rules)
- `C_code_abi_rule.md` (C prototype rules)

Missing them does not block usage; it merely makes the GUI's "rule document" buttons inert.

### 4.2 Dependencies for the generation phase

- **The generation phase (GUI / CLI) has no extra dependencies.** The tool itself does not go online, and it does not use the bridge.
- **Running the generated code / test page** is when the bridge and the service come into play.

### 4.3 Dependencies for the runtime phase

| Component | Purpose | Required? |
|-----------|---------|:---------:|
| **Service** (compiled from the generated `*_service_*` code) | Provides the business logic | ✅ Required |
| **Bridge** (`bridge.py` or `bridge.exe`) | HTTP ↔ RPC forwarding | ✅ **Must always be running** |
| **Call side** (compiled from the generated `*_call_*` code, or the HTML test page) | Issues calls | On demand |
| **CMake ≥ 3.15** (for C++ targets only) | Builds the generated C++ pair | On demand |

### 4.4 Dependencies for C++ targets

The CMake script produced by the toolchain requires:

- **CMake 3.15** or later.
- A C **and** C++ compiler (the project declares `project(<name> C CXX)`).
- The LingoFuse C++ distribution directory, supplied as `LINGOFUSE_CPP_LIB_DIR`. It must contain `LingoFuse.h`, `LingoFuse.c`, `LingoFuse.hpp`, `lf_io.hpp`, `lf_http_bridge_client.hpp`, and `json.hpp`.

### 4.5 Agent mode

Agent mode requires the LingoFuse runtime:

- `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`
- `z_ipc_*.dll` / `libz_ipc_*.so`
- A Beacon service (`agent_main_app`) must be online

If you only use the local GUI / CLI, none of these runtime dependencies are needed.

---

## 5. GUI Operation Guide

### 5.1 Launching the GUI

**Run the executable with no command-line arguments.** The GUI opens directly.

The GUI has 5 top-level tabs, advancing left to right:

```
[1. Welcome] → [2. Source Code] → [3. Source ↔ JSON] → [4. JSON ↔ Model] → [5. Final Source]
```

Each tab has a row of "previous / next" buttons at the top, and a bottom panel showing the live `DoStatus` log.

At startup, the form also silently starts the **MCP service** on a background thread (see Chapter 7).

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
2. If you are unsure of the language, click **Select Language** to let the tool detect it.
3. If the syntax highlighting looks wrong, pick the language manually from the dropdown.
4. Click **Next: Pascal/C → JSON**.

### 5.4 Page 3 — Source ↔ JSON

This page displays the **raw parser output (LV0)**.

| Button | Purpose |
|--------|---------|
| **Back: rebuild code from JSON** | Rebuild source code from the current JSON, write it back to Page 2. |
| **Next: JSON ↔ Model** | Normalize LV0 into LV1 Model, jump to Page 4. |

You may **manually correct the JSON here** — for example, if the parser misclassifies a type, edit the string in the JSON directly and click **Next** to continue.

### 5.5 Page 4 — JSON ↔ Model

This page displays the **normalized model JSON (LV1)**.

| Button | Purpose |
|--------|---------|
| **Back: JSON ↔ Model** | Reverse-restore LV1 to LV0, write back to Page 3. |
| **Next: generate source** | Generate all 19 artifacts, jump to Page 5. |

**Tip**: the model JSON automatically drops unsupported types (`Boolean`, `Variant`, arrays, records, classes, interfaces, enums, sets, pointers, `Currency`, `TDateTime`, etc.). If a function does not appear in the final artifacts, it almost always has an unsupported ABI type in its parameters or return value.

### 5.6 Page 5 — Final Source

This page has **8 sub-tabs**, each showing **two editors** (code + companion `.md`):

| Sub-tab | Content |
|---------|---------|
| Pascal Service | Pascal service code + README |
| Pascal Call | Pascal call code + README |
| JavaScript Call | JS client code + README |
| JavaScript Test HTML | Self-contained HTML test page |
| Python Service | Python service code + README |
| Python Call | Python call code + README |
| C++ Service | C++ service `.hpp` + `.cpp` + README |
| C++ Call | C++ call `.hpp` + `.cpp` + README |
| **CMake** | **`CMakeLists.txt` + `test_main___.cpp`** |

> **Open the `.md` sub-tab first.** See Chapter 3. The `.md` is where the build commands, CMake scripts, and test programs live.

**Files have already been written to disk**: during generation, all 19 files are automatically written to the `<UnitName>/` subdirectory of the executable's directory.

Top button:

- **Back: Model JSON** — return to Page 4 to keep adjusting the model.

### 5.7 The CMake sub-tab

The CMake sub-tab shows the two fixed-name artifacts:

- `CMakeLists.txt` — the CMake build script.
- `test_main___.cpp` — the C++ call test driver.

These are written to `<exe dir>/<UnitName>/` and are the exact files that the C++ README's "Building – CMake" section references. **Copy them out of this tab (or from the disk directory) along with the `.hpp`/`.cpp` pair**, and the CMake project is complete.

### 5.8 Log panel

The bottom panel is the live `DoStatus` log. It shows which file was just saved, any dropped routines during normalization, and any errors from the generators. It clears itself when it exceeds 5000 lines.

---

## 6. Command-Line Guide

### 6.1 Trigger condition

Command-line mode **only triggers when at least one argument is passed**. No arguments = GUI.

The program is built for the console subsystem, therefore:

- Double-click = launch GUI (the system may pop up an extra empty console window; closing the main window ends it).
- Command-line run = all `DoStatus` messages go straight to stdout, and normal completion returns via exit codes.

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
| `.js` | JavaScript | **Call side only** |

**JavaScript is call-side only**: specifying a `.js` output without passing `--call` exits immediately with an argument error.

### 6.5 What each run produces

Taking the base name of `<output>` (extension removed), the tool writes to the **same directory**:

- **Code files**: `<base>.xxx` (single file for Pascal / Python / JS; C++ produces `<base>.hpp` + `<base>.cpp`).
- **Companion README**: `<base>_readme.md` — **the real deliverable** (see Chapter 3).
- **JS-specific**: additionally produces `<base>_test.html` (self-contained test page).
- **C++-specific**: additionally produces `CMakeLists.txt` and `test_main___.cpp` (**fixed names, no base prefix**).

> **Note on the C++ fixed names**: `CMakeLists.txt` and `test_main___.cpp` are the exact names the C++ README references. Generating two different units into the same directory will overwrite the previous CMake files. **One directory per unit.**

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

On error, it prints `Failed.` and returns a non-zero exit code. **Do not parse the wording**; depend on the exit code.

### 6.9 ⚠️ The CLI does not start the bridge

**The CLI is only responsible for generating code. It does not start the bridge, and it does not start the service.**

To actually run an end-to-end call, you must manually:

1. Compile / run the generated service (see the generated `<base>_readme.md` for build commands);
2. **Start `bridge.py` (or `bridge.exe`) separately and keep it running**;
3. Then run the call side or open the HTML test page.

### 6.10 ⚠️ The CLI delivers the `.md` alongside the code — read it

For every generated artifact, the CLI writes a `<base>_readme.md`. **Read it before you try to build anything.** The `.md` contains:

- The exact compile command for the target language.
- **The C++ CMake script**, when applicable.
- A complete test program.
- The tool reference for that artifact.
- The deployment and troubleshooting sections.

### 6.11 Building the generated C++

When the CLI produces a C++ target, the CMake support files land next to the `.hpp`/`.cpp` pair. The typical workflow is:

```bash
# Put the .hpp/.cpp pair, CMakeLists.txt, and test_main___.cpp in one directory.
cd that_directory

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The CMake project builds **two executables**:

- `<Unit>_http_json_service` — the service executable.
- `<Unit>_http_json_call_test` — the call test driver.

The CMake script **does not stage the runtime DLLs**. Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` and `z_ipc_*` next to the executables (or add their directory to `PATH` / `LD_LIBRARY_PATH`).

---

## 7. Agent (MCP-API) Guide

### 7.1 Trigger condition

**After the GUI starts**, the tool automatically launches the MCP service on a background thread:

1. Creates a LingoFuse App (default name `code_decl_to_json_abi_mcp_api`).
2. Connects to the LingoFuse endpoint (default `ipc:agent`).
3. Registers all **24 tools** via the Beacon (default App `agent_main_app`, API `register_agent`).

So for an agent to call this tool, the following must hold:

- This tool's GUI **is running**;
- The Beacon (e.g. `pascal_agent_service`) **is running**;
- The two LingoFuse endpoints match (default `ipc:agent`).

> **Note**: the MCP service and the bridge **are two different things**.
> - The MCP service: lets an agent invoke this tool's 24 APIs (to generate code).
> - The bridge: lets every runtime call side reach the service.
>
> **They do not substitute for each other.** The agent does not need the bridge to generate code; but the moment the generated code runs, **the bridge must still be up**.

### 7.2 Tool inventory (24 tools)

Grouped into 5 functional clusters.

#### 7.2.1 Write / Inspect (Step 1)

| Tool | Purpose |
|------|---------|
| `CodeDeclToJsonAbi_SetSourceCode` | **Step 1**: put a source string (Pascal or C) into the "source editor" and select the source language. Args: `Source`, `Language` (`"pascal"` or `"c"`). |
| `CodeDeclToJsonAbi_SetModelJson` | **Step 1 alternative**: feed an LV1 Model JSON directly. Arg: `ModelJson`. |
| `CodeDeclToJsonAbi_GetSourceJson` | **Read-only**: return the current LV0 source JSON. |
| `CodeDeclToJsonAbi_GetModelJson` | **Read-only**: return the current LV1 model JSON. |

> `SetSourceCode` and `SetModelJson` are **two mutually exclusive entry points**. Either works, but once you use `SetModelJson` you skip both the parser and the normalizer.

#### 7.2.2 Generation (Step 2)

| Tool | Purpose |
|------|---------|
| `CodeDeclToJsonAbi_GenerateAll` | **Step 2**: run all generators and cache the results. Returns JSON with `unit_name` and a `files` manifest that includes the two CMake artifacts. |

`GenerateAll` may be called repeatedly; each call re-runs every generator against the current model JSON.

#### 7.2.3 Read Artifacts (Step 3, 19 read-only tools)

**Pascal**

| Tool | Artifact |
|------|----------|
| `CodeDeclToJsonAbi_GetLastPascalServiceCode` | Pascal service code |
| `CodeDeclToJsonAbi_GetLastPascalServiceReadme` | Pascal service README |
| `CodeDeclToJsonAbi_GetLastPascalCallCode` | Pascal call code |
| `CodeDeclToJsonAbi_GetLastPascalCallReadme` | Pascal call README |

**JavaScript**

| Tool | Artifact |
|------|----------|
| `CodeDeclToJsonAbi_GetLastJsCallCode` | JS client |
| `CodeDeclToJsonAbi_GetLastJsCallReadme` | JS README |
| `CodeDeclToJsonAbi_GetLastJsTestHtml` | HTML test page |

**Python**

| Tool | Artifact |
|------|----------|
| `CodeDeclToJsonAbi_GetLastPythonServiceCode` | Python service |
| `CodeDeclToJsonAbi_GetLastPythonServiceReadme` | Python service README |
| `CodeDeclToJsonAbi_GetLastPythonCallCode` | Python call |
| `CodeDeclToJsonAbi_GetLastPythonCallReadme` | Python call README |

**C++**

| Tool | Artifact |
|------|----------|
| `CodeDeclToJsonAbi_GetLastCppServiceHeader` | C++ service `.hpp` |
| `CodeDeclToJsonAbi_GetLastCppServiceImpl` | C++ service `.cpp` |
| `CodeDeclToJsonAbi_GetLastCppServiceReadme` | C++ service README |
| `CodeDeclToJsonAbi_GetLastCppCallHeader` | C++ call `.hpp` |
| `CodeDeclToJsonAbi_GetLastCppCallImpl` | C++ call `.cpp` |
| `CodeDeclToJsonAbi_GetLastCppCallReadme` | C++ call README |

**CMake**

| Tool | Artifact |
|------|----------|
| `CodeDeclToJsonAbi_GetLastCMakeScript` | `CMakeLists.txt` |
| `CodeDeclToJsonAbi_GetLastTestMainCpp` | `test_main___.cpp` |

All 19 readers are **pure read** — they never trigger new parsing or generation.

### 7.3 Recommended call sequences

**Minimum flow (you only need one artifact)**:

```
1. CodeDeclToJsonAbi_SetSourceCode(Source="...", Language="pascal")
2. CodeDeclToJsonAbi_GenerateAll()
3. CodeDeclToJsonAbi_GetLastPythonServiceCode()      ← pick whichever you want
```

**Inspect-only flow (see the parse and the model)**:

```
1. CodeDeclToJsonAbi_SetSourceCode(Source="...", Language="c")
2. CodeDeclToJsonAbi_GetSourceJson()                 ← inspect LV0
3. CodeDeclToJsonAbi_GetModelJson()                  ← inspect LV1
```

**Direct-injection flow (you already have a model)**:

```
1. CodeDeclToJsonAbi_SetModelJson(ModelJson="...")
2. CodeDeclToJsonAbi_GenerateAll()
3. Invoke any of the 19 readers as needed
```

**Full C++ build-prep flow (recommended for agents that will also build the artifacts)**:

```
1. CodeDeclToJsonAbi_SetSourceCode(<source>, "c")
2. CodeDeclToJsonAbi_GenerateAll()
3. CodeDeclToJsonAbi_GetLastCppServiceHeader()      ← the .hpp
4. CodeDeclToJsonAbi_GetLastCppServiceImpl()        ← the .cpp
5. CodeDeclToJsonAbi_GetLastCMakeScript()           ← CMakeLists.txt
6. CodeDeclToJsonAbi_GetLastTestMainCpp()           ← test_main___.cpp
7. CodeDeclToJsonAbi_GetLastCppServiceReadme()      ← ⚠️ READ THIS FIRST
```

Step 7 returns the `.md`. **The `.md` is where the CMake invocation, the include directories, and the link libraries are.** An agent that intends to actually build the artifact should read the `.md` before doing anything else.

### 7.4 Tool return values

Every tool returns a **JSON string**.

`SetSourceCode` / `SetModelJson` on success:

```json
{"status":"ok","unit_name":"Calculator"}
```

`GenerateAll` on success:

```json
{
  "status":"ok",
  "unit_name":"Calculator",
  "files":{
    "pascal_service_code":   "Calculator_http_json_service_unit.pas",
    "pascal_service_readme": "Calculator_http_json_service_pascal.md",
    "pascal_call_code":      "Calculator_http_json_call_unit.pas",
    "pascal_call_readme":    "Calculator_http_json_call_pascal.md",
    "js_call_code":          "Calculator_http_json_call.js",
    "js_call_readme":        "Calculator_http_json_call_js.md",
    "js_test_html":          "Calculator_http_json_call_test.html",
    "python_service_code":   "Calculator_http_json_service.py",
    "python_service_readme": "Calculator_http_json_service_python.md",
    "python_call_code":      "Calculator_http_json_call.py",
    "python_call_readme":    "Calculator_http_json_call_python.md",
    "cpp_service_header":    "Calculator_http_json_service.hpp",
    "cpp_service_impl":      "Calculator_http_json_service.cpp",
    "cpp_service_readme":    "Calculator_http_json_service_cpp.md",
    "cpp_call_header":       "Calculator_http_json_call.hpp",
    "cpp_call_impl":         "Calculator_http_json_call.cpp",
    "cpp_call_readme":       "Calculator_http_json_call_cpp.md",
    "cmake_script":          "CMakeLists.txt",
    "test_main_cpp":         "test_main___.cpp"
  }
}
```

On failure:

```json
{"error":"<message>"}
```

**The 19 readers** return the **full artifact text** (plain text, not JSON) on success; on failure, they return an empty string.

### 7.5 Agent-mode notes

1. **The source language only accepts `"pascal"` or `"c"`**; any other value is rejected.
2. **Do not alternate `SetSourceCode` and `SetModelJson` within one session** — the later call completely overwrites the earlier state.
3. **`GenerateAll` is idempotent**: repeated calls do not accumulate garbage; they simply rewrite the caches.
4. **Order matters**: `SetSourceCode`/`SetModelJson` → `GenerateAll` → read. Reversing the order fails.
5. **The 19 readers are only valid for the "most recent successful `GenerateAll`"**: calling them before `GenerateAll` returns empty strings.
6. **The GUI must be alive**: the MCP service is attached at GUI startup; closing the GUI takes all tools offline.
7. **Generating code with an agent ≠ running the code**: to actually run the generated code, **you must still manually start the bridge and keep it running**.
8. **Point agents at the `.md` files.** After a successful `GenerateAll`, every `GetLastXxxReadme` returns a `.md`. **That `.md` is where the build commands, CMake scripts, and test programs live.**
9. **For C++ targets, always fetch all five artifacts**: the header, the implementation, the CMake script, the test driver, and the README. Fetching only the `.hpp`/`.cpp` pair leaves the build incomplete.

### 7.6 Example agent interaction

```
# 1. Feed the source
CodeDeclToJsonAbi_SetSourceCode(
    Source   = "<contents of calculator.pas>",
    Language = "pascal")

# 2. Generate everything
CodeDeclToJsonAbi_GenerateAll()

# 3. Read the artifacts (and the companions)
CodeDeclToJsonAbi_GetLastCppServiceHeader()      # the .hpp
CodeDeclToJsonAbi_GetLastCppServiceImpl()        # the .cpp
CodeDeclToJsonAbi_GetLastCMakeScript()           # CMakeLists.txt
CodeDeclToJsonAbi_GetLastTestMainCpp()           # test_main___.cpp
CodeDeclToJsonAbi_GetLastCppServiceReadme()      # ⚠️ the .md — has the CMake invocation

CodeDeclToJsonAbi_GetLastPythonServiceCode()     # the .py
CodeDeclToJsonAbi_GetLastPythonServiceReadme()   # ⚠️ the .md — has the run instructions

CodeDeclToJsonAbi_GetLastPascalServiceCode()     # the .pas
CodeDeclToJsonAbi_GetLastPascalServiceReadme()   # ⚠️ the .md — has the .lpr test program
```

The agent can then either forward the artifacts to a user or, if the environment permits, execute the build and run instructions directly from the `.md`.

---

## 8. How the MCP Tool Provider Unit Is Built

This chapter documents the **bootstrap → AI-fill architecture** that produces `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`. Every statement here is about the **tooling that writes the tool provider**, not about the tool provider itself.

### 8.1 The Three-Stage Build

The tool provider unit is not written by hand. It is produced in three stages:

```
Stage 1: Bootstrap script
    ↓ emits a structurally complete Pascal unit
    ↓ with 24 callback shells, 24 internal-call stubs, 24 tool schemas
    ↓ and the full registration scaffolding
    code_decl_to_json_abi_mcp_api_tool_provider_unit.pas

Stage 2: AI fill-in
    ↓ fills the body of each internal_call_* function
    ↓ with the UI-synchronization logic

Stage 3: Compile + run
    ↓ the unit is compiled into the GUI executable
    ↓ at GUI startup, the MCP service registers all 24 tools
```

### 8.2 What the Bootstrap Script Writes

For each of the 24 tools, the bootstrap script writes:

1. **A `function` declaration in the `interface` section** — the external signature.
2. **A `procedure Callback_...` forward declaration** — the cdecl callback that LingoFuse will invoke.
3. **The full body of `procedure Callback_...`** — including:
   - Reading the input `TDataHnd___` as UTF-8 bytes.
   - Parsing the bytes as JSON.
   - Extracting named parameters.
   - **Calling the corresponding `internal_call_*` function** (this call is already written; the AI does not touch it).
   - Writing the return string back to the output `TDataHnd___`.
   - A `try/except` envelope that converts any exception into `{"error": "..."}`.
4. **A shell for `function internal_call_...`** — the FPC/Delphi `{$IFDEF}` split, the `TCompute.Sync` wrapper, and a **body that the AI must fill in**.
5. **A tool schema registration** in `RegisterTools` — the tool's `name`, `description`, `target_app`, `target_api`, and JSON `parameters` schema.

The bootstrap script also writes the entire registration scaffolding in `RegisterAPIs` (24 `LF_RegisterCallEx` calls) and `Execute_And_Reg_all` (the App creation, the endpoint connection, and the beacon handshake).

### 8.3 What the AI Fills In

The AI fills exactly one thing per tool: **the body inside `Do_Sync___` (FPC) or the anonymous procedure (Delphi)**.

Every AI-written body follows the same four-step pattern:

```
Step 1: Null-check the form.
        if code_decl_to_abi_json_form = nil then
          Result := JsonError('Form not available');

Step 2: Touch the form.
        - Write to an editor, OR
        - Call a button-click handler, OR
        - Switch a tab, OR
        - Read an editor's .Lines.Text

Step 3: Build the return string.
        - JsonStatusOk, OR
        - JsonStatusOkWithUnit(...), OR
        - JsonError(...), OR
        - the raw editor text.

Step 4: Clear the CMake session caches if this is an input tool.
        FSessionCMakeScript := '';
        FSessionTestMainCpp := '';
```

The AI never writes:

- The `TCompute.Sync` wrapper.
- The callback envelope.
- The exception handling.
- The LingoFuse registration code.
- The tool schema.

### 8.4 Why the UI-Synchronization Pattern

The critical design decision: **the AI does not write new state management logic**. Every MCP tool body delegates to the GUI form. The chain of custody is:

```
MCP client
    ↓ calls CodeDeclToJsonAbi_GenerateAll (LingoFuse Call)
Callback_CodeDeclToJsonAbi_GenerateAll_..._GenerateAll (cdecl, worker thread)
    ↓ calls internal_call_...
internal_call_CodeDeclToJsonAbi_GenerateAll_..._GenerateAll
    ↓ TCompute.Sync(Do_Sync___)
Do_Sync___ (runs on the MAIN thread)
    ↓ writes code_decl_to_abi_json_form.SourceCodeEditor.Text
    ↓ calls code_decl_to_abi_json_form.ParseSourceToJsonClick
    ↓ calls code_decl_to_abi_json_form.NormalizeJsonToModelClick
    ↓ calls code_decl_to_abi_json_form.GenerateAllSourcesClick
    ↓ reads code_decl_to_abi_json_form.PascalServiceCodeEditor.Lines.Text
    ↓ returns to TCompute.Sync
TCompute.Sync returns
    ↓ internal_call_* returns the string
Callback_* writes the string to the output DataHandle
    ↓ LingoFuse returns to the MCP client
```

Every arrow in that chain is **written once** by the bootstrap script, except the three lines inside `Do_Sync___` that touch the form.

**Consequences of this design**:

1. **The GUI is the single source of truth.** There is no parallel state.
2. **Adding a new MCP tool is a purely mechanical operation.** Copy an existing `internal_call_*` pair, rename it, point it at a different form field or button click, and add the tool schema to `RegisterTools`.
3. **The GUI's button-click handlers are effectively the MCP tool implementations.** The MCP layer is a thin remote-control veneer.
4. **Thread-safety is inherited, not reinvented.** `TCompute.Sync` marshals the body onto the main thread.
5. **No new state fields.** If an MCP tool needs a value, that value must already exist as a form editor or form field.

### 8.5 The Six Tool Patterns

Every one of the 24 tools falls into one of six patterns. The AI's fill-in is determined entirely by which pattern the tool belongs to.

#### Pattern A — Setter, writes to an editor and returns a status JSON

Examples: `SetSourceCode`, `SetModelJson`.

The AI writes:
1. Null-check.
2. Validate the argument.
3. Write to the editor.
4. Switch the tab.
5. Clear the CMake caches.
6. Return `JsonStatusOk` or `JsonStatusOkWithUnit(...)`.

#### Pattern B — Reader, returns an editor's `.Lines.Text`

Examples: `GetSourceJson`, `GetModelJson`.

The AI writes:
1. Null-check.
2. Read the editor.
3. Return the text.

#### Pattern C — CMake cache reader, returns a session string

Examples: `GetLastCMakeScript`, `GetLastTestMainCpp`.

The AI writes exactly one line: `Result := FSessionCMakeScript;` (or `FSessionTestMainCpp`).

#### Pattern D — Driver, calls a sequence of button-click handlers

Examples: `GenerateAll`.

The AI writes:
1. Null-check.
2. Check that source or model is present.
3. Call the appropriate button-click handlers in order.
4. Read the model JSON to extract `UnitName`.
5. Call `GenerateCMakeScript` and `GenerateTestMainCpp` directly, caching the results.
6. Build the file manifest JSON.
7. Return the manifest.

#### Pattern E — Artifact reader, switches to a Final Source sub-tab and returns an editor

Examples: the 17 artifact readers for Pascal / JS / Python / C++.

The AI writes:
1. Null-check.
2. Switch `MainPageControl.ActivePage` to `FinalSourceTabSheet`.
3. Switch `FinalSourcePageControl.ActivePage` to the appropriate child tab.
4. Return the editor's `.Lines.Text`.

#### Pattern F — Tool that produces no value (rare)

No such tool exists in the current 24, but the pattern is available if a future tool needs it.

### 8.6 A Worked Example — `SetSourceCode`

The bootstrap writes the entire callback and the entire function shell. The AI writes only the `Do_Sync___` body:

```pascal
procedure Do_Sync___();
var
  lang: string;
begin
  if code_decl_to_abi_json_form = nil then
  begin
    Result := JsonError('Form not available');
    Exit;
  end;

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
    Result := JsonError('Unsupported language. Use pascal or c.');
    Exit;
  end;

  code_decl_to_abi_json_form.SourceCodeEditor.Text := Source;
  code_decl_to_abi_json_form.MainPageControl.ActivePage :=
    code_decl_to_abi_json_form.SourceCodeTabSheet;

  FSessionCMakeScript := '';
  FSessionTestMainCpp := '';

  Result := JsonStatusOk;
end;
```

The AI's contribution is exactly the **six UI touches**: set the combo box index, call the change handler, write the editor text, switch the page, clear two caches, and return the status.

### 8.7 What the AI Must Not Do

- **Do not add new state fields to the form** for the sake of an MCP tool.
- **Do not call UI methods from the worker thread.** Every UI touch must be inside `Do_Sync___`.
- **Do not bypass the callback envelope.** Let exceptions propagate; the envelope converts them into `{"error": "..."}`.
- **Do not renumber or rename the tools.** Tool names are stable identifiers that external callers depend on.
- **Do not modify the tool schemas** without updating the AI-filled bodies in lockstep. The schema's `properties` names are the parameter names the callback extracts.

### 8.8 Adding a New Tool — the Mechanical Recipe

To add a 25th tool:

1. **Choose the pattern** (A–E) that matches what the tool does.
2. **In the bootstrap script's tool table**, add a new entry with:
   - The tool name.
   - A description string.
   - The parameter list.
   - The pattern identifier.
3. **Re-run the bootstrap script.** It regenerates the unit with the new callback, the new stub, and the new tool schema.
4. **Fill in the AI body** following the chosen pattern.
5. **Update the GUI** if the tool needs a new editor or a new tab.
6. **Rebuild the GUI executable.**

The tool then appears in the beacon's tool list automatically. No other file needs to change.

### 8.9 Why This Architecture Scales

The architecture keeps three concerns separate:

- **Plumbing** (bootstrap): LingoFuse registration, cdecl callbacks, error envelopes, tool schemas.
- **Dispatch** (AI fill-in): the mapping from an MCP tool to a GUI action.
- **State** (GUI form): the actual in-memory session.

Because dispatch is a pure mapping and never owns state, an AI can regenerate the dispatch layer from scratch without losing any session data. And because the bootstrap script owns the plumbing, adding a tool never requires hand-writing LingoFuse boilerplate.

---

## 9. Programmatic Interface

The tool can also be driven from another program. This section describes the **public API surface** — the same functions the CLI, GUI, and MCP provider call internally.

### 9.1 Where the API Lives

| Unit | Exports |
|------|---------|
| `http_pas_abi_service_generator_tool` | `GenerateHTTPServicePascalCode` / `GenerateHTTPServicePascalReadme` |
| `http_pas_abi_call_generator_tool` | `GenerateHTTPCallPascalCode` / `GenerateHTTPCallPascalReadme` |
| `http_py_abi_service_generator_tool` | `GenerateHTTPServicePythonCode` / `GenerateHTTPServicePythonReadme` |
| `http_py_abi_call_generator_tool` | `GenerateHTTPCallPythonCode` / `GenerateHTTPCallPythonReadme` |
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

Every `Generate*Code` function has a **companion `Generate*Readme` function**. If you call only the code function and not the README function, you produce a `.pas` / `.py` / `.hpp` without its build instructions. **Always call both.** The generated code and its `.md` are designed to be produced together.

### 9.6 Registering Custom Generators with the Tool Itself

If you are extending the tool and want your generator to appear in the CLI, GUI, or MCP frontends, you must register it in three places:

1. `code_decl_to_json_abi.lpr` — `uses` clause, so the unit's `initialization` runs.
2. `code_decl_to_abi_json_frm.pas` — `implementation uses`, so the GUI can call it.
3. `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` — `RegisterAPIs`, `RegisterTools`, and the appropriate `internal_call_*` function, so agents can reach it.

For the third point, follow the mechanical recipe in Chapter 8.8.

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
| `*_http_json_call.js` | Browser JS client (IIFE, attached to `window.<UnitName>Api`). | ✅ **Required** |
| `*_http_json_call_test.html` | Self-contained HTML test page; double-click to test. | ✅ **Required** |
| `CMakeLists.txt` | CMake build script for the C++ pair + C++ test driver. | — |
| `test_main___.cpp` | C++ call test driver referenced by the CMake script. | ✅ **Required** (when executed) |
| `*_readme.md` | **Per-artifact companion documentation. The real deliverable.** Contains wire protocol, type mapping, deployment, testing, API reference, and language-specific build scripts (including the C++ CMake script). | — |

> **Note**: **The service itself does not go through the bridge.** The bridge only serves the "call → service" direction.

### 10.2 File Locations

- **GUI / MCP**: artifacts are written to the `<UnitName>/` subdirectory of the executable's directory.
- **CLI**: artifacts are written to the output file's directory.

### 10.3 The Two CMake Artifacts Are Unit-Level

`CMakeLists.txt` and `test_main___.cpp` use **fixed names** (no unit prefix). Generating two different units into the same directory will overwrite the previous CMake files. **Use one directory per unit.**

### 10.4 The Bridge Is a Forwarder, and Must Always Be Running

**Every generated call side (Pascal / Python / C++ / JavaScript) talks to the backend through the bridge:**

```
caller ──HTTP POST──▶ bridge.py / bridge.exe ──LF_Call──▶ service
caller ◀─HTTP resp──  bridge.py / bridge.exe ◀─LF ret───  service
```

**When starting the bridge, specify an endpoint that matches the service, e.g.:**

```
python3 bridge.py --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

**Important rules, once more for emphasis**:

- **The bridge is a forwarder and must always be running.** Closing the bridge closes the whole path.
- The bridge may run as `bridge.py` or be compiled into `bridge.exe` — both behave identically.
- The bridge should run in its **own terminal**, in the foreground. Only after you see the HTTP listening log should you start the call side.
- After a crash or kill, restarting the bridge is enough to recover; the call side does not need to be restarted.

### 10.5 Where the CMake Script Looks for the LingoFuse C++ Library

The CMake script requires a directory that contains:

- `LingoFuse.h`
- `LingoFuse.c`
- `LingoFuse.hpp`
- `lf_io.hpp`
- `lf_http_bridge_client.hpp`
- `json.hpp`

Supply the directory at configure time via `-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf`, or via the cmake-gui field labeled **"LingoFuse C++ library directory"**.

---

## 11. JSON Safety and Stability

Because every generated call side ultimately speaks JSON over HTTP, **JSON is the safety and stability boundary of the entire pipeline**. The following points are guaranteed by the toolchain:

1. **UTF-8 everywhere.** Requests and responses are always UTF-8; the bridge serializes with `ensure_ascii=False`, so non-ASCII payloads (Chinese, emoji, and other multi-byte content) are carried as literal UTF-8 rather than being re-encoded as `\uXXXX` escapes.

2. **NUL-terminator policy is explicit.** LingoFuse strings are NUL-terminated on the wire. The bridge **strips the trailing NUL** before forwarding to HTTP clients, and the generated call sides never emit a stray NUL into JSON.

3. **The bridge is binary-safe.** If a payload cannot be parsed as JSON at all, the bridge forwards it verbatim rather than corrupting it.

4. **Deterministic unwrapping.** The bridge wraps every service response in a stable envelope (`{"status_code": ..., "headers": ..., "body": ...}`). The generated call sides unwrap `body` and check `body.code`; code `0` returns `body.result`, any other code raises the language-appropriate exception.

5. **No silent precision loss on the wire.** Large integers are transmitted as JSON numbers by default, which is safe for Python and for C++ (via `std::int64_t` on the service side). It is **not** safe for the JavaScript client, whose `Number` is IEEE-754 double. For `int64` / `uint64` interfaces intended for browser consumption, **the recommended pattern is to have the service return the value as a string**. The generated READMEs call this out explicitly.

6. **Stable error schema.** Every failure surfaces either as `{"error":"<message>"}` (tool-level) or as `{"code": -N, "error": "<message>"}` (service/bridge level). Call sides translate these into language-specific exceptions: `EHTTPCallError` (Pascal), `HTTPCallError` (Python / C++), `LFHttpCallError` (JavaScript).

The practical upshot: **as long as the bridge is running and the endpoint strings match on both sides, JSON payloads produced by one language's call side are consumed correctly by any other language's service side, and vice versa.**

---

## 12. Language Support: Today and Tomorrow

### 12.1 Excellent Interface Support for Strongly-Typed Languages

For **Pascal, C++, and Python**, the generated interfaces are first-class, not merely stubs:

- **Pascal**: the generated service unit registers cdecl callbacks with LingoFuse directly and uses `Z.Json` for serialization. The generated call unit uses `LFHttpPost` from `lf_http_bridge_client` and exposes each API as a **typed free function**.
- **C++**: the generated service produces a clean `.hpp`/`.cpp` pair with a namespace, typed function signatures, `LF_CDECL`-compatible callbacks, and JSON I/O helpers. The generated call side exposes a **typed free function per API** and carries a rich set of tunables. **The generated `.md` contains the CMake script and every compiler invocation you need**, and the CMake pair is emitted alongside the code.
- **Python**: the generated service module exposes a `register_all_http_json_apis(app)` entry point with typed internal stubs; the generated call module exposes **one typed Python function per API** and a unified internal `_call_api()` dispatcher.

In all three languages, the type families (integer / float / string) map to the language's natural primitives, JSON serialization is handled internally, and the only thing the developer has to do is fill in the `internal_call_<Api>` stub body.

### 12.2 Excellent Support for Full-Stack Languages (JavaScript Today; TypeScript and PHP on the Roadmap)

- **JavaScript (available today)**: the generated `.js` is a **self-contained IIFE**, attaches itself to `window.<Unit>Api` (or `globalThis.<Unit>Api`), uses only `fetch` / `Promise` / `async-await`, and has **no third-party dependencies**. A **self-contained HTML test page** is bundled alongside.
- **TypeScript (roadmap)**: a natural next step that will reuse most of the JS backend and add `.d.ts`-style declaration output.
- **PHP (roadmap)**: a separate backend that will plug into the same CLI / GUI / MCP dispatch, exposing each API as a typed PHP function using the same HTTP/JSON wire protocol.

### 12.3 The System Is Designed for Unbounded Extension

Adding a new target language is a **mechanical process**, not an architectural change. The steps are:

1. Create two generator units: `<lang>_abi_service_generator_tool.pas` and `<lang>_abi_call_generator_tool.pas`.
2. Provide a type mapping table from the three ABI families to the target language's native types.
3. Register the new units in the main program, the CLI dispatcher, the GUI form, and the MCP tool provider.
4. Update the CLI's `Detect_Target_Lang` and help text.
5. Update the MCP `regCount` assertion and the tool schema table.

**There is no architectural ceiling on the number of supported target languages.** Every language with (a) an HTTP client, (b) a JSON library, and (c) a runtime that can speak the wire protocol is a candidate.

**The user-facing contract does not change when a language is added**: the same CLI flags, the same GUI workflow, and the same MCP tools continue to work.

---

## 13. Frequently Asked Questions

### Q1: Why is a function I passed in missing from the generated result?

Check three things:

1. **Is the function top-level** (in the `interface` section, not nested inside a `class` / `record`)? Nested declarations are skipped.
2. **Are its parameters and return type in the supported set?** Only the integer family, float family, and string family are accepted.
3. **Is the function name non-empty?**

### Q2: Why does the model JSON have fewer functions than the source file?

Same as above. During normalization, any function with unsupported types is dropped wholesale.

### Q3: What happens if the CLI is asked to output `.js` without `--call`?

It exits immediately with an argument error, exit code `1`. JavaScript is a call-side-only target.

### Q4: I see no output at all after running the CLI.

In CLI mode, this tool writes all `DoStatus` messages to stdout. If you are running from inside an IDE or have redirected stdout, you may not see them. Run it directly in a terminal.

### Q5: The "rule document" buttons in the GUI do nothing.

The executable directory is missing `pascal_code_abi_rule.md` or `C_code_abi_rule.md`. Put those two files next to the executable.

### Q6: An agent call returns `{"error":"Form not available"}`.

The GUI is not running. The MCP service is a GUI-lifetime service; after the GUI closes, all tools become unavailable.

### Q7: An agent call returns `{"error":"Beacon not available ..."}`.

The Beacon service (default `agent_main_app`) is not online, or its endpoint differs from this tool's endpoint. Check both sides' `--endpoint` arguments.

### Q8: What exactly do I get if I call `GetModelJson` immediately after `SetSourceCode`?

You get the result of the **normalizer running automatically**. Both `GetSourceJson` and `GetModelJson` compute LV0/LV1 on the fly when `SetSourceCode` succeeds.

### Q9: Does calling `GenerateAll` multiple times pollute the result?

No. Every `GenerateAll` re-runs all generators from scratch, overwriting the old caches.

### Q10: Can I generate only one target language?

**The current version does not support that.** `GenerateAll` produces all artifacts at once. If you only want one of them, pick it out of the readers; the files written to disk can simply be ignored.

### Q11: Running the generated call side or HTML test page gives `Network error` / `Failed to fetch` / `Connection refused`.

**99% of the time, the bridge is not running (or was up and got closed).**

Troubleshooting steps:

1. **Confirm the bridge is actually running**: check its terminal for live log output.
2. **Confirm the bridge's endpoint matches the service**.
3. **Confirm the bridge's port matches the caller's expectation**: default `8081`.
4. **Restart the bridge**.

> Once again: **the bridge (`bridge.py` / `bridge.exe`) is a forwarder and must always be running.**

### Q12: The service is up — why can I still not reach it?

The service, the bridge, and the caller are **three independent processes**, and all three are required:

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
- Only the bridge, no service → the bridge reports API not available / timeout.
- All three up but not started in order → restart in the order "service → bridge → caller".

### Q13: Where do I find the CMake script for the generated C++?

There are **three** equivalent ways:

1. On disk: the file `CMakeLists.txt`, written next to the generated `.hpp`/`.cpp` pair.
2. In the GUI: the **CMake** sub-tab of the Final Source page.
3. Via MCP: `CodeDeclToJsonAbi_GetLastCMakeScript`.

The companion file `test_main___.cpp` is available by the same three routes.

### Q14: How do I build the generated C++?

Put the `.hpp`, `.cpp`, `CMakeLists.txt`, and `test_main___.cpp` in one directory, then:

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The CMake project builds two executables: `<Unit>_http_json_service` and `<Unit>_http_json_call_test`.

### Q15: Does the CMake script stage the LingoFuse DLLs?

No. Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` and `z_ipc_*` next to the executables, or add their directory to `PATH` / `LD_LIBRARY_PATH`.

### Q16: Where do I find the test program for the generated Pascal?

**In the generated `<Unit>_http_json_service_pascal.md` (or `_call_pascal.md`).** It contains a complete `.lpr` file and the exact `fpc -Fu<...>` command line to build it.

### Q17: How do I build the generated Python service?

**Read the `<Unit>_http_json_service_python.md`.** It tells you which `PYTHONPATH` or `pip install` is needed, and it relies on the generated module's own `if __name__ == "__main__":` block as the test program.

### Q18: How does the MCP tool provider unit get built? Do I have to write it by hand?

No. It is produced by a **three-stage build**:

1. **Bootstrap script** — emits the structurally complete unit: callbacks, error envelopes, tool schemas, LingoFuse registration, and function shells.
2. **AI fill-in** — fills the body of each `internal_call_*` function with the UI-synchronization logic.
3. **Compile** — the unit is compiled into the GUI executable.

Each `internal_call_*` body follows one of six patterns (see Chapter 8.5). The AI's contribution is a handful of UI touches per tool; everything else is mechanical.

### Q19: Why does the MCP tool count change between releases?

Because the tool set grows with the toolchain. v1 shipped 22 tools; v2 ships **24** — the two new ones (`GetLastCMakeScript` and `GetLastTestMainCpp`) expose the CMake artifacts added by the CMake sub-toolchain. Adding a new tool is a mechanical operation (see Chapter 8.8).

### Q20: Why does the guide keep telling me to read the `.md`?

Because **the `.md` is the real deliverable.** The code file is the skeleton; the `.md` is the manual that tells you how to build, test, and deploy that skeleton. Whenever you are about to compile, run, or debug a generated artifact, **the answer is in its `.md`, not in this user guide.**

---

## Appendix: One-Sentence Summary of the Usage Modes

- **GUI**: five tabs, click left to right; when something goes wrong, step back and fix it. Open the `.md` sub-tab before trying to build. The **CMake** sub-tab holds the two CMake artifacts.
- **CLI**: `code_decl_to_json_abi [--call] input output`; extension picks the language, exit code tells success or failure. Read `<base>_readme.md` before building. For C++ targets, look for `CMakeLists.txt` and `test_main___.cpp` in the same directory.
- **Agent**: `SetSourceCode` (or `SetModelJson`) → `GenerateAll` → invoke the 24 readers as needed. Read the `readme` fields for build instructions, and fetch the two CMake readers when building C++.
- **Programmatic**: call the `Generate*Code` and `Generate*Readme` functions directly; for C++, also call `GenerateCMakeScript` and `GenerateTestMainCpp`.

**The one rule you must never forget at runtime**: **the bridge (`bridge.py` or `bridge.exe`) is a forwarder and must always be running.**

**The one rule you must never forget after generation**: **read the generated `.md` files. The test code, the build scripts (including the C++ CMake script), and the interface reference all live there.**

---

*Document version: v2*
*Last updated: 2026-09-25*
*Document role: user-facing guide for code_decl_to_json_abi. For the deeper architectural reference, see code_decl_to_json_abi_knowledge_base.md.*