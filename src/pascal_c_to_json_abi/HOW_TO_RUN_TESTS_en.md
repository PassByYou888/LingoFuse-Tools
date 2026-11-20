# Testing Guide for Each Language

> *English translation of [HOW_TO_RUN_TESTS.md](HOW_TO_RUN_TESTS.md).*

> This document explains how to run the tests for **each target language**.
>
> **Three universal preconditions**:
>
> 1. **The bridge program (`bridge.py` / `bridge.exe`) must always be running**.
> 2. **The service side must already be started and online**.
> 3. **The call side must be started after the bridge program is ready**.
>
> Test driver files follow the naming rule `<UnitName>_http_json_<side>_main_test___.<ext>`. The complete artifact list is whatever the generator returns.
>
> **This document does not cover "how to build the artifacts"** — see `BUILD_GUIDE.md` (or chapter 14) for the build steps. This document only covers **"how to run the tests once the artifacts are built"**.

---

## Table of contents

1. [Universal three-process layout](#1-universal-three-process-layout)
2. [Universal test checklist](#2-universal-test-checklist)
3. [Pascal](#3-pascal)
4. [Python](#4-python)
5. [C++](#5-c)
6. [C#](#6-c)
7. [JavaScript (browser)](#7-javascript-browser)
8. [Node.js](#8-nodejs)
9. [TypeScript](#9-typescript)
10. [PHP](#10-php)
11. [Rust](#11-rust)
12. [Go](#12-go)
13. [Java](#13-java)
14. [Delphi](#14-delphi)
15. [Dart](#15-dart)
16. [Swift](#16-swift)
17. [Ruby](#17-ruby)
18. [Zig](#18-zig)
19. [Erlang](#19-erlang)
20. [Fortran](#20-fortran)
21. [Julia](#21-julia)
22. [R](#22-r)
23. [Universal troubleshooting](#23-universal-troubleshooting)

---

## 1. Universal three-process layout

An end-to-end test in any language follows the same three-process model:

```
┌──────────────────────────────────────────────────────────────┐
│ Terminal 1: service side                                       │
│   start the generated service (Pascal / Python / C++ / C# / Rust / ...) │
│   listens on ipc:<UnitName>_http_json                          │
└──────────────────────────────────────────────────────────────┘
                            ▲
                            │ LF_Call
┌──────────────────────────────────────────────────────────────┐
│ Terminal 2: bridge program                                     │
│   python3 bridge.py --endpoint ipc:<UnitName>_http_json \      │
│                     --port 8081 --no-precheck                  │
│   must stay resident in the foreground                         │
└──────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTP POST
┌──────────────────────────────────────────────────────────────┐
│ Terminal 3: call side (test driver)                             │
│   run the generated call-side test driver                      │
│   prints OK / FAILED, final exit code 0 or 1                   │
└──────────────────────────────────────────────────────────────┘
```

**The startup order must be followed strictly**: service → bridge → call side.

**Shutdown order**: call side → bridge → service.

### 1.1 Endpoint naming conventions

| Name | Value |
|------|-----|
| LingoFuse endpoint | `ipc:<UnitName>_http_json` |
| Default bridge HTTP port | `8081` |
| Default Base URL | `http://127.0.0.1:8081/<UnitName>` |
| Default bridge App name | `__lf_http_bridge__` |
| Default bridge API name | `__lf_outbound_post__` |

`<UnitName>` is the normalized unit name obtained after parsing the source unit (for example `unit Calculator;` → `Calculator`).

---

## 2. Universal test checklist

The test drivers in every language do the same thing:

1. Initialize (the LingoFuse client / HTTP client required to connect to the bridge).
2. For each supported API, do in turn:
   - a **synchronous** call;
   - an **asynchronous** call (if the language supports it).
3. Each call prints `OK` or `FAILED: <reason>`.
4. Print a summary: `Passed: N` / `Failed: M`.
5. Exit with `0` (all succeeded) or `1` (at least one failure).

**Test driver file name**: `<UnitName>_http_json_<side>_main_test___.<ext>`

- `<side>` = `service` or `call`.
- `<ext>` = see each language section.

**Test modes**:

| Mode | Meaning | Needs the bridge? | Needs the service? |
|------|------|:----------------:|:------------:|
| **Default mode** | Service starts + blocks | ❌ | ❌ |
| **`--smoke` mode** | In-process LocalCall self-test | ❌ | ❌ (in process) |
| **Call-side test** | Goes through the full HTTP chain | ✅ **required** | ✅ **required** |

---

## 3. Pascal

### 3.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_unit.pas` | Pascal service unit |
| `<Unit>_http_json_call_unit.pas` | Pascal call unit |
| `<Unit>_http_json_service_main_test___.pas` | Service-side test driver |
| `<Unit>_http_json_call_main_test___.pas` | Call-side test driver |

### 3.2 Prerequisites

- FPC 3.2+ or Delphi 11+.
- `lingofuse_import.pas`, `Z.Core`, `Z.PascalStrings`, `Z.UPascalStrings`, `Z.Json`, `Z.UnicodeMixedLib`.
- `LingoFuse64.dll` (or `liblingofuse.so` / `liblingofuse.dylib`).
- `z_ipc_64.dll`.

### 3.3 Compiling the test drivers

**Service-side test driver**:

```bash
fpc -Fu<path-to-ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated> \
    <Unit>_http_json_service_main_test___.pas
```

**Call-side test driver**:

```bash
fpc -Fu<path-to-ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated> \
    <Unit>_http_json_call_main_test___.pas
```

### 3.4 Running the tests

**Service side**:

```bash
./<Unit>_http_json_service_main_test___
# or default mode
./<Unit>_http_json_service_main_test___
# or --smoke mode (in-process LocalCall self-test)
./<Unit>_http_json_service_main_test___ --smoke
```

**Call side**:

```bash
./<Unit>_http_json_call_main_test___
# override the Base URL
./<Unit>_http_json_call_main_test___ http://10.0.0.5:8081/<Unit>
```

### 3.5 Expected output (call side)

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

### 3.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Fatal: Can't find unit Z.Core` | The `-Fu` paths are not configured | add `-Fu<ZCore path>` |
| `LF_PrepareClient returned -1` | The bridge is not started, or the endpoint differs | check the bridge terminal and `--endpoint` |
| `EHTTPCallError: Network error` | The bridge is not running | start the bridge |
| `3029 function header doesn't match` | FPC overload conflict | check the overload declarations in the generated unit and the test driver |

---

## 4. Python

### 4.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.py` | Python service |
| `<Unit>_http_json_call.py` | Python call module |
| `<Unit>_http_json_service_main_test___.py` | Service-side test driver |
| `<Unit>_http_json_call_main_test___.py` | Call-side test driver |

### 4.2 Prerequisites

```bash
# call side
pip install requests

# service side
pip install <path-to-LingoFuse>/python
```

### 4.3 Running the tests

**Service side**:

```bash
python3 <Unit>_http_json_service_main_test___.py
# or --smoke mode (in-process LocalCall, no bridge needed)
python3 <Unit>_http_json_service_main_test___.py --smoke
```

**Call side**:

```bash
python3 <Unit>_http_json_call_main_test___.py
# override the Base URL
python3 <Unit>_http_json_call_main_test___.py http://10.0.0.5:8081/<Unit>
```

### 4.4 Expected output (call side)

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

### 4.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `ModuleNotFoundError: requests` | Not installed | `pip install requests` |
| `ModuleNotFoundError: lingofuse` | The LingoFuse Python package is not installed | install the LingoFuse distribution |
| `HTTPCallError: Network error` | The bridge is not running | start the bridge |
| `asyncio: Task was destroyed` | An async task was not fully awaited | wrap with `asyncio.run(main())` |

---

## 5. C++

### 5.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.hpp` + `.cpp` | C++ service |
| `<Unit>_http_json_call.hpp` + `.cpp` | C++ call |
| `CMakeLists.txt` | Build script |
| `test_main___.cpp` | Call-side test driver |

### 5.2 Prerequisites

- CMake 3.15+.
- A C and C++ compiler (MSVC / g++ / clang++).
- The LingoFuse C++ distribution directory (containing `LingoFuse.h`, `LingoFuse.c`, `LingoFuse.hpp`, `lf_io.hpp`, `lf_http_bridge_client.hpp`, `json.hpp`).

### 5.3 Build

```bash
# Make sure <Unit>_http_json_service.hpp/.cpp, <Unit>_http_json_call.hpp/.cpp,
# CMakeLists.txt and test_main___.cpp are all in the same directory.
cd <that-directory>

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

The build produces two executables:

- `<Unit>_http_json_service` (service side)
- `<Unit>_http_json_call_test` (call-side test driver)

### 5.4 Running the tests

**Service side**:

```bash
./build/<Unit>_http_json_service
```

**Call side**:

```bash
./build/<Unit>_http_json_call_test
```

**Windows**: first copy `LingoFuse64.dll` and `z_ipc_64.dll` into `build/Release/`.

```cmd
copy C:\LingoFuse\cpp\LingoFuse64.dll build\Release\
copy C:\LingoFuse\cpp\z_ipc_64.dll build\Release\
build\Release\<Unit>_http_json_call_test.exe
```

### 5.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===
Base URL: http://127.0.0.1:8081/Calculator

  Add [sync] : OK
  Add [async]: OK
  Sub [sync] : OK
  Sub [async]: OK

all calls succeeded
```

### 5.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Cannot determine link language` | `project()` only declares `CXX` | declare `C CXX` |
| `LINGOFUSE_CPP_LIB_DIR does not point at a LingoFuse C++ library directory` | `-DLINGOFUSE_CPP_LIB_DIR` not passed | pass it |
| The linker cannot find `LingoFuse` | The DLL was not copied | copy it next to the executable |
| `HTTPCallError: ... (code=-1, http_status=0)` | The bridge is not running | start the bridge |

---

## 6. C#

### 6.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.cs` | C# service module |
| `<Unit>_http_json_call.cs` | C# call module |
| `<Unit>_http_json_service_main_test___.cs` | Service-side test driver |
| `<Unit>_http_json_call_main_test___.cs` | Call-side test driver |

### 6.2 Prerequisites

- .NET 8.0+.
- The LingoFuse .NET binding (`LingoFuse.dll`).
- The LingoFuse native library (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`) and `z_ipc_*`.

### 6.3 Build and run (service side)

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
# or --smoke mode
dotnet run -- --smoke
```

### 6.4 Build and run (call side)

```bash
dotnet new console -o my_call
cd my_call
cp ../<Unit>_http_json_call.cs .
cp ../<Unit>_http_json_call_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

### 6.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===
Base URL: http://127.0.0.1:8081/Calculator
Endpoint: ipc:Calculator_http_json

  Add [sync] : OK
  Add [async]: OK
  Sub [sync] : OK
  Sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 6.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `DllNotFoundException: LingoFuse64` | The DLL was not copied | copy it into the bin directory |
| `Could not load type 'lingofuse.AppHandle'` | Missing LingoFuse.dll reference | `dotnet add reference` |
| `HTTPCallError` | The bridge is not running | start the bridge |
| `PrepareDone returned 0` | `PrepareDone` was already called in the same process | restart the process |

---

## 7. JavaScript (browser)

### 7.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_call.js` | Browser JS client (IIFE) |
| `<Unit>_http_json_call_test.html` | Self-contained test page |

### 7.2 Prerequisites

A modern browser (Chrome / Edge / Firefox / Safari). **No third-party dependencies**.

### 7.3 Running the tests

**Option A: double-click `*_test.html`**

Just double-click to open it.

**Option B: serve over HTTP (recommended)**

```bash
cd <generated-directory>
python3 -m http.server 9000
# open http://127.0.0.1:9000/<Unit>_http_json_call_test.html
```

**Option C: include it in your own page**

```html
<script src="<Unit>_http_json_call.js"></script>
<script>
  (async () => {
    try {
      const r = await CalculatorApi.Add(1, 2);
      console.log('Add(1, 2) =', r);
    } catch (e) {
      console.error('Add failed:', e.message, 'code:', e.code);
    }
  })();
</script>
```

### 7.4 Expected output (HTML test page)

Each API card shows `OK: <result>` or `Error: <message>`. The banner at the top shows:
- `Page ready. Base URL: http://127.0.0.1:8081/<Unit>`
- `Last call: <Api> succeeded.` / `Last call: <Api> failed: ...`

### 7.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Failed to fetch` | The bridge is not running, or CORS | start the bridge; it must return `Access-Control-Allow-Origin: *` |
| CORS error when opened via `file://` | The browser's `file://` restriction | serve it with `python3 -m http.server 9000` |
| `Mixed Content` | The page is https while the bridge is http | serve the page over http, or give the bridge https |
| `Add is not a function` | `window.<Unit>Api` is not ready | check the `<script src>` path; call after `DOMContentLoaded` |

---

## 8. Node.js

### 8.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_node.js` | Node.js service |
| `<Unit>_http_json_call_node.js` | Node.js call module |
| `<Unit>_http_json_service_main_test___.js` | Service-side test driver |
| `<Unit>_http_json_call_main_test___.js` | Call-side test driver |
| `setup_js_tests.ps1` | Environment preparation script |

### 8.2 Prerequisites

- Node.js 18+ (`fetch` is built in).
- `lingofuse-js` (service side).

### 8.3 Preparing the environment (recommended)

```powershell
.\setup_js_tests.ps1 -JsLibDir D:\LingoFuse\js\lingofuse-js -RunSmoke
```

**Manual**:

```bash
npm install lingofuse-js
```

### 8.4 Running the tests

**Service side**:

```bash
node <Unit>_http_json_service_main_test___.js
# --smoke mode
node <Unit>_http_json_service_main_test___.js --smoke
```

**Call side**:

```bash
node <Unit>_http_json_call_main_test___.js
# override the Base URL
node <Unit>_http_json_call_main_test___.js http://10.0.0.5:8081/<Unit>
```

### 8.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add [await]: OK
  Add [promise]: OK
  Sub [await]: OK
  Sub [promise]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 8.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Cannot find module 'lingofuse-js'` | Not installed | `npm install lingofuse-js` |
| `fetch is not defined` | Node < 18 | upgrade Node |
| `HTTPCallError` | The bridge is not running | start the bridge |
| `ECONNREFUSED` | Wrong bridge port | check `--port` |

---

## 9. TypeScript

### 9.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.ts` | TypeScript service |
| `<Unit>_http_json_call_ts.ts` | TypeScript call module |
| `<Unit>_http_json_service_main_test___.ts` | Service-side test driver |
| `<Unit>_http_json_call_main_test___.ts` | Call-side test driver |
| `setup_ts_tests.ps1` | Environment preparation script |

### 9.2 Prerequisites

- Node.js 18+.
- `lingofuse-ts`, `tsx`.

### 9.3 Preparing the environment (recommended)

```powershell
.\setup_ts_tests.ps1 -TsLibDir D:\LingoFuse\ts\lingofuse-ts -RunSmoke
```

**Manual**:

```bash
npm install lingofuse-ts tsx
```

### 9.4 Running the tests

**Service side**:

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_service_main_test___.ts
# --smoke
./node_modules/.bin/tsx.cmd <Unit>_http_json_service_main_test___.ts --smoke
```

**Call side**:

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_call_main_test___.ts
# override the Base URL
./node_modules/.bin/tsx.cmd <Unit>_http_json_call_main_test___.ts http://10.0.0.5:8081/<Unit>
```

**Linux / macOS**: `./node_modules/.bin/tsx`

### 9.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add [await]: OK
  Add [promise]: OK
  Sub [await]: OK
  Sub [promise]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 9.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `tsx: not found` | Not installed | `npm install tsx` |
| `Cannot find module 'lingofuse-ts'` | Not installed | `npm install lingofuse-ts` |
| `TypeError: Cannot read property` | TS compile target mismatch | check `target` in `tsconfig.json` |
| `HTTPCallError` | The bridge is not running | start the bridge |

---

## 10. PHP

### 10.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_call_php.php` | PHP call module |
| `<Unit>_http_json_call_main_test___.php` | Call-side test driver |

**PHP has no service side** (call side only).

### 10.2 Prerequisites

- PHP 7.4+.
- The `curl` extension (preferred) or `allow_url_fopen=On`.

### 10.3 Running the tests

```bash
php <Unit>_http_json_call_main_test___.php
# override the Base URL
php <Unit>_http_json_call_main_test___.php http://10.0.0.5:8081/<Unit>
```

### 10.4 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 10.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Call to undefined function curl_init()` | The curl extension is not installed | `apt install php-curl` or edit php.ini |
| `file_get_contents(): http:// wrapper is disabled` | `allow_url_fopen=Off` | install the curl extension |
| `HttpJsonCallError` | The bridge is not running | start the bridge |
| `SSL certificate problem` | Bridge https certificate | add `--insecure` or configure a CA |

---

## 11. Rust

### 11.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_rs.rs` | Rust service |
| `<Unit>_http_json_call_rs.rs` | Rust call module |
| `<Unit>_http_json_service_main_test___.rs` | Service-side test driver |
| `<Unit>_http_json_call_main_test___.rs` | Call-side test driver |

### 11.2 Prerequisites

- Rust 1.70+.
- Call-side crates: `ureq`, `reqwest`, `tokio`, `serde_json`.
- Service-side crates: `lingofuse`, `serde_json`.

### 11.3 Build and run (service side)

```bash
cargo new my_service
cd my_service
cargo add lingofuse --path ../LingoFuse/rust
cargo add serde_json
cp ../<Unit>_http_json_service_rs.rs src/
cp ../<Unit>_http_json_service_main_test___.rs src/main.rs
cargo run
```

### 11.4 Build and run (call side)

```bash
cargo new my_call
cd my_call
cargo add ureq
cargo add reqwest --features json
cargo add tokio --features rt,rt-multi-thread,macros
cargo add serde_json
cp ../<Unit>_http_json_call_rs.rs src/
cp ../<Unit>_http_json_call_main_test___.rs src/main.rs
cargo run
```

### 11.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===
Base URL : http://127.0.0.1:8081/Calculator
API count: 2
Each API is tested twice (sync + async).

--- Synchronous pass (ureq) ---

  Add [sync] : OK
  Sub [sync] : OK

--- Asynchronous pass (reqwest + tokio) ---

  Add [async]: OK
  Sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 11.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `cargo: no such command: add` | cargo is too old | `rustup update` |
| `linking with cc failed` | Missing C linker | install MSVC Build Tools or gcc |
| `HttpCallError` | The bridge is not running | start the bridge |
| `ureq::Error::Transport` | Network error / bridge not started | check the bridge |
| `tokio` runtime error | Missing `#[tokio::main]` | use the `#[tokio::main]` in the generated code |

---

## 12. Go

### 12.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_go.go` | Go service |
| `<Unit>_http_json_call_go.go` | Go call module |
| `<Unit>_http_json_service_main_test.go` | Service-side test |
| `<Unit>_http_json_call_main_test.go` | Call-side test |

### 12.2 Prerequisites

- Go 1.21+.
- Service side: `github.com/PassByYou888/LingoFuse/go`.
- Call side: standard library only.

### 12.3 Build and run (service side)

```bash
go mod init calculator
go get github.com/PassByYou888/LingoFuse/go
cp ../<Unit>_http_json_service_go.go .
cp ../<Unit>_http_json_service_main_test.go .
go test -v
# or build an executable
go build -o service .
./service
```

### 12.4 Build and run (call side)

```bash
go mod init calculator_call
cp ../<Unit>_http_json_call_go.go .
cp ../<Unit>_http_json_call_main_test.go .
go test -v
```

### 12.5 Expected output (call side)

```
=== RUN   TestCall_Add_Sync
--- PASS: TestCall_Add_Sync (0.05s)
=== RUN   TestCall_Add_Async
--- PASS: TestCall_Add_Async (0.06s)
=== RUN   TestCall_Sub_Sync
--- PASS: TestCall_Sub_Sync (0.05s)
=== RUN   TestCall_Sub_Async
--- PASS: TestCall_Sub_Async (0.06s)
PASS
ok      calculator_call 0.25s
```

### 12.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `module github.com/PassByYou888/LingoFuse not found` | `go get` not run | `go get github.com/PassByYou888/LingoFuse/go` |
| `undefined: HTTPCallError` | The call module is not imported | make sure `_http_json_call_go.go` is in the same package as the test |
| `cgo` related errors | The service side needs cgo | set `CGO_ENABLED=1` |
| `HTTPCallError` | The bridge is not running | start the bridge |

---

## 13. Java

### 13.1 Artifacts

| File | Description |
|------|------|
| `HttpJsonService.java` | Java service class |
| `HttpJsonClient.java` | Java call class |
| `HttpJsonServiceTest.java` | Service-side test driver |
| `HttpJsonCallTest.java` | Call-side test driver |

### 13.2 Prerequisites

- JDK 11+ (17+ recommended).
- `jackson-databind.jar`.
- Service side: `lingofuse.jar`.

### 13.3 Build and run (service side)

```bash
javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonService
# --smoke mode
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonServiceTest --smoke
```

**Windows**: separate the classpath with `;`:

```cmd
javac -cp lingofuse.jar;jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED -cp .;lingofuse.jar;jackson-databind.jar HttpJsonService
```

### 13.4 Build and run (call side)

```bash
javac -cp jackson-databind.jar HttpJsonClient.java HttpJsonCallTest.java
java -cp .:jackson-databind.jar HttpJsonCallTest
```

### 13.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 13.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `ClassNotFoundException: com.fasterxml.jackson.databind.JsonNode` | Jackson missing | download `jackson-databind.jar` |
| `UnsatisfiedLinkError: LingoFuse64` | Native library missing | add it to `-Djava.library.path` |
| `ClassNotFoundException: lingofuse.AppHandle` | `lingofuse.jar` missing | install the LingoFuse Java package |
| `HTTPCallException` | The bridge is not running | start the bridge |

---

## 14. Delphi

### 14.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_call_delphi.pas` | Delphi call unit |
| `<Unit>_http_json_call_delphi_test___.dpr` | Call-side test driver |

**Delphi has no service side** (call side only).

### 14.2 Prerequisites

- Delphi 10.3+.
- RTL only (`System.Net.HttpClient`, `System.JSON`, `System.Classes`).

### 14.3 Build and run

**Option A: command line**

```cmd
dcc32 <Unit>_http_json_call_delphi_test___.dpr
<Unit>_http_json_call_delphi_test___.exe
```

**Option B: IDE**

1. Open `<Unit>_http_json_call_delphi_test___.dpr`.
2. `Build`.
3. `Run`.

### 14.4 Expected output (call side)

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

### 14.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Unit not found: System.Net.HttpClient` | Delphi < 10.3 | upgrade Delphi |
| `EHTTPCallError: Network error` | The bridge is not running | start the bridge |
| Async test times out | `CheckSynchronize` is not pumped | the generated code already uses `PumpUntilSignaled`, nothing to do |

---

## 15. Dart

### 15.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.dart` | Dart service |
| `<Unit>_http_json_call.dart` | Dart call module |
| `<Unit>_http_json_service_main_test___.dart` | Service-side test |
| `<Unit>_http_json_call_main_test___.dart` | Call-side test |

### 15.2 Prerequisites

Add to `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.0.0
```

The service side also needs the `lingofuse` package.

### 15.3 Running the tests

**Service side**:

```bash
dart run <Unit>_http_json_service_main_test___.dart
```

**Call side**:

```bash
dart run <Unit>_http_json_call_main_test___.dart
# override the Base URL
dart run <Unit>_http_json_call_main_test___.dart http://10.0.0.5:8081/<Unit>
```

### 15.4 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL : http://127.0.0.1:8081/Calculator
API count: 2

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 15.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Error: Couldn't resolve the package 'http'` | `dart pub get` not run | `dart pub get` |
| `HttpCallError` | The bridge is not running | start the bridge |
| `LateInitializationError` | The service has not finished init | wait for the `visible` log |

---

## 16. Swift

### 16.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_swift.swift` | Swift service |
| `<Unit>_http_json_call_swift.swift` | Swift call module |
| `<Unit>_http_json_service_main_test___.swift` | Service-side test |
| `<Unit>_http_json_call_main_test___.swift` | Call-side test |

### 16.2 Prerequisites

- Swift 5.9+.
- macOS 12+ / iOS 15+ (required for the async APIs).

### 16.3 Running the tests

**Service side**:

```bash
swift <Unit>_http_json_service_main_test___.swift
```

**Call side**:

```bash
swift <Unit>_http_json_call_main_test___.swift
```

### 16.4 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator
Timeout : 30.0s

--- Synchronous pass ---

  Add [sync] : OK
  Sub [sync] : OK

--- Asynchronous pass ---

  Add [async]: OK
  Sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 16.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `error: cannot find 'FoundationNetworking'` | On Linux it must be imported explicitly | the generated code already handles it |
| `HTTPCallError` | The bridge is not running | start the bridge |
| `@unchecked Sendable` warning | Normal concurrency annotation | nothing to do |
| async pass does not run | Below macOS 12 | upgrade the OS, or use the sync pass |

---

## 17. Ruby

### 17.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.rb` | Ruby service |
| `<Unit>_http_json_call.rb` | Ruby call module |
| `<Unit>_http_json_service_main_test___.rb` | Service-side test |
| `<Unit>_http_json_call_main_test___.rb` | Call-side test |

### 17.2 Prerequisites

- Ruby 2.7+ / 3.0+.
- Service side: the `lingofuse` gem (a C extension).
- Call side: standard library only.

### 17.3 Running the tests

**Service side**:

```bash
gem install lingofuse   # once only
ruby <Unit>_http_json_service_main_test___.rb
# --smoke mode (in-process LocalCall)
ruby <Unit>_http_json_service_main_test___.rb --smoke
```

**Call side**:

```bash
ruby <Unit>_http_json_call_main_test___.rb
# override the Base URL
ruby <Unit>_http_json_call_main_test___.rb http://10.0.0.5:8081/<Unit>
```

### 17.4 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add [sync] : OK
  Sub [sync] : OK

=== Summary ===
Passed: 2
Failed: 0
```

### 17.5 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `cannot load such file -- lingofuse` | The gem is not installed | `gem install lingofuse` |
| `HTTPCallError` | The bridge is not running | start the bridge |
| `dynamic constant assignment` | Assigning to `HTTP_CALL_BASE_URL` by mistake | use `Module.base_url = "..."` |
| The process does not exit | The `NativeBridge.start` thread was not joined | the generated code already force-exits with `exit!` |

---

## 18. Zig

### 18.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_zig.zig` | Zig service |
| `<Unit>_http_json_call_zig.zig` | Zig call module |
| `<Unit>_http_json_service_main_test___.zig` | Service-side test |
| `<Unit>_http_json_call_main_test___.zig` | Call-side test |
| `setup_zig_tests.ps1` | Environment preparation script |

### 18.2 Prerequisites

- Zig 0.13+.
- The `lingofuse` Zig binding.
- `LingoFuse64.dll` and `z_ipc_64.dll`.

### 18.3 Preparing the environment (recommended)

```powershell
.\setup_zig_tests.ps1 -ZigLibDir D:\LingoFuse\zig -BinaryDir D:\LingoFuse\Binary
```

The script creates two projects, `zig_service_test/` and `zig_call_test/`.

### 18.4 Running the tests

**Service side**:

```bash
cd zig_service_test
zig build run
# press Enter to stop
```

**Call side**:

```bash
cd zig_call_test
zig build run
# press Enter to exit
```

### 18.5 Expected output (call side)

```
================================================================
  LingoFuse Zig HTTP/JSON call test (via LingoFuse mesh + bridge)
  Endpoint   : ipc:Calculator_http_json
  Bridge App : __lf_http_bridge__
  Bridge Api : __lf_outbound_post__
  Base URL   : http://127.0.0.1:8081/Calculator
================================================================
[diag] bridge reachable: __lf_http_bridge__.__lf_outbound_post__
[OK  ] Add [sync]
[OK  ] Add [async]
[OK  ] Sub [sync]
[OK  ] Sub [async]

================================================================
  Results: 4 passed, 0 failed
================================================================
Press Enter to exit.
```

### 18.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `zig build` reports a fingerprint mismatch | `build.zig.zon` fingerprint is stale | replace `.fingerprint` as the error message says |
| `bridge app '__lf_http_bridge__' not found in mesh` | The bridge is not started | start the bridge |
| `framework.init failed` | LingoFuse64.dll is not on PATH | copy the DLL into `zig_call_test/` |
| `std.array_list.Managed` compile error | Wrong Zig version | use Zig 0.13+ |

---

## 19. Erlang

### 19.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.erl` | Erlang service module |
| `<Unit>_http_json_call.erl` | Erlang call module |
| `<Unit>_http_json_service_main_test___.escript` | Service-side test |
| `<Unit>_http_json_call_main_test___.escript` | Call-side test |
| `setup_erlang_tests.ps1` | Environment preparation script |

### 19.2 Prerequisites

- Erlang/OTP 25+.
- The `lingofuse` Erlang binding (including `lingofuse_nif.dll`).

### 19.3 Preparing the environment (recommended)

```powershell
.\setup_erlang_tests.ps1 -ErlangBindingDir D:\LingoFuse\erlang -RunSmoke
```

### 19.4 Running the tests

**Service side**:

```bash
escript <Unit>_http_json_service_main_test___.escript
# --smoke mode
escript <Unit>_http_json_service_main_test___.escript --smoke
```

**Call side**:

```bash
escript <Unit>_http_json_call_main_test___.escript
# override the Base URL
escript <Unit>_http_json_call_main_test___.escript http://10.0.0.5:8081/<Unit>
```

### 19.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

[OK] service is visible.
  add [sync]: OK
  add [async]: OK
  sub [sync]: OK
  sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 19.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `no such file or directory: lingofuse_nif.dll` | NIF missing | `setup_erlang_tests.ps1` copies it |
| `{error, {http_error, econnrefused}}` | The bridge is not running | start the bridge |
| `service_not_visible` | The service is not ready (within 3 seconds) | increase `PROBE_RETRIES` |
| `undef` error | The module is not compiled | `erlc -o ebin *.erl` |

---

## 20. Fortran

### 20.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service_mod.f90` | Fortran service module |
| `<Unit>_http_json_call_mod.f90` | Fortran call module |
| `<Unit>_http_json_service_main_test___.f90` | Service-side test |
| `<Unit>_http_json_call_main_test___.f90` | Call-side test |
| `setup_fortran_tests.ps1` | Environment preparation script |

### 20.2 Prerequisites

- gfortran 9+ or ifort / flang.
- `lf_fortran_mod.f90` + `lf_fortran.cpp` + `LingoFuse.c`.
- `LingoFuse64.dll`.

### 20.3 Preparing the environment (recommended)

```powershell
.\setup_fortran_tests.ps1 -FortranLibDir D:\LingoFuse\fortran\c_ext -RunSmoke
```

The script will:

1. Compile `lf_fortran_mod.f90`, `lf_fortran.cpp`, `LingoFuse.c`.
2. Compile `<Unit>_http_json_service_mod.f90` and `<Unit>_http_json_call_mod.f90`.
3. Compile the two test drivers.
4. Link `service_test.exe` and `call_test.exe`.

### 20.4 Running the tests

**Service side**:

```bash
cd _build_fortran
./service_test.exe
# --smoke mode
./service_test.exe --smoke
```

**Call side**:

```bash
cd _build_fortran
./call_test.exe
# override the Base URL
./call_test.exe http://10.0.0.5:8081/<Unit>
```

### 20.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===
Base URL : http://127.0.0.1:8081/Calculator
Endpoint : ipc:Calculator_http_json
APIs     : 2

  Add [sync] : OK
  Add [async]: OK
  Sub [sync] : OK
  Sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 20.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `gfortran: command not found` | Not installed | `apt install gfortran` or MinGW-w64 |
| `undefined reference to 'lf_*'` | `lf_fortran.cpp` not linked | use `setup_fortran_tests.ps1` |
| `c_funloc ... not a variable` | Empty parameter list form | already fixed in the generated code (v4) |
| `HTTPCallError` | The bridge is not running | start the bridge |

---

## 21. Julia

### 21.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.jl` | Julia service module |
| `<Unit>_http_json_call.jl` | Julia call module |
| `<Unit>_http_json_service_main_test___.jl` | Service-side test |
| `<Unit>_http_json_call_main_test___.jl` | Call-side test |
| `setup_julia_tests.ps1` | Environment preparation script |

### 21.2 Prerequisites

- Julia 1.9+ (1.10+ recommended).
- **`--threads=2` or more is required** (needed for consuming LingoFuse callbacks).
- The `LingoFuse` and `JSON3` packages.

### 21.3 Preparing the environment (recommended)

```powershell
.\setup_julia_tests.ps1 -JuliaBindingDir D:\LingoFuse\julia -RunSmoke
```

### 21.4 Running the tests

**Service side**:

```bash
julia --project=<GenDir> --threads=2 <Unit>_http_json_service_main_test___.jl
# --smoke mode
julia --project=<GenDir> --threads=2 <Unit>_http_json_service_main_test___.jl --smoke
```

**Call side**:

```bash
julia --project=<GenDir> --threads=2 <Unit>_http_json_call_main_test___.jl
# override the Base URL / Endpoint
julia --project=<GenDir> --threads=2 <Unit>_http_json_call_main_test___.jl \
    http://10.0.0.5:8081/<Unit> ipc:Calculator_http_json
```

### 21.5 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator
Endpoint: ipc:Calculator_http_json

  Add [sync] : OK
  Add [async]: OK
  Sub [sync] : OK
  Sub [async]: OK

=== Summary ===
Passed: 4
Failed: 0
```

### 21.6 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `FATAL: --threads=2 or more required` | Single-threaded | add `--threads=2` |
| `ArgumentError: Package LingoFuse not found` | Not installed | `setup_julia_tests.ps1` |
| `HTTPCallError` | The bridge is not running | start the bridge |
| `prepare_client returned -1` | The endpoint is already in use | check the port, or use a different endpoint |

---

## 22. R

### 22.1 Artifacts

| File | Description |
|------|------|
| `<Unit>_http_json_service.R` | R service |
| `<Unit>_http_json_service_impl.R` | R user implementation stubs |
| `<Unit>_http_json_call.R` | R call module |
| `<Unit>_http_json_service_main_test___.R` | Service-side test |
| `<Unit>_http_json_call_main_test___.R` | Call-side test |
| `setup_r_tests.ps1` | Environment preparation script |

### 22.2 Prerequisites

- R 4.0+.
- The four packages `lingofuse`, `jsonlite`, `httr`, `future`.

### 22.3 Preparing the environment (recommended)

```powershell
.\setup_r_tests.ps1 -RLibDir D:\LingoFuse\r\lingofuse -InstallMissing -RunSmoke
```

### 22.4 Running the tests

**Service side**:

```bash
# set the environment variable first
export LINGOFUSE_RUNTIME=/path/to/LingoFuse64
Rscript <Unit>_http_json_service_main_test___.R
```

**Call side**:

```bash
export LINGOFUSE_RUNTIME=/path/to/LingoFuse64
Rscript <Unit>_http_json_call_main_test___.R
```

### 22.5 Stopping the R service

The R service watches the `service.exit` sentinel file. **Open a second PowerShell window**:

```powershell
'' > "<script directory>\service.exit"
```

The service detects it within about 100 ms, runs `exit_main_thread` → `free_app` → `shutdown` in order, then exits.

**Ctrl+C is the fallback**, but on some platforms it may leave the terminal in a broken state.

### 22.6 Expected output (call side)

```
=== Calculator HTTP/JSON call test ===
Base URL: http://127.0.0.1:8081/Calculator

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 22.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Package 'lingofuse' is required` | Not installed | `setup_r_tests.ps1 -InstallMissing` |
| `Cannot locate the LingoFuse runtime` | `LINGOFUSE_RUNTIME` is not set | set the environment variable |
| `The *_async variants require future::plan('sequential')` | The future plan is incompatible | `future::plan(future::sequential)` |
| `HTTPCallError` | The bridge is not running | start the bridge |

---

## 23. Universal troubleshooting

### 23.1 Symptom → cause → fix

| Symptom | Most likely cause | Fix |
|------|--------------|------|
| Every language reports `Network error` / `Connection refused` | **The bridge is not running** | start `bridge.py` |
| The bridge terminal shows no logs at all | The bridge failed to start | check the `--endpoint` argument and the `bridge.py` path |
| `LF_PrepareClient returned -1` | The endpoint is occupied by another process | use another endpoint, or kill the old process |
| `LF_PrepareDone returned 0` | Already called in the same process | restart the process |
| `no found app("<name>")` | The target App is not on the mesh | the service side is not started, or the endpoint differs |
| `code=-3` (`-3 bridge precheck`) | The bridge precheck cache is stale | add `--no-precheck` to the bridge |
| `code=-4` (protocol error) | The bridge response is malformed | check the bridge version against the service version |
| The service side reports `Address already in use` | The endpoint is occupied | use another endpoint, or kill the old process |
| The service runs but the call side gets no response | The endpoint strings differ | both sides must use `ipc:<Unit>_http_json` |
| Call side times out | The service is blocked / the bridge is blocked | look at the service-side logs |
| Call side reports an `int64` precision problem | JS `Number` precision limit | have the service side return a string |
| The bridge was closed by accident | The terminal was closed by accident | restart the bridge; the call side does not need to restart |

### 23.2 The "health check" order for the three processes

1. **Service side**: check whether it printed `[OK] Service ready` or a similar log.
2. **Bridge**: check whether it printed an HTTP listening log (`Listening on 127.0.0.1:8081` or similar).
3. **Call side**: run the test driver.

**If any step fails, fix that step before continuing.**

### 23.3 Common endpoint string mistakes

| Wrong form | Correct form |
|----------|----------|
| `Calculator` | `ipc:Calculator_http_json` |
| `ipc:calculator_http_json` (case) | `ipc:Calculator_http_json` (exactly matching `<UnitName>`) |
| `ipc:Calculator` | `ipc:Calculator_http_json` |
| `tcp://127.0.0.1:8081/Calculator` | `ipc:Calculator_http_json` |

**The endpoint string must be exactly identical on both sides**. The bridge's `--endpoint` and the service's `HTTP_SERVICE_ENDPOINT` / `ENDPOINT` constant must be the same.

### 23.4 Test driver exit codes

| Exit code | Meaning |
|:------:|------|
| `0` | All passed |
| `1` | At least one failure, or a timeout, or a startup failure |

**CI relies on exit codes; do not parse the stdout text.**

### 23.5 Log levels

| Language | How to enable debug logging |
|------|----------------------|
| Pascal | set `DEBUG_LOG = True` (in the service code) |
| Python | set `DEBUG_LOG = True` (top of `<Unit>_http_json_call.py`) |
| C++ | set `DEBUG_LOG = true` (in the service / call code) |
| C# | set `AppInfo.DebugLog = true` or `HttpJsonCallConfig.DebugLog = true` |
| JS | `DEBUG_LOG = true` (in `<Unit>_http_json_call.js`) |
| Node.js | `process.env.LINGOFUSE_DEBUG = '1'` or `DEBUG_LOG = true` |
| TypeScript | `HttpJsonCallConfig.debugLog = true` |
| PHP | `HttpJsonCallConfig::$debugLog = true` |
| Rust | `set_debug_log(true)` |
| Go | `SetDebugLog(true)` |
| Java | `-DLINGOFUSE_DEBUG=1` or an environment variable |
| Dart | `DEBUG_LOG = true` |
| Swift | set `debugLog = true` before `baseUrl` |
| Ruby | `Module.debug_log = true` |
| Zig | `call.DEBUG_LOG = true` |
| Erlang | the `DEBUG_LOG` constant (in the generated module) |
| Fortran | `DEBUG_LOG = .true.` |
| Julia | `DEBUG_LOG = true` (a module constant) |
| R | the `DEBUG_LOG` constant (in the generated module) |

**With debug enabled, every request and response is written to stderr, making problems much easier to locate.**

### 23.6 Sync / async coverage of the test drivers per language

| Language | Sync | Async | Notes |
|------|:----:|:----:|------|
| Pascal | ✅ | ✅ | the `_P` variants are not tested (nested limitation) |
| Python | ✅ | ✅ | `await` variants |
| C++ | ✅ | ✅ | `std::promise` + `std::future` |
| C# | ✅ | ✅ | `TaskCompletionSource` |
| JavaScript | — | ✅ | `await` / `Promise` only |
| Node.js | — | ✅ | `await` / `Promise` only |
| TypeScript | — | ✅ | `await` / `Promise` only |
| PHP | ✅ | — | synchronous only |
| Rust | ✅ | ✅ | `ureq` / `reqwest` |
| Go | ✅ | ✅ | sync / channel |
| Java | ✅ | — | synchronous only (HTTP client) |
| Delphi | ✅ | ✅ | `TThread` subclass |
| Dart | — | ✅ | `Future` only |
| Swift | ✅ | ✅ | `DispatchSemaphore` / `async` |
| Ruby | ✅ | — | synchronous only (concurrency possible with `Thread.new`) |
| Zig | ✅ | ✅ | LingoFuse `callAsync` |
| Erlang | ✅ | ✅ | `spawn` |
| Fortran | ✅ | ✅ | `lf_async_call` |
| Julia | ✅ | ✅ | `Task` / `future` |
| R | ✅ | ✅ | sync / `future` |

---

## Appendix: one-page quick reference

| Language | Service test command | Call test command | Needs the bridge? |
|------|-------------|-------------|:----------:|
| Pascal | `./<U>_http_json_service_main_test___ [--smoke]` | `./<U>_http_json_call_main_test___ [<base_url>]` | ✅ |
| Python | `python3 <U>_http_json_service_main_test___.py [--smoke]` | `python3 <U>_http_json_call_main_test___.py [<base_url>]` | ✅ |
| C++ | `./<U>_http_json_service` | `./<U>_http_json_call_test` | ✅ |
| C# | `dotnet run [-- --smoke]` | `dotnet run` | ✅ |
| JavaScript | double-click `*_test.html` | double-click `*_test.html` | ✅ |
| Node.js | `node <U>_http_json_service_main_test___.js [--smoke]` | `node <U>_http_json_call_main_test___.js [<base_url>]` | ✅ |
| TypeScript | `tsx <U>_http_json_service_main_test___.ts [--smoke]` | `tsx <U>_http_json_call_main_test___.ts [<base_url>]` | ✅ |
| PHP | — | `php <U>_http_json_call_main_test___.php [<base_url>]` | ✅ |
| Rust | `cargo run` (src/main.rs points at the service test) | `cargo run` (src/main.rs points at the call test) | ✅ |
| Go | `go test -v` (service test directory) | `go test -v` (call test directory) | ✅ |
| Java | `java HttpJsonServiceTest [--smoke]` | `java HttpJsonCallTest [<base_url>]` | ✅ |
| Delphi | — | `dcc32 <U>_http_json_call_delphi_test___.dpr` then run the `.exe` | ✅ |
| Dart | `dart run <U>_http_json_service_main_test___.dart` | `dart run <U>_http_json_call_main_test___.dart [<base_url>]` | ✅ |
| Swift | `swift <U>_http_json_service_main_test___.swift` | `swift <U>_http_json_call_main_test___.swift` | ✅ |
| Ruby | `ruby <U>_http_json_service_main_test___.rb [--smoke]` | `ruby <U>_http_json_call_main_test___.rb [<base_url>]` | ✅ |
| Zig | `cd zig_service_test && zig build run` | `cd zig_call_test && zig build run` | ✅ |
| Erlang | `escript <U>_http_json_service_main_test___.escript [--smoke]` | `escript <U>_http_json_call_main_test___.escript [<base_url>]` | ✅ |
| Fortran | `./service_test.exe [--smoke]` | `./call_test.exe [<base_url>]` | ✅ |
| Julia | `julia --threads=2 <U>_http_json_service_main_test___.jl [--smoke]` | `julia --threads=2 <U>_http_json_call_main_test___.jl [<base_url>] [<endpoint>]` | ✅ |
| R | `Rscript <U>_http_json_service_main_test___.R` | `Rscript <U>_http_json_call_main_test___.R` | ✅ |

**`<U>` = the normalized unit name; `<base_url>` defaults to `http://127.0.0.1:8081/<U>`; `<endpoint>` defaults to `ipc:<U>_http_json`.**

**The bridge program must always be running — that sentence means the same thing in every language.**
