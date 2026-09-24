# code_decl_to_json_abi User Guide

> This document describes **how to use** `code_decl_to_json_abi`, covering:
> - Graphical User Interface (GUI) operation
> - Command-Line Interface (CLI) operation
> - Remote invocation from an agent (MCP / LingoFuse)
> - **Programmatic interface** (embedding the generator in your own tools)
>
> **The single most important rule at runtime**: the **bridge must always be running**. Every artifact this tool generates that performs a call ultimately depends on it. See Chapter 2.
>
> **The single most important rule after generation**: **read the generated `.md` files.** The real interface code, test programs, and build scripts — including the C++ CMake script — live inside them. See Chapter 3.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [⚠️ Global Prerequisite: The Bridge Must Always Be Running](#2-️-global-prerequisite-the-bridge-must-always-be-running)
3. [⚠️ Read This First: The Generated Markdown Is The Real Deliverable](#3-️-read-this-first-the-generated-markdown-is-the-real-deliverable)
4. [Environment Preparation](#4-environment-preparation)
5. [GUI Operation Guide](#5-gui-operation-guide)
6. [Command-Line Guide](#6-command-line-guide)
7. [Agent (MCP-API) Guide](#7-agent-mcp-api-guide)
8. [Programmatic Interface](#8-programmatic-interface)
9. [Artifact Inventory](#9-artifact-inventory)
10. [JSON Safety and Stability](#10-json-safety-and-stability)
11. [Language Support: Today and Tomorrow](#11-language-support-today-and-tomorrow)
12. [Frequently Asked Questions](#12-frequently-asked-questions)

---

## 1. Project Overview

`code_decl_to_json_abi` is a **prototype-declaration → HTTP/JSON interface code generator**.

Give it a Pascal unit or a C header, and it will:

1. Parse out every top-level function/procedure declaration;
2. Normalize them into an intermediate model (Model);
3. Generate a complete set of **HTTP POST + JSON** interface code covering multiple language directions, **17 files in total**.

### Supported source languages

Only two source languages are accepted:

- **Pascal** (`.pas` / `.pp` / `.p`)
- **C** (`.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx`)

### Supported target languages

| Target | Service (exposes the API) | Call (invokes the API) |
|--------|---------------------------|------------------------|
| Pascal | ✅ `<unit>_http_json_service_unit.pas` | ✅ `<unit>_http_json_call_unit.pas` |
| Python | ✅ `<unit>_http_json_service.py` | ✅ `<unit>_http_json_call.py` |
| C++ | ✅ `.hpp` + `.cpp` (two files) | ✅ `.hpp` + `.cpp` (two files) |
| JavaScript | ❌ (no service side) | ✅ `.js` + bundled test page `.html` |
| Per-target companion | ✅ Markdown README | ✅ Markdown README |

**One-sentence summary**: you write a Pascal/C "declaration", and the tool lays out all the cross-language, cross-process HTTP/JSON interfaces for you.

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

**As long as the bridge is not running, all of the above call sides and test pages will fail immediately.** Typical symptoms:

- `EHTTPCallError: ... Network error` (Pascal / C++)
- `HTTPCallError: Network error` (Python)
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

> **Memorize one sentence: the bridge (`bridge.py` / `bridge.exe`) is a forwarder and must always be running.** Every call-side artifact and test page this tool generates depends on it.

---

## 3. ⚠️ Read This First: The Generated Markdown Is The Real Deliverable

> **This is the most important post-generation rule. It changes how you consume everything the tool produces.**

Every generated code artifact is paired with a companion **Markdown document**. That `.md` is not a "nice-to-have" — **it is where the real, runnable interface material lives.** When `code_decl_to_json_abi` produces, say, a C++ service, it writes:

- `<Unit>_http_json_service.hpp` + `<Unit>_http_json_service.cpp` — the generated C++ skeleton.
- `<Unit>_http_json_service_cpp.md` — **the companion document, and the real deliverable.**

### 3.1 What every generated `.md` contains

Each `<Unit>_http_json_<lang>.md` file contains, at minimum:

1. **A complete, copy-pasteable test program.**
   - **Pascal**: a full `.lpr` program you can compile as-is, with the exact `fpc -Fu<...>` command lines (search paths for `lingofuse_import.pas`, `Z.Core`, and the generated unit).
   - **Python**: the generated module already contains `if __name__ == "__main__":`, so the "test program" **is** the module itself; the `.md` tells you which environment variables and `PYTHONPATH` to set.
   - **C++**: a full `main.cpp`, plus **a CMake script and a raw compiler invocation (g++, clang++, MSVC)**. The CMake target name, include directories, source files, link libraries, and required C++ standard are all spelled out. A minimal fallback header is provided so you can compile even before the official LingoFuse C++ binding is available.
   - **JavaScript**: a self-contained HTML test page alongside the `.js`, plus instructions on how to serve it.

2. **The full interface reference for that artifact.**
   - Every API the artifact exposes.
   - Its typed signature in the target language.
   - The **request layout** and **success response layout** on the wire.
   - A **call example** per API.

3. **The build instructions for that specific language.**
   - **C++ CMake script** — target name, sources, includes, libraries, standard.
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

> **Rule of thumb**: whenever you finish generating code, **open the `.md` first**. It is written for exactly the situation you are in — "I have the code, what do I do with it?".

### 3.2 Why the Markdown is generated alongside the code

The `.md` and the code are generated from **the same `TPascal_Func_Model`** in the same pass. This guarantees:

- **They never drift apart.** If you re-generate after editing the source unit, both the code and the `.md` are updated together.
- **The `.md` always describes the current code.** The tool reference is driven by the same function list the generators consumed.
- **You can hand the `.md` to another engineer (or to an agent) and they can reproduce your build.** Nothing is left implicit.

### 3.3 What you will typically not find in the `.md`

- **Business logic.** The `internal_call_<Api>` stubs are deliberately left empty; you fill them in. The `.md` tells you what signature to match and what the wire layout is, but not what to compute.
- **A ready-made CMake project for your entire application.** The `.md` gives you the CMake snippet for the generated artifact; wiring it into a larger project is your choice.
- **Credentials or deployment secrets.** The `.md` assumes a local, trusted runtime.

### 3.4 How to find the `.md` files

| Entry | Where to look |
|-------|---------------|
| **GUI** | Each sub-tab of the **Final Source** page shows **two editors**: the code, and the companion `.md`. Both are also on disk under `<exe dir>/<UnitName>/`. |
| **CLI** | Next to `<base>.<ext>`, the tool also writes `<base>_readme.md`. |
| **MCP** | Every `ConvertToXxx` call returns `{"result": "...", "readme": "..."}` — the `readme` field is the `.md` companion. Every `GetLastXxxReadme` tool returns its full text. |

### 3.5 Practical consequence for this guide

Because the `.md` files carry the language-specific details, this user guide does **not** try to reproduce every build command for every language. Instead:

- Chapters 5–7 cover the **three frontends** and how to drive them.
- Chapter 8 covers the **programmatic interface**.
- Chapters 9–11 cover the **wire format, JSON safety, and type system** — the cross-language invariants.
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

### 4.4 Agent mode

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
[1. Welcome] → [2. Source Code] → [3. Source <-> JSON] → [4. JSON <-> Model] → [5. Final Source]
```

Each tab has a row of "previous / next" buttons at the top, and a bottom panel showing the live `DoStatus` log.

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

You may **manually correct the JSON here** — for example, if the parser misclassifies a type, edit the string in the JSON directly and click **Next** to continue. The reverse-rebuild button helps you verify that your edits are still legal.

### 5.5 Page 4 — JSON ↔ Model

This page displays the **normalized model JSON (LV1)**.

| Button | Purpose |
|--------|---------|
| **Back: JSON ↔ Model** | Reverse-restore LV1 to LV0, write back to Page 3. |
| **Next: generate source** | Generate all 17 files, jump to Page 5. |

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

> **Open the `.md` sub-tab first.** See Chapter 3. The `.md` is where the build commands, CMake scripts, and test programs live.

**Files have already been written to disk**: during generation, all files are automatically written to the `<UnitName>/` subdirectory of the executable's directory, with the file name pattern `<UnitName>_http_json_*.xxx`.

Top button:

- **Back: Model JSON** — return to Page 4 to keep adjusting the model.

### 5.7 Log panel

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
| `.hpp` / `.hh` / `.h` / `.cpp` / `.cc` / `.cxx` / `.c` | C++ (`.hpp` + `.cpp` two files) | Service + Call |
| `.js` | JavaScript | **Call side only** |

**JavaScript is call-side only**: specifying a `.js` output without passing `--call` exits immediately with an argument error.

### 6.5 What each run produces

Taking the base name of `<output>` (extension removed), the tool writes to the **same directory**:

- **Code files**: `<base>.xxx` (single file for Pascal / Python / JS; C++ produces `<base>.hpp` + `<base>.cpp`).
- **Companion README**: `<base>_readme.md` — **the real deliverable** (see Chapter 3).
- **JS-specific**: additionally produces `<base>_test.html` (self-contained test page).

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

**Service: C → C++ (`.hpp` + `.cpp` two files)**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.hpp
```

Artifacts:

```
calculator_service.hpp
calculator_service.cpp
calculator_service_readme.md
```

**Call: C → JavaScript (`.js` + `.html` two files)**

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
Output : calculator_service.py
Mode   : service
Unit   : ComplexTestUnit
Funcs  : 28
Saved  : calculator_service.py
Saved  : calculator_service_readme.md
Done.
```

On error, it prints `Failed.` and returns a non-zero exit code. **Do not parse the wording**; depend on the exit code.

### 6.9 ⚠️ The CLI does not start the bridge

**The CLI is only responsible for generating code. It does not start the bridge, and it does not start the service.**

To actually run an end-to-end call, you must manually:

1. Compile / run the generated service (see the generated `<base>_readme.md` for build commands — the C++ one has the CMake script);
2. **Start `bridge.py` (or `bridge.exe`) separately and keep it running**;
3. Then run the call side or open the HTML test page.

### 6.10 ⚠️ The CLI delivers the `.md` alongside the code — read it

For every generated artifact, the CLI writes a `<base>_readme.md`. **Read it before you try to build anything.** The `.md` contains:

- The exact compile command for the target language.
- **The C++ CMake script**, when applicable.
- A complete test program.
- The tool reference for that artifact.
- The deployment and troubleshooting sections.

See Chapter 3 for the full contract.

---

## 7. Agent (MCP-API) Guide

### 7.1 Trigger condition

**After the GUI starts**, the tool automatically launches the MCP service on a background thread:

1. Creates a LingoFuse App (default name `code_decl_to_json_abi_mcp_api`).
2. Connects to the LingoFuse endpoint (default `ipc:agent`).
3. Registers all **22 tools** via the Beacon (default App `agent_main_app`, API `register_agent`).

So for an agent to call this tool, the following must hold:

- This tool's GUI **is running**;
- The Beacon (e.g. `pascal_agent_service`) **is running**;
- The two LingoFuse endpoints match (default `ipc:agent`).

> **Note**: the MCP service and the bridge **are two different things**.
> - The MCP service: lets an agent invoke this tool's 22 APIs (to generate code).
> - The bridge: lets every runtime call side reach the service.
>
> **They do not substitute for each other.** The agent does not need the bridge to generate code; but the moment the generated code runs, **the bridge must still be up**.

### 7.2 Tool inventory (22 tools)

Grouped into 4 functional clusters.

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
| `CodeDeclToJsonAbi_GenerateAll` | **Step 2**: run all 17 generators and cache the results into the 17 editors. Returns JSON with `unit_name` and a `files` manifest. |

`GenerateAll` may be called repeatedly; each call re-runs every generator against the current model JSON.

#### 7.2.3 Read Artifacts (Step 3, 17 read-only tools)

Grouped by target language and side:

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

All 17 readers are **pure read** — they never trigger new parsing or generation.

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
3. Invoke any of the 17 readers as needed
```

**Build-prep flow (recommended for agents that will also build the artifacts)**:

```
1. CodeDeclToJsonAbi_SetSourceCode(<source>, "c")
2. CodeDeclToJsonAbi_GenerateAll()
3. CodeDeclToJsonAbi_GetLastCppServiceHeader()      ← the .hpp
4. CodeDeclToJsonAbi_GetLastCppServiceImpl()        ← the .cpp
5. CodeDeclToJsonAbi_GetLastCppServiceReadme()      ← ⚠️ READ THIS FIRST
```

Step 5 returns the `.md`. **The `.md` is where the CMake script, the test `main.cpp`, the include directories, and the link libraries are.** An agent that intends to actually build the artifact should read the `.md` before doing anything else.

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
    "cpp_call_readme":       "Calculator_http_json_call_cpp.md"
  }
}
```

On failure:

```json
{"error":"<message>"}
```

**The 17 readers** return the **full artifact text** (plain text, not JSON) on success; on failure, they return an empty string.

### 7.5 Agent-mode notes

1. **The source language only accepts `"pascal"` or `"c"`**; any other value is rejected.
2. **Do not alternate `SetSourceCode` and `SetModelJson` within one session** — the later call completely overwrites the earlier state, and `GetSourceJson` is only meaningful for `SetSourceCode`.
3. **`GenerateAll` is idempotent**: repeated calls do not accumulate garbage; they simply rewrite the 17 caches.
4. **Order matters**: `SetSourceCode`/`SetModelJson` → `GenerateAll` → read. Reversing the order fails.
5. **The 17 readers are only valid for the "most recent successful `GenerateAll`"**: calling them before `GenerateAll` returns empty strings.
6. **The GUI must be alive**: the MCP service is attached at GUI startup; closing the GUI takes all tools offline.
7. **Generating code with an agent ≠ running the code**: to actually run the generated code, **you must still manually start the bridge and keep it running**.
8. **Point agents at the `.md` files.** After a successful `GenerateAll`, every `GetLastXxxReadme` returns a `.md`. **That `.md` is where the build commands, CMake scripts, and test programs live.** An agent that intends to build the artifact must read the `.md` first.

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
CodeDeclToJsonAbi_GetLastCppServiceReadme()      # ⚠️ the .md — has the CMake script

CodeDeclToJsonAbi_GetLastPythonServiceCode()     # the .py
CodeDeclToJsonAbi_GetLastPythonServiceReadme()   # ⚠️ the .md — has the run instructions

CodeDeclToJsonAbi_GetLastPascalServiceCode()     # the .pas
CodeDeclToJsonAbi_GetLastPascalServiceReadme()   # ⚠️ the .md — has the .lpr test program
```

The agent can then either forward the artifacts to a user or, if the environment permits, execute the build and run instructions directly from the `.md`.

---

## 8. Programmatic Interface

The tool can also be driven from another program. This section describes the **public API surface** — the same functions the CLI, GUI, and MCP provider call internally.

### 8.1 Where the API lives

| Unit | Exports |
|------|---------|
| `http_pas_abi_service_generator_tool` | `GenerateABIServicePascalCode` / `GenerateABIServicePascalReadme` |
| `http_pas_abi_call_generator_tool` | `GenerateABICallPascalCode` / `GenerateABICallPascalReadme` |
| `http_py_abi_service_generator_tool` | `GenerateABIServicePyCode` / `GenerateABIServicePyReadme` |
| `http_py_abi_call_generator_tool` | `GenerateABICallPyCode` / `GenerateABICallPyReadme` |
| `http_cpp_abi_service_generator_tool` | `GenerateABIServiceHppCode` / `GenerateABIServiceCppCode` / `GenerateABIServiceCppReadme` |
| `http_cpp_abi_call_generator_tool` | `GenerateABICallHppCode` / `GenerateABICallCppCode` / `GenerateABICallCppReadme` |
| `http_js_abi_call_generator_tool` | `GenerateABICallJsCode` / `GenerateABICallJsReadme` / `GenerateABICallJsTestHtml` |

Each code function returns a `TPascalStringList` that the caller must dispose.

### 8.2 Model building

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

### 8.3 Minimum viable embedding

```pascal
var
  Parser: tpascal_func_decl_tool;
  Model: TPascal_Func_Model;
  Code, Readme: TPascalStringList;
begin
  Parser := tpascal_func_decl_tool.CreateFrom_Pascal_Code(SourceText);
  try
    Model := TPascal_Func_Model.Create;
    try
      Model.Typ_Normalize_Func := tnf_ABI;
      Model.LoadFromParser(Parser, nil);      // nil report = silent

      Code := GenerateABIServicePascalCode(Model);
      try
        if Code <> nil then
          Code.SaveToFile('MyUnit_http_json_service_unit.pas');
      finally
        Code.Free;
      end;

      Readme := GenerateABIServicePascalReadme(Model);
      try
        if Readme <> nil then
          Readme.SaveToFile('MyUnit_http_json_service_pascal.md');
      finally
        Readme.Free;
      end;
    finally
      Model.Free;
    end;
  finally
    Parser.Free;
  end;
end;
```

### 8.4 Contract summary

| Function family | Input | Output | Notes |
|-----------------|-------|--------|-------|
| `GenerateABI*Code` / `GenerateABI*Readme` | `TPascal_Func_Model` (must be `tnf_ABI`) | `TPascalStringList` or `nil` | Caller disposes; `nil` on empty model |
| `tpascal_func_decl_tool.CreateFrom_*` | source text | parser instance | Caller disposes |
| `TPascal_Func_Model.LoadFromParser` | parser + optional report | — | Applies the six filters (Chapter 11) |

### 8.5 ⚠️ The `.md` generator is part of the API

Every `GenerateABI*Code` function has a **companion `GenerateABI*Readme` function**. If you call only the code function and not the README function, you produce a `.pas` / `.py` / `.hpp` without its build instructions. **Always call both.** The generated code and its `.md` are designed to be produced together.

### 8.6 Registering the generators with the tool itself

If you are extending the tool and want your generator to appear in the CLI, GUI, or MCP frontends, you must register it in three places (see `code_decl_to_abi_OPERATIONS.md` Chapter 3):

1. `code_decl_to_json_abi.lpr` — `uses` clause, so the unit's `initialization` runs.
2. `code_decl_to_abi_json_frm.pas` — `implementation uses`, so the GUI can call it.
3. `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` — `RegisterAPIs`, `RegisterTools`, and the appropriate `Work_*` helper, so agents can reach it.

---

## 9. Artifact Inventory

### 9.1 What each artifact is for

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
| `*_readme.md` | **Per-artifact companion documentation. The real deliverable.** Contains wire protocol, type mapping, deployment, testing, API reference, and language-specific build scripts (including the C++ CMake script). | — |

> **Note**: **The service itself does not go through the bridge.** The bridge only serves the "call → service" direction.

### 9.2 File locations

- **GUI / command line**: artifacts are written to the `<UnitName>/` subdirectory of the executable's directory.
- **Agent (MCP)**: artifacts are identical to the GUI version and are written to the same `<UnitName>/` directory; additionally, the content of the 17 editors is returned verbatim to the agent via the readers.

### 9.3 The bridge is a forwarder, and must always be running

**Every generated call side (Pascal / Python / C++ / JavaScript) talks to the backend through the bridge:**

```
caller ──HTTP POST──▶ bridge.py / bridge.exe ──LF_Call──▶ service
caller ◀─HTTP resp──  bridge.py / bridge.exe ◀─LF ret───  service
```

**When starting the bridge, specify an endpoint that matches the service, e.g.:**

```
python3 bridge.py --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

Or the compiled executable form:

```
bridge.exe --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

`--no-precheck` skips the bridge's API precheck (about 3 seconds of latency), which is more stable on first startup.

**Important rules, once more for emphasis**:

- **The bridge is a forwarder and must always be running.** Closing the bridge closes the whole path.
- The bridge may run as `bridge.py` or be compiled into `bridge.exe` — both behave identically.
- The bridge should run in its **own terminal**, in the foreground. Only after you see the HTTP listening log should you start the call side.
- After a crash or kill, restarting the bridge is enough to recover; the call side does not need to be restarted.

---

## 10. JSON Safety and Stability

Because every generated call side ultimately speaks JSON over HTTP, **JSON is the safety and stability boundary of the entire pipeline**. The following points are guaranteed by the toolchain:

1. **UTF-8 everywhere.** Requests and responses are always UTF-8; the bridge serializes with `ensure_ascii=False`, so non-ASCII payloads (Chinese, emoji, and other multi-byte content) are carried as literal UTF-8 rather than being re-encoded as `\uXXXX` escapes.

2. **NUL-terminator policy is explicit.** LingoFuse strings are NUL-terminated on the wire. The bridge **strips the trailing NUL** before forwarding to HTTP clients, and the generated call sides never emit a stray NUL into JSON. This removes the single most common class of "extra byte at the end of the JSON" bugs.

3. **The bridge is binary-safe.** If a payload cannot be parsed as JSON at all, the bridge forwards it verbatim rather than corrupting it. JSON repair (BOM removal, trailing-comma handling, encoding fallback) is applied only when JSON parsing is actually possible.

4. **Deterministic unwrapping.** The bridge wraps every service response in a stable envelope (`{"status_code": ..., "headers": ..., "body": ...}`). The generated call sides unwrap `body` and check `body.code`; code `0` returns `body.result`, any other code raises the language-appropriate exception. There is no ambiguity about where the payload lives.

5. **No silent precision loss on the wire.** Large integers are transmitted as JSON numbers by default, which is safe for Python (unbounded `int`) and for C++ (via `std::int64_t` on the service side). It is **not** safe for the JavaScript client, whose `Number` is IEEE-754 double. For `int64` / `uint64` interfaces intended for browser consumption, **the recommended pattern is to have the service return the value as a string**. The generated READMEs call this out explicitly.

6. **Stable error schema.** Every failure surfaces either as `{"error":"<message>"}` (tool-level) or as `{"code": -N, "error": "<message>"}` (service/bridge level). Call sides translate these into language-specific exceptions: `EHTTPCallError` (Pascal), `HTTPCallError` (Python / C++), `LFHttpCallError` (JavaScript).

The practical upshot: **as long as the bridge is running and the endpoint strings match on both sides, JSON payloads produced by one language's call side are consumed correctly by any other language's service side, and vice versa.**

---

## 11. Language Support: Today and Tomorrow

### 11.1 Excellent interface support for strongly-typed languages

For **Pascal, C++, and Python**, the generated interfaces are first-class, not merely stubs:

- **Pascal**: the generated service unit registers cdecl callbacks with LingoFuse directly and uses `Z.Json` for serialization. The generated call unit uses `LFHttpPost` from `lf_http_bridge_client` and exposes each API as a **typed free function**, so a Pascal caller never touches raw JSON.
- **C++**: the generated service produces a clean `.hpp`/`.cpp` pair with a namespace, typed function signatures, `LF_CDECL`-compatible callbacks, and JSON I/O helpers. The generated call side exposes a **typed free function per API** and carries a rich set of tunables (`HTTP_CALL_BASE_URL`, `HTTP_CALL_TIMEOUT_MS`, `HTTP_CALL_DEFAULT_TIMEOUT_S`, etc.). **The generated `.md` contains the CMake script and every compiler invocation you need.**
- **Python**: the generated service module exposes a `register_all_http_json_apis(app)` entry point with typed internal stubs; the generated call module exposes **one typed Python function per API** and a unified internal `_call_api()` dispatcher.

In all three languages, the type families (integer / float / string) map to the language's natural primitives, JSON serialization is handled internally, and the only thing the developer has to do is fill in the `internal_call_<Api>` stub body.

### 11.2 Excellent support for full-stack languages (JavaScript today; TypeScript and PHP on the roadmap)

- **JavaScript (available today)**: the generated `.js` is a **self-contained IIFE**, attaches itself to `window.<Unit>Api` (or `globalThis.<Unit>Api`), uses only `fetch` / `Promise` / `async-await`, and has **no third-party dependencies**. Every API is exposed as an `async` function with a JSDoc-annotated signature. A **self-contained HTML test page** is bundled alongside, so a full-stack developer can open it in a browser and exercise the interface immediately.
- **TypeScript (roadmap)**: because TypeScript is a strict superset of JavaScript and the generated JS already carries JSDoc type annotations that TS understands, a TS generator is a natural next step. It will reuse most of the JS backend and add `.d.ts`-style declaration output, unlocking a typed full-stack path.
- **PHP (roadmap)**: PHP is a separate backend that will plug into the same CLI / GUI / MCP dispatch. It will expose each API as a typed PHP function using the same HTTP/JSON wire protocol, so a PHP backend can call the same LingoFuse service that a Pascal or Python client is calling.

### 11.3 The system is designed for unbounded extension

**Today is the starting phase.** The system currently ships production-ready bindings for **three strongly-typed languages (Pascal, C++, Python)** and **one full-stack language (JavaScript)**.

**The generator backend treats each target language as a mechanical, pluggable unit.** Adding a new language is a **mechanical process**, not an architectural change. The steps are documented in `code_decl_to_abi_OPERATIONS.md` Chapter 14, and they are the same for every language:

1. Create two generator units: `<lang>_abi_service_generator_tool.pas` and `<lang>_abi_call_generator_tool.pas`.
2. Provide a type mapping table from the three ABI families (integer / float / string) to the target language's native types.
3. Register the new units in the main program, the CLI dispatcher, the GUI form, and the MCP tool provider.
4. Update the CLI's `Detect_Target_Lang` and help text.
5. Update the MCP `regCount` assertion.

**There is no architectural ceiling on the number of supported target languages.** Every language with (a) an HTTP client, (b) a JSON library, and (c) a runtime that can speak the wire protocol is a candidate.

**The user-facing contract does not change when a language is added**: the same CLI flags, the same GUI workflow, and the same MCP tools continue to work. The only difference is a new set of `<lang>_*` generator units in the backend, and a new companion `.md` per artifact.

---

## 12. Frequently Asked Questions

### Q1: Why is a function I passed in missing from the generated result?

Check three things:

1. **Is the function top-level** (in the `interface` section, not nested inside a `class` / `record`)? Nested declarations are skipped.
2. **Are its parameters and return type in the supported set?** Only the integer family, float family, and string family are accepted. `Boolean`, `Variant`, arrays, records, classes, interfaces, enums, sets, pointers, `Currency`, `TDateTime` are not supported.
3. **Is the function name non-empty** (`Name.Len > 0`)?

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

You get the result of the **normalizer running automatically**. Both `GetSourceJson` and `GetModelJson` compute LV0/LV1 on the fly when `SetSourceCode` succeeds, so you can inspect them.

### Q9: Does calling `GenerateAll` multiple times pollute the result?

No. Every `GenerateAll` re-runs all 17 generators from scratch, overwriting the old caches.

### Q10: Can I generate only one target language?

**The current version does not support that.** `GenerateAll` produces all 17 at once. If you only want one of them, pick it out of the 17 readers; the 17 files written to disk can simply be ignored.

### Q11: Running the generated call side or HTML test page gives `Network error` / `Failed to fetch` / `Connection refused`.

**99% of the time, the bridge is not running (or was up and got closed).**

Troubleshooting steps:

1. **Confirm the bridge is actually running**: check its terminal for live log output.
2. **Confirm the bridge's endpoint matches the service**: both sides must be the same string, e.g. `ipc:calc_http_json`.
3. **Confirm the bridge's port matches the caller's expectation**: default `8081`. The caller's `HTTP_CALL_BASE_URL` or the HTML page's Base URL must be `http://127.0.0.1:8081/<unit>`.
4. **Restart the bridge**: sometimes the bridge crashed but its terminal is still open, so it looks like it is "still up". A restart is the quickest fix.

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

### Q13: What about TypeScript and PHP?

TypeScript and PHP are **on the roadmap** as part of the full-stack-language expansion. Until their generators land:

- For TypeScript projects, use the JavaScript output — its JSDoc type annotations are already TS-friendly.
- For PHP projects, treat it as a future addition; the wire protocol it will use is unchanged, so a PHP client can, in the meantime, be hand-written against the same HTTP/JSON contract described in the generated READMEs.

The architecture is intentionally unbounded: **as new target-language backends are added, they slot into the same CLI, GUI, and MCP dispatchers. There is no ceiling on how many programming languages the generator can eventually target.**

### Q14: Where do I find the CMake script for the generated C++?

**In the generated `<Unit>_http_json_service_cpp.md` (or `_call_cpp.md`).** The `.md` companion is where all language-specific build material lives — CMake scripts, compiler invocations, include paths, link libraries, and a full test `main.cpp`. See Chapter 3 for the full contract.

### Q15: Where do I find the test program for the generated Pascal?

**In the generated `<Unit>_http_json_service_pascal.md` (or `_call_pascal.md`).** It contains a complete `.lpr` file and the exact `fpc -Fu<...>` command line to build it.

### Q16: How do I build the generated Python service?

**Read the `<Unit>_http_json_service_python.md`.** It tells you which `PYTHONPATH` or `pip install` is needed, and it relies on the generated module's own `if __name__ == "__main__":` block as the test program — no separate script is required.

### Q17: Why does the guide keep telling me to read the `.md`?

Because **the `.md` is the real deliverable.** The code file is the skeleton; the `.md` is the manual that tells you how to build, test, and deploy that skeleton. The code and the `.md` are generated from the same model in the same pass, so they never drift apart. Whenever you are about to compile, run, or debug a generated artifact, **the answer is in its `.md`, not in this user guide.** This guide explains how to *drive the tool*; the `.md` explains how to *use the artifact*.

---

## Appendix: One-Sentence Summary of the Usage Modes

- **GUI**: five tabs, click left to right; when something goes wrong, step back and fix it. Open the `.md` sub-tab before trying to build.
- **CLI**: `code_decl_to_json_abi [--call] input output`; extension picks the language, exit code tells success or failure. Read `<base>_readme.md` before building.
- **Agent**: `SetSourceCode` (or `SetModelJson`) → `GenerateAll` → invoke the 17 readers as needed. Read the `readme` fields for build instructions.
- **Programmatic**: call the `GenerateABI*Code` and `GenerateABI*Readme` functions directly; always generate both.

**The one rule you must never forget at runtime**: **the bridge (`bridge.py` or `bridge.exe`) is a forwarder and must always be running.**

**The one rule you must never forget after generation**: **read the generated `.md` files. The test code, the build scripts (including the C++ CMake script), and the interface reference all live there.**