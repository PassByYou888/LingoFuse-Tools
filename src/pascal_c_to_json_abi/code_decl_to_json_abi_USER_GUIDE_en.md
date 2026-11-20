# code_decl_to_json_abi User Guide (v3 · Chinese expanded edition, no Markdown artifacts)

> *English translation of [code_decl_to_json_abi_USER_GUIDE.md](code_decl_to_json_abi_USER_GUIDE.md).*

> **Document positioning** — this is the **user-facing operations manual** for the `code_decl_to_json_abi` toolchain. It covers: GUI, CLI and MCP front-end operation, the programmatic interface, the support matrix and artifact list for every target language, the global prerequisite of the bridge program, how to read the interface contracts, build-and-deploy practice, and FAQs and troubleshooting.
>
> **The major change in this version (relative to the English original v3)** — the new version **no longer generates `_readme.md` companion documents**. The `.md` generation feature has been removed from the toolchain. In its place:
>
> - **the comment block at the top of each generated source file** carries the interface description;
> - **the stub signature** (`internal_call_<Api>`) is itself the most authoritative interface contract;
> - **`CMakeLists.txt` and `test_main___.cpp`** carry the C++ side's build and call contracts;
> - **`launch_bridge.ps1` and `setup_*_tests.ps1`** carry the bridge and test-environment preparation contracts;
> - **each language's test driver** (`*_main_test___.*`) is itself the most authoritative call example.
>
> So **Chapter 3** of this version changes from the English original's "read the `.md`" to "**where to read the interface contracts**", and a complete "**Build and deployment in practice**" chapter (Chapter 14) has been added to make up for the information density lost when `.md` was removed.
>
> **The single most important rule at runtime** — **the bridge program (`bridge.py` / `bridge.exe`) must always be running**. Every generated caller-side artifact ultimately depends on it. See Chapter 2.
>
> **The single most important rule after generation** — **read the contract from the code itself, the CMake script, the test driver and the stub signature**. The `internal_call_<Api>` signature is the final definition of the interface; the `CMakeLists.txt` target name is the final definition of the build; `test_main___.cpp` is the most authoritative call example. See Chapter 3.
>
> **The MCP change in v3** — the MCP API has been reduced from 24 tools to **exactly three tools**:
>
> - `CodeDeclToJsonAbi_Generate(Source, Language)`
> - `CodeDeclToJsonAbi_ListFiles()`
> - `CodeDeclToJsonAbi_GetFile(FileName)`
>
> A single `Generate` call now produces the code for **every target language** in one shot, plus the CMake build scripts and the C++ test driver.
>
> **The extra content in this Chinese expanded edition** — on top of the English original v3: the complete language support matrix (covering all 20+ target languages registered in the `.lpr`), the artifact list and example file names for each target language, a behavior description for each generator unit, the bridge program's lifecycle and the three process layouts in detail, more troubleshooting entries, more complete MCP tool call examples, minimal and complete embedding examples of the programmatic interface, a quick reference for error codes and exception types, a glossary, **build and deployment in practice**, **a complete walkthrough of a typical workflow**, and **a cross-reference of interface-contract sources**. This edition is **substantially larger** than the English original.

---

## Table of contents

### Part I — Project overview

- [Chapter 1  Project overview](#chapter-1--project-overview)
- [Chapter 2  Global prerequisite: the bridge program must always be running](#chapter-2--global-prerequisite-the-bridge-program-must-always-be-running)
- [Chapter 3  Where to read the interface contracts](#chapter-3--where-to-read-the-interface-contracts)

### Part II — Environment and preparation

- [Chapter 4  Environment preparation](#chapter-4--environment-preparation)

### Part III — Operating the three front ends

- [Chapter 5  GUI operation guide](#chapter-5--gui-operation-guide)
- [Chapter 6  Command-line operation guide](#chapter-6--command-line-operation-guide)
- [Chapter 7  Agent (MCP-API) operation guide — the three tools](#chapter-7--agent-mcp-api-operation-guide--the-three-tools)

### Part IV — MCP tool provider architecture

- [Chapter 8  How the MCP tool provider unit is built](#chapter-8--how-the-mcp-tool-provider-unit-is-built)

### Part V — Programmatic interface

- [Chapter 9  Programmatic interface](#chapter-9--programmatic-interface)

### Part VI — Artifacts, protocol and safety

- [Chapter 10  Artifact list](#chapter-10--artifact-list)
- [Chapter 11  JSON safety and stability](#chapter-11--json-safety-and-stability)

### Part VII — Language support and extension

- [Chapter 12  Language support: today and tomorrow](#chapter-12--language-support-today-and-tomorrow)

### Part VIII — FAQ and troubleshooting

- [Chapter 13  Frequently asked questions](#chapter-13--frequently-asked-questions)

### Part IX — Build and deployment in practice

- [Chapter 14  Build and deployment in practice](#chapter-14--build-and-deployment-in-practice)
- [Chapter 15  A complete walkthrough of a typical workflow](#chapter-15--a-complete-walkthrough-of-a-typical-workflow)

### Appendices

- [Appendix A — The artifact list of one run](#appendix-a--the-artifact-list-of-one-run)
- [Appendix B — Quick reference for error codes and exception types](#appendix-b--quick-reference-for-error-codes-and-exception-types)
- [Appendix C — Command-line argument quick reference](#appendix-c--command-line-argument-quick-reference)
- [Appendix D — MCP tool parameter quick reference](#appendix-d--mcp-tool-parameter-quick-reference)
- [Appendix E — Language support matrix](#appendix-e--language-support-matrix)
- [Appendix F — Cross-reference of interface-contract sources](#appendix-f--cross-reference-of-interface-contract-sources)
- [Appendix G — Quick reference for artifact file suffixes by target language](#appendix-g--quick-reference-for-artifact-file-suffixes-by-target-language)
- [Appendix H — Glossary](#appendix-h--glossary)

---

## Chapter 1  Project overview

### 1.1 What this tool is

`code_decl_to_json_abi` is a **cross-language code generator**.

You give it one Pascal unit (`.pas` / `.pp` / `.p`) or one C header (`.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx`) and it will:

1. **parse** every top-level function/procedure declaration in the file;
2. **normalize** them into an intermediate model (the LV1 Model);
3. **generate** a complete set of **HTTP POST + JSON** interface code, covering:
   - the **service side**: registers the functions as LingoFuse Call APIs, receives JSON requests and returns JSON responses;
   - the **caller side**: turns a local function call into an HTTP POST to the bridge program;
   - **test programs**: a service-side self-test program plus an end-to-end caller-side test program;
   - **build scripts**: the CMake script for the C++ target plus the C++ test driver;
   - **environment preparation scripts**: the bridge launch script plus a test-environment setup script for each language.

**In one sentence**: you write one Pascal unit or one C header, and this tool lays out every cross-language, cross-process HTTP/JSON interface for you — including the C++ side's CMake build script and the complete test suite for each language.

### 1.2 Which source languages are supported

**Only two**:

| Source language | File extensions |
|--------|-----------|
| Pascal | `.pas` / `.pp` / `.p` |
| C | `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` |

**The key distinction**:

- **Source language** = the language you input = `pascal` or `c`.
- **Target language** = the language of the generated artifacts = any of the languages in §1.3 below.

**This is the mistake beginners make most often**: passing a target language (`python`, `cpp`, `csharp`, `javascript`) to an MCP tool as the source language. It is rejected immediately.

### 1.3 Which target languages are supported

The target languages actually registered by this toolchain (per the `uses` list in the `.lpr` file) cover the following 20+:

| # | Target language | Service | Caller | Test programs | Build scripts | Notes |
|:-:|----------|:------:|:------:|:--------:|:--------:|------|
| 1 | **Pascal** | ✅ | ✅ | ✅ | — | native FPC / Delphi support |
| 2 | **Python** | ✅ | ✅ | ✅ | — | depends on `requests` |
| 3 | **C++** | ✅ | ✅ | ✅ | ✅ | CMake + test driver |
| 4 | **C#** | ✅ | ✅ | ✅ | — | .NET 8+ |
| 5 | **JavaScript** (browser) | ❌ | ✅ | ✅ (HTML) | — | self-contained HTML test page |
| 6 | **Node.js** | ✅ | ✅ | ✅ | ✅ | needs `lingofuse-js` |
| 7 | **TypeScript** | ✅ | ✅ | ✅ | ✅ | needs `lingofuse-ts` + `tsx` |
| 8 | **PHP** | ❌ | ✅ | ✅ | — | plain `curl` / `fopen` |
| 9 | **Rust** | ✅ | ✅ | ✅ | — | `ureq` + `reqwest` + `tokio` |
| 10 | **Go** | ✅ | ✅ | ✅ | — | standard library |
| 11 | **Java** | ✅ | ✅ | ✅ | — | JDK 11+ + Jackson |
| 12 | **Delphi** | ❌ | ✅ | ✅ | — | native RTL |
| 13 | **Dart** | ✅ | ✅ | ✅ | — | `http` package |
| 14 | **Swift** | ✅ | ✅ | ✅ | — | Foundation + `Dispatch` |
| 15 | **Ruby** | ✅ | ✅ | ✅ | — | `lingofuse` gem |
| 16 | **Zig** | ✅ | ✅ | ✅ | ✅ | `std` standard library |
| 17 | **Erlang** | ✅ | ✅ | ✅ | ✅ | `httpc` standard library |
| 18 | **Fortran** | ✅ | ✅ | ✅ | ✅ | `iso_c_binding` |
| 19 | **Julia** | ✅ | ✅ | ✅ | ✅ | `LingoFuse` + `JSON3` |
| 20 | **R** | ✅ | ✅ | ✅ | ✅ | `lingofuse` + `jsonlite` + `httr` + `future` |
| 21 | **Bridge launch script** | — | — | — | ✅ | `launch_bridge.ps1` |

> **Important**: the complete build commands, dependencies, environment variables and troubleshooting table for each target language are **no longer carried by a generated `.md`** (the new version removed `.md` generation). In its place:
>
> - **interface contracts** are read from the stub signatures and the top comment block of the generated code (see Chapter 3);
> - **build commands** are read from the CMake script, `setup_*_tests.ps1` and Chapter 14 of this document;
> - **call examples** are read from each language's test driver (`*_main_test___.*`);
> - **troubleshooting** is in Chapter 13 and Chapter 14 of this document.

### 1.4 How many artifacts

**The count varies with the number of supported functions in the model and with the target languages covered.** Taking the five-language scope (Pascal / Python / C++ / C# / JavaScript) as the example:

| No. | Artifact |
|:----:|------|
| 1 | `<U>_http_json_service_unit.pas` |
| 2 | `<U>_http_json_call_unit.pas` |
| 3 | `<U>_http_json_service_main_test___.pas` |
| 4 | `<U>_http_json_call_main_test___.pas` |
| 5 | `<U>_http_json_call.js` |
| 6 | `<U>_http_json_call_test.html` |
| 7 | `<U>_http_json_service.py` |
| 8 | `<U>_http_json_call.py` |
| 9 | `<U>_http_json_service_main_test___.py` |
| 10 | `<U>_http_json_call_main_test___.py` |
| 11 | `<U>_http_json_service.hpp` |
| 12 | `<U>_http_json_service.cpp` |
| 13 | `<U>_http_json_call.hpp` |
| 14 | `<U>_http_json_call.cpp` |
| 15 | `CMakeLists.txt` |
| 16 | `test_main___.cpp` |
| 17 | `<U>_http_json_service.cs` |
| 18 | `<U>_http_json_call.cs` |
| 19 | `<U>_http_json_service_main_test___.cs` |
| 20 | `<U>_http_json_call_main_test___.cs` |

**20 in total** (the English original v3 reported "26" because it included READMEs — 7 of those were README files; now that the READMEs are gone, 19–20 pure artifacts remain, depending on whether `test_main___.cpp` and `CMakeLists.txt` are counted separately).

If the model triggers more target languages (for example Rust, Go and Java are enabled together), the artifact count grows accordingly, and can reach 60+. **The true artifact list of each run is whatever the MCP `Generate` return value or the GUI's "Final Source" list says.**

### 1.5 The three front ends

All three share **one single GUI form**; there are no parallel implementations:

| Front end | Trigger condition | Target user |
|------|----------|----------|
| **GUI** | started with no arguments | human engineers |
| **CLI** | started with ≥1 argument | build scripts, CI |
| **MCP** | runs automatically once the GUI starts | Agents, remote tools |

### 1.6 The three MCP tools

| # | Tool | Purpose |
|:-:|------|------|
| 1 | `CodeDeclToJsonAbi_Generate(Source, Language)` | parse + generate every artifact, and return the file list |
| 2 | `CodeDeclToJsonAbi_ListFiles()` | return the list of artifact file names |
| 3 | `CodeDeclToJsonAbi_GetFile(FileName)` | return the complete content of one file by name |

### 1.7 The two-step workflow

```
Step 1: Generate(Source, "pascal" | "c")   → {"status":"ok","count":20,"files":[...]}
Step 2: ListFiles()                        → {"status":"ok","count":20,"files":[...]}
        GetFile("CMakeLists.txt")          → {"status":"ok","name":"...","text":"..."}
```

**There is no step 3**. There is no intermediate inspection tool. **There are no README artifacts**.

### 1.8 Eight rules you must remember

1. **`Language` accepts only `"pascal"` or `"c"`**. `"python"`, `"cpp"`, `"csharp"` and `"javascript"` are **target** languages, not source languages. Passing one is an immediate error.
2. **`Generate` produces every target in one call**. There is no "call per target" interface. If you want the Python service, call `GetFile` by name from the list after `Generate`.
3. **`ListFiles` and `GetFile` are pure reads**. They rerun no generator. To refresh the output, call `Generate` again.
4. **One `Generate` corresponds to one source text**. A repeated call replaces the whole session.
5. **The service side and the caller side must come from the same source text**.
6. **A type outside the three ABI families causes the whole function to be silently dropped** (see §4.3).
7. **`int64` / `uint64` lose precision in JavaScript clients**, because JS `Number` is an IEEE-754 double (see §11.5).
8. **Every generated caller-side artifact requires the bridge program to be running** (see Chapter 2).

### 1.9 Where the interface contracts are (the core change in this version)

The English original v3's "read the `.md`" rule has been retired. **This version has no `.md`**. Interface contracts must be read from the following entities:

| Contract kind | Authoritative source |
|----------|----------|
| **API name** | the registration table in `<U>_http_json_service_*` (the first argument of `LF_RegisterCallEx(...)`) |
| **Parameter types and count** | the signature of the `internal_call_<Api>` stub |
| **Return type** | the return declaration of the `internal_call_<Api>` stub |
| **Wire request shape** | `{ "args": [v1, v2, ...] }` (fixed, see Chapter 10) |
| **Wire response shape** | `{ "code": 0, "result": ... }` / `{ "code": -1, "error": ... }` (fixed, see Chapter 10) |
| **Call example** | each language's `*_main_test___.*` test driver |
| **Build command** | C++: the target names in `CMakeLists.txt`; Python: run with `python` directly; others: see Chapter 14 |
| **Environment variables** | the top comment block of the generated code |
| **Service endpoint name** | the `HTTP_SERVICE_ENDPOINT` / `ENDPOINT` constants (syntax differs per language, see Chapter 10) |
| **Bridge program name** | `__lf_http_bridge__` / `__lf_outbound_post__` (these defaults are the same in every language) |

**Chapter 3 expands each of these nine contract kinds.**

### 1.10 Recommended reading order

| Your role | Suggested reading order |
|----------|--------------|
| **First-time user** | Chapter 1 → 2 → 3 → 4 → 5 (GUI) → 14 (build and deploy) |
| **CI / build engineer** | Chapter 1 → 2 → 6 (CLI) → 14 |
| **Agent developer** | Chapter 1 → 7 (MCP) → 8 (architecture) |
| **Want to embed the generator** | Chapter 1 → 9 (programmatic interface) |
| **Ops / deployment** | Chapter 2 → 10 (artifact list) → 14 → 13 (FAQ) |

---

## Chapter 2  Global prerequisite: the bridge program must always be running

> **This is the most important runtime prerequisite. Read this chapter before any other chapter.**

### 2.1 What the bridge program is

**`bridge.py` (or the compiled `bridge.exe`) is the HTTP↔RPC forwarding utility provided by LingoFuse.**

Its only job is: **translate an HTTP request into an internal LingoFuse call, and translate the return value back into an HTTP response.**

```
HTTP client  ──HTTP POST──▶  bridge.py / bridge.exe  ──LF_Call──▶  service
HTTP client  ◀─HTTP response── bridge.py / bridge.exe ◀──LF return── service
```

### 2.2 Why it must always be running

**Every caller-side artifact generated by this tool** (Pascal / Python / C++ / C# / JavaScript / Node.js / TypeScript / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Zig / Erlang / Fortran / Julia / R) and **the bundled HTML test page** do **not** talk to the service directly. They all go through the bridge program:

| Caller-side artifact | How it communicates |
|-----------|----------|
| Pascal caller | internally uses `LFHttpPost` through LingoFuse to reach the bridge |
| Python caller | uses `requests.post(...)` to send the request straight to the bridge's HTTP port |
| C++ caller | reaches the bridge through the LingoFuse C ABI |
| C# caller | reaches the bridge through the LingoFuse .NET binding |
| JavaScript caller | uses `fetch(...)` to POST straight to the bridge's HTTP port |
| Node.js caller | uses `fetch(...)` (Node 18+) to POST straight to the bridge |
| TypeScript caller | same as Node.js |
| PHP caller | uses `curl_*`, or `fopen` + `stream_get_meta_data` |
| Rust caller | `ureq` for sync, `reqwest` + `tokio` for async |
| Go caller | uses the `net/http` standard library |
| Java caller | uses `java.net.http.HttpClient` |
| Delphi caller | uses `System.Net.HttpClient` |
| Dart caller | uses `package:http` |
| Swift caller | uses `URLSession` |
| Ruby caller | uses the `net/http` standard library |
| Zig caller | reaches the bridge through LingoFuse |
| Erlang caller | uses the `httpc` standard library |
| Fortran caller | through the LingoFuse C ABI |
| Julia caller | through LingoFuse `future` / `call` |
| R caller | through LingoFuse `lf_call` |
| **HTML test page** | same as the JavaScript caller |

**As long as the bridge program is not running, every caller side and test page above fails immediately.** Typical symptoms:

- `EHTTPCallError: ... Network error` (Pascal)
- `HTTPCallError: Network error` (Python)
- `HTTPCallError: ... (code=-1, http_status=0)` (C++ / C# / Java)
- `Failed to fetch` / CORS errors (JS / browser)
- `Connection refused` (manual `curl` test)
- `ureq::Error::Transport` / `reqwest::Error` (Rust)
- `Net::OpenTimeout` / `Net::ReadTimeout` (Ruby)
- `TimeoutError` / `ConnectionError` (Python `requests`)

### 2.3 Lifecycle rules for the bridge program

| Rule | Explanation |
|------|------|
| **Must be started separately** | the bridge is a standalone process. It runs **separately** from your caller and your service. |
| **Must be resident** | as long as you intend to call an interface or open the test page, the bridge **must keep running**. |
| **Do not crowd it into the same terminal as the caller/service** | start the bridge in an **independent terminal**. |
| **Must be ready before the caller** | recommended start order: **service → bridge → caller**. |
| **A restart recovers it** | after the bridge crashes or is killed, simply run it again; the caller does not need a restart. |
| **Do not restart when you don't need to** | the bridge supports `Overlap_Connection`, so a restart does not disturb services that are already ready. |

### 2.4 The recommended three-process layout

```
Terminal 1 (service):  start the generated service (Pascal / Python / C++ / C# / Rust / ...)
Terminal 2 (bridge):   python3 bridge.py --endpoint <same endpoint as the service> --port 8081 --no-precheck
Terminal 3 (caller):   start the generated caller, or double-click the HTML test page
```

**The bridge must stay resident in the foreground of terminal 2.** Only after you see it print its HTTP listening log may you start calling.

### 2.5 How the three processes depend on each other

```
         ┌─────────────────┐
         │  Service process │  ← must be online
         │  (Service)       │
         └────────┬────────┘
                  │ LF_Call
                  ▼
         ┌─────────────────┐
         │  Bridge process  │  ← must be online, resident in the foreground
         │  (bridge.py)     │
         └────────┬────────┘
                  │ HTTP POST
                  ▼
         ┌─────────────────┐
         │  Caller process  │  ← started on demand
         │  (Call)          │
         └─────────────────┘
```

**None of the three can be missing**:

- **service only, no bridge** → the caller reports `Network error`.
- **bridge only, no service** → the bridge reports the API as unavailable / times out.
- **all three present but the start order is wrong** → restart in the order "service → bridge → caller".

### 2.6 Stages that do not need the bridge program

**The bridge program is not needed during the following stages**:

| Stage | Bridge needed? |
|------|:----------------:|
| Generating code in the GUI | ❌ no |
| Generating code from the CLI | ❌ no |
| MCP calls to `Generate` / `ListFiles` / `GetFile` | ❌ no |
| Reading the interface contracts from the code / CMake / test driver | ❌ no |
| Compiling the generated service-side code | ❌ no |
| Compiling the generated caller-side code | ❌ no |
| **Running** the generated service-side code | ❌ no |
| **Running** the generated caller-side code | ✅ **yes** |
| **Opening** the HTML test page | ✅ **yes** |
| **Running** a C++ / C# / Rust / ... test driver | ✅ **yes** |

### 2.7 Common misconceptions

- ❌ "Once the code is generated I can call it directly." → **No.** The bridge must be running.
- ❌ "I only generate code in the GUI, so I don't need the bridge." → **The generation stage truly does not need it.** But as soon as you **run** the generated code or open the test page, you do.
- ❌ "The bridge and the service are alternatives." → **Both must run at the same time.**
- ❌ "The bridge only needs to run once, then I can close it." → **Closing the bridge closes the entire HTTP↔RPC path.**
- ❌ "The MCP service and the bridge are the same thing." → **No.** The MCP service lets an Agent call this tool to generate code; the bridge lets the generated code call the service. **They cannot substitute for each other.**
- ❌ "Without a `.md` there's no way to know how to build." → **No.** The CMake script, `setup_*_tests.ps1`, the test drivers, the stub signatures and the top comment blocks of the generated code together carry everything the `.md` used to hold. See Chapter 3 and Chapter 14.

> **Remember one sentence: the bridge program (`bridge.py` / `bridge.exe`) is the forwarder, and it must always be running.**

### 2.8 Quick reference for the bridge launch command

```bash
# simplest form (assuming bridge.py is on PATH)
python3 bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck

# with an explicit Python executable
python3 /path/to/bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck

# Windows
python.exe bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck

# using the generated launch script (the toolchain emits launch_bridge.ps1)
.\launch_bridge.ps1 -PyDir D:\LingoFuse\python\lingofuse -UnitName <UnitName>
```

**Argument reference**:

| Argument | Explanation |
|------|------|
| `--endpoint` | the LingoFuse endpoint **identical** to the service side's |
| `--port` | the bridge's HTTP listening port. Default 8081 |
| `--no-precheck` | skip the API pre-check at startup. **Strongly recommended**, because the pre-check cache updates with a delay |
| `--bridge-app` | override the bridge's default LingoFuse App name (default `__lf_http_bridge__`) |
| `--bridge-api` | override the bridge's default LingoFuse API name (default `__lf_outbound_post__`) |

---

## Chapter 3  Where to read the interface contracts

> **This version has no `.md` artifacts.** Interface contracts must be read from the generated code, the CMake script, the test drivers and the stub signatures. This chapter expands each of the nine contract kinds.

### 3.1 Reading parameter and return types from the stub signature

**The stub is the final definition of the interface.** Every supported routine corresponds to one `internal_call_<Api>` stub. **The stub's signature = the exact dual of the wire contract.**

#### 3.1.1 The Pascal stub

```pascal
// generated file: <U>_http_json_service_unit.pas
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
begin
  // TODO: call the real function, for example:
  //   Result := Add(a, b);
  Result := 0;
end;
```

**How to read it**:

- **API name**: `Add` (the two `Add` segments of `internal_call_Add_Add` denote the original routine name and the normalized ApiName respectively).
- **Parameters**: `a: Int64`, `b: Int64`.
- **Return**: `Int64`.

#### 3.1.2 The Python stub

```python
# generated file: <U>_http_json_service.py
def internal_call_Add(a: int, b: int) -> int:
    """
    HTTP/JSON API: Add.

    TODO: replace the body with a call to the real implementation.
    Suggested call: Add(a, b)
    """
    # TODO: implement this stub.
    return 0
```

**How to read it**:

- **API name**: `Add`.
- **Parameters**: `a: int`, `b: int`.
- **Return**: `int`.
- **Suggested call form**: `Add(a, b)`.

#### 3.1.3 The C++ stub

```cpp
// generated file: <U>_http_json_service.cpp
std::int64_t internal_call_Add(std::int64_t a, std::int64_t b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b);
    return 0;
}
```

#### 3.1.4 The C# stub

```csharp
// generated file: <U>_http_json_service.cs
public static long Add(long a, long b)
{
    // TODO: replace the body with a call to the real implementation.
    // Suggested call: Add(a, b);
    return 0;
}
```

#### 3.1.5 The Rust stub

```rust
// generated file: <U>_http_json_service_rs.rs
pub fn internal_call_Add(a: i64, b: i64) -> i64 {
    let _ = (a, b);
    // TODO: replace this body with the real implementation.
    0
}
```

#### 3.1.6 The Go stub

```go
// generated file: <U>_http_json_service_go.go
func internalCallAdd(a int64, b int64) (int64, error) {
    _ = a
    _ = b
    // TODO: replace this body with the real implementation.
    return 0, nil
}
```

#### 3.1.7 The `extract_*` helpers on the Rust service side

The Rust service-side stub signature reflects the parameter types directly. A set of `extract_i64` / `extract_f64` / `extract_string` helpers is also generated, to convert JSON values into Rust types. **The return type of these helpers is exactly the set of JSON types the wire parameter accepts**:

| Helper | Accepts JSON type | Rejects JSON type |
|----------|----------------|----------------|
| `extract_i64` | integer | float (reports "not an integer") |
| `extract_f64` | integer or float | string, boolean |
| `extract_string` | string | number, boolean |

**Conclusion**: the stub signature maps directly onto the wire types — `i64` → JSON integer; `f64` → JSON number; `&str` → JSON string.

### 3.2 Reading API names from the registration table

**The registration table is the sole authority for API names.** The generated registration function calls `LF_RegisterCallEx` / `app.registerCall` / `app.register_call` in turn (syntax differs per language). **The first argument is the wire API name.**

#### 3.2.1 Pascal registration

```pascal
// generated file: <U>_http_json_service_unit.pas
procedure RegisterAllHTTPJsonAPIs(App: TAppHnd___);
begin
  LF_RegisterCallEx(App, 'Add',  'Adds two integers and returns the sum.', nil, @Callback_Add);
  LF_RegisterCallEx(App, 'Sub',  'Subtracts b from a.',                  nil, @Callback_Sub);
end;
```

#### 3.2.2 Python registration

```python
# generated file: <U>_http_json_service.py
def register_all_http_json_apis(app):
    app.register_call(
        'Add',
        _make_call_adapter(internal_call_Add, 'Add', ['a', 'b'], [0, 0]),
        'Adds two integers and returns the sum.',
    )
    app.register_call(
        'Sub',
        _make_call_adapter(internal_call_Sub, 'Sub', ['a', 'b'], [0, 0]),
        'Subtracts b from a.',
    )
```

#### 3.2.3 C++ registration

```cpp
// generated file: <U>_http_json_service.cpp
void register_all_http_json_apis(lingofuse::App& app) {
    if (!app.registerCall("Add", "Adds two integers and returns the sum.",
                          nullptr, Callback_Add)) { /* ... */ }
    if (!app.registerCall("Sub", "Subtracts b from a.",
                          nullptr, Callback_Sub)) { /* ... */ }
}
```

#### 3.2.4 Rust registration

```rust
// generated file: <U>_http_json_service_rs.rs
pub fn register_all_apis(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    app.register_call("Add", "Adds two integers and returns the sum.", cb_Add)?;
    app.register_call("Sub", "Subtracts b from a.", cb_Sub)?;
    Ok(())
}
```

**Conclusion**: `'Add'` / `'Sub'` etc. are the HTTP path segment `<api-name>`; the URL looks like `http://.../<app-name>/Add`.

### 3.3 Reading language-specific configuration from the top comment block of the generated code

**Every generated source file has a fixed comment block at the top** describing that language's dependencies, build, run method and wire protocol. **This is the most important first-hand information source now that the `.md` is gone.**

#### 3.3.1 The C++ service top comment (excerpt)

```cpp
// Auto-generated by http_cpp_abi_service_generator_tool.pas.
// Source model unit: Calculator.
// Do not edit by hand unless you know what you are doing.
//
// Wire protocol (HTTP/JSON path, both directions):
//   request  = JSON object
//              { "args": [v1, v2, ...] }     positional arguments
//              { "a": v1, "b": v2, ... }     named arguments
//   response = JSON object
//              { "code": 0,  "result": ... }  on success
//              { "code": -1, "error":  ... }  on failure
//
// This header does NOT define LF_CDECL. That macro is provided by
// LingoFuse.h (pulled in by LingoFuse.hpp). ...
```

**How to read it**:

- the **wire protocol** (request shape, response shape);
- the **dependency relationship** ("LingoFuse.h comes from LingoFuse.hpp");
- the **prohibitions** ("do not redefine LF_CDECL").

#### 3.3.2 The Rust caller top comment (excerpt)

```rust
// Auto-generated by http_rust_abi_call_generator_tool.pas.
// Source model unit: Calculator.
// ...
// Dependencies (add to Cargo.toml):
//   ureq = "2"
//   reqwest = { version = "0.12", features = ["json"] }
//   tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }
//   serde_json = "1"
//
// Usage as a crate root:
//   Copy this file to `src/main.rs` (or `src/lib.rs`) and call
//   the generated functions from `fn main()` (sync) or
//   `#[tokio::main] async fn main()` (async).
```

**How to read it**:

- the **`Cargo.toml` dependencies** (copy-paste ready);
- the **usage mode** (crate root or submodule);
- the **sync / async entry** (`fn main()` vs `#[tokio::main] async fn main()`).

#### 3.3.3 The Zig caller top comment (excerpt)

```zig
// Auto-generated by http_zig_abi_call_generator_tool.pas (v14).
// Source model unit: Calculator.
// ...
// The generated code reaches the service THROUGH the LingoFuse mesh,
// using bridge.py as the LingoFuse-to-HTTP bridge:
//
//   Zig caller  --LF-->  bridge.py  --HTTP-->  remote service
//
// The caller MUST call lf.framework.init() before the first remote
// call, and lf.framework.deinit() on exit.
```

**How to read it**:

- the **process topology** (Zig → bridge → service);
- the **lifecycle contract** (must `init()` first, `deinit()` before exit).

### 3.4 Reading the build contract from CMakeLists.txt

**`CMakeLists.txt` is the sole authority for the C++ build.** It defines:

1. the **target names**: `<U>_http_json_service` and `<U>_http_json_call_test`.
2. the **source files**: `<U>_http_json_service.cpp`, `<U>_http_json_call.cpp`, `test_main___.cpp`, `LingoFuse.c`.
3. the **include directories**: the project directory + `LINGOFUSE_CPP_LIB_DIR`.
4. the **linked libraries**: `ws2_32` on Windows; `Threads::Threads` + `${CMAKE_DL_LIBS}` elsewhere.
5. the **C++ standard**: 17.
6. the **required variable**: `LINGOFUSE_CPP_LIB_DIR` (a cache PATH, empty by default).

#### 3.4.1 Key excerpt

```cmake
cmake_minimum_required(VERSION 3.15)
project(<U>_http_json_test C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(LINGOFUSE_CPP_LIB_DIR "" CACHE PATH "LingoFuse C++ library directory")

if(NOT EXISTS "${LINGOFUSE_CPP_LIB_DIR}/LingoFuse.h")
    message(FATAL_ERROR ...)
endif()

set(LINGOFUSE_C_SOURCE    "${LINGOFUSE_CPP_LIB_DIR}/LingoFuse.c")
set(LINGOFUSE_INCLUDE_DIR "${LINGOFUSE_CPP_LIB_DIR}")
set(PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

# Service target
add_executable(<U>_http_json_service
    "${PROJECT_DIR}/<U>_http_json_service.cpp"
    "${LINGOFUSE_C_SOURCE}"
)
target_include_directories(<U>_http_json_service PRIVATE
    "${PROJECT_DIR}"
    "${LINGOFUSE_INCLUDE_DIR}"
)

# Call test target
add_executable(<U>_http_json_call_test
    "${PROJECT_DIR}/test_main___.cpp"
    "${PROJECT_DIR}/<U>_http_json_call.cpp"
    "${LINGOFUSE_C_SOURCE}"
)
```

#### 3.4.2 How to read it

- **`-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf` must be set**, otherwise configure immediately hits `FATAL_ERROR`.
- **two executables**: `<U>_http_json_service` and `<U>_http_json_call_test`.
- **`test_main___.cpp` and `<U>_http_json_call.cpp` belong to the same target** — they must be compiled together.
- **`LingoFuse.c` belongs to both targets** — it is a C source, so the `project()` in CMake must declare `C CXX`.

### 3.5 Reading the call example from test_main___.cpp

**`test_main___.cpp` is the most authoritative example of how to call.** It calls each generated function in turn and prints `OK` / `FAILED`.

#### 3.5.1 Key excerpt

```cpp
int main() {
    lingofuse::LibraryLoader loader;

    lingofuse::resetPrepare();
    lingofuse::prepareClient("ipc:<U>_http_json", nullptr);
    if (lingofuse::prepareDone() != 1) {
        std::printf("LingoFuse init failed\n");
        return 1;
    }

    <U>::HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<U>";

    int failures = 0;

    // ---- Add [sync] ----
    {
        std::printf("  Add [sync] : ");
        try {
            auto r = <U>::Add(1, 2);
            std::printf("OK\n");
            (void)r;
        } catch (const <U>::HTTPCallError& e) {
            std::printf("FAILED: %s (code=%d, http=%d)\n",
                e.what(), e.code, e.http_status);
            ++failures;
        }
    }

    // ---- Add [async] ----
    {
        std::printf("  Add [async]: ");
        auto p = std::make_shared<std::promise<<U>::AddAsyncResult>>();
        auto fut = p->get_future();
        bool submit_ok = true;
        try {
            <U>::Add_Async(1, 2,
                [p](auto r) {
                    try { p->set_value(std::move(r)); } catch (...) {}
                });
        } catch (const std::exception& e) {
            std::printf("FAILED: submit threw: %s\n", e.what());
            ++failures;
            submit_ok = false;
        }
        // ... wait on the future
    }

    lingofuse::exitMainThread();
    lingofuse::shutdown();
    return failures == 0 ? 0 : 1;
}
```

#### 3.5.2 How to read it

- **the argument of `prepareClient` is the `ENDPOINT`**: `"ipc:<U>_http_json"`.
- **`prepareDone()` must return 1**, otherwise the framework has already started or has failed.
- **the default value of `HTTP_CALL_BASE_URL` is `"http://127.0.0.1:8081/<U>"`**, matching the bridge port.
- **the sync call signature**: `<U>::Add(1, 2)` — returns the result directly, throws an exception on failure.
- **the async call signature**: `<U>::Add_Async(1, 2, callback)` — returns immediately, the result arrives through the callback.
- **the only failure shape**: `HTTPCallError`.

### 3.6 Reading the call example from each language's test driver

**The test driver is the call example.** Each `*_main_test___.*` file calls every API in order and prints `OK` / `FAILED`.

| Language | Test driver file name | Core call form |
|------|----------------|--------------|
| Pascal | `<U>_http_json_call_main_test___.pas` | `Test_<Api>_Sync;` / `Test_<Api>_Async;` |
| Python | `<U>_http_json_call_main_test___.py` | `call_module.Add(0, 0)` / `await call_module.Add_async(0, 0)` |
| Rust | `<U>_http_json_call_main_test___.rs` | `call::Add(0, 0)` / `call::Add_async(0, 0).await` |
| Go | `<U>_http_json_call_main_test.go` | `Add(0, 0)` / `AddAsync(ctx, 0, 0)` |
| Java | `HttpJsonCallTest.java` | `callApi(baseUrl, "Add", List.of(0, 0))` |
| Ruby | `<U>_http_json_call_main_test___.rb` | `api.Add(0, 0)` |
| R | `<U>_http_json_call_main_test___.R` | `add(0, 0)` |
| Julia | `<U>_http_json_call_main_test___.jl` | `call.Add(0, 0)` / `call.Add_async(0, 0)` |
| PHP | `<U>_http_json_call_main_test___.php` | `HttpJsonCallApi::Add(0, 0)` |
| Node.js | `<U>_http_json_call_main_test___.js` | `await api.Add(0, 0)` |
| TypeScript | `<U>_http_json_call_main_test___.ts` | `await api.Add(0, 0)` |
| Dart | `<U>_http_json_call_main_test___.dart` | `await api.Add(0, 0)` |
| Swift | `<U>_http_json_call_main_test___.swift` | `try Api.Add(0, 0)` |
| Delphi | `<U>_http_json_call_delphi_test___.dpr` | `Test_Add_Sync;` / `Test_Add_Async;` |
| Zig | `<U>_http_json_call_main_test___.zig` | `call.Add(0, 0)` / `call.Add_async(0, 0, ...)` |
| Erlang | `<U>_http_json_call_main_test___.escript` | `'add'(0, 0)` / `'add_async'(0, 0, Callback)` |
| Fortran | `<U>_http_json_call_main_test___.f90` | `add_call(0, 0)` / `add_call_async(0, 0, cb, user_data)` |
| Julia | `<U>_http_json_call_main_test___.jl` | `ModuleName.add(0, 0)` / `ModuleName.add_async(0, 0)` |

**How to read it**: replace the "0" in the test driver with your own argument values.

### 3.7 Reading the environment-preparation contract from setup_*_tests.ps1

**The test-environment setup script for each language is a `.ps1`.** They carry "what must be done before running the tests".

#### 3.7.1 `setup_js_tests.ps1` (Node.js)

Core steps:

1. verify that `node` / `npm` are on PATH.
2. check that the four generated files exist.
3. `npm install` `lingofuse-js`.
4. optionally `-RunSmoke` runs `node .\<U>_http_json_service_main_test___.js --smoke`.

#### 3.7.2 `setup_ts_tests.ps1` (TypeScript)

Core steps:

1. verify `node` / `npm`.
2. check the four generated files.
3. `npm install` `lingofuse-ts` + `tsx`.
4. optionally `-RunSmoke` runs `.\node_modules\.bin\tsx.cmd .\<U>_http_json_service_main_test___.ts --smoke`.

#### 3.7.3 `setup_zig_tests.ps1` (Zig)

Core steps:

1. verify `zig` is on PATH.
2. create the two Zig projects `zig_service_test/` and `zig_call_test/`.
3. copy the generated `.zig` files into them.
4. write `build.zig` and `build.zig.zon`.

#### 3.7.4 `setup_erlang_tests.ps1` (Erlang)

Core steps:

1. verify `erlc` / `escript` are on PATH.
2. copy `lingofuse*.beam` into `ebin/`.
3. copy `lingofuse_nif.dll` into `priv/`.
4. `erlc -o ebin <U>_http_json_service.erl <U>_http_json_call.erl`.

#### 3.7.5 `setup_fortran_tests.ps1` (Fortran)

Core steps:

1. verify `gfortran` / `g++` / `gcc`.
2. compile `lf_fortran_mod.f90`, `lf_fortran.cpp`, `LingoFuse.c`.
3. compile `<U>_http_json_service_mod.f90`, `<U>_http_json_call_mod.f90`.
4. compile the two test drivers.
5. link `service_test.exe` and `call_test.exe`.

#### 3.7.6 `setup_julia_tests.ps1` (Julia)

Core steps:

1. verify `julia`.
2. if the `lingofuse` Julia package is missing `Project.toml`, create one automatically.
3. `Pkg.develop(path=...)` installs `lingofuse` into the current project.
4. `Pkg.add("JSON3")`, `Pkg.instantiate()`, `Pkg.precompile()`.

#### 3.7.7 `setup_r_tests.ps1` (R)

Core steps:

1. verify `R` / `Rscript`.
2. verify the four R packages `lingofuse`, `jsonlite`, `httr`, `future`.
3. with `-InstallMissing`, install the missing packages automatically.
4. optionally `-RunSmoke` runs `Rscript -e "parse(<U>_http_json_service.R)"` as a pure syntax check.

**Conclusion**: if you want to prepare the environment by hand, just read the source of the corresponding `setup_*_tests.ps1`; each step is self-explanatory.

### 3.8 Reading the bridge launch contract from launch_bridge.ps1

**`launch_bridge.ps1` is the bridge launch script.** It carries:

1. the **required `-PyDir` argument** (the directory containing `bridge.py`).
2. the **optional `-UnitName` / `-Endpoint` / `-Port` / `-PyExe` / `-NoPrecheck` / `-DryRun`**.
3. **endpoint auto-derivation**: `ipc:<UnitName>_http_json`.
4. **the recommended use of `--no-precheck`**.

**Core invocation form**:

```powershell
.\launch_bridge.ps1 -PyDir D:\LingoFuse\python\lingofuse -UnitName Calculator
```

**Conclusion**: when you don't want to hand-write `python bridge.py ...`, just call this script.

### 3.9 Reading configuration defaults from the constant declarations in the generated code

**Every generated source file declares its default configuration constants.** These constants correspond directly to that language's "user-editable configuration".

#### 3.9.1 Pascal caller

```pascal
// generated file: <U>_http_json_call_unit.pas
var
  HTTP_CALL_BASE_URL: string = 'http://127.0.0.1:8081/<U>';
  HTTP_CALL_TIMEOUT_MS: Integer = 30000;
```

#### 3.9.2 Python caller

```python
# generated file: <U>_http_json_call.py
HTTP_CALL_BASE_URL = 'http://127.0.0.1:8081/<U>'
HTTP_CALL_TIMEOUT = 30.0
DEBUG_LOG = False
```

#### 3.9.3 C++ caller

```cpp
// generated file: <U>_http_json_call.cpp
std::string HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<U>";
std::string HTTP_BRIDGE_APP_NAME = "";
std::string HTTP_BRIDGE_API_NAME = "";
std::uint64_t HTTP_CALL_TIMEOUT_MS = 0;
double HTTP_CALL_DEFAULT_TIMEOUT_S = 0.0;
```

#### 3.9.4 Rust caller

```rust
// generated file: <U>_http_json_call_rs.rs
pub const DEFAULT_BASE_URL: &str = "http://127.0.0.1:8081/<U>";
pub const DEFAULT_TIMEOUT_SECS: u64 = 30;
// at runtime these can be changed through set_base_url() / set_timeout_secs()
```

#### 3.9.5 Go caller

```go
// generated file: <U>_http_json_call_go.go
const DefaultBaseURL = "http://127.0.0.1:8081/<U>"
var HTTPCallBaseURL = DefaultBaseURL
var HTTPCallTimeout = 30 * time.Second
```

#### 3.9.6 Ruby caller

```ruby
# generated file: <U>_http_json_call.rb
module CalculatorHttpJsonCall
  @base_url = "http://127.0.0.1:8081/<U>"
  @http_call_timeout = 30.0
  @debug_log = (ENV['LINGOFUSE_DEBUG'] == '1') || (ENV['LINGOFUSE_DEBUG'] == 'true')

  class << self
    attr_accessor :base_url
    attr_accessor :http_call_timeout
    attr_accessor :debug_log
    # read-only compatibility readers:
    def HTTP_CALL_BASE_URL; @base_url; end
    def HTTP_CALL_TIMEOUT; @http_call_timeout; end
    def DEBUG_LOG; @debug_log; end
  end
end
```

**Note the Ruby pitfall**: `HTTP_CALL_BASE_URL` is **read-only**. Assigning to it is parsed by Ruby as a constant assignment and raises `dynamic constant assignment`. Use `Module.base_url = "..."` instead.

#### 3.9.7 Julia caller

```julia
# generated file: <U>_http_json_call.jl
module CalculatorHttpJsonCall
  HTTP_CALL_BASE_URL::String = "http://127.0.0.1:8081/<U>"
  HTTP_BRIDGE_APP_NAME::String = ""
  HTTP_BRIDGE_API_NAME::String = ""
  HTTP_CALL_TIMEOUT_MS::Int64 = Int64(0)
  HTTP_CALL_DEFAULT_TIMEOUT_S::Float64 = 0.0
end
```

**How to access it in Julia**: `CalculatorHttpJsonCall.HTTP_CALL_BASE_URL = "..."` (direct module variable assignment).

### 3.10 Cross-reference of interface-contract sources (quick reference)

| Contract | Pascal | Python | C++ | C# | Rust | Go | Java | Ruby | R | Julia | Swift | Zig |
|------|:------:|:------:|:---:|:--:|:----:|:--:|:----:|:----:|:-:|:-----:|:-----:|:---:|
| **API name** | registration table | registration table | registration table | registration table | registration table | registration table | registration table | registration table | registration table | registration table | registration table | registration table |
| **Parameter types** | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature |
| **Return type** | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature | stub signature |
| **Call example** | test driver | test driver | `test_main___.cpp` | test driver | test driver | test driver | test driver | test driver | test driver | test driver | test driver | test driver |
| **Build command** | `fpc` + `-Fu` | `python3` | `CMakeLists.txt` | `dotnet` | `cargo` | `go` | `javac` | `ruby` | `Rscript` | `julia` | `swift` | `zig` |
| **Environment variables** | top comment | top comment | top comment | top comment | top comment | top comment | top comment | top comment | top comment | top comment | top comment | top comment |
| **Default base URL** | `HTTP_CALL_BASE_URL` | `HTTP_CALL_BASE_URL` | `HTTP_CALL_BASE_URL` | `HttpJsonCallConfig.BaseUrl` | `DEFAULT_BASE_URL` | `DefaultBaseURL` | `HTTP_CALL_BASE_URL` | `@base_url` | `HTTP_CALL_BASE_URL` | `HTTP_CALL_BASE_URL` | `baseUrl` | `DEFAULT_BASE_URL` |
| **Default timeout** | `HTTP_CALL_TIMEOUT_MS` | `HTTP_CALL_TIMEOUT` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | `HttpJsonCallConfig.HttpTimeoutSec` | `DEFAULT_TIMEOUT_SECS` | `HTTPCallTimeout` | `HTTP_CALL_TIMEOUT` | `@http_call_timeout` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | `timeout` | `DEFAULT_HTTP_TIMEOUT_SEC` |

**How to read it**: first read the stub signature to identify the interface, then read the test driver to identify the call form, then read the CMake script / `setup_*_tests.ps1` to identify the build method, and finally read the top comment block to identify the environment variables.

---

## Chapter 4  Environment preparation

### 4.1 Running the tool itself

Run `code_decl_to_json_abi` in the executable's directory. The program looks for the following files next to itself:

- `pascal_code_abi_rule.md` (Pascal prototype rules)
- `C_code_abi_rule.md` (C prototype rules)

**Their absence does not block usage**; it only disables the GUI's "rule document" buttons.

> **Note**: these two `*_rule.md` files are **not generated artifacts**. They are rule files that ship with the tool and are maintained by the tool's author; they have nothing to do with the `.md` generation feature. **What was removed is the artifact README, not these two rule files.**

### 4.2 Dependencies of the generation stage

- **The generation stage (GUI / CLI / MCP) has no extra dependencies.** The tool itself does not use the network and does not use the bridge program.
- **The bridge program and the service side are needed only when running the generated code / test pages.**

### 4.3 Dependencies of the run stage

| Component | Purpose | Required |
|------|------|:--------:|
| **Service side** (compiled from the generated `*_service_*` code) | provides the business logic | ✅ required |
| **Bridge program** (`bridge.py` or `bridge.exe`) | HTTP ↔ RPC forwarding | ✅ **must always be running** |
| **Caller side** (compiled from the generated `*_call_*` code, or the HTML test page) | issues the calls | on demand |

### 4.4 Dependencies of the C++ target

The CMake script generated by this toolchain needs:

- **CMake 3.15** or later.
- **both a C and a C++ compiler** (the project declares `project(<name> C CXX)`).
- a **LingoFuse C++ distribution directory**, given through `LINGOFUSE_CPP_LIB_DIR`. That directory must contain:
  - `LingoFuse.h`
  - `LingoFuse.c`
  - `LingoFuse.hpp`
  - `lf_io.hpp`
  - `lf_http_bridge_client.hpp`
  - `json.hpp`

### 4.5 Dependencies of the C# target

The generated C# artifacts need:

- **.NET 8.0** or later.
- the **LingoFuse .NET binding** (`LingoFuse.dll`).
- the **LingoFuse native library** (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`) and `z_ipc_*`.

### 4.6 Dependencies of the Rust target

The generated Rust artifacts need:

- **Rust 1.70+**.
- the following crates (caller side): `ureq`, `reqwest`, `tokio`, `serde_json`.
- the following crates (service side): `lingofuse`, `serde_json`.

### 4.7 Dependencies of the Go target

The generated Go artifacts need:

- **Go 1.21+**.
- caller side: the standard library only.
- service side: `github.com/PassByYou888/LingoFuse/go`.

### 4.8 Dependencies of the Java target

The generated Java artifacts need:

- **JDK 11+** (17+ recommended).
- caller side / tests: `com.fasterxml.jackson.core:jackson-databind`.
- service side: the `lingofuse` Java package.

### 4.9 Dependencies of the Node.js / TypeScript targets

- **Node.js 18+** (`fetch` has been built in since Node 18).
- caller side: the standard library only.
- service side: `lingofuse-js` (Node.js) or `lingofuse-ts` (TypeScript).
- TypeScript tests: the `tsx` command-line tool.

### 4.10 Dependencies of the Ruby target

- **Ruby 2.7+** (3.0+ recommended).
- service side: the `lingofuse` gem (a C extension toolchain is needed at compile time).
- caller side: the standard library only (`net/http`, `json`, `uri`).

### 4.11 Dependencies of the R target

- **R 4.0+**.
- service side: `lingofuse`, `jsonlite`.
- caller side: `lingofuse`, `jsonlite`, `httr`, `future`.

### 4.12 Dependencies of the Julia target

- **Julia 1.9+** (1.10+ recommended).
- Julia must be started with `--threads=2` or more.
- the `LingoFuse` and `JSON3` packages.

### 4.13 Dependencies of the Erlang target

- **Erlang/OTP 25+**.
- service side: the `lingofuse` Erlang binding (including `lingofuse_nif.dll`).

### 4.14 Dependencies of the Fortran target

- **gfortran 9+** or **ifort / flang**.
- service side: `lf_fortran_mod.f90` + `lf_fortran.cpp`.

### 4.15 Dependencies of Agent mode

Agent mode needs the LingoFuse runtime:

- `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`
- `z_ipc_*.dll` / `libz_ipc_*.so`
- an online Beacon service (`agent_main_app`)

If you use only the local GUI / CLI, **these runtime dependencies are not needed**.

### 4.16 Verifying that the dependencies are ready

| Language | Verification command |
|------|----------|
| C++ | `cmake --version`, `g++ --version` or `cl.exe` |
| Rust | `rustc --version`, `cargo --version` |
| Go | `go version` |
| Java | `java -version`, `javac -version` |
| Node.js | `node --version`, `npm --version` |
| TypeScript | `npx tsc --version` or `npx tsx --version` |
| Ruby | `ruby --version`, `gem list lingofuse` |
| R | `Rscript -e 'cat(R.version.string)'` |
| Julia | `julia --version`, `julia -e 'using Pkg; Pkg.status()'` |
| Erlang | `erl -version`, `escript --version` |
| Fortran | `gfortran --version` |
| Zig | `zig version` |
| PHP | `php --version`, `php -m | grep curl` |
| Swift | `swift --version` |
| Dart | `dart --version` |

**Only after every dependency is satisfied should you move on to Chapter 5 (GUI) or Chapter 6 (CLI).**

---

## Chapter 5  GUI operation guide

### 5.1 Starting the GUI

**Run the executable with no command-line arguments.** The GUI opens directly.

The GUI has 5 top-level tabs, progressing left to right:

```
[1. Welcome] → [2. Source Code] → [3. Source ↔ JSON] → [4. JSON ↔ Model] → [5. Final Source]
```

Each tab has a row of "previous / next" buttons at the top, and the bottom panel shows a live `DoStatus` log.

At startup the form also silently starts the **MCP service** on a background thread (see Chapter 7).

### 5.2 Page 1 — Welcome

- shows an overall introduction to the tool, its architecture and its workflow.
- buttons on the right:
  - **Pascal rule doc** — opens `pascal_code_abi_rule.md`.
  - **C rule doc** — opens `C_code_abi_rule.md`.
- **Next: Enter source code** — jumps to page 2.

### 5.3 Page 2 — Source Code

This page is where you **input the code**.

**The top toolbar**:

| Control | Purpose |
|------|------|
| **Select Language label** | click it to auto-detect the source language. |
| **Language Selector dropdown** | `Auto-detect` / `Pascal` / `C`, manual selection. |
| **Format** | keep only top-level functions and rebuild a minimal declaration set. |
| **Empty unit** | insert a minimal skeleton (Pascal or C). |
| **Test unit** | insert a complex sample covering many syntactic forms (recommended to look at first on a first run). |
| **Next: Pascal/C → JSON** | parses the current source, produces LV0 JSON, jumps to page 3. |

**Steps**:

1. paste your Pascal unit or C header into the editor.
2. if you are unsure of the language, click **Select Language** and let the tool detect it.
3. if the syntax highlighting looks wrong, select the language manually from the dropdown.
4. click **Next: Pascal/C → JSON**.

### 5.4 Page 3 — Source ↔ JSON

This page shows the **raw parse output (LV0)**.

| Button | Purpose |
|------|------|
| **Back: rebuild code from JSON** | rebuild the source code from the current JSON and write it back to page 2. |
| **Next: JSON ↔ Model** | normalize LV0 into the LV1 Model and jump to page 4. |

You can **correct the JSON by hand here** — for example if the parser classified a type wrongly, edit the string in the JSON directly and then click **Next** to continue.

### 5.5 Page 4 — JSON ↔ Model

This page shows the **normalized model JSON (LV1)**.

| Button | Purpose |
|------|------|
| **Back: JSON ↔ Model** | restore LV1 back to LV0 and write it back to page 3. |
| **Next: generate source** | generate every artifact and jump to page 5. |

**Tip**: the model JSON automatically drops unsupported types (`Boolean`, `Variant`, arrays, records, classes, interfaces, enums, sets, pointers, `Currency`, `TDateTime`, etc.). If a function does not appear in the final artifacts, it is almost always because one of its parameters or its return value carries an unsupported ABI type.

### 5.6 Page 5 — Final Source

This page has **9+ sub-tabs**, each showing **one editor** (**there is no companion `.md` editor any more**):

| Sub-tab | Content |
|--------|------|
| Pascal Service | Pascal service code |
| Pascal Call | Pascal caller code |
| JavaScript Call | JS client code |
| JavaScript Test HTML | the self-contained HTML test page |
| Python Service | Python service code |
| Python Call | Python caller code |
| C# Service | C# service code |
| C# Call | C# caller code |
| C# Test | service test driver + caller test driver |
| C++ Service | C++ service `.hpp` + `.cpp` |
| C++ Call | C++ caller `.hpp` + `.cpp` |
| **CMake** | **`CMakeLists.txt` + `test_main___.cpp`** |
| (other registered languages) | the corresponding language's code / tests |

> **The `.md` editor has been removed.** To read an interface contract inside the GUI, switch to the corresponding language's sub-tab and **read the comment block at the top of the code**. See Chapter 3.

**The files are already written to disk**: during generation every artifact is written automatically to the `<UnitName>/` subdirectory of the executable's directory.

The button at the top:

- **Back: Model JSON** — return to page 4 and keep adjusting the model.

### 5.7 Where the generated "file list" lives

**`final_source_file_ListView`** is the artifact list inside the GUI. Each entry contains:

- `Caption`: the file name.
- `SubItems[0]`: the full path.

**The MCP layer's `ListFiles` and `GetFile` read this ListView.** It is filled by `GenerateAllSourcesClick` and cleared before every generation.

### 5.8 The CMake sub-tab

The CMake sub-tab shows two fixed-name artifacts:

- `CMakeLists.txt` — the CMake build script.
- `test_main___.cpp` — the C++ caller test driver.

These two files are written to `<exe directory>/<UnitName>/`, which is exactly what the C++ build needs. **Copy them (together with the `.hpp`/`.cpp` pair) out of this tab (or from the disk directory)** and the CMake project is complete.

### 5.9 The C# Test sub-tab

The C# Test sub-tab shows two C# test artifacts:

- `<Unit>_http_json_service_main_test___.cs` — the service-side test program.
- `<Unit>_http_json_call_main_test___.cs` — the caller-side test program.

Both test programs are designed to be copied into a `dotnet new console` project as `Program.cs`, alongside the corresponding service or caller module.

### 5.10 The log panel

The bottom panel is a live `DoStatus` log. It shows: which file was just saved, which functions were dropped during normalization, and what error a generator raised. It clears itself after 5000 lines.

### 5.11 Reading interface contracts from the GUI

1. **Stub signature** → open the corresponding language's Service sub-tab and find the `internal_call_<Api>` stub.
2. **API name** → search the same file for `LF_RegisterCallEx` / `app.registerCall` / `app.register_call`.
3. **Call example** → open the corresponding language's Test sub-tab.
4. **Build command** → open the CMake sub-tab (C++), or read the top comment of the corresponding language's test driver.
5. **Default base URL / timeout** → open the corresponding language's Call sub-tab and find the constant declarations.

---

## Chapter 6  Command-line operation guide

### 6.1 Trigger condition

Command-line mode is **triggered only when at least one argument is passed**. No arguments = GUI.

The program is compiled with the console subsystem, therefore:

- double-clicking = starts the GUI (the system may pop up an extra empty console window; closing the main window ends it).
- running from the command line = every `DoStatus` message goes straight to stdout, and normal completion is returned through the exit code.

### 6.2 Syntax

```
code_decl_to_json_abi --help
code_decl_to_json_abi <input_file> <output_file>
code_decl_to_json_abi --call <input_file> <output_file>
code_decl_to_json_abi --lang <language_id> <input_file> <output_file>
```

| Argument | Explanation |
|------|------|
| `--help` / `-h` / `-?` / `/?` | print help and exit. **Recognized only as the 1st argument.** |
| `--call` / `-c` | generate the caller side. **Recognized only as the 1st argument**; the default is the service side. |
| `--lang <id>` / `-l <id>` | force the target language. Valid values: see `--list-languages`. |
| `--list-languages` / `-ll` | list every registered target language. |
| `<input_file>` | the input source file. The language is decided by the **extension**. |
| `<output_file>` | the output file. The target language is decided by the **extension** (unless `--lang` is given). |

### 6.3 Input extension → source language

| Extension | Source language |
|--------|--------|
| `.pas` / `.pp` / `.p` | Pascal |
| `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` | C |

### 6.4 Output extension → target language

| Extension | Target language | Directions supported |
|--------|----------|------------|
| `.pas` / `.pp` / `.p` | Pascal | Service + Call |
| `.py` | Python | Service + Call |
| `.hpp` / `.hh` / `.h` / `.cpp` / `.cc` / `.cxx` / `.c` | C++ (`.hpp` + `.cpp` pair + CMake) | Service + Call |
| `.cs` | C# (service code + caller code + test programs) | Service + Call + Test |
| `.js` | JavaScript | **Call side only** |
| `.node.js` / `_node.js` | Node.js | Service + Call |
| `.ts` | TypeScript | Service + Call |
| `.go` | Go | Service + Call |
| `.rs` | Rust | Service + Call |
| `.java` | Java | Service + Call |
| `.dpr` / `.dproj` | Delphi | **Call side only** |
| `.dart` | Dart | Service + Call |
| `.swift` | Swift | Service + Call |
| `.rb` | Ruby | Service + Call |
| `.zig` | Zig | Service + Call |
| `.erl` | Erlang | Service + Call |
| `.f90` | Fortran | Service + Call |
| `.jl` | Julia | Service + Call |
| `.r` / `.R` | R | Service + Call |
| `.php` | PHP | **Call side only** |

**JavaScript and PHP are caller-side only**: producing a `.js` or `.php` output without `--call` exits immediately with an argument error.

### 6.5 What each run produces

Based on the base name of `<output>` (with the extension stripped), the tool writes **into the same directory**:

- **the code file**: `<base>.xxx` (a single file for Pascal / Python / JS / C# / Rust / Go / Java / Ruby / Erlang / Julia / R; C++ produces a `<base>.hpp` + `<base>.cpp` pair).
- **the companion test program**: `<base>_main_test___.xxx` (for some languages, see Appendix G).
- **JS only**: additionally `<base>_test.html` (the self-contained test page).
- **C++ only**: additionally `CMakeLists.txt` and `test_main___.cpp` (**fixed names, no base prefix**).
- **Node.js / TypeScript only**: additionally `setup_js_tests.ps1` / `setup_ts_tests.ps1`.
- **R / Julia / Erlang / Fortran / Zig only**: additionally `setup_<lang>_tests.ps1`.
- **Bridge only**: `launch_bridge.ps1`.
- **⚠️ No `<base>_readme.md` any more.**

> **About the C++ fixed names**: `CMakeLists.txt` and `test_main___.cpp` are the exact names the C++ build requires. Generating two different units into the same directory overwrites the previous CMake file. **One unit per directory.**

### 6.6 Examples

**Service: Pascal → Pascal**

```
code_decl_to_json_abi calculator.pas calculator_service.pas
```

Artifact:

```
calculator_service.pas
```

(The test program `<base>_main_test___.pas` is produced independently by the test generator — see the artifact mapping in Appendix G; a single CLI run produces the requested side of service + call.)

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
CMakeLists.txt
test_main___.cpp
```

**Service: C → C# (project + tests)**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_project.cs
```

Artifacts (all written to the directory that holds the output file):

```
ComplexTestUnit_http_json_service.cs
ComplexTestUnit_http_json_call.cs
ComplexTestUnit_http_json_service_main_test___.cs
ComplexTestUnit_http_json_call_main_test___.cs
```

**Call: C → JavaScript (`.js` + `.html`)**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.js
```

Artifacts:

```
calculator_call.js
calculator_call_test.html
```

**Service: C → Rust**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.rs
```

Artifact:

```
calculator_service.rs
```

**Call: C → Go**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.go
```

Artifact:

```
calculator_call.go
```

**Forcing a target language (unknown extension)**

```
code_decl_to_json_abi --lang java ComplexTestUnit.h out/Calculator
```

### 6.7 Exit codes

| Exit code | Meaning |
|:------:|------|
| `0` | conversion succeeded. |
| `1` | missing or invalid arguments. |
| `2` | source parsing failed (`ParseSuccess=False`, or no usable declaration was found). |
| `3` | code generation failed (a generator returned `nil`). |
| `4` | file I/O error (read or write failed). |

### 6.8 Output messages

In command-line mode every intermediate message is written to stdout, for example:

```
Reading: ComplexTestUnit.h (1234 chars)
Output : calculator_service.hpp
Target : cpp
Mode   : service
Unit   : ComplexTestUnit
Funcs  : 28
Wrote  : calculator_service.hpp
Wrote  : calculator_service.cpp
Wrote  : CMakeLists.txt
Wrote  : test_main___.cpp
Done.
```

On error it prints `Failed.` and returns a non-zero exit code. **Do not parse the text**; rely on the exit code.

### 6.9 ⚠️ The CLI does not start the bridge program

**The CLI only generates code. It starts neither the bridge program nor the service.**

To actually run one end-to-end call you must manually:

1. compile / run the generated service side (build commands in Chapter 14);
2. **start `bridge.py` (or `bridge.exe`) separately and keep it running**;
3. then run the caller side or open the HTML test page.

### 6.10 ⚠️ The CLI no longer delivers `.md` — read the code

The new version **does not produce `<base>_readme.md`**. Interface contracts are read from the code itself:

- **stub signature** → read the service code.
- **call example** → read `<base>_main_test___.xxx`.
- **build command** → read `CMakeLists.txt` (C++), `setup_*_tests.ps1` (multi-language), or Chapter 14.
- **default configuration** → read the constant declarations at the top of the call code.
- **environment variables / dependencies** → read the comment block at the top of the generated code.

### 6.11 Building the generated C++

When the CLI produces a C++ target, the CMake support files land next to the `.hpp`/`.cpp` pair. A typical workflow:

```bash
# put the .hpp/.cpp pair, CMakeLists.txt and test_main___.cpp into one directory.
cd that-directory

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The CMake project builds **two executables**:

- `<Unit>_http_json_service` — the service executable.
- `<Unit>_http_json_call_test` — the caller test driver.

The CMake script **does not copy the runtime DLLs**. Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` and `z_ipc_*` next to the executables (or add their directory to `PATH` / `LD_LIBRARY_PATH`).

### 6.12 Building the generated C#

The CLI's `.cs` output produces a complete C# project. Workflow:

```bash
# put the four C# files into one directory.

dotnet new console -o my_service
cd my_service
cp ../ComplexTestUnit_http_json_service.cs .
cp ../ComplexTestUnit_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

### 6.13 Building the generated Rust

```bash
# put the .rs files into one directory.

cargo new my_service
cd my_service
cargo add lingofuse --path ../LingoFuse/rust
cargo add serde_json
cp ../calculator_service.rs src/
cp ../calculator_service_main_test___.rs src/main.rs
cargo run
```

### 6.14 Building the generated Go

```bash
# put the .go files into one directory.

go mod init calculator
go get github.com/PassByYou888/LingoFuse/go
cp calculator_service.go .
cp calculator_service_main_test.go .
go test -v
```

### 6.15 Building the generated Java

```bash
# put the .java files into one directory.

javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED -cp .:lingofuse.jar:jackson-databind.jar HttpJsonService
```

---

## Chapter 7  Agent (MCP-API) operation guide — the three tools

### 7.1 Trigger condition

**After the GUI starts**, the tool automatically starts the MCP service on a background thread:

1. it creates a LingoFuse App (default name `code_decl_to_json_abi_mcp_api`).
2. it connects to the LingoFuse endpoint (default `ipc:agent`).
3. it registers all **three tools** through the Beacon (default App `agent_main_app`, API `register_agent`).

So for an Agent to call this tool, the following must hold:

- this tool's GUI is **running**;
- the Beacon (e.g. `pascal_agent_service`) is **running**;
- both sides use the same LingoFuse endpoint (default `ipc:agent`).

> **Note**: the MCP service and the bridge program **are two different things**.
>
> - MCP service: lets an Agent call this tool's three APIs (to generate code).
> - Bridge program: lets every runtime caller side reach the service.
>
> **They cannot substitute for each other.** An Agent generating code does not need the bridge; but as soon as the generated code runs, **the bridge must still be running**.

### 7.2 The three tools

| # | Tool | Purpose |
|:-:|------|------|
| 1 | `CodeDeclToJsonAbi_Generate(Source, Language)` | **step 1**: parse the source text, generate every artifact, and return a list of all file names |
| 2 | `CodeDeclToJsonAbi_ListFiles()` | **step 2a**: return the list of artifact file names |
| 3 | `CodeDeclToJsonAbi_GetFile(FileName)` | **step 2b**: return the complete content of one file by name |

### 7.3 The three-step workflow

```
┌──────────────────────────────────────────────────────────────┐
│  1.  CodeDeclToJsonAbi_Generate(Source, Language)            │
│      → {"status":"ok","unit_name":"...","count":20,          │
│         "files":[...]}                                       │
├──────────────────────────────────────────────────────────────┤
│  2.  CodeDeclToJsonAbi_ListFiles()                           │
│      → {"status":"ok","count":20,"files":[...]}              │
├──────────────────────────────────────────────────────────────┤
│  3.  CodeDeclToJsonAbi_GetFile("Calculator_http_json_         │
│                                service_unit.pas")             │
│      → {"status":"ok","name":"...","text":"..."}             │
│                                                              │
│      (repeat GetFile for the files you need. No second       │
│       Generate call is required.)                            │
└──────────────────────────────────────────────────────────────┘
```

### 7.4 Tool 1 — `CodeDeclToJsonAbi_Generate`

**Signature**: `function(Source: string; Language: string): string`

**Parameters**:

| Parameter | Type | Explanation |
|------|------|------|
| `Source` | string | the complete source text |
| `Language` | string | `"pascal"` or `"c"`, case-insensitive |

**The language rule (pitfall number one)**:

- `"pascal"` means **the source text is a Pascal unit**.
- `"c"` means **the source text is a C header**.
- `"python"`, `"cpp"`, `"csharp"` and `"javascript"` are **target** languages, **not** source languages. Passing any of them returns:
  `{"error":"Unsupported language. Use ''pascal'' or ''c''."}`

**Success return** (five-language scope, example):

```json
{
  "status": "ok",
  "unit_name": "Calculator",
  "count": 20,
  "files": [
    "Calculator_http_json_service_unit.pas",
    "Calculator_http_json_call_unit.pas",
    "Calculator_http_json_service_main_test___.pas",
    "Calculator_http_json_call_main_test___.pas",
    "Calculator_http_json_call.js",
    "Calculator_http_json_call_test.html",
    "Calculator_http_json_service.py",
    "Calculator_http_json_call.py",
    "Calculator_http_json_service_main_test___.py",
    "Calculator_http_json_call_main_test___.py",
    "Calculator_http_json_service.cs",
    "Calculator_http_json_call.cs",
    "Calculator_http_json_service_main_test___.cs",
    "Calculator_http_json_call_main_test___.cs",
    "Calculator_http_json_service.hpp",
    "Calculator_http_json_service.cpp",
    "Calculator_http_json_call.hpp",
    "Calculator_http_json_call.cpp",
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

- every successful call **replaces the session**. Calling `Generate` again with a different source text discards everything from the previous call.
- every successful call **writes all artifacts to disk**, under `<exe directory>/<normalized unit name>/`.
- **one call produces every target**. There is no per-target `Generate` interface.
- **the artifact list contains no `_readme.md`**. Interface contracts are read from the code itself (see Chapter 3).

### 7.5 Tool 2 — `CodeDeclToJsonAbi_ListFiles`

**Signature**: `function(): string`

**Success return**:

```json
{
  "status": "ok",
  "count": 20,
  "files": ["<name 1>", "<name 2>", ...]
}
```

**Empty return** (if `Generate` has not been called yet):

```json
{"status": "ok", "count": 0, "files": []}
```

**Notes**:

- **pure read.** It reruns no generator and modifies no session state.
- the names are **file names**, not full paths. Pass one of these names as the `GetFile` argument.

### 7.6 Tool 3 — `CodeDeclToJsonAbi_GetFile`

**Signature**: `function(FileName: string): string`

**Parameters**:

| Parameter | Type | Explanation |
|------|------|------|
| `FileName` | string | must be a value previously returned by `ListFiles` |

**Success return**:

```json
{
  "status": "ok",
  "name": "<FileName>",
  "text": "<complete artifact text>"
}
```

The `text` field contains **the complete artifact**, never truncated. Multi-line content is embedded as a string with standard JSON escaping.

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

- **pure read.** It reruns no generator and modifies no session state.
- **`FileName` is case-sensitive.** `CMakeLists.txt` is valid; `cmakelists.txt` is not.
- **the `text` field may be empty** (when the file really is empty). Use `status` to tell "empty" apart from "error".

### 7.7 The recommended call sequence

**Minimal flow (one target, one file)**:

```
1. CodeDeclToJsonAbi_Generate(Source="...", Language="pascal")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_unit.pas")
```

**Complete C++ build-preparation flow**:

```
1. CodeDeclToJsonAbi_Generate(<source>, "c")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.hpp")
4. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.cpp")
5. CodeDeclToJsonAbi_GetFile("<U>_http_json_call.hpp")
6. CodeDeclToJsonAbi_GetFile("<U>_http_json_call.cpp")
7. CodeDeclToJsonAbi_GetFile("CMakeLists.txt")
8. CodeDeclToJsonAbi_GetFile("test_main___.cpp")
```

**Note**: there is no step 5 `.md` to pull. **Interface contracts come from the stub signatures and the call examples in `test_main___.cpp`.**

**Complete C# build-preparation flow**:

```
1. CodeDeclToJsonAbi_Generate(<source>, "c")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.cs")
4. CodeDeclToJsonAbi_GetFile("<U>_http_json_call.cs")
5. CodeDeclToJsonAbi_GetFile("<U>_http_json_service_main_test___.cs")
6. CodeDeclToJsonAbi_GetFile("<U>_http_json_call_main_test___.cs")
```

**Agent introspection flow (when the Agent wants to see what it produced)**:

```
1. CodeDeclToJsonAbi_Generate(<source>, "pascal")
2. CodeDeclToJsonAbi_ListFiles()          ← see all the file names
3. CodeDeclToJsonAbi_GetFile(<any name>)  ← read any artifact
```

### 7.8 Notes for Agent mode

1. **The source language accepts only `"pascal"` or `"c"`**; any other value is rejected.
2. **One `Generate` produces every target.** If you want the Python service, read the Python-named file — do not call `Generate` again.
3. **`Generate` is idempotent across calls.** Calling it repeatedly with the same source produces the same artifacts, overwriting the previous disk content.
4. **Order matters**: `Generate` first, then `ListFiles` / `GetFile`. The reverse fails.
5. **`ListFiles` and `GetFile` are pure reads.** Unless you want a different session, do not call `Generate` between these two steps.
6. **The GUI must be alive.** The MCP service is attached when the GUI starts; closing the GUI takes all three tools offline.
7. **Generating code with an Agent ≠ running the code.** To actually run the generated code, **you must still start the bridge program manually and keep it running**.
8. **There are no `.md` artifacts.** The Agent must read the contracts from the code itself. Recommended reading order:
   - first `GetFile` the service code → read the stub signatures → determine API names, parameters and return types.
   - then `GetFile` the test driver → read the call examples.
   - if the target is C++, `GetFile("CMakeLists.txt")` → read target names, source files and link libraries.
   - if the target is multi-language and has `setup_*_tests.ps1`, `GetFile` it → read the environment preparation steps.
9. **A C++ target requires all six artifacts**: header + implementation + test driver + CMake script + two tests. **There is no `.md`.**
10. **A C# target requires all four artifacts**: service code + caller code + two test programs.

### 7.9 Example Agent interaction

```
# 1. feed in the source and generate every artifact
CodeDeclToJsonAbi_Generate(
    Source   = "<contents of calculator.pas>",
    Language = "pascal")
→ {"status":"ok","unit_name":"Calculator","count":20,"files":[...]}

# 2. see what was produced
CodeDeclToJsonAbi_ListFiles()
→ {"status":"ok","count":20,"files":[...]}

# 3. read artifacts on demand — no second Generate needed
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_unit.pas")      ← read the stub signatures
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call_unit.pas")        ← read the default base URL
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call_main_test___.pas") ← read the call examples
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call.js")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call_test.html")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service.py")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call.py")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service.hpp")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service.cpp")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call.hpp")
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call.cpp")
CodeDeclToJsonAbi_GetFile("CMakeLists.txt")
CodeDeclToJsonAbi_GetFile("test_main___.cpp")
```

The Agent can then hand the artifacts to the user, or — where the environment allows — run the build and run steps in Chapter 14 directly.

### 7.10 How an Agent bootstraps a build script from the artifacts

**Now that there is no `.md`, the Agent's "read the contract from the artifacts" path is**:

```
GetFile(service code)
    → stub signature = API name + parameter types + return type
    → registration table = list of API names
    → top comment = dependencies, protocol, prohibitions

GetFile(call code)
    → default base URL / timeout / bridge App name / bridge API name
    → top comment = dependencies, usage

GetFile(test driver)
    → call examples
    → assertion shape (OK / FAILED)

GetFile(CMakeLists.txt)  [if the target includes C++]
    → target names
    → source file list
    → include directories
    → link libraries

GetFile(setup_*_tests.ps1)  [if the target language has one]
    → environment preparation steps
    → package installation commands
    → test commands
```

**The Agent's "auto-generated build script" template**:

```python
# the Agent's pseudocode
service_src = get_file("<U>_http_json_service.<ext>")
stub_signatures = parse_stub_signatures(service_src)  # extract API names and types from the code

call_src = get_file("<U>_http_json_call.<ext>")
config = parse_config_constants(call_src)  # HTTP_CALL_BASE_URL etc.

test_src = get_file("<U>_http_json_call_main_test___.<ext>")
call_examples = parse_call_examples(test_src)

# if the target is C++:
cmake_src = get_file("CMakeLists.txt")
targets = parse_cmake_targets(cmake_src)
sources = parse_cmake_sources(cmake_src)
link_libs = parse_cmake_link_libs(cmake_src)

# if the target language has a setup script:
setup_src = get_file("setup_<lang>_tests.ps1")
env_steps = parse_setup_steps(setup_src)
```

---

## Chapter 8  How the MCP tool provider unit is built

This chapter documents the **bootstrap → AI-fill architecture that produces `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`**. Every sentence in this chapter is about **the tool that writes the tool provider**, not about the tool provider itself.

### 8.1 The three-stage build

The tool provider unit is not hand-written. It is produced in three stages:

```
Stage 1: Bootstrap script
    ↓ produces a structurally complete Pascal unit
    ↓ containing 3 callback shells, 3 internal-call stubs, 3 tool schemas
    ↓ plus the complete registration scaffolding
    code_decl_to_json_abi_mcp_api_tool_provider_unit.pas

Stage 2: AI fill
    ↓ fills in each internal_call_* function body
    ↓ including the UI synchronization logic

Stage 3: Compile + run
    ↓ the unit is compiled into the GUI executable
    ↓ the MCP service registers all 3 tools when the GUI starts
```

### 8.2 What the bootstrap script writes

For each of the 3 tools, the bootstrap script writes:

1. **the `function` declaration in the `interface` section** — the external signature.
2. **the `procedure Callback_...` forward declaration** — the cdecl callback LingoFuse will invoke.
3. **the complete body of `procedure Callback_...`** — containing:
   - reading the input `TDataHnd___` as UTF-8 bytes.
   - parsing the bytes into JSON.
   - extracting the named parameters.
   - **calling the matching `internal_call_*` function** (that call is already written; the AI does not touch it).
   - writing the returned string back into the output `TDataHnd___`.
   - a `try/except` envelope that turns any exception into `{"error": "..."}`.
4. **the shell of `function internal_call_...`** — the FPC/Delphi `{$IFDEF}` branches, the `TCompute.Sync` wrapper, and **a function body that the AI must fill in**.
5. **the tool schema registration in `RegisterTools`** — the tool's `name`, `description`, `target_app`, `target_api`, and the JSON `parameters` schema.

The bootstrap script also writes the complete registration scaffolding for `RegisterAPIs` (3 `LF_RegisterCallEx` calls) and `Execute_And_Reg_all` (App creation, endpoint connection, Beacon handshake).

### 8.3 What the AI fills in

Per tool, the AI fills in exactly one thing: **the body inside `Do_Sync___` (FPC) or the anonymous procedure (Delphi)**.

**Tool 1 — `Generate`**:

1. check that the form is available.
2. validate the `Language` parameter (only `pascal` / `c`).
3. select the language in the combo box.
4. write the source text into the source editor.
5. call the parse / normalize / generate button handlers in order.
6. read the generated file list from the ListView.
7. read the unit name from the model JSON.
8. build the file-list JSON and return it.

**Tool 2 — `ListFiles`**:

1. check that the form is available.
2. walk the ListView.
3. return the file names.

**Tool 3 — `GetFile`**:

1. check that the form is available.
2. match `FileName` against the ListView entries.
3. read the file at `SubItems[0]` of the matching entry (UTF-8).
4. return the text.

The AI **never** writes:

- the `TCompute.Sync` wrapper.
- the callback envelope.
- the exception handling.
- the LingoFuse registration code.
- the tool schema.

### 8.4 Why the UI-synchronization pattern

The key design decision: **the AI writes no new state-management logic**. Every MCP tool body delegates to the GUI form. The hosting chain is:

```
MCP client
    ↓ calls CodeDeclToJsonAbi_Generate (LingoFuse Call)
Callback_CodeDeclToJsonAbi_Generate (cdecl, worker thread)
    ↓ calls internal_call_...
internal_call_CodeDeclToJsonAbi_Generate
    ↓ TCompute.Sync(Do_Sync___)
Do_Sync___ (runs on the main thread)
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

Every arrow in that chain is **written once by the bootstrap script**, except the UI touches each tool needs inside `Do_Sync___`.

**Consequences of this design**:

1. **The GUI is the single source of truth.** There is no parallel state.
2. **Adding a new MCP tool is purely mechanical.** Copy an `internal_call_*` pair, rename it, point it at a different form field or button click, add the tool schema to `RegisterTools`, done.
3. **The GUI's button-click handlers literally are the MCP tool implementations.** The MCP layer is only a thin remote control.
4. **Thread safety is inherited, not reinvented.** `TCompute.Sync` marshals the body onto the main thread.
5. **No new state fields are introduced.** If an MCP tool needs a value, that value must already exist as a form editor or form field.

### 8.5 Why the reduction to three tools

The previous iteration exposed 24 tools. That was a **remote-control panel**, not an Agent-friendly API. The Agent had to understand:

- which 2 of the 24 tools are the input tools.
- which 1 is the generation tool.
- which of the remaining 21 readers it needs.

That is a **discoverability problem**: the Agent's first action was always wrong, and correcting it took a whole round of regeneration.

The three-tool design solves it:

- **one tool per verb**: Generate, List, Get.
- **Generate** produces **every** target in one call.
- **List** / **Get** are pure reads.

### 8.6 Adding a new tool — the mechanical recipe

To add a fourth tool:

1. **pick the right pattern** (setter, reader, driver, cache reader).
2. **add one entry to the bootstrap script's tool table**, containing:
   - the tool name.
   - the description string.
   - the parameter list.
   - the pattern identifier.
3. **rerun the bootstrap script.** It regenerates the unit with the new callback, the new stub and the new tool schema.
4. **fill in the AI body according to the chosen pattern**.
5. **if the tool needs a new editor or a new tab, update the GUI.**
6. **recompile the GUI executable.**

The tool then appears automatically in the Beacon's tool list. No other file needs to change.

### 8.7 What the AI must never do

- **Never add a new state field to the form for an MCP tool.**
- **Never call a UI method from a worker thread.** Every UI touch must be inside `Do_Sync___`.
- **Never bypass the callback envelope.** Let exceptions propagate; the envelope turns them into `{"error": "..."}`.
- **Never rename or renumber tools.** Tool names are stable identifiers that external callers depend on.
- **Never change the tool schema without changing the AI-filled function body.**

---

## Chapter 9  Programmatic interface

The tool can also be driven from another program. This chapter describes the **public API surface** — the same functions the CLI, the GUI and the MCP provider call internally.

### 9.1 Where the APIs live

| Unit | Exports |
|------|------|
| `http_pas_abi_service_generator_tool` | `GenerateHTTPServicePascalCode` |
| `http_pas_abi_call_generator_tool` | `GenerateHTTPCallPascalCode` |
| `http_pas_abi_test_generator_tool` | `GenerateHTTPServicePascalTestCode` / `GenerateHTTPCallPascalTestCode` |
| `http_py_abi_service_generator_tool` | `GenerateHTTPServicePythonCode` |
| `http_py_abi_call_generator_tool` | `GenerateHTTPCallPythonCode` |
| `http_py_abi_test_generator_tool` | `GenerateHTTPServicePythonTestCode` / `GenerateHTTPCallPythonTestCode` |
| `http_csharp_abi_service_generator_tool` | `GenerateHTTPServiceCsharpCode` |
| `http_csharp_abi_call_generator_tool` | `GenerateHTTPCallCsharpCode` |
| `http_csharp_abi_test_generator_tool` | `GenerateHTTPServiceCsharpTestCode` / `GenerateHTTPCallCsharpTestCode` |
| `http_cpp_abi_service_generator_tool` | `GenerateHTTPServiceCppHeader` / `GenerateHTTPServiceCppCode` |
| `http_cpp_abi_call_generator_tool` | `GenerateHTTPCallCppHeader` / `GenerateHTTPCallCppCode` |
| `http_js_abi_call_generator_tool` | `GenerateHTTPCallJsCode` / `GenerateHTTPCallJsHtmlCode` |
| `http_cmake_generator_tool` | `GenerateCMakeScript` / `GenerateTestMainCpp` |
| `http_rust_abi_service_generator_tool` | `GenerateHTTPServiceRustCode` |
| `http_rust_abi_call_generator_tool` | `GenerateHTTPCallRustCode` |
| `http_rust_abi_test_generator_tool` | `GenerateHTTPServiceRustTestCode` / `GenerateHTTPCallRustTestCode` |
| `http_go_abi_service_generator_tool` | `GenerateHTTPServiceGoCode` |
| `http_go_abi_call_generator_tool` | `GenerateHTTPCallGoCode` |
| `http_go_abi_test_generator_tool` | `GenerateHTTPServiceGoTestCode` / `GenerateHTTPCallGoTestCode` |
| `http_java_abi_service_generator_tool` | `GenerateHTTPServiceJavaCode` |
| `http_java_abi_call_generator_tool` | `GenerateHTTPCallJavaCode` |
| `http_java_abi_test_generator_tool` | `GenerateHTTPServiceJavaTestCode` / `GenerateHTTPCallJavaTestCode` |
| (the other languages are the same) | ... |

Every code function returns a `TPascalStringList`; the caller is responsible for freeing it. **There is no `Generate*Readme` function — the `.md` generation feature has been removed.**

### 9.2 Building the Model

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
        // the Model can now be handed to the generator functions.
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

For a C header, use `CreateFrom_C_Code` instead.

### 9.3 A minimal working embed

```pascal
var
  Parser: tpascal_func_decl_tool;
  Model: TPascal_Func_Model;
  Code: TPascalStringList;
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

      // if the target is C++, also produce the CMake pair:
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

**Note**: there is no need to call `Generate*Readme` any more. The `.md` generator has been removed.

### 9.4 Contract summary

| Function family | Input | Output | Notes |
|--------|------|------|------|
| `Generate*Code` | `TPascal_Func_Model` (must be `tnf_ABI`) | `TPascalStringList` or `nil` | the caller frees it; `nil` when the model is empty |
| `GenerateCMakeScript` / `GenerateTestMainCpp` | `TPascal_Func_Model` | `TPascalStringList` or `nil` | the caller frees it; fixed output file names |
| `tpascal_func_decl_tool.CreateFrom_*` | source text | a parser instance | the caller frees it |
| `TPascal_Func_Model.LoadFromParser` | parser + optional report | — | applies the type-family filters |

### 9.5 Producing only one side (service or call)

```pascal
// produce only the Pascal service side
Code := GenerateHTTPServicePascalCode(Model);

// produce only the Pascal caller side
Code := GenerateHTTPCallPascalCode(Model);

// produce only the Python service side
Code := GenerateHTTPServicePythonCode(Model);

// produce only the Rust caller side
Code := GenerateHTTPCallRustCode(Model);

// produce only the Java service side
Code := GenerateHTTPServiceJavaCode(Model);
```

**The `Generate*Code` functions do not automatically produce test programs or CMake scripts.** For the complete artifact set, run the logic behind `GenerateAllSourcesClick` (see the GUI chapter), or call `Generate*TestCode` / `GenerateCMakeScript` / `GenerateTestMainCpp` yourself as needed.

### 9.6 Registering a custom generator into the tool itself

If you are extending the tool and want your generator to appear in the CLI, GUI and MCP front ends, you must register it in three places:

1. `code_decl_to_json_abi.lpr` — the `uses` clause, so the unit's `initialization` runs.
2. `code_decl_to_abi_json_frm.pas` — `implementation uses`, so the GUI can call it.
3. `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` — if you added a tool, follow the mechanical recipe in §8.6.

**In most cases you only need the first two**; the three-tool MCP layer picks up the new artifacts automatically (through `final_source_file_ListView`).

### 9.7 Registering a new CodeGenEntry

Every generator unit calls `RegisterCodeGenEntry` in its `initialization` section. **That registration is the only way the toolchain recognizes a generator.**

```pascal
initialization
  RegisterCodeGenEntry(
    'pascal',                                  // LanguageID
    'Pascal HTTP/JSON service code',            // DisplayName
    asService,                                  // Side
    akServiceCode,                              // Kind
    '_http_json_service_unit.pas',              // Suffix
    False,                                      // FixedName
    @GenerateHTTPServicePascalCode);            // Func
```

**When adding a new target language**, add the `RegisterCodeGenEntry` calls in its generator units. **The `akServiceReadme` / `akCallReadme` / `akTestReadme` kinds are no longer registered by any generator** (they became dead enum values after the `.md` generation feature was removed).

---

## Chapter 10  Artifact list

### 10.1 The purpose of each artifact

| Extension / name | Purpose | Bridge needed at runtime |
|---------------|------|:----------------------:|
| `*_http_json_service_unit.pas` | Pascal service: registers the APIs, listens for RPC, turns LingoFuse calls into JSON. | ❌ (the service itself does not go through the bridge) |
| `*_http_json_call_unit.pas` | Pascal caller: turns a local function call into an HTTP POST to `bridge.py`. | ✅ **required** |
| `*_http_json_service_main_test___.pas` | Pascal service-side test driver. | ❌ (local test) |
| `*_http_json_call_main_test___.pas` | Pascal caller-side end-to-end test driver. | ✅ **required** |
| `*_http_json_service.py` | Python service. | ❌ |
| `*_http_json_call.py` | Python caller. | ✅ **required** |
| `*_http_json_service_main_test___.py` | Python service-side test driver. | ❌ |
| `*_http_json_call_main_test___.py` | Python caller-side end-to-end test driver. | ✅ **required** |
| `*_http_json_service.hpp` / `.cpp` | C++ service (`.hpp` declarations + `.cpp` implementation). | ❌ |
| `*_http_json_call.hpp` / `.cpp` | C++ caller. | ✅ **required** |
| `*_http_json_service.cs` | C# service module. | ❌ |
| `*_http_json_call.cs` | C# caller. | ✅ **required** |
| `*_http_json_service_main_test___.cs` | C# service test driver. | ❌ (local test) |
| `*_http_json_call_main_test___.cs` | C# call test driver. | ✅ **required** |
| `*_http_json_call.js` | browser JS client (IIFE, attached to `window.<UnitName>Api`). | ✅ **required** |
| `*_http_json_call_test.html` | self-contained HTML test page; double-click to test. | ✅ **required** |
| `*_http_json_service_node.js` | Node.js service module. | ❌ |
| `*_http_json_call_node.js` | Node.js caller module. | ✅ **required** |
| `*_http_json_service.ts` | TypeScript service module. | ❌ |
| `*_http_json_call_ts.ts` | TypeScript caller module. | ✅ **required** |
| `*_http_json_service_rs.rs` | Rust service module. | ❌ |
| `*_http_json_call_rs.rs` | Rust caller module. | ✅ **required** |
| `*_http_json_service_go.go` | Go service module. | ❌ |
| `*_http_json_call_go.go` | Go caller module. | ✅ **required** |
| `HttpJsonService.java` | Java service class. | ❌ |
| `HttpJsonClient.java` | Java caller class. | ✅ **required** |
| `*_http_json_service_swift.swift` | Swift service module. | ❌ |
| `*_http_json_call_swift.swift` | Swift caller module. | ✅ **required** |
| `*_http_json_service.rb` | Ruby service module. | ❌ |
| `*_http_json_call.rb` | Ruby caller module. | ✅ **required** |
| `*_http_json_service_zig.zig` | Zig service module. | ❌ |
| `*_http_json_call_zig.zig` | Zig caller module. | ✅ **required** |
| `*_http_json_service.erl` | Erlang service module. | ❌ |
| `*_http_json_call.erl` | Erlang caller module. | ✅ **required** |
| `*_http_json_service_mod.f90` | Fortran service module. | ❌ |
| `*_http_json_call_mod.f90` | Fortran caller module. | ✅ **required** |
| `*_http_json_service.jl` | Julia service module. | ❌ |
| `*_http_json_call.jl` | Julia caller module. | ✅ **required** |
| `*_http_json_service.R` | R service script. | ❌ |
| `*_http_json_service_impl.R` | R service user-implementation stub. | ❌ |
| `*_http_json_call.R` | R caller module. | ✅ **required** |
| `*_http_json_call_delphi.pas` | Delphi caller unit. | ✅ **required** |
| `*_http_json_call.dart` | Dart caller module. | ✅ **required** |
| `*_http_json_service.dart` | Dart service module. | ❌ |
| `*_http_json_call_php.php` | PHP caller module. | ✅ **required** |
| `CMakeLists.txt` | the CMake build script for the C++ pair + the C++ test driver. | — |
| `test_main___.cpp` | the C++ caller test driver referenced by the CMake script. | ✅ **required** (when executed) |
| `launch_bridge.ps1` | the bridge launch script. | — |
| `setup_js_tests.ps1` | Node.js test-environment setup script. | — |
| `setup_ts_tests.ps1` | TypeScript test-environment setup script. | — |
| `setup_zig_tests.ps1` | Zig test-environment setup script. | — |
| `setup_erlang_tests.ps1` | Erlang test-environment setup script. | — |
| `setup_fortran_tests.ps1` | Fortran test-environment setup script. | — |
| `setup_julia_tests.ps1` | Julia test-environment setup script. | — |
| `setup_r_tests.ps1` | R test-environment setup script. | — |

> **Note**: **there is no `*_readme.md` artifact.** Interface contracts are read from the code itself, the test drivers, the CMake script, `setup_*_tests.ps1` and the stub signatures. See Chapter 3.
>
> **The service itself does not go through the bridge program.** The bridge program only serves the "call → service" direction.

### 10.2 File locations

- **GUI / MCP**: artifacts are written to the `<UnitName>/` subdirectory of the executable's directory.
- **CLI**: artifacts are written to the directory that holds the output file.

### 10.3 The two CMake artifacts are unit-level

`CMakeLists.txt` and `test_main___.cpp` use **fixed names** (no unit prefix). Generating two different units into the same directory overwrites the previous CMake file. **One unit per directory.**

### 10.4 The complete file list (five-language scope, 20 artifacts)

For a source unit whose parsed name is `<U>`:

```
 1.  <U>_http_json_service_unit.pas
 2.  <U>_http_json_call_unit.pas
 3.  <U>_http_json_service_main_test___.pas
 4.  <U>_http_json_call_main_test___.pas
 5.  <U>_http_json_call.js
 6.  <U>_http_json_call_test.html
 7.  <U>_http_json_service.py
 8.  <U>_http_json_call.py
 9.  <U>_http_json_service_main_test___.py
10.  <U>_http_json_call_main_test___.py
11.  <U>_http_json_service.cs
12.  <U>_http_json_call.cs
13.  <U>_http_json_service_main_test___.cs
14.  <U>_http_json_call_main_test___.cs
15.  <U>_http_json_service.hpp
16.  <U>_http_json_service.cpp
17.  <U>_http_json_call.hpp
18.  <U>_http_json_call.cpp
19.  CMakeLists.txt
20.  test_main___.cpp
```

**The other target languages (Rust, Go, Java, Swift, Ruby, Zig, Erlang, Fortran, Julia, R, Dart, PHP, Node.js, TypeScript, Delphi) produce their own additional artifacts**; the exact list is whatever the MCP `Generate` return value or the GUI's "Final Source" list says.

### 10.5 The bridge program is the forwarder and must always be running

**Every generated caller side (Pascal / Python / C++ / C# / JavaScript / Node.js / TypeScript / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Zig / Erlang / Fortran / Julia / R) talks to the backend through the bridge program:**

```
caller ──HTTP POST──▶ bridge.py / bridge.exe ──LF_Call──▶ service
caller ◀─HTTP resp──  bridge.py / bridge.exe ◀─LF ret───  service
```

**When starting the bridge program, specify the same endpoint as the service, for example:**

```
python3 bridge.py --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

**The important rule, stressed once more:**

- **The bridge program is the forwarder and must always be running.** Closing the bridge closes the whole path.
- the bridge can be `bridge.py`, or it can be compiled into `bridge.exe` — both behave the same.
- the bridge should run in the foreground in an **independent terminal**. Only after you see its HTTP listening log should you start the caller side.
- after it crashes or is killed, restarting it recovers everything; the caller does not need a restart.

### 10.6 Where the CMake script finds the LingoFuse C++ library

The CMake script requires a directory containing:

- `LingoFuse.h`
- `LingoFuse.c`
- `LingoFuse.hpp`
- `lf_io.hpp`
- `lf_http_bridge_client.hpp`
- `json.hpp`

Pass it as `-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf`, or fill in the **"LingoFuse C++ library directory"** field in cmake-gui.

---

## Chapter 11  JSON safety and stability

Because every generated caller side ultimately speaks JSON over HTTP, **JSON is the safety and stability boundary of the whole pipeline**. The following points are guaranteed by the toolchain:

### 11.1 UTF-8 throughout

Requests and responses are always UTF-8; the bridge serializes with `ensure_ascii=False`, so non-ASCII payloads (Chinese, emoji and other multi-byte content) travel as literal UTF-8 rather than being re-encoded into `\uXXXX` escapes.

### 11.2 An explicit NUL terminator policy

LingoFuse strings are NUL-terminated on the wire. The bridge **strips the trailing NUL** before forwarding to the HTTP client, and the generated caller sides never mix a stray NUL into the JSON.

### 11.3 The bridge is binary-safe

If a payload cannot be parsed as JSON at all, the bridge forwards it as-is rather than corrupting it.

### 11.4 Deterministic unwrapping

The bridge wraps every service response in a stable envelope (`{"status_code": ..., "headers": ..., "body": ...}`). The generated caller side unwraps `body` and checks `body.code`; code `0` returns `body.result`, any other code raises that language's exception.

### 11.5 No silent precision loss on the wire

Large integers travel as JSON numbers by default, which is safe for Python and for C++ (the service side's `std::int64_t`). **It is not safe for JavaScript clients**, because JS `Number` is an IEEE-754 double. For `int64` / `uint64` interfaces intended for browser consumption, **the recommended pattern is to have the service return a string**.

**Affected caller-side artifacts**:

- JavaScript (`Number` precision ceiling 2^53)
- PHP (integer overflow becomes float)
- the browser HTML test page

**Not affected**:

- Pascal (`Int64` is complete)
- Python (arbitrary-precision integers)
- C++ (`std::int64_t`)
- C# (`long`)
- Rust (`i64`)
- Go (`int64`)
- Java (`long`)
- Ruby (`Integer` is arbitrary precision)
- R (`integer` is 32-bit, but `numeric` carries 53-bit precision)
- Julia (`Int64`)

### 11.6 A stable error schema

Every failure shows up as one of:

- `{"error":"<message>"}` (tool level)
- `{"code": -N, "error": "<message>"}` (service / bridge level)

The caller sides translate these into language-specific exceptions:

| Language | Exception class |
|------|--------|
| Pascal | `EHTTPCallError` |
| Python | `HTTPCallError` |
| C++ | `HTTPCallError` |
| C# | `HTTPCallError` |
| JavaScript | `LFHttpCallError` |
| Node.js | `HTTPCallError` |
| TypeScript | `HttpJsonCallError` |
| PHP | `HttpJsonCallError` |
| Rust | `HttpCallError` |
| Go | `HTTPCallError` |
| Java | `HTTPCallException` |
| Dart | `HttpCallError` |
| Swift | `HTTPCallError` |
| Ruby | `HTTPCallError` |
| R | `http_call_error` |
| Julia | `HTTPCallError` |
| Zig | `HttpCallError` |
| Erlang | `{error, {service_error, Code, Msg}}` |
| Fortran | through the `ok` output parameter |
| Delphi | `EHTTPCallError` |

**Practical conclusion**: as long as the bridge is running and both sides agree on the endpoint string, **a JSON payload produced by one language's caller side is consumed correctly by any other language's service side, and vice versa**.

---

## Chapter 12  Language support: today and tomorrow

### 12.1 Excellent interface support for strongly typed languages

For **Pascal, C++, C#, Python, Rust, Go, Java, Swift, Ruby, Zig, Erlang, Fortran, Julia, R and Dart**, the generated interface is a first-class citizen, not merely a stub:

- **Pascal**: the generated service unit registers cdecl callbacks directly with LingoFuse and serializes with `Z.Json`. The generated call unit uses `LFHttpPost` from `lf_http_bridge_client` and exposes every API as a **typed free function**.
- **C++**: the generated service produces a clean `.hpp`/`.cpp` pair, with namespaces, typed function signatures, `LF_CDECL`-compatible callbacks and JSON I/O helpers. The generated caller side exposes every API as a **typed free function** and carries a full set of tunable parameters. **`CMakeLists.txt` and `test_main___.cpp` are produced alongside the code.**
- **C#**: the generated service and caller modules use the official LingoFuse .NET binding. The service exposes a `Service.RegisterAPIs` entry point and a stub for each routine. The caller side exposes one typed synchronous function and one typed asynchronous function per API. **Both test programs are produced too.**
- **Python**: the generated service module exposes a `register_all_http_json_apis(app)` entry point and typed internal stubs; the generated call module exposes **one typed Python function per API**, with a unified internal `_call_api()` dispatcher.
- **Rust**: the service module registers callbacks with the `lingofuse` crate; the call module exposes one synchronous function (`ureq`) and one asynchronous function (`reqwest` + `tokio`) per API.
- **Go**: the service module uses the `lingofuse` Go package; the call module exposes one synchronous function per API plus a channel-based asynchronous function.
- **Java**: the service module uses the LingoFuse Java package; the call module exposes one statically typed method per API.
- **Swift**: the service module uses the `lingofuse` Swift module; the call module exposes one synchronous function and one `async throws` asynchronous function per API.
- **Ruby**: the service module uses the `lingofuse` gem; the call module exposes one module method per API.
- **R**: the service module uses `lingofuse` + `jsonlite`; the call module exposes one function per API (with an optional `_async` variant based on `future`).
- **Julia**: the service module uses `LingoFuse` + `JSON3`; the call module exposes one synchronous function and one `Task`-based asynchronous function per API.

**For every one of these languages**, the three type families (integer / float / string) map onto that language's native primitives, JSON serialization is handled internally, and the only thing the developer has to do is fill in the `internal_call_<Api>` stub body.

### 12.2 Excellent support for full-stack languages

- **JavaScript (browser)**: the generated `.js` is a **self-contained IIFE** attached to `window.<Unit>Api` (or `globalThis.<Unit>Api`), using only `fetch` / `Promise` / `async-await`, with **zero third-party dependencies**. A **self-contained HTML test page** ships with it.
- **TypeScript**: the generated `.ts` module has typed function signatures, `Promise<T>` returns and configurable `HttpJsonCallOptions`. A TS call test program ships with it and needs `tsx` to run.
- **Node.js**: the generated `.js` is a CommonJS module in `module.exports` form, using Node 18+'s built-in `fetch`.
- **PHP**: the generated `.php` uses `curl_*` (preferred) or `fopen` + `stream_get_meta_data`, with zero third-party dependencies.

### 12.3 The system is designed for unbounded extension

Adding a new target language is a **mechanical process**, not an architecture change. The steps are:

1. create two generator units: `<lang>_abi_service_generator_tool.pas` and `<lang>_abi_call_generator_tool.pas`.
2. provide a mapping table from the three ABI families to the target language's native types.
3. register the new units in the main program, the CLI dispatcher and the GUI form.
4. update the CLI's `Detect_Target_Lang` and its help text.
5. **nothing in the MCP layer needs changing** — the three-tool MCP layer picks up the new artifacts automatically (through `final_source_file_ListView`).

**There is no architectural ceiling on the number of supported languages.** As long as a language has (a) an HTTP client, (b) a JSON library, and (c) a runtime that can speak the wire protocol, it is a candidate.

**When a language is added, the user-facing contract does not change**: the same CLI flags, the same GUI workflow and the same three MCP tools keep working.

### 12.4 The language support matrix (details in Appendix E)

For the full support matrix (each language's supported directions, extensions, build scripts and test programs) see **[Appendix E — Language support matrix](#appendix-e--language-support-matrix)**.

---

## Chapter 13  Frequently asked questions

### Question 1: Why did the function I passed in disappear from the output?

Check three things:

1. **Is the function top-level** (in the `interface` section rather than nested inside a `class` / `record`)? Nested declarations are skipped.
2. **Are the parameters and return types in the supported set**? Only the integer family, the float family and the string family are accepted.
3. **Is the function name non-empty**?

### Question 2: Why does the model JSON have fewer functions than the source file?

Same as question 1. During normalization, any function carrying an unsupported type is dropped entirely.

### Question 3: What happens if the CLI is asked to output `.js` without `--call`?

It exits immediately with an argument error, exit code `1`. JavaScript is a caller-side-only target.

### Question 4: After the CLI finishes I see no output at all.

In CLI mode this tool writes all `DoStatus` messages to stdout. If you run it from an IDE or you redirect stdout, you may not see them. Run it directly in a terminal.

### Question 5: Clicking the "rule document" button in the GUI does nothing.

`pascal_code_abi_rule.md` or `C_code_abi_rule.md` is missing from the executable's directory. Put both files next to the executable. **These two are rule files that ship with the tool; they have nothing to do with the `.md` generation feature.**

### Question 6: An Agent call returns `{"error":"Form not available"}`.

The GUI is not running. The MCP service is a GUI-lifetime service; once the GUI closes, all tools go offline.

### Question 7: An Agent call returns `{"error":"Beacon not available ..."}`.

The Beacon service (default `agent_main_app`) is offline, or its endpoint does not match this tool's endpoint. Check both sides' `--endpoint` arguments.

### Question 8: What happens with `Language="python"`?

It returns `{"error":"Unsupported language. Use ''pascal'' or ''c''."}`.

`"python"`, `"cpp"`, `"csharp"` and `"javascript"` are **target** languages. To produce the Python service, pass `"pascal"` or `"c"` as `Language`, then call `GetFile` on the Python-named file in the list.

### Question 9: Do repeated `Generate` calls pollute the result?

No. Every `Generate` reruns all generators from scratch, overwriting the previous session and the disk content.

### Question 10: Can I generate only one target language?

**No.** `Generate` produces every target in one call. If you want only a few of them, pick them from the list with `GetFile`; the other files on disk can be ignored.

### Question 11: Running the generated caller side or the HTML test page reports `Network error` / `Failed to fetch` / `Connection refused`.

**In 99% of cases the bridge program is not running (or was running and got closed).**

Troubleshooting steps:

1. **Confirm the bridge program really is running**: check whether its terminal shows live log output.
2. **Confirm the bridge program's endpoint matches the service's**.
3. **Confirm the bridge program's port matches what the caller expects**: default `8081`.
4. **Restart the bridge program**.

> Once more: **the bridge program (`bridge.py` / `bridge.exe`) is the forwarder and must always be running.**

### Question 12: The service is up — so why can't I still call it?

The service, the bridge program and the caller side are **three independent processes**, and all three are needed:

```
Service process (must be online)
     ▲
     │ LF_Call
Bridge process (must be online, in the foreground, always running)
     ▲
     │ HTTP POST
Caller process (started on demand)
```

- service only, no bridge → the caller reports `Network error`.
- bridge only, no service → the bridge reports the API as unavailable / times out.
- all three present but the start order is wrong → restart in the order "service → bridge → call".

### Question 13: **Without a `.md`, how do I build?**

**This is the biggest change in the new version.** Interface contracts are read from the following entities:

- **stub signatures** (`internal_call_<Api>`) → API names, parameter types, return types.
- **test drivers** (`*_main_test___.*`) → call examples.
- **CMakeLists.txt** (C++) → target names, source files, link libraries.
- **setup_*_tests.ps1** (multi-language) → environment preparation steps.
- **the top comment block of the generated code** → dependencies, wire protocol, prohibitions.
- **the constant declarations in the generated code** → default base URL / timeout / bridge App name.

**See Chapter 3.** **Chapter 14 (Build and deployment in practice) of this document also gives the complete steps for each language.**

### Question 14: How do I build the generated C++?

Put `.hpp`, `.cpp`, `CMakeLists.txt` and `test_main___.cpp` into one directory, then:

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The CMake project builds two executables: `<Unit>_http_json_service` and `<Unit>_http_json_call_test`.

### Question 15: Does the CMake script copy the LingoFuse DLLs?

No. Copy `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` and `z_ipc_*` next to the executables, or add their directory to `PATH` / `LD_LIBRARY_PATH`.

### Question 16: Where are the generated Pascal test programs?

**In `<Unit>_http_json_service_main_test___.pas` and `<Unit>_http_json_call_main_test___.pas`.** They are complete test programs; compile them directly with `fpc`.

### Question 17: How do I build the generated Python service?

```bash
pip install requests
python3 <Unit>_http_json_service.py
```

**The `if __name__ == "__main__":` block starts the service.**

### Question 18: How do I build the generated C# service?

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

For the caller side, substitute `<Unit>_http_json_call.cs` and `<Unit>_http_json_call_main_test___.cs`.

### Question 19: How is the MCP tool provider unit built? Do I have to write it by hand?

No. It is produced by a **three-stage build**:

1. **Bootstrap script** — produces the structurally complete unit: callbacks, error envelope, tool schemas, LingoFuse registration, function shells.
2. **AI fill** — fills each `internal_call_*` body with UI-synchronization logic.
3. **Compile** — the unit is compiled into the GUI executable.

The AI's contribution is the small number of UI touches per tool; everything else is mechanical.

### Question 20: Why was the MCP tool count reduced from 24 to 3?

Because 24 tools were a **remote-control panel**, not an Agent-friendly API. The Agent's first action was always wrong, and correcting it took a whole round of regeneration. The three-tool design gives the Agent one tool per verb:

- `Generate` — one call produces every target.
- `ListFiles` — see what was produced.
- `GetFile` — read what you need.

The Agent succeeds on its first three-tool workflow attempt. That is the whole point.

### Question 21: **Why is `.md` no longer generated?**

Because `.md` generation produced **far too much documentation volume**. With multi-language targets, every `.md` had to maintain a complete set of build commands, troubleshooting tables and API references per language — the volume ballooned to an unacceptable size.

**With `.md` removed, the interface contracts are still obtainable from the generated code, the test drivers, the CMake script and `setup_*_tests.ps1`.** Those are living artifacts that are always in sync with the code. See Chapter 3 and Chapter 14.

### Question 22: What values does the `--lang` argument accept?

Run `code_decl_to_json_abi --list-languages` to see every registered language id. Common values include:

`pascal`, `python`, `cpp`, `csharp`, `javascript`, `nodejs`, `typescript`, `php`, `rust`, `go`, `java`, `delphi`, `dart`, `swift`, `ruby`, `zig`, `erlang`, `fortran`, `julia`, `r`.

### Question 23: Should the Rust caller use sync or async?

Either, depending on the scenario:

- **sync (`ureq`)**: simple, no async runtime, good for scripts and CLI tools.
- **async (`reqwest` + `tokio`)**: high concurrency, consistent with the `tokio` ecosystem, good for servers.

**Both variants are produced by the generator**; you can use just one of them.

### Question 24: Why must Julia use `--threads=2`?

Because Julia's LingoFuse binding needs at least two threads to work: one for the `start_callback_consumer` callback consumption, and one for the main thread's synchronous wait. `--threads=1` deadlocks.

### Question 25: Why must R's `*_async` functions use `plan("sequential")`?

Because `future`'s `multisession` / `multicore` plans fork worker processes, and the LingoFuse runtime is not initialized in the child process, so internal calls always fail. The generated `*_async` functions check `future::plan()` at dispatch time and raise immediately if the plan is incompatible. **For concurrency, use the synchronous function plus your own thread pool.**

### Question 26: How does the generated R service shut down gracefully?

The generated R service watches for a `service.exit` sentinel file. **Open a second PowerShell window** and run:

```powershell
'' > "<script-directory>\service.exit"
```

The service notices it on the next poll (within about 100 ms), runs `exit_main_thread` → `free_app` → `shutdown` in order, then exits. **Ctrl+C is a fallback**, but on some platforms it can leave the terminal in a bad state.

### Question 27: How does the generated Zig service handle Ctrl+C?

The generated Zig service waits for Enter via `readLine()` in `main`; after Enter it runs `exitMainThread` → `app.deinit()` → `shutdown()`. **Ctrl+C terminates the process directly through the OS, and LingoFuse cleanup is done by the OS**, so the user does not need to do anything extra.

### Question 28: What is the difference between `run_smoke_test/0` and `main/0` in the generated Erlang service?

- **`main/0`**: starts the full LingoFuse mesh (`prepare_service` + `prepare_client`), begins listening, and enters the event loop. Requires `bridge.py` to be running.
- **`run_smoke_test/0`**: **does not** start the mesh; it only creates an `AppHandle` inside the process and calls each API directly through `lingofuse:local_call/2`. **Does not need `bridge.py`**.

### Question 29: How does the generated Fortran code handle the NUL terminator?

LingoFuse strings are NUL-terminated. After reading a response, the generated Fortran caller uses the `strip_trailing_nul` helper to strip the trailing NUL before handing it to the JSON parser.

### Question 30: What is the difference between `main/0` and `run_smoke_test` in the generated Julia service?

- **`main/0`** (the generated module): fully starts the LingoFuse mesh and blocks until SIGINT.
- **`run_smoke_test`** (`run_smoke()` in the test program): creates an `AppHandle` inside the process and calls each API directly through `local_call`. **Does not need `bridge.py`**.

### Question 31: What are all those `LF_CDECL` / `LF_CDECL_FUNC` in the generated code?

`LF_CDECL` is the **calling-convention macro** provided by the LingoFuse C ABI. It expands to `__cdecl` (MSVC) or `__attribute__((cdecl))` (MinGW / clang-cl / GCC) depending on the platform. **The generated C++ service code uses it to declare the callbacks**, so LingoFuse can call them correctly across the C ABI.

**Do not redefine it.** If you need it in non-LingoFuse code, `#include "LingoFuse.h"` gives you the definition.

### Question 32: Why do I see `_SyncResultBox` / `@unchecked Sendable` in the generated code?

That is the **Swift generator**'s thread-safety wrapper for the synchronous call path. `DispatchSemaphore.wait()` / `.signal()` establish a happens-before relationship that the Swift concurrency checker cannot infer across the C callback boundary, hence the explicit `@unchecked Sendable` annotation. **This is correct and necessary** — not a hack.

### Question 33: How does the Rust generator handle the `ureq::Error::Status(200, response)` branch?

That is the `Status` variant `ureq` returns on 4xx / 5xx. The generated code reads the response body there and hands it to `parse_envelope` for uniform handling. `parse_envelope` checks the HTTP status code and constructs `HttpCallError` correctly.

### Question 34: Why does `int64` lose precision in JavaScript clients?

JS `Number` is an IEEE-754 double with a 53-bit mantissa. `2^53 + 1` does not equal `2^53 + 1`; it silently rounds. **Solution**: have the service return `int64` / `uint64` as strings and let the client parse them with a bignum library.

### Question 35: What is the difference between `HttpJsonCallError` and `LFHttpCallError`?

- **`HttpJsonCallError`**: the exception class name in TypeScript / PHP and other languages (Java uses `HTTPCallException`).
- **`LFHttpCallError`**: the exception class name in browser JavaScript (with the `LF` prefix, to avoid name collisions in the JS global scope).

**The two have exactly the same semantics**: `.code` / `.httpStatus` / `.message`.

---

## Chapter 14  Build and deployment in practice

This chapter is the most important supplementary chapter after the `.md` removal. Per language, it gives the **complete steps from artifacts to a runnable program**.

### 14.1 Pascal

#### 14.1.1 Dependencies

- FPC 3.2+ or Delphi 11+.
- `lingofuse_import.pas` (the LingoFuse Pascal binding).
- `Z.Core`, `Z.PascalStrings`, `Z.UPascalStrings`, `Z.Json`, `Z.UnicodeMixedLib`.

#### 14.1.2 Building the service side

```bash
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated-directory> \
    <Unit>_http_json_service_main_test___.pas
```

Or `uses` the generated unit in your own `.lpr`:

```pascal
program MyService;

uses
  SysUtils, lingofuse_import,
  <Unit>_http_json_service_unit;

var
  App: TAppHnd___;
begin
  App := CreateAndRegisterHTTPJsonApp;
  if App = nil then
  begin
    WriteLn('Failed to create app');
    Halt(1);
  end;
  LF_PrepareClientEx('ipc:<Unit>_http_json', App);
  if LF_PrepareDone() <> 1 then
  begin
    WriteLn('Failed to prepare');
    Halt(1);
  end;
  WriteLn('Service ready. Press Enter to stop.');
  ReadLn;
  LF_ExitMainThread;
  LF_FreeApp(App);
  LF_Shutdown;
end.
```

#### 14.1.3 Building the caller side

```bash
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated-directory> \
    <Unit>_http_json_call_main_test___.pas
```

#### 14.1.4 Deployment checklist

- `LingoFuse64.dll` (or `liblingofuse.so` / `liblingofuse.dylib`)
- `z_ipc_64.dll` (or `libz_ipc_64.so`)
- the generated `.pas` or `.ppu` files

### 14.2 Python

#### 14.2.1 Dependencies

```bash
pip install requests
```

The **service side** also needs the `lingofuse` Python package (installed from the LingoFuse distribution):

```bash
pip install <path-to-LingoFuse>/python
```

#### 14.2.2 Running the service side

```bash
python3 <Unit>_http_json_service.py
```

#### 14.2.3 Running the caller side

```bash
python3 <Unit>_http_json_call_main_test___.py
```

**Overriding the base URL**:

```bash
python3 <Unit>_http_json_call_main_test___.py http://10.0.0.5:8081/<Unit>
```

#### 14.2.4 Deployment checklist

- `LingoFuse64.dll` (service side)
- `z_ipc_64.dll`
- the generated `.py` files
- `PYTHONPATH` pointing at the LingoFuse Python package (service side)

### 14.3 C++

#### 14.3.1 Dependencies

- CMake 3.15+
- a C and a C++ compiler (MSVC / g++ / clang++)
- the LingoFuse C++ distribution directory

#### 14.3.2 Build

```bash
# make sure <Unit>_http_json_service.hpp/.cpp, <Unit>_http_json_call.hpp/.cpp,
# CMakeLists.txt and test_main___.cpp are all in the same directory.
cd <that-directory>

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

**Windows + MSVC**:

```cmd
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=C:\LingoFuse\cpp -G "Visual Studio 17 2022"
cmake --build build --config Release
```

#### 14.3.3 Deployment checklist

- `LingoFuse64.dll` (or `.so` / `.dylib`)
- `z_ipc_64.dll`
- the two executables: `<Unit>_http_json_service`, `<Unit>_http_json_call_test`

**DLL copying**: the CMake script does **not** copy the runtime DLLs. Copy them by hand, or set `PATH` / `LD_LIBRARY_PATH`.

### 14.4 C#

#### 14.4.1 Dependencies

- .NET 8.0+
- the LingoFuse .NET binding (`LingoFuse.dll`)
- the LingoFuse native libraries

#### 14.4.2 Building the service side

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

#### 14.4.3 Building the caller side

```bash
dotnet new console -o my_call
cd my_call
cp ../<Unit>_http_json_call.cs .
cp ../<Unit>_http_json_call_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

#### 14.4.4 Deployment checklist

- `LingoFuse64.dll` (or `.so` / `.dylib`)
- `z_ipc_64.dll`
- `LingoFuse.dll` (the .NET binding)
- the generated `.cs` files

### 14.5 JavaScript (browser)

#### 14.5.1 Dependencies

None. `fetch` is built into the browser.

#### 14.5.2 Usage

**Option A: double-click `*_test.html`**

Open the test page directly.

**Option B: include it in your own page**

```html
<script src="<Unit>_http_json_call.js"></script>
<script>
  (async () => {
    try {
      const r = await <Unit>Api.Add(1, 2);
      console.log('Add(1, 2) =', r);
    } catch (e) {
      console.error('Add failed:', e.message, 'code:', e.code);
    }
  })();
</script>
```

**Option C: serve it over HTTP**

```bash
python3 -m http.server 9000
# open http://127.0.0.1:9000/<Unit>_http_json_call_test.html
```

#### 14.5.3 CORS

The bridge program must return `Access-Control-Allow-Origin: *` (or a specific origin). `bridge.py` enables CORS by default; if it does not, add `--cors '*'` to the bridge launch arguments.

#### 14.5.4 Deployment checklist

- `LingoFuse64.dll` (service side)
- `z_ipc_64.dll`
- the generated `.js` and `.html`

### 14.6 Node.js

#### 14.6.1 Dependencies

```bash
npm install lingofuse-js
```

Or use the generated `setup_js_tests.ps1`.

#### 14.6.2 Running

**Service side**:

```bash
node <Unit>_http_json_service_node.js
```

**Caller side**:

```bash
node <Unit>_http_json_call_main_test___.js
```

**Overriding the base URL**:

```bash
node <Unit>_http_json_call_main_test___.js http://10.0.0.5:8081/<Unit>
```

### 14.7 TypeScript

#### 14.7.1 Dependencies

```bash
npm install lingofuse-ts tsx
```

Or use the generated `setup_ts_tests.ps1`.

#### 14.7.2 Running

**Service side**:

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_service.ts
```

**Caller side**:

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_call_main_test___.ts
```

### 14.8 PHP

#### 14.8.1 Dependencies

`curl_*` (preferred) or `fopen`. PHP 7.4+.

#### 14.8.2 Running the caller side

```bash
php <Unit>_http_json_call_main_test___.php
```

**Overriding the base URL**:

```bash
php <Unit>_http_json_call_main_test___.php http://10.0.0.5:8081/<Unit>
```

### 14.9 Rust

#### 14.9.1 Dependencies

**`Cargo.toml`** (caller side):

```toml
[dependencies]
ureq = "2"
reqwest = { version = "0.12", features = ["json"] }
tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }
serde_json = "1"
```

**`Cargo.toml`** (service side):

```toml
[dependencies]
lingofuse = { path = "../LingoFuse/rust" }
serde_json = "1"
```

#### 14.9.2 Running

**Service side**:

```bash
cargo new my_service
cd my_service
cp ../<Unit>_http_json_service_rs.rs src/main.rs
cargo run
```

**Caller side**:

```bash
cargo new my_call
cd my_call
cp ../<Unit>_http_json_call_rs.rs src/main.rs
cp ../<Unit>_http_json_call_main_test___.rs src/main.rs
cargo run
```

#### 14.9.3 Deployment checklist

- `LingoFuse64.dll` (or `.so` / `.dylib`)
- `z_ipc_64.dll`

### 14.10 Go

#### 14.10.1 Dependencies

```bash
go mod init calculator
go get github.com/PassByYou888/LingoFuse/go
```

#### 14.10.2 Running

**Service side**:

```bash
cp ../<Unit>_http_json_service_go.go .
cp ../<Unit>_http_json_service_main_test.go .
go test -v
# or
go build -o service .
./service
```

**Caller side**:

```bash
cp ../<Unit>_http_json_call_go.go .
cp ../<Unit>_http_json_call_main_test.go .
go test -v
```

### 14.11 Java

#### 14.11.1 Dependencies

- JDK 11+
- `jackson-databind.jar`
- `lingofuse.jar` (service side)

#### 14.11.2 Running

**Service side**:

```bash
javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonService
```

**Caller side**:

```bash
javac -cp jackson-databind.jar HttpJsonClient.java HttpJsonCallTest.java
java -cp .:jackson-databind.jar HttpJsonCallTest
```

### 14.12 Delphi

#### 14.12.1 Dependencies

Delphi 10.3+. `System.Net.HttpClient`, `System.JSON`.

#### 14.12.2 Compiling

```cmd
dcc32 <Unit>_http_json_call_delphi_test___.dpr
```

Or open the `.dpr` in the IDE and compile.

#### 14.12.3 Running

```cmd
<Unit>_http_json_call_delphi_test___.exe
```

### 14.13 Dart

#### 14.13.1 Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.0.0
```

#### 14.13.2 Running

**Caller side**:

```bash
dart run <Unit>_http_json_call_main_test___.dart
```

**Overriding the base URL**:

```bash
dart run <Unit>_http_json_call_main_test___.dart http://10.0.0.5:8081/<Unit>
```

### 14.14 Swift

#### 14.14.1 Dependencies

- Swift 5.9+
- macOS 12+ / iOS 15+ (needed for the async API)

#### 14.14.2 Running

**Caller side**:

```bash
swift <Unit>_http_json_call_main_test___.swift
```

**Windows / Linux**: Swift for Windows / Swift on Linux.

### 14.15 Ruby

#### 14.15.1 Dependencies

**Service side**:

```bash
gem install lingofuse
```

**Caller side**: the standard library only.

#### 14.15.2 Running

**Service side**:

```bash
ruby <Unit>_http_json_service.rb
```

**Caller side**:

```bash
ruby <Unit>_http_json_call_main_test___.rb
```

**Overriding the base URL**:

```bash
ruby <Unit>_http_json_call_main_test___.rb http://10.0.0.5:8081/<Unit>
```

### 14.16 Zig

#### 14.16.1 Dependencies

- Zig 0.13+
- the `lingofuse` Zig binding

#### 14.16.2 Running

**Using the generated `setup_zig_tests.ps1`**:

```powershell
.\setup_zig_tests.ps1 -ZigLibDir D:\LingoFuse\zig -BinaryDir D:\LingoFuse\Binary
```

The script creates the two projects `zig_service_test/` and `zig_call_test/`.

**Manually**:

```bash
cd zig_service_test
zig build run
```

### 14.17 Erlang

#### 14.17.1 Dependencies

- Erlang/OTP 25+
- the `lingofuse` Erlang binding

#### 14.17.2 Running

**Using the generated `setup_erlang_tests.ps1`**:

```powershell
.\setup_erlang_tests.ps1 -ErlangBindingDir D:\LingoFuse\erlang -RunSmoke
```

**Manually**:

```bash
erlc -o ebin <Unit>_http_json_service.erl
escript <Unit>_http_json_service_main_test___.escript
```

### 14.18 Fortran

#### 14.18.1 Dependencies

- gfortran 9+
- `lf_fortran_mod.f90` + `lf_fortran.cpp`

#### 14.18.2 Running

**Using the generated `setup_fortran_tests.ps1`**:

```powershell
.\setup_fortran_tests.ps1 -FortranLibDir D:\LingoFuse\fortran\c_ext -RunSmoke
```

### 14.19 Julia

#### 14.19.1 Dependencies

- Julia 1.9+
- the `LingoFuse` and `JSON3` packages
- `--threads=2` is mandatory

#### 14.19.2 Running

**Using the generated `setup_julia_tests.ps1`**:

```powershell
.\setup_julia_tests.ps1 -JuliaBindingDir D:\LingoFuse\julia -RunSmoke
```

**Manually**:

```bash
julia --project=<GenDir> --threads=2 <Unit>_http_json_service_main_test___.jl
```

### 14.20 R

#### 14.20.1 Dependencies

- R 4.0+
- the four packages `lingofuse`, `jsonlite`, `httr`, `future`

#### 14.20.2 Running

**Using the generated `setup_r_tests.ps1`**:

```powershell
.\setup_r_tests.ps1 -RLibDir D:\LingoFuse\r\lingofuse -InstallMissing -RunSmoke
```

**Manually**:

```bash
Rscript <Unit>_http_json_service.R
Rscript <Unit>_http_json_call_main_test___.R
```

---

## Chapter 15  A complete walkthrough of a typical workflow

This chapter walks through the complete flow from source text to a running test, using one concrete example.

### 15.1 The input source text

`Calculator.pas`:

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

### 15.2 The GUI walkthrough

1. **Start**: double-click `code_decl_to_json_abi.exe` (no arguments).
2. **Page 1 Welcome**: click "Next: Enter source code".
3. **Page 2 Source Code**: paste the contents of `Calculator.pas`; click "Select Language" to auto-detect; click "Next: Pascal/C → JSON".
4. **Page 3 Source ↔ JSON**: check that the LV0 JSON contains `Add` and `Sub`; click "Next: JSON ↔ Model".
5. **Page 4 JSON ↔ Model**: check that the LV1 Model contains both functions; click "Next: generate source".
6. **Page 5 Final Source**: browse each sub-tab; confirm the files were written to the `<exe>/Calculator/` directory.

**The artifact directory**:

```
<exe>/Calculator/
├── Calculator_http_json_service_unit.pas
├── Calculator_http_json_call_unit.pas
├── Calculator_http_json_service_main_test___.pas
├── Calculator_http_json_call_main_test___.pas
├── Calculator_http_json_call.js
├── Calculator_http_json_call_test.html
├── Calculator_http_json_service.py
├── Calculator_http_json_call.py
├── Calculator_http_json_service_main_test___.py
├── Calculator_http_json_call_main_test___.py
├── Calculator_http_json_service.cs
├── Calculator_http_json_call.cs
├── Calculator_http_json_service_main_test___.cs
├── Calculator_http_json_call_main_test___.cs
├── Calculator_http_json_service.hpp
├── Calculator_http_json_service.cpp
├── Calculator_http_json_call.hpp
├── Calculator_http_json_call.cpp
├── CMakeLists.txt
└── test_main___.cpp
```

### 15.3 Reading the contracts from the artifacts

**Open `Calculator_http_json_service_unit.pas`**:

```pascal
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
```

→ **API name**: `Add`; **parameters**: `a: Int64`, `b: Int64`; **return**: `Int64`.

**Open `Calculator_http_json_call_unit.pas`**:

```pascal
var
  HTTP_CALL_BASE_URL: string = 'http://127.0.0.1:8081/Calculator';
  HTTP_CALL_TIMEOUT_MS: Integer = 30000;
```

→ **default base URL**: `http://127.0.0.1:8081/Calculator`; **default timeout**: 30000ms.

**Open `Calculator_http_json_call_main_test___.pas`**:

```pascal
Test_Add_Sync;
Test_Add_Async;
```

→ **call example**: `Test_Add_Sync;` / `Test_Add_Async;`.

### 15.4 Compiling and running

**Terminal 1 (service)**:

```bash
cd <exe>/Calculator
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    Calculator_http_json_service_main_test___.pas
./Calculator_http_json_service_main_test___
```

**Terminal 2 (bridge)**:

```bash
python3 bridge.py --endpoint ipc:Calculator_http_json --port 8081 --no-precheck
```

**Terminal 3 (call)**:

```bash
cd <exe>/Calculator
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    Calculator_http_json_call_main_test___.pas
./Calculator_http_json_call_main_test___
```

**Expected output**:

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add [sync] : OK
  Add [async]: OK
  Sub [sync] : OK
  Sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 15.5 The CLI walkthrough

**Generate the service side**:

```bash
code_decl_to_json_abi Calculator.pas calculator_service.pas
```

**Generate the caller side**:

```bash
code_decl_to_json_abi --call Calculator.pas calculator_call.pas
```

**Compile and run** (same as §15.4).

### 15.6 The MCP walkthrough

```json
// 1. Generate
{
  "tool": "CodeDeclToJsonAbi_Generate",
  "arguments": {
    "Source": "unit Calculator; ... end.",
    "Language": "pascal"
  }
}
// → {"status":"ok","unit_name":"Calculator","count":20,"files":[...]}

// 2. ListFiles
{ "tool": "CodeDeclToJsonAbi_ListFiles", "arguments": {} }
// → {"status":"ok","count":20,"files":[...]}

// 3. GetFile (read the contracts)
{ "tool": "CodeDeclToJsonAbi_GetFile",
  "arguments": { "FileName": "Calculator_http_json_service_unit.pas" } }
// → read the stub signatures to get the API names and types

{ "tool": "CodeDeclToJsonAbi_GetFile",
  "arguments": { "FileName": "Calculator_http_json_call_main_test___.pas" } }
// → read the call examples
```

**Note**: **there is no `_readme.md` to pull.** Every contract is read from the code.

---

## Appendix A — The artifact list of one run

### A.1 Five-language scope (20 artifacts)

See §10.4.

### A.2 All-language scope

If the model triggers every registered language, the artifacts are:

```
<U>_http_json_service_unit.pas
<U>_http_json_call_unit.pas
<U>_http_json_service_main_test___.pas
<U>_http_json_call_main_test___.pas
<U>_http_json_call.js
<U>_http_json_call_test.html
<U>_http_json_service.py
<U>_http_json_call.py
<U>_http_json_service_main_test___.py
<U>_http_json_call_main_test___.py
<U>_http_json_service.cs
<U>_http_json_call.cs
<U>_http_json_service_main_test___.cs
<U>_http_json_call_main_test___.cs
<U>_http_json_service.hpp
<U>_http_json_service.cpp
<U>_http_json_call.hpp
<U>_http_json_call.cpp
<U>_http_json_service_node.js
<U>_http_json_call_node.js
<U>_http_json_service_main_test___.js
<U>_http_json_call_main_test___.js
<U>_http_json_service.ts
<U>_http_json_call_ts.ts
<U>_http_json_service_main_test___.ts
<U>_http_json_call_main_test___.ts
<U>_http_json_service_rs.rs
<U>_http_json_call_rs.rs
<U>_http_json_service_main_test___.rs
<U>_http_json_call_main_test___.rs
<U>_http_json_service_go.go
<U>_http_json_call_go.go
<U>_http_json_service_main_test.go
<U>_http_json_call_main_test.go
HttpJsonService.java
HttpJsonClient.java
HttpJsonServiceTest.java
HttpJsonCallTest.java
<U>_http_json_service_swift.swift
<U>_http_json_call_swift.swift
<U>_http_json_service_main_test___.swift
<U>_http_json_call_main_test___.swift
<U>_http_json_service.rb
<U>_http_json_call.rb
<U>_http_json_service_main_test___.rb
<U>_http_json_call_main_test___.rb
<U>_http_json_service_zig.zig
<U>_http_json_call_zig.zig
<U>_http_json_service_main_test___.zig
<U>_http_json_call_main_test___.zig
<U>_http_json_service.erl
<U>_http_json_call.erl
<U>_http_json_service_main_test___.escript
<U>_http_json_call_main_test___.escript
<U>_http_json_service_mod.f90
<U>_http_json_call_mod.f90
<U>_http_json_service_main_test___.f90
<U>_http_json_call_main_test___.f90
<U>_http_json_service.jl
<U>_http_json_call.jl
<U>_http_json_service_main_test___.jl
<U>_http_json_call_main_test___.jl
<U>_http_json_service.R
<U>_http_json_service_impl.R
<U>_http_json_call.R
<U>_http_json_service_main_test___.R
<U>_http_json_call_main_test___.R
<U>_http_json_call_delphi.pas
<U>_http_json_call_delphi_test___.dpr
<U>_http_json_call.dart
<U>_http_json_service.dart
<U>_http_json_service_main_test___.dart
<U>_http_json_call_main_test___.dart
<U>_http_json_call_php.php
<U>_http_json_call_main_test___.php
CMakeLists.txt
test_main___.cpp
launch_bridge.ps1
setup_js_tests.ps1
setup_ts_tests.ps1
setup_zig_tests.ps1
setup_erlang_tests.ps1
setup_fortran_tests.ps1
setup_julia_tests.ps1
setup_r_tests.ps1
```

**90+ in total. Not one of them is a `_readme.md`.**

**The real list is whatever the MCP `Generate` return value or the GUI's "Final Source" list says.**

---

## Appendix B — Quick reference for error codes and exception types

### B.1 Wire error codes

| Code | Meaning | Typical HTTP status |
|:-:|------|:--------------:|
| `0` | success. Never reported as an error. | 200 |
| `-1` | remote call failed (service-side exception, network failure, timeout). | 200 or 0 |
| `-2` | request shape error (malformed URL path, un-serializable request body). | 400 |
| `-3` | bridge pre-check failed (the bridge's local cache has not yet seen that API). | 200 |
| `-4` | bridge protocol error (malformed envelope, missing field). | 200 |

### B.2 Tool-level error JSON

| Tool | Success | Failure |
|------|------|------|
| `Generate` | `{"status":"ok","unit_name":"...","count":N,"files":[...]}` | `{"error":"<message>"}` |
| `ListFiles` | `{"status":"ok","count":N,"files":[...]}` | `{"status":"error",...}` |
| `GetFile` | `{"status":"ok","name":"...","text":"..."}` | `{"status":"error","name":"...","error":"..."}` |

### B.3 Exception classes per language

See §11.6.

### B.4 Common error message cross-reference

| Message | Source |
|------|------|
| `Unsupported language. Use pascal or c.` | MCP `Generate` |
| `Form not available` | all three MCP tools (GUI not running) |
| `File not found. Call ListFiles first to get valid names.` | MCP `GetFile` |
| `Generation failed: <reason>` | MCP `Generate` |
| `LF_PrepareClient returned -1` | LingoFuse failed to start |
| `LF_PrepareDone returned 0` | LingoFuse already started (already called in this process) |
| `no found app("<name>")` | LingoFuse routing failure |
| `3029 function header doesn't match` | FPC overload conflict |
| `Illegal expression` / `Syntax error, ";" expected` | FPC inline-variable misuse |
| `Cannot determine link language` | CMake, `project()` declares only `CXX` |
| `dynamic constant assignment` | Ruby assignment to a constant |
| `@unchecked Sendable` warning | Swift concurrency check (a correct annotation, not a bug) |
| `PyImportError` / `ModuleNotFoundError` | missing `requests` / `lingofuse` |
| `cargo: no such command: add` | Rust too old; upgrade to get `cargo add` |
| `go: module github.com/PassByYou888/LingoFuse not found` | `go get` was not run |
| `ClassNotFoundException: lingofuse.AppHandle` | `lingofuse.jar` not on the classpath |

---

## Appendix C — Command-line argument quick reference

| Argument | Short form | Explanation |
|------|:----:|------|
| `--help` | `-h` / `-?` / `/?` | print help and exit |
| `--list-languages` | `-ll` | list every registered target language |
| `--call` | `-c` | generate the caller side (default is the service side) |
| `--lang <id>` | `-l <id>` | force the target language |
| `<input_file>` | — | the input source file |
| `<output_file>` | — | the output file / directory |

### C.1 Input extension → source language

| Extension | Source language |
|--------|--------|
| `.pas` / `.pp` / `.p` | Pascal |
| `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` | C |

### C.2 Output extension → target language

See §6.4.

### C.3 Exit codes

| Code | Meaning |
|:-:|------|
| `0` | success |
| `1` | missing or invalid arguments |
| `2` | source parsing failed |
| `3` | code generation failed |
| `4` | file I/O error |

---

## Appendix D — MCP tool parameter quick reference

### D.1 `CodeDeclToJsonAbi_Generate`

| Parameter | Type | Required | Explanation |
|------|------|:----:|------|
| `Source` | string | ✅ | the complete source text |
| `Language` | string | ✅ | `"pascal"` or `"c"`, case-insensitive |

### D.2 `CodeDeclToJsonAbi_ListFiles`

No parameters.

### D.3 `CodeDeclToJsonAbi_GetFile`

| Parameter | Type | Required | Explanation |
|------|------|:----:|------|
| `FileName` | string | ✅ | must be a value previously returned by `ListFiles`, case-sensitive |

---

## Appendix E — Language support matrix

| # | Language | Service | Call | Test | Build script | Dependencies | Special requirements |
|:-:|------|:----:|:----:|:----:|:--------:|------|----------|
| 1 | Pascal | ✅ | ✅ | ✅ | — | `lingofuse_import`, `Z.Core` | FPC 3.2+ or Delphi 11+ |
| 2 | Python | ✅ | ✅ | ✅ | — | `requests` | Python 3.8+ |
| 3 | C++ | ✅ | ✅ | ✅ | ✅ | `LingoFuse.hpp`, `lf_http_bridge_client.hpp`, `json.hpp` | C++17, CMake 3.15+ |
| 4 | C# | ✅ | ✅ | ✅ | — | LingoFuse .NET binding | .NET 8.0+ |
| 5 | JavaScript | ❌ | ✅ | ✅ | — | none (browser `fetch`) | a modern browser |
| 6 | Node.js | ✅ | ✅ | ✅ | ✅ | `lingofuse-js` | Node 18+ |
| 7 | TypeScript | ✅ | ✅ | ✅ | ✅ | `lingofuse-ts`, `tsx` | TS 5.0+, Node 18+ |
| 8 | PHP | ❌ | ✅ | ✅ | — | `curl_*` or `fopen` | PHP 7.4+ |
| 9 | Rust | ✅ | ✅ | ✅ | — | `lingofuse`, `ureq`, `reqwest`, `tokio`, `serde_json` | Rust 1.70+ |
| 10 | Go | ✅ | ✅ | ✅ | — | the `lingofuse` Go package | Go 1.21+ |
| 11 | Java | ✅ | ✅ | ✅ | — | the `lingofuse` Java package, Jackson | JDK 11+ |
| 12 | Delphi | ❌ | ✅ | ✅ | — | `System.Net.HttpClient` | Delphi 10.3+ |
| 13 | Dart | ✅ | ✅ | ✅ | — | the `http` package | Dart 3.0+ |
| 14 | Swift | ✅ | ✅ | ✅ | — | Foundation | Swift 5.9+ / macOS 12+ |
| 15 | Ruby | ✅ | ✅ | ✅ | — | the `lingofuse` gem | Ruby 2.7+ / 3.0+ |
| 16 | Zig | ✅ | ✅ | ✅ | ✅ | the `lingofuse` Zig binding | Zig 0.13+ |
| 17 | Erlang | ✅ | ✅ | ✅ | ✅ | the `lingofuse` Erlang binding, `httpc` | OTP 25+ |
| 18 | Fortran | ✅ | ✅ | ✅ | ✅ | `lf_fortran_mod.f90`, `lf_fortran.cpp` | gfortran 9+ |
| 19 | Julia | ✅ | ✅ | ✅ | ✅ | `LingoFuse`, `JSON3` | Julia 1.9+, `--threads=2` |
| 20 | R | ✅ | ✅ | ✅ | ✅ | `lingofuse`, `jsonlite`, `httr`, `future` | R 4.0+ |
| 21 | Bridge launch | — | — | — | ✅ | `bridge.py` | PowerShell 5.1+ |

**Notes**:

- "✅" means that direction / artifact is registered and has a generator.
- "❌" means there is no generator for that direction / artifact.
- The "Special requirements" column lists only the **hard prerequisites the user must know**, not the full dependency tree.

---

## Appendix F — Cross-reference of interface-contract sources

| Contract type | Authoritative source | File example |
|----------|----------|----------|
| **API name** | registration table | the `LF_RegisterCallEx` calls in `<U>_http_json_service_unit.pas` |
| **Parameter types and count** | stub signature | `internal_call_Add(a: Int64; b: Int64)` |
| **Return type** | stub signature | `): Int64;` |
| **Wire request shape** | fixed protocol | `{ "args": [v1, v2, ...] }` (see Chapter 10) |
| **Wire response shape** | fixed protocol | `{ "code": 0, "result": ... }` / `{ "code": -1, "error": ... }` |
| **Call example** | test driver | `<U>_http_json_call_main_test___.pas` |
| **Build command** | CMake script / `setup_*_tests.ps1` / Chapter 14 | `CMakeLists.txt`, `setup_js_tests.ps1` |
| **Default base URL** | code constant declaration | `HTTP_CALL_BASE_URL` / `DEFAULT_BASE_URL` |
| **Default timeout** | code constant declaration | `HTTP_CALL_TIMEOUT_MS` / `DEFAULT_TIMEOUT_SECS` |
| **Bridge App name** | code constant declaration | `__lf_http_bridge__` (the same default in every language) |
| **Bridge API name** | code constant declaration | `__lf_outbound_post__` (the same default in every language) |
| **Service endpoint name** | code constant declaration | `HTTP_SERVICE_ENDPOINT` / `ENDPOINT` |
| **Environment variables** | top comment block of the generated code | `LINGOFUSE_DEBUG`, `PYTHONPATH` etc. |
| **Wire protocol** | top comment block of the generated code | "request = { args: [...] }" / "response = { code, result }" |
| **Prohibitions** | top comment block of the generated code | "do not redefine LF_CDECL" / "must init/deinit" |

---

## Appendix G — Quick reference for artifact file suffixes by target language

| Language | Service artifact suffix | Caller artifact suffix | Test artifact suffix | Build script |
|------|-------------|-------------|-------------|----------|
| Pascal | `_http_json_service_unit.pas` | `_http_json_call_unit.pas` | `_http_json_service_main_test___.pas` / `_http_json_call_main_test___.pas` | — |
| Python | `_http_json_service.py` | `_http_json_call.py` | `_http_json_service_main_test___.py` / `_http_json_call_main_test___.py` | — |
| C++ | `_http_json_service.hpp` + `_http_json_service.cpp` | `_http_json_call.hpp` + `_http_json_call.cpp` | `test_main___.cpp` | `CMakeLists.txt` |
| C# | `_http_json_service.cs` | `_http_json_call.cs` | `_http_json_service_main_test___.cs` / `_http_json_call_main_test___.cs` | — |
| JavaScript | (not supported) | `_http_json_call.js` | `_http_json_call_test.html` | — |
| Node.js | `_http_json_service_node.js` | `_http_json_call_node.js` | `_http_json_service_main_test___.js` / `_http_json_call_main_test___.js` | `setup_js_tests.ps1` |
| TypeScript | `_http_json_service.ts` | `_http_json_call_ts.ts` | `_http_json_service_main_test___.ts` / `_http_json_call_main_test___.ts` | `setup_ts_tests.ps1` |
| PHP | (not supported) | `_http_json_call_php.php` | `_http_json_call_main_test___.php` | — |
| Rust | `_http_json_service_rs.rs` | `_http_json_call_rs.rs` | `_http_json_service_main_test___.rs` / `_http_json_call_main_test___.rs` | — |
| Go | `_http_json_service_go.go` | `_http_json_call_go.go` | `_http_json_service_main_test.go` / `_http_json_call_main_test.go` | — |
| Java | `HttpJsonService.java` | `HttpJsonClient.java` | `HttpJsonServiceTest.java` / `HttpJsonCallTest.java` | — |
| Delphi | (not supported) | `_http_json_call_delphi.pas` | `_http_json_call_delphi_test___.dpr` | — |
| Dart | `_http_json_service.dart` | `_http_json_call.dart` | `_http_json_service_main_test___.dart` / `_http_json_call_main_test___.dart` | — |
| Swift | `_http_json_service_swift.swift` | `_http_json_call_swift.swift` | `_http_json_service_main_test___.swift` / `_http_json_call_main_test___.swift` | — |
| Ruby | `_http_json_service.rb` | `_http_json_call.rb` | `_http_json_service_main_test___.rb` / `_http_json_call_main_test___.rb` | — |
| Zig | `_http_json_service_zig.zig` | `_http_json_call_zig.zig` | `_http_json_service_main_test___.zig` / `_http_json_call_main_test___.zig` | `setup_zig_tests.ps1` |
| Erlang | `_http_json_service.erl` | `_http_json_call.erl` | `_http_json_service_main_test___.escript` / `_http_json_call_main_test___.escript` | `setup_erlang_tests.ps1` |
| Fortran | `_http_json_service_mod.f90` | `_http_json_call_mod.f90` | `_http_json_service_main_test___.f90` / `_http_json_call_main_test___.f90` | `setup_fortran_tests.ps1` |
| Julia | `_http_json_service.jl` | `_http_json_call.jl` | `_http_json_service_main_test___.jl` / `_http_json_call_main_test___.jl` | `setup_julia_tests.ps1` |
| R | `_http_json_service.R` + `_http_json_service_impl.R` | `_http_json_call.R` | `_http_json_service_main_test___.R` / `_http_json_call_main_test___.R` | `setup_r_tests.ps1` |
| Bridge | — | — | — | `launch_bridge.ps1` |

**General suffix conventions**:

- **there is no `_readme.md` artifact** (the `.md` generation feature has been removed).
- every artifact with `FixedName = True` (`CMakeLists.txt` / `test_main___.cpp` / `launch_bridge.ps1` / `setup_*_tests.ps1`) is written under its exact name with no `<Unit>` prefix.

---

## Appendix H — Glossary

| Term | Meaning |
|------|------|
| **LV0 JSON** | the intermediate representation the parser emits directly. Contains source positions, raw type spellings and modifiers. |
| **LV1 Model** | the normalized intermediate model. The single input of every generator. Contains `UnitName`, `Functions`, `Params`, `Comments`. |
| **ABI family** | the three supported type sets in this toolchain: the integer family, the float family and the string family. |
| **PascalType** | the normalized type field in the LV1 model. Generators use it to decide the target type. |
| **internal_call_<Api>** | the stub function the generator leaves for the user to fill in. **Do not rename it**; regenerating loses your body. |
| **Bridge (bridge program)** | `bridge.py` / `bridge.exe`. The HTTP↔RPC forwarder. **Must always be running**. |
| **Beacon** | the LingoFuse service that registers Agent tools (default `agent_main_app`). |
| **MCP** | Model Context Protocol. This tool exposes 3 tools to Agents through it. |
| **TCompute.Sync** | a synchronization primitive that dispatches a nested procedure onto the main thread and blocks until it completes. Every UI touch must happen inside it. |
| **ApiName** | the normalized routine name. Used for URL path segments, JSON keys and target-language identifiers. |
| **MakeApiName** | the function that normalizes an arbitrary string into a safe ApiName. **Every generator must use the same character-replacement rules**. |
| **Target Language** | the language of the generated artifacts (Pascal / Python / C++ / C# / JavaScript / ...). |
| **Source Language** | the language of the input source text (only `pascal` / `c`). |
| **Wire Type** | the JSON wire type. This toolchain uses only two: `number` and `string`. |
| **Fixed Name** | an artifact file name that does not vary with the `<Unit>` prefix (`CMakeLists.txt` / `test_main___.cpp` / `launch_bridge.ps1` / `setup_*_tests.ps1`). |
| **Readme (removed)** | the former `*_readme.md` artifact. The new version no longer generates it. Interface contracts are read from the code itself. |
| **Service** | the service side. Registers the functions as LingoFuse Call APIs. |
| **Call** | the caller side. Turns local function calls into HTTP POSTs. |
| **Test** | test programs. Service-side self-test + caller-side end-to-end test. |
| **Bridge Setup** | the bridge launch script (`launch_bridge.ps1`). |
| **Setup Script** | each language's test-environment setup script (`setup_*_tests.ps1`). |
| **Stub Signature** | the signature of `internal_call_<Api>`. **The final definition of the interface contract**. |
| **CMake Target** | the `add_executable` target name in `CMakeLists.txt`. The sole authority for the C++ build. |
| **Test Driver** | `*_main_test___.*`. The most authoritative source of call examples. |

---

## Appendix I — One-sentence summary of each usage mode

- **GUI**: five tabs, click left to right; when something goes wrong, step back and fix it. **No `.md` sub-tab**; interface contracts are read from the code, the CMake script and the test drivers. The **CMake** sub-tab holds the two CMake artifacts.
- **CLI**: `code_decl_to_json_abi [--call] [--lang <id>] input output`; the extension decides the language and the exit code decides success. **No `<base>_readme.md`**; interface contracts are read from the code. For a C++ target also look at `CMakeLists.txt` and `test_main___.cpp` in the same directory.
- **Agent**: `Generate` → `ListFiles` → `GetFile`. Three tools, a two-step flow, one session. **There is no `.md` to read**; read the contracts from the stub signatures, the test drivers, the CMake script and `setup_*_tests.ps1`.
- **Programmatic**: call the `Generate*Code` functions directly; for C++ also call `GenerateCMakeScript` and `GenerateTestMainCpp`; for C# also call `GenerateHTTPServiceCsharpTestCode` and `GenerateHTTPCallCsharpTestCode`. **`Generate*Readme` is no longer needed.**

**The one rule to remember at runtime**: **the bridge program (`bridge.py` or `bridge.exe`) is the forwarder and must always be running.**

**The one rule to remember after generation**: **there is no `.md` to read. Read the interface contracts from the stub signatures, the test drivers, the CMake script, `setup_*_tests.ps1` and the top comment block of the generated code.** See Chapter 3 and Chapter 14.

---

*Document version: v3 Chinese expanded edition (no Markdown artifacts)*
*Document role: the user-facing guide for code_decl_to_json_abi. For a deeper architectural reference see code_decl_to_json_abi_knowledge_base.md.*
