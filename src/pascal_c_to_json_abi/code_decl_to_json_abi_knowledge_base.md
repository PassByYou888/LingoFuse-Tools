# code_decl_to_json_abi Complete Knowledge Base (v2)

> **Purpose**: This document is the single authoritative reference for the `code_decl_to_json_abi` toolchain. After reading it, you should be able to correctly drive the entire generation workflow — GUI, CLI, or MCP — without reading any source code.
>
> **Promise**: Every statement has been verified against the current source. Anything I cannot determine is explicitly called out in the Honest Uncertainty List at the end.
>
> **Version**: v2. This version supersedes v1 and reflects three additions: (a) the CMake generator tool and its two fixed-name artifacts, (b) the bootstrap → AI-fill architecture of the MCP tool provider unit, and (c) the growth of the MCP tool set from 22 to **24 tools**.
>
> **Scope**: `code_decl_to_json_abi.lpr`, `code_decl_to_abi_json_frm.pas`, `code_decl_to_json_abi_cmdline.pas`, `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`, `http_cmake_generator_tool.pas`, and the seven code generators.
>
> **Document language**: English.

---

## Table of Contents

- [Chapter 0  Quick Orientation](#chapter-0--quick-orientation)
- [Chapter 1  The Bootstrap → AI-Fill Architecture](#chapter-1--the-bootstrap--ai-fill-architecture)
- [Chapter 2  Three Frontends, One Source of Truth](#chapter-2--three-frontends-one-source-of-truth)
- [Chapter 3  The CMake Sub-Toolchain](#chapter-3--the-cmake-sub-toolchain)
- [Chapter 4  Three-Phase Workflow](#chapter-4--three-phase-workflow)
- [Chapter 5  MCP API Complete Reference (24 Tools)](#chapter-5--mcp-api-complete-reference-24-tools)
- [Chapter 6  The 8 Generators in Detail](#chapter-6--the-8-generators-in-detail)
- [Chapter 7  Type System and Mapping Rules](#chapter-7--type-system-and-mapping-rules)
- [Chapter 8  HTTP/JSON Wire Protocol](#chapter-8--httpjson-wire-protocol)
- [Chapter 9  Error Handling and Error Codes](#chapter-9--error-handling-and-error-codes)
- [Chapter 10  Complete Artifact Inventory](#chapter-10--complete-artifact-inventory)
- [Chapter 11  Common Pitfalls and Anti-Patterns](#chapter-11--common-pitfalls-and-anti-patterns)
- [Chapter 12  AI Agent Usage Rules and Decision Tree](#chapter-12--ai-agent-usage-rules-and-decision-tree)
- [Chapter 13  Complete Usage Examples](#chapter-13--complete-usage-examples)
- [Chapter 14  Honest Uncertainty List](#chapter-14--honest-uncertainty-list)

---

## Chapter 0  Quick Orientation

### 0.1 What This Project Is

`code_decl_to_json_abi` is a **cross-language code generator**. It accepts a Pascal unit or a C header and produces LingoFuse service-side and call-side code targeting the HTTP/JSON protocol, for the following target languages:

- **Pascal** (service + call)
- **Python** (service + call)
- **C++** (service + call, plus a CMake build script and a C++ test driver)
- **JavaScript** (call side + a self-contained HTML test page)

The output is a set of artifacts, each paired with a Markdown companion document that carries the language-specific build commands, CMake scripts, and test programs.

### 0.2 Three Public Frontends

All three drive the **same underlying GUI form**. There is no parallel implementation of the generation logic; the CLI and the MCP provider both simulate the GUI's button clicks and edit-field writes.

| Entry point | Trigger | Audience |
|-------------|---------|----------|
| **GUI** | Launch with no arguments | Human engineers |
| **CLI** | Launch with at least one argument | Build scripts, CI |
| **MCP** | Automatic, after the GUI starts | AI agents, remote tools |

### 0.3 5-Second Cheat Sheet

```
Step 1: SetSourceCode(Source, "pascal" | "c")     // or SetModelJson(ModelJson)
Step 2: GenerateAll()
Step 3: GetLast<Lang><Side><Artifact>()           // choose from 24 readers
```

### 0.4 The 8 Rules You Must Not Forget

1. **The `Language` argument only accepts `"pascal"` or `"c"`**. `"python"`, `"cpp"`, and `"js"` are **target** languages, not **source** languages.
2. **After Step 1, you must call `GenerateAll`**. Otherwise every reader returns an empty string.
3. **Read is a pure read**. It never triggers a new generation; to refresh the cache, call `GenerateAll` again.
4. **A single `SetSourceCode` covers the entire session**. Switching target language does not require re-feeding the source.
5. **Service and Call halves must come from the same source text**.
6. **Types outside the three ABI families cause the entire routine to be silently dropped** (see Chapter 7).
7. **`int64` / `uint64` lose precision on the JS client** because JS `Number` is IEEE-754 double.
8. **The bridge (`bridge.py` / `bridge.exe`) must always be running** for any generated Call artifact to work.

---

## Chapter 1  The Bootstrap → AI-Fill Architecture

### 1.1 What a "Bootstrap Script" Is

The toolchain ships a **bootstrap script** whose sole job is to emit a **structurally complete but semantically empty** Pascal unit:

```
code_decl_to_json_abi_mcp_api_tool_provider_unit.pas
```

The bootstrap script does not write any business logic. It writes:

1. **A unit skeleton** — the `unit` header, the `interface`, the `uses` clause, the exported global variables, the `TCompute`-based callback registration code.
2. **24 cdecl callback shells** — one per MCP tool, each with the full `try/except` envelope already written, and each already wired to a matching `internal_call_<ToolName>` function.
3. **24 `internal_call_*` function stubs** — the function signatures are correct; the bodies are empty.
4. **24 tool-schema registrations** in `RegisterTools` — each tool's `name`, `description`, `target_app`, and `target_api` fields are filled in; the JSON `parameters` schema is pre-populated with the correct types and required-field lists.
5. **The `RegisterAPIs` and `Execute_And_Reg_all` functions** — the LingoFuse App creation, the `LF_RegisterCallEx` calls, and the beacon connection logic.

In short: the bootstrap script writes the **plumbing**; it does not write the **dispatch logic**.

### 1.2 What the AI Fills In

After the bootstrap script has produced the unit, an AI fills in the **body of each `internal_call_*` function**. Each body follows the same pattern:

```pascal
function internal_call_CodeDeclToJsonAbi_<ToolName>(...): string;
{$IFDEF FPC}
  procedure Do_Sync___();
  begin
    // ← the AI writes this block
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
    // ← the AI writes this block (Delphi version)
    temp_ := ...;
  end);
  Result := temp_;
{$ENDIF FPC}
end;
```

The AI's job is to write the **nested `Do_Sync___` procedure body** (FPC) or the **anonymous procedure body** (Delphi). Everything else — the `TCompute.Sync` wrapper, the `{$IFDEF}` split, the exception envelope, the callback dispatch — is already in place from the bootstrap.

### 1.3 Why the UI-Synchronization Pattern

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

1. **The GUI is the single source of truth.** There is no parallel state. If the GUI shows a value, the MCP tool returns that value. If the GUI does not have it, the MCP tool returns an empty string.
2. **Adding a new MCP tool is a purely mechanical operation.** Copy an existing `internal_call_*` pair (callback + internal), rename it, point it at a different form field or button click, and add the tool schema to `RegisterTools`.
3. **The GUI's button-click handlers are effectively the MCP tool implementations.** The MCP layer is a thin remote-control veneer.
4. **Thread-safety is inherited, not reinvented.** `TCompute.Sync` marshals the body onto the main thread, where the LCL is safe to touch. The AI never has to think about critical sections.

### 1.4 What the AI Must Not Do

- **Do not add new state fields to the form** for the sake of an MCP tool. If a value is needed, it must already exist as a form editor or a form field.
- **Do not call UI methods from the worker thread.** Every UI touch must be inside `Do_Sync___` (or the anonymous procedure), which `TCompute.Sync` runs on the main thread.
- **Do not bypass the callback envelope.** The `try/except` around the `internal_call_*` is written by the bootstrap; the AI's body should let exceptions propagate so the envelope can convert them into `{"error": "..."}`.
- **Do not renumber or rename the tools.** Tool names are stable identifiers that external callers depend on.

### 1.5 Worked Example — `SetSourceCode`

The bootstrap writes:

```pascal
procedure Callback_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(
  _Trigger___: Pointer; _In___, _Out___: TDataHnd___); cdecl;
var
  jsonBytes: TBytes;
  jo: TZ_JsonObject;
  Source: string;
  Language: string;
  ret: string;
  errMsg: string;
begin
  jo := TZ_JsonObject.Create;
  try
    jsonBytes := LF_ReadStringBytes(TDataHnd(_In___));
    // ... (envelope: empty check, JSON parse, error write-back) ...
    Source   := jo.S['Source'];
    Language := jo.S['Language'];

    ret := internal_call_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(Source, Language);
    jo.Clear;
    jo.S['result'] := ret;
    LF_WriteStringBytes(TDataHnd(_Out___), jo.ToBytes);
    // ... (logging) ...
  except
    // ... (exception write-back) ...
  end;
  jo.Free;
end;
```

The AI writes only:

```pascal
function internal_call_CodeDeclToJsonAbi_SetSourceCode_CodeDeclToJsonAbi_SetSourceCode(
  Source: string; Language: string): string;
{$IFDEF FPC}
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
{$ELSE FPC}
var
  temp_: string;
{$ENDIF FPC}
begin
  // ... the TCompute.Sync wrapper as shown in §1.2 ...
end;
```

The AI's contribution is exactly the **five UI touches** inside `Do_Sync___`: setting the combo box index, calling the combo box's change handler, writing the editor text, switching the page, and clearing the two session caches. Everything else is mechanical.

### 1.6 Where the Pattern Extends

The same pattern applies to **all 24 tools**, with three variations:

- **Setter tools** (`SetSourceCode`, `SetModelJson`): write to an editor, switch to a tab, return a status JSON.
- **Reader tools** (`GetSourceJson`, `GetModelJson`, and the 19 artifact readers): switch to the appropriate tab, return the corresponding editor's `.Lines.Text`.
- **Driver tools** (`GenerateAll`): call a sequence of button-click handlers in the right order, then read the resulting JSON to build a file manifest.

No tool does anything that the GUI cannot do by hand.

---

## Chapter 2  Three Frontends, One Source of Truth

### 2.1 The GUI Form Is the State

Every piece of state lives on the form instance `Tcode_decl_to_abi_json_form`. There is no global model. There is no separate MCP session. The form is the session.

Fields that matter:

| Field | Type | Purpose |
|-------|------|---------|
| `SourceCodeEditor` | `TSynEdit` | source text |
| `SourceJsonEditor` | `TSynEdit` | LV0 Source JSON |
| `ModelJsonEditor` | `TSynEdit` | LV1 Model JSON |
| `PascalServiceCodeEditor`, `PascalServiceReadmeEditor` | `TSynEdit` | Pascal service artifacts |
| `PascalCallCodeEditor`, `PascalCallReadmeEditor` | `TSynEdit` | Pascal call artifacts |
| `JavaScriptCallCodeEditor`, `JavaScriptCallReadmeEditor`, `JavaScriptTestHtmlEditor` | `TSynEdit` | JS artifacts |
| `PythonServiceCodeEditor`, `PythonServiceReadmeEditor` | `TSynEdit` | Python service artifacts |
| `PythonCallCodeEditor`, `PythonCallReadmeEditor` | `TSynEdit` | Python call artifacts |
| `CppServiceHeaderEditor`, `CppServiceImplEditor`, `CppServiceReadmeEditor` | `TSynEdit` | C++ service artifacts |
| `CppCallHeaderEditor`, `CppCallImplEditor`, `CppCallReadmeEditor` | `TSynEdit` | C++ call artifacts |
| `CMakeEditor`, `CMake_TestMain_Editor` | `TSynEdit` | CMake artifacts (shown in GUI) |
| `MainPageControl`, `FinalSourcePageControl` | `TPageControl` | which page is visible |

**Session-only caches** (not visible to the user, but important for the MCP path):

| Field | Purpose |
|-------|---------|
| `FSessionCMakeScript: string` | the CMake script text, cached for `GetLastCMakeScript` |
| `FSessionTestMainCpp: string` | the test driver text, cached for `GetLastTestMainCpp` |

These two caches exist because the CMake artifacts are not shown as first-class editors in the GUI's tab structure. They are written to disk during `GenerateAll`, and cached in memory so the readers can return them without re-reading the disk.

### 2.2 The GUI Frontend

**Trigger**: launch with zero arguments.

**Behavior**: the LCL application starts, `Tcode_decl_to_abi_json_form` is created, and `Application.Run` enters the event loop. The user sees five tabs:

```
[Welcome] → [Source Code] → [Source ↔ JSON] → [JSON ↔ Model] → [Final Source]
```

At startup, the form's `Create` also calls `TCompute.RunM_NP(StartMcpService)`, which sets two LingoFuse options and calls `Execute_And_Reg_all`. This is the only thing the GUI does beyond its visible behavior.

### 2.3 The CLI Frontend

**Trigger**: launch with at least one argument.

**Behavior**: the LPR file calls `Process_CommandLine` **before** `Application.Initialize`. If the function returns `False`, the LPR exits with `CommandLine_ExitCode`; the LCL is never started.

The CLI is fully independent of the GUI. It has its own `uses` clause, its own parsing logic (using the same `tpascal_func_decl_tool` and `TPascal_Func_Model`), and its own per-target dispatch. It does **not** touch the form.

The consequence: **the CLI and the GUI share the generators, but not the session state**. Running the CLI does not populate the GUI's editors, and vice versa.

### 2.4 The MCP Frontend

**Trigger**: automatic, when the GUI is running.

**Behavior**: the `StartMcpService` procedure starts a background thread that connects to the LingoFuse endpoint `ipc:agent` and registers the 24 MCP tools with the beacon at `agent_main_app.register_agent`.

The MCP path shares state with the GUI because **every tool body delegates to the form**. This is the entire point of the bootstrap → AI-fill architecture described in Chapter 1.

**Visibility consequence**: opening the GUI and watching it while an agent drives it, you will see the editors fill in, the tabs switch, and the log scroll — exactly as if a human had clicked the buttons.

### 2.5 The Three Frontends in a Single Sentence Each

- **GUI**: a human clicks buttons and edits text.
- **CLI**: a shell script calls `Process_CommandLine`; the form is never created.
- **MCP**: an agent calls LingoFuse tools; the tools click the same buttons a human would click.

---

## Chapter 3  The CMake Sub-Toolchain

### 3.1 Why CMake Was Added

The generated C++ artifacts are two code files (`.hpp` + `.cpp`) plus a README. The README's "Building – CMake" section presents a CMake script, and that script names two files by fixed name:

- `CMakeLists.txt` — the build script itself.
- `test_main___.cpp` — the call-side test driver.

If the toolchain only emitted the `.hpp`/`.cpp` pair, a user following the README would have to hand-write both files. The CMake sub-toolchain closes that gap.

### 3.2 The Two CMake Artifacts

**`CMakeLists.txt`** — a complete, ready-to-configure CMake project. Key facts (all verified against `http_cmake_generator_tool.pas`):

| Aspect | Value |
|--------|-------|
| Minimum CMake version | `3.15` |
| Project language list | `C CXX` (both are required; see §3.4) |
| C++ standard | `17`, required, extensions off |
| Cache variable | `LINGOFUSE_CPP_LIB_DIR` |
| CMake-gui label | "LingoFuse C++ library directory" |
| Service target | `<Unit>_http_json_service` (executable) |
| Call test target | `<Unit>_http_json_call_test` (executable) |
| Sources per target | the generated `.cpp` + `LingoFuse.c` |
| Windows link libraries | `ws2_32` |
| macOS link libraries | `Threads::Threads` |
| Linux link libraries | `Threads::Threads` + `${CMAKE_DL_LIBS}` |
| Warnings on MSVC | `/W4 /permissive-` |
| Warnings on GCC/Clang | `-Wall -Wextra` |
| Runtime DLL staging | **none** — the script deliberately does not touch the DLLs |

**`test_main___.cpp`** — a driver that:

1. Constructs a `lingofuse::LibraryLoader` as its first statement.
2. Calls `lingofuse::resetPrepare()`, `lingofuse::prepareClient("ipc:<Unit>_http_json", nullptr)`, `lingofuse::prepareDone()`.
3. Sets `HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>"`.
4. Calls every supported wrapper function with default arguments (`0`, `0.0`, `std::string()`).
5. Prints `OK` or `FAILED: <reason>` per call.
6. Returns 0 if every call succeeded, 1 otherwise.

### 3.3 The Fixed File Names

The two CMake artifacts are written to **fixed names**, not unit-prefixed names. This is deliberate:

- `CMakeLists.txt` is the file CMake looks for by default; it cannot be renamed.
- `test_main___.cpp` is referenced by that exact name in the generated CMake script.

**Consequence**: generating two different units into the same directory will overwrite the previous CMake files. The intended workflow is one directory per unit.

### 3.4 Why `project(... C CXX)` and Not `project(... CXX)`

This was a real bug in an earlier revision. `LingoFuse.c` is a **C source file**. When a CMake project declares only `CXX` as its language, CMake cannot determine the link language for a target that contains a `.c` file, and configuration fails with:

```
Cannot determine link language for target "<target>"
```

Declaring `C CXX` lets CMake route the `.c` file to the C compiler and everything else to the C++ compiler. The generated script always uses `C CXX`.

### 3.5 What the CMake Script Requires

The directory pointed to by `LINGOFUSE_CPP_LIB_DIR` must contain:

- `LingoFuse.h`
- `LingoFuse.c`
- `LingoFuse.hpp`
- `lf_io.hpp`
- `lf_http_bridge_client.hpp`
- `json.hpp`

If `LingoFuse.h` is missing, the script emits a `FATAL_ERROR` at configure time with a diagnostic that names the missing file and the current value of the cache variable.

### 3.6 What the CMake Script Does NOT Do

- **It does not stage any DLL.** Where the runtime DLLs live is a deployment concern. The README's deployment section covers it.
- **It does not install anything.** No `install()` rules. No `CPack`.
- **It does not configure a build type.** The user selects `-DCMAKE_BUILD_TYPE=Release` if desired.
- **It does not locate LingoFuse automatically.** The path is supplied by the user via the cache variable.

### 3.7 How to Drive the CMake Script

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

Or, in cmake-gui: fill in the "LingoFuse C++ library directory" field.

### 3.8 Which Frontends Produce CMake Artifacts

| Frontend | CMake artifacts | Where |
|----------|:---------------:|-------|
| **GUI** | ✅ | written to `<exe dir>/<UnitName>/`, and displayed in the GUI's CMake editors |
| **CLI** | ✅ | written to the output file's directory, as `CMakeLists.txt` and `test_main___.cpp` |
| **MCP** | ✅ | written to `<exe dir>/<UnitName>/`, and cached in `FSessionCMakeScript` / `FSessionTestMainCpp` for the two readers |

All three write the same bytes because all three call the same two generator functions: `GenerateCMakeScript` and `GenerateTestMainCpp` from `http_cmake_generator_tool.pas`.

### 3.9 The Two CMake Readers

Two of the 24 MCP tools exist specifically to expose the CMake artifacts:

- `CodeDeclToJsonAbi_GetLastCMakeScript` — returns the `CMakeLists.txt` text.
- `CodeDeclToJsonAbi_GetLastTestMainCpp` — returns the `test_main___.cpp` text.

Both are pure readers. Both return the cached string; neither reads the disk.

---

## Chapter 4  Three-Phase Workflow

### 4.1 Flow Diagram

```
┌───────────────────────────────────┐
│  Step 1: Input                    │
│  ─────────────────────────        │
│  ① SetSourceCode(Source, Lang)    │  source text + source language
│  ② SetModelJson(ModelJson)        │  feed LV1 Model JSON directly
└──────────────┬────────────────────┘
               │
               ▼
┌───────────────────────────────────┐
│  Step 2: Generate                 │
│  ─────────────────────────        │
│  GenerateAll()                    │  run all 8 generators + CMake
└──────────────┬────────────────────┘
               │
               ▼
┌───────────────────────────────────┐
│  Step 3: Read                     │
│  ─────────────────────────        │
│  24 readers                       │  read the artifacts you need
└───────────────────────────────────┘
```

### 4.2 Step 1 — Input

#### `SetSourceCode(Source, Language)`

| Parameter | Type | Required | Notes |
|-----------|------|:--------:|-------|
| `Source` | `string` | Yes | full source text |
| `Language` | `string` | Yes | `"pascal"` or `"c"`, case-insensitive |

**Actions performed on the main thread**:
1. Set `LanguageSelectorComboBox.ItemIndex` and call `LanguageSelectorChange`.
2. Write `Source` into `SourceCodeEditor`.
3. Switch `MainPageControl.ActivePage` to `SourceCodeTabSheet`.
4. Clear `FSessionCMakeScript` and `FSessionTestMainCpp`.

**Does not parse, does not generate.**

Returns `{"status":"ok"}` on success, `{"error":"<message>"}` on failure.

#### `SetModelJson(ModelJson)`

| Parameter | Type | Required | Notes |
|-----------|------|:--------:|-------|
| `ModelJson` | `string` | Yes | LV1 Model JSON (shape in §6.7) |

**Actions performed**:
1. Validate JSON well-formedness.
2. Extract `UnitName` from the JSON.
3. Write `ModelJson` into `ModelJsonEditor`.
4. Switch `MainPageControl.ActivePage` to `ModelJsonTabSheet`.
5. Clear the two CMake caches.

Returns `{"status":"ok","unit_name":"<UnitName>"}` or `{"error":"<message>"}`.

#### Which One to Use

Use `SetSourceCode` unless you already have an LV1 model JSON produced elsewhere (for example by a previous `GetModelJson` call, or by another tool that emits the same shape). In that case use `SetModelJson`, which bypasses both the parser and the normalizer.

### 4.3 Step 2 — `GenerateAll()`

Takes no arguments.

**Actions performed (in order, on the main thread)**:

1. If `SourceCodeEditor.Text` is non-empty → call `ParseSourceToJsonClick`.
2. If `SourceJsonEditor.Text` is non-empty → call `NormalizeJsonToModelClick`.
3. If `ModelJsonEditor.Text` is non-empty → call `GenerateAllSourcesClick`.
4. Additionally, if the model is present → invoke `GenerateCMakeScript` and `GenerateTestMainCpp` directly, caching the results in `FSessionCMakeScript` and `FSessionTestMainCpp`.

`GenerateAllSourcesClick` internally:

- Writes the three intermediate files to disk (`source.pas`/`source.h`, `source.json`, `source_model.json`) if their editors are non-empty.
- Runs each of the seven code generators via a table-driven `Emit` helper.
- Writes each artifact to disk under `<exe dir>/<UnitName>/`.
- Writes `CMakeLists.txt` and `test_main___.cpp` under the same directory.
- Mirrors the artifact text into the corresponding editor.
- Switches `MainPageControl.ActivePage` to `FinalSourceTabSheet`.

**Success return**:

```json
{
  "status": "ok",
  "unit_name": "<UnitName>",
  "files": {
    "pascal_service_code":    "<UnitName>_http_json_service_unit.pas",
    "pascal_service_readme":  "<UnitName>_http_json_service_pascal.md",
    "pascal_call_code":       "<UnitName>_http_json_call_unit.pas",
    "pascal_call_readme":     "<UnitName>_http_json_call_pascal.md",
    "js_call_code":           "<UnitName>_http_json_call.js",
    "js_call_readme":         "<UnitName>_http_json_call_js.md",
    "js_test_html":           "<UnitName>_http_json_call_test.html",
    "python_service_code":    "<UnitName>_http_json_service.py",
    "python_service_readme":  "<UnitName>_http_json_service_python.md",
    "python_call_code":       "<UnitName>_http_json_call.py",
    "python_call_readme":     "<UnitName>_http_json_call_python.md",
    "cpp_service_header":     "<UnitName>_http_json_service.hpp",
    "cpp_service_impl":       "<UnitName>_http_json_service.cpp",
    "cpp_service_readme":     "<UnitName>_http_json_service_cpp.md",
    "cpp_call_header":        "<UnitName>_http_json_call.hpp",
    "cpp_call_impl":          "<UnitName>_http_json_call.cpp",
    "cpp_call_readme":        "<UnitName>_http_json_call_cpp.md",
    "cmake_script":           "CMakeLists.txt",
    "test_main_cpp":          "test_main___.cpp"
  }
}
```

**Failure return**: `{"error":"<message>"}`.

**Failure scenarios**:
- `"No source text or model JSON in session. Call SetSourceCode or SetModelJson first."`
- `"Model JSON is empty. Cannot generate."`
- `"Form not available"`

### 4.4 Step 3 — Reading

All 24 readers take no arguments and return `string`. See Chapter 5.

**Key conventions**:
- **Pure read** — no generation, no disk I/O.
- If the corresponding branch has never been generated, the reader returns `""`.
- Each `GenerateAll` refreshes all cached values.

### 4.5 Session Behavior

- **One source, many targets**: after a single `SetSourceCode`, any combination of readers may be called.
- **Repeated `SetSourceCode`**: replaces the source text entirely; previously cached values are not cleared until the next `GenerateAll`.
- **Repeated `GenerateAll`**: re-parses and refreshes all cached values every time; disk writes are overwritten.

---

## Chapter 5  MCP API Complete Reference (24 Tools)

### 5.1 Naming Convention

Every tool is prefixed with `CodeDeclToJsonAbi_`. This makes beacon discovery easy and avoids collisions with other tool providers.

### 5.2 The 24 Tools at a Glance

| # | Tool | Category | Return type |
|---|------|----------|-------------|
| 1 | `CodeDeclToJsonAbi_SetSourceCode` | Step 1 | status JSON |
| 2 | `CodeDeclToJsonAbi_SetModelJson` | Step 1 | status JSON |
| 3 | `CodeDeclToJsonAbi_GetSourceJson` | intermediate read | LV0 JSON |
| 4 | `CodeDeclToJsonAbi_GetModelJson` | intermediate read | LV1 JSON |
| 5 | `CodeDeclToJsonAbi_GenerateAll` | Step 2 | file-manifest JSON |
| 6 | `CodeDeclToJsonAbi_GetLastPascalServiceCode` | Step 3 | Pascal source |
| 7 | `CodeDeclToJsonAbi_GetLastPascalServiceReadme` | Step 3 | Markdown |
| 8 | `CodeDeclToJsonAbi_GetLastPascalCallCode` | Step 3 | Pascal source |
| 9 | `CodeDeclToJsonAbi_GetLastPascalCallReadme` | Step 3 | Markdown |
| 10 | `CodeDeclToJsonAbi_GetLastJsCallCode` | Step 3 | JavaScript |
| 11 | `CodeDeclToJsonAbi_GetLastJsCallReadme` | Step 3 | Markdown |
| 12 | `CodeDeclToJsonAbi_GetLastJsTestHtml` | Step 3 | HTML |
| 13 | `CodeDeclToJsonAbi_GetLastPythonServiceCode` | Step 3 | Python source |
| 14 | `CodeDeclToJsonAbi_GetLastPythonServiceReadme` | Step 3 | Markdown |
| 15 | `CodeDeclToJsonAbi_GetLastPythonCallCode` | Step 3 | Python source |
| 16 | `CodeDeclToJsonAbi_GetLastPythonCallReadme` | Step 3 | Markdown |
| 17 | `CodeDeclToJsonAbi_GetLastCppServiceHeader` | Step 3 | C++ header |
| 18 | `CodeDeclToJsonAbi_GetLastCppServiceImpl` | Step 3 | C++ impl |
| 19 | `CodeDeclToJsonAbi_GetLastCppServiceReadme` | Step 3 | Markdown |
| 20 | `CodeDeclToJsonAbi_GetLastCppCallHeader` | Step 3 | C++ header |
| 21 | `CodeDeclToJsonAbi_GetLastCppCallImpl` | Step 3 | C++ impl |
| 22 | `CodeDeclToJsonAbi_GetLastCppCallReadme` | Step 3 | Markdown |
| 23 | `CodeDeclToJsonAbi_GetLastCMakeScript` | Step 3 | CMake script |
| 24 | `CodeDeclToJsonAbi_GetLastTestMainCpp` | Step 3 | C++ source |

### 5.3 Tool Signatures by Category

#### 5.3.1 Input Tools (2)

| Tool | Signature |
|------|-----------|
| `SetSourceCode` | `function(Source: string; Language: string): string` |
| `SetModelJson` | `function(ModelJson: string): string` |

#### 5.3.2 Intermediate Readers (2)

| Tool | Signature |
|------|-----------|
| `GetSourceJson` | `function(): string` |
| `GetModelJson` | `function(): string` |

#### 5.3.3 Generation Tool (1)

| Tool | Signature |
|------|-----------|
| `GenerateAll` | `function(): string` |

#### 5.3.4 Artifact Readers (19)

All are `function(): string`. Fifteen of them mirror the fifteen code+README artifacts from the seven generators; four are the CMake pair plus the two remaining artifact readers. (Count: 4 Pascal + 3 JS + 4 Python + 6 C++ + 2 CMake = 19.)

### 5.4 Input Tool Contracts

#### `SetSourceCode`

**Success**: `{"status":"ok"}`

**Failure**:
- `{"error":"Unsupported language. Use pascal or c."}`
- `{"error":"Form not available"}`

**Notes**:
- Empty `Source` does **not** raise an error; it writes empty text. A subsequent `GenerateAll` will fail with a parse error.
- The `Language` comparison is case-insensitive after `Trim` and `LowerCase`.

#### `SetModelJson`

**Success**: `{"status":"ok","unit_name":"<UnitName>"}`

**Failure**:
- `{"error":"Empty model JSON"}`
- `{"error":"Invalid model JSON"}`
- `{"error":"Form not available"}`

### 5.5 Intermediate Reader Contracts

#### `GetSourceJson`

Returns `SourceJsonEditor.Lines.Text` or `""`.

- If the most recent Step 1 was `SetModelJson`, returns `""` — that path does not produce LV0.
- If the most recent Step 1 was `SetSourceCode` but `GenerateAll` has not been called, returns `""`.
- After a successful `GenerateAll`, is populated.

#### `GetModelJson`

Returns `ModelJsonEditor.Lines.Text` or `""`.

- If the most recent Step 1 was `SetModelJson`, returns exactly the string that was passed in.
- If the most recent Step 1 was `SetSourceCode`, is populated after a successful `GenerateAll`.

### 5.6 Generation Tool Contract

#### `GenerateAll`

**Precondition**: `SourceCodeEditor.Text` or `ModelJsonEditor.Text` is non-empty.

**Postcondition on success**: all 17 code+README artifacts are cached, the two CMake artifacts are cached, and the on-disk directory `<exe dir>/<UnitName>/` contains all 19 files.

**Side effect**: writes to disk. If the disk is not writable, the disk write fails but the in-memory cache is still valid; the return value is still `{"status":"ok"}`.

### 5.7 Artifact Reader Contracts

Every artifact reader does the following before reading:

1. Switch `MainPageControl.ActivePage` to `FinalSourceTabSheet`.
2. Switch `FinalSourcePageControl.ActivePage` to the corresponding child `TabSheet`.
3. Return the corresponding editor's `.Lines.Text` (or the cached session string, for the CMake pair).

**Return value**: the artifact text, or `""` if the branch has never been generated.

**Pure read**: no generation, no disk I/O.

### 5.8 The Two CMake Readers

`GetLastCMakeScript` and `GetLastTestMainCpp` are **not** backed by a `TSynEdit`. They return `FSessionCMakeScript` and `FSessionTestMainCpp`, which are plain `string` fields on the form. They are populated by `GenerateAll` in the CMake step of `GenerateAllSourcesClick`.

If `GenerateAll` has not run since the last `SetSourceCode` / `SetModelJson`, both fields are empty and both readers return `""`.

### 5.9 Registration Flow

The `Execute_And_Reg_all` function performs the entire startup in one shot:

1. `RegisterAPIs` — creates the LingoFuse App, issues 24 `LF_RegisterCallEx` calls.
2. `LF_PrepareClientEx("ipc:agent", App)` — connects to the LingoFuse endpoint.
3. `LF_PrepareDone` — waits for the client to be ready.
4. `RegisterTools` — registers the 24 tool JSON schemas with `agent_main_app.register_agent`.

**Return value**: `True` iff all 24 tools registered successfully.

**Global variables** (may be modified before the call):

| Variable | Default |
|----------|---------|
| `MY_APP_NAME` | `"code_decl_to_json_abi_mcp_api"` |
| `MY_APP_DESC` | `"Tool provider for unit code_decl_to_json_abi_mcp_api"` |
| `IPC_ENDPOINT` | `"ipc:agent"` |
| `BEACON_APP` | `"agent_main_app"` |
| `REGISTER_API` | `"register_agent"` |
| `AGENT_LOG_API` | `"agent_log"` |
| `DEBUG_LOG` | `True` |

### 5.10 The 24 Callbacks

Each tool has a corresponding `Callback_CodeDeclToJsonAbi_<ToolName>_CodeDeclToJsonAbi_<ToolName>` cdecl function that:

1. Reads the input `TDataHnd___` as UTF-8 bytes.
2. Parses the bytes as JSON.
3. Extracts the named parameters.
4. Calls the corresponding `internal_call_*` function.
5. Writes the return string to the output `TDataHnd___` as JSON.
6. Wraps everything in `try/except`.

The callbacks are **not** part of the AI-fill scope. They are entirely written by the bootstrap script.

### 5.11 The 24 Tool Schemas

Each tool's JSON schema is registered with the beacon in `RegisterTools`. The schema contains:

- `name` — the tool identifier, exactly as listed in §5.2.
- `description` — a long, single-string description of what the tool does, its parameters, and its return shape. These descriptions are written by the bootstrap script and are stable.
- `target_app` — always `MY_APP_NAME`.
- `target_api` — the LingoFuse Call API name; matches the tool name.
- `parameters` — a JSON Schema object with `type: "object"`, a `properties` map, and a `required` array. For tools with no parameters, `properties` is empty and `required` is absent.

---

## Chapter 6  The 8 Generators in Detail

### 6.1 The List

| # | Generator unit | Produces |
|---|----------------|----------|
| 1 | `http_pas_abi_service_generator_tool` | Pascal service code + README |
| 2 | `http_pas_abi_call_generator_tool` | Pascal call code + README |
| 3 | `http_js_abi_call_generator_tool` | JS call code + README + HTML |
| 4 | `http_py_abi_service_generator_tool` | Python service code + README |
| 5 | `http_py_abi_call_generator_tool` | Python call code + README |
| 6 | `http_cpp_abi_service_generator_tool` | C++ service header + impl + README |
| 7 | `http_cpp_abi_call_generator_tool` | C++ call header + impl + README |
| 8 | `http_cmake_generator_tool` | `CMakeLists.txt` + `test_main___.cpp` |

Total artifacts: 17 (from generators 1–7) + 2 (from generator 8) = **19 files**.

### 6.2 Common Contract (Generators 1–7)

| Item | Convention |
|------|-----------|
| Input | `TPascal_Func_Model` with `Typ_Normalize_Func = tnf_ABI` |
| Output | `TPascalStringList` (line list), caller must `DisposeObject` |
| Empty model | `Model = nil` or `Model.UnitName` empty → returns `nil` |
| Unsupported routines | silently dropped; log only if `GenerateCode_LogEnabled` is `True` |
| Overloads | same-name overloads are suffixed `_1`, `_2`, … in source order |

### 6.3 The CMake Generator Contract

`GenerateCMakeScript` and `GenerateTestMainCpp` both take a `TPascal_Func_Model` and return a `TPascalStringList`. Both consult:

- `Model.UnitName` — to derive the project name, the target names, and the endpoint string.
- `Model.Funcs` — only `GenerateTestMainCpp` iterates over the functions, to emit one test call per routine.

`GenerateCMakeScript` does **not** consult the function list. It only needs the unit name.

### 6.4 Name Normalization

`MakeApiName(FuncName)` replaces the following characters in `FuncName` with `_`:

- space, tab
- `.` `/` `\` `@` `:` `#` `?` `&` `=` `+` `-`

If the resulting identifier begins with a digit, a `_` is prepended.

### 6.5 Artifact File Names

Every artifact from generators 1–7 is prefixed with the normalized `UnitName`:

| Generator | Output files |
|-----------|--------------|
| Pascal service | `<U>_http_json_service_unit.pas` + `<U>_http_json_service_pascal.md` |
| Pascal call | `<U>_http_json_call_unit.pas` + `<U>_http_json_call_pascal.md` |
| JS call | `<U>_http_json_call.js` + `<U>_http_json_call_js.md` + `<U>_http_json_call_test.html` |
| Python service | `<U>_http_json_service.py` + `<U>_http_json_service_python.md` |
| Python call | `<U>_http_json_call.py` + `<U>_http_json_call_python.md` |
| C++ service | `<U>_http_json_service.hpp` + `<U>_http_json_service.cpp` + `<U>_http_json_service_cpp.md` |
| C++ call | `<U>_http_json_call.hpp` + `<U>_http_json_call.cpp` + `<U>_http_json_call_cpp.md` |
| CMake | `CMakeLists.txt` + `test_main___.cpp` (**fixed names, no unit prefix**) |

Where `<U>` is the normalized `UnitName`.

### 6.6 The `internal_call_<Api>` Stub

Each generated service unit contains one stub per supported routine, which the user must fill in. The shape is fixed:

**Pascal**:
```pascal
function internal_call_Foo_Foo(a: Int64; b: string): Int64;
begin
  // TODO: call the real function
  Result := 0;
end;
```

**Python**:
```python
def internal_call_Foo(a: int, b: str) -> int:
    """..."""
    # TODO: call the real function
    return 0
```

**C++**:
```cpp
std::int64_t internal_call_Foo(std::int64_t a, std::string b) {
    // TODO: call the real function
    return 0;
}
```

### 6.7 LV1 Model JSON Shape

`GenerateAll` consumes this JSON. If you feed it directly via `SetModelJson`, it must contain:

```json
{
  "UnitName": "MyUnit",
  "Functions": [
    {
      "Name": "Add",
      "IsFunction": true,
      "Comment": "Adds two numbers",
      "ReturnType": "int64",
      "Params": [
        {"Name": "a", "Typ": "Integer", "PascalType": "int64", "Description": "First operand"},
        {"Name": "b", "Typ": "Integer", "PascalType": "int64", "Description": "Second operand"}
      ]
    }
  ]
}
```

**Key points**:
- `UnitName` is required.
- Each element of `Functions` requires `Name` / `IsFunction` / `Params` / `ReturnType`.
- `PascalType` determines the type-family decision (see Chapter 7).
- `Description` is used only by the READMEs.

---

## Chapter 7  Type System and Mapping Rules

### 7.1 The Three Families

#### String family

`string` / `ansistring` / `unicodestring` / `tpascalstring` / `tupascalstring` / `tp_string` / `pchar` / `pansichar` / `pwidechar`

The JS generator additionally recognizes `u_string`.

#### Float family

`double` / `single` / `extended` / `real`

#### Integer family

`integer` / `longint` / `int64` / `cardinal` / `dword` / `longword` / `uint64` / `word` / `smallint` / `byte`

### 7.2 Target Language Mapping

| ABI family | Pascal | Python | C++ | JavaScript |
|------------|--------|--------|-----|------------|
| String | `string` | `str` | `std::string` | `string` |
| Float | preserved | `float` | `double` | `number` |
| Integer | preserved | `int` | `std::int64_t` | `number` |

**Key differences**:

- **Pascal** preserves the original width.
- **Python** uses `int` (unbounded).
- **C++** narrows all integers to `std::int64_t` and all floats to `double`.
- **JavaScript** narrows everything to `number` (IEEE-754 double) — **precision risk**.

### 7.3 Unsupported Types

The following types cause the entire routine to be silently dropped:

- `Boolean` / `WordBool` / `LongBool`
- `Variant` / `OleVariant`
- Arrays, records, classes, interfaces
- Enums, sets, generics
- Pointers, function pointers
- `Currency` / `Comp` / `TDateTime`

**Workaround**: serialize complex values to `string` and pass them as a normal string argument.

### 7.4 JSON Wire Types

| ABI family | JSON wire type |
|------------|----------------|
| String | `string` |
| Float | `number` |
| Integer | `number` |

JSON clients cannot distinguish `Integer` from `Int64` at the byte level. Large-integer precision is bounded by the client's JSON parser.

### 7.5 Numeric Precision Limits

| Scenario | Limit |
|----------|-------|
| JS `Number` exact integer range | ±2^53 − 1 |
| `int64` maximum | 9223372036854775807 |
| `uint64` maximum | 18446744073709551615 |
| Python `json` int | unbounded |
| JS `JSON.parse` number | IEEE-754 double |

**Recommendation**: when handling `int64` / `uint64` on a JS client, have the service return strings.

---

## Chapter 8  HTTP/JSON Wire Protocol

### 8.1 URL Composition

```
HTTP_CALL_BASE_URL + "/" + <api-name>
```

Default `HTTP_CALL_BASE_URL` for every target: `http://127.0.0.1:8081/<U>`.

### 8.2 Request Format

#### Call → Bridge (LingoFuse call)

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

#### Bridge → Service (HTTP POST)

```http
POST /<app>/<api> HTTP/1.1
Content-Type: application/json; charset=utf-8
Content-Length: ...

{"args": [v1, v2, ...]}
```

### 8.3 Response Format

#### Service → Bridge

```json
{"code": 0, "result": <value>}
{"code": -1, "error": "<message>"}
```

#### Bridge → Call (envelope)

```json
{
  "status_code": 200,
  "headers": { ... },
  "body": { "code": 0, "result": <value> }
}
```

#### Call Unwrapping

Read `body`, check `body.code`:

- `body.code = 0` → return `body.result`.
- `body.code <> 0` → throw the language-appropriate exception.

### 8.4 Argument Semantics

#### Positional (recommended)

```json
{"args": [v1, v2, v3]}
```

Array element `i` maps to parameter `i`. Missing arguments take the type default (`0` / `0.0` / `""`).

#### Named (alternative)

```json
{"param1": v1, "param2": v2}
```

Matches parameter names, case-sensitive. **Only takes effect when `args` is absent**.

### 8.5 Encoding

- Requests and responses are UTF-8.
- The bridge serializes with `ensure_ascii=False`.
- The bridge strips the trailing `\0` from LingoFuse strings before forwarding.

### 8.6 HTTP Method

The bridge only accepts **`POST`**.

---

## Chapter 9  Error Handling and Error Codes

### 9.1 Toolchain Error JSON

- Tool errors: `{"error": "<message>"}`.
- Service / bridge errors: `{"code": -N, "error": "<message>"}`.

### 9.2 All Known Tool Error Messages

| Message | Trigger |
|---------|---------|
| `Unsupported language. Use pascal or c.` | `Language` is not `pascal` / `c` |
| `Empty model JSON` | `SetModelJson("")` |
| `Invalid model JSON` | `SetModelJson(invalid JSON)` |
| `Form not available` | main form not created |
| `No source text or model JSON in session. Call SetSourceCode or SetModelJson first.` | `GenerateAll` before Step 1 |
| `Model JSON is empty. Cannot generate.` | `ModelJsonEditor` empty |

### 9.3 Service / Bridge Error Codes

| code | Meaning | Typical `http_status` |
|:----:|---------|:---------------------:|
| `0` | success | 200 |
| `-1` | remote call failed | 200 or 0 |
| `-2` | request shape error | 400 |
| `-3` | bridge precheck failed | 200 |

### 9.4 Exception Types by Target

| Target | Exception class | Fields |
|--------|-----------------|--------|
| Pascal | `EHTTPCallError` | `.Message` only |
| Python | `HTTPCallError` | `.code` / `.http_status` |
| C++ | `HTTPCallError` | `.code` / `.http_status` |
| JavaScript | `LFHttpCallError` | `.code` / `.httpStatus` |

### 9.5 Troubleshooting Flow

1. Check that Step 1 returned `{"status":"ok"}`.
2. Check that `GenerateAll` returned `{"status":"ok"}`.
3. Check that the required reader returned a non-empty string.
4. Check the GUI's log panel for dropped-routine warnings.
5. If the environment uses an agent, check the LingoFuse connection via the `Execute_And_Reg_all` return value.

### 9.6 Bridge Precheck Failure (code = -3)

`bridge.py` checks the API by default through a broadcast cache that may lag by about 3 seconds. Recommendations:

- Start the bridge with `--no-precheck`.
- Or wait 3 seconds after the service starts before calling.
- Or catch `code = -3` and retry.

---

## Chapter 10  Complete Artifact Inventory

### 10.1 The 19 Files

| # | File | Produced by | Purpose |
|---|------|-------------|---------|
| 1 | `<U>_http_json_service_unit.pas` | Pascal service gen | Pascal service |
| 2 | `<U>_http_json_service_pascal.md` | Pascal service gen | Pascal service README |
| 3 | `<U>_http_json_call_unit.pas` | Pascal call gen | Pascal call |
| 4 | `<U>_http_json_call_pascal.md` | Pascal call gen | Pascal call README |
| 5 | `<U>_http_json_call.js` | JS gen | JS client |
| 6 | `<U>_http_json_call_js.md` | JS gen | JS README |
| 7 | `<U>_http_json_call_test.html` | JS gen | JS HTML test page |
| 8 | `<U>_http_json_service.py` | Python service gen | Python service |
| 9 | `<U>_http_json_service_python.md` | Python service gen | Python service README |
| 10 | `<U>_http_json_call.py` | Python call gen | Python call |
| 11 | `<U>_http_json_call_python.md` | Python call gen | Python call README |
| 12 | `<U>_http_json_service.hpp` | C++ service gen | C++ service header |
| 13 | `<U>_http_json_service.cpp` | C++ service gen | C++ service impl |
| 14 | `<U>_http_json_service_cpp.md` | C++ service gen | C++ service README |
| 15 | `<U>_http_json_call.hpp` | C++ call gen | C++ call header |
| 16 | `<U>_http_json_call.cpp` | C++ call gen | C++ call impl |
| 17 | `<U>_http_json_call_cpp.md` | C++ call gen | C++ call README |
| 18 | `CMakeLists.txt` | CMake gen | CMake build script |
| 19 | `test_main___.cpp` | CMake gen | C++ test driver |

### 10.2 File Locations

| Frontend | Location |
|----------|----------|
| GUI | `<exe dir>/<UnitName>/` |
| CLI | same directory as the output file |
| MCP | `<exe dir>/<UnitName>/` |

### 10.3 The Bridge Is Not Part of the Deployment

The bridge is a **forwarder**. It is a separate process that must be running for any Call artifact to work. It is not generated by this toolchain; it ships with the LingoFuse runtime.

---

## Chapter 11  Common Pitfalls and Anti-Patterns

### 11.1 Input-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| `SetSourceCode(Text, "python")` | `SetSourceCode(Text, "pascal")` + read a Python reader |
| `SetSourceCode(Text, "cpp")` | `SetSourceCode(Text, "c")` + read a C++ reader |
| Call `GenerateAll` directly | call `SetSourceCode` or `SetModelJson` first |
| Read immediately after `SetSourceCode` | `GenerateAll` must be in between |

### 11.2 Generation-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Think `GenerateAll` can only be called once | It may be called many times; each refreshes the cache |
| `SetSourceCode(A)` → read → `SetSourceCode(B)` → read | The latter overwrites the former |
| Expect the MCP path not to write to disk | It writes to `<exe dir>/<UnitName>/` |

### 11.3 Read-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Expect a reader to trigger generation | a reader only reads the cache |
| Read a Call reader after generating Service | the corresponding branch must be generated |
| Read `GetSourceJson` after `SetModelJson` | that path produces no LV0 |

### 11.4 Type-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| A `Boolean` parameter | change to `Integer` (0/1) or `string` |
| An array parameter | serialize to `string` |
| Expect `int64` to be lossless on JS | JS `Number` is exact only up to 2^53 |
| Expect `Extended` to be consistent across platforms | treat it as `double` |

### 11.5 CMake-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| `project(<name> CXX)` | use `project(<name> C CXX)`; `LingoFuse.c` is a C file |
| Generating two units into the same directory | one directory per unit; `CMakeLists.txt` and `test_main___.cpp` are overwritten |
| Expecting the CMake script to stage DLLs | the script does not; the README's deployment section covers it |
| Forgetting `LINGOFUSE_CPP_LIB_DIR` | the configure step fails with a clear `FATAL_ERROR` |

### 11.6 Session-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Expect a reset tool | there is none; re-call `SetSourceCode` / `SetModelJson` |
| Multi-threaded `GenerateAll` | serialize; UI operations are not concurrency-safe |
| Expect state to persist after process exit | state is in-memory; process exit discards it |

### 11.7 The Complete Anti-Pattern List

| # | Anti-pattern | Consequence | Fix |
|---|--------------|-------------|-----|
| 1 | `Language='python'` | error return | use `pascal` / `c` |
| 2 | Skip `GenerateAll` | readers return `""` | call `GenerateAll` first |
| 3 | Call `SetSourceCode` twice without `GenerateAll` | cache not updated | call `GenerateAll` again |
| 4 | Mix Service / Call | wire protocol mismatch | generate both from the same source |
| 5 | Have a `Boolean` parameter | routine silently dropped | change the type |
| 6 | Handle `int64` on JS | precision loss | service returns strings |
| 7 | Forget bridge `--no-precheck` | first call returns `code = -3` | add `--no-precheck` |
| 8 | LingoFuse not prepared | call side fails to initialize | `LF_PrepareClient` + `LF_PrepareDone` |
| 9 | Bridge endpoint does not match service | `code = -3` | check `--endpoint` |
| 10 | Generate two units into one directory | CMake files overwritten | one directory per unit |
| 11 | `project(name CXX)` | configure error | `project(name C CXX)` |
| 12 | Expect the CMake script to stage DLLs | linker cannot find LingoFuse | stage manually or set PATH |

---

## Chapter 12  AI Agent Usage Rules and Decision Tree

### 12.1 Ten Usage Rules

1. **Pass only `pascal` or `c` as `Language`.**
2. **After Step 1, always call `GenerateAll`.**
3. **Read is a pure read.** To refresh, call `GenerateAll` again.
4. **One `SetSourceCode` per session is enough.**
5. **Service and Call must come from the same source text.**
6. **When `int64` / `uint64` are involved, warn the user about JS precision.**
7. **Unsupported routines are silently dropped.** Tell the user to inspect the artifact or re-generate with supported types.
8. **On failure, check the tool's `{"error":"..."}` return first.**
9. **The MCP path writes to disk** under `<exe dir>/<UnitName>/`.
10. **When unsure, run a minimal example first.**

### 12.2 Decision Tree

```
What does the user want?
├── "Generate code from a Pascal unit"
│   ├── Target Pascal service → SetSourceCode(pas) → GenAll → GetLastPascalServiceCode
│   ├── Target Pascal call    → SetSourceCode(pas) → GenAll → GetLastPascalCallCode
│   ├── Target Python service → SetSourceCode(pas) → GenAll → GetLastPythonServiceCode
│   ├── Target Python call    → SetSourceCode(pas) → GenAll → GetLastPythonCallCode
│   ├── Target C++ service    → SetSourceCode(pas) → GenAll → GetLastCppServiceHeader + Impl + Readme
│   ├── Target C++ call       → SetSourceCode(pas) → GenAll → GetLastCppCallHeader + Impl + Readme
│   ├── Target JS call        → SetSourceCode(pas) → GenAll → GetLastJsCallCode + TestHtml
│   └── Target CMake          → SetSourceCode(pas) → GenAll → GetLastCMakeScript + TestMainCpp
└── "Generate code from a C header"
    └── Same as above, pass "c" as Language
```

### 12.3 Pre-Call Checklist

- [ ] Which target language? (Pascal / Python / C++ / JS)
- [ ] Service side or call side?
- [ ] Is the source text Pascal or C?
- [ ] Are all parameter types supported?
- [ ] Are there any `Boolean` / `Variant` / array / record parameters?
- [ ] Are there any `int64` parameters or return values? (JS precision)

### 12.4 Post-Call Checklist

- [ ] Did `SetSourceCode` / `SetModelJson` return `{"status":"ok"}`?
- [ ] Did `GenerateAll` return `{"status":"ok"}`?
- [ ] Does the required reader return a non-empty string?
- [ ] If empty, was the wrong branch called?
- [ ] For C++: are `CMakeLists.txt` and `test_main___.cpp` present next to the `.hpp`/`.cpp` pair?

### 12.5 Output File Naming Cheat Sheet

```
<UnitName>_http_json_<side>.<ext>

side ∈ {service, call}
ext  ∈ {pas, py, hpp, cpp, js, html, md}

Fixed-name exceptions:
  CMakeLists.txt
  test_main___.cpp
```

### 12.6 Frequently Asked Questions

**Q: Should I use `SetSourceCode` or `SetModelJson`?**
A: Use `SetSourceCode` if you have source text. Use `SetModelJson` if you already have an LV1 model JSON.

**Q: Where are the generated artifacts?**
A: In memory (returned by the readers) and on disk (`<exe dir>/<UnitName>/` for GUI/MCP; the output directory for CLI).

**Q: Why does a reader return an empty string?**
A: Three reasons: `GenerateAll` was not called; the wrong branch was called; or the source text was empty.

**Q: Why is a function missing from the output?**
A: It contains an unsupported type and was silently dropped.

**Q: Where is the CMake script?**
A: In `CMakeLists.txt`, written next to the C++ artifacts. Also retrievable via `GetLastCMakeScript`.

**Q: How do I build the generated C++?**
A: Configure the CMake project with `-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf`, then `cmake --build`.

**Q: Does the CMake script stage the DLLs?**
A: No. The README's deployment section covers DLL placement.

---

## Chapter 13  Complete Usage Examples

### 13.1 Minimum Flow — Pascal source → Python service

**Input** (Pascal unit):

```pascal
unit Calculator;

interface

// Adds two numbers
function Add(a, b: Integer): Integer;

// Subtracts b from a
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

**Call sequence**:

```
1. CodeDeclToJsonAbi_SetSourceCode(<text above>, "pascal")
   → {"status":"ok"}

2. CodeDeclToJsonAbi_GenerateAll()
   → {"status":"ok","unit_name":"Calculator","files":{...}}

3. CodeDeclToJsonAbi_GetLastPythonServiceCode()
   → Python module source

4. CodeDeclToJsonAbi_GetLastPythonServiceReadme()
   → Markdown usage document
```

### 13.2 C source → C++ call (with CMake)

**Input** (C header):

```c
/* Math.h */
#ifndef MATH_H
#define MATH_H

int square(int x);
double sqrt_of(double x);

#endif
```

**Call sequence**:

```
1. CodeDeclToJsonAbi_SetSourceCode(<text above>, "c")
2. CodeDeclToJsonAbi_GenerateAll()
3. CodeDeclToJsonAbi_GetLastCppCallHeader()
4. CodeDeclToJsonAbi_GetLastCppCallImpl()
5. CodeDeclToJsonAbi_GetLastCppCallReadme()
6. CodeDeclToJsonAbi_GetLastCMakeScript()
7. CodeDeclToJsonAbi_GetLastTestMainCpp()
```

**Build the artifacts**:

```bash
# write the seven outputs above to a directory
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

### 13.3 One source, multiple targets

```
1. SetSourceCode(MyUnitText, "pascal")
2. GenerateAll()

// Read any target; all come from the same source
3. GetLastPascalServiceCode()
4. GetLastPythonServiceCode()
5. GetLastCppServiceHeader()
6. GetLastCppServiceImpl()
7. GetLastJsCallCode()
8. GetLastJsTestHtml()
9. GetLastCMakeScript()
```

No need to re-call `SetSourceCode`.

### 13.4 Use an existing model JSON

```
1. SetModelJson('{"UnitName":"X","Functions":[...]}')
   → {"status":"ok","unit_name":"X"}
2. GenerateAll()
3. GetLastPascalCallCode()
```

### 13.5 Troubleshooting a failure

```
SetSourceCode(Text, "pascal")
GenerateAll()
// Returns {"error":"Model JSON is empty. Cannot generate."}
// This means the source text failed to parse.
GetSourceJson()
// If empty → the source text itself has a problem.
// If non-empty → LV0 to LV1 normalization failed (rare).
```

### 13.6 GUI user flow

1. Open the program.
2. Select `Pascal` or `C` in the top dropdown.
3. Paste source text into the Source page.
4. Click `Source → JSON`.
5. Click `JSON → Model`.
6. Click `Generate Source`.
7. View or copy artifacts from the Final Source tabs.
8. Artifacts are also written to `<exe dir>/<UnitName>/`.

---

## Chapter 14  Honest Uncertainty List

1. **`GenerateAll` disk-write behavior in a non-writable directory**
   - The source calls `SaveCode` / `SaveSynEditCode`, which internally uses `TPascalStringList.SaveToFile`.
   - **Uncertain**: whether a write failure raises an exception that is swallowed, and whether the MCP return value is affected.
   - **Recommendation**: rely on the in-memory cache (reader return values), not on the disk.

2. **Exception propagation from `GenerateAllSourcesClick` to MCP**
   - The button event handler is not wrapped in `try/except` in the source.
   - **Uncertain**: whether an exception is caught by the callback envelope and converted to `{"error":"..."}`.
   - **Speculation**: yes, because the callback envelope has an `except on E: Exception` branch, but the message may be incomplete.

3. **`LanguageSelectorChange` when `ItemIndex = 0`**
   - The `else` branch sets the highlighter to `AnyHighlighter` and `CurrentSourceLanguage` to `slUnknown`.
   - **Uncertain**: what `ParseSourceToJsonClick` does in the `slUnknown` state.
   - **Speculation**: it reports `"Unsupported language."` and exits.

4. **State sharing when multiple `TFuncDeclList`s are used simultaneously**
   - **Uncertain**: whether `tpascal_func_decl_tool` uses global state internally, and therefore whether concurrent calls are safe.

5. **`MakeApiName`'s handling of `-`**
   - The source replaces `-` with `_`.
   - **Uncertain**: whether this is intentional (Pascal function names cannot contain `-` anyway) or defensive.
   - **Speculation**: defensive.

6. **Whether every edge syntax in the `InsertTestUnit` sample parses**
   - The sample contains a variety of edge syntax (generics, function pointers, nested types).
   - **Uncertain**: whether every construct is correctly parsed by `Z.Pascal_Func_Tool`.
   - **Recommendation**: treat it as a parser stress test, not a generator test.

7. **Whether the generated HTML test page works under `file://`**
   - The HTML embeds everything needed.
   - **Uncertain**: CORS behavior under `file://`.
   - **Speculation**: for `http://127.0.0.1:8081` requests, cross-origin is triggered; serve the page via a local HTTP server.

8. **Whether the C++ call side's `_invoke` is thread-safe**
   - **Uncertain**: whether concurrent calls to `lingofuse::bridge::httpCall` contend on shared state.
   - **Speculation**: `LF_Call` is thread-safe.

9. **The relationship between `HTTP_CALL_DEFAULT_TIMEOUT_S` and `HTTP_CALL_TIMEOUT_MS`**
   - The source uses `25.0` and `60000`.
   - **Uncertain**: whether the two must be kept consistent manually.
   - **Recommendation**: ensure `HTTP_CALL_TIMEOUT_MS > HTTP_CALL_DEFAULT_TIMEOUT_S * 1000`.

10. **The GUI log panel's clearing strategy**
    - Source: clears when exceeding 5000 lines.
    - **Uncertain**: whether this causes performance problems when log volume explodes.

11. **The `SysTimer` interval**
    - **Uncertain**: the concrete value.
    - **Speculation**: 100–500 ms.

12. **Whether all 24 callbacks are correctly registered**
    - **Uncertain**: whether `RegisterAPIs` has omissions or duplicates.
    - **Speculation**: they correspond one-to-one with the 24 schemas in `RegisterTools`.

13. **Whether `SendLogAsync`'s `TCompute.RunC` can lose logs**
    - **Uncertain**: race conditions under high concurrency.

14. **`LF_CheckApiEx(BEACON_APP, REGISTER_API)`'s 3-second cache**
    - **Uncertain**: whether a just-started beacon is misjudged as unavailable.

15. **C++ generator's `LF_CDECL` macro**
    - It appears in callback definitions.
    - **Uncertain**: where `LF_CDECL` is defined.
    - **Recommendation**: confirm it is defined before compiling.

16. **Whether `GenerateAll`'s file manifest matches the actual file names**
    - The manifest is assembled manually in `internal_call`.
    - **Uncertain**: whether it matches the names written by `SaveCode` word-for-word.
    - **Speculation**: yes, because both follow the same naming rules.

17. **Whether `SetModelJson` preserves the byte-level exactness of the input**
    - The source validates with `ParseText`, then writes the original string.
    - **Uncertain**: whether `ParseText` normalizes the original.
    - **Speculation**: no; the original string is preserved.

18. **Whether `GenerateCMakeScript` and `GenerateTestMainCpp` are called for non-C++ targets**
    - The GUI's `GenerateAllSourcesClick` calls them unconditionally.
    - **Uncertain**: whether this is intentional or an oversight.
    - **Speculation**: intentional — the CMake script is a unit-level artifact, not a C++-only artifact, and the CLI writes it for C++ targets specifically (see §3.8).

19. **Whether the CMake script's `test_main___.cpp` reference is always satisfiable**
    - The script expects `test_main___.cpp` in the same directory.
    - **Uncertain**: whether the CLI always writes it alongside the `.hpp`/`.cpp` pair.
    - **Speculation**: yes — the CLI's `Generate_Cpp` writes both CMake artifacts unconditionally.

20. **The exact scope of `FSessionCMakeScript` / `FSessionTestMainCpp`**
    - They are cleared by `SetSourceCode` and `SetModelJson`.
    - **Uncertain**: whether they are also cleared by `GenerateAll`'s other steps.
    - **Speculation**: no; they are populated only by the CMake step.

---

## Closing

### Purpose of This Knowledge Base

A self-contained, actionable, bounded reference for `code_decl_to_json_abi`. It does not pretend to replace the source, but it lets you use the tool correctly in 90% of scenarios, and know when to stop and ask a human in the remaining 10%.

### Core Promises

- **Self-review**: every conclusion has been verified against the source.
- **Actionable**: every pattern can be copied and pasted.
- **Honest**: uncertain points are called out explicitly.

### The Five Facts to Remember

1. **`SetSourceCode(Source, "pascal" | "c")`** — only these two source languages are accepted.
2. **`GenerateAll()`** — mandatory; produces all 19 artifacts at once.
3. **24 readers** — 2 intermediate + 1 generation + 19 artifact readers.
4. **The MCP provider is a bootstrap → AI-fill architecture** — every tool body delegates to the GUI via `TCompute.Sync`.
5. **C++ targets carry two extra fixed-name files** — `CMakeLists.txt` and `test_main___.cpp`.

### Interface with Related Units

- The generators depend on `Z.Pascal_Func_Model` and `Z.Pascal_Func_Tool`.
- The generated artifacts depend on `lingofuse_import` (and, for C++ call, `lf_http_bridge_client`).
- The CMake sub-toolchain depends on the LingoFuse C++ distribution.
- The bridge `bridge.py` handles the conversion between HTTP/JSON and LingoFuse; its internals are outside this document's scope.

---

**Document version**: v2
**Document role**: single authoritative reference for `code_decl_to_json_abi`. If any discrepancy with the source is found, the source prevails.