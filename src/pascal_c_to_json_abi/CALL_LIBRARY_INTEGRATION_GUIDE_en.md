# CALL Library Integration Guide

> *English translation of [CALL_LIBRARY_INTEGRATION_GUIDE.md](CALL_LIBRARY_INTEGRATION_GUIDE.md).*

> This document gives the integration method for the **Call library (call side)** in **each target language**.
>
> **What the Call library is** — the Call library is the "call side" artifact: a code module that converts a local function call into a request to the LingoFuse HTTP bridge program (`bridge.py` / `bridge.exe`), and converts the response back into local types.
>
> **Three universal prerequisites for the Call library**:
>
> 1. **The bridge program (`bridge.py` / `bridge.exe`) must always be running**.
> 2. **The service side must already be started and online** (that is, the target `<AppName>` has joined the LingoFuse mesh).
> 3. **The bridge program's endpoint must match the service side exactly** (default `ipc:<UnitName>_http_json`).
>
> **The core of this document is "integration"** — that is: how to bring it in, initialize it, call it, configure it and handle errors in your project. It does **not** cover "how to build the artifact itself" (see `BUILD_GUIDE.md` for the build steps), nor "how to run the test driver" (see `HOW_TO_RUN_TESTS.md` for the run steps).
>
> **On "whether a bridge is needed"** — **all 20+ Call libraries access the service through the bridge program**. No exception. But **the integration approach splits into two modes**:
>
> - **Mode A (direct HTTP mode)**: the Call library POSTs directly to the bridge program's HTTP port. **No LingoFuse native library required**. Applies to Python, JavaScript, Node.js, TypeScript, PHP, Rust, Go, Java, Delphi, Dart, Swift, Ruby and Erlang.
> - **Mode B (LingoFuse Mesh mode)**: the Call library calls the bridge program's `__lf_outbound_post__` API directly through the LingoFuse C ABI, and the bridge program forwards it over HTTP. **The LingoFuse native library is required**. Applies to Pascal, C++, C#, Zig, Fortran, Julia and R.
>
> Both modes ultimately reach the bridge program, but **the dependencies, the initialization approach and the platform support range** differ. See chapter 2.

---

## Table of contents

1. [Positioning of the Call library](#1-positioning-of-the-call-library)
2. [The two integration modes](#2-the-two-integration-modes)
3. [Universal prerequisite: the bridge program must always be running](#3-universal-prerequisite-the-bridge-program-must-always-be-running)
4. [Mode A vs Mode B](#4-mode-a-vs-mode-b)
5. [Detailed integration per language](#5-detailed-integration-per-language)
   - [5.1 Pascal (mode B)](#51-pascal-mode-b)
   - [5.2 Python (mode A)](#52-python-mode-a)
   - [5.3 C++ (mode B)](#53-c-mode-b)
   - [5.4 C# (mode B)](#54-c-mode-b)
   - [5.5 JavaScript (mode A)](#55-javascript-mode-a)
   - [5.6 Node.js (mode A)](#56-nodejs-mode-a)
   - [5.7 TypeScript (mode A)](#57-typescript-mode-a)
   - [5.8 PHP (mode A)](#58-php-mode-a)
   - [5.9 Rust (mode A)](#59-rust-mode-a)
   - [5.10 Go (mode A)](#510-go-mode-a)
   - [5.11 Java (mode A)](#511-java-mode-a)
   - [5.12 Delphi (mode A)](#512-delphi-mode-a)
   - [5.13 Dart (mode A)](#513-dart-mode-a)
   - [5.14 Swift (mode A)](#514-swift-mode-a)
   - [5.15 Ruby (mode A)](#515-ruby-mode-a)
   - [5.16 Zig (mode B)](#516-zig-mode-b)
   - [5.17 Erlang (mode A)](#517-erlang-mode-a)
   - [5.18 Fortran (mode B)](#518-fortran-mode-b)
   - [5.19 Julia (mode B)](#519-julia-mode-b)
   - [5.20 R (mode B)](#520-r-mode-b)
6. [Platform and OS support matrix](#6-platform-and-os-support-matrix)
7. [Cross-comparison quick reference](#7-cross-comparison-quick-reference)
8. [Common integration problems](#8-common-integration-problems)

---

## 1. Positioning of the Call library

### 1.1 Call library = the call side

A complete interface pair consists of **Service (service side)** and **Call (call side)**:

| Side | Responsibility | Goes through the bridge? |
|----|------|:--------------:|
| **Service** | Registers functions as LingoFuse Call APIs, receives JSON requests and returns JSON responses | ❌ (the service itself does not go through the bridge) |
| **Call** | Converts local function calls into requests to the bridge program, then converts responses back to local types | ✅ **mandatory** |

### 1.2 Artifact naming

```
<UnitName>_http_json_call_<lang_suffix>.<ext>
```

| Language | Call library file name |
|------|--------------|
| Pascal | `<Unit>_http_json_call_unit.pas` |
| Python | `<Unit>_http_json_call.py` |
| C++ | `<Unit>_http_json_call.hpp` + `<Unit>_http_json_call.cpp` |
| C# | `<Unit>_http_json_call.cs` |
| JavaScript | `<Unit>_http_json_call.js` |
| Node.js | `<Unit>_http_json_call_node.js` |
| TypeScript | `<Unit>_http_json_call_ts.ts` |
| PHP | `<Unit>_http_json_call_php.php` |
| Rust | `<Unit>_http_json_call_rs.rs` |
| Go | `<Unit>_http_json_call_go.go` |
| Java | `HttpJsonClient.java` |
| Delphi | `<Unit>_http_json_call_delphi.pas` |
| Dart | `<Unit>_http_json_call.dart` |
| Swift | `<Unit>_http_json_call_swift.swift` |
| Ruby | `<Unit>_http_json_call.rb` |
| Zig | `<Unit>_http_json_call_zig.zig` |
| Erlang | `<Unit>_http_json_call.erl` |
| Fortran | `<Unit>_http_json_call_mod.f90` |
| Julia | `<Unit>_http_json_call.jl` |
| R | `<Unit>_http_json_call.R` |

### 1.3 Public interface exposed by the Call library

The Call library in each language exposes:

- **a typed function (synchronous)** for each supported API.
- **a typed function (asynchronous, where the language supports it)** for each supported API.
- **a configuration object** (base URL, timeout, bridge app name, etc.).
- **an error type** (`HTTPCallError` / `EHTTPCallError` / `LFHttpCallError` / `HttpJsonCallError` / `HttpCallError` / `HTTPCallException` etc.).

**Support for sync vs async** is covered in chapter 7.

---

## 2. The two integration modes

### 2.1 Mode A — direct HTTP mode

**The Call library POSTs directly to the bridge program's HTTP port.**

```
Call library  ──HTTP POST──▶  bridge.py :8081  ──LF_Call──▶  Service
Call library  ◀─HTTP response──  bridge.py :8081  ◀─LF return──  Service
```

**Characteristics**:

- **no LingoFuse native library needed** (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`).
- **no LingoFuse endpoint needed**.
- **no LingoFuse client initialization needed**.
- only `HTTP_CALL_BASE_URL` pointing at `http://127.0.0.1:8081/<UnitName>`.
- dependencies are the language's own HTTP client + JSON library.
- **platform support range = the language's own support range**.

**Languages using mode A**:

| # | Language | HTTP client | JSON library |
|:-:|------|-------------|---------|
| 1 | Python | `requests` | built-in `json` |
| 2 | JavaScript (browser) | built-in `fetch` | built-in `JSON` |
| 3 | Node.js | built-in `fetch` (Node 18+) | built-in `JSON` |
| 4 | TypeScript | built-in `fetch` | built-in `JSON` |
| 5 | PHP | `curl_*` / `fopen` | built-in `json_encode` / `json_decode` |
| 6 | Rust | `ureq` (sync) / `reqwest` (async) | `serde_json` |
| 7 | Go | `net/http` | built-in `encoding/json` |
| 8 | Java | `java.net.http.HttpClient` | Jackson `ObjectMapper` |
| 9 | Delphi | `System.Net.HttpClient` | `System.JSON` |
| 10 | Dart | `package:http` | built-in `dart:convert` |
| 11 | Swift | `URLSession` | `JSONSerialization` |
| 12 | Ruby | `net/http` | built-in `json` |
| 13 | Erlang | `httpc` | the `json` Erlang library |

### 2.2 Mode B — LingoFuse Mesh mode

**The Call library calls the bridge program's `__lf_outbound_post__` API directly through the LingoFuse C ABI, and the bridge program forwards it over HTTP.**

```
Call library  ──LF_Call──▶  bridge.py  ──HTTP POST──▶  Service
Call library  ◀─LF return──  bridge.py  ◀─HTTP response──  Service
```

**Characteristics**:

- **requires the LingoFuse native library** (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`) plus `z_ipc_*`.
- **requires a LingoFuse endpoint** (default `ipc:<UnitName>_http_json`).
- **requires LingoFuse client initialization**:
  - `LF_LoadLibrary` / the language-specific `init`.
  - `LF_PrepareClientEx` / `prepareClient` / `prepare_client`.
  - `LF_PrepareDone` / `prepareDone` / `prepare_done`.
- reaches the bridge program through `__lf_http_bridge__.__lf_outbound_post__`.
- **platform support range = the LingoFuse native library's support range**.

**Languages using mode B**:

| # | Language | Entry point | Dependencies |
|:-:|------|----------|------|
| 1 | Pascal | `LFHttpPost` / `LF_Async_CallEx` (from `lf_http_bridge_client`) | `lingofuse_import`, `lf_http_bridge_client` |
| 2 | C++ | `lingofuse::bridge::httpCall` / `lingofuse::callAsync` (from `lf_http_bridge_client.hpp`) | `LingoFuse.hpp`, `lf_http_bridge_client.hpp`, `json.hpp` |
| 3 | C# | `Framework.Call` / `Async.Call` (from the `LingoFuse` .NET binding) | the `LingoFuse` .NET binding |
| 4 | Zig | `lf.framework.call` / `lf.async_call.callAsync` (from the `lingofuse` Zig binding) | the `lingofuse` Zig binding |
| 5 | Fortran | `lf_call` / `lf_async_call` (from `lf_fortran_mod`) | `lf_fortran_mod.f90`, `lf_fortran.cpp` |
| 6 | Julia | `lingofuse.call` / `lingofuse.future` (from the `LingoFuse` Julia binding) | `LingoFuse`, `JSON3` |
| 7 | R | `lingofuse::lf_call` (from the `lingofuse` R package) | `lingofuse`, `jsonlite`, `future` (for async only) |

### 2.3 Why two modes exist

- **Mode A**: purely for **minimal dependencies**. The calling language has a mature HTTP client, so plain HTTP is the simplest and most portable integration. **New languages should prefer mode A**.
- **Mode B**: because some languages (or some scenarios) **must use LingoFuse's mesh routing capability** (for example cross-network calls, or routing by App name / UID / P2PName), or because the language ecosystem has no stable HTTP client, or because existing users already depend on LingoFuse's C ABI.

**Both modes end up with the same effect**: the service side receives the same JSON request.

---

## 3. Universal prerequisite: the bridge program must always be running

**This is the shared prerequisite of all 20+ Call libraries.** See chapter 2 of `USER_GUIDE.md`.

**Quick reminder**:

```bash
python3 bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck
```

| Parameter | Notes |
|------|------|
| `--endpoint` | the LingoFuse endpoint, **identical** to the service side |
| `--port` | the bridge program's HTTP listening port. Default 8081 |
| `--no-precheck` | skips the API pre-check at startup. **Strongly recommended** |
| `--bridge-app` | overrides the bridge's default App name (default `__lf_http_bridge__`) |
| `--bridge-api` | overrides the bridge's default API name (default `__lf_outbound_post__`) |

**Three-process layout**:

```
Terminal 1 (service):  start the generated service
Terminal 2 (bridge):   python3 bridge.py --endpoint ipc:<UnitName>_http_json --port 8081
Terminal 3 (caller):   start your Call library integration code
```

**If the bridge program is not running**, every Call library fails immediately:

| Mode | Typical error |
|------|----------|
| Mode A | `Connection refused` / `Network error` / `HTTPCallError` |
| Mode B | `LF_PrepareClient returned -1` / `LF_Async_CallEx failed` / `no found app("__lf_http_bridge__")` |

---

## 4. Mode A vs Mode B

| Dimension | Mode A (direct HTTP) | Mode B (LingoFuse Mesh) |
|------|:------------------:|:-----------------------:|
| **Requires the bridge program** | ✅ mandatory | ✅ mandatory |
| **Requires the LingoFuse native library** | ❌ no | ✅ mandatory |
| **Requires a LingoFuse endpoint** | ❌ no | ✅ mandatory |
| **Requires LingoFuse initialization** | ❌ no | ✅ mandatory (init / prepareClient / prepareDone) |
| **Communication protocol** | HTTP POST | LingoFuse C ABI → the bridge's `__lf_outbound_post__` |
| **Dependencies** | the language's HTTP client + JSON library | the LingoFuse C ABI + a LingoFuse binding |
| **Platform support** | the language's own support range | the LingoFuse native library's support range |
| **Cross-network calls** | the bridge must be exposed publicly | via the LingoFuse mesh (App name / UID / P2PName routing) |
| **Languages** | Python / JS / Node.js / TS / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Erlang | Pascal / C++ / C# / Zig / Fortran / Julia / R |
| **Configuration entry** | `HTTP_CALL_BASE_URL` (pointing at `http://127.0.0.1:8081/<Unit>`) | `HTTP_CALL_BASE_URL` + `HTTP_BRIDGE_APP_NAME` + `HTTP_BRIDGE_API_NAME` + `LF_CLIENT_ENDPOINT` |
| **Typical error** | `Connection refused` | `LF_PrepareClient returned -1` |
| **Start order** | service → bridge → caller | service → bridge → caller (and the caller must initialize LingoFuse) |

**Advice for integrators**:

- If your language is in the mode A list, **prefer mode A** — fewer dependencies, wider platform coverage, simpler integration.
- If your language is in the mode B list (or you need LingoFuse's mesh routing), use mode B.
- Mode A and mode B can be **mixed** (different languages in one project using different modes), as long as they all point at the same bridge program.

---

## 5. Detailed integration per language

### 5.1 Pascal (mode B)

#### 5.1.1 Artifacts

```
<Unit>_http_json_call_unit.pas
```

#### 5.1.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `lingofuse_import.pas` | LingoFuse distribution | ✅ |
| `lf_http_bridge_client.pas` | LingoFuse distribution | ✅ |
| `Z.Core`, `Z.PascalStrings`, `Z.UPascalStrings`, `Z.UnicodeMixedLib`, `Z.Json` | the Z framework | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` / `libz_ipc_64.so` | LingoFuse distribution | ✅ (runtime) |

#### 5.1.3 Platform

- **Compiler**: FPC 3.2+ / Delphi 11+.
- **OS**: Windows (32/64-bit), Linux (x86_64 / aarch64), macOS (x86_64 / arm64). **Subject to the support range of the LingoFuse native library**.

#### 5.1.4 Initialization

```pascal
uses
  lingofuse_import,
  <Unit>_http_json_call_unit;

var
  App: TAppHnd___;
begin
  // 1. Load the LingoFuse native library (if not auto-loaded)
  //    LF_LoadLibrary is triggered automatically on the first LF_* call, but an explicit call is safer.
  if LF_LoadLibrary() <> 1 then
  begin
    WriteLn('Failed to load LingoFuse');
    Halt(1);
  end;

  // 2. Connect to the same LingoFuse endpoint as bridge.py
  LF_PrepareClientEx('ipc:<Unit>_http_json', nil);
  if LF_PrepareDone() <> 1 then
  begin
    WriteLn('LingoFuse prepare failed');
    Halt(1);
  end;

  // 3. Configure the base URL (already http://127.0.0.1:8081/<Unit> by default)
  HTTP_CALL_BASE_URL := 'http://127.0.0.1:8081/<Unit>';
end;
```

#### 5.1.5 Synchronous call

```pascal
try
  var Sum: Int64;
  Sum := Add(1, 2);
  WriteLn('Add(1, 2) = ', Sum);
except
  on E: EHTTPCallError do
    WriteLn('Add failed: ', E.Message);
end;
```

#### 5.1.6 Asynchronous call

```pascal
Add_Async(1, 2,
  procedure(const R: Int64)
  begin
    WriteLn('Add result: ', R);
  end,
  procedure(E: Exception)
  begin
    WriteLn('Add error: ', E.Message);
  end);
```

**Note**: the async callback runs on a **worker thread**. To update the UI, use `TThread.Queue(nil, ...)` yourself.

#### 5.1.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `string` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| `HTTP_CALL_TIMEOUT_MS` | `Integer` | `30000` | per-call timeout (ms) |

#### 5.1.8 Error handling

- **Exception type**: `EHTTPCallError`.
- **Fields**: `Code` (Integer), `HttpStatus` (Integer), `Message` (inherited from `Exception`).

#### 5.1.9 Shutdown

```pascal
LF_ExitMainThread;
LF_Shutdown;
```

---

### 5.2 Python (mode A)

#### 5.2.1 Artifacts

```
<Unit>_http_json_call.py
```

#### 5.2.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `requests` | PyPI | ✅ |
| Python 3.8+ | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.2.3 Platform

- **Compiler / runtime**: Python 3.8+.
- **OS**: every platform that Python + `requests` support — Windows, Linux, macOS, FreeBSD, OpenBSD, NetBSD and so on.

#### 5.2.4 Initialization

```python
import <Unit>_http_json_call as api

# set the base URL (already http://127.0.0.1:8081/<Unit> by default)
api.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>"

# set the timeout (30.0 seconds by default)
api.HTTP_CALL_TIMEOUT = 30.0

# enable debug logging (False by default)
api.DEBUG_LOG = False
```

LingoFuse initialization is **not** required.

#### 5.2.5 Synchronous call

```python
try:
    result = api.Add(1, 2)
    print(f"Add(1, 2) = {result}")
except api.HTTPCallError as e:
    print(f"Add failed: {e.message}, code={e.code}, http_status={e.http_status}")
```

#### 5.2.6 Asynchronous call

```python
import asyncio

async def main():
    try:
        result = await api.Add_async(1, 2)
        print(f"Add(1, 2) = {result}")
    except api.HTTPCallError as e:
        print(f"Add failed: {e.message}")

asyncio.run(main())
```

#### 5.2.7 Configuration

| Configuration item | Default | Notes |
|--------|--------|------|
| `HTTP_CALL_BASE_URL` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| `HTTP_CALL_TIMEOUT` | `30.0` | timeout (seconds) |
| `DEBUG_LOG` | `False` | whether to print requests / responses |

#### 5.2.8 Error handling

- **Exception type**: `HTTPCallError`.
- **Fields**: `.code` (int), `.http_status` (int), `.message` (str, inherited from `Exception`).

#### 5.2.9 Shutdown

None (Python's `requests` is stateless; the process exit releases everything).

---

### 5.3 C++ (mode B)

#### 5.3.1 Artifacts

```
<Unit>_http_json_call.hpp
<Unit>_http_json_call.cpp
```

#### 5.3.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `LingoFuse.h`, `LingoFuse.c` | LingoFuse distribution | ✅ |
| `LingoFuse.hpp`, `lf_io.hpp` | LingoFuse distribution | ✅ |
| `lf_http_bridge_client.hpp` | LingoFuse distribution | ✅ |
| `json.hpp` (nlohmann) | shipped with the LingoFuse distribution or obtained separately | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |

#### 5.3.3 Platform

- **Compiler**: C++17 (MSVC 2019+ / g++ 9+ / clang++ 10+).
- **OS**: Windows, Linux, macOS. **Subject to the support range of the LingoFuse C ABI native library**.

#### 5.3.4 Initialization

```cpp
#include "LingoFuse.hpp"
#include "<Unit>_http_json_call.hpp"

int main() {
    // 1. Load the LingoFuse native library (RAII)
    lingofuse::LibraryLoader loader;

    // 2. Connect to the same endpoint as bridge.py
    lingofuse::resetPrepare();
    lingofuse::prepareClient("ipc:<Unit>_http_json", nullptr);
    if (lingofuse::prepareDone() != 1) {
        std::cerr << "LingoFuse init failed" << std::endl;
        return 1;
    }

    // 3. Configure the base URL (already http://127.0.0.1:8081/<Unit> by default)
    <Unit>::HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";

    // ... calling ...

    lingofuse::exitMainThread();
    lingofuse::shutdown();
    return 0;
}
```

#### 5.3.5 Synchronous call

```cpp
try {
    std::int64_t sum = <Unit>::Add(1, 2);
    std::cout << "Add(1, 2) = " << sum << std::endl;
} catch (const <Unit>::HTTPCallError& e) {
    std::cerr << "Add failed: " << e.what()
              << " (code=" << e.code
              << ", http=" << e.http_status << ")" << std::endl;
}
```

#### 5.3.6 Asynchronous call

```cpp
#include <future>
#include <memory>

auto p = std::make_shared<std::promise<<Unit>::AddAsyncResult>>();
auto fut = p->get_future();

<Unit>::Add_Async(1, 2,
    [p](auto r) {
        try { p->set_value(std::move(r)); } catch (...) {}
    });

if (fut.wait_for(std::chrono::seconds(30)) == std::future_status::ready) {
    auto r = fut.get();
    if (r.ok) {
        std::cout << "Add = " << r.value << std::endl;
    } else {
        std::cerr << "Add failed: " << r.error << std::endl;
    }
} else {
    std::cerr << "Add timed out" << std::endl;
}
```

**Note**: the async callback runs on a **worker thread**. Do not touch unlocked shared state inside the callback.

#### 5.3.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `std::string` | `"http://127.0.0.1:8081/<Unit>"` | the bridge program's HTTP prefix |
| `HTTP_BRIDGE_APP_NAME` | `std::string` | `""` (i.e. `__lf_http_bridge__`) | bridge App name |
| `HTTP_BRIDGE_API_NAME` | `std::string` | `""` (i.e. `__lf_outbound_post__`) | bridge API name |
| `HTTP_CALL_TIMEOUT_MS` | `std::uint64_t` | `0` (default 60000) | LingoFuse round-trip timeout |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `double` | `0.0` (default 25.0) | outgoing HTTP timeout |

#### 5.3.8 Error handling

- **Exception type**: `<Unit>::HTTPCallError` (inherits from `std::runtime_error`).
- **Fields**: `.code` (int), `.http_status` (int), `.what()` (const char*).

#### 5.3.9 Shutdown

```cpp
lingofuse::exitMainThread();
lingofuse::shutdown();
// LibraryLoader calls LF_FreeLibrary automatically in its destructor
```

---

### 5.4 C# (mode B)

#### 5.4.1 Artifacts

```
<Unit>_http_json_call.cs
```

#### 5.4.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `LingoFuse` .NET binding (`LingoFuse.dll`) | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| .NET 8.0+ | — | ✅ |

#### 5.4.3 Platform

- **Runtime**: .NET 8.0+.
- **OS**: Windows, Linux, macOS. **Subject to the support range of the LingoFuse .NET binding and the native library**.
- **.NET Framework 4.x**: **not supported** (the generated code uses .NET 8+ features such as `JsonDocument` and `System.Text.Json`).

#### 5.4.4 Initialization

```csharp
using LingoFuse;
using <Unit>_http_json_call;

// 1. Configure the bridge parameters (already pointing at http://127.0.0.1:8081/<Unit> by default)
HttpJsonCallConfig.BaseUrl = "http://127.0.0.1:8081/<Unit>";
HttpJsonCallConfig.BridgeAppName = "__lf_http_bridge__";
HttpJsonCallConfig.BridgeApiName = "__lf_outbound_post__";
HttpJsonCallConfig.CallTimeoutMs = 60000;
HttpJsonCallConfig.HttpTimeoutSec = 25.0;

// 2. Connect to the LingoFuse endpoint
Framework.SetOption("Wait_Connection_ReadyOk", "True");
Framework.SetOption("Overlap_Connection", "True");
Framework.ResetPrepare();
Framework.PrepareClient("ipc:<Unit>_http_json", null);

if (Framework.PrepareDone() != 1)
{
    Console.Error.WriteLine("LingoFuse init failed");
    return 1;
}
```

#### 5.4.5 Synchronous call

```csharp
try
{
    long sum = API.Add(1, 2);
    Console.WriteLine($"Add(1, 2) = {sum}");
}
catch (HTTPCallError e)
{
    Console.Error.WriteLine($"Add failed: {e.Message} (code={e.Code}, http={e.HttpStatus})");
}
```

#### 5.4.6 Asynchronous call

```csharp
using System.Threading.Tasks;

var tcs = new TaskCompletionSource<API.AddAsyncResult>(
    TaskCreationOptions.RunContinuationsAsynchronously);

API.AddAsync(1, 2, r => tcs.TrySetResult(r));

if (tcs.Task.Wait(TimeSpan.FromSeconds(30)))
{
    var r = tcs.Task.Result;
    if (r.Ok)
        Console.WriteLine($"Add = {r.Value}");
    else
        Console.Error.WriteLine($"Add failed: {r.Error} (code={r.Code}, http={r.HttpStatus})");
}
else
{
    Console.Error.WriteLine("Add timed out");
}
```

**Note**: `RunContinuationsAsynchronously` on `TaskCompletionSource` is mandatory, otherwise the callback may execute synchronously on the worker thread.

#### 5.4.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HttpJsonCallConfig.BaseUrl` | `string` | `"http://127.0.0.1:8081/<Unit>"` | the bridge program's HTTP prefix |
| `HttpJsonCallConfig.BridgeAppName` | `string` | `"__lf_http_bridge__"` | bridge App name |
| `HttpJsonCallConfig.BridgeApiName` | `string` | `"__lf_outbound_post__"` | bridge API name |
| `HttpJsonCallConfig.CallTimeoutMs` | `ulong` | `60000` | LingoFuse round-trip timeout |
| `HttpJsonCallConfig.HttpTimeoutSec` | `double` | `25.0` | outgoing HTTP timeout |
| `HttpJsonCallConfig.DebugLog` | `bool` | `false` | whether to print the request URL |

#### 5.4.8 Error handling

- **Exception type**: `HTTPCallError` (inherits from `Exception`).
- **Fields**: `.Code` (int), `.HttpStatus` (int), `.Message` (string).

#### 5.4.9 Shutdown

```csharp
try { NetworkEvents.Clear(); } catch { }
try { Framework.ExitMainThread(); } catch { }
try { Framework.Shutdown(); } catch { }
```

---

### 5.5 JavaScript (mode A)

#### 5.5.1 Artifacts

```
<Unit>_http_json_call.js
```

#### 5.5.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| a modern browser (Chrome / Edge / Firefox / Safari) | — | ✅ |
| built-in `fetch`, `JSON` | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.5.3 Platform

- **Browser**: Chrome 57+, Edge 16+, Firefox 52+, Safari 11+ (`fetch` support).
- **OS**: any OS with a modern browser (Windows / macOS / Linux / ChromeOS / iOS / Android).

#### 5.5.4 Bringing it in

**Option A: a `<script>` tag**

```html
<script src="<Unit>_http_json_call.js"></script>
```

**Option B: `import` (ES Module)**

The generated `.js` is an IIFE hung on `window.<Unit>Api`, not an ES Module. To use it as a module you must rewrite it yourself.

#### 5.5.5 Initialization

```javascript
// the global object is already attached to window.<Unit>Api
// set the base URL
<Unit>Api.setBaseUrl("http://127.0.0.1:8081/<Unit>");

// or read it directly
console.log(<Unit>Api.getBaseUrl());
```

LingoFuse initialization is **not** required.

#### 5.5.6 Calling (async only)

```javascript
try {
    const sum = await <Unit>Api.Add(1, 2);
    console.log(`Add(1, 2) = ${sum}`);
} catch (e) {
    if (e instanceof <Unit>Api.Error) {
        console.error(`Add failed: ${e.message}, code=${e.code}, http=${e.httpStatus}`);
    } else {
        console.error(`Add failed: ${e}`);
    }
}
```

#### 5.5.7 Configuration

| Configuration item | Method | Default |
|--------|------|--------|
| Base URL | `<Unit>Api.setBaseUrl(url)` / `<Unit>Api.baseUrl` | `'http://127.0.0.1:8081/<Unit>'` |
| Error class | `<Unit>Api.Error` | `LFHttpCallError` |

**Note**: the JavaScript version **has no** `HTTP_CALL_TIMEOUT` setting — `fetch` uses the browser's default timeout (usually 300 seconds).

#### 5.5.8 Error handling

- **Exception type**: `<Unit>Api.Error` (i.e. `LFHttpCallError`).
- **Fields**: `.code` (number), `.httpStatus` (number), `.message` (string).

#### 5.5.9 Shutdown

None (closing the browser page releases everything).

---

### 5.6 Node.js (mode A)

#### 5.6.1 Artifacts

```
<Unit>_http_json_call_node.js
```

#### 5.6.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Node.js 18+ (`fetch` built in) | — | ✅ |
| built-in `fetch` | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.6.3 Platform

- **Runtime**: Node.js 18+.
- **OS**: every platform Node.js supports — Windows, Linux, macOS, FreeBSD, OpenBSD and so on.

#### 5.6.4 Bringing it in

```javascript
'use strict';

const api = require('./<Unit>_http_json_call_node.js');
```

#### 5.6.5 Initialization

```javascript
api.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";
api.HTTP_CALL_TIMEOUT_MS = 30000;
api.DEBUG_LOG = false;

// or through an environment variable
// process.env.LINGOFUSE_DEBUG = '1';
```

LingoFuse initialization is **not** required.

#### 5.6.6 Calling (async only)

```javascript
try {
    const sum = await api.Add(1, 2);
    console.log(`Add(1, 2) = ${sum}`);
} catch (e) {
    if (e instanceof api.HTTPCallError) {
        console.error(`Add failed: ${e.message}, code=${e.code}, http=${e.httpStatus}`);
    } else {
        console.error(`Add failed: ${e}`);
    }
}
```

#### 5.6.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `string` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| `HTTP_CALL_TIMEOUT_MS` | `number` | `30000` | timeout (ms), 0 means no timeout |
| `DEBUG_LOG` | `boolean` | `false` (or `LINGOFUSE_DEBUG=1`) | whether to print requests / responses |

#### 5.6.8 Error handling

- **Exception type**: `api.HTTPCallError` (inherits from `Error`).
- **Fields**: `.code` (number), `.httpStatus` (number), `.message` (string).

#### 5.6.9 Shutdown

None (the Node.js process exit releases everything).

---

### 5.7 TypeScript (mode A)

#### 5.7.1 Artifacts

```
<Unit>_http_json_call_ts.ts
```

#### 5.7.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| TypeScript 5.0+ | npm | ✅ |
| runtime Node 18+ (via `tsx`) or a modern browser | — | ✅ |
| built-in `fetch` | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.7.3 Platform

- **Runtime**: Node.js 18+ (running `.ts` directly through `tsx`) or compiled to JS and run in a browser.
- **OS**: same as the runtime.

#### 5.7.4 Bringing it in

```typescript
import * as api from "./<Unit>_http_json_call_ts";
```

#### 5.7.5 Initialization

```typescript
api.HttpJsonCallConfig.baseUrl = "http://127.0.0.1:8081/<Unit>";
api.HttpJsonCallConfig.httpTimeoutMs = 30000;
api.HttpJsonCallConfig.debugLog = false;
```

LingoFuse initialization is **not** required.

#### 5.7.6 Calling (async only)

```typescript
try {
    const sum: number = await api.Add(1, 2);
    console.log(`Add(1, 2) = ${sum}`);
} catch (e) {
    if (e instanceof api.HttpJsonCallError) {
        console.error(`Add failed: ${e.message}, code=${e.code}, http=${e.httpStatus}`);
    } else {
        console.error(`Add failed: ${e}`);
    }
}
```

#### 5.7.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HttpJsonCallConfig.baseUrl` | `string` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| `HttpJsonCallConfig.httpTimeoutMs` | `number` | `30000` | timeout (ms) |
| `HttpJsonCallConfig.debugLog` | `boolean` | `false` | whether to print requests / responses |

**Each API also accepts an optional `HttpJsonCallOptions`**:

```typescript
await api.Add(1, 2, { timeoutMs: 5000 });
```

#### 5.7.8 Error handling

- **Exception type**: `api.HttpJsonCallError` (inherits from `Error`).
- **Fields**: `.code` (number), `.httpStatus` (number), `.message` (string).

#### 5.7.9 Shutdown

None (the process exit releases everything).

---

### 5.8 PHP (mode A)

#### 5.8.1 Artifacts

```
<Unit>_http_json_call_php.php
```

#### 5.8.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| PHP 7.4+ | — | ✅ |
| the `curl` extension (preferred) | — | recommended |
| `allow_url_fopen=On` (fallback) | — | fallback |
| built-in `json_encode` / `json_decode` | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.8.3 Platform

- **Runtime**: PHP 7.4+.
- **OS**: every platform PHP supports — Windows, Linux, macOS, FreeBSD and so on.

#### 5.8.4 Bringing it in

```php
require_once __DIR__ . '/<Unit>_http_json_call_php.php';

use <SafeNamespace>\HttpJsonCallApi;
use <SafeNamespace>\HttpJsonCallConfig;
use <SafeNamespace>\HttpJsonCallError;
```

**`<SafeNamespace>`** is the normalized unit name (for example `unit Calculator;` → `Calculator`).

#### 5.8.5 Initialization

```php
HttpJsonCallConfig::$baseUrl = "http://127.0.0.1:8081/<Unit>";
HttpJsonCallConfig::$httpTimeoutSec = 30;
HttpJsonCallConfig::$debugLog = false;
```

LingoFuse initialization is **not** required.

#### 5.8.6 Calling (synchronous)

```php
try {
    $sum = HttpJsonCallApi::Add(1, 2);
    echo "Add(1, 2) = $sum\n";
} catch (HttpJsonCallError $e) {
    fwrite(STDERR, "Add failed: " . $e->getMessage()
        . ", code=" . $e->getCode()
        . ", http=" . $e->httpStatus . "\n");
}
```

**The PHP version only has synchronous calls** (no `_async` variant).

#### 5.8.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HttpJsonCallConfig::$baseUrl` | `string` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| `HttpJsonCallConfig::$httpTimeoutSec` | `int` | `30` | timeout (seconds) |
| `HttpJsonCallConfig::$debugLog` | `bool` | `false` | whether to print requests / responses |

**Each API also accepts an optional `$options` argument**:

```php
HttpJsonCallApi::Add(1, 2, ['timeoutSec' => 5]);
```

#### 5.8.8 Error handling

- **Exception type**: `HttpJsonCallError` (inherits from `\RuntimeException`).
- **Fields**: `.getCode()` (int), `.httpStatus` (int), `.getMessage()` (string).

#### 5.8.9 Shutdown

None (PHP's `curl` releases automatically after each request).

---

### 5.9 Rust (mode A)

#### 5.9.1 Artifacts

```
<Unit>_http_json_call_rs.rs
```

#### 5.9.2 Dependencies

**`Cargo.toml`**:

```toml
[dependencies]
ureq = "2"                                    # synchronous
reqwest = { version = "0.12", features = ["json"] }  # asynchronous
tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }
serde_json = "1"
```

The LingoFuse native library is **not** required.

#### 5.9.3 Platform

- **Compiler / runtime**: Rust 1.70+.
- **OS**: Windows, Linux, macOS, FreeBSD and various embedded platforms — **every platform Rust supports**.

#### 5.9.4 Bringing it in

**Option A: crate root (`src/main.rs` or `src/lib.rs`)**

```rust
mod <unit_snake_case>_http_json_call;  // the file name
use <unit_snake_case>_http_json_call as api;
```

**Option B: a `#[path]` submodule**

```rust
#[path = "<Unit>_http_json_call_rs.rs"]
mod api;
```

#### 5.9.5 Initialization

```rust
api::set_base_url("http://127.0.0.1:8081/<Unit>");
api::set_timeout_secs(30);
api::set_debug_log(false);
```

LingoFuse initialization is **not** required.

#### 5.9.6 Synchronous call

```rust
match api::Add(1, 2) {
    Ok(sum) => println!("Add(1, 2) = {}", sum),
    Err(e) => eprintln!("Add failed: {} (code={}, http={})",
                        e, e.code, e.http_status),
}
```

#### 5.9.7 Asynchronous call

```rust
#[tokio::main]
async fn main() {
    match api::Add_async(1, 2).await {
        Ok(sum) => println!("Add(1, 2) = {}", sum),
        Err(e) => eprintln!("Add failed: {}", e),
    }
}
```

It **must** run inside `#[tokio::main]` or a manually constructed `tokio::runtime::Runtime`.

#### 5.9.8 Configuration

| Configuration item | Function | Default |
|--------|------|--------|
| Base URL | `set_base_url(&str)` / `get_base_url() -> String` | `"http://127.0.0.1:8081/<Unit>"` |
| Timeout (seconds) | `set_timeout_secs(u64)` / `get_timeout_secs() -> u64` | `30` (0 means no timeout) |
| Debug log | `set_debug_log(bool)` / `get_debug_log() -> bool` | `false` |

#### 5.9.9 Error handling

- **Error type**: `api::HttpCallError` (implements `std::error::Error` + `std::fmt::Display`).
- **Fields**: `.code` (i32), `.http_status` (i32), `.message` (String).

#### 5.9.10 Shutdown

None (Rust's `ureq` / `reqwest` release automatically on drop).

---

### 5.10 Go (mode A)

#### 5.10.1 Artifacts

```
<Unit>_http_json_call_go.go
```

#### 5.10.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Go 1.21+ | — | ✅ |
| the standard library (`net/http`, `encoding/json`, `context`) | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.10.3 Platform

- **Runtime**: Go 1.21+.
- **OS**: Windows, Linux, macOS, FreeBSD, OpenBSD, NetBSD, Plan 9, Android, iOS, WASM — **every platform Go supports**.

#### 5.10.4 Bringing it in

```go
import (
    "github.com/yourorg/yourmodule/<unit>_http_json_call_go"
)
```

or directly within the same package.

#### 5.10.5 Initialization

```go
call.SetBaseURL("http://127.0.0.1:8081/<Unit>")
call.SetTimeout(30 * time.Second)
call.SetDebugLog(false)
```

LingoFuse initialization is **not** required.

#### 5.10.6 Synchronous call

```go
sum, err := call.Add(1, 2)
if err != nil {
    log.Printf("Add failed: %v", err)
} else {
    log.Printf("Add(1, 2) = %d", sum)
}
```

**A procedure (no return value)**:

```go
err := call.Log("hello")
if err != nil {
    log.Printf("Log failed: %v", err)
}
```

#### 5.10.7 Asynchronous call (channel style)

```go
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()

ch := call.AddAsync(ctx, 1, 2)
r := <-ch
if r.Err != nil {
    log.Printf("Add failed: %v", r.Err)
} else {
    log.Printf("Add = %d", r.Value)
}
```

#### 5.10.8 Configuration

| Configuration item | Variable / function | Default |
|--------|------------|--------|
| Base URL | `HTTPCallBaseURL` / `SetBaseURL(string)` | `DefaultBaseURL` |
| Timeout | `HTTPCallTimeout` / `SetTimeout(time.Duration)` | `30 * time.Second` (0 means no timeout) |
| Debug log | `DebugLog` / `SetDebugLog(bool)` | `false` |

#### 5.10.9 Error handling

- **Error type**: `*call.HTTPCallError` (implements the `error` interface).
- **Fields**: `.Message` (string), `.Code` (int), `.HTTPStatus` (int).

#### 5.10.10 Shutdown

None (Go's `http.Client` is usable at its zero value; the process exit releases everything).

---

### 5.11 Java (mode A)

#### 5.11.1 Artifacts

```
HttpJsonClient.java
```

#### 5.11.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| JDK 11+ | — | ✅ |
| `jackson-databind.jar` | Maven Central / manual | ✅ |
| built-in `java.net.http.HttpClient` | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.11.3 Platform

- **Runtime**: JDK 11+ (17+ recommended).
- **OS**: Windows, Linux, macOS, Solaris, AIX — **every platform the JDK supports**.

#### 5.11.4 Bringing it in

```java
import <package>.HttpJsonClient;
import <package>.HttpJsonClient.HTTPCallException;
```

**`<package>`** is the Java package of the generated code (none by default, so you must add a `package` declaration yourself or place it in the caller's package).

#### 5.11.5 Initialization

```java
HttpJsonClient.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";
HttpJsonClient.HTTP_CALL_TIMEOUT = java.time.Duration.ofSeconds(30);
```

LingoFuse initialization is **not** required.

#### 5.11.6 Calling (synchronous only)

```java
try {
    long sum = HttpJsonClient.Add(1, 2);
    System.out.println("Add(1, 2) = " + sum);
} catch (HttpJsonClient.HTTPCallException e) {
    System.err.println("Add failed: " + e.getMessage()
        + " (code=" + e.code + ", http=" + e.httpStatus + ")");
}
```

**The Java version only has synchronous calls** (no `_async` variant).

#### 5.11.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `String` | `"http://127.0.0.1:8081/<Unit>"` | the bridge program's HTTP prefix |
| `HTTP_CALL_TIMEOUT` | `Duration` | `Duration.ofSeconds(30)` | timeout |

#### 5.11.8 Error handling

- **Exception type**: `HttpJsonClient.HTTPCallException` (inherits from `RuntimeException`).
- **Fields**: `.code` (int), `.httpStatus` (int), `.getMessage()` (String).

#### 5.11.9 Shutdown

None (Java's `HttpClient` is a process-level singleton).

---

### 5.12 Delphi (mode A)

#### 5.12.1 Artifacts

```
<Unit>_http_json_call_delphi.pas
```

#### 5.12.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Delphi 10.3+ | — | ✅ |
| `System.Net.HttpClient`, `System.JSON`, `System.Classes`, `System.Generics.Collections`, `System.Net.URLClient` | — | ✅ |

The LingoFuse native library is **not** required.

#### 5.12.3 Platform

- **Compiler**: Delphi 10.3+.
- **OS**: Windows, macOS, iOS, Android, Linux — **subject to the Delphi version**. Delphi 10.3 supports Windows 32/64-bit, macOS 64-bit, iOS, Android and Linux 64-bit.

#### 5.12.4 Bringing it in

```pascal
uses
  <Unit>_http_json_call_delphi;
```

#### 5.12.5 Initialization

```pascal
HTTP_CALL_BASE_URL := 'http://127.0.0.1:8081/<Unit>';
HTTP_CALL_TIMEOUT_MS := 30000;
```

LingoFuse initialization is **not** required.

#### 5.12.6 Synchronous call

```pascal
try
  var Sum := Add(1, 2);
  WriteLn('Add(1, 2) = ', Sum);
except
  on E: EHTTPCallError do
    WriteLn('Add failed: ', E.Message,
      ' (code=', E.Code, ', http=', E.HttpStatus, ')');
end;
```

#### 5.12.7 Asynchronous call

```pascal
Add_Async(1, 2,
  procedure(const R: Int64)
  begin
    WriteLn('Add = ', R);
  end,
  procedure(E: Exception)
  begin
    WriteLn('Add failed: ', E.Message);
  end);
```

**Note**: the async callback runs on a **worker thread**. To update the UI use `TThread.Queue`.

#### 5.12.8 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `string` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| `HTTP_CALL_TIMEOUT_MS` | `Integer` | `30000` | timeout (ms), 0 means no timeout |

#### 5.12.9 Error handling

- **Exception type**: `EHTTPCallError` (inherits from `Exception`).
- **Fields**: `.Code` (Integer), `.HttpStatus` (Integer), `.Message` (string).

#### 5.12.10 Shutdown

None (Delphi's `THTTPClient` releases after each call).

---

### 5.13 Dart (mode A)

#### 5.13.1 Artifacts

```
<Unit>_http_json_call.dart
```

#### 5.13.2 Dependencies

**`pubspec.yaml`**:

```yaml
dependencies:
  http: ^1.0.0
```

The LingoFuse native library is **not** required.

#### 5.13.3 Platform

- **Runtime**: Dart 3.0+.
- **OS**: Windows, Linux, macOS, iOS, Android, Web (via Flutter or Dart Web) — **every platform Dart supports**.

#### 5.13.4 Bringing it in

```dart
import 'package:your_package/<Unit>_http_json_call.dart' as api;
```

or from the same directory:

```dart
import '<Unit>_http_json_call.dart' as api;
```

#### 5.13.5 Initialization

```dart
api.setBaseUrl('http://127.0.0.1:8081/<Unit>');
api.HTTP_CALL_TIMEOUT = const Duration(seconds: 30);
api.DEBUG_LOG = false;
```

LingoFuse initialization is **not** required.

#### 5.13.6 Calling (async only)

```dart
try {
    final sum = await api.Add(1, 2);
    print('Add(1, 2) = $sum');
} on api.HttpCallError catch (e) {
    print('Add failed: ${e.message}, code=${e.code}, http=${e.httpStatus}');
}
```

#### 5.13.7 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| Base URL | `setBaseUrl(url)` / `getBaseUrl()` / `DEFAULT_BASE_URL` | `'http://127.0.0.1:8081/<Unit>'` | the bridge program's HTTP prefix |
| Timeout | `HTTP_CALL_TIMEOUT` | `Duration(seconds: 30)` | timeout |
| Debug log | `DEBUG_LOG` | `false` | whether to print requests / responses |

#### 5.13.8 Error handling

- **Exception type**: `api.HttpCallError` (implements `Exception`).
- **Fields**: `.message` (String), `.code` (int), `.httpStatus` (int).

#### 5.13.9 Shutdown

None (Dart's `http.Client` releases after each request, or at process exit).

---

### 5.14 Swift (mode A)

#### 5.14.1 Artifacts

```
<Unit>_http_json_call_swift.swift
```

#### 5.14.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Swift 5.9+ | — | ✅ |
| `Foundation` | standard library | ✅ |
| `FoundationNetworking` (Linux) | — | required on Linux |
| `Dispatch` | standard library | ✅ |

The LingoFuse native library is **not** required.

#### 5.14.3 Platform

- **Compiler / runtime**: Swift 5.9+.
- **OS**: macOS 12+, iOS 15+ (required by the async API), Linux, Windows. **macOS 11 / iOS 14 can only use the synchronous API**.

#### 5.14.4 Bringing it in

**Option A: within the same module**

```swift
// add the generated .swift file to the target directly
let sum = try <Unit>HttpJsonClient.Add(1, 2)
```

**Option B: as an SPM package**

Put the `.swift` file into the `Sources/<ModuleName>/` directory.

#### 5.14.5 Initialization

```swift
<Unit>HttpJsonClient.baseUrl = "http://127.0.0.1:8081/<Unit>"
<Unit>HttpJsonClient.timeout = 30.0
<Unit>HttpJsonClient.debugLog = false
```

LingoFuse initialization is **not** required.

#### 5.14.6 Synchronous call

```swift
do {
    let sum = try <Unit>HttpJsonClient.Add(1, 2)
    print("Add(1, 2) = \(sum)")
} catch let e as <Unit>HttpJsonClient.HTTPCallError {
    print("Add failed: \(e.message) (code=\(e.code), http=\(e.httpStatus))")
} catch {
    print("Add failed: \(error)")
}
```

#### 5.14.7 Asynchronous call

```swift
@available(macOS 12.0, iOS 15.0, *)
func callAddAsync() async {
    do {
        let sum = try await <Unit>HttpJsonClient.Add_async(1, 2)
        print("Add(1, 2) = \(sum)")
    } catch let e as <Unit>HttpJsonClient.HTTPCallError {
        print("Add failed: \(e.message)")
    } catch {
        print("Add failed: \(error)")
    }
}
```

#### 5.14.8 Configuration

| Configuration item | Type | Default | Notes |
|--------|------|--------|------|
| `baseUrl` | `String` | `"http://127.0.0.1:8081/<Unit>"` | the bridge program's HTTP prefix |
| `timeout` | `TimeInterval` | `30.0` | timeout (seconds) |
| `debugLog` | `Bool` | `false` | whether to print requests / responses |

#### 5.14.9 Error handling

- **Error type**: `<Unit>HttpJsonClient.HTTPCallError` (implements `Error` + `CustomStringConvertible`).
- **Fields**: `.message` (String), `.code` (Int), `.httpStatus` (Int).

#### 5.14.10 Shutdown

None (`URLSession.shared` is a process-level singleton).

---

### 5.15 Ruby (mode A)

#### 5.15.1 Artifacts

```
<Unit>_http_json_call.rb
```

#### 5.15.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Ruby 2.7+ / 3.0+ | — | ✅ |
| `net/http`, `json`, `uri` | standard library | ✅ |

The LingoFuse native library is **not** required.

#### 5.15.3 Platform

- **Runtime**: Ruby 2.7+ / 3.0+.
- **OS**: every platform Ruby supports — Windows, Linux, macOS, FreeBSD and so on.

#### 5.15.4 Bringing it in

```ruby
require_relative '<Unit>_http_json_call'
```

#### 5.15.5 Initialization

```ruby
<ModuleName>.base_url = "http://127.0.0.1:8081/<Unit>"
<ModuleName>.http_call_timeout = 30.0
<ModuleName>.debug_log = false
```

**`<ModuleName>`** is the generated Ruby module name (for example `<Unit>HttpJsonCall`).

**Pitfall**: do **not** assign to `HTTP_CALL_BASE_URL`. It is a read-only compatibility reader. Assigning to it is parsed by Ruby as a constant assignment and raises `dynamic constant assignment`.

#### 5.15.6 Calling (synchronous only)

```ruby
begin
  sum = <ModuleName>.Add(1, 2)
  puts "Add(1, 2) = #{sum}"
rescue <ModuleName>::HTTPCallError => e
  warn "Add failed: #{e.message}, code=#{e.code}, http=#{e.http_status}"
end
```

**Concurrent calls** use `Thread.new { ... }`:

```ruby
threads = []
threads << Thread.new { <ModuleName>.Add(1, 2) }
threads << Thread.new { <ModuleName>.Sub(5, 3) }
threads.each(&:join)
```

#### 5.15.7 Configuration

| Configuration item | Read/write | Default |
|--------|------|--------|
| `base_url` | read/write | `'http://127.0.0.1:8081/<Unit>'` |
| `http_call_timeout` | read/write | `30.0` |
| `debug_log` | read/write | `false` (or `LINGOFUSE_DEBUG=1`) |
| `HTTP_CALL_BASE_URL` | **read-only** | same as `base_url` |
| `HTTP_CALL_TIMEOUT` | **read-only** | same as `http_call_timeout` |
| `DEBUG_LOG` | **read-only** | same as `debug_log` |

#### 5.15.8 Error handling

- **Exception type**: `<ModuleName>::HTTPCallError` (inherits from `StandardError`).
- **Fields**: `.code` (Integer), `.http_status` (Integer), `.message` (String).

#### 5.15.9 Shutdown

None (Ruby's `Net::HTTP` is created fresh each time).

---

### 5.16 Zig (mode B)

#### 5.16.1 Artifacts

```
<Unit>_http_json_call_zig.zig
```

#### 5.16.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Zig 0.13+ | — | ✅ |
| the `lingofuse` Zig binding (`src/lingofuse.zig`) | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |

#### 5.16.3 Platform

- **Compiler**: Zig 0.13+.
- **OS**: Windows, Linux, macOS. **Subject to the support range of the LingoFuse native library**.

#### 5.16.4 Bringing it in

```zig
const call = @import("<Unit>_http_json_call_zig.zig");
```

**`build.zig`** needs:

```zig
const lf_dep = b.dependency("lingofuse", .{ .target = target, .optimize = optimize });
exe_mod.addImport("lingofuse", lf_dep.module("lingofuse"));
```

#### 5.16.5 Initialization

```zig
// 1. Load LingoFuse
try lf.framework.init();
defer lf.framework.deinit();

// 2. Configure options
lf.options.setWaitConnectionReadyOk(false) catch {};
lf.options.setOverlapConnection(true) catch {};
lf.options.setQuiet(true) catch {};

// 3. Connect the endpoint
lf.framework.resetPrepare();
_ = lf.framework.prepareClient("ipc:<Unit>_http_json", null) catch |e| {
    std.debug.print("[FATAL] prepareClient failed: {}\n", .{e});
    return;
};
_ = lf.framework.prepareDone();

// 4. Configure the base URL (already http://127.0.0.1:8081/<Unit> by default)
call.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";
```

#### 5.16.6 Synchronous call

```zig
if (call.Add(1, 2)) |sum| {
    std.debug.print("Add(1, 2) = {d}\n", .{sum});
} else |e| {
    const info = call.lastError();
    std.debug.print("Add failed: {s} (code={d}, msg={s})\n", .{
        @errorName(e), info.code, info.message()
    });
}
```

#### 5.16.7 Asynchronous call

```zig
const Waiter = struct {
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    success: bool = false,
    err_buf: [128]u8 = undefined,
    err_len: usize = 0,
};

fn addHandler(user_ctx: ?*anyopaque, result: call.Add_Result) void {
    const w: *Waiter = @ptrCast(@alignCast(user_ctx orelse return));
    switch (result) {
        .ok => { w.success = true; w.done.store(true, .release); },
        .err => |e| {
            const n = @errorName(e);
            const m = @min(n.len, w.err_buf.len);
            @memcpy(w.err_buf[0..m], n[0..m]);
            w.err_len = m;
            w.done.store(true, .release);
        },
    }
}

var w = Waiter{};
call.Add_async(1, 2, &w, addHandler) catch |e| {
    std.debug.print("submit failed: {}\n", .{e});
    return;
};
// poll w.done
```

#### 5.16.8 Configuration

| Configuration item | Type | Default |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `[]const u8` | `"http://127.0.0.1:8081/<Unit>"` |
| `BRIDGE_APP_NAME` | `[:0]const u8` | `"__lf_http_bridge__"` |
| `BRIDGE_API_NAME` | `[:0]const u8` | `"__lf_outbound_post__"` |
| `BRIDGE_TIMEOUT_MS` | `u64` | `35_000` |
| `DEFAULT_HTTP_TIMEOUT_SEC` | `u32` | `30` |
| `DEBUG_LOG` | `bool` | `false` |

#### 5.16.9 Error handling

- **Error type**: `call.HttpCallError` (an `error{}` enum).
- **Details**: `call.lastError()` returns `*const ErrorInfo` (containing `kind`, `code`, `http_status`, `message()`).

#### 5.16.10 Shutdown

```zig
lf.framework.exitMainThread();
lf.framework.shutdown();
lf.framework.deinit();
```

---

### 5.17 Erlang (mode A)

#### 5.17.1 Artifacts

```
<Unit>_http_json_call.erl
```

#### 5.17.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Erlang/OTP 25+ | — | ✅ |
| `inets` (`httpc`) | OTP standard library | ✅ |
| `ssl` | OTP standard library | ✅ |
| the `json` Erlang library | Hex / manual | ✅ |

The LingoFuse native library is **not** required.

#### 5.17.3 Platform

- **Runtime**: Erlang/OTP 25+.
- **OS**: every platform Erlang/OTP supports — Windows, Linux, macOS, FreeBSD and so on.

#### 5.17.4 Bringing it in

```erlang
-module(my_app).
-export([run/0]).

run() ->
    %% load the generated module
    <Unit>_http_json_call:set_base_url(<<"http://127.0.0.1:8081/<Unit>">>),
    <Unit>_http_json_call:set_timeout(30000),
    ...
```

**`<Unit>_http_json_call.erl`** must be compiled to `.beam` and be on the code path.

#### 5.17.5 Initialization

```erlang
ok = <Unit>_http_json_call:set_base_url(<<"http://127.0.0.1:8081/<Unit>">>),
ok = <Unit>_http_json_call:set_timeout(30000).
```

LingoFuse initialization is **not** required.

#### 5.17.6 Synchronous call

```erlang
case <Unit>_http_json_call:add(1, 2) of
    {ok, Sum} ->
        io:format("Add(1, 2) = ~p~n", [Sum]);
    {error, {service_error, Code, Msg}} ->
        io:format(standard_error, "Add failed: code=~p msg=~s~n", [Code, Msg]);
    {error, Reason} ->
        io:format(standard_error, "Add failed: ~p~n", [Reason])
end.
```

#### 5.17.7 Asynchronous call

```erlang
Self = self(),
<Unit>_http_json_call:add_async(1, 2, fun(R) -> Self ! {add_done, R} end),
receive
    {add_done, {ok, Sum}} -> io:format("Add = ~p~n", [Sum]);
    {add_done, {error, Reason}} -> io:format("Add failed: ~p~n", [Reason])
after 30000 ->
    io:format("Add timed out~n")
end.
```

#### 5.17.8 Configuration

| Configuration item | Function | Default |
|--------|------|--------|
| Base URL | `set_base_url/1` / `get_base_url/0` | `<<"http://127.0.0.1:8081/<Unit>">>` |
| Timeout (ms) | `set_timeout/1` / `get_timeout/0` | `30000` |

#### 5.17.8.1 Error format

- **Success**: `{ok, Result}`
- **Service error**: `{error, {service_error, Code, Msg}}`
- **HTTP error**: `{error, {http_status, Status, Body}}`
- **Transport error**: `{error, {http_error, Reason}}`
- **JSON parse failure**: `{error, {json_decode_failed, Reason}}`

#### 5.17.9 Shutdown

None (Erlang's `httpc` is an OTP-level application; the process exit releases everything).

---

### 5.18 Fortran (mode B)

#### 5.18.1 Artifacts

```
<Unit>_http_json_call_mod.f90
```

#### 5.18.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| gfortran 9+ / ifort / flang | — | ✅ |
| `lf_fortran_mod.f90` | LingoFuse distribution | ✅ |
| `lf_fortran.cpp` | LingoFuse distribution | ✅ |
| `LingoFuse.c` | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |

#### 5.18.3 Platform

- **Compiler**: gfortran 9+ / ifort / flang.
- **OS**: Windows, Linux, macOS. **Subject to the support range of `lf_fortran.cpp` + the LingoFuse C ABI native library**.

#### 5.18.4 Bringing it in

```fortran
program my_app
  use iso_c_binding
  use lf_fortran_mod
  use <Unit>_http_json_call_mod
  implicit none
  ! ...
end program
```

#### 5.18.5 Initialization

```fortran
call http_call_init( &
    base_url = 'http://127.0.0.1:8081/<Unit>', &
    bridge_app = '__lf_http_bridge__', &
    bridge_api = '__lf_outbound_post__', &
    call_timeout_ms = 60000_c_int64_t, &
    http_timeout_sec = 25.0d0)
```

**Note**: Fortran's `http_call_init` does **not** load the LingoFuse native library — that is `lf_fortran_mod`'s job. **The caller must complete LingoFuse initialization first**:

```fortran
! pseudo-code — see lf_fortran_mod for the exact API
call lf_load_library()
call lf_prepare_client('ipc:<Unit>_http_json', c_null_ptr)
call lf_prepare_done()
```

#### 5.18.6 Synchronous call

```fortran
integer(c_int64_t) :: sum
sum = add_call(1_c_int64_t, 2_c_int64_t)
print *, 'Add(1, 2) = ', sum
```

**A procedure**:

```fortran
call log_call('hello')
```

**Failure handling**: the Fortran version has no exception mechanism. On failure it returns the type's zero value (`0` / `0.0d0` / `''`), or `c_null_ptr`. **The caller must check whether the return value is a zero value**, or use the async API's `ok` output argument.

#### 5.18.7 Asynchronous call

```fortran
subroutine my_callback(user_data, result_handle) bind(C)
    type(c_ptr), value :: user_data, result_handle
    logical :: ok
    integer(c_int64_t) :: sum
    sum = add_read_async_result(result_handle, ok)
    if (ok) then
        print *, 'Add = ', sum
    else
        print *, 'Add failed'
    end if
end subroutine

call add_call_async(1_c_int64_t, 2_c_int64_t, &
    c_funloc(my_callback), c_null_ptr)
```

#### 5.18.8 Configuration

| Configuration item | Type | Default |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `character(len=512)` | `'http://127.0.0.1:8081/<Unit>'` |
| `HTTP_BRIDGE_APP_NAME` | `character(len=128)` | `'__lf_http_bridge__'` |
| `HTTP_BRIDGE_API_NAME` | `character(len=128)` | `'__lf_outbound_post__'` |
| `HTTP_CALL_TIMEOUT_MS` | `integer(c_int64_t)` | `0` (default 60000) |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `real(c_double)` | `0.0d0` (default 25.0) |

#### 5.18.9 Error handling

- **Synchronous call**: returns the type's zero value (`0` / `0.0d0` / `''`), with no exception mechanism.
- **Asynchronous call**: the `ok` output argument of `*_read_async_result(handle, ok)` is a `logical`.
- **Return value checking**: the caller must test it explicitly.

#### 5.18.10 Shutdown

```fortran
call lf_exit_main_thread()
call lf_shutdown()
```

---

### 5.19 Julia (mode B)

#### 5.19.1 Artifacts

```
<Unit>_http_json_call.jl
```

#### 5.19.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| Julia 1.9+ | — | ✅ |
| the `LingoFuse` Julia binding | LingoFuse distribution | ✅ |
| `JSON3` | Julia registry | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| **`--threads=2` or more** | — | ✅ |

#### 5.19.3 Platform

- **Runtime**: Julia 1.9+ (1.10+ recommended).
- **OS**: Windows, Linux, macOS, FreeBSD. **Subject to the support range of the LingoFuse Julia binding**.

#### 5.19.4 Bringing it in

```julia
include("<Unit>_http_json_call.jl")
import .<Unit>HttpJsonCall
```

or as a project package:

```julia
using <Unit>HttpJsonCall
```

#### 5.19.5 Initialization

**Must be inside a Julia process started with `--threads=2` or more**:

```julia
using LingoFuse
import LingoFuse: reset_prepare, prepare_client, prepare_done,
                  set_option, start_callback_consumer,
                  stop_callback_consumer

# 1. start the callback consumer (required)
start_callback_consumer()

# 2. configure
set_option("Wait_Connection_ReadyOk", "True")
set_option("Overlap_Connection", "True")
reset_prepare()

# 3. connect the endpoint
prepare_client("ipc:<Unit>_http_json", nothing)
prepare_done()

# 4. configure the base URL
<Unit>HttpJsonCall.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>"
```

#### 5.19.6 Synchronous call

```julia
try
    sum = <Unit>HttpJsonCall.add(1, 2)
    println("Add(1, 2) = $sum")
catch e
    if e isa <Unit>HttpJsonCall.HTTPCallError
        println("Add failed: $(e.msg), code=$(e.code), http=$(e.http_status)")
    else
        rethrow()
    end
end
```

#### 5.19.7 Asynchronous call

```julia
task = <Unit>HttpJsonCall.add_async(1, 2)
try
    sum = fetch(task)
    println("Add(1, 2) = $sum")
catch e
    println("Add failed: $e")
end
```

#### 5.19.8 Configuration

| Configuration item | Type | Default |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `String` | `"http://127.0.0.1:8081/<Unit>"` |
| `HTTP_BRIDGE_APP_NAME` | `String` | `""` (i.e. `"__lf_http_bridge__"`) |
| `HTTP_BRIDGE_API_NAME` | `String` | `""` (i.e. `"__lf_outbound_post__"`) |
| `HTTP_CALL_TIMEOUT_MS` | `Int64` | `Int64(0)` (default 60000) |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `Float64` | `0.0` (default 25.0) |

#### 5.19.9 Error handling

- **Exception type**: `<Unit>HttpJsonCall.HTTPCallError` (implements `Exception`).
- **Fields**: `.msg` (String), `.code` (Int), `.http_status` (Int).

#### 5.19.10 Shutdown

```julia
stop_callback_consumer()
```

---

### 5.20 R (mode B)

#### 5.20.1 Artifacts

```
<Unit>_http_json_call.R
```

#### 5.20.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| R 4.0+ | — | ✅ |
| the `lingofuse` R package | LingoFuse distribution | ✅ |
| `jsonlite` | CRAN | ✅ |
| `future` (async only) | CRAN | required for async |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |

#### 5.20.3 Platform

- **Runtime**: R 4.0+.
- **OS**: Windows, Linux, macOS. **Subject to the support range of the `lingofuse` R package**.

#### 5.20.4 Bringing it in

```r
source("<Unit>_http_json_call.R")
```

or as a package.

#### 5.20.5 Initialization

```r
# 1. set the LingoFuse runtime directory (optional, if the default probing fails)
LF_CLIENT_RUNTIME_DIR <- "C:/LingoFuse/Binary"

# 2. configure the base URL (already http://127.0.0.1:8081/<Unit> by default)
HTTP_CALL_BASE_URL <- "http://127.0.0.1:8081/<Unit>"

# 3. initialize the LingoFuse client
lf_http_client_init()

# 4. optional: async needs the future package
if (requireNamespace("future", quietly = TRUE)) {
    future::plan(future::sequential)
}
```

`lf_http_client_init()` internally does:

- `lingofuse::lf_load(runtime_dir)`
- `lingofuse::lf_prepare_client(endpoint, NULL)`
- `lingofuse::lf_prepare_done()`

#### 5.20.6 Synchronous call

```r
result <- tryCatch(
    add(1, 2),
    http_call_error = function(e) {
        cat("Add failed: ", conditionMessage(e),
            " (code=", e$code, ", http=", e$http_status, ")\n", sep = "")
        NULL
    }
)
if (!is.null(result)) {
    cat("Add(1, 2) = ", result, "\n", sep = "")
}
```

#### 5.20.7 Asynchronous call

```r
# requires future::plan(future::sequential)
future::plan(future::sequential)

fut <- add_async(1, 2,
    on_success = function(r) cat("Add = ", r, "\n", sep = ""),
    on_error = function(msg, code) cat("Add failed: ", msg, " (code=", code, ")\n", sep = ""))
value(fut)  # blocking wait
```

**Warning**: the `*_async` variants **require** `future::plan("sequential")`. `multisession` / `multicore` fork worker processes, and the LingoFuse runtime is not initialized in the child process, so the internal calls fail forever. The generated `*_async` functions check at dispatch time and report an error immediately if the plan is incompatible.

**For concurrency, use the synchronous functions plus your own thread pool.**

#### 5.20.8 Configuration

| Configuration item | Type | Default |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `character` | `"http://127.0.0.1:8081/<Unit>"` |
| `HTTP_BRIDGE_APP_NAME` | `character` | `"__lf_http_bridge__"` |
| `HTTP_BRIDGE_API_NAME` | `character` | `"__lf_outbound_post__"` |
| `HTTP_CALL_TIMEOUT_MS` | `integer` | `60000` |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `numeric` | `25.0` |
| `LF_CLIENT_ENDPOINT` | `character` | `"ipc:<Unit>_http_json"` |
| `LF_CLIENT_RUNTIME_DIR` | `character` or `NULL` | `NULL` (auto-probed) |

#### 5.20.9 Error handling

- **Exception type**: `http_call_error` (`structure(class = c("http_call_error", "error", "condition"), list(...))`).
- **Fields**: `e$message` (character), `e$code` (integer), `e$http_status` (integer).

#### 5.20.10 Shutdown

```r
lf_http_client_shutdown()
```

It internally calls `lingofuse::lf_exit_main_thread()` + `lingofuse::lf_shutdown()`.

---

## 6. Platform and OS support matrix

### 6.1 By language

| Language | Compiler / runtime | Windows | Linux | macOS | Other OS | Notes |
|------|----------------|:-------:|:-----:|:-----:|---------|------|
| Pascal | FPC 3.2+ / Delphi 11+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library | mode B |
| Python | Python 3.8+ | ✅ | ✅ | ✅ | FreeBSD, OpenBSD etc. | mode A |
| C++ | C++17 compiler | ✅ | ✅ | ✅ | limited by the LingoFuse native library | mode B |
| C# | .NET 8.0+ | ✅ | ✅ | ✅ | limited by the LingoFuse .NET binding | mode B |
| JavaScript | modern browser | ✅ | ✅ | ✅ | iOS, Android, ChromeOS | mode A |
| Node.js | Node.js 18+ | ✅ | ✅ | ✅ | FreeBSD, OpenBSD | mode A |
| TypeScript | Node.js 18+ / browser | ✅ | ✅ | ✅ | same as the runtime | mode A |
| PHP | PHP 7.4+ | ✅ | ✅ | ✅ | FreeBSD etc. | mode A |
| Rust | Rust 1.70+ | ✅ | ✅ | ✅ | FreeBSD, WASM, embedded | mode A |
| Go | Go 1.21+ | ✅ | ✅ | ✅ | FreeBSD, OpenBSD, NetBSD, Plan 9, Android, iOS, WASM | mode A |
| Java | JDK 11+ | ✅ | ✅ | ✅ | Solaris, AIX | mode A |
| Delphi | Delphi 10.3+ | ✅ | ✅ | ✅ | iOS, Android (subject to the Delphi version) | mode A |
| Dart | Dart 3.0+ | ✅ | ✅ | ✅ | iOS, Android, Web | mode A |
| Swift | Swift 5.9+ | ✅ | ✅ | ✅ | iOS (async requires macOS 12+ / iOS 15+) | mode A |
| Ruby | Ruby 2.7+ / 3.0+ | ✅ | ✅ | ✅ | FreeBSD etc. | mode A |
| Zig | Zig 0.13+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library | mode B |
| Erlang | Erlang/OTP 25+ | ✅ | ✅ | ✅ | FreeBSD etc. | mode A |
| Fortran | gfortran 9+ | ✅ | ✅ | ✅ | limited by `lf_fortran.cpp` + the LingoFuse native library | mode B |
| Julia | Julia 1.9+ | ✅ | ✅ | ✅ | FreeBSD | mode B, `--threads=2` mandatory |
| R | R 4.0+ | ✅ | ✅ | ✅ | limited by the `lingofuse` R package | mode B |

### 6.2 By OS

| OS | Mode A support | Mode B support |
|----------|:-----------:|:-----------:|
| Windows (x86 / x64 / arm64) | ✅ Python, JS, Node.js, TS, PHP, Rust, Go, Java, Delphi, Dart, Swift, Ruby, Erlang | ✅ Pascal, C++, C#, Zig, Fortran, Julia, R |
| Linux (x64 / arm64) | ✅ Python, JS, Node.js, TS, PHP, Rust, Go, Java, Dart, Swift, Ruby, Erlang | ✅ Pascal, C++, C#, Zig, Fortran, Julia, R |
| macOS (x64 / arm64) | ✅ Python, JS, Node.js, TS, PHP, Rust, Go, Java, Delphi, Dart, Swift, Ruby, Erlang | ✅ Pascal, C++, C#, Zig, Fortran, Julia, R |
| iOS / iPadOS | ✅ JavaScript, Swift, Dart, Delphi | ❌ (the LingoFuse native library does not support them) |
| Android | ✅ JavaScript, Dart, Delphi | ❌ |
| FreeBSD / OpenBSD / NetBSD | ✅ Python, Rust, Go, Ruby, Erlang | ❌ |
| Browser (any OS) | ✅ JavaScript | ❌ |
| WASM | ✅ Rust, Go | ❌ |

**Key conclusions**:

- **Mobile (iOS / Android) can only use mode A**, because the LingoFuse native library does not support those platforms.
- **Embedded / WASM can only use mode A.** Same reason.
- **Desktop / server (Windows / Linux / macOS) can use both mode A and mode B**.

### 6.3 By "whether the LingoFuse native library is needed"

| Language | Needs `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | Needs `z_ipc_*` | Needs `bridge.py` |
|------|:-----------------------------------------------------------:|:---------------:|:----------------:|
| Python | ❌ | ❌ | ✅ |
| JavaScript | ❌ | ❌ | ✅ |
| Node.js | ❌ | ❌ | ✅ |
| TypeScript | ❌ | ❌ | ✅ |
| PHP | ❌ | ❌ | ✅ |
| Rust | ❌ | ❌ | ✅ |
| Go | ❌ | ❌ | ✅ |
| Java | ❌ | ❌ | ✅ |
| Delphi | ❌ | ❌ | ✅ |
| Dart | ❌ | ❌ | ✅ |
| Swift | ❌ | ❌ | ✅ |
| Ruby | ❌ | ❌ | ✅ |
| Erlang | ❌ | ❌ | ✅ |
| Pascal | ✅ | ✅ | ✅ |
| C++ | ✅ | ✅ | ✅ |
| C# | ✅ | ✅ | ✅ |
| Zig | ✅ | ✅ | ✅ |
| Fortran | ✅ | ✅ | ✅ |
| Julia | ✅ | ✅ | ✅ |
| R | ✅ | ✅ | ✅ |

**The biggest advantage of mode A**: **no LingoFuse native library is needed at all**; only `bridge.py` running is required. That makes integrating Python / JS / Node.js / TS / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Erlang extremely simple — no DLL loading, no cross-platform binary distribution, no native-library version compatibility to worry about.

---

## 7. Cross-comparison quick reference

### 7.1 Integration approach

| Language | Mode | Needs LingoFuse init | Bringing it in | Sync API | Async API |
|------|:----:|:-------------------:|----------|:--------:|:--------:|
| Pascal | B | ✅ | `uses <Unit>_http_json_call_unit;` | ✅ | ✅ |
| Python | A | ❌ | `import <Unit>_http_json_call as api` | ✅ | ✅ |
| C++ | B | ✅ | `#include "<Unit>_http_json_call.hpp"` | ✅ | ✅ |
| C# | B | ✅ | `using <Unit>_http_json_call;` | ✅ | ✅ |
| JavaScript | A | ❌ | `<script src="...">` | ❌ | ✅ |
| Node.js | A | ❌ | `const api = require('./..._node.js')` | ❌ | ✅ |
| TypeScript | A | ❌ | `import * as api from "./..._ts"` | ❌ | ✅ |
| PHP | A | ❌ | `require_once '..._php.php'` | ✅ | ❌ |
| Rust | A | ❌ | `mod api;` / `#[path]` | ✅ | ✅ |
| Go | A | ❌ | `import "..."` / same package | ✅ | ✅ |
| Java | A | ❌ | `import ...HttpJsonClient` | ✅ | ❌ |
| Delphi | A | ❌ | `uses <Unit>_http_json_call_delphi;` | ✅ | ✅ |
| Dart | A | ❌ | `import '..._dart.dart' as api` | ❌ | ✅ |
| Swift | A | ❌ | same target / SPM package | ✅ | ✅ (macOS 12+ / iOS 15+) |
| Ruby | A | ❌ | `require_relative '..._ruby'` | ✅ | ❌ |
| Zig | B | ✅ | `const call = @import("..._zig.zig")` | ✅ | ✅ |
| Erlang | A | ❌ | load `<Unit>_http_json_call.beam` | ✅ | ✅ |
| Fortran | B | ✅ | `use <Unit>_http_json_call_mod` | ✅ | ✅ |
| Julia | B | ✅ | `include("..._jl")` / `using ...` | ✅ | ✅ |
| R | B | ✅ | `source("..._R")` | ✅ | ✅ |

### 7.2 Error types

| Language | Error type | Main fields |
|------|----------|----------|
| Pascal | `EHTTPCallError` | `.Message`, `.Code`, `.HttpStatus` |
| Python | `HTTPCallError` | `.message`, `.code`, `.http_status` |
| C++ | `HTTPCallError` | `.what()`, `.code`, `.http_status` |
| C# | `HTTPCallError` | `.Message`, `.Code`, `.HttpStatus` |
| JavaScript | `LFHttpCallError` | `.message`, `.code`, `.httpStatus` |
| Node.js | `HTTPCallError` | `.message`, `.code`, `.httpStatus` |
| TypeScript | `HttpJsonCallError` | `.message`, `.code`, `.httpStatus` |
| PHP | `HttpJsonCallError` | `.getMessage()`, `.getCode()`, `.httpStatus` |
| Rust | `HttpCallError` | `.message`, `.code`, `.http_status` |
| Go | `HTTPCallError` | `.Message`, `.Code`, `.HTTPStatus` |
| Java | `HTTPCallException` | `.getMessage()`, `.code`, `.httpStatus` |
| Delphi | `EHTTPCallError` | `.Message`, `.Code`, `.HttpStatus` |
| Dart | `HttpCallError` | `.message`, `.code`, `.httpStatus` |
| Swift | `HTTPCallError` | `.message`, `.code`, `.httpStatus` |
| Ruby | `HTTPCallError` | `.message`, `.code`, `.http_status` |
| Zig | `HttpCallError` + `lastError()` | `lastError().code`, `lastError().http_status` |
| Erlang | `{error, Reason}` | `{service_error, Code, Msg}` / `{http_status, Status, Body}` |
| Fortran | zero-value return / `ok` output argument | no exception mechanism |
| Julia | `HTTPCallError` | `.msg`, `.code`, `.http_status` |
| R | `http_call_error` | `e$message`, `e$code`, `e$http_status` |

### 7.3 Configuration entries

| Language | Base URL | Timeout | Debug |
|------|----------|------|-------|
| Pascal | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT_MS` | (none built in) |
| Python | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT` | `DEBUG_LOG` |
| C++ | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | (none built in) |
| C# | `HttpJsonCallConfig.BaseUrl` | `HttpJsonCallConfig.HttpTimeoutSec` | `HttpJsonCallConfig.DebugLog` |
| JavaScript | `<Unit>Api.setBaseUrl(url)` | (none) | (none) |
| Node.js | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT_MS` | `DEBUG_LOG` |
| TypeScript | `HttpJsonCallConfig.baseUrl` | `HttpJsonCallConfig.httpTimeoutMs` | `HttpJsonCallConfig.debugLog` |
| PHP | `HttpJsonCallConfig::$baseUrl` | `HttpJsonCallConfig::$httpTimeoutSec` | `HttpJsonCallConfig::$debugLog` |
| Rust | `set_base_url(&str)` | `set_timeout_secs(u64)` | `set_debug_log(bool)` |
| Go | `HTTPCallBaseURL` | `HTTPCallTimeout` | `DebugLog` |
| Java | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT` | (none built in) |
| Delphi | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT_MS` | (none built in) |
| Dart | `setBaseUrl(url)` / `DEFAULT_BASE_URL` | `HTTP_CALL_TIMEOUT` | `DEBUG_LOG` |
| Swift | `baseUrl` | `timeout` | `debugLog` |
| Ruby | `base_url` (**do not** use `HTTP_CALL_BASE_URL`) | `http_call_timeout` | `debug_log` |
| Zig | `HTTP_CALL_BASE_URL` | `DEFAULT_HTTP_TIMEOUT_SEC` + `BRIDGE_TIMEOUT_MS` | `DEBUG_LOG` |
| Erlang | `set_base_url/1` | `set_timeout/1` | (none built in) |
| Fortran | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` + `HTTP_CALL_TIMEOUT_MS` | (none built in) |
| Julia | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` + `HTTP_CALL_TIMEOUT_MS` | `DEBUG_LOG` |
| R | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` + `HTTP_CALL_TIMEOUT_MS` | `DEBUG_LOG` |

### 7.4 Thread model

| Language | Thread of the synchronous call | Thread of the async callback | Notes |
|------|----------------|----------------|----------|
| Pascal | caller thread (blocking) | worker thread | to update the UI use `TThread.Queue` |
| Python | caller thread (blocking) | the `asyncio` event loop thread | standard `asyncio.run(main())` |
| C++ | caller thread (blocking) | worker thread | do not touch unlocked shared state in the callback |
| C# | caller thread (blocking) | worker thread | use `TaskCompletionSource` |
| JavaScript | none (async only) | microtask queue | standard Promise |
| Node.js | none (async only) | microtask queue | standard Promise |
| TypeScript | none (async only) | microtask queue | standard Promise |
| PHP | caller thread (blocking) | none (sync only) | — |
| Rust | caller thread (blocking) | `tokio` worker | use `#[tokio::main]` |
| Go | caller goroutine (blocking) | a new goroutine (channel) | standard channel pattern |
| Java | caller thread (blocking) | none (sync only) | — |
| Delphi | caller thread (blocking) | worker thread | to update the UI use `TThread.Queue` |
| Dart | none (async only) | microtask queue | standard Future |
| Swift | caller thread (blocking) | `URLSession` callback queue (sync) / concurrent task (async) | `@unchecked Sendable` is the correct annotation |
| Ruby | caller thread (blocking) | none (sync only) | for concurrency use `Thread.new` |
| Zig | caller thread (blocking) | LingoFuse async worker | poll with `std.atomic.Value(bool)` |
| Erlang | caller process (blocking) | a new process (spawn) | standard `receive` |
| Fortran | caller thread (blocking) | LingoFuse async worker | use the `c_funloc` callback |
| Julia | caller Task (blocking) | `Threads.@spawn` | `--threads=2` is mandatory |
| R | caller thread (blocking) | `future` worker | **must** use `future::plan("sequential")` |

---

## 8. Common integration problems

### 8.1 All languages

| Symptom | Cause | Fix |
|------|------|------|
| `Network error` / `Connection refused` | **the bridge program is not running** | start `bridge.py` |
| `code=-3` | the bridge's pre-check cache is stale | add `--no-precheck` to the bridge |
| `code=-4` | bridge protocol error | check the bridge and service versions |
| call timeout | the service side blocks / the bridge blocks | look at the service-side log |
| `int64` precision loss | JS `Number` / PHP int | have the service side return a string |

### 8.2 Mode A specific

| Symptom | Cause | Fix |
|------|------|------|
| `Connection refused` (no LingoFuse needed) | the bridge program is not running | start `bridge.py` |
| CORS error (browser) | the bridge does not return `Access-Control-Allow-Origin` | add `--cors '*'` to the bridge |
| `fetch` does not work under `file://` | the browser's `file://` restriction | serve it with `python3 -m http.server` |

### 8.3 Mode B specific

| Symptom | Cause | Fix |
|------|------|------|
| `LF_LoadLibrary` returns something other than 1 | the LingoFuse native library is missing or the architecture is wrong | copy the correct `LingoFuse64.dll` / `liblingofuse.so` |
| `LF_PrepareClient returned -1` | the endpoint is already taken / invalid | check the endpoint string; kill the old process |
| `LF_PrepareDone returned 0` | it was already called in this process | restart the process |
| `no found app("__lf_http_bridge__")` | the bridge program is not running | start `bridge.py` |
| `no found app("<Unit>")` | the service side is not running | start the service |
| `LF_Async_CallEx failed` | the LingoFuse main loop is not running | check whether `LF_PrepareDone` returned 1 |

### 8.4 Language specific

| Language | Symptom | Cause | Fix |
|------|------|------|------|
| Ruby | `dynamic constant assignment` | assigning to `HTTP_CALL_BASE_URL` | use `Module.base_url = "..."` |
| R | `*_async variants require future::plan('sequential')` | an incompatible future plan | `future::plan(future::sequential)` |
| Julia | `--threads=2 or more required` | single-threaded | add `--threads=2` |
| Julia | `prepare_client returned -1` | the endpoint is already taken | change the endpoint or kill the old process |
| C# | `DllNotFoundException: LingoFuse64` | the DLL was not copied | copy it into the bin directory |
| C# | `Could not load type 'lingofuse.AppHandle'` | the LingoFuse.dll reference is missing | `dotnet add reference` |
| Swift | `HTTPCallError` (the async pass does not run) | macOS below 12 | use only the synchronous pass |
| PHP | `Call to undefined function curl_init()` | the curl extension is not installed | `apt install php-curl`, or `allow_url_fopen=On` |
| Zig | `build.zig` fingerprint mismatch | the fingerprint is stale | replace `.fingerprint` per the error message |
| Erlang | `no such file or directory: lingofuse_nif.dll` | the NIF is missing | copy it to `priv/` |
| Fortran | `undefined reference to 'lf_*'` | `lf_fortran.cpp` was not linked | use `setup_fortran_tests.ps1` |
| Go | `module not found` | `go get` was not run | `go get github.com/PassByYou888/LingoFuse/go` |

### 8.5 Common mistakes in bridge names and endpoint strings

| Wrong form | Correct form |
|----------|----------|
| `Calculator` (endpoint) | `ipc:Calculator_http_json` |
| `ipc:calculator_http_json` (case) | `ipc:Calculator_http_json` (exactly matching `<UnitName>`) |
| `HTTP_CALL_BASE_URL = "http://127.0.0.1:8081"` (App name missing) | `"http://127.0.0.1:8081/Calculator"` |
| `HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/Calculator/"` (trailing slash) | the generated code strips it, but better not to write it |
| `BridgeAppName = ""` (mode B, C++ / C# / Julia etc.) | leaving it empty uses the default `__lf_http_bridge__`; but setting it explicitly is clearer |
| `BridgeApiName = "__lf_http_bridge__"` (wrong) | `"__lf_outbound_post__"` |

---

## Appendix: one-page quick reference

| Language | Mode | Needs native library | Needs init | Sync | Async | Bringing it in |
|------|:----:|:----------:|:---------:|:----:|:----:|----------|
| Pascal | B | ✅ | ✅ | ✅ | ✅ | `uses` |
| Python | A | ❌ | ❌ | ✅ | ✅ | `import` |
| C++ | B | ✅ | ✅ | ✅ | ✅ | `#include` |
| C# | B | ✅ | ✅ | ✅ | ✅ | `using` |
| JavaScript | A | ❌ | ❌ | ❌ | ✅ | `<script src>` |
| Node.js | A | ❌ | ❌ | ❌ | ✅ | `require` |
| TypeScript | A | ❌ | ❌ | ❌ | ✅ | `import` |
| PHP | A | ❌ | ❌ | ✅ | ❌ | `require_once` |
| Rust | A | ❌ | ❌ | ✅ | ✅ | `mod` / `#[path]` |
| Go | A | ❌ | ❌ | ✅ | ✅ | `import` |
| Java | A | ❌ | ❌ | ✅ | ❌ | `import` |
| Delphi | A | ❌ | ❌ | ✅ | ✅ | `uses` |
| Dart | A | ❌ | ❌ | ❌ | ✅ | `import` |
| Swift | A | ❌ | ❌ | ✅ | ✅ | same target / SPM |
| Ruby | A | ❌ | ❌ | ✅ | ❌ | `require_relative` |
| Zig | B | ✅ | ✅ | ✅ | ✅ | `@import` |
| Erlang | A | ❌ | ❌ | ✅ | ✅ | load the `.beam` |
| Fortran | B | ✅ | ✅ | ✅ | ✅ | `use` |
| Julia | B | ✅ | ✅ | ✅ | ✅ | `include` / `using` |
| R | B | ✅ | ✅ | ✅ | ✅ | `source` |

**The bridge program (`bridge.py` / `bridge.exe`) must always be running.** All 20+ Call libraries access the service through it — the only difference is "direct HTTP" (mode A) versus "through the LingoFuse C ABI" (mode B).

**Mode A does not need the LingoFuse native library; mode B does.** That is the decisive factor when choosing a mode.
