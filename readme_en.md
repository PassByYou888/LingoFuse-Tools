# LingoFuse-Tools

> *English translation of [readme.md](readme.md).*

> **One Pascal unit or one C header file covers the entire cross-language interface line.**
>
> Code, tests, build scripts, knowledge bases — all grown from the same model, so they never drift.

[LingoFuse](https://github.com/PassByYou888/LingoFuse) is the foundation for cross-language communication. **LingoFuse-Tools** is its **interface generation layer**: it turns the Pascal functions or C functions you are already writing into service / call code that any target language can **call directly** — no IDL to write, no stubs to hand-code, no need to maintain a separate "what the interface looks like" copy for every language.

[Download the pre-built package](https://github.com/PassByYou888/LingoFuse-Tools/releases/tag/pre_build)

> **A note from the author**: this repository was open-sourced simply because it was convenient for my own use. The problem it solves is very specific — I change a Pascal declaration once and do not want to manually sync call code and test assertions across 20 languages. It does not aim to be a "general-purpose code generation framework", and it does no community management. MIT, take it and use it.

---

## The real problem this repository solves: the maintenance entropy of interfaces

The expensive part of a cross-language interface is not "writing it the first time", but **whether, after one change, all languages, all tests, all build scripts and all documentation can keep up together**.

Once `Add(a, b: Integer): Integer` is written, you have to write a call once in Python, a header/impl once in C++, a P/Invoke wrapper once in C#, an assertion once in each test, add a target in CMake, and write "how to use this API" once in the README. **Every additional language doubles the entropy; every signature change can leave an inconsistent byte somewhere.**

LingoFuse-Tools does exactly one thing: **turn the "interface" from something you maintain into something you generate.** You maintain **one declaration**. The generator is responsible for projecting that declaration onto every target language, every protocol, every test and build script. Change the declaration, regenerate, and all targets refresh together. **There is no such thing as "C++ was changed but Rust was forgotten", because there is no hand-written "Rust version" to remember.**

---

## Three tool lines: one declaration, three ways to "reach the other side"

This repository is not "one generator" but **three parallel projection lines**. They share the same parser, the same intermediate model (LV1), and the same type whitelist. The only differences are **which protocol ships the request to the other side** and **what the product set looks like**.

| Tool | Protocol | Positioning in one sentence |
|---|---|---|
| **`code_decl_to_abi`** | LingoFuse binary ABI | When both ends are LingoFuse native, take the shortest path: fixed-width binary, zero JSON parsing, zero text encoding |
| **`code_decl_to_json_abi`** | HTTP + JSON (via `bridge.py`) | When one end is a browser, an external HTTP client, or a language without a LingoFuse binding, "lend out" LingoFuse's mesh capabilities over HTTP |
| **`code_decl_to_mcp`** | MCP (Model Context Protocol) | Turn functions directly into tools an AI Agent can discover; the Agent does not need to know LingoFuse, only MCP |

**The selection rule compresses into one sentence**: if the other side **can** load the LingoFuse runtime, prefer ABI; if it **cannot**, use JSON ABI; if the other side is an **Agent**, use MCP.

The three product sets differ — ABI emits service/call source code and tests, JSON ABI additionally emits bridge configuration and an HTML test page, MCP emits a tool provider and tool schema — but **the input contract is the same one**. What you write in a `.pas` or `.h` file is understood by all three lines.

---

## Language support: what each line covers

All three tables below **rely solely on the generator files in the repository's directory tree**. A language appears in the table only if there is a generator unit for it on that tool line.

### `code_decl_to_abi` — the binary ABI line

| Target language | Service | Call | Test | Setup |
|---|:---:|:---:|:---:|:---:|
| Pascal | ✅ | ✅ | ✅ | — |
| Python | ✅ | ✅ | ✅ | — |
| C++ | ✅ | ✅ | ✅ | — (handled by `CMakeLists.txt`) |
| C# | ✅ | ✅ | ✅ | — |
| Rust | ✅ | ✅ | ✅ | ✅ |
| Go | ✅ | ✅ | ✅ | ✅ |
| Java | ✅ | ✅ | ✅ | ✅ |
| Node.js | ✅ | ✅ | ✅ | ✅ |
| TypeScript | ✅ | ✅ | ✅ | ✅ |
| Erlang | ✅ | ✅ | ✅ | ✅ |
| Julia | ✅ | ✅ | ✅ | ✅ |
| Zig | ✅ | ✅ | ✅ | ✅ |
| Swift | ✅ | ✅ | ✅ | ✅ |
| Ruby | ✅ | ✅ | ✅ | ✅ |
| Fortran | ✅ | ✅ | ✅ | ✅ |
| Dart | ✅ | ✅ | ✅ | ✅ |
| R | ✅ | ✅ | ✅ | ✅ |

**17 target languages, all with both Service and Call generation capability.**

### `code_decl_to_json_abi` — the HTTP/JSON line

| Target language | Service | Call | Notes |
|---|:---:|:---:|---|
| Pascal / Python / C++ / C# / Rust / Go / Java / Node.js / TypeScript / Erlang / Julia / Zig / Swift / Ruby / Fortran / Dart / R | ✅ | ✅ | 17 languages, consistent with the ABI line |
| **JavaScript (browser)** | ❌ | ✅ | **Call side only** |
| **PHP** | ❌ | ✅ | **Call side only** |
| **Delphi** | ❌ | ✅ | **Call side only** |

**The JSON line covers 20 target languages, of which 3 (JS / PHP / Delphi) have only the Call side.**

### `code_decl_to_mcp` — the MCP line

| Target language | Generator |
|---|---|
| Pascal | `pas_mcp_generator_tool` |
| Python | `py_mcp_generator_tool` |
| C++ | `cpp_mcp_generator_tool` |
| C# | `csharp_mcp_generator_tool` |

**The MCP line currently delivers 4 languages.** There is also `cmake_for_cpp_mcp_generator_tool`, which generates the CMake build script for the C++ side.

### Summary

| Tool line | Service languages | Call languages | Total languages involved |
|---|:---:|:---:|:---:|
| `code_decl_to_abi` | 17 | 17 | **17** |
| `code_decl_to_json_abi` | 17 | 20 | **20** |
| `code_decl_to_mcp` | 4 | 4 | **4** |
| **Total across the three lines (deduplicated)** | — | — | **20** |

> **Delphi, PHP and JavaScript (browser) appear only on the JSON line, and only on the Call side.** They have no Service generation capability, and no ABI / MCP generators.

---

## The governing principle: generation boundaries are set by the "type whitelist", not by "language"

LingoFuse-Tools has a design that does not look much like a "code generator": **it does not try to understand arbitrary types; it only recognizes three ABI families — integers, floats, and strings.**

This means:

- Whether a function **can be generated** depends neither on whether it is Pascal or C, nor on whether the target language is Rust or R, but only on whether its parameters and return value fall into these three families.
- `Boolean`, `Variant`, arrays, records, classes, interfaces, enums, pointers, `TDateTime` — **the whole declaration is silently dropped**. It is not "partially generated", and it is not "reported later at runtime". The generator filters them out during the normalization stage and leaves one line in the log with the reason.
- Complex structures cannot "pass through", but they can be **downgraded**: stuff JSON into a `string` and let the other side deserialize it itself. This is the only supported "complex type escape hatch".

This principle determines the **applicable shape** of this repository: it best fits systems whose **interfaces are naturally numeric/string intensive** — compute engines, protocol gateways, data pipelines, embedded control planes. If an interface is inherently "pass an object in, pass an object out", LingoFuse-Tools forces you to make an explicit serialization decision at the declaration level. That friction is deliberate, not a defect.

---

## Engineering positioning: not "yet another gRPC code generator", but "a single source of truth for cross-language interfaces"

A gRPC `.proto` is an **interface definition**, and what it generates are **stubs**. LingoFuse-Tools' `.pas` / `.h` is **the implementation itself**, and what it generates is **the layer that exposes the implementation as remotely callable**.

This difference has three engineering consequences:

**First, it has no "IDL drift" failure mode.** The function is already in the header file. You do not need to maintain an IDL separate from the implementation, so the classic drift of "the IDL changed but the implementation did not" or "the implementation changed but the IDL did not" cannot occur.

**Second, it is "whole-product" generation, not "client stub only".** One run of `code_decl_to_abi` produces the service side (registering the function into the mesh), the call side (letting other languages call it), test programs (end-to-end verification), build scripts (CMake / Cargo / Maven etc.) and a knowledge base (how to build, deploy and troubleshoot this product). **The caller does not just get "an API that can be called", but a complete path from compilation to execution.**

**Third, it is "Agent native", not "Agent compatible".** Each tool is itself an MCP tool provider, and each tool ships with a knowledge base written for AI (input contract, wire format, pitfall records, debugging tree). **An Agent can drive the entire tool chain without reading the generator source code** — it calls `Generate` over MCP, then reads the knowledge base to understand what was generated. This is the most essential difference between this repository and most "AI-friendly" tools: **AI is the primary user, not an added feature.**

---

## Unified capabilities: four front ends, one back end

All three tools share the same front-end shapes. There is no split of "this tool has a GUI but that one only has a CLI".

| Capability | Concrete form |
|---|---|
| **GUI** | A five-tab wizard: Welcome → Source Code → Source ↔ JSON → JSON ↔ Model → Final Source. At every step you can manually inspect/correct the intermediate JSON — it is not a black box |
| **CLI** | File to file, no UI, with clear exit-code semantics (0 success / 1 bad arguments / 2 parse failure / 3 generation failure / 4 I/O error) |
| **MCP** | After the GUI starts, it automatically registers as an MCP tool provider. `code_decl_to_abi` exposes 31 tools, `code_decl_to_json_abi` 3, and `code_decl_to_mcp` 11 — the counts differ because workflow granularity differs, not because capability differs |
| **Programmatic interface** | Every generator is an independent Pascal unit exporting a `GenerateXxxCode(Model)` function. You can bypass all front ends and call it directly from your own Pascal program |

**The output of GUI / CLI / MCP is byte-identical.** The `internal_call_*` functions of the MCP layer literally call the GUI's button handlers; there is no "the MCP path quietly does something different".

---

## Quick start

**Prerequisites**: Free Pascal 3.2+ or Delphi 10.4+; Lazarus (for GUI builds) or the `fpc` command line; the zCore submodule initialized; the LingoFuse runtime (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` + `z_ipc_*`) on `PATH` or in the same directory as the tool executable.

```bash
git submodule update --init --recursive
lazbuild -B src/pascal_c_to_abi/code_decl_to_abi.lpi
lazbuild -B src/pascal_c_to_json_abi/code_decl_to_json_abi.lpi
lazbuild -B src/pascal_c_to_mcp/code_decl_to_mcp.lpi
```

**CLI examples**:

```bash
# Pascal -> binary ABI (one of 17 languages)
code_decl_to_abi calculator.pas
# Products include: calculator_service.hpp + calculator_call.hpp + tests + CMake

# C++ header file -> HTTP/JSON ABI (20 languages, including Call-only JS/PHP/Delphi)
code_decl_to_json_abi ComplexTestUnit.h
# Products include: calculator_service.hpp + bridge configuration + HTML test page

# Pascal -> MCP tool provider (one of 4 languages)
code_decl_to_mcp calculator.pas
# Products include: calculator_provider.pas (tool schema + handler)
```

**MCP**: after the GUI starts, the tool automatically registers with the `agent_main_app` beacon. Taking `code_decl_to_mcp` as an example, an Agent needs only three steps: `SetSourceCode` → `ConvertToXxxMCP` → `GetLastXxxCode/Readme`. No GUI interaction, no CLI invocation — no different from calling any other MCP tool.

---

## Knowledge bases: "interface manuals" written for AI, from the same source as the code

Every tool ships with a knowledge base whose content is not "a tutorial written for humans" but **a contract that AI can consume directly**:

- **Input contract** (`pascal_code_abi_rule.md` / `C_code_abi_rule.md` / `pascal_code_json_abi_rule.md` / `C_code_json_abi_rule.md` / `pascal_code_mcp_rule.md` / `C_code_mcp_rule.md`): which declarations get extracted, which get silently dropped, that parameter names must appear at the start of the line, that `{ }` comments must not contain `}`, why C's `void *` is rejected on the Pascal side — **every rule comes with ✅/❌ code examples**.
- **Wire protocol** (`MCP_API_Contract.md`): UTF-8 + NUL framing, status byte semantics, the `required` array containing all parameters, the mandatory `ensure_ascii=False` — **at the byte level, not the pseudocode level**.
- **Pitfall records** (`R_ABI_Generator_Knowledge_Base.md` / `Dart_ABI_Generators_Fix_Report.md` / `Fortran_ABI_Generator_Work_Report.md` / `LingoFuse_Ruby_ABI_Integration_Report.md` / `swift_abi_generator_development_log.md` / `TypeScript_ABI_Generator_Development_Report.md` / `LingoFuse_JS_Async_Generator_Fix_Knowledge_Base.md`): records of the places where "what I assumed" was overturned by actual testing — `int64` losing precision in JS, `_timer.unref()` making async hang forever, Ruby's dispatcher thread touching a dangling pointer after the DLL unloads, Swift's missing `LF_LoadLibrary` call causing all `LF_*` calls to fail silently.

**Feed them to an Agent and the Agent can take over the tool.** This is the repository's design promise: the knowledge base is not "documentation", it is **an executable interface specification**.

---

## Repository structure (quick look)

```
src/
├── pascal_c_to_abi/          <- code_decl_to_abi (binary ABI)
│   ├── code_decl_to_abi.lpr  <- main program (CLI/GUI dispatch)
│   ├── code_decl_to_abi_frm.pas
│   ├── code_decl_to_abi_cmdline.pas
│   ├── *_abi_*_generator_tool.pas   <- generators for 17 languages
│   └── *_rule.md / *Knowledge*.md    <- input contracts + pitfall library
├── pascal_c_to_json_abi/     <- code_decl_to_json_abi (HTTP/JSON)
│   ├── http_bridge_setup_generator_tool.pas   <- bridge startup script
│   └── http_*_abi_*_generator_tool.pas        <- generators for 20 languages
├── pascal_c_to_mcp/          <- code_decl_to_mcp (MCP)
│   ├── *_mcp_generator_tool.pas     <- generators for 4 languages
│   └── MCP_API_Contract.md
├── common/                   <- shared foundation (lingofuse_import / helper)
└── zCore/                    <- Z framework submodule
```

In every tool directory, **generator units sit side by side with knowledge bases** — deliberately: reading generator behavior and reading contract documentation happen in the same field of view, so there is no break of the kind "the code is here, the documentation is in another repository".

---

## Who this repository is not for

- **People who want "install it and run, one command for all languages"**: the generator itself must be built with FPC/Lazarus, and the target languages' build scripts need that language's toolchain. The generator only guarantees that "the generated code is complete", not that "every compiler is installed on your machine".
- **People whose interfaces are inherently "object in, object out"**: types outside the three ABI families are dropped. You need to make a serialization decision at the declaration level first; that is not something the generator does for you.
- **People who need a mature community, Stack Overflow Q&A, and third-party tutorials**: it is maintained by one person; Issues get answered, but there is no SLA.

**Conversely**: if you need to **expose a set of Pascal / C functions you are already using to 20 languages with minimal manual maintenance cost**, and you accept the boundary of "only integers / floats / strings, complex structures are serialized into strings yourself", then this repository is the implementation closest to a "single source of truth" that can be found today.

---

## Related projects

- **[LingoFuse](https://github.com/PassByYou888/LingoFuse)** — the communication foundation
- **[LingoFuse-pasAgent-v3](https://github.com/PassByYou888/LingoFuse-pasAgent-v3)** — the Agent and MCP runtime
- **[zIPC](https://github.com/PassByYou888/zIPC)** — the underlying same-machine IPC

---

## License

**MIT** — take it, modify it, sell it; no need to thank me.

Like the main LingoFuse repository, **sharing is itself the purpose** here.

---

*Open an Issue if you have questions. For urgent matters, add me on QQ (600585).*
