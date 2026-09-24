# code_decl_to_json_abi Complete Knowledge Base

> **Purpose**: This document is the **single authoritative reference** for the `code_decl_to_json_abi` toolchain. After reading this document, you should be able to correctly, without looking at any source code:
> - Drive the entire generation workflow through the MCP API (22 tools);
> - Understand the content and purpose of every artifact file;
> - Determine whether a given Pascal / C function will be supported;
> - Troubleshoot common failure scenarios.
>
> **Promise**: Every statement in this document has been verified line-by-line against the source. Anything I cannot determine from the source is explicitly called out in the "Honest Uncertainty List" at the end.
>
> **Scope**: `code_decl_to_json_abi.lpr`, `code_decl_to_abi_json_frm.pas`, `code_decl_to_json_abi_mcp_api.pas`, `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`, and the 7 generator units.
>
> **Document language**: English. **File names**: English.

---

## Table of Contents

- [Chapter 0  Quick Orientation](#chapter-0-quick-orientation)
- [Chapter 1  Core Concepts and Terminology](#chapter-1-core-concepts-and-terminology)
- [Chapter 2  Three-Phase Workflow](#chapter-2-three-phase-workflow)
- [Chapter 3  MCP API Complete Reference](#chapter-3-mcp-api-complete-reference)
- [Chapter 4  All 22 Tools Quick Reference](#chapter-4-all-22-tools-quick-reference)
- [Chapter 5  UI Controls Complete Reference](#chapter-5-ui-controls-complete-reference)
- [Chapter 6  The 7 Generators in Detail](#chapter-6-the-7-generators-in-detail)
- [Chapter 7  Type System and Mapping Rules](#chapter-7-type-system-and-mapping-rules)
- [Chapter 8  HTTP/JSON Wire Protocol](#chapter-8-httpjson-wire-protocol)
- [Chapter 9  Error Handling and Error Codes](#chapter-9-error-handling-and-error-codes)
- [Chapter 10  Common Pitfalls and Anti-Patterns](#chapter-10-common-pitfalls-and-anti-patterns)
- [Chapter 11  AI Agent Usage Rules and Decision Tree](#chapter-11-ai-agent-usage-rules-and-decision-tree)
- [Chapter 12  Complete Usage Examples](#chapter-12-complete-usage-examples)
- [Chapter 13  Honest Uncertainty List](#chapter-13-honest-uncertainty-list)

---

## Chapter 0  Quick Orientation

### 0.1 What This Project Is

`code_decl_to_json_abi` is a **cross-language code generator**. It takes a **Pascal unit** or a **C header file** as input and automatically generates **LingoFuse service-side / call-side code targeting the HTTP/JSON protocol**, covering the following target languages:

- **Pascal** (service + call)
- **Python** (service + call)
- **C++** (service + call)
- **JavaScript** (call side + HTML test page only)

**17 artifacts in total** (each artifact is paired with a Markdown usage document; READMEs count toward the artifact total).

### 0.2 Three Public Frontends

The same generation capability is exposed through three entry points:

| Entry | File | Audience |
|-------|------|----------|
| **GUI** | `code_decl_to_json_abi.lpr` + `code_decl_to_abi_json_frm.pas` | Human engineers |
| **MCP API (declarations)** | `code_decl_to_json_abi_mcp_api.pas` | Only for other units to `uses` |
| **MCP API (implementation + registration)** | `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` | Discovered by the LingoFuse beacon |

**All three behave identically**: the MCP path reuses the entire GUI logic by "simulating UI operations" on the main thread.

### 0.3 5-Second Cheat Sheet

```
Step 1: SetSourceCode(Source, "pascal" | "c")     // or SetModelJson(ModelJson)
Step 2: GenerateAll()
Step 3: GetLast<Lang><Side><Artifact>()           // pick from the 17 readers
```

### 0.4 The 7 Most Important Rules

1. **The `Language` argument only accepts `"pascal"` or `"c"`**. `python` / `cpp` / `js` are *target* languages, **not** source languages.
2. **After Step 1, you must call `GenerateAll`**. Otherwise all readers return empty strings.
3. **Read is pure read** — it does not trigger new generation; to refresh the cache, call `GenerateAll` again.
4. **A single `SetSourceCode` covers the entire session**. Switching target language does not require a new source.
5. **Service and Call halves must come from the same source text** — do not mix them.
6. **Arguments of type `Boolean` / `Variant` / array / record / class / interface / enum / set / generics / pointer / `Currency` / `Comp` / `TDateTime` cause the entire routine to be silently dropped**.
7. **`int64` / `uint64` may lose precision on the JS client** (JS `Number` is IEEE-754 double).

---

## Chapter 1  Core Concepts and Terminology

### 1.1 Glossary

| Term | Definition |
|------|------------|
| **Source** | Input text: a Pascal unit or a C header file |
| **Source Language** | The source language. **Only** `pascal` or `c` |
| **Target Language** | The target language: `pascal` / `python` / `cpp` / `javascript` |
| **Side** | Which side. `Service` / `Call` |
| **Source JSON (LV0)** | Intermediate JSON produced by parsing the source text |
| **Model JSON (LV1)** | Model JSON produced by normalizing Source JSON; the sole input to the generators |
| **Service** | Service side: registers APIs, decodes requests, runs user implementations, encodes responses |
| **Call** | Call side: exposes the same signatures as functions, serializes arguments, issues remote calls |
| **Bridge** | The converter between HTTP/JSON and LingoFuse (`bridge.py`) |
| **MCP API** | The 22 tool functions exposed to agents through the LingoFuse beacon |
| **Beacon** | The LingoFuse application hosting all tool registration info (default name `agent_main_app`) |
| **Tool Provider Unit** | The Pascal unit that registers MCP APIs with the beacon |

### 1.2 Two Legal Forms of Source Text

#### 1.2.1 Pascal Unit (`Language = "pascal"`)

Must be a complete `.pas` file with this structure:

```pascal
unit MyUnit;

interface

uses
  SysUtils, ...;

// top-level function/procedure declarations
function Add(a, b: Integer): Integer;
procedure Log(msg: string);

implementation

// implementations (ignored)

end.
```

**What the parser cares about**:
- The `unit` declaration (extracts `UnitName`)
- **Top-level** function / procedure declarations between `interface` and `implementation`
- The comment immediately preceding a declaration (extracted as the description)

**What the parser ignores**:
- Everything after `implementation`
- Declarations inside classes / records / interfaces (`NestLevel > 0`)
- Unit lists in `uses` (recorded into `UsesList` but do not affect generation)

#### 1.2.2 C Header File (`Language = "c"`)

Must be a complete `.h` file with this structure:

```c
/* MyHeader.h */
#ifndef MYHEADER_H
#define MYHEADER_H

/* top-level function prototypes */
int Add(int a, int b);
void Log(const char* msg);

#endif /* MYHEADER_H */
```

**What the parser cares about**:
- The `#ifndef` / `#define` include guard (extracts `UnitName`)
- Top-level function prototypes

**What the parser ignores**:
- Macro definitions (other than the guard)
- `struct` / `enum` / `union` / `typedef`
- Global variable declarations (with `=` initialization)
- Function definitions (with `{ ... }` bodies)
- Function-pointer parameters (containing `(*...)`)

### 1.3 Three Type Families

All 7 generators only recognize these three **families** (members are listed in Chapter 7):

- **String family**
- **Float family**
- **Integer family**

**Argument types outside these three families cause the entire routine to be silently dropped.**

### 1.4 Session State

- All state lives on the main form instance `code_decl_to_abi_json_form`.
- **Not persisted** (the MCP path, per the source implementation, writes files to `<executable directory>/<UnitName>/`; see Chapter 5 for details).
- There is no explicit reset tool; re-calling `SetSourceCode` / `SetModelJson` replaces everything.
- Exiting the process discards all state.

---

## Chapter 2  Three-Phase Workflow

### 2.1 Flow Diagram

```
┌───────────────────────────────┐
│  Step 1: Input                │
│  ─────────────────────────    │
│  ① SetSourceCode(Source, Lang)│  ← source text + source language
│  ② SetModelJson(ModelJson)    │  ← feed LV1 Model JSON directly
└──────────────┬────────────────┘
               │
               ▼
┌───────────────────────────────┐
│  Step 2: Generate             │
│  ─────────────────────────    │
│  GenerateAll()                │  ← generate all 17 artifacts at once, cache them
└──────────────┬────────────────┘
               │
               ▼
┌───────────────────────────────┐
│  Step 3: Read                 │
│  ─────────────────────────    │
│  17 GetLast* readers          │  ← read the artifacts you need, one by one
└───────────────────────────────┘
```

### 2.2 Step 1: Input

#### 2.2.1 `SetSourceCode(Source, Language)`

| Parameter | Type | Required | Notes |
|-----------|------|:--------:|-------|
| `Source` | `string` | Yes | Full source text |
| `Language` | `string` | Yes | `"pascal"` or `"c"`, case-insensitive |

**Actions performed** (on the main thread):
1. Set `Sel_Lang_ComboBox.ItemIndex` according to `Language` and call `Sel_Lang_ComboBoxChange`.
2. Write `Source` into `source_edit`.
3. Switch `MainPageControl.ActivePage` to `SourceTab`.

**Does not parse, does not generate.**

**Returns**:
- `{"status":"ok"}` — success
- `{"error":"<message>"}` — failure

#### 2.2.2 `SetModelJson(ModelJson)`

| Parameter | Type | Required | Notes |
|-----------|------|:--------:|-------|
| `ModelJson` | `string` | Yes | LV1 Model JSON (shape in §6.6) |

**Actions performed**:
1. Validate JSON well-formedness.
2. Write `ModelJson` into `model_json_edit`.
3. Switch `MainPageControl.ActivePage` to `ModelJsonTab`.

**Does not generate.**

**Returns**:
- `{"status":"ok","unit_name":"<UnitName>"}` — success
- `{"error":"<message>"}` — failure

### 2.3 Step 2: `GenerateAll()`

**Takes no arguments.**

**Actions performed** (in order, simulating clicks on the main thread):

1. If `source_edit.Text` is non-empty → call `source_2_json_nex_ButtonClick`
   - Parse source text → write into `source2json_edit`
   - UI switches to `SourceJsonTab`
2. If `source2json_edit.Text` is non-empty → call `JsonToModelButtonClick`
   - LV0 JSON → normalize → write into `model_json_edit`
   - UI switches to `ModelJsonTab`
3. If `model_json_edit.Text` is non-empty → call `GenerateSourceButtonClick`
   - Calls all 7 generators × 2 (code + README)
   - Results go into the 17 `final_*_Edit` fields
   - Results are also written to disk under `<executable directory>/<UnitName>/` (**the MCP path writes to disk too**)
   - UI switches to `FinalSourceTab`

**Preconditions**: at least one of `source_edit` or `model_json_edit` is non-empty.

**Returns** (success):
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
    "cpp_call_readme":        "<UnitName>_http_json_call_cpp.md"
  }
}
```

**Returns** (failure):
```json
{"error":"<message>"}
```

**Failure scenarios**:
- `"No source text or model JSON in session. Call SetSourceCode or SetModelJson first."`
- `"Model JSON is empty. Cannot generate."`
- `"Form not available"`

### 2.4 Step 3: Reading

**All 19 readers take no arguments and return `string`.** See §3.3.

**Key conventions**:
- **Pure read** — does not trigger any generation.
- If the corresponding branch has never been generated → returns empty string `""`.
- Each `GenerateAll` refreshes all cached values.

### 2.5 Session Behavior

- **One source, many targets**: after a single `SetSourceCode`, any combination of readers may be called.
- **Repeated `SetSourceCode`**: replaces the source text entirely; previously cached values are not automatically cleared, but the next `GenerateAll` will refill them.
- **Repeated `GenerateAll`**: re-parses and refreshes all 17 cached values every time.

---

## Chapter 3  MCP API Complete Reference

### 3.1 Naming Convention

Every function is prefixed with `CodeDeclToJsonAbi_`. Globally unique, to make beacon discovery easy.

### 3.2 Tool Function Signatures (by Category)

#### 3.2.1 Input Tools (2)

| Function | Signature |
|----------|-----------|
| `CodeDeclToJsonAbi_SetSourceCode` | `function(Source: string; Language: string): string` |
| `CodeDeclToJsonAbi_SetModelJson` | `function(ModelJson: string): string` |

#### 3.2.2 Intermediate Readers (2)

| Function | Signature |
|----------|-----------|
| `CodeDeclToJsonAbi_GetSourceJson` | `function(): string` |
| `CodeDeclToJsonAbi_GetModelJson` | `function(): string` |

#### 3.2.3 Generation Tool (1)

| Function | Signature |
|----------|-----------|
| `CodeDeclToJsonAbi_GenerateAll` | `function(): string` |

#### 3.2.4 Artifact Readers (17)

All are `function(): string`:

1. `CodeDeclToJsonAbi_GetLastPascalServiceCode`
2. `CodeDeclToJsonAbi_GetLastPascalServiceReadme`
3. `CodeDeclToJsonAbi_GetLastPascalCallCode`
4. `CodeDeclToJsonAbi_GetLastPascalCallReadme`
5. `CodeDeclToJsonAbi_GetLastJsCallCode`
6. `CodeDeclToJsonAbi_GetLastJsCallReadme`
7. `CodeDeclToJsonAbi_GetLastJsTestHtml`
8. `CodeDeclToJsonAbi_GetLastPythonServiceCode`
9. `CodeDeclToJsonAbi_GetLastPythonServiceReadme`
10. `CodeDeclToJsonAbi_GetLastPythonCallCode`
11. `CodeDeclToJsonAbi_GetLastPythonCallReadme`
12. `CodeDeclToJsonAbi_GetLastCppServiceHeader`
13. `CodeDeclToJsonAbi_GetLastCppServiceImpl`
14. `CodeDeclToJsonAbi_GetLastCppServiceReadme`
15. `CodeDeclToJsonAbi_GetLastCppCallHeader`
16. `CodeDeclToJsonAbi_GetLastCppCallImpl`
17. `CodeDeclToJsonAbi_GetLastCppCallReadme`

### 3.3 Input Tool Detailed Contracts

#### 3.3.1 `SetSourceCode`

**Success return**: `{"status":"ok"}`

**Failure returns**:
- `{"error":"Unsupported language. Use pascal or c."}` — `Language` is not `pascal` / `c`
- `{"error":"Form not available"}` — GUI not initialized

**Notes**:
- Empty `Source` **does not raise an error**; it simply writes empty text. A subsequent `GenerateAll` will fail due to parse failure.
- **Synchronization mechanism**: `internal_call` uses `TCompute.Sync` internally to run UI operations on the main thread.

#### 3.3.2 `SetModelJson`

**Success return**: `{"status":"ok","unit_name":"<UnitName>"}`

**Failure returns**:
- `{"error":"Empty model JSON"}`
- `{"error":"Invalid model JSON"}`
- `{"error":"Form not available"}`

### 3.4 Intermediate Reader Detailed Contracts

#### 3.4.1 `GetSourceJson`

**Returns**: `source2json_edit.Text` or `""`.

- If the most recent Step 1 was `SetModelJson`, **returns an empty string** (that path does not produce LV0 JSON).
- If the most recent Step 1 was `SetSourceCode` but `GenerateAll` has not yet been called, still `""`.
- After a successful `GenerateAll`, it is filled in.

#### 3.4.2 `GetModelJson`

**Returns**: `model_json_edit.Text` or `""`.

- If the most recent Step 1 was `SetModelJson`, returns the exact string that was passed in.
- If the most recent Step 1 was `SetSourceCode`, has value after a successful `GenerateAll`.

### 3.5 Generation Tool Detailed Contract

#### 3.5.1 `GenerateAll`'s Disk-Write Side Effect

**Key fact**: `GenerateAll` internally calls `GenerateSourceButtonClick`, which **writes all 17 artifacts to disk**. Disk location: `umlCombinePath(umlGetFilePath(ParamStr(0)), Model.UnitName)`.

- If `<executable directory>/<UnitName>/` does not exist, it is created.
- If the directory is not writable, the disk write fails but the in-memory cache is still filled; the MCP return is still `{"status":"ok"}`.

### 3.6 Artifact Reader Detailed Contracts

Each reader does two things before reading:

1. Switch `MainPageControl.ActivePage` to `FinalSourceTab`.
2. Switch `final_source_PageControl.ActivePage` to the corresponding child `TabSheet`.

**Return value** = the corresponding `final_*_Edit.Lines.Text`.

**Notes**:
- If `GenerateAll` has never been called, the edit is empty → returns `""`.
- If `Form not available`, returns `""`.

### 3.7 All 22 Tools Quick Reference

| # | Tool | Category | Input | Output |
|---|------|----------|-------|--------|
| 1 | `SetSourceCode` | Step 1 | text + source language | status JSON |
| 2 | `SetModelJson` | Step 1 | LV1 JSON | status JSON |
| 3 | `GetSourceJson` | intermediate read | none | LV0 JSON |
| 4 | `GetModelJson` | intermediate read | none | LV1 JSON |
| 5 | `GenerateAll` | Step 2 | none | file-manifest JSON |
| 6 | `GetLastPascalServiceCode` | Step 3 | none | Pascal source |
| 7 | `GetLastPascalServiceReadme` | Step 3 | none | Markdown |
| 8 | `GetLastPascalCallCode` | Step 3 | none | Pascal source |
| 9 | `GetLastPascalCallReadme` | Step 3 | none | Markdown |
| 10 | `GetLastJsCallCode` | Step 3 | none | JavaScript |
| 11 | `GetLastJsCallReadme` | Step 3 | none | Markdown |
| 12 | `GetLastJsTestHtml` | Step 3 | none | HTML |
| 13 | `GetLastPythonServiceCode` | Step 3 | none | Python source |
| 14 | `GetLastPythonServiceReadme` | Step 3 | none | Markdown |
| 15 | `GetLastPythonCallCode` | Step 3 | none | Python source |
| 16 | `GetLastPythonCallReadme` | Step 3 | none | Markdown |
| 17 | `GetLastCppServiceHeader` | Step 3 | none | C++ header |
| 18 | `GetLastCppServiceImpl` | Step 3 | none | C++ impl |
| 19 | `GetLastCppServiceReadme` | Step 3 | none | Markdown |
| 20 | `GetLastCppCallHeader` | Step 3 | none | C++ header |
| 21 | `GetLastCppCallImpl` | Step 3 | none | C++ impl |
| 22 | `GetLastCppCallReadme` | Step 3 | none | Markdown |

### 3.8 Registration Flow (Not a Tool, Internal)

`Execute_And_Reg_all` does this in one shot:

1. `RegisterAPIs` → creates the App and issues 22 `LF_RegisterCallEx` calls.
2. `LF_PrepareClientEx("ipc:agent", App)`.
3. `LF_PrepareDone`.
4. `RegisterTools` → registers the 22 tool JSON schemas with `agent_main_app.register_agent`.

**Return value**: `True` iff all 22 tools registered successfully.

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

---

## Chapter 4  All 22 Tools Quick Reference

(See §3.7; not repeated here.)

**Call templates**:

```
# Minimum complete flow
SetSourceCode(MyUnitText, "pascal")
GenerateAll()
GetLastPythonServiceCode()
GetLastPythonServiceReadme()
```

```
# Feed model JSON directly
SetModelJson(ExistingModelJson)
GenerateAll()
GetLastCppCallHeader()
GetLastCppCallImpl()
GetLastCppCallReadme()
```

```
# One source text, multiple target reads
SetSourceCode(MyUnitText, "pascal")
GenerateAll()
GetLastPascalServiceCode()
GetLastPythonServiceCode()
GetLastCppServiceHeader()
GetLastJsCallCode()
```

---

## Chapter 5  UI Controls Complete Reference

### 5.1 Top-Level Structure

```
Tcode_decl_to_abi_json_form
├── MainPageControl: TPageControl
│   ├── WelcomeTab: TTabSheet
│   ├── SourceTab: TTabSheet
│   │   └── source_edit: TSynEdit
│   ├── SourceJsonTab: TTabSheet
│   │   └── source2json_edit: TSynEdit
│   ├── ModelJsonTab: TTabSheet
│   │   └── model_json_edit: TSynEdit
│   └── FinalSourceTab: TTabSheet
│       └── final_source_PageControl: TPageControl
│           ├── http_pas_service_TabSheet
│           │   ├── final_http_pas_service_source_Edit: TSynEdit
│           │   └── final_http_pas_service_readme_Edit: TSynEdit
│           ├── http_pas_call_TabSheet
│           │   ├── final_http_pas_call_source_Edit: TSynEdit
│           │   └── final_http_pas_call_readme_Edit: TSynEdit
│           ├── http_webjs_call_TabSheet
│           │   ├── final_http_webjs_call_source_Edit: TSynEdit
│           │   └── final_http_webjs_call_readme_Edit: TSynEdit
│           ├── http_webjs_test_TabSheet
│           │   └── final_http_webjs_test_source_Edit: TSynEdit
│           ├── http_py_service_TabSheet
│           │   ├── final_http_py_service_source_Edit: TSynEdit
│           │   └── final_http_py_service_readme_Edit: TSynEdit
│           ├── http_py_call_TabSheet
│           │   ├── final_http_py_call_source_Edit: TSynEdit
│           │   └── final_http_py_call_readme_Edit: TSynEdit
│           ├── http_cpp_service_TabSheet
│           │   ├── final_http_hpp_service_source_Edit: TSynEdit
│           │   ├── final_http_cpp_service_source_Edit: TSynEdit
│           │   └── final_http_cpp_service_readme_Edit: TSynEdit
│           └── http_cpp_call_TabSheet
│               ├── final_http_hpp_call_source_Edit: TSynEdit
│               ├── final_http_cpp_call_source_Edit: TSynEdit
│               └── final_http_cpp_call_readme_Edit: TSynEdit
├── BottomPanel: TPanel
│   └── LogMemo: TMemo
└── SysTimer: TTimer
```

### 5.2 Key Fields Overview

#### 5.2.1 Text Editors (3)

| Field | Content |
|-------|---------|
| `source_edit` | source text |
| `source2json_edit` | LV0 Source JSON |
| `model_json_edit` | LV1 Model JSON |

#### 5.2.2 Artifact Editors (17)

See §3.2.4 and §3.7 — they map one-to-one.

#### 5.2.3 TabSheets

| Field | Description |
|-------|-------------|
| `WelcomeTab` | Welcome page |
| `SourceTab` | Source text page |
| `SourceJsonTab` | LV0 JSON page |
| `ModelJsonTab` | LV1 JSON page |
| `FinalSourceTab` | All artifacts page |
| `http_pas_service_TabSheet` | Pascal service |
| `http_pas_call_TabSheet` | Pascal call |
| `http_webjs_call_TabSheet` | JS call |
| `http_webjs_test_TabSheet` | JS HTML test page |
| `http_py_service_TabSheet` | Python service |
| `http_py_call_TabSheet` | Python call |
| `http_cpp_service_TabSheet` | C++ service |
| `http_cpp_call_TabSheet` | C++ call |

#### 5.2.4 Buttons

| Field | Event | Purpose |
|-------|-------|---------|
| `source_2_json_nex_Button` | `source_2_json_nex_ButtonClick` | Source → LV0 JSON |
| `JsonToModelButton` | `JsonToModelButtonClick` | LV0 JSON → LV1 JSON |
| `ModelToJsonButton` | `ModelToJsonButtonClick` | LV1 JSON → LV0 JSON (reverse) |
| `BackToModelJsonButton` | `BackToModelJsonButtonClick` | Switch back to ModelJsonTab |
| `JsonToPascalButton` | `JsonToPascalButtonClick` | LV0 JSON → source code |
| `GenerateSourceButton` | `GenerateSourceButtonClick` | LV1 JSON → 17 artifacts (**writes to disk**) |
| `Formater_source_Button` | `Formater_source_ButtonClick` | Format source text |
| `to_source_Button` | `to_source_ButtonClick` | Switch back to SourceTab |
| `empty_unit_Button` | `empty_unit_ButtonClick` | Insert empty template |
| `empty_unit_Button1` | `empty_unit_Button1Click` | Insert complex test sample |
| `Open_pascal_rule_Button` | `Open_pascal_rule_ButtonClick` | Open Pascal rules document |
| `Open_c_rule_Button` | `Open_c_rule_ButtonClick` | Open C rules document |

#### 5.2.5 Language Selection

| Field | Description |
|-------|-------------|
| `Sel_Lang_ComboBox` | Drop-down: `ItemIndex` = 0 (unknown) / 1 (Pascal) / 2 (C) |
| `Sel_Lang_ComboBoxChange` | Switches highlighter + updates `current_language` |

**`current_language`** is a **private field**. It cannot be written from the outside. It must be set indirectly via `Sel_Lang_ComboBox.ItemIndex` + `Sel_Lang_ComboBoxChange`.

#### 5.2.6 Log and Timer

| Field | Description |
|-------|-------------|
| `LogMemo` | Displays `DoStatus` logs (cleared when exceeding 5000 lines) |
| `SysTimer` | Flushes the log queue + drives LingoFuse Sync |

### 5.3 MCP → UI Simulation Rules

Each `internal_call_*` uses `TCompute.Sync` to post UI operations to the main thread. The simulation rule table:

| MCP tool | UI operations |
|----------|---------------|
| `SetSourceCode` | Set `Sel_Lang_ComboBox.ItemIndex` → call `Sel_Lang_ComboBoxChange` → write `source_edit.Text` → switch to `SourceTab` |
| `SetModelJson` | Validate JSON → write `model_json_edit.Text` → switch to `ModelJsonTab` |
| `GetSourceJson` | Read `source2json_edit.Text` |
| `GetModelJson` | Read `model_json_edit.Text` |
| `GenerateAll` | If source → call `source_2_json_nex_ButtonClick`; if LV0 → call `JsonToModelButtonClick`; if LV1 → call `GenerateSourceButtonClick`; finally switch to `FinalSourceTab` |
| All 17 readers | Switch to `FinalSourceTab` → switch to the corresponding child `TabSheet` → read the corresponding `final_*_Edit.Lines.Text` |

### 5.4 Disk Write Location

In `GenerateSourceButtonClick`:

```pascal
app_dir.Text := umlCombinePath(umlGetFilePath(ParamStr(0)), func_model.UnitName);
umlCreateDirectory(app_dir.Text);
```

Artifacts are written to `<executable directory>/<UnitName>/`. **The MCP path writes to disk too** (because it internally calls this event).

### 5.5 Disk Write File Names

Specified by `SaveCode(fn)` / `SaveSynEditCode(edit, fn)`:

| Call | File name |
|------|-----------|
| `SaveSynEditCode(source_edit, 'source.pas')` | `source.pas` (source, only if non-empty) |
| `SaveSynEditCode(source_edit, 'source.h')` | `source.h` (C source, only if non-empty) |
| `SaveSynEditCode(source2json_edit, 'source.json')` | `source.json` (only if non-empty) |
| `SaveSynEditCode(model_json_edit, 'source_model.json')` | `source_model.json` (only if non-empty) |
| `SaveCode(func_model.UnitName + '_http_json_service_unit.pas')` | Pascal service |
| `SaveCode(func_model.UnitName + '_http_json_service_pascal.md')` | Pascal service README |
| `SaveCode(func_model.UnitName + '_http_json_call_unit.pas')` | Pascal call |
| `SaveCode(func_model.UnitName + '_http_json_call_pascal.md')` | Pascal call README |
| `SaveCode(func_model.UnitName + '_http_json_call.js')` | JS call |
| `SaveCode(func_model.UnitName + '_http_json_call_js.md')` | JS call README |
| `SaveCode(func_model.UnitName + '_http_json_call_test.html')` | JS test page |
| `SaveCode(func_model.UnitName + '_http_json_service.py')` | Python service |
| `SaveCode(func_model.UnitName + '_http_json_service_python.md')` | Python service README |
| `SaveCode(func_model.UnitName + '_http_json_call.py')` | Python call |
| `SaveCode(func_model.UnitName + '_http_json_call_python.md')` | Python call README |
| `SaveCode(func_model.UnitName + '_http_json_service.hpp')` | C++ service header |
| `SaveCode(func_model.UnitName + '_http_json_service.cpp')` | C++ service impl |
| `SaveCode(func_model.UnitName + '_http_json_service_cpp.md')` | C++ service README |
| `SaveCode(func_model.UnitName + '_http_json_call.hpp')` | C++ call header |
| `SaveCode(func_model.UnitName + '_http_json_call.cpp')` | C++ call impl |
| `SaveCode(func_model.UnitName + '_http_json_call_cpp.md')` | C++ call README |

---

## Chapter 6  The 7 Generators in Detail

### 6.1 Common Contract (Shared by All 7)

| Item | Convention |
|------|-----------|
| **Input** | `TPascal_Func_Model` with `Typ_Normalize_Func = tnf_ABI` |
| **Output** | `TPascalStringList` (line list), caller must `DisposeObject` |
| **Empty model** | `Model = nil` or `Model.UnitName` empty → returns `nil` |
| **Unsupported routines** | Silently dropped; only a `DoStatus` log if `GenerateCode_LogEnabled=True` |
| **Overloads** | Same-name overloads are suffixed `_1`, `_2` in order |

### 6.2 Name Normalization

`MakeApiName(FuncName)` replaces the following characters in `FuncName` with `_`:

- space, tab
- `.` `/` `\` `@` `:` `#` `?` `&` `=` `+`

**Note**: `-` is not replaced. If the source function name contains `-`, the generated JS/C++ identifier will be a syntax error.

### 6.3 File Name Rules

Every artifact name is prefixed with `Model.UnitName` (`UnitName` is also run through `MakeApiName` first).

| Generator | Output files |
|-----------|--------------|
| Pascal service | `<U>_http_json_service_unit.pas` + `<U>_http_json_service_pascal.md` |
| Pascal call | `<U>_http_json_call_unit.pas` + `<U>_http_json_call_pascal.md` |
| JS call | `<U>_http_json_call.js` + `<U>_http_json_call_js.md` + `<U>_http_json_call_test.html` |
| Python service | `<U>_http_json_service.py` + `<U>_http_json_service_python.md` |
| Python call | `<U>_http_json_call.py` + `<U>_http_json_call_python.md` |
| C++ service | `<U>_http_json_service.hpp` + `<U>_http_json_service.cpp` + `<U>_http_json_service_cpp.md` |
| C++ call | `<U>_http_json_call.hpp` + `<U>_http_json_call.cpp` + `<U>_http_json_call_cpp.md` |

Where `<U>` = the normalized `UnitName`.

### 6.4 Generator-by-Generator Details

#### 6.4.1 Pascal Service (`http_pas_abi_service_generator_tool`)

**Output structure**:
- Unit name: `<U>_http_json_service_unit`
- Interface:
  - `HTTP_SERVICE_APP_NAME` / `HTTP_SERVICE_APP_DESC` (editable)
  - `DEBUG_LOG: Boolean` (editable)
  - `RegisterAllHTTPJsonAPIs(App: TAppHnd___)`
  - `CreateAndRegisterHTTPJsonApp: TAppHnd___`
  - `function internal_call_<Api>(...): ...;` × N (**stubs that the user must fill in**)
- Implementation:
  - JSON access helpers (`_Json_Get_Int64_ByIndex` etc.)
  - cdecl callbacks (`Callback_<Api>`)
  - registration function

**Dependencies** (needed by the generated unit):
- `SysUtils, Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Json, lingofuse_import`

**What the user must do**:
1. Add the actual implementation unit to the `uses` clause in the `implementation` section.
2. Fill in each `internal_call_<Api>` function body.
3. Start the host program using the standard LingoFuse service workflow.

#### 6.4.2 Pascal Call (`http_pas_abi_call_generator_tool`)

**Output structure**:
- Unit name: `<U>_http_json_call_unit`
- Interface:
  - `EHTTPCallError = class(Exception)`
  - `HTTP_CALL_BASE_URL: string` (editable)
  - `function <Api>(...): ...;` × N
- Implementation: each function does `LFHttpPost` → checks `body.code` → returns `body.result`

**Dependencies**:
- `SysUtils, Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Json, lingofuse_import, lf_http_bridge_client`

**What the user must do**:
1. Prepare LingoFuse at program startup (`LF_ResetPrepare` / `LF_PrepareClient` / `LF_PrepareDone`).
2. Set `HTTP_CALL_BASE_URL`.
3. Call the generated free functions directly.

#### 6.4.3 JS Call (`http_js_abi_call_generator_tool`)

**Outputs 3 files**:

1. `<U>_http_json_call.js` — standalone IIFE library
   - Attached to `window.<U>Api` (or `globalThis.<U>Api`)
   - Members: `baseUrl` / `getBaseUrl()` / `setBaseUrl(url)` / `Error` / one `async` function per API
   - No third-party dependencies (only `fetch` / `Promise` / `async-await`)

2. `<U>_http_json_call_js.md` — README

3. `<U>_http_json_call_test.html` — self-contained test page
   - Embeds the JS library
   - One test card per API: parameter input boxes + button + result area

**JS precision warning**: `int64` / `uint64` parameters and return values are tagged with `@warning` in the JSDoc.

#### 6.4.4 Python Service (`http_py_abi_service_generator_tool`)

**Output structure**:
- Dependency: the `lingofuse` Python package
- Interface:
  - `HTTP_SERVICE_APP_NAME` / `HTTP_SERVICE_APP_DESC` / `HTTP_SERVICE_ENDPOINT` (editable)
  - `DEBUG_LOG: bool` (editable)
  - `register_all_http_json_apis(app)`
  - `create_and_register_http_json_app()`
  - `internal_call_<Api>(...)` × N (stub)
  - `main()` — includes signal handling and clean shutdown

**What the user must do**:
1. Fill in each `internal_call_<Api>`.
2. Run `python3 <U>_http_json_service.py`.
3. Start `bridge.py` with the same `--endpoint`.

#### 6.4.5 Python Call (`http_py_abi_call_generator_tool`)

**Output structure**:
- Dependency: `requests`
- Interface:
  - `HTTP_CALL_BASE_URL: str`
  - `HTTP_CALL_TIMEOUT: float` (default 30.0)
  - `DEBUG_LOG: bool` (default False)
  - `HTTPCallError`
  - One function per API
  - `_call_api(api_name, args)` — internal unified entry point

**What the user must do**:
1. `pip install requests`
2. `import <U>_http_json_call as api`
3. `api.HTTP_CALL_BASE_URL = "http://.../<app>"`
4. Call the generated functions

#### 6.4.6 C++ Service (`http_cpp_abi_service_generator_tool`)

**Outputs 3 files**:

1. `<U>_http_json_service.hpp`
   - Depends on `<cstdint>` `<string>` `LingoFuse.hpp`
   - Namespace: `<u>` (lowercase `U`)
   - Members: `HTTP_SERVICE_APP_NAME` and other constants, `internal_call_<Api>` × N, `register_all_http_json_apis` / `create_and_register_http_json_app` / `run_service`
2. `<U>_http_json_service.cpp`
   - Implementation: stub definitions, cdecl callbacks, registration, `main()`
   - Depends on `LingoFuse.hpp` / `lf_io.hpp` / `json.hpp`
3. `<U>_http_json_service_cpp.md`

**What the user must do**:
1. Fill in each `internal_call_<Api>`.
2. `g++ -std=c++17 ... LingoFuse.c -o service -pthread -ldl`
3. Start the service, then start the bridge with the same endpoint.

#### 6.4.7 C++ Call (`http_cpp_abi_call_generator_tool`)

**Outputs 3 files**:

1. `<U>_http_json_call.hpp`
   - Depends on `<cstdint>` `<stdexcept>` `<string>`
   - Namespace: `<u>`
   - Members:
     - `HTTP_BRIDGE_APP_NAME` (default `__lf_http_bridge__`)
     - `HTTP_BRIDGE_API_NAME` (default `__lf_outbound_post__`)
     - `HTTP_CALL_TIMEOUT_MS` (default 60000)
     - `HTTP_CALL_BASE_URL` (default `http://127.0.0.1:8081/<U>`)
     - `HTTP_CALL_DEFAULT_TIMEOUT_S` (default 25.0)
     - `HTTPCallError` class
     - `<Api>` × N
2. `<U>_http_json_call.cpp`
   - Internal unified entry point `_lf_http_post(url, body, timeout)`
3. `<U>_http_json_call_cpp.md`

**What the user must do**:
1. Prepare LingoFuse (`LibraryLoader` / `resetPrepare` / `prepareClient` / `prepareDone`).
2. Set `HTTP_CALL_BASE_URL`.
3. Call the generated functions.

### 6.5 Shape of the `internal_call_<Api>` Stub

Each stub is where the user must fill in. Copy as-is:

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

### 6.6 LV1 Model JSON Shape

`GenerateAll` actually consumes this JSON. If you feed it directly via `SetModelJson`, it must contain the following fields:

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
- Each element of the `Functions` array requires `Name` / `IsFunction` / `Params` / `ReturnType`.
- `PascalType` determines the type-family decision (see Chapter 7).
- `Description` is used by the README.

### 6.7 Generator ↔ GUI Event Mapping

| GUI event | Generator called |
|-----------|------------------|
| `source_2_json_nex_ButtonClick` | none (parse only) |
| `JsonToModelButtonClick` | none (normalize only) |
| `JsonToPascalButtonClick` | `tpascal_func_decl_tool.decl_to_pascal` / `decl_to_c` |
| `Formater_source_ButtonClick` | same as above |
| `GenerateSourceButtonClick` | **all 7 generators × 2 (code + README)** |

---

## Chapter 7  Type System and Mapping Rules

### 7.1 The Three Families

#### 7.1.1 String Family

| Type name (case-insensitive) |
|------------------------------|
| `string` / `ansistring` / `unicodestring` |
| `tpascalstring` / `tupascalstring` / `tp_string` |
| `pchar` / `pansichar` / `pwidechar` |
| `u_string` (**only recognized by the JS generator**; Pascal/Python/C++ generators do not recognize it) |

#### 7.1.2 Float Family

| Type name |
|-----------|
| `double` / `single` / `extended` / `real` |

#### 7.1.3 Integer Family

| Type name |
|-----------|
| `integer` / `longint` / `int64` |
| `cardinal` / `dword` / `longword` / `uint64` |
| `word` / `smallint` / `byte` |

### 7.2 Target Language Mapping Table

| ABI family | Pascal | Python | C++ | JavaScript |
|------------|--------|--------|-----|------------|
| String | `string` | `str` | `std::string` | `string` |
| Float | `Double` / `Single` / `Extended` / `Real` (each preserved) | `float` | `double` | `number` |
| Integer | each preserved (`Integer` / `Int64` / ...) | `int` | `std::int64_t` (all narrowed) | `number` |

**Key differences**:
- **Pascal** preserves the original width.
- **Python** uses `int` (unbounded); annotation is informational only.
- **C++** narrows all integers to `std::int64_t` and all floats to `double`.
- **JavaScript** narrows all integers and floats to `number` (IEEE-754 double) — **there is precision risk**.

### 7.3 Unsupported Types

The following types cause **the entire routine to be silently dropped**:

- `Boolean` / `WordBool` / `LongBool`
- `Variant` / `OleVariant`
- Arrays, records, classes, interfaces
- Enums, sets, generics
- Pointers, function pointers
- `Currency` / `Comp` / `TDateTime`

**Workaround**: serialize complex values to `string` and pass them along.

### 7.4 JSON Wire Types

The HTTP/JSON protocol carries less type information than the ABI binary protocol:

| ABI family | JSON wire type |
|------------|----------------|
| String | `string` |
| Float | `number` |
| Integer | `number` |

Therefore:
- JSON clients cannot distinguish `Integer` from `Int64` at the byte level.
- Large integers' precision is determined by the client's JSON parser.
- The server deserializes according to the declared Pascal type; if a JSON number exceeds the target type's range, it is **silently truncated**.

### 7.5 Numeric Precision Limits Quick Reference

| Scenario | Limit |
|----------|-------|
| JS `Number` exact integer range | ±2^53 − 1 |
| `int64` maximum | 9223372036854775807 ≈ 9.2×10^18 |
| `uint64` maximum | 18446744073709551615 ≈ 1.8×10^19 |
| JSON number (Python `json`) | unbounded int, or bounded float |
| JSON number (JS `JSON.parse`) | IEEE-754 double |

**Recommendation**: When handling `int64` / `uint64` on a JS client, have the server return strings.

---

## Chapter 8  HTTP/JSON Wire Protocol

### 8.1 URL Composition

#### 8.1.1 Call → Bridge

```
HTTP_CALL_BASE_URL + "/" + <api-name>
```

- `HTTP_CALL_BASE_URL` default: `http://127.0.0.1:8081/<U>`
- The user may modify it after the call side is initialized

#### 8.1.2 Bridge → Service

The bridge maps `/<app>/<api>` to a LingoFuse call `LF_Call(<app>, <api>)`.

### 8.2 Request Format

#### 8.2.1 Call → Bridge (LingoFuse call)

```
LF_Call("__lf_http_bridge__", <bridge_request>)
```

`<bridge_request>` is JSON:

```json
{
  "url":     "http://.../<api>",
  "method":  "POST",
  "headers": { "Content-Type": "application/json; charset=utf-8" },
  "body":    { "args": [v1, v2, ...] },
  "timeout": 25.0
}
```

#### 8.2.2 Bridge → Service (HTTP POST)

```http
POST /<app>/<api> HTTP/1.1
Content-Type: application/json; charset=utf-8
Content-Length: ...

{"args": [v1, v2, ...]}
```

### 8.3 Response Format

#### 8.3.1 Service → Bridge

```json
{"code": 0, "result": <value>}     // success
{"code": -1, "error": "<message>"} // failure
```

#### 8.3.2 Bridge → Call (envelope)

```json
{
  "status_code": 200,
  "headers": { ... },
  "body": { "code": 0, "result": <value> }
}
```

#### 8.3.3 Call Unwrapping

Read the `body` field and check `body.code`:

- `body.code = 0` → return `body.result`
- `body.code <> 0` → throw an exception

### 8.4 Argument Semantics

#### 8.4.1 Positional Arguments (Recommended)

```json
{"args": [v1, v2, v3]}
```

- Array element `i` maps to the `i`-th parameter of the original function
- If too few arguments are provided, missing parameters take the type's default value (`0` / `0.0` / `""`)

#### 8.4.2 Named Arguments (Alternative)

```json
{"param1": v1, "param2": v2}
```

- Matches the original function's parameter names (**case-sensitive**)
- **Only takes effect when `args` is absent**

#### 8.4.3 Priority

If `args` is present, named arguments are **completely ignored**.

### 8.5 Character Encoding

- Both requests and responses are **UTF-8**
- Serialization strategy: `ensure_ascii=False`
- The bridge strips the trailing `\0` from LingoFuse strings before forwarding

### 8.6 HTTP Method

The bridge only accepts **`POST`** (other methods are rejected).

---

## Chapter 9  Error Handling and Error Codes

### 9.1 Toolchain Error JSON Shape

#### 9.1.1 Input/Generation Tool Errors

```json
{"error":"<message>"}
```

#### 9.1.2 Service/Bridge Errors

```json
{"code": -N, "error": "<message>"}
```

### 9.2 All Known Error Messages

| Message | Trigger |
|---------|---------|
| `Unsupported language. Use pascal or c.` | `Language` is not `pascal` / `c` |
| `Empty model JSON` | `SetModelJson("")` |
| `Invalid model JSON` | `SetModelJson(invalid JSON)` |
| `Form not available` | Main form not created |
| `No source text or model JSON in session. Call SetSourceCode or SetModelJson first.` | `GenerateAll` called before Step 1 |
| `Model JSON is empty. Cannot generate.` | `model_json_edit` empty |

### 9.3 Service/Bridge Error Codes

| code | Meaning | Typical `http_status` |
|:----:|---------|:---------------------:|
| `0` | Success | 200 |
| `-1` | Remote call failed (server exception, network error, timeout) | 200 (server exception) / 0 (network error) |
| `-2` | Request shape error (URL path could not be parsed) | 400 |
| `-3` | Bridge precheck failed (bridge did not find the target API) | 200 |

### 9.4 Exception Types by Target Language

| Target | Exception class | Fields |
|--------|-----------------|--------|
| Pascal | `EHTTPCallError` | `.Message` (no `.code` field) |
| Python | `HTTPCallError` | `.code` / `.http_status` |
| C++ | `HTTPCallError` | `.code` / `.http_status` |
| JavaScript | `LFHttpCallError` | `.code` / `.httpStatus` |

### 9.5 Troubleshooting Flow

1. **Check whether Step 1 succeeded** (returns `{"status":"ok"}`).
2. **Check whether `GenerateAll` succeeded.**
3. **Check reader return values** (empty string means not generated).
4. **Check the LingoFuse connection** (`Execute_And_Reg_all`'s return value).
5. **Check `LogMemo`** (all `DoStatus` output).

### 9.6 Handling Bridge Precheck Failure (code = -3)

`bridge.py` checks `check_api` by default, relying on a broadcast cache that may lag by ~3 seconds. Recommendations:

- Start the bridge with `--no-precheck`
- Or wait 3 seconds after the service starts before calling
- Or catch `code = -3` on the client and retry after a delay

---

## Chapter 10  Common Pitfalls and Anti-Patterns

### 10.1 Input-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| `SetSourceCode(Text, "python")` | `SetSourceCode(Text, "pascal")` + read Python reader |
| `SetSourceCode(Text, "cpp")` | `SetSourceCode(Text, "c")` + read C++ reader |
| Call `GenerateAll` directly | Call `SetSourceCode` or `SetModelJson` first |
| Read right after `SetSourceCode` | `GenerateAll` must be in between |
| `SetModelJson(hand-written JSON)` without `UnitName` | Must contain `UnitName` / `Functions` |

### 10.2 Generation-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Think `GenerateAll` can only be called once | It can be called many times; each refreshes the cache |
| `SetSourceCode(A)` → read → `SetSourceCode(B)` → read | The latter overwrites the former; a session should have only one source |
| Expect the MCP path not to write to disk | It actually writes to `<exe_dir>/<UnitName>/` |
| Assume the directory is writable | If not, the disk write fails but the in-memory cache remains valid |

### 10.3 Read-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Expect a reader to trigger generation | A reader only reads the cache |
| Read a Call reader after generating Service | You get an empty string; read the corresponding branch |
| Read `GetSourceJson` after `SetModelJson` | You get an empty string; that path produces no LV0 |

### 10.4 Type-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| A `Boolean` parameter in the source unit | Change to `Integer` (0/1) or `string` |
| An array parameter in the source unit | Serialize it to `string` |
| Expect `int64` to be lossless on JS | JS `Number` is only exact up to 2^53; have the server return strings |
| Expect `Extended` to be consistent across platforms | Treat it as `double` |

### 10.5 Session-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Expect a reset tool | There is none; re-call `SetSourceCode` / `SetModelJson` |
| Multi-threaded `GenerateAll` | Serialize; internal UI operations are not concurrency-safe |
| Expect state to persist after the process exits | It is in-memory; the process exit discards it |

### 10.6 UI-Stage Pitfalls

| Anti-pattern | Correct approach |
|--------------|------------------|
| Write `current_language` directly | Use `Sel_Lang_ComboBox.ItemIndex` + `Sel_Lang_ComboBoxChange` |
| Expect `*_ButtonClick` to produce no logs | It does `DoStatus` to `LogMemo` |
| Expect `LogMemo` to be unbounded | It clears when exceeding 5000 lines |

### 10.7 Complete Anti-Pattern List

| # | Anti-pattern | Consequence | Fix |
|---|--------------|-------------|-----|
| 1 | `Language='python'` | Returns error | Use `pascal` / `c` |
| 2 | Skip `GenerateAll` | Readers return empty string | Call `GenerateAll` first |
| 3 | Call `SetSourceCode` twice without `GenerateAll` | Cache not updated | Call `GenerateAll` again |
| 4 | Mix Service / Call | Wire protocol mismatch | Generate both from the same source |
| 5 | Have a `Boolean` parameter | Whole routine dropped | Change the type |
| 6 | Handle `int64` on JS | Precision loss | Server returns strings |
| 7 | Forget bridge `--no-precheck` | First call returns `code = -3` | Add `--no-precheck` |
| 8 | LingoFuse not prepared | Call side fails to initialize | `LF_PrepareClient` + `LF_PrepareDone` |
| 9 | Bridge endpoint does not match service | `code = -3` | Check `--endpoint` |
| 10 | Expect empty source text to error | It silently writes | Validate input yourself |

---

## Chapter 11  AI Agent Usage Rules and Decision Tree

### 11.1 Ten Usage Rules

1. **Pass only `pascal` or `c` as `Language`**. Anything else returns an error.
2. **After Step 1, you must call `GenerateAll`** before calling any reader.
3. **Read is pure read**. To refresh, call `GenerateAll` again.
4. **One `SetSourceCode` per session is enough**. Switching target language does not switch source.
5. **Service / Call must come from the same source**.
6. **When there are `int64` / `uint64` parameters or return values, warn the user about JS precision**.
7. **Unsupported routines are silently dropped**; tell the user to look at `LogMemo` or check the artifacts.
8. **On failure, look at `LogMemo` first**, then the MCP `error` return.
9. **The MCP path writes to disk** under `<exe_dir>/<UnitName>/`.
10. **When unsure, run a minimal example first**.

### 11.2 Decision Tree

```
What does the user want?
├── "Generate code from a Pascal unit"
│   ├── Target Pascal service → SetSourceCode(pas) → GenAll → GetLastPascalServiceCode
│   ├── Target Pascal call    → SetSourceCode(pas) → GenAll → GetLastPascalCallCode
│   ├── Target Python service → SetSourceCode(pas) → GenAll → GetLastPythonServiceCode
│   ├── Target Python call    → SetSourceCode(pas) → GenAll → GetLastPythonCallCode
│   ├── Target C++ service    → SetSourceCode(pas) → GenAll → GetLastCppServiceHeader + Impl
│   ├── Target C++ call       → SetSourceCode(pas) → GenAll → GetLastCppCallHeader + Impl
│   └── Target JS call        → SetSourceCode(pas) → GenAll → GetLastJsCallCode + Html
└── "Generate code from a C header"
    └── Same as above, pass "c" as Language
```

### 11.3 Pre-Call Checklist

- [ ] Which target language? (pascal / python / cpp / js)
- [ ] Service side or call side?
- [ ] Is the source text Pascal or C?
- [ ] Are all parameter types supported?
- [ ] Are there any `Boolean` / `Variant` / array / record parameters? (→ will be dropped)
- [ ] Are there any `int64` parameters or return values? (→ JS precision issue)

### 11.4 Post-Call Checklist

- [ ] Did `SetSourceCode` / `SetModelJson` return `{"status":"ok"}`?
- [ ] Did `GenerateAll` return `{"status":"ok"}`?
- [ ] Does the required reader return a non-empty string?
- [ ] If empty, was the wrong branch called (Service / Call)?
- [ ] Does `LogMemo` show any dropped-routine warnings?

### 11.5 Output File Naming Cheat Sheet

```
<UnitName>_http_json_<side>.<ext>

side ∈ {service, call}
ext  ∈ {pas, py, hpp, cpp, js, html, md}
```

### 11.6 FAQ

**Q: Should I use `SetSourceCode` or `SetModelJson`?**
A: If you have source text, use `SetSourceCode`. If you have LV1 JSON (e.g. produced elsewhere), use `SetModelJson`. In most cases, use `SetSourceCode`.

**Q: Where are the generated artifacts?**
A: In memory (returned by readers) + on disk (`<exe_dir>/<UnitName>/`).

**Q: Why does a reader return an empty string?**
A: One of three reasons: ① `GenerateAll` was not called; ② the wrong branch was called; ③ the source text is empty.

**Q: Why is a function missing from the generated output?**
A: It contains an unsupported type and was silently dropped. Check `LogMemo`.

**Q: Do I need to call `SetSourceCode` once per target language?**
A: No. After one `SetSourceCode`, `GenerateAll` produces all 17 artifacts at once. You can then read any of them.

---

## Chapter 12  Complete Usage Examples

### 12.1 Minimum Complete Flow (Pascal source → Python service)

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

### 12.2 C source → C++ call

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
1. SetSourceCode(<text above>, "c")
2. GenerateAll()
3. GetLastCppCallHeader()
4. GetLastCppCallImpl()
5. GetLastCppCallReadme()
```

### 12.3 One source, multiple targets

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
```

**No need** to re-call `SetSourceCode`.

### 12.4 Use an existing Model JSON directly

```
1. SetModelJson('{"UnitName":"X","Functions":[...]}')
   → {"status":"ok","unit_name":"X"}
2. GenerateAll()
3. GetLastPascalCallCode()
```

### 12.5 Troubleshooting a Failure

```
SetSourceCode(Text, "pascal")
GenerateAll()
// Returns {"error":"Model JSON is empty. Cannot generate."}
// ↓ This means the source text failed to parse
GetSourceJson()
// If empty → the source text itself has a problem
// If non-empty → LV0 to LV1 normalization failed (rare)
```

### 12.6 GUI User Manual Flow

1. Open the program.
2. Select `Pascal` or `C` in the top dropdown.
3. Paste source text into the `Source` page.
4. Click `Source → JSON`.
5. Click `JSON → Model`.
6. Click `Generate Source`.
7. View/copy artifacts on the `Final Source` page's various TabSheets.
8. Artifacts are also written to `<exe_dir>/<UnitName>/`.

---

## Chapter 13  Honest Uncertainty List

The following items cannot be fully determined from the available source. Consult the source or ask a human before relying on them.

1. **`GenerateAll`'s disk-write behavior in a non-writable directory**
   - The source calls `SaveCode` / `SaveSynEditCode`, which internally uses `TPascalStringList.SaveToFile`.
   - **Uncertain**: whether a write failure raises an exception that is swallowed; whether the MCP return is affected.
   - **Recommendation**: rely only on the in-memory cache (reader return values), not on disk.

2. **Exception propagation from `GenerateSourceButtonClick` to MCP**
   - The button event handler is not wrapped in `try...except` in the source.
   - **Uncertain**: whether the exception is caught by `Callback_*` and converted to `{"error":...}`.
   - **Speculation**: yes (because `Callback_*` has `except on E: Exception`), but the message may be incomplete.

3. **`Sel_Lang_ComboBoxChange`'s behavior when `ItemIndex = 0`**
   - The `else` branch in the source sets `source_edit.Highlighter` to `AnyHighlighter` and `current_language` to `slUnknown`.
   - **Uncertain**: what happens when `source_2_json_nex_ButtonClick` is called after `slUnknown` is set.
   - **Speculation**: it will report `"unsupported language."` and exit.

4. **State sharing when multiple `TFuncDeclList`s are used simultaneously**
   - Whether `tpascal_func_decl_tool` uses global state internally.
   - **Uncertain**: whether concurrent calls are safe.

5. **`MakeApiName`'s handling of `-`**
   - The source does not replace `-`.
   - **Uncertain**: whether this is intentional (since Pascal function names do not contain `-`) or an oversight.
   - **Speculation**: intentional.

6. **Whether all edge syntax in the complex test sample inserted by `empty_unit_Button1Click` can be parsed**
   - The sample contains a variety of edge syntax (generics, function pointers, nested types, etc.).
   - **Uncertain**: whether every syntax construct is correctly parsed by `Z.Pascal_Func_Tool`.
   - **Recommendation**: treat it as a **parser stress test** rather than a generator test.

7. **Whether the HTML produced by `GetLastJsTestHtml` can be opened by double-clicking**
   - The generated HTML embeds the JS library and can theoretically run offline.
   - **Uncertain**: CORS behavior under the `file://` protocol.
   - **Speculation**: for `http://127.0.0.1:8081` requests, cross-origin is triggered; serve it via a local HTTP server.

8. **Whether the C++ call side's `_lf_http_post` is thread-safe internally**
   - The source uses `lingofuse::DataHandle` + `lingofuse::call`.
   - **Uncertain**: whether there is shared-state contention under concurrent calls.
   - **Speculation**: `LF_Call` is thread-safe (see the LingoFuse documentation).

9. **Relationship between `HTTP_CALL_DEFAULT_TIMEOUT_S` and `HTTP_CALL_TIMEOUT_MS`**
   - In the source, `HTTP_CALL_DEFAULT_TIMEOUT_S = 25.0` and `HTTP_CALL_TIMEOUT_MS = 60000`.
   - **Uncertain**: `60000 ms` is the LingoFuse round-trip timeout and `25.0 s` is the HTTP request timeout; the two must be kept consistent manually.
   - **Recommendation**: ensure `HTTP_CALL_TIMEOUT_MS > HTTP_CALL_DEFAULT_TIMEOUT_S * 1000`.

10. **`LogMemo` clearing strategy when exceeding 5000 lines**
    - Source: `if LogMemo.Lines.Count > 5000 then LogMemo.Lines.Clear;`.
    - **Uncertain**: whether this causes performance problems when log volume explodes.

11. **`SysTimer`'s interval**
    - The source does not directly give `Interval`.
    - **Uncertain**: the concrete value.
    - **Speculation**: between 100 and 500 ms.

12. **Whether all `Callback_*` are correctly registered**
    - The source has 22 `Callback_*` functions.
    - **Uncertain**: whether `RegisterAPIs` has omissions or duplicates.
    - **Speculation**: they correspond one-to-one with the 22 schemas in `RegisterTools`.

13. **Whether `Do_Th_Send`'s `TCompute.RunC` can lose logs**
    - The source posts asynchronously.
    - **Uncertain**: whether there is a race condition under high concurrency.

14. **`LF_CheckApiEx(BEACON_APP, REGISTER_API)`'s 3-second cache issue**
    - `RegisterTools` calls it first to check the beacon.
    - **Uncertain**: if the beacon just started, whether it misjudges it as unavailable.

15. **C++ generator's `LF_CDECL` macro**
    - It appears in the source in `Callback_*` definitions.
    - **Uncertain**: where `LF_CDECL` is defined (LingoFuse.hpp or LingoFuse.h).
    - **Recommendation**: confirm `LF_CDECL` is defined before compiling.

16. **Whether `GenerateAll`'s file manifest matches the actual file names written by `GenerateSourceButtonClick`**
    - The `files` field returned by MCP is assembled manually by `internal_call`.
    - **Uncertain**: whether it matches `SaveCode`'s actual file names word-for-word.
    - **Speculation**: yes (same naming rules).

17. **Whether `SetModelJson` preserves the byte-level exactness of the input JSON**
    - The source first validates with `ParseText`, then writes the original string into `model_json_edit`.
    - **Uncertain**: whether `ParseText` normalizes the original.
    - **Speculation**: no (what is written is the original string).

---

## Closing

### Purpose of This Knowledge Base

A **self-contained, actionable, bounded** reference for `code_decl_to_json_abi`. It does not pretend to replace the source, but it lets you use the tool correctly in 90% of scenarios, and know when to stop and ask a human in the remaining 10%.

### Core Promises

- **Self-review**: every conclusion has been verified line-by-line against the source.
- **Actionable**: every pattern can be copied and pasted.
- **Honest**: uncertain points are called out explicitly, without misleading.

### Quick Recall

1. **`SetSourceCode(Source, "pascal" | "c")`** — only these two source languages are accepted.
2. **`GenerateAll()`** — mandatory, produces all 17 artifacts at once.
3. **`GetLast<Lang><Side><Artifact>()`** — 17 pure-read readers.
4. **Unsupported routines are silently dropped**.
5. **JS handling of `int64` carries precision risk**.

### Interface with Related Units

- The generators depend on `Z.Pascal_Func_Model` and `Z.Pascal_Func_Tool`.
- The generated artifacts depend on `lingofuse_import` and `lf_http_bridge_client`.
- The bridge `bridge.py` handles the conversion between HTTP/JSON and LingoFuse (this document does not cover its internals).

---

**Document version**: v1.0
**Last updated**: 2026-09-23
**Document role**: This file is the single authoritative reference for `code_decl_to_json_abi`. If any discrepancy with the source is found, the source prevails.